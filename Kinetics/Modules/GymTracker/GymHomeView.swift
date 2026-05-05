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
                StartWorkoutSheet(
                    activePlan: viewModel.activePlan,
                    routines: viewModel.routines,
                    onStart: { routine in
                        if let r = routine {
                            startRoutineSession(r)
                        } else {
                            startEmptySession()
                        }
                    },
                    userId: uid
                )
            }
            .sheet(item: $daySlotToStart) { _ in
                StartWorkoutSheet(
                    activePlan: viewModel.activePlan,
                    routines: viewModel.routines,
                    onStart: { routine in
                        if let r = routine {
                            startRoutineSession(r)
                        } else {
                            startEmptySession()
                        }
                    },
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
                streakBadge
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

// ExerciseLibraryView, ExerciseDetailView, and AddExerciseSheet live in ExerciseLibraryView.swift
