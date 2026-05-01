import SwiftUI

// MARK: - GymWorkoutDetailView

/// Full breakdown of a completed `WorkoutSession`.
/// Pushed from `GymWorkoutHistoryView` via `NavigationStack`.
@MainActor
struct GymWorkoutDetailView: View {

    // MARK: Properties

    let session: WorkoutSession
    let userId: String
    /// Called after the user confirms deletion so the parent list can remove the row.
    let onDelete: (WorkoutSession) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var showDeleteConfirm = false
    @State private var personalRecords: [PersonalRecord] = []

    // MARK: - Computed

    private var dateText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d, yyyy"
        return formatter.string(from: session.startedAt)
    }

    private var durationText: String {
        let start = session.startedAt
        let end = session.endedAt ?? Date()
        let minutes = max(0, Int(end.timeIntervalSince(start)) / 60)
        if minutes < 60 { return "\(minutes) min" }
        let h = minutes / 60
        let m = minutes % 60
        return m > 0 ? "\(h)h \(m)m" : "\(h)h"
    }

    private var totalVolumeKg: Double {
        session.entries
            .flatMap(\.sets)
            .filter(\.isCompleted)
            .reduce(0) { $0 + ($1.weight * Double($1.reps)) }
    }

    private var formattedVolume: String {
        let kg = totalVolumeKg
        if kg == 0 { return "0 kg" }
        let formatted = kg.truncatingRemainder(dividingBy: 1) == 0
            ? "\(Int(kg)) kg"
            : String(format: "%.1f kg", kg)
        return formatted
    }

    private var completedSetsCount: Int {
        session.entries.flatMap(\.sets).filter(\.isCompleted).count
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    headerCard
                    statsRow
                    exerciseBreakdown
                    if !session.notes.isEmpty { notesSection }
                    deleteButton
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 40)
            }
        }
        .navigationTitle(dateText)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.black, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task { loadPersonalRecords() }
        .confirmationDialog(
            "Delete this workout?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                do {
                    try GymRepository.shared.deleteSession(session)
                    onDelete(session)
                    dismiss()
                } catch {
                    // Deletion error is non-fatal — just dismiss
                    dismiss()
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This action cannot be undone.")
        }
    }

    // MARK: - Header Card

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.kineticsBlue.opacity(0.13))
                        .frame(width: 48, height: 48)
                    Image(systemName: "figure.strengthtraining.traditional")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(Color.kineticsBlue)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("Workout")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)

                    Text(dateText)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(Color.kineticsSubtext)
                }

                Spacer()

                if session.isCompleted {
                    Text("Completed")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.kineticsGreen)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            Capsule()
                                .fill(Color.kineticsGreen.opacity(0.14))
                        )
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(white: 0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
                )
        )
    }

    // MARK: - Stats Row

    private var statsRow: some View {
        HStack(spacing: 12) {
            DetailStatCell(value: durationText, label: "Duration", color: Color.kineticsBlue)
            DetailStatCell(value: formattedVolume, label: "Total Volume", color: Color.kineticsGreen)
            DetailStatCell(value: "\(completedSetsCount)", label: "Sets Done", color: Color.kineticsAmber)
        }
    }

    // MARK: - Exercise Breakdown

    private var exerciseBreakdown: some View {
        VStack(alignment: .leading, spacing: 12) {
            DetailSectionHeader(title: "Exercises")

            VStack(spacing: 10) {
                ForEach(
                    session.entries.sorted { $0.orderIndex < $1.orderIndex },
                    id: \.id
                ) { entry in
                    ExerciseBreakdownCard(
                        entry: entry,
                        personalRecords: personalRecords
                    )
                }
            }
        }
    }

    // MARK: - Notes Section

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            DetailSectionHeader(title: "Notes")

            Text(session.notes)
                .font(.system(size: 14))
                .foregroundStyle(Color.kineticsSubtext)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(white: 0.08))
                )
        }
    }

    // MARK: - Delete Button

    private var deleteButton: some View {
        Button {
            showDeleteConfirm = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "trash.fill")
                    .font(.system(size: 14, weight: .semibold))
                Text("Delete Workout")
                    .font(.system(size: 15, weight: .semibold))
            }
            .foregroundStyle(Color.kineticsRed)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.kineticsRed.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(Color.kineticsRed.opacity(0.25), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private func loadPersonalRecords() {
        personalRecords = (try? GymRepository.shared.fetchPersonalRecords(userId: userId)) ?? []
    }
}

// MARK: - DetailStatCell

private struct DetailStatCell: View {
    let value: String
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .minimumScaleFactor(0.7)
                .lineLimit(1)

            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.kineticsSubtext)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(white: 0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(color.opacity(0.2), lineWidth: 1)
                )
        )
    }
}

// MARK: - DetailSectionHeader

private struct DetailSectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Color.kineticsSubtext)
            .textCase(.uppercase)
            .kerning(0.8)
    }
}

// MARK: - ExerciseBreakdownCard

private struct ExerciseBreakdownCard: View {

    let entry: WorkoutExerciseEntry
    let personalRecords: [PersonalRecord]

    private var prForExercise: PersonalRecord? {
        personalRecords.first { $0.exerciseId == entry.exerciseId }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Exercise name header
            Text(entry.exerciseName)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.top, 14)

            Divider()
                .background(Color.white.opacity(0.07))
                .padding(.horizontal, 14)

            // Sets list
            let sortedSets = entry.sets.sorted { $0.setNumber < $1.setNumber }
            VStack(spacing: 4) {
                ForEach(sortedSets, id: \.id) { set in
                    SetBreakdownRow(
                        set: set,
                        exerciseId: entry.exerciseId,
                        personalRecord: prForExercise
                    )
                }
            }
            .padding(.bottom, 10)
        }
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(white: 0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
                )
        )
    }
}

// MARK: - SetBreakdownRow

private struct SetBreakdownRow: View {

    let set: WorkoutSet
    let exerciseId: String
    let personalRecord: PersonalRecord?

    private var isPR: Bool {
        guard let pr = personalRecord, set.isCompleted else { return false }
        return set.weight >= pr.weight && set.weight > 0
    }

    private var weightDisplay: String {
        if set.weight == 0 { return "BW" }
        let formatted = set.weight.truncatingRemainder(dividingBy: 1) == 0
            ? "\(Int(set.weight)) kg"
            : String(format: "%.1f kg", set.weight)
        return formatted
    }

    var body: some View {
        HStack(spacing: 8) {
            // Set label
            Text("Set \(set.setNumber)")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(set.isCompleted ? Color.kineticsSubtext : Color.kineticsSubtext.opacity(0.5))
                .frame(width: 50, alignment: .leading)

            // Weight × reps
            Text("\(weightDisplay) × \(set.reps)")
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundStyle(set.isCompleted ? .white : Color.kineticsSubtext.opacity(0.5))

            Spacer()

            // PR badge
            if isPR {
                HStack(spacing: 3) {
                    Text("🏆")
                        .font(.system(size: 12))
                    Text("PR!")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.kineticsAmber)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    Capsule()
                        .fill(Color.kineticsAmber.opacity(0.14))
                )
            } else if !set.isCompleted {
                Text("Skipped")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.kineticsSubtext.opacity(0.5))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(
            isPR ? Color.kineticsAmber.opacity(0.04) : Color.clear
        )
    }
}
