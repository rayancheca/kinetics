import SwiftUI

// MARK: - StrikingOnboardingView

struct StrikingOnboardingView: View {
    let onDismiss: () -> Void
    private let accent = Color.kineticsRed

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
                        Image(systemName: "bolt.circle.fill")
                            .font(.system(size: 56))
                            .foregroundStyle(accent)
                    }
                    .padding(.top, 8)

                    // MARK: Title
                    Text("STRIKING CLINIC")
                        .font(.system(size: 28, weight: .black))
                        .tracking(4)
                        .foregroundStyle(.white)
                        .padding(.top, 16)

                    Text("AI-powered punch and kick analysis")
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
                            icon: "bolt.fill",
                            name: "Strike Velocity",
                            description: "How fast your fist or foot moves at impact. Measured in mph.",
                            benchmarks: "Beginner: 8–15 mph · Intermediate: 15–25 · Elite: 25–35 mph",
                            accent: accent
                        )

                        OnboardingMetricRow(
                            number: 2,
                            icon: "link",
                            name: "Kinematic Chain",
                            description: "Whether your hips fire before your shoulders — the source of real power.",
                            benchmarks: "Score 0–100 · Below 60: arm-punching · Above 80: elite sequencing",
                            accent: accent
                        )

                        OnboardingMetricRow(
                            number: 3,
                            icon: "crop",
                            name: "Hip-Shoulder Separation",
                            description: "The 'coil' — how far your hips open before your shoulders release.",
                            benchmarks: "Below 20°: no coil · 20–35°: developing · 35°+: elite power storage",
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
                            instruction: "Position your phone so your full body is visible — head to feet. Landscape or portrait both work. Step back 6–8 feet from the camera.",
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
