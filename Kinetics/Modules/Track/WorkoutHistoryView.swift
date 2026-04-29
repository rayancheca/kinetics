import SwiftUI

// MARK: - WorkoutHistoryViewModel

/// Lightweight observable ViewModel scoped to `WorkoutHistoryView`.
///
/// Defined in the same file as the view it drives; the history screen is a
/// single-purpose surface that doesn't warrant a separate file.
@Observable
@MainActor
final class WorkoutHistoryViewModel {

    // MARK: - State

    var workouts: [WorkoutResult] = []
    var isLoading = false
    var errorMessage: String?

    /// The currently selected activity type filter. `nil` means "All".
    var selectedFilter: WorkoutActivityType?

    // MARK: - Derived

    var filteredWorkouts: [WorkoutResult] {
        guard let filter = selectedFilter else { return workouts }
        return workouts.filter { $0.activityType == filter }
    }

    // MARK: - Grouped by Week

    /// Groups `filteredWorkouts` into "This Week", "Last Week", and "Older" buckets.
    var groupedWorkouts: [(title: String, workouts: [WorkoutResult])] {
        let calendar = Calendar.current
        let now = Date()

        guard let thisWeekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start,
              let lastWeekStart = calendar.date(byAdding: .weekOfYear, value: -1, to: thisWeekStart)
        else {
            return [("All Time", filteredWorkouts)]
        }

        var thisWeek: [WorkoutResult] = []
        var lastWeek: [WorkoutResult] = []
        var older: [WorkoutResult] = []

        for workout in filteredWorkouts {
            if workout.startedAt >= thisWeekStart {
                thisWeek.append(workout)
            } else if workout.startedAt >= lastWeekStart {
                lastWeek.append(workout)
            } else {
                older.append(workout)
            }
        }

        var groups: [(title: String, workouts: [WorkoutResult])] = []
        if !thisWeek.isEmpty  { groups.append(("This Week",  thisWeek))  }
        if !lastWeek.isEmpty  { groups.append(("Last Week",  lastWeek))  }
        if !older.isEmpty     { groups.append(("Older",      older))     }
        return groups
    }

    // MARK: - Data Loading

    func load(userId: String) async {
        isLoading = true
        errorMessage = nil
        do {
            workouts = try await WorkoutRepository.shared.fetchAll(userId: userId)
        } catch {
            errorMessage = "Could not load workouts: \(error.localizedDescription)"
        }
        isLoading = false
    }

    func delete(workout: WorkoutResult, userId: String) async {
        do {
            try await WorkoutRepository.shared.delete(id: workout.id, userId: userId)
            workouts.removeAll { $0.id == workout.id }
        } catch {
            errorMessage = "Failed to delete workout: \(error.localizedDescription)"
        }
    }
}

// MARK: - WorkoutHistoryView

/// Scrollable list of all past GPS workouts for the current user.
///
/// Pushed onto the navigation stack from `TrackView` via a toolbar button or list link.
/// Supports activity-type filtering via a horizontal pill row and swipe-to-delete.
@MainActor
struct WorkoutHistoryView: View {

    // MARK: - Environment / State

    @Environment(AppState.self) private var appState
    @State private var viewModel = WorkoutHistoryViewModel()
    @State private var navigationPath = NavigationPath()

    // MARK: - Body

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ZStack {
                Color.kineticsBackground.ignoresSafeArea()

                if viewModel.isLoading {
                    loadingView
                } else if viewModel.groupedWorkouts.isEmpty {
                    emptyStateView
                } else {
                    workoutList
                }
            }
            .navigationTitle("Workouts")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(Color.kineticsBackground, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .safeAreaInset(edge: .top) {
                filterPills
                    .padding(.top, 4)
                    .padding(.bottom, 8)
                    .background(Color.kineticsBackground)
            }
            .navigationDestination(for: WorkoutResult.self) { workout in
                WorkoutDetailView(workout: workout)
            }
            .alert("Error", isPresented: .constant(viewModel.errorMessage != nil)) {
                Button("OK") { viewModel.errorMessage = nil }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
        }
        .task {
            guard let uid = appState.authManager.currentUser?.uid else { return }
            await viewModel.load(userId: uid)
        }
    }

    // MARK: - Filter Pills

    private var filterPills: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                filterPill(label: "All", activityType: nil)

                ForEach(WorkoutActivityType.allCases, id: \.self) { type in
                    filterPill(label: type.displayName, activityType: type)
                }
            }
            .padding(.horizontal, 20)
        }
    }

    private func filterPill(label: String, activityType: WorkoutActivityType?) -> some View {
        let isSelected = viewModel.selectedFilter == activityType
        let accent: Color = activityType.map { Color(hex: $0.accentColorHex) } ?? Color.kineticsBlue

        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                viewModel.selectedFilter = activityType
            }
        } label: {
            HStack(spacing: 5) {
                if let type = activityType {
                    Image(systemName: type.systemImage)
                        .font(.system(size: 11, weight: .semibold))
                }
                Text(label)
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(isSelected ? .black : .white.opacity(0.6))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(isSelected ? accent : Color.kineticsDark)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(isSelected ? .clear : .white.opacity(0.1), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Workout List

    private var workoutList: some View {
        List {
            ForEach(viewModel.groupedWorkouts, id: \.title) { group in
                Section {
                    ForEach(group.workouts) { workout in
                        Button {
                            navigationPath.append(workout)
                        } label: {
                            WorkoutHistoryRow(workout: workout)
                        }
                        .listRowBackground(Color.kineticsDark)
                        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                Task {
                                    guard let uid = appState.authManager.currentUser?.uid else { return }
                                    await viewModel.delete(workout: workout, userId: uid)
                                }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                } header: {
                    Text(group.title)
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(2)
                        .foregroundStyle(.white.opacity(0.35))
                        .textCase(nil)
                        .padding(.top, 8)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }

    // MARK: - Loading View

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .tint(Color.kineticsBlue)
                .scaleEffect(1.2)
            Text("Loading workouts…")
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.4))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "figure.run.circle")
                .font(.system(size: 64))
                .foregroundStyle(Color.kineticsBlue.opacity(0.4))

            VStack(spacing: 8) {
                Text("No workouts yet")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white)

                Text("Tap Track to start your first session.")
                    .font(.system(size: 15))
                    .foregroundStyle(.white.opacity(0.45))
                    .multilineTextAlignment(.center)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - WorkoutHistoryRow

/// Single list row for a `WorkoutResult`, used inside `WorkoutHistoryView`.
///
/// Displays sport icon (tinted in the activity's accent color), activity type label,
/// date, and the three most informative metrics: distance, duration, average pace.
private struct WorkoutHistoryRow: View {

    let workout: WorkoutResult

    private var accent: Color { Color(hex: workout.activityType.accentColorHex) }

    var body: some View {
        HStack(spacing: 14) {
            // Sport icon badge
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(accent.opacity(0.14))
                    .frame(width: 44, height: 44)
                Image(systemName: workout.activityType.systemImage)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(accent)
            }

            // Activity + date
            VStack(alignment: .leading, spacing: 3) {
                Text(workout.activityType.displayName.uppercased())
                    .font(.system(size: 13, weight: .black))
                    .foregroundStyle(.white)

                Text(workout.formattedDate)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.4))
            }

            Spacer()

            // Key metrics
            VStack(alignment: .trailing, spacing: 3) {
                Text(workout.formattedDistance)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                HStack(spacing: 6) {
                    Text(workout.formattedDuration)
                    Text("·")
                    Text(workout.formattedAvgPace)
                }
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.4))
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.2))
        }
        .padding(.vertical, 12)
    }
}
