import SwiftUI
import StoreKit

// MARK: - SubscriptionView

struct SubscriptionView: View {

    @State private var manager = SubscriptionManager.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.kineticsBackground.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    headerSection
                        .padding(.top, 48)
                        .padding(.bottom, 40)

                    productCards
                        .padding(.horizontal, 20)

                    restoreButton
                        .padding(.top, 28)
                        .padding(.bottom, 48)
                }
            }

            if manager.isLoading {
                loadingOverlay
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Purchase Error", isPresented: .constant(manager.purchaseError != nil)) {
            Button("OK") { manager.purchaseError = nil }
        } message: {
            Text(manager.purchaseError ?? "")
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.kineticsBlue.opacity(0.15))
                    .frame(width: 80, height: 80)
                Image(systemName: "star.fill")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(Color.kineticsAmber)
            }

            Text("GO PREMIUM")
                .font(.system(size: 34, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .tracking(1)

            Text("Unlock advanced analytics and\nad-free experience")
                .font(.system(size: 15))
                .foregroundStyle(.white.opacity(0.55))
                .multilineTextAlignment(.center)
                .lineSpacing(3)
        }
    }

    // MARK: - Product Cards

    private var productCards: some View {
        VStack(spacing: 14) {
            if manager.products.isEmpty {
                // Skeleton placeholders while products load
                ForEach(0..<2, id: \.self) { _ in
                    ProductCardSkeleton()
                }
            } else {
                let sorted = manager.products.sorted { lhs, rhs in
                    // Annual first
                    lhs.id == KineticsProduct.premiumAnnual.rawValue
                }
                ForEach(sorted, id: \.id) { product in
                    ProductCard(
                        product: product,
                        isMostPopular: product.id == KineticsProduct.premiumAnnual.rawValue
                    ) {
                        Task { await manager.purchase(product) }
                    }
                }
            }
        }
    }

    // MARK: - Restore

    private var restoreButton: some View {
        Button {
            Task { await manager.restorePurchases() }
        } label: {
            Text("Restore Purchases")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.38))
                .underline()
        }
    }

    // MARK: - Loading Overlay

    private var loadingOverlay: some View {
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea()
            ProgressView()
                .tint(Color.kineticsBlue)
                .scaleEffect(1.4)
        }
    }
}

// MARK: - ProductCard

private struct ProductCard: View {

    let product: Product
    let isMostPopular: Bool
    let onTap: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Image(systemName: iconName)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Color.kineticsBlue)
                        .frame(width: 36)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(product.displayName)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)
                        Text(product.description)
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.45))
                            .lineLimit(2)
                    }

                    Spacer()

                    Text(product.displayPrice)
                        .font(.system(size: 20, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                }

                Button(action: onTap) {
                    Text("Subscribe")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Color.kineticsDark)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(Color.kineticsBlue)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
            .padding(18)
            .background(Color.kineticsDark)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(
                        isMostPopular ? Color.kineticsBlue.opacity(0.55) : Color.white.opacity(0.06),
                        lineWidth: isMostPopular ? 1.5 : 1
                    )
            )

            if isMostPopular {
                mostPopularBadge
                    .padding(.top, -10)
                    .padding(.trailing, 16)
            }
        }
    }

    private var mostPopularBadge: some View {
        Text("Most Popular")
            .font(.system(size: 10, weight: .bold))
            .tracking(0.8)
            .foregroundStyle(Color.kineticsDark)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.kineticsAmber)
            .clipShape(Capsule())
    }

    private var iconName: String {
        product.id == KineticsProduct.premiumAnnual.rawValue
            ? "calendar.badge.checkmark"
            : "repeat.circle.fill"
    }
}

// MARK: - ProductCardSkeleton

private struct ProductCardSkeleton: View {
    @State private var shimmer = false

    var body: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(Color.kineticsDark)
            .frame(height: 110)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.06), lineWidth: 1)
            )
            .opacity(shimmer ? 0.5 : 0.9)
            .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: shimmer)
            .onAppear { shimmer = true }
    }
}
