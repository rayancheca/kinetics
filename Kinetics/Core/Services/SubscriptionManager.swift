import Foundation
import StoreKit
import Observation

// MARK: - Product IDs

// These must be registered in App Store Connect before going live.
// Using reverse-DNS format matching the bundle ID prefix.
enum KineticsProduct: String, CaseIterable {
    case premiumMonthly = "com.rayancheca.kinetics.premium.monthly"
    case premiumAnnual  = "com.rayancheca.kinetics.premium.annual"
}

// MARK: - SubscriptionManager

@Observable
@MainActor
final class SubscriptionManager {

    static let shared = SubscriptionManager()

    var isPremium: Bool = false
    var products: [Product] = []
    var purchaseError: String?
    var isLoading = false

    /// `true` once the product load has completed and no products came back.
    /// Indicates that App Store Connect hasn't been configured yet — shows a
    /// graceful "Premium Coming Soon" state instead of crashing or hanging.
    var noProductsAvailable: Bool = false

    nonisolated(unsafe) private var transactionListener: Task<Void, Error>?

    init() {
        transactionListener = listenForTransactions()
        Task { await loadProducts() }
        Task { await updateSubscriptionStatus() }
    }

    deinit {
        transactionListener?.cancel()
    }

    // MARK: - Load products

    func loadProducts() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let loaded = try await Product.products(
                for: KineticsProduct.allCases.map(\.rawValue)
            )
            products = loaded
            // Mark as coming-soon if the store returned zero products.
            noProductsAvailable = loaded.isEmpty
        } catch {
            // Network/sandbox error — treat as coming-soon rather than surfacing
            // a cryptic StoreKit error to the user.
            noProductsAvailable = true
            // Don't set purchaseError here; the screen shows a graceful banner.
        }
    }

    // MARK: - Purchase (Product overload)

    @discardableResult
    func purchase(_ product: Product) async -> Bool {
        isLoading = true
        defer { isLoading = false }
        purchaseError = nil

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                await updateSubscriptionStatus()
                await transaction.finish()
                return true
            case .userCancelled:
                return false
            case .pending:
                return false
            @unknown default:
                return false
            }
        } catch {
            purchaseError = error.localizedDescription
            return false
        }
    }

    // MARK: - Purchase (KineticsProduct overload)
    //
    // Called from SubscriptionView when the StoreKit product hasn't loaded yet
    // but the user taps Subscribe anyway. Triggers a reload first, then purchases.

    @discardableResult
    func purchase(_ plan: KineticsProduct) async -> Bool {
        if products.isEmpty {
            await loadProducts()
        }
        guard let product = products.first(where: { $0.id == plan.rawValue }) else {
            purchaseError = "This product isn't available yet. Please try again later."
            return false
        }
        return await purchase(product)
    }

    // MARK: - Restore

    func restorePurchases() async {
        isLoading = true
        defer { isLoading = false }
        do {
            try await AppStore.sync()
            await updateSubscriptionStatus()
        } catch {
            purchaseError = error.localizedDescription
        }
    }

    // MARK: - Status check

    func updateSubscriptionStatus() async {
        var activeSub = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               transaction.productType == .autoRenewable,
               transaction.revocationDate == nil {
                activeSub = true
                break
            }
        }
        isPremium = activeSub
    }

    // MARK: - Transaction listener

    private func listenForTransactions() -> Task<Void, Error> {
        Task.detached { [weak self] in
            for await result in Transaction.updates {
                if case .verified(let transaction) = result {
                    await self?.updateSubscriptionStatus()
                    await transaction.finish()
                }
            }
        }
    }

    // MARK: - Helpers

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw StoreError.failedVerification
        case .verified(let value):
            return value
        }
    }
}

// MARK: - StoreError

enum StoreError: Error {
    case failedVerification
}
