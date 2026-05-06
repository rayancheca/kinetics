import SwiftData
import SwiftUI

// MARK: - RecentWorkoutFilter

enum RecentWorkoutFilter: String, CaseIterable {
    case all       = "All"
    case thisWeek  = "This Week"
    case thisMonth = "This Month"
    case completed = "Completed"
    case empty     = "Empty"
}

// MARK: - GymHomeViewModel

@Observable
@MainActor
final class GymHomeViewModel {

    // MARK: State

    var recentSessions: [WorkoutSession] = []
    var personalRecords: [PersonalRecord] = []
    var routines: [Routine] = []
    var activePlan: WeeklyPlan?
    var streak: Int = 0
    var weeklyWorkoutCount: Int = 0
    var monthlyVolumeKg: Double = 0
    var isLoading = false
    var errorMessage: String?
    var showNewWorkout = false
    var showExerciseLibrary = false
    var showStartWorkoutSheet = false

    /// Filter applied to the recent workouts list on the home screen.
    var recentWorkoutFilter: RecentWorkoutFilter = .all

    /// The most recent in-progress session for this user, if any.
    var inProgressSession: WorkoutSession?

    // MARK: - Derived

    /// Session IDs hidden by the archive action — persisted via @AppStorage in the view layer.
    /// The ViewModel itself is storage-agnostic; the view injects the archived set.
    var archivedSessionIds: Set<String> = []

    var filteredRecentSessions: [WorkoutSession] {
        let calendar = Calendar.current
        let now = Date()
        var result = recentSessions.filter { !archivedSessionIds.contains($0.id) }

        switch recentWorkoutFilter {
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
        case .completed:
            result = result.filter { $0.isCompleted }
        case .empty:
            result = result.filter { $0.entries.isEmpty }
        }

        return result
    }

    // MARK: Load

    func load(userId: String) async {
        isLoading = true
        defer { isLoading = false }
        errorMessage = nil

        try? GymRepository.shared.seedExerciseLibraryIfNeeded()
        try? GymRepository.shared.seedTestRoutinesIfNeeded(userId: userId)
        do {
            let allRecent = try GymRepository.shared.fetchSessions(userId: userId, limit: 20)
            // Completed sessions for the "Recent Workouts" section (limit 3)
            recentSessions = allRecent.filter { $0.isCompleted }.prefix(3).map { $0 }
            // Detect the most recent in-progress session
            inProgressSession = allRecent.first { !$0.isCompleted && $0.endedAt == nil }
            personalRecords = await GymRepository.shared.fetchPersonalRecords(userId: userId)
            routines = await GymRepository.shared.fetchRoutines(userId: userId)
            streak = (try? GymRepository.shared.calculateStreak(userId: userId)) ?? 0
            weeklyWorkoutCount = computeWeeklyCount(userId: userId)
            monthlyVolumeKg = computeMonthlyVolume()
            activePlan = fetchActivePlan(userId: userId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: Abandon In-Progress Session

    func abandonSession(_ session: WorkoutSession) {
        do {
            // completeSession marks isCompleted=true and stamps endedAt
            try GymRepository.shared.completeSession(session)
            inProgressSession = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: Session Management

    func startNewSession(userId: String) throws -> WorkoutSession {
        try GymRepository.shared.createSession(userId: userId)
    }

    func repeatSession(_ session: WorkoutSession, userId: String) throws -> WorkoutSession {
        try GymRepository.shared.repeatSession(session, userId: userId)
    }

    func startRoutineSession(_ routine: Routine, userId: String) throws -> WorkoutSession {
        try GymRepository.shared.startSession(from: routine, userId: userId)
    }

    func fetchActivePlan(userId: String) -> WeeklyPlan? {
        guard let container = GymRepository.shared.modelContainer else { return nil }
        let context = ModelContext(container)
        let uid = userId
        let descriptor = FetchDescriptor<WeeklyPlan>(
            predicate: #Predicate { $0.userId == uid && $0.isActive == true }
        )
        return try? context.fetch(descriptor).first
    }

    // MARK: Delete Session

    func deleteSession(_ session: WorkoutSession) {
        do {
            try GymRepository.shared.deleteSession(session)
            recentSessions.removeAll { $0.id == session.id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Derived: Longest streak

    var longestStreakDays: Int {
        guard !recentSessions.isEmpty else { return 0 }
        let sorted = recentSessions
            .filter { $0.isCompleted }
            .map { Calendar.current.startOfDay(for: $0.startedAt) }
            .sorted()
        let uniqueDays = Array(Set(sorted)).sorted()
        guard !uniqueDays.isEmpty else { return 0 }
        var best = 1
        var current = 1
        for i in 1 ..< uniqueDays.count {
            let diff = Calendar.current.dateComponents([.day], from: uniqueDays[i - 1], to: uniqueDays[i]).day ?? 0
            if diff == 1 {
                current += 1
                best = max(best, current)
            } else if diff > 1 {
                current = 1
            }
        }
        return best
    }

    // MARK: - Derived: Trained days this week (weekday indices, Sunday = 1)

    var trainedDaysThisWeek: Set<Int> {
        let cal = Calendar.current
        let now = Date()
        guard let weekStart = cal.dateInterval(of: .weekOfYear, for: now)?.start else { return [] }
        let weekSessions = recentSessions.filter { $0.isCompleted && $0.startedAt >= weekStart }
        let weekdays = weekSessions.map { cal.component(.weekday, from: $0.startedAt) }
        return Set(weekdays)
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
    @State private var daySlotToStart: WeeklyDaySlot?
    @State private var showAbandonConfirm = false
    @State private var showConflictAlert = false
    @State private var pendingRoutine: Routine? = nil

    // MARK: Streak detail sheet

    @State private var showStreakDetail = false

    // MARK: Undo / Archive state

    /// Sessions removed by delete (pending undo within the 5-second window).
    @State private var undoPending: WorkoutSession? = nil
    @State private var showUndoToast = false

    /// Persisted archive set — session IDs hidden from the recent list.
    @AppStorage("gym.archivedSessionIds") private var archivedIdsRaw: String = ""

    private var archivedSessionIds: Set<String> {
        Set(archivedIdsRaw.split(separator: ",").map(String.init))
    }

    private var uid: String {
        appState.authManager.currentUser?.uid ?? "preview-user"
    }

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

                // Undo toast overlay
                if showUndoToast {
                    undoToast
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .zIndex(100)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .task {
                viewModel.archivedSessionIds = archivedSessionIds
                await viewModel.load(userId: uid)
            }
            .onChange(of: archivedIdsRaw) { _, _ in
                viewModel.archivedSessionIds = archivedSessionIds
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
                case "weekly-planner":
                    WeeklyPlanListView()
                default:
                    EmptyView()
                }
            }
            .sheet(isPresented: $viewModel.showExerciseLibrary) {
                ExerciseLibraryView()
            }
            .sheet(isPresented: $viewModel.showStartWorkoutSheet) {
                StartWorkoutPickerSheet(
                    activePlan: viewModel.activePlan,
                    routines: viewModel.routines,
                    lastSession: viewModel.recentSessions.first,
                    onStartBlank: { startEmptySession() },
                    onStartRoutine: { routine in startRoutineSession(routine) },
                    onRepeatLast: { session in repeatSession(session) },
                    userId: uid
                )
            }
            .sheet(item: $daySlotToStart) { _ in
                StartWorkoutPickerSheet(
                    activePlan: viewModel.activePlan,
                    routines: viewModel.routines,
                    lastSession: viewModel.recentSessions.first,
                    onStartBlank: { startEmptySession() },
                    onStartRoutine: { routine in startRoutineSession(routine) },
                    onRepeatLast: { session in repeatSession(session) },
                    userId: uid
                )
            }
            .sheet(item: $activeSession) { session in
                ActiveGymSessionView(session: session)
                    .onDisappear {
                        activeSession = nil
                        Task { await viewModel.load(userId: uid) }
                    }
            }
            .sheet(isPresented: $showStreakDetail) {
                StreakDetailSheet(
                    currentStreak: viewModel.streak,
                    longestStreak: viewModel.longestStreakDays,
                    trainedDaysThisWeek: viewModel.trainedDaysThisWeek
                )
            }
            .confirmationDialog(
                "End this workout?",
                isPresented: $showAbandonConfirm,
                titleVisibility: .visible
            ) {
                Button("End Workout", role: .destructive) {
                    if let session = viewModel.inProgressSession {
                        viewModel.abandonSession(session)
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Your progress will be marked complete and saved.")
            }
            .confirmationDialog(
                "Workout already in progress",
                isPresented: $showConflictAlert,
                titleVisibility: .visible
            ) {
                Button("Resume Existing") {
                    if let session = viewModel.inProgressSession {
                        activeSession = session
                    }
                }
                Button("End & Start New", role: .destructive) {
                    forceStartNew()
                }
                Button("Cancel", role: .cancel) {
                    pendingRoutine = nil
                }
            } message: {
                Text("You have a workout paused. Resume it or end it and start fresh.")
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
                // Header
                logHeader
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 16)

                // Resume Workout Banner (shown when a session is in-progress)
                if let inProgress = viewModel.inProgressSession {
                    ResumeWorkoutBanner(
                        session: inProgress,
                        onResume: { activeSession = inProgress },
                        onAbandon: { showAbandonConfirm = true }
                    )
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }

                // Weekly Calendar Strip
                WeeklyCalendarStrip(
                    activePlan: viewModel.activePlan,
                    onDayTap: { slot in
                        daySlotToStart = slot
                    },
                    onViewPlanTap: {
                        navigationPath.append("weekly-planner")
                    }
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 20)

                // Big CTA
                startWorkoutButton
                    .padding(.horizontal, 16)
                    .padding(.bottom, 28)

                // Quick Start Routines
                quickStartRoutinesSection
                    .padding(.bottom, 28)

                // Recent Workouts
                recentWorkoutsSection
                    .padding(.horizontal, 16)
                    .padding(.bottom, 40)
            }
        }
    }

    // MARK: - Log Header

    private var logHeader: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text(headerDayString)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.kineticsSubtext)

                Text(headerDateString)
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(.white)
            }

            Spacer()

            if viewModel.streak > 0 {
                Button { showStreakDetail = true } label: {
                    streakBadge
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var headerDayString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        return formatter.string(from: Date()).uppercased()
    }

    private var headerDateString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM d"
        return formatter.string(from: Date())
    }

    private var streakBadge: some View {
        HStack(spacing: 5) {
            Image(systemName: "flame.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.kineticsAmber)

            Text("\(viewModel.streak) day streak")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.kineticsAmber)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(Color.kineticsAmber.opacity(0.12))
                .overlay(
                    Capsule()
                        .strokeBorder(Color.kineticsAmber.opacity(0.28), lineWidth: 1)
                )
        )
    }

    // MARK: - Big Start Workout Button

    private var startWorkoutButton: some View {
        StartWorkoutBigButton {
            viewModel.showStartWorkoutSheet = true
        }
    }

    // MARK: - Quick Start Routines Section

    private var quickStartRoutinesSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                GymSectionHeader(title: "Quick Start")
                Spacer()
                NavigationLink(destination: WeeklyPlanListView()) {
                    HStack(spacing: 6) {
                        Image(systemName: "list.bullet.rectangle")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.kineticsBlue)
                        Text("Manage Plans")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.kineticsBlue)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Color.kineticsBlue.opacity(0.10))
                    .clipShape(Capsule())
                }
                .padding(.trailing, 16)
                Button {
                    navigationPath.append("routines")
                } label: {
                    Text("All Routines")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.kineticsBlue)
                }
                .buttonStyle(.plain)
                .padding(.trailing, 16)
            }
            .padding(.horizontal, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    Spacer().frame(width: 6)

                    ForEach(viewModel.routines, id: \.id) { routine in
                        RoutineQuickCard(routine: routine) {
                            startRoutineSession(routine)
                        }
                    }

                    CreateRoutineCard {
                        navigationPath.append("routines")
                    }

                    Spacer().frame(width: 6)
                }
            }
        }
    }

    // MARK: - Recent Workouts Section

    private var recentWorkoutsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
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

            // Filter chip bar
            if !viewModel.recentSessions.isEmpty {
                recentWorkoutsFilterBar
            }

            if viewModel.filteredRecentSessions.isEmpty && viewModel.recentSessions.isEmpty {
                GymEmptyWorkoutsCard {
                    startEmptySession()
                }
            } else if viewModel.filteredRecentSessions.isEmpty {
                // Sessions exist but none match the current filter
                noFilterMatchCard
            } else {
                recentWorkoutsList
            }
        }
    }

    // MARK: - Filter Bar

    private var recentWorkoutsFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(RecentWorkoutFilter.allCases, id: \.self) { filter in
                    RecentFilterChip(
                        title: filter.rawValue,
                        isSelected: viewModel.recentWorkoutFilter == filter
                    ) {
                        withAnimation(.spring(duration: 0.22)) {
                            viewModel.recentWorkoutFilter = filter
                        }
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }

    // MARK: - Recent Workouts List with Swipe Actions

    private var recentWorkoutsList: some View {
        LazyVStack(spacing: 10) {
            ForEach(viewModel.filteredRecentSessions, id: \.id) { session in
                RecentWorkoutCard(
                    session: session,
                    isArchived: archivedSessionIds.contains(session.id),
                    onTap: {
                        navigationPath.append("history")
                    },
                    onRepeat: {
                        repeatSession(session)
                    }
                )
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        confirmDeleteSession(session)
                    } label: {
                        Label("Delete", systemImage: "trash.fill")
                    }
                }
                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                    Button {
                        archiveSession(session)
                    } label: {
                        Label("Archive", systemImage: "archivebox.fill")
                    }
                    .tint(Color(white: 0.35))
                }
            }
        }
    }

    // MARK: - No filter match

    private var noFilterMatchCard: some View {
        VStack(spacing: 10) {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(Color.kineticsBlue.opacity(0.45))

            Text("No workouts match this filter")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)

            Text("Try a different filter")
                .font(.system(size: 12))
                .foregroundStyle(Color.kineticsSubtext)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(white: 0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(Color.white.opacity(0.05), lineWidth: 1)
                )
        )
    }

    // MARK: - Undo Toast

    private var undoToast: some View {
        VStack {
            Spacer()
            HStack(spacing: 14) {
                Image(systemName: "trash")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.8))

                Text("Workout deleted")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)

                Spacer()

                Button {
                    undoDelete()
                } label: {
                    Text("Undo")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color.kineticsBlue)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(white: 0.14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
                    )
            )
            .shadow(color: .black.opacity(0.4), radius: 16, x: 0, y: 6)
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
    }

    // MARK: - Actions

    private func startEmptySession() {
        if viewModel.inProgressSession != nil {
            pendingRoutine = nil
            showConflictAlert = true
            return
        }
        Task {
            do {
                let session = try viewModel.startNewSession(userId: uid)
                activeSession = session
            } catch {
                viewModel.errorMessage = error.localizedDescription
            }
        }
    }

    private func startRoutineSession(_ routine: Routine) {
        if viewModel.inProgressSession != nil {
            pendingRoutine = routine
            showConflictAlert = true
            return
        }
        Task {
            do {
                let session = try viewModel.startRoutineSession(routine, userId: uid)
                activeSession = session
            } catch {
                viewModel.errorMessage = error.localizedDescription
            }
        }
    }

    private func forceStartNew() {
        Task {
            if let existing = viewModel.inProgressSession {
                viewModel.abandonSession(existing)
            }
            do {
                let session: WorkoutSession
                if let routine = pendingRoutine {
                    session = try viewModel.startRoutineSession(routine, userId: uid)
                } else {
                    session = try viewModel.startNewSession(userId: uid)
                }
                pendingRoutine = nil
                activeSession = session
            } catch {
                viewModel.errorMessage = error.localizedDescription
            }
        }
    }

    private func repeatSession(_ session: WorkoutSession) {
        Task {
            do {
                let newSession = try viewModel.repeatSession(session, userId: uid)
                activeSession = newSession
            } catch {
                viewModel.errorMessage = error.localizedDescription
            }
        }
    }

    // MARK: - Delete with Undo

    private func confirmDeleteSession(_ session: WorkoutSession) {
        // Stash the pending deletion for potential undo
        undoPending = session
        withAnimation(.spring(duration: 0.25)) {
            viewModel.deleteSession(session)
            showUndoToast = true
        }

        // Auto-dismiss toast after 5 seconds, committing the delete
        Task {
            try? await Task.sleep(for: .seconds(5))
            withAnimation(.spring(duration: 0.2)) {
                showUndoToast = false
                undoPending = nil
            }
        }
    }

    private func undoDelete() {
        guard let session = undoPending else { return }
        // Re-insert the session back into recentSessions
        withAnimation(.spring(duration: 0.25)) {
            viewModel.recentSessions.insert(session, at: 0)
            showUndoToast = false
            undoPending = nil
        }
        // The underlying data was already deleted from SwiftData — re-save it
        do {
            try GymRepository.shared.saveSession(session)
        } catch {
            viewModel.errorMessage = error.localizedDescription
        }
    }

    // MARK: - Archive

    private func archiveSession(_ session: WorkoutSession) {
        var ids = archivedSessionIds
        ids.insert(session.id)
        archivedIdsRaw = ids.joined(separator: ",")
        viewModel.archivedSessionIds = ids
    }
}

// MARK: - RecentFilterChip

private struct RecentFilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                .foregroundStyle(isSelected ? .black : Color.kineticsSubtext)
                .padding(.horizontal, 13)
                .padding(.vertical, 7)
                .background(
                    Capsule()
                        .fill(isSelected ? Color.kineticsBlue : Color.clear)
                        .overlay(
                            Capsule()
                                .strokeBorder(
                                    isSelected ? Color.clear : Color.kineticsBlue.opacity(0.3),
                                    lineWidth: 1
                                )
                        )
                )
                .animation(.spring(duration: 0.2), value: isSelected)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - StartWorkoutBigButton

private struct StartWorkoutBigButton: View {
    let action: () -> Void
    @State private var isPressed = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.black)

                VStack(alignment: .leading, spacing: 1) {
                    Text("START WORKOUT")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.black)
                        .kerning(0.5)
                    Text("Choose routine or start empty")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.black.opacity(0.65))
                }

                Spacer()

                Image(systemName: "arrow.right")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.black.opacity(0.7))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
            .background(
                LinearGradient(
                    colors: [Color.kineticsBlue, Color(red: 0.0, green: 0.55, blue: 0.9)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: Color.kineticsBlue.opacity(0.45), radius: 18, x: 0, y: 8)
            .scaleEffect(isPressed ? 0.97 : 1.0)
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

// MARK: - RoutineQuickCard

private struct RoutineQuickCard: View {
    let routine: Routine
    let onStart: () -> Void

    @State private var isPressed = false

    var body: some View {
        Button(action: onStart) {
            VStack(alignment: .leading, spacing: 12) {
                // Icon
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.kineticsBlue.opacity(0.15))
                        .frame(width: 40, height: 40)
                    Image(systemName: "figure.strengthtraining.traditional")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(Color.kineticsBlue)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(routine.name)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    Text("\(routine.exerciseIds.count) exercises")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.kineticsSubtext)
                }

                Spacer(minLength: 0)

                // Start label
                HStack(spacing: 4) {
                    Text("Start")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.kineticsBlue)
                    Image(systemName: "play.fill")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Color.kineticsBlue)
                }
            }
            .padding(14)
            .frame(width: 140, height: 148, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(white: 0.09))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Color.kineticsBlue.opacity(0.2), lineWidth: 1)
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

// MARK: - CreateRoutineCard

private struct CreateRoutineCard: View {
    let onTap: () -> Void
    @State private var isPressed = false

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.kineticsPurple.opacity(0.15))
                        .frame(width: 40, height: 40)
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color.kineticsPurple)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("Create\nRoutine")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    Text("Save a plan")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.kineticsSubtext)
                }

                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(width: 140, height: 148, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(white: 0.09))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Color.kineticsPurple.opacity(0.2), lineWidth: 1)
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

// MARK: - RecentWorkoutCard

private struct RecentWorkoutCard: View {
    let session: WorkoutSession
    let isArchived: Bool
    let onTap: () -> Void
    let onRepeat: () -> Void

    private var durationText: String {
        let start = session.startedAt
        let end = session.endedAt ?? Date()
        let minutes = Int(end.timeIntervalSince(start)) / 60
        if minutes < 60 { return "\(minutes) min" }
        let h = minutes / 60
        let m = minutes % 60
        return m > 0 ? "\(h)h \(m)m" : "\(h)h"
    }

    private var dateLabel: String {
        let cal = Calendar.current
        if cal.isDateInToday(session.startedAt) { return "Today" }
        if cal.isDateInYesterday(session.startedAt) { return "Yesterday" }
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMM d"
        return f.string(from: session.startedAt)
    }

    private var timeLabel: String {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
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

    private var topExercises: [String] {
        Array(session.entries
            .sorted { $0.orderIndex < $1.orderIndex }
            .prefix(3)
            .map(\.exerciseName))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Archive label if applicable
            if isArchived {
                HStack(spacing: 6) {
                    Image(systemName: "archivebox")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color(white: 0.5))
                    Text("Archived")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color(white: 0.5))
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 4)
            }

            // Top info row
            Button(action: onTap) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(dateLabel)
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(.white)
                            Text(timeLabel)
                                .font(.system(size: 12, weight: .regular))
                                .foregroundStyle(Color.kineticsSubtext)
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 3) {
                            Text(durationText)
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundStyle(Color.kineticsBlue)
                            if session.isCompleted {
                                Text("Completed")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(Color.kineticsGreen)
                            }
                        }
                    }

                    // Stats row
                    HStack(spacing: 20) {
                        statPill(
                            value: formattedVolume,
                            label: "Volume",
                            color: Color.kineticsGreen
                        )
                        statPill(
                            value: "\(exerciseCount)",
                            label: "Exercises",
                            color: Color.kineticsBlue
                        )
                        statPill(
                            value: "\(session.entries.flatMap(\.sets).filter(\.isCompleted).count)",
                            label: "Sets",
                            color: Color.kineticsAmber
                        )
                    }

                    // Exercise chips
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
                                        Capsule().fill(Color(white: 0.12))
                                    )
                            }
                            if session.entries.count > 3 {
                                Text("+\(session.entries.count - 3)")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(Color.kineticsSubtext.opacity(0.6))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Capsule().fill(Color(white: 0.12)))
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, isArchived ? 4 : 16)
                .padding(.bottom, 12)
            }
            .buttonStyle(.plain)

            // Divider + Repeat button
            Divider()
                .background(Color.white.opacity(0.06))

            Button(action: onRepeat) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Repeat Workout")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(Color.kineticsBlue)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }
            .buttonStyle(.plain)
        }
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(white: 0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
                )
        )
        .opacity(isArchived ? 0.65 : 1.0)
    }

    private func statPill(value: String, label: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color.kineticsSubtext)
        }
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

// MARK: - ResumeWorkoutBanner

private struct ResumeWorkoutBanner: View {

    let session: WorkoutSession
    let onResume: () -> Void
    let onAbandon: () -> Void

    @State private var elapsedText: String = ""
    @State private var timerTask: Task<Void, Never>?

    private func updateElapsed() {
        let total = Int(Date().timeIntervalSince(session.startedAt))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            elapsedText = String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            elapsedText = String(format: "%02d:%02d", minutes, seconds)
        }
    }

    var body: some View {
        Button(action: onResume) {
            HStack(spacing: 0) {
                // Green left accent bar
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.kineticsGreen)
                    .frame(width: 4)
                    .padding(.vertical, 4)

                HStack(spacing: 12) {
                    // Pulsing dot
                    Circle()
                        .fill(Color.kineticsGreen)
                        .frame(width: 8, height: 8)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text("Workout In Progress")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.white)
                            Text("·")
                                .foregroundStyle(Color.kineticsSubtext)
                            Text(elapsedText)
                                .font(.system(size: 14, weight: .bold, design: .monospaced))
                                .foregroundStyle(Color.kineticsGreen)
                                .contentTransition(.numericText())
                        }
                        Text("Tap to resume")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color.kineticsSubtext)
                    }

                    Spacer()

                    // Dismiss / abandon button
                    Button {
                        onAbandon()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.kineticsSubtext)
                            .padding(8)
                            .background(Circle().fill(Color(white: 0.15)))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(white: 0.09))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Color.kineticsGreen.opacity(0.35), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .onAppear {
            updateElapsed()
            timerTask = Task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(1))
                    guard !Task.isCancelled else { return }
                    updateElapsed()
                }
            }
        }
        .onDisappear {
            timerTask?.cancel()
            timerTask = nil
        }
        .animation(.linear(duration: 0.25), value: elapsedText)
    }
}

// MARK: - StartWorkoutPickerSheet

struct StartWorkoutPickerSheet: View {

    @Environment(\.dismiss) private var dismiss

    let activePlan: WeeklyPlan?
    let routines: [Routine]
    let lastSession: WorkoutSession?
    let onStartBlank: () -> Void
    let onStartRoutine: (Routine) -> Void
    let onRepeatLast: (WorkoutSession) -> Void
    let userId: String

    @State private var showRoutinePicker = false

    private var todayRoutine: Routine? {
        let dow = Calendar.current.component(.weekday, from: Date()) - 1
        guard let slot = activePlan?.slots.first(where: { $0.dayOfWeek == dow }),
              let routineId = slot.routineId else { return nil }
        return routines.first { $0.id == routineId }
    }

    private var lastSessionLabel: String {
        guard let session = lastSession else { return "No recent workout" }
        let cal = Calendar.current
        if cal.isDateInYesterday(session.startedAt) { return "yesterday" }
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        return formatter.string(from: session.startedAt).lowercased()
    }

    private var lastSessionRoutineName: String {
        guard let session = lastSession else { return "" }
        if let first = session.entries.first {
            // Use the first exercise's name as a hint, or fall back to generic label
            return first.exerciseName.isEmpty ? "Last Workout" : "Last Workout"
        }
        return "Last Workout"
    }

    var body: some View {
        ZStack {
            Color(white: 0.06).ignoresSafeArea()

            VStack(spacing: 0) {
                // Pull bar
                Capsule()
                    .fill(Color(white: 0.28))
                    .frame(width: 36, height: 4)
                    .padding(.top, 10)
                    .padding(.bottom, 18)

                Text("START A WORKOUT")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.kineticsSubtext)
                    .kerning(1.0)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 14)

                VStack(spacing: 0) {
                    // Row 1: Today's Plan
                    pickerRow(
                        icon: "calendar",
                        iconColor: Color.kineticsBlue,
                        title: todayRoutine != nil ? "Today's Plan" : "Today's Plan",
                        subtitle: todayRoutine.map { "\($0.name) — from My Split" } ?? "No routine assigned for today",
                        isEnabled: todayRoutine != nil,
                        action: {
                            if let routine = todayRoutine {
                                dismiss()
                                onStartRoutine(routine)
                            }
                        }
                    )

                    rowDivider

                    // Row 2: Choose Routine
                    pickerRow(
                        icon: "list.bullet.clipboard",
                        iconColor: Color.kineticsPurple,
                        title: "Choose Routine",
                        subtitle: "Pick from your saved routines",
                        isEnabled: true,
                        action: { showRoutinePicker = true }
                    )

                    rowDivider

                    // Row 3: Repeat Last Workout
                    pickerRow(
                        icon: "arrow.clockwise",
                        iconColor: Color.kineticsAmber,
                        title: "Repeat Last Workout",
                        subtitle: lastSession != nil ? "\(lastSessionRoutineName) — \(lastSessionLabel)" : "No recent workout found",
                        isEnabled: lastSession != nil,
                        action: {
                            if let session = lastSession {
                                dismiss()
                                onRepeatLast(session)
                            }
                        }
                    )

                    rowDivider

                    // Row 4: Start Blank Session
                    pickerRow(
                        icon: "plus",
                        iconColor: Color(white: 0.55),
                        title: "Start Blank Session",
                        subtitle: "Add exercises as you go",
                        isEnabled: true,
                        action: {
                            dismiss()
                            onStartBlank()
                        }
                    )
                }
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(white: 0.1))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.07), lineWidth: 1)
                        )
                )
                .padding(.horizontal, 16)

                Spacer()
            }
        }
        .presentationDetents([.height(340)])
        .presentationBackground(Color(white: 0.06))
        .sheet(isPresented: $showRoutinePicker) {
            RoutinePickerSheet(
                routines: routines,
                onSelect: { routine in
                    dismiss()
                    onStartRoutine(routine)
                }
            )
        }
    }

    // MARK: - Row Builder

    private func pickerRow(
        icon: String,
        iconColor: Color,
        title: String,
        subtitle: String,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(iconColor.opacity(isEnabled ? 0.18 : 0.08))
                        .frame(width: 40, height: 40)
                    Image(systemName: icon)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(iconColor.opacity(isEnabled ? 1.0 : 0.35))
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(isEnabled ? .white : Color.kineticsSubtext)
                    Text(subtitle)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(Color.kineticsSubtext.opacity(isEnabled ? 1.0 : 0.55))
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isEnabled ? Color.kineticsSubtext.opacity(0.6) : Color.kineticsSubtext.opacity(0.2))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }

    private var rowDivider: some View {
        Divider()
            .background(Color.white.opacity(0.06))
            .padding(.leading, 70)
    }
}

// MARK: - RoutinePickerSheet

private struct RoutinePickerSheet: View {

    @Environment(\.dismiss) private var dismiss

    let routines: [Routine]
    let onSelect: (Routine) -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                if routines.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "list.bullet.clipboard")
                            .font(.system(size: 36, weight: .light))
                            .foregroundStyle(Color.kineticsBlue.opacity(0.4))
                        Text("No routines yet")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                        Text("Create a routine from the Quick Start section")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.kineticsSubtext)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 32)
                } else {
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVStack(spacing: 10) {
                            ForEach(routines, id: \.id) { routine in
                                Button {
                                    onSelect(routine)
                                    dismiss()
                                } label: {
                                    HStack(spacing: 14) {
                                        ZStack {
                                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                .fill(Color.kineticsBlue.opacity(0.14))
                                                .frame(width: 44, height: 44)
                                            Image(systemName: "figure.strengthtraining.traditional")
                                                .font(.system(size: 18, weight: .medium))
                                                .foregroundStyle(Color.kineticsBlue)
                                        }

                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(routine.name)
                                                .font(.system(size: 15, weight: .semibold))
                                                .foregroundStyle(.white)
                                            Text("\(routine.exerciseIds.count) exercises")
                                                .font(.system(size: 12))
                                                .foregroundStyle(Color.kineticsSubtext)
                                        }

                                        Spacer()

                                        HStack(spacing: 3) {
                                            ForEach(routine.muscleGroups.prefix(3), id: \.rawValue) { mg in
                                                Circle().fill(mg.color).frame(width: 7, height: 7)
                                            }
                                        }

                                        Image(systemName: "play.circle.fill")
                                            .font(.system(size: 24))
                                            .foregroundStyle(Color.kineticsBlue)
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 13)
                                    .background(
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .fill(Color(white: 0.09))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                                    .strokeBorder(Color.white.opacity(0.07), lineWidth: 1)
                                            )
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                }
            }
            .navigationTitle("Choose Routine")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.black, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.kineticsSubtext)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(Color.black)
    }
}

// MARK: - StreakDetailSheet

private struct StreakDetailSheet: View {

    let currentStreak: Int
    let longestStreak: Int
    /// Weekday components (Sunday = 1 … Saturday = 7) for days trained this week.
    let trainedDaysThisWeek: Set<Int>

    @Environment(\.dismiss) private var dismiss
    @State private var animatedStreak: Int = 0

    // MARK: - Milestone logic

    private var nextMilestone: Int {
        let milestones = [7, 14, 30, 60, 90, 180, 365]
        return milestones.first { $0 > currentStreak } ?? ((currentStreak / 30 + 1) * 30)
    }

    private var milestoneProgress: Double {
        let previous: Int
        let milestones = [7, 14, 30, 60, 90, 180, 365]
        if let idx = milestones.firstIndex(where: { $0 > currentStreak }), idx > 0 {
            previous = milestones[idx - 1]
        } else if currentStreak >= 365 {
            previous = (currentStreak / 30) * 30
        } else {
            previous = 0
        }
        let range = nextMilestone - previous
        guard range > 0 else { return 1 }
        return min(1, Double(currentStreak - previous) / Double(range))
    }

    private var motivationalCopy: String {
        switch currentStreak {
        case 0: return "Start your streak today."
        case 1: return "One day down. Keep going."
        case 2 ..< 7: return "Building momentum. Don't break the chain."
        case 7 ..< 14: return "One week strong. Consistency is a superpower."
        case 14 ..< 30: return "Two weeks in. You're forming a real habit."
        case 30 ..< 60: return "A full month. Legendary consistency."
        case 60 ..< 90: return "Two months of grit. Respect."
        default: return "Elite. Most people don't make it here."
        }
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            Color(white: 0.05).ignoresSafeArea()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 28) {
                    // Drag handle
                    Capsule()
                        .fill(Color(white: 0.3))
                        .frame(width: 36, height: 4)
                        .padding(.top, 12)

                    // Big streak number
                    VStack(spacing: 4) {
                        HStack(alignment: .lastTextBaseline, spacing: 8) {
                            Text("\(animatedStreak)")
                                .font(.system(size: 80, weight: .black, design: .rounded))
                                .foregroundStyle(Color.kineticsAmber)
                                .contentTransition(.numericText())
                                .animation(.spring(duration: 0.6), value: animatedStreak)

                            Image(systemName: "flame.fill")
                                .font(.system(size: 36, weight: .semibold))
                                .foregroundStyle(Color.kineticsAmber)
                                .symbolEffect(.bounce, value: animatedStreak)
                        }
                        Text("day streak")
                            .font(.system(size: 18, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color.kineticsSubtext)
                    }

                    // Motivational copy
                    Text(motivationalCopy)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white.opacity(0.75))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)

                    // Current vs longest
                    HStack(spacing: 16) {
                        streakStat(label: "Current", value: currentStreak, color: Color.kineticsAmber)
                        Rectangle()
                            .fill(Color(white: 0.2))
                            .frame(width: 1, height: 44)
                        streakStat(label: "Best", value: max(longestStreak, currentStreak), color: Color.kineticsGreen)
                    }
                    .padding(.vertical, 20)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color(white: 0.09))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .strokeBorder(Color.white.opacity(0.07), lineWidth: 1)
                            )
                    )
                    .padding(.horizontal, 24)

                    // 7-day mini calendar
                    weekMiniCalendar
                        .padding(.horizontal, 24)

                    // Milestone progress bar
                    milestoneSection
                        .padding(.horizontal, 24)

                    Spacer().frame(height: 20)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(Color(white: 0.05))
        .onAppear {
            // Animate the streak number in after a brief delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                withAnimation(.spring(duration: 0.6)) {
                    animatedStreak = currentStreak
                }
            }
        }
    }

    // MARK: - Streak stat tile

    private func streakStat(label: String, value: Int, color: Color) -> some View {
        VStack(spacing: 4) {
            Text("\(value)")
                .font(.system(size: 32, weight: .black, design: .rounded))
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.kineticsSubtext)
                .textCase(.uppercase)
                .kerning(0.6)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Week mini calendar

    private var weekMiniCalendar: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("This Week")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.kineticsSubtext)
                .textCase(.uppercase)
                .kerning(0.8)

            HStack(spacing: 6) {
                ForEach(weekDays, id: \.weekday) { info in
                    VStack(spacing: 5) {
                        Text(info.label)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Color.kineticsSubtext.opacity(0.7))

                        ZStack {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(
                                    info.trained
                                        ? Color.kineticsAmber.opacity(0.85)
                                        : info.isToday
                                            ? Color(white: 0.18)
                                            : Color(white: 0.11)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .strokeBorder(
                                            info.isToday && !info.trained
                                                ? Color.kineticsAmber.opacity(0.4)
                                                : Color.clear,
                                            lineWidth: 1
                                        )
                                )
                                .frame(width: 36, height: 36)

                            if info.trained {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(.black)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(white: 0.09))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.07), lineWidth: 1)
                )
        )
    }

    private struct WeekDayInfo {
        let weekday: Int  // 1 = Sunday
        let label: String
        let trained: Bool
        let isToday: Bool
    }

    private var weekDays: [WeekDayInfo] {
        let cal = Calendar.current
        let todayWeekday = cal.component(.weekday, from: Date())
        let labels = ["S", "M", "T", "W", "T", "F", "S"]
        return (1 ... 7).map { weekday in
            WeekDayInfo(
                weekday: weekday,
                label: labels[weekday - 1],
                trained: trainedDaysThisWeek.contains(weekday),
                isToday: weekday == todayWeekday
            )
        }
    }

    // MARK: - Milestone progress

    private var milestoneSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Next milestone")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.kineticsSubtext)
                    .textCase(.uppercase)
                    .kerning(0.8)
                Spacer()
                Text("\(nextMilestone) days")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.kineticsBlue)
            }

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color(white: 0.15))
                        .frame(height: 8)

                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color.kineticsAmber, Color.kineticsAmber.opacity(0.6)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geo.size.width * milestoneProgress, height: 8)
                        .animation(.spring(duration: 0.8).delay(0.3), value: milestoneProgress)
                }
            }
            .frame(height: 8)

            Text("\(currentStreak) / \(nextMilestone) days")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(Color.kineticsSubtext)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(white: 0.09))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.07), lineWidth: 1)
                )
        )
    }
}

// ExerciseLibraryView, ExerciseDetailView, and AddExerciseSheet live in ExerciseLibraryView.swift
