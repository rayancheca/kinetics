import FirebaseCore
import SwiftUI
import UIKit

// MARK: - ShareCardView

struct ShareCardView: View {
    let exerciseName: String
    let weight: Double
    let reps: Int
    let achievedAt: Date

    var body: some View {
        ZStack {
            // Background
            LinearGradient(
                colors: [Color(red: 0.05, green: 0.05, blue: 0.08), Color(red: 0.1, green: 0.08, blue: 0.15)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(spacing: 0) {
                // Header
                HStack {
                    Image(systemName: "bolt.fill")
                        .foregroundStyle(Color.kineticsBlue)
                    Text("KINETICS")
                        .font(.system(size: 13, weight: .black, design: .rounded))
                        .tracking(3)
                        .foregroundStyle(Color.kineticsBlue)
                    Spacer()
                    Text("PERSONAL RECORD")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(2)
                        .foregroundStyle(Color.kineticsAmber)
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)

                Spacer()

                // Trophy
                Image(systemName: "trophy.fill")
                    .font(.system(size: 52, weight: .bold))
                    .foregroundStyle(Color.kineticsAmber)

                Spacer().frame(height: 16)

                // Exercise name
                Text(exerciseName.uppercased())
                    .font(.system(size: 18, weight: .black, design: .rounded))
                    .tracking(2)
                    .foregroundStyle(.white.opacity(0.7))

                Spacer().frame(height: 8)

                // Weight
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(weightFormatted)
                        .font(.system(size: 72, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .monospacedDigit()
                    Text("kg")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(.white.opacity(0.6))
                }

                Text("\(reps) reps")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.kineticsSubtext)

                Spacer()

                // Date
                Text(achievedAt, format: .dateTime.day().month(.wide).year())
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.kineticsSubtext)
                    .padding(.bottom, 24)
            }
        }
        .frame(width: 390, height: 390)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var weightFormatted: String {
        weight.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", weight)
            : String(format: "%.1f", weight)
    }
}

// MARK: - ShareCardGenerator

@MainActor
enum ShareCardGenerator {
    static func image(for record: PersonalRecord) -> UIImage {
        let view = ShareCardView(
            exerciseName: record.exerciseName,
            weight: record.weight,
            reps: record.reps,
            achievedAt: record.achievedAt
        )
        let renderer = ImageRenderer(content: view)
        renderer.scale = 3.0
        return renderer.uiImage ?? UIImage()
    }

    static func share(record: PersonalRecord, from viewController: UIViewController? = nil) {
        let image = image(for: record)
        let text = "New PR: \(record.exerciseName) — \(record.weight)kg × \(record.reps) reps 💪"
        let items: [Any] = [image, text]
        let activityVC = UIActivityViewController(activityItems: items, applicationActivities: nil)

        let presenter = viewController
            ?? UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap { $0.windows }
                .first { $0.isKeyWindow }?
                .rootViewController

        presenter?.present(activityVC, animated: true)
    }
}
