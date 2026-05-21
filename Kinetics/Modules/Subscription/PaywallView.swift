import StoreKit
import SwiftUI

// MARK: - PaywallView

/// Contextual paywall sheet surfaced when a user tries to access a premium feature.
///
/// - Displays a header that names the locked feature.
/// - Lists exactly what's included in Kinetics Pro.
/// - Calls `SubscriptionManager.purchase(_:)` on the CTA tap.
/// - Dismisses automatically after a successful purchase.
///
/// Usage:
/// ```swift
/// .sheet(isPresented: $showPaywall) {
///     PaywallView(lockedFeature: "AI Coach Report")
/// }
/// ```
struct PaywallView: View {

    // MARK: - Inputs

    /// Short name of the feature that triggered this paywall (e.g. "AI Coach Report").
    let lockedFeature: String

    // MARK: - Environment

    @Environment(\.dismiss) private var dismiss

    // MARK: - State

    @State private var manager = SubscriptionManager.shared
    @State private var selectedPlan: KineticsProduct = .premiumAnnual

    // MARK: - Body

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // Subtle purple ambient glow
            Color.kineticsPurple
                .opacity(0.06)
                .blur(radius: 120)
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    // Drag indicator
                    Capsule()
                        .fill(.white.opacity(0.2))
                        .frame(width: 36, height: 4)
                        .padding(.top, 12)
                        .padding(.bottom, 24)

                    lockedBadge
                        .padding(.bottom, 28)

                    featureList
                        .padding(.horizontal, 24)
                        .padding(.bottom, 28)

                    if manager.products.isEmpty && !manager.isLoading {
                        comingSoonCard
                            .padding(.horizontal, 24)
                            .padding(.bottom, 24)
                    } else {
                        planToggle
                            .padding(.horizontal, 24)
                            .padding(.bottom, 20)

                        ctaButton
                            .padding(.horizontal, 24)
                            .padding(.bottom, 14)
                    }

                    restoreButton
                        .padding(.bottom, 16)

                    dismissButton
                        .padding(.bottom, 40)
                }
            }

            if manager.isLoading {
                loadingOverlay
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
        .alert("Purchase Error", isPresented: .constant(manager.purchaseError != nil)) {
            Button("OK") { manager.purchaseError = nil }
        } message: {
            Text(manager.purchaseError ?? "")
        }
        // Auto-dismiss when the purchase completes in the background.
        .onChange(of: manager.isPremium) { _, isPremium in
            if isPremium { dismiss() }
        }
    }

    // MARK: - Locked Feature Badge

    private var lockedBadge: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.kineticsAmber.opacity(0.10))
                    .frame(width: 88, height: 88)
                Circle()
                    .fill(Color.kineticsAmber.opacity(0.05))
                    .frame(width: 118, height: 118)
                Image(systemName: "lock.fill")
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundStyle(Color.kineticsAmber)
            }

            VStack(spacing: 6) {
                Text("\(lockedFeature)")
                    .font(.system(size: 22, weight: .black))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                Text("This feature requires Kinetics Pro.")
                    .font(.system(size: 14, design: .rounded))
                    .foregroundStyle(.white.opacity(0.45))
                    .multilineTextAlignment(.center)
            }
        }
    }

    // MARK: - Feature List

    private let features: [(icon: String, text: String, color: Color)] = [
        ("brain.head.profile",   "AI-powered form breakdown after every set",  Color(red: 0.545, green: 0.361, blue: 0.965)),
        ("chart.xyaxis.line",    "Advanced biomechanics charts & analytics",   Color(red: 0, green: 0.76, blue: 1)),
        ("bolt.fill",            "Unlimited live coaching sessions",            Color(red: 0.224, green: 0.906, blue: 0.439)),
        ("figure.run",           "Strava route discovery & sync",               Color(red: 0.98, green: 0.38, blue: 0.16)),
        ("trophy.fill",          "Session history, PRs & streak tracking",      Color(red: 1, green: 0.722, blue: 0)),
        ("icloud.fill",          "Cross-device sync via iCloud",                Color(red: 0, green: 0.76, blue: 1)),
    ]

    private var featureList: some View {
        VStack(spacing: 10) {
            ForEach(features, id: \.text) { feature in
                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(feature.color.opacity(0.14))
                            .frame(width: 34, height: 34)
                        Image(systemName: feature.icon)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(feature.color)
                    }
                    Text(feature.text)
                        .font(.system(size: 14, design: .rounded))
                        .foregroundStyle(.white.opacity(0.82))
                    Spacer()
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.kineticsGreen)
                }
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(red: 0.075, green: 0.075, blue: 0.075))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(.white.opacity(0.07), lineWidth: 1)
                )
        )
    }

    // MARK: - Plan Toggle

    private var planToggle: some View {
        HStack(spacing: 10) {
            planCard(
                plan: .premiumMonthly,
                title: "Monthly",
                price: priceString(for: .premiumMonthly) ?? "$4.99",
                period: "/month",
                badge: nil
            )
            planCard(
                plan: .premiumAnnual,
                title: "Annual",
                price: priceString(for: .premiumAnnual) ?? "$39.99",
                period: "/year",
                badge: "Save 33%"
            )
        }
    }

    private func planCard(
        plan: KineticsProduct,
        title: String,
        price: String,
        period: String,
        badge: String?
    ) -> some View {
        let isSelected = selectedPlan == plan
        return Button {
            withAnimation(.spring(duration: 0.28, bounce: 0.2)) { selectedPlan = plan }
        } label: {
            ZStack(alignment: .top) {
                VStack(spacing: 6) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(isSelected ? .white : .white.opacity(0.45))
                    Text(price)
                        .font(.system(size: 20, weight: .black, design: .rounded))
                        .foregroundStyle(isSelected ? Color.kineticsAmber : .white.opacity(0.45))
                    Text(period)
                        .font(.system(size: 11))
                        .foregroundStyle(isSelected ? .white.opacity(0.55) : .white.opacity(0.28))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(isSelected
                              ? Color.kineticsAmber.opacity(0.08)
                              : Color(red: 0.075, green: 0.075, blue: 0.075)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(
                                    isSelected ? Color.kineticsAmber.opacity(0.55) : .white.opacity(0.08),
                                    lineWidth: isSelected ? 1.5 : 1
                                )
                        )
                )

                if let badge {
                    Text(badge)
                        .font(.system(size: 9, weight: .bold))
                        .tracking(0.4)
                        .foregroundStyle(.black)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 3)
                        .background(Color.kineticsAmber)
                        .clipShape(Capsule())
                        .offset(y: -11)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - CTA Button

    private var ctaButton: some View {
        Button {
            guard let product = manager.products.first(where: { $0.id == selectedPlan.rawValue }) else {
                return
            }
            Task { await manager.purchase(product) }
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.kineticsAmber, Color(red: 1, green: 0.55, blue: 0)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(height: 54)

                VStack(spacing: 2) {
                    Text("Unlock Premium")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(.black)
                    Text("3 days free, then \(selectedPlanPrice)")
                        .font(.system(size: 11))
                        .foregroundStyle(.black.opacity(0.55))
                }
            }
        }
        .disabled(manager.isLoading)
        .buttonStyle(.plain)
    }

    // MARK: - Coming Soon (no StoreKit products loaded)

    private var comingSoonCard: some View {
        VStack(spacing: 12) {
            Image(systemName: "clock.badge.checkmark.fill")
                .font(.system(size: 30))
                .foregroundStyle(Color.kineticsAmber)
            Text("Premium Coming Soon")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
            Text("In-App Purchases are being set up. All Pro features will be available at launch.")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.42))
                .multilineTextAlignment(.center)
                .lineSpacing(2)
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(red: 0.075, green: 0.075, blue: 0.075))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.kineticsAmber.opacity(0.18), lineWidth: 1)
                )
        )
    }

    // MARK: - Restore / Dismiss

    private var restoreButton: some View {
        Button {
            Task { await manager.restorePurchases() }
        } label: {
            Text("Restore Purchases")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.32))
                .underline()
        }
    }

    private var dismissButton: some View {
        Button {
            dismiss()
        } label: {
            Text("Not now")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.22))
        }
    }

    // MARK: - Loading Overlay

    private var loadingOverlay: some View {
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea()
            ProgressView()
                .tint(Color.kineticsAmber)
                .scaleEffect(1.4)
        }
    }

    // MARK: - Helpers

    private var selectedPlanPrice: String {
        switch selectedPlan {
        case .premiumMonthly:
            return priceString(for: .premiumMonthly).map { "\($0)/mo" } ?? "$4.99/mo"
        case .premiumAnnual:
            return priceString(for: .premiumAnnual).map { "\($0)/yr" } ?? "$39.99/yr"
        }
    }

    private func priceString(for plan: KineticsProduct) -> String? {
        manager.products.first(where: { $0.id == plan.rawValue })?.displayPrice
    }
}
