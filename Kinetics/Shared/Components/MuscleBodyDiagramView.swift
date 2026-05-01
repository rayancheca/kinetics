import SwiftUI

// MARK: - MuscleBodyDiagramView
//
// Visual muscle-group diagram. Shows a simplified anterior/posterior body
// silhouette with primary and secondary muscles highlighted using their
// canonical accent colours from `GymMuscleGroup`.

struct MuscleBodyDiagramView: View {

    let primaryMuscles: [GymMuscleGroup]
    let secondaryMuscles: [GymMuscleGroup]

    var body: some View {
        VStack(spacing: 12) {
            // Primary muscles
            if !primaryMuscles.isEmpty {
                muscleRow(title: "Primary", muscles: primaryMuscles, opacity: 1.0)
            }
            // Secondary muscles
            if !secondaryMuscles.isEmpty {
                muscleRow(title: "Secondary", muscles: secondaryMuscles, opacity: 0.55)
            }
            // Empty state
            if primaryMuscles.isEmpty && secondaryMuscles.isEmpty {
                Text("No muscle data available")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.kineticsSubtext)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
            }
        }
        .padding(.horizontal, 4)
    }

    private func muscleRow(title: String, muscles: [GymMuscleGroup], opacity: Double) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .tracking(1.2)
                .foregroundStyle(Color.kineticsSubtext)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(muscles, id: \.rawValue) { group in
                        HStack(spacing: 6) {
                            Circle()
                                .fill(group.color.opacity(opacity))
                                .frame(width: 10, height: 10)
                            Text(group.rawValue)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.white.opacity(0.85))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(group.color.opacity(opacity * 0.15))
                                .overlay(
                                    Capsule()
                                        .strokeBorder(group.color.opacity(opacity * 0.35), lineWidth: 1)
                                )
                        )
                    }
                }
                .padding(.horizontal, 2)
            }
        }
    }
}
