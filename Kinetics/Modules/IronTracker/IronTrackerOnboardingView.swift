import SwiftUI

// MARK: - IronTrackerOnboardingView

struct IronTrackerOnboardingView: View {
    let onDismiss: () -> Void
    private let accent = Color.kineticsBlue

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
                        Image(systemName: "dumbbell.fill")
                            .font(.system(size: 56))
                            .foregroundStyle(accent)
                    }
                    .padding(.top, 8)

                    // MARK: Title
                    Text("IRON TRACKER")
                        .font(.system(size: 28, weight: .black))
                        .tracking(4)
                        .foregroundStyle(.white)
                        .padding(.top, 16)

                    Text("Bar path, VBT, and symmetry analysis")
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
                            icon: "chart.line.uptrend.xyaxis",
                            name: "Bar Path",
                            description: "The exact trajectory your barbell follows through each rep, traced in real time on screen.",
                            benchmarks: "<2cm deviation: elite · 2–5cm: good · >5cm: technique breakdown",
                            accent: accent
                        )

                        OnboardingMetricRow(
                            number: 2,
                            icon: "gauge.high",
                            name: "VBT Speed",
                            description: "Bar velocity in meters per second — the real measure of power output.",
                            benchmarks: ">1.0 m/s: speed zone · 0.6–1.0: power · <0.6: strength/grind",
                            accent: accent
                        )

                        OnboardingMetricRow(
                            number: 3,
                            icon: "scale.3d",
                            name: "Bilateral Symmetry",
                            description: "How evenly your left and right sides work during pressing movements.",
                            benchmarks: "100%: balanced · Below 85%: imbalance · Below 70%: injury risk",
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
                            instruction: "LANDSCAPE MODE — this module locks to landscape. Mount your phone at hip height on a tripod, 4–6 feet to the side. You should see the full range of motion.",
                            requiresLandscape: true
                        )
                    }
                    .padding(.horizontal, 20)

                    // MARK: CTA
                    Button { onDismiss() } label: {
                        Text("Start Tracking →")
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
