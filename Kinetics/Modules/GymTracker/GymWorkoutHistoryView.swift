import SwiftUI

// MARK: - GymWorkoutHistoryViewModel

@Observable
@MainActor
final class GymWorkoutHistoryViewModel {

    // MARK: State

    var sessions: [WorkoutSession] = []
    var isLoading = false
    var errorMessage: String?
    var selectedTimeFilter: TimeFilter = .all
    var selectedMuscleFilter: String? = nil

    // MARK: - TimeFilter

    enum TimeFilter: String, CaseIterable {
        case all        = "All"
        case thisWeek   = "This Week"
        case thisMonth  = "This Month"
    }

    // MARK: - Derived

    var filteredSessions: [WorkoutSession] {
        let calendar = Calendar.current
        let now = Date()

        var result = sessions

        switch selectedTimeFilter {
        case .all:
            break
        case .thisWeek:
            if let weekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start {
                result = result.filter { $0.startedAt >= weekStart }
            }
        case .thisMonth:
            if let monthStart = calendar.dateInterval(of: .month, for: now)?.start {
                result = result.filter { $0.startedAt >= monthStart }
            }
        }

        if let muscle = selectedMuscleFilter {
            result = result.filter { session in
                session.entries.contains { entry in
                    entry.exerciseName.localizedCaseInsensitiveContains(muscle)
                }
            }
        }

        return result
    }

    var availableMuscleGroups: [String] {
        GymMuscleGroup.allCases.map(\.rawValue)
    }

    // MARK: - Load

    func load(userId: String) async {
        isLoading = true
        defer { isLoading = false }
        errorMessage = nil
        do {
            sessions = try GymRepository.shared.fetchSessions(userId: userId, limit: 200)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Delete

    func delete(_ session: WorkoutSession) {
        do {
            try GymRepository.shared.deleteSession(session)
            sessions.removeAll { $0.id == session.id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - GymWorkoutHistoryView

@MainActor
struct GymWorkoutHistoryView: View {

    let userId: String

    @State private var viewModel = GymWorkoutHistoryViewModel()
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                Color.black.ignoresSafeArea()
                content
            }
            .navigationTitle("WORKOUT HISTORY")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.black, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .task { await viewModel.load(userId: userId) }
            .navigationDestination(for: WorkoutSession.self) { session in
                GymWorkoutDetailView(session: session, userId: userId) { deleted in
                    viewModel.sessions.removeAll { $0.id == deleted.id }
                }
            }
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        VStack(spacing: 0) {
            filterBar

            if viewModel.isLoading {
                loadingState
            } else if viewModel.filteredSessions.isEmpty {
                emptyState
            } else {
                sessionList
            }
        }
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        VStack(spacing: 0) {
            // Time filters
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(GymWorkoutHistoryViewModel.TimeFilter.allCases, id: \.self) { filter in
                        HistoryFilterChip(
                            title: filter.rawValue,
                            isSelected: viewModel.selectedTimeFilter == filter,
                            color: Color.kineticsBlue
                        ) {
                            viewModel.selectedTimeFilter = filter
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 6)
            }

            // Muscle group filters
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    HistoryFilterChip(
                        title: "All Muscles",
                        isSelected: viewModel.selectedMuscleFilter == nil,
                        color: Color.kineticsGreen
                    ) {
                        viewModel.selectedMuscleFilter = nil
                    }

                    ForEach(viewModel.availableMuscleGroups, id: \.self) { muscle in
                        HistoryFilterChip(
                            title: muscle,
                            isSelected: viewModel.selectedMuscleFilter == muscle,
                            color: Color.kineticsGreen
                        ) {
                            viewModel.selectedMuscleFilter = viewModel.selectedMuscleFilter == muscle
                                ? nil
                                : muscle
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 2)
                .padding(.bottom, 10)
            }

            Divider()
                .background(Color.white.opacity(0.08))
        }
        .background(Color.black)
    }

    // MARK: - Loading State

    private var loadingState: some View {
        VStack(spacing: 20) {
            Spacer()
            ProgressView()
                .tint(Color.kineticsBlue)
                .scaleEffect(1.3)
            Text("Loading workouts…")
                .font(.system(size: 14))
                .foregroundStyle(Color.kineticsSubtext)
            Spacer()
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()

            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color(white: 0.08))
                    .frame(width: 80, height: 80)
                Image(systemName: "dumbbell")
                    .font(.system(size: 34, weight: .medium))
                    .foregroundStyle(Color.kineticsBlue.opacity(0.5))
            }

            VStack(spacing: 8) {
                Text(viewModel.selectedTimeFilter == .all && viewModel.selectedMuscleFilter == nil
                     ? "No workouts logged yet"
                     : "No workouts match this filter")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)

                Text(viewModel.selectedTimeFilter == .all && viewModel.selectedMuscleFilter == nil
                     ? "Complete your first session to see it here."
                     : "Try a different time range or muscle group.")
                    .font(.subheadline)
                    .foregroundStyle(Color.kineticsSubtext)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Spacer()
        }
    }

    // MARK: - Session List

    private var sessionList: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 10) {
                ForEach(viewModel.filteredSessions, id: \.id) { session in
                    Button {
                        path.append(session)
                    } label: {
                        HistorySessionCard(session: session)
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            viewModel.delete(session)
                        } label: {
                            Label("Delete", systemImage: "trash.fill")
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 32)
        }
    }
}

// MARK: - HistoryFilterChip

private struct HistoryFilterChip: View {
    let title: String
    let isSelected: Bool
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? .black : Color.kineticsSubtext)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(
                    Capsule()
                        .fill(isSelected ? color : Color(white: 0.1))
                        .overlay(
                            Capsule()
                                .strokeBorder(
                                    isSelected ? Color.clear : color.opacity(0.15),
                                    lineWidth: 1
                                )
                        )
                )
                .animation(.spring(duration: 0.2), value: isSelected)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - HistorySessionCard

private struct HistorySessionCard: View {

    let session: WorkoutSession

    // MARK: Computed

    private var dateText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d"
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
        if kg == 0 { return "—" }
        if kg >= 1000 { return String(format: "%.1fk kg", kg / 1000) }
        let formatted = kg.truncatingRemainder(dividingBy: 1) == 0
            ? "\(Int(kg)) kg"
            : String(format: "%.1f kg", kg)
        return formatted
    }

    private var exerciseCount: Int { session.entries.count }

    private var topExercises: [String] {
        Array(session.entries
            .sorted { $0.orderIndex < $1.orderIndex }
            .map(\.exerciseName)
            .prefix(3))
    }

    // MARK: Body

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Row 1: date + duration
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(dateText)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)

                    Text("\(exerciseCount) exercise\(exerciseCount == 1 ? "" : "s")")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.kineticsSubtext)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 3) {
                    Text(durationText)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.kineticsBlue)

                    Text(formattedVolume)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.kineticsSubtext)
                }
            }

            // Row 2: exercise chips
            if !topExercises.isEmpty {
                HStack(spacing: 6) {
                    ForEach(topExercises, id: \.self) { name in
                        Text(name)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color.kineticsSubtext)
                            .lineLimit(1)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(Color(white: 0.12))
                            )
                    }

                    if session.entries.count > 3 {
                        Text("+\(session.entries.count - 3)")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color.kineticsSubtext.opacity(0.7))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(Color(white: 0.12))
                            )
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(white: 0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
                )
        )
        .contentShape(Rectangle())
    }
}
