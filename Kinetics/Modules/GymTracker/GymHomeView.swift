import SwiftUI

// MARK: - GymHomeViewModel

@Observable
@MainActor
final class GymHomeViewModel {

    // MARK: State

    var recentSessions: [WorkoutSession] = []
    var personalRecords: [PersonalRecord] = []
    var isLoading = false
    var errorMessage: String?
    var showNewWorkout = false
    var showExerciseLibrary = false

    // MARK: Load

    func load(userId: String) async {
        isLoading = true
        defer { isLoading = false }
        errorMessage = nil

        try? GymRepository.shared.seedExerciseLibraryIfNeeded()
        do {
            recentSessions = try GymRepository.shared.fetchSessions(userId: userId, limit: 5)
            personalRecords = try GymRepository.shared.fetchPersonalRecords(userId: userId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: Session Management

    func startNewSession(userId: String) throws -> WorkoutSession {
        try GymRepository.shared.createSession(userId: userId)
    }
}

// MARK: - GymHomeView

@MainActor
struct GymHomeView: View {

    @Environment(AppState.self) private var appState
    @State private var viewModel = GymHomeViewModel()
    @State private var activeSession: WorkoutSession?
    @State private var navigationPath = NavigationPath()
    @State private var showComingSoonAlert = false

    private var uid: String {
        appState.authManager.currentUser?.uid ?? "preview-user"
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ZStack {
                Color.kineticsBackground.ignoresSafeArea()

                if viewModel.isLoading {
                    ProgressView()
                        .tint(Color.kineticsBlue)
                } else {
                    scrollContent
                }
            }
            .navigationTitle("Gym")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(Color.kineticsBackground, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        viewModel.showNewWorkout = true
                    } label: {
                        Image(systemName: "plus")
                            .foregroundStyle(Color.kineticsBlue)
                            .fontWeight(.semibold)
                    }
                }
            }
            .task {
                await viewModel.load(userId: uid)
            }
            .sheet(isPresented: $viewModel.showExerciseLibrary) {
                ExerciseLibraryView()
            }
            .sheet(isPresented: $viewModel.showNewWorkout) {
                // Triggers session creation when sheet appears
                Color.clear
                    .onAppear {
                        viewModel.showNewWorkout = false
                        startSession()
                    }
            }
            .sheet(item: $activeSession) { session in
                ActiveGymSessionView(session: session)
            }
            .alert("Error", isPresented: .init(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { viewModel.errorMessage = nil }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
        }
    }

    // MARK: - Scroll Content

    @ViewBuilder
    private var scrollContent: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 28) {
                quickStartSection
                    .padding(.top, 20)

                if !viewModel.recentSessions.isEmpty {
                    recentSessionsSection
                }

                if !viewModel.personalRecords.isEmpty {
                    personalRecordsSection
                }

                if viewModel.recentSessions.isEmpty && viewModel.personalRecords.isEmpty {
                    emptyState
                        .frame(maxWidth: .infinity)
                        .padding(.top, 60)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
    }

    // MARK: - Quick Start Section

    private var quickStartSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick Start")
                .font(.headline)
                .foregroundStyle(.white.opacity(0.6))
                .textCase(.uppercase)
                .kerning(0.8)

            HStack(spacing: 12) {
                QuickStartCard(
                    title: "New Workout",
                    subtitle: "Start a session",
                    icon: "dumbbell.fill",
                    color: Color.kineticsBlue
                ) {
                    startSession()
                }

                QuickStartCard(
                    title: "Exercise Library",
                    subtitle: "Browse exercises",
                    icon: "books.vertical.fill",
                    color: Color.kineticsGreen
                ) {
                    viewModel.showExerciseLibrary = true
                }
            }
        }
    }

    // MARK: - Recent Sessions Section

    private var recentSessionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Recent Sessions")

            VStack(spacing: 8) {
                ForEach(viewModel.recentSessions, id: \.id) { session in
                    RecentSessionRow(session: session)
                }
            }
        }
    }

    // MARK: - Personal Records Section

    private var personalRecordsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Top Lifts")

            VStack(spacing: 8) {
                ForEach(viewModel.personalRecords, id: \.id) { record in
                    PRRow(record: record)
                }
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "dumbbell")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(Color.kineticsBlue.opacity(0.5))

            Text("No workouts yet")
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundStyle(.white)

            Text("Tap + to start your first session")
                .font(.subheadline)
                .foregroundStyle(Color.kineticsSubtext)
        }
    }

    // MARK: - Actions

    private func startSession() {
        Task {
            do {
                let session = try viewModel.startNewSession(userId: uid)
                activeSession = session
            } catch {
                viewModel.errorMessage = error.localizedDescription
            }
        }
    }
}

// MARK: - QuickStartCard (private)

private struct QuickStartCard: View {
    let title: String
    let subtitle: String
    let icon: String
    let color: Color
    let action: () -> Void

    @State private var isPressed = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(color.opacity(0.18))
                        .frame(width: 44, height: 44)

                    Image(systemName: icon)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(color)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)

                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.kineticsSubtext)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.kineticsDark)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(color.opacity(0.2), lineWidth: 1)
                    )
            )
            .scaleEffect(isPressed ? 0.97 : 1.0)
            .animation(.spring(duration: 0.2), value: isPressed)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
    }
}

// MARK: - SectionHeader (private)

private struct SectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Color.kineticsSubtext)
            .textCase(.uppercase)
            .kerning(0.8)
    }
}

// MARK: - RecentSessionRow (private)

private struct RecentSessionRow: View {

    let session: WorkoutSession

    private var durationText: String {
        let start = session.startedAt
        let end = session.endedAt ?? Date()
        let seconds = Int(end.timeIntervalSince(start))
        let minutes = seconds / 60
        if minutes < 60 {
            return "\(minutes)m"
        } else {
            let hours = minutes / 60
            let remaining = minutes % 60
            return remaining > 0 ? "\(hours)h \(remaining)m" : "\(hours)h"
        }
    }

    private var dateText: String {
        let formatter = DateFormatter()
        let calendar = Calendar.current
        if calendar.isDateInToday(session.startedAt) {
            return "Today"
        } else if calendar.isDateInYesterday(session.startedAt) {
            return "Yesterday"
        } else {
            formatter.dateFormat = "MMM d"
            return formatter.string(from: session.startedAt)
        }
    }

    private var exerciseCountText: String {
        let count = session.entries.count
        let totalSets = session.entries.reduce(0) { $0 + $1.sets.count }
        return "\(count) exercise\(count == 1 ? "" : "s") · \(totalSets) sets"
    }

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Color.kineticsBlue)
                .frame(width: 36, height: 36)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.kineticsBlue.opacity(0.15))
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(dateText)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)

                Text(exerciseCountText)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.kineticsSubtext)
            }

            Spacer()

            Text(durationText)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.kineticsSubtext)

            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.kineticsSubtext.opacity(0.6))
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.kineticsDark)
        )
    }
}

// MARK: - PRRow (private)

private struct PRRow: View {

    let record: PersonalRecord

    private var weightText: String {
        let kg = record.weight
        if kg == 0 { return "BW × \(record.reps)" }
        // Display in kg for now; could add lb toggle later
        let formatted = kg.truncatingRemainder(dividingBy: 1) == 0
            ? String(Int(kg)) : String(format: "%.1f", kg)
        return "\(formatted) kg × \(record.reps)"
    }

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "trophy.fill")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Color.kineticsAmber)
                .frame(width: 36, height: 36)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.kineticsAmber.opacity(0.15))
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(record.exerciseName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Text(weightText)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.kineticsSubtext)
            }

            Spacer()
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.kineticsDark)
        )
    }
}

// MARK: - ExerciseLibraryView

@MainActor
struct ExerciseLibraryView: View {

    @State private var exercises: [Exercise] = []
    @State private var searchText = ""
    @State private var selectedCategory: String? = nil
    @State private var isLoading = false
    @State private var showComingSoonAlert = false
    @Environment(\.dismiss) private var dismiss

    private let categories = ["All", "Strength", "Cardio", "Olympic", "Flexibility"]

    var body: some View {
        NavigationStack {
            ZStack {
                Color.kineticsBackground.ignoresSafeArea()

                VStack(spacing: 0) {
                    categoryFilterBar

                    if isLoading {
                        Spacer()
                        ProgressView()
                            .tint(Color.kineticsBlue)
                        Spacer()
                    } else if exercises.isEmpty {
                        emptyLibraryState
                    } else {
                        exerciseList
                    }

                    createCustomButton
                }
            }
            .navigationTitle("Exercise Library")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.kineticsBackground, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Color.kineticsBlue)
                }
            }
            .searchable(
                text: $searchText,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Search exercises"
            )
            .task { loadExercises() }
            .onChange(of: searchText) { loadExercises() }
            .onChange(of: selectedCategory) { loadExercises() }
            .alert("Coming Soon", isPresented: $showComingSoonAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("Custom exercise creation will be available in the next update.")
            }
        }
    }

    // MARK: - Category Filter Bar

    private var categoryFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(categories, id: \.self) { category in
                    CategoryPill(
                        title: category,
                        isSelected: category == "All"
                            ? selectedCategory == nil
                            : selectedCategory == category
                    ) {
                        selectedCategory = category == "All" ? nil : category
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Color.kineticsBackground)
    }

    // MARK: - Exercise List

    private var exerciseList: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 8) {
                ForEach(exercises, id: \.id) { exercise in
                    ExerciseRow(exercise: exercise)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
    }

    // MARK: - Empty State

    private var emptyLibraryState: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "magnifyingglass")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(Color.kineticsSubtext.opacity(0.5))

            Text(searchText.isEmpty ? "No exercises in library" : "No results for \"\(searchText)\"")
                .font(.headline)
                .foregroundStyle(.white)

            Text("Try a different search or category")
                .font(.subheadline)
                .foregroundStyle(Color.kineticsSubtext)

            Spacer()
        }
    }

    // MARK: - Create Custom Button

    private var createCustomButton: some View {
        Button {
            showComingSoonAlert = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 16, weight: .medium))
                Text("Create Custom Exercise")
                    .font(.system(size: 15, weight: .semibold))
            }
            .foregroundStyle(Color.kineticsBlue)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                Color.kineticsBlue.opacity(0.1)
                    .overlay(
                        Divider()
                            .frame(maxHeight: 1)
                            .background(Color.kineticsBlue.opacity(0.2)),
                        alignment: .top
                    )
            )
        }
    }

    // MARK: - Data Loading

    private func loadExercises() {
        isLoading = true
        let filter = searchText.isEmpty ? nil : searchText
        exercises = (try? GymRepository.shared.fetchExercises(
            filter: filter,
            category: selectedCategory
        )) ?? []
        isLoading = false
    }
}

// MARK: - CategoryPill (private)

private struct CategoryPill: View {

    let title: String
    let isSelected: Bool
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
                        .fill(isSelected ? Color.kineticsBlue : Color.kineticsDark)
                )
                .animation(.spring(duration: 0.2), value: isSelected)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - ExerciseRow (private)

private struct ExerciseRow: View {

    let exercise: Exercise

    // MARK: Computed Properties

    private var categoryColor: Color {
        switch exercise.category.lowercased() {
        case "strength": return Color.kineticsBlue
        case "cardio": return Color.kineticsGreen
        case "olympic": return Color.kineticsPurple
        default: return Color.kineticsOrange
        }
    }

    private var categoryIcon: String {
        switch exercise.category.lowercased() {
        case "cardio": return "bolt.fill"
        default: return "dumbbell.fill"
        }
    }

    private var detailText: String {
        [exercise.primaryMuscle, exercise.equipment]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    // MARK: Body

    var body: some View {
        HStack(spacing: 14) {
            // Category Icon
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(categoryColor.opacity(0.18))
                    .frame(width: 40, height: 40)

                Image(systemName: categoryIcon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(categoryColor)
            }

            // Name + Detail
            VStack(alignment: .leading, spacing: 3) {
                Text(exercise.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                if !detailText.isEmpty {
                    Text(detailText)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.kineticsSubtext)
                        .lineLimit(1)
                }
            }

            Spacer()

            // Favorite Indicator
            if exercise.isFavorite {
                Image(systemName: "heart.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.kineticsRed)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.kineticsDark)
        )
    }
}
