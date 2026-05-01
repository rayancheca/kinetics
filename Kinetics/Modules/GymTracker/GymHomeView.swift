import SwiftUI

// MARK: - GymHomeViewModel

@Observable
@MainActor
final class GymHomeViewModel {

    // MARK: State

    var recentSessions: [WorkoutSession] = []
    var personalRecords: [PersonalRecord] = []
    var routines: [Routine] = []
    var streak: Int = 0
    var weeklyWorkoutCount: Int = 0
    var monthlyVolumeKg: Double = 0
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
            recentSessions = try GymRepository.shared.fetchSessions(userId: userId, limit: 3)
            personalRecords = await GymRepository.shared.fetchPersonalRecords(userId: userId)
            routines = await GymRepository.shared.fetchRoutines(userId: userId)
            streak = (try? GymRepository.shared.calculateStreak(userId: userId)) ?? 0
            weeklyWorkoutCount = computeWeeklyCount(userId: userId)
            monthlyVolumeKg = computeMonthlyVolume()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: Session Management

    func startNewSession(userId: String) throws -> WorkoutSession {
        try GymRepository.shared.createSession(userId: userId)
    }

    // MARK: Private Helpers

    private func computeWeeklyCount(userId: String) -> Int {
        let calendar = Calendar.current
        let now = Date()
        guard let weekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start else {
            return 0
        }
        return recentSessions.filter {
            $0.isCompleted && $0.startedAt >= weekStart
        }.count
    }

    private func computeMonthlyVolume() -> Double {
        let calendar = Calendar.current
        let now = Date()
        guard let monthStart = calendar.dateInterval(of: .month, for: now)?.start else {
            return 0
        }
        return recentSessions
            .filter { $0.startedAt >= monthStart }
            .flatMap(\.entries)
            .flatMap(\.sets)
            .reduce(0) { $0 + ($1.weight * Double($1.reps)) }
    }
}

// MARK: - GymHomeView

@MainActor
struct GymHomeView: View {

    @Environment(AppState.self) private var appState
    @State private var viewModel = GymHomeViewModel()
    @State private var activeSession: WorkoutSession?
    @State private var navigationPath = NavigationPath()

    private var uid: String {
        appState.authManager.currentUser?.uid ?? "preview-user"
    }

    /// Derives a first name from the Firebase user's email prefix, matching ProfileView logic.
    private var firstName: String {
        let isAnonymous = appState.authManager.currentUser?.isAnonymous == true
        if isAnonymous { return "Athlete" }
        return appState.authManager.currentUser?.email?
            .components(separatedBy: "@").first?
            .capitalized ?? "Athlete"
    }

    // MARK: - Body

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ZStack {
                Color.black.ignoresSafeArea()

                if viewModel.isLoading {
                    ProgressView()
                        .tint(Color.kineticsBlue)
                } else {
                    scrollContent
                }
            }
            .navigationBarHidden(true)
            .task {
                await viewModel.load(userId: uid)
            }
            .navigationDestination(for: String.self) { destination in
                switch destination {
                case "routines":
                    RoutineListView()
                case "progress":
                    GymProgressView(userId: uid)
                case "prs":
                    PersonalRecordsView(userId: uid)
                case "body":
                    BodyMeasurementView(userId: uid)
                case "history":
                    GymWorkoutHistoryView(userId: uid)
                default:
                    EmptyView()
                }
            }
            .sheet(isPresented: $viewModel.showExerciseLibrary) {
                ExerciseLibraryView()
            }
            .sheet(isPresented: $viewModel.showNewWorkout) {
                Color.clear
                    .onAppear {
                        viewModel.showNewWorkout = false
                        startSession()
                    }
            }
            .sheet(item: $activeSession) { session in
                ActiveGymSessionView(session: session)
                    .onDisappear {
                        Task { await viewModel.load(userId: uid) }
                    }
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
            VStack(alignment: .leading, spacing: 0) {
                dashboardHeader
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 24)

                quickActionsRow
                    .padding(.bottom, 24)

                todaysFocusCard
                    .padding(.horizontal, 20)
                    .padding(.bottom, 28)

                statsStrip
                    .padding(.horizontal, 20)
                    .padding(.bottom, 28)

                recentWorkoutsSection
                    .padding(.horizontal, 20)
                    .padding(.bottom, 28)

                quickAccessGrid
                    .padding(.horizontal, 20)
                    .padding(.bottom, 40)
            }
        }
    }

    // MARK: - Dashboard Header

    private var dashboardHeader: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("GYM")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.kineticsBlue)
                    .kerning(2.5)

                Text(firstName)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.white)

                Text(headerDateString)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(Color.kineticsSubtext)
            }

            Spacer()

            if viewModel.streak > 0 {
                streakBadge
            }
        }
    }

    private var headerDateString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d"
        return formatter.string(from: Date())
    }

    private var streakBadge: some View {
        VStack(spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.kineticsAmber)

                Text("\(viewModel.streak)")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }

            Text("day streak")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color.kineticsAmber.opacity(0.8))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.kineticsAmber.opacity(0.12))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(Color.kineticsAmber.opacity(0.25), lineWidth: 1)
                )
        )
    }

    // MARK: - Quick Actions Row

    private var quickActionsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                Spacer().frame(width: 10)

                QuickActionPill(
                    icon: "dumbbell.fill",
                    label: "New Workout",
                    color: Color.kineticsBlue
                ) {
                    startSession()
                }

                QuickActionPill(
                    icon: "books.vertical.fill",
                    label: "Quick Log",
                    color: Color.kineticsGreen
                ) {
                    viewModel.showExerciseLibrary = true
                }

                QuickActionPill(
                    icon: "rectangle.stack.fill",
                    label: "Routines",
                    color: Color.kineticsPurple
                ) {
                    navigationPath.append("routines")
                }

                QuickActionPill(
                    icon: "chart.line.uptrend.xyaxis",
                    label: "Progress",
                    color: Color.kineticsAmber
                ) {
                    navigationPath.append("progress")
                }

                Spacer().frame(width: 10)
            }
        }
    }

    // MARK: - Today's Focus Card

    @ViewBuilder
    private var todaysFocusCard: some View {
        if let routine = viewModel.routines.first {
            TodayFocusCard(routine: routine) {
                startSession()
            }
        } else {
            BuildRoutinePromptCard {
                navigationPath.append("routines")
            }
        }
    }

    // MARK: - Stats Strip

    private var statsStrip: some View {
        HStack(spacing: 12) {
            StatCell(
                value: "\(viewModel.weeklyWorkoutCount)",
                label: "This week",
                color: Color.kineticsBlue
            )

            StatCell(
                value: formattedVolume(viewModel.monthlyVolumeKg),
                label: "kg this month",
                color: Color.kineticsGreen
            )

            StatCell(
                value: "\(viewModel.streak)",
                label: "day streak",
                color: Color.kineticsAmber
            )
        }
    }

    private func formattedVolume(_ kg: Double) -> String {
        if kg >= 1000 {
            return String(format: "%.1fk", kg / 1000)
        }
        return String(Int(kg))
    }

    // MARK: - Recent Workouts Section

    private var recentWorkoutsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                GymSectionHeader(title: "Recent Workouts")
                Spacer()
                if !viewModel.recentSessions.isEmpty {
                    Button {
                        navigationPath.append("history")
                    } label: {
                        Text("See All")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Color.kineticsBlue)
                    }
                    .buttonStyle(.plain)
                }
            }

            if viewModel.recentSessions.isEmpty {
                GymEmptyWorkoutsCard {
                    startSession()
                }
            } else {
                VStack(spacing: 8) {
                    ForEach(viewModel.recentSessions, id: \.id) { session in
                        RecentWorkoutRow(session: session) {
                            navigationPath.append("history")
                        }
                    }
                }
            }
        }
    }

    // MARK: - Quick Access Grid

    private var quickAccessGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            GymSectionHeader(title: "Quick Access")

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12)
                ],
                spacing: 12
            ) {
                GridAccessCard(
                    icon: "books.vertical.fill",
                    label: "Exercise Library",
                    color: Color.kineticsBlue
                ) {
                    viewModel.showExerciseLibrary = true
                }

                GridAccessCard(
                    icon: "calendar",
                    label: "Routines",
                    color: Color.kineticsPurple
                ) {
                    navigationPath.append("routines")
                }

                GridAccessCard(
                    icon: "trophy.fill",
                    label: "Personal Records",
                    color: Color.kineticsAmber
                ) {
                    navigationPath.append("prs")
                }

                GridAccessCard(
                    icon: "chart.line.uptrend.xyaxis",
                    label: "Progress",
                    color: Color.kineticsGreen
                ) {
                    navigationPath.append("progress")
                }
            }
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

// MARK: - QuickActionPill

private struct QuickActionPill: View {
    let icon: String
    let label: String
    let color: Color
    let action: () -> Void

    @State private var isPressed = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(color)

                Text(label)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .background(
                Capsule()
                    .fill(Color(white: 0.1))
                    .overlay(
                        Capsule()
                            .strokeBorder(color.opacity(0.3), lineWidth: 1)
                    )
            )
            .scaleEffect(isPressed ? 0.96 : 1.0)
            .animation(.spring(duration: 0.18), value: isPressed)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
    }
}

// MARK: - TodayFocusCard

private struct TodayFocusCard: View {
    let routine: Routine
    let onStart: () -> Void

    @State private var isPressed = false

    private var estimatedMinutes: Int {
        // ~3 min per exercise is a reasonable estimate
        max(15, routine.exerciseIds.count * 3)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("TODAY'S FOCUS")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.kineticsBlue)
                        .kerning(1.5)

                    Text(routine.name)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                }
                Spacer()
                Image(systemName: "figure.strengthtraining.traditional")
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(Color.kineticsBlue.opacity(0.4))
            }

            HStack(spacing: 16) {
                Label(
                    "\(routine.exerciseIds.count) exercises",
                    systemImage: "list.bullet"
                )
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.kineticsSubtext)

                Label(
                    "~\(estimatedMinutes) min",
                    systemImage: "clock"
                )
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.kineticsSubtext)
            }

            Button(action: onStart) {
                HStack {
                    Text("Start Routine")
                        .font(.system(size: 15, weight: .semibold))
                    Image(systemName: "arrow.right")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    LinearGradient(
                        colors: [Color.kineticsBlue, Color.kineticsBlue.opacity(0.8)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .scaleEffect(isPressed ? 0.98 : 1.0)
            .animation(.spring(duration: 0.18), value: isPressed)
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in isPressed = true }
                    .onEnded { _ in isPressed = false }
            )
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(white: 0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
                )
        )
    }
}

// MARK: - BuildRoutinePromptCard

private struct BuildRoutinePromptCard: View {
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.kineticsPurple.opacity(0.14))
                        .frame(width: 52, height: 52)
                    Image(systemName: "plus.rectangle.on.rectangle")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(Color.kineticsPurple)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Build Your First Routine")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                    Text("Save a plan you can launch every session")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(Color.kineticsSubtext)
                        .lineLimit(2)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.kineticsSubtext.opacity(0.5))
            }
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(white: 0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(Color.kineticsPurple.opacity(0.2), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - StatCell

private struct StatCell: View {
    let value: String
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .minimumScaleFactor(0.7)
                .lineLimit(1)

            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.kineticsSubtext)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(white: 0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(color.opacity(0.18), lineWidth: 1)
                )
        )
    }
}

// MARK: - RecentWorkoutRow

private struct RecentWorkoutRow: View {
    let session: WorkoutSession
    let onTap: () -> Void

    private var durationText: String {
        let start = session.startedAt
        let end = session.endedAt ?? Date()
        let minutes = Int(end.timeIntervalSince(start)) / 60
        if minutes < 60 {
            return "\(minutes)m"
        }
        let h = minutes / 60
        let m = minutes % 60
        return m > 0 ? "\(h)h \(m)m" : "\(h)h"
    }

    private var dateLabel: String {
        let cal = Calendar.current
        if cal.isDateInToday(session.startedAt) { return "Today" }
        if cal.isDateInYesterday(session.startedAt) { return "Yesterday" }
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f.string(from: session.startedAt)
    }

    private var volumeKg: Double {
        session.entries
            .flatMap(\.sets)
            .filter(\.isCompleted)
            .reduce(0) { $0 + ($1.weight * Double($1.reps)) }
    }

    private var formattedVolume: String {
        let kg = volumeKg
        if kg == 0 { return "—" }
        if kg >= 1000 { return String(format: "%.1fk kg", kg / 1000) }
        return "\(Int(kg)) kg"
    }

    private var exerciseCount: Int { session.entries.count }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.kineticsBlue.opacity(0.13))
                        .frame(width: 42, height: 42)
                    Image(systemName: "figure.strengthtraining.traditional")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(Color.kineticsBlue)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(dateLabel)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)

                    HStack(spacing: 6) {
                        Text("\(exerciseCount) exercise\(exerciseCount == 1 ? "" : "s")")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.kineticsSubtext)

                        Text("·")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.kineticsSubtext.opacity(0.5))

                        Text(formattedVolume)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color.kineticsSubtext)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 3) {
                    Text(durationText)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)

                    if session.isCompleted {
                        Text("Done")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Color.kineticsGreen)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill(Color.kineticsGreen.opacity(0.14))
                            )
                    }
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.kineticsSubtext.opacity(0.4))
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(white: 0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(Color.white.opacity(0.05), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - GymEmptyWorkoutsCard

private struct GymEmptyWorkoutsCard: View {
    let onStart: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "dumbbell")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(Color.kineticsBlue.opacity(0.45))

            VStack(spacing: 6) {
                Text("No workouts yet. Hit the gym.")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)

                Text("Log your first session to see it here")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.kineticsSubtext)
            }

            Button(action: onStart) {
                Text("Start First Workout")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.kineticsBlue)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.kineticsBlue.opacity(0.12))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .strokeBorder(Color.kineticsBlue.opacity(0.25), lineWidth: 1)
                            )
                    )
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .padding(.horizontal, 20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(white: 0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(Color.white.opacity(0.05), lineWidth: 1)
                )
        )
    }
}

// MARK: - GridAccessCard

private struct GridAccessCard: View {
    let icon: String
    let label: String
    let color: Color
    let action: () -> Void

    @State private var isPressed = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(color.opacity(0.16))
                        .frame(width: 44, height: 44)

                    Image(systemName: icon)
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(color)
                }

                Text(label)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(white: 0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(color.opacity(0.18), lineWidth: 1)
                    )
            )
            .scaleEffect(isPressed ? 0.96 : 1.0)
            .animation(.spring(duration: 0.18), value: isPressed)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
    }
}

// MARK: - GymSectionHeader

private struct GymSectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Color.kineticsSubtext)
            .textCase(.uppercase)
            .kerning(0.8)
    }
}

// ExerciseLibraryView, ExerciseDetailView, and AddExerciseSheet live in ExerciseLibraryView.swift
