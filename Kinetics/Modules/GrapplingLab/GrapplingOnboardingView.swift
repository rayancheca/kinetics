import SwiftUI

// MARK: - GrapplingOnboardingView

struct GrapplingOnboardingView: View {
    let onDismiss: () -> Void
    private let accent = Color.kineticsOrange

    var body: some View {
        ZStack {
            Color.kineticsBackground.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    // MARK: Close button
                    HStack {
                        Spacer()
                        Button { onDismiss() } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 26))
                                .foregroundStyle(.white.opacity(0.3))
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)

                    // MARK: Hero icon
                    ZStack {
                        Circle()
                            .fill(accent.opacity(0.15))
                            .frame(width: 90, height: 90)
                            .blur(radius: 20)
                        Image(systemName: "person.2.fill")
                            .font(.system(size: 56))
                            .foregroundStyle(accent)
                    }
                    .padding(.top, 8)

                    // MARK: Title
                    Text("GRAPPLING LAB")
                        .font(.system(size: 28, weight: .black))
                        .tracking(4)
                        .foregroundStyle(.white)
                        .padding(.top, 16)

                    Text("Leverage, base, and balance analysis")
                        .font(.system(size: 15))
                        .foregroundStyle(.white.opacity(0.5))
                        .multilineTextAlignment(.center)
                        .padding(.top, 6)

                    // MARK: Metrics
                    VStack(spacing: 10) {
                        HStack {
                            Text("WHAT WE MEASURE")
                                .font(.system(size: 10, weight: .semibold))
                                .tracking(2.5)
                                .foregroundStyle(.white.opacity(0.35))
                            Spacer()
                        }
                        .padding(.top, 28)

                        OnboardingMetricRow(
                            number: 1,
                            icon: "scope",
                            name: "Center of Mass",
                            description: "Where your body weight is concentrated, projected onto the floor. The dot must stay inside your base.",
                            benchmarks: "Dot exits base = sweep risk · Inside base = stable",
                            accent: accent
                        )

                        OnboardingMetricRow(
                            number: 2,
                            icon: "hand.raised.fill",
                            name: "Kuzushi Index",
                            description: "Your ability to control your opponent's balance and posture position.",
                            benchmarks: "Score 0–100 · Above 70: dominant · Below 40: reactive",
                            accent: accent
                        )

                        OnboardingMetricRow(
                            number: 3,
                            icon: "shield.fill",
                            name: "Base Stability",
                            description: "How solid your support platform is — feet and knees on the floor.",
                            benchmarks: "Below 50%: frequently off-balance · Above 80%: elite base",
                            accent: accent
                        )
                    }
                    .padding(.horizontal, 20)

                    // MARK: Camera setup
                    VStack(alignment: .leading, spacing: 0) {
                        HStack {
                            Text("SETUP")
                                .font(.system(size: 10, weight: .semibold))
                                .tracking(2.5)
                                .foregroundStyle(.white.opacity(0.35))
                            Spacer()
                        }
                        .padding(.top, 24)
                        .padding(.bottom, 10)

                        OnboardingCameraSetup(
                            instruction: "Mount your phone to the side at hip height or prop it on a bag. Make sure your full body is visible. A training partner can hold the phone.",
                            requiresLandscape: false
                        )
                    }
                    .padding(.horizontal, 20)

                    // MARK: CTA
                    Button { onDismiss() } label: {
                        Text("Start Training →")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 54)
                            .background(accent)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 28)
                    .padding(.bottom, 40)
                }
            }
        }
    }
}
