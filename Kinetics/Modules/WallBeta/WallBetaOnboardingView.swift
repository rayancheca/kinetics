import SwiftUI

// MARK: - WallBetaOnboardingView

struct WallBetaOnboardingView: View {
    let onDismiss: () -> Void
    private let accent = Color.kineticsGreen

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
                        Image(systemName: "figure.climbing")
                            .font(.system(size: 56))
                            .foregroundStyle(accent)
                    }
                    .padding(.top, 8)

                    // MARK: Title
                    Text("WALL BETA")
                        .font(.system(size: 28, weight: .black))
                        .tracking(4)
                        .foregroundStyle(.white)
                        .padding(.top, 16)

                    Text("Hip position, tension, and dyno analysis")
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
                            icon: "arrow.up.to.line.compact",
                            name: "Hip Proximity",
                            description: "How close your hips are to the wall — closer means weight on feet, not arms.",
                            benchmarks: "<50%: sagging off · 50–75%: developing · 75%+: solid technique",
                            accent: accent
                        )

                        OnboardingMetricRow(
                            number: 2,
                            icon: "arrow.down.circle",
                            name: "Hip Sag Detection",
                            description: "Moments when your hips drop and pull you off the wall.",
                            benchmarks: "0 events: perfect · 1–2: minor · 3+: core activation needed",
                            accent: accent
                        )

                        OnboardingMetricRow(
                            number: 3,
                            icon: "waveform.path",
                            name: "Dyno Arc",
                            description: "The trajectory of your body during explosive dynamic moves.",
                            benchmarks: "Smooth arc = controlled · Jagged = wasted energy",
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
                            instruction: "Set your phone on a ledge or table directly facing the wall, 6–10 feet back. Full body must be visible — top of head to feet.",
                            requiresLandscape: false
                        )
                    }
                    .padding(.horizontal, 20)

                    // MARK: CTA
                    // kineticsGreen is a bright neon — use kineticsDark for readable label text
                    Button { onDismiss() } label: {
                        Text("Start Climbing →")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(Color.kineticsDark)
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
