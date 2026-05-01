import SwiftUI
import StoreKit

// MARK: - SubscriptionView

struct SubscriptionView: View {

    @State private var manager = SubscriptionManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var selectedPlan: KineticsProduct = .premiumAnnual

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // Ambient glow
            Color(red: 0, green: 0.76, blue: 1)
                .opacity(0.05)
                .blur(radius: 100)
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    heroSection
                        .padding(.top, 52)
                        .padding(.bottom, 36)

                    featureList
                        .padding(.horizontal, 24)
                        .padding(.bottom, 32)

                    if manager.products.isEmpty && !manager.isLoading {
                        comingSoonCard
                            .padding(.horizontal, 24)
                            .padding(.bottom, 32)
                    } else {
                        planToggle
                            .padding(.horizontal, 24)
                            .padding(.bottom, 24)

                        ctaButton
                            .padding(.horizontal, 24)
                            .padding(.bottom, 16)
                    }

                    restoreButton
                        .padding(.bottom, 20)

                    legalFooter
                        .padding(.horizontal, 24)
                        .padding(.bottom, 52)
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

    // MARK: - Hero

    private var heroSection: some View {
        VStack(spacing: 14) {
            // Badge
            ZStack {
                Circle()
                    .fill(Color.kineticsAmber.opacity(0.12))
                    .frame(width: 96, height: 96)
                Circle()
                    .fill(Color.kineticsAmber.opacity(0.06))
                    .frame(width: 130, height: 130)
                Image(systemName: "crown.fill")
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundStyle(Color.kineticsAmber)
            }

            // Title
            VStack(spacing: 6) {
                HStack(spacing: 8) {
                    Text("KINETICS")
                        .font(.system(size: 28, weight: .black))
                        .foregroundStyle(.white)
                    Text("PRO")
                        .font(.system(size: 20, weight: .black))
                        .foregroundStyle(Color.kineticsAmber)
                }

                Text("Unlock your full athletic potential")
                    .font(.system(size: 15, design: .rounded))
                    .foregroundStyle(.white.opacity(0.5))
                    .multilineTextAlignment(.center)
            }
        }
    }

    // MARK: - Feature List

    private let features: [(icon: String, text: String, color: Color)] = [
        ("bolt.fill", "Unlimited live coaching sessions", Color(red: 0, green: 0.76, blue: 1)),
        ("chart.xyaxis.line", "Advanced biomechanics analytics & graphs", Color(red: 0.224, green: 0.906, blue: 0.439)),
        ("brain.head.profile", "AI-powered form breakdown after every set", Color(red: 0.545, green: 0.361, blue: 0.965)),
        ("trophy.fill", "Session history, PRs, and streak tracking", Color(red: 1, green: 0.722, blue: 0)),
        ("icloud.fill", "Cross-device sync via iCloud", Color(red: 0, green: 0.76, blue: 1)),
    ]

    private var featureList: some View {
        VStack(spacing: 12) {
            ForEach(features, id: \.text) { feature in
                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(feature.color.opacity(0.15))
                            .frame(width: 36, height: 36)
                        Image(systemName: feature.icon)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(feature.color)
                    }
                    Text(feature.text)
                        .font(.system(size: 15, design: .rounded))
                        .foregroundStyle(.white.opacity(0.85))
                    Spacer()
                }
            }
        }
        .padding(20)
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
        VStack(spacing: 12) {
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

            if selectedPlan == .premiumAnnual {
                Text("That's just \(annualMonthlyEquivalent)/month, billed annually")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.38))
            }
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
            withAnimation(.spring(duration: 0.3, bounce: 0.2)) {
                selectedPlan = plan
            }
        } label: {
            ZStack(alignment: .top) {
                VStack(spacing: 6) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(isSelected ? .white : .white.opacity(0.5))

                    Text(price)
                        .font(.system(size: 22, weight: .black, design: .rounded))
                        .foregroundStyle(isSelected ? Color(red: 0, green: 0.76, blue: 1) : .white.opacity(0.5))

                    Text(period)
                        .font(.system(size: 11))
                        .foregroundStyle(isSelected ? .white.opacity(0.55) : .white.opacity(0.3))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(isSelected
                            ? Color(red: 0, green: 0.76, blue: 1).opacity(0.1)
                            : Color(red: 0.075, green: 0.075, blue: 0.075)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(
                                    isSelected
                                        ? Color(red: 0, green: 0.76, blue: 1).opacity(0.6)
                                        : .white.opacity(0.08),
                                    lineWidth: isSelected ? 1.5 : 1
                                )
                        )
                )

                if let badge {
                    Text(badge)
                        .font(.system(size: 10, weight: .bold))
                        .tracking(0.5)
                        .foregroundStyle(.black)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.kineticsAmber)
                        .clipShape(Capsule())
                        .offset(y: -12)
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
                            colors: [
                                Color(red: 0, green: 0.76, blue: 1),
                                Color(red: 0, green: 0.55, blue: 0.88),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(height: 56)

                VStack(spacing: 2) {
                    Text("Start Free Trial")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(.black)
                    Text("3 days free, then \(selectedPlanPrice)")
                        .font(.system(size: 11))
                        .foregroundStyle(.black.opacity(0.55))
                }
            }
        }
        .disabled(manager.isLoading)
    }

    // MARK: - Restore

    private var restoreButton: some View {
        Button {
            Task { await manager.restorePurchases() }
        } label: {
            Text("Restore Purchases")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.35))
                .underline()
        }
    }

    // MARK: - Coming Soon (no products loaded)

    private var comingSoonCard: some View {
        VStack(spacing: 14) {
            Image(systemName: "clock.badge.checkmark.fill")
                .font(.system(size: 36))
                .foregroundStyle(Color.kineticsAmber)

            Text("Premium Coming Soon")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.white)

            Text("We're still setting up In-App Purchases. Check back shortly — all Pro features will be available at launch.")
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.45))
                .multilineTextAlignment(.center)
                .lineSpacing(3)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(red: 0.075, green: 0.075, blue: 0.075))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.kineticsAmber.opacity(0.2), lineWidth: 1)
                )
        )
    }

    // MARK: - Legal Footer

    private var legalFooter: some View {
        VStack(spacing: 8) {
            Text("Payment will be charged to your Apple ID account at confirmation of purchase. Subscription automatically renews unless auto-renew is turned off at least 24 hours before the end of the current period.")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.22))
                .multilineTextAlignment(.center)
                .lineSpacing(3)

            HStack(spacing: 16) {
                Link("Terms of Use", destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.3))
                Text("·")
                    .foregroundStyle(.white.opacity(0.2))
                Link("Privacy Policy", destination: URL(string: "https://kinetics.app/privacy")!)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.3))
            }
        }
    }

    // MARK: - Loading Overlay

    private var loadingOverlay: some View {
        ZStack {
            Color.black.opacity(0.65).ignoresSafeArea()
            ProgressView()
                .tint(Color(red: 0, green: 0.76, blue: 1))
                .scaleEffect(1.4)
        }
    }

    // MARK: - Helpers

    private var selectedPlanPrice: String {
        switch selectedPlan {
        case .premiumMonthly:
            return priceString(for: .premiumMonthly).map { "\($0)/month" } ?? "$4.99/month"
        case .premiumAnnual:
            return priceString(for: .premiumAnnual).map { "\($0)/year" } ?? "$39.99/year"
        }
    }

    private var annualMonthlyEquivalent: String {
        guard let product = manager.products.first(where: { $0.id == KineticsProduct.premiumAnnual.rawValue }),
              let price = product.price as Decimal? else {
            return "$3.33"
        }
        let monthly = price / 12
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = Locale.current
        return formatter.string(from: NSDecimalNumber(decimal: monthly)) ?? "$3.33"
    }

    private func priceString(for plan: KineticsProduct) -> String? {
        manager.products.first(where: { $0.id == plan.rawValue })?.displayPrice
    }
}

// MARK: - ProductCard (legacy — kept if referenced elsewhere)

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
