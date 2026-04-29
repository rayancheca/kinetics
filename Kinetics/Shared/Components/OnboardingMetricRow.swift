import SwiftUI

// MARK: - OnboardingMetricRow

struct OnboardingMetricRow: View {
    let number: Int
    let icon: String
    let name: String
    let description: String
    let benchmarks: String
    let accent: Color

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Number badge
            Text("\(number)")
                .font(.system(size: 14, weight: .black))
                .foregroundStyle(accent)
                .frame(width: 28, height: 28)
                .background(accent.opacity(0.15))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(accent)
                    Text(name)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                }
                Text(description)
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.65))
                    .fixedSize(horizontal: false, vertical: true)
                Text(benchmarks)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(accent.opacity(0.8))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(accent.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                    .padding(.top, 2)
            }
        }
        .padding(14)
        .background(Color(red: 0.09, green: 0.09, blue: 0.09))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.white.opacity(0.07), lineWidth: 0.5)
        )
    }
}

// MARK: - OnboardingCameraSetup

struct OnboardingCameraSetup: View {
    let instruction: String
    let requiresLandscape: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "camera.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.kineticsBlue)
                Text("CAMERA SETUP")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(2)
                    .foregroundStyle(.white.opacity(0.4))
            }
            if requiresLandscape {
                Label("LANDSCAPE MODE REQUIRED", systemImage: "rectangle.landscape.rotate")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.kineticsBlue)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 10)
                    .background(Color.kineticsBlue.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 7))
            }
            Text(instruction)
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.6))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(Color(red: 0.07, green: 0.07, blue: 0.07))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.kineticsBlue.opacity(0.2), lineWidth: 0.5)
        )
    }
}
