import SwiftUI
import SwiftData
import UIKit

// MARK: - ActiveGymSessionViewModel

@Observable
@MainActor
final class ActiveGymSessionViewModel {

    // MARK: - Session State

    var session: WorkoutSession
    var workoutName: String
    var elapsedTime: TimeInterval = 0
    var showExercisePicker = false
    var showFinishSheet = false
    var errorMessage: String?

    // MARK: - Expanded Cards

    /// Entry IDs that are currently expanded.
    var expandedEntries: Set<String> = []

    // MARK: - PR Tracking

    /// Exercise IDs that achieved a new PR this session.
    var newPRExerciseIds: Set<String> = []
    /// Map from exerciseId → (exerciseName, newWeight) for PRs hit this session.
    var sessionPRs: [(exerciseName: String, weight: Double, reps: Int)] = []

    // MARK: - Rest Timer State

    var restSecondsRemaining: Int?
    var restTimerInitialSeconds: Int = 90
    var showRestTimer = false
    var restTimerExpiredBanner = false

    // MARK: - Previous Bests (fetched async per exercise)

    /// exerciseId → (maxWeight, description e.g. "10 reps @ 80.0 kg")
    var previousBests: [String: (weight: Double, setDescription: String)] = [:]

    // MARK: - Superset grouping

    /// key = entryId → paired entryId
    var supersetLinks: [String: String] = [:]

    // MARK: - Volume PR tracking

    var previousMaxVolume: Double = 0

    // MARK: - Private

    private var timerTask: Task<Void, Never>?
    private var restTimerTask: Task<Void, Never>?

    // MARK: - Init

    init(session: WorkoutSession) {
        self.session = session
        let hour = Calendar.current.component(.hour, from: session.startedAt)
        switch hour {
        case 5..<12:  workoutName = "Morning Session"
        case 12..<17: workoutName = "Afternoon Session"
        case 17..<21: workoutName = "Evening Session"
        default:      workoutName = "Night Session"
        }
        if let first = session.entries.first {
            expandedEntries.insert(first.id)
        }
    }

    // MARK: - Workout Timer

    func startTimer() {
        timerTask?.cancel()
        elapsedTime = Date().timeIntervalSince(session.startedAt)
        timerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, let self else { return }
                self.elapsedTime = Date().timeIntervalSince(self.session.startedAt)
            }
        }
    }

    func stopTimer() {
        timerTask?.cancel()
        timerTask = nil
    }

    // MARK: - Rest Timer

    func startRestTimer(seconds: Int = 90) {
        restTimerTask?.cancel()
        restTimerInitialSeconds = seconds
        restSecondsRemaining = seconds
        showRestTimer = true
        restTimerExpiredBanner = false

        restTimerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, let self else { return }
                let current = self.restSecondsRemaining ?? 0
                if current <= 1 {
                    self.restSecondsRemaining = 0
                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.success)
                    self.restTimerExpiredBanner = true
                    try? await Task.sleep(for: .seconds(2.5))
                    guard !Task.isCancelled else { return }
                    self.restSecondsRemaining = nil
                    self.showRestTimer = false
                    self.restTimerExpiredBanner = false
                    return
                }
                self.restSecondsRemaining = current - 1
            }
        }
    }

    func adjustRestTimer(by delta: Int) {
        guard var secs = restSecondsRemaining else { return }
        secs = max(5, secs + delta)
        restSecondsRemaining = secs
        restTimerInitialSeconds = max(restTimerInitialSeconds, secs)
    }

    func cancelRestTimer() {
        restTimerTask?.cancel()
        restTimerTask = nil
        restSecondsRemaining = nil
        showRestTimer = false
        restTimerExpiredBanner = false
    }

    var formattedRest: String {
        guard let secs = restSecondsRemaining else { return "0:00" }
        let minutes = secs / 60
        let seconds = secs % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    var restRingProgress: Double {
        guard let secs = restSecondsRemaining, restTimerInitialSeconds > 0 else { return 0 }
        return Double(secs) / Double(restTimerInitialSeconds)
    }

    // MARK: - Previous Best Fetching

    func fetchPreviousBest(for entry: WorkoutExerciseEntry, userId: String) {
        let exerciseId = entry.exerciseId
        Task { [weak self] in
            guard let self else { return }
            let pr = await GymRepository.shared.fetchPersonalRecord(exerciseId: exerciseId, userId: userId)
            if let pr {
                let desc = "\(pr.reps) reps @ \(String(format: "%.1f", pr.weight)) kg"
                self.previousBests[exerciseId] = (weight: pr.weight, setDescription: desc)
            }
        }
    }

    // MARK: - Exercise Management

    func addExercise(_ exercise: Exercise) throws {
        let entry = WorkoutExerciseEntry(
            exerciseId: exercise.id,
            exerciseName: exercise.name,
            orderIndex: session.entries.count
        )
        let firstSet = WorkoutSet(setNumber: 1)
        entry.sets.append(firstSet)
        session.entries.append(entry)
        expandedEntries.insert(entry.id)
        try GymRepository.shared.saveSession(session)
    }

    // MARK: - Set Management

    func addSet(to entry: WorkoutExerciseEntry) throws {
        let lastWeight = entry.sets.last?.weight ?? 0
        let lastReps = entry.sets.last?.reps ?? 10
        let nextNumber = entry.sets.count + 1
        let newSet = try GymRepository.shared.addSet(
            to: entry,
            weight: lastWeight,
            reps: lastReps
        )
        newSet.setNumber = nextNumber
    }

    func markSetCompleted(_ set: WorkoutSet) throws {
        try GymRepository.shared.markSetCompleted(set)
        startRestTimer()
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
    }

    func checkAndRecordPR(for entry: WorkoutExerciseEntry, set: WorkoutSet, userId: String) async {
        guard set.weight > 0, set.reps > 0 else { return }
        let existingPR = await GymRepository.shared.fetchPersonalRecord(
            exerciseId: entry.exerciseId,
            userId: userId
        )
        if existingPR == nil || set.weight > (existingPR?.weight ?? 0) {
            let isNew = !newPRExerciseIds.contains(entry.exerciseId)
            newPRExerciseIds.insert(entry.exerciseId)
            if isNew || set.weight > (sessionPRs.first(where: { _ in true })?.weight ?? 0) {
                sessionPRs.removeAll { $0.exerciseName == entry.exerciseName }
                sessionPRs.append((exerciseName: entry.exerciseName, weight: set.weight, reps: set.reps))
            }
            if isNew {
                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.success)
            }
        }
    }

    func deleteSet(_ set: WorkoutSet, from entry: WorkoutExerciseEntry) throws {
        try GymRepository.shared.deleteSet(set)
        let sorted = entry.sets.sorted { $0.setNumber < $1.setNumber }
        for (index, s) in sorted.enumerated() {
            s.setNumber = index + 1
        }
    }

    // MARK: - Superset Management

    func linkSuperset(entryA: WorkoutExerciseEntry, entryB: WorkoutExerciseEntry) {
        supersetLinks[entryA.id] = entryB.id
        supersetLinks[entryB.id] = entryA.id
    }

    func unlinkSuperset(entry: WorkoutExerciseEntry) {
        if let partner = supersetLinks[entry.id] {
            supersetLinks.removeValue(forKey: partner)
        }
        supersetLinks.removeValue(forKey: entry.id)
    }

    func isInSuperset(_ entry: WorkoutExerciseEntry) -> Bool {
        supersetLinks[entry.id] != nil
    }

    // MARK: - Session Completion

    func completeSession(userId: String) throws {
        stopTimer()
        cancelRestTimer()
        session.notes = workoutName

        var prMap: [String: (name: String, weight: Double, reps: Int)] = [:]
        for entry in session.entries {
            for set in entry.sets where set.isCompleted && set.weight > 0 && set.reps > 0 {
                let existing = try? GymRepository.shared.fetchPersonalRecords(userId: userId)
                    .first { $0.exerciseId == entry.exerciseId }
                if existing == nil || set.weight > (existing?.weight ?? 0) {
                    if let current = prMap[entry.exerciseId] {
                        if set.weight > current.weight {
                            prMap[entry.exerciseId] = (name: entry.exerciseName, weight: set.weight, reps: set.reps)
                        }
                    } else {
                        prMap[entry.exerciseId] = (name: entry.exerciseName, weight: set.weight, reps: set.reps)
                    }
                }
                try? GymRepository.shared.updatePersonalRecord(
                    userId: userId,
                    exerciseId: entry.exerciseId,
                    exerciseName: entry.exerciseName,
                    weight: set.weight,
                    reps: set.reps
                )
            }
        }
        sessionPRs = prMap.values.map { (exerciseName: $0.name, weight: $0.weight, reps: $0.reps) }
            .sorted { $0.exerciseName < $1.exerciseName }

        try GymRepository.shared.completeSession(session)
        let streak = (try? GymRepository.shared.calculateStreak(userId: userId)) ?? 0
        let durationMinutes = Int(elapsedTime) / 60
        WidgetDataStore.shared.updateStreak(streak)
        WidgetDataStore.shared.updateTodayStats(steps: 0, calories: 0, workoutMinutes: durationMinutes)
    }

    // MARK: - Computed

    var formattedElapsed: String {
        let total = Int(elapsedTime)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }

    var totalVolumeKg: Double {
        session.entries.flatMap(\.sets).filter(\.isCompleted).reduce(0) { $0 + $1.weight * Double($1.reps) }
    }

    var formattedTotalVolume: String {
        let volume = totalVolumeKg
        if volume >= 1000 {
            return String(format: "%.1f t", volume / 1000)
        }
        return String(format: "%.0f kg", volume)
    }

    var completedSetCount: Int {
        session.entries.flatMap(\.sets).filter(\.isCompleted).count
    }

    var exerciseCount: Int {
        session.entries.count
    }

    var sortedEntries: [WorkoutExerciseEntry] {
        session.entries.sorted { $0.orderIndex < $1.orderIndex }
    }

    var isVolumePR: Bool {
        previousMaxVolume > 0 && totalVolumeKg > previousMaxVolume
    }

    /// Estimated calories: MET 5.0 (resistance training) × 80 kg default body weight × duration hours.
    var estimatedCalories: Int {
        let hours = elapsedTime / 3600.0
        return Int(5.0 * 80.0 * hours)
    }
}

// MARK: - Epley 1RM

private func epley1RM(weight: Double, reps: Int) -> Double {
    guard reps > 0, weight > 0 else { return 0 }
    if reps == 1 { return weight }
    return weight * (1.0 + Double(reps) / 30.0)
}

// MARK: - Plate Calculation

private struct PlatePair: Identifiable {
    let id = UUID()
    let weightKg: Double
    let count: Int

    var color: Color {
        switch weightKg {
        case 25:  return Color(red: 0.88, green: 0.18, blue: 0.18)
        case 20:  return Color(red: 0.18, green: 0.38, blue: 0.88)
        case 15:  return Color(red: 0.95, green: 0.80, blue: 0.10)
        case 10:  return Color(red: 0.18, green: 0.78, blue: 0.28)
        case 5:   return Color(white: 0.88)
        default:  return Color(white: 0.22)
        }
    }
}

private func calculatePlates(totalKg: Double) -> (pairs: [PlatePair], isValid: Bool) {
    let barWeight = 20.0
    let plateOptions: [Double] = [25, 20, 15, 10, 5, 2.5]
    guard totalKg >= barWeight else { return ([], false) }

    var remaining = ((totalKg - barWeight) / 2.0 * 10).rounded() / 10
    var pairs: [PlatePair] = []

    for plate in plateOptions {
        if remaining >= plate {
            let count = Int(remaining / plate)
            pairs.append(PlatePair(weightKg: plate, count: count))
            remaining -= Double(count) * plate
            remaining = (remaining * 10).rounded() / 10
        }
    }

    return (pairs, remaining < 0.05)
}

// MARK: - ActiveGymSessionView

@MainActor
struct ActiveGymSessionView: View {

    let session: WorkoutSession
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: ActiveGymSessionViewModel
    @State private var isEditingName = false
    @FocusState private var nameFieldFocused: Bool

    init(session: WorkoutSession) {
        self.session = session
        self._viewModel = State(initialValue: ActiveGymSessionViewModel(session: session))
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.kineticsBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                headerBar
                exerciseScrollList
                bottomSummaryBar
            }

            if !viewModel.showRestTimer {
                addExerciseFAB
                    .transition(.scale.combined(with: .opacity))
            }

            if viewModel.showRestTimer {
                RestTimerOverlay(viewModel: viewModel)
                    .transition(.opacity)
                    .zIndex(10)
            }
        }
        .navigationBarBackButtonHidden()
        .onAppear {
            viewModel.startTimer()
            for entry in session.entries {
                viewModel.fetchPreviousBest(for: entry, userId: session.userId)
            }
            Task {
                let sessions = await GymRepository.shared.fetchWorkoutSessions(userId: session.userId)
                let completed = sessions.filter { $0.isCompleted && $0.id != session.id }
                viewModel.previousMaxVolume = completed.map(\.totalVolumeKg).max() ?? 0
            }
        }
        .onDisappear { viewModel.stopTimer() }
        .onTapGesture {
            nameFieldFocused = false
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                            to: nil, from: nil, for: nil)
        }
        .sheet(isPresented: $viewModel.showExercisePicker) {
            ExercisePickerView { exercise in
                try viewModel.addExercise(exercise)
                if let last = session.entries.last {
                    viewModel.fetchPreviousBest(for: last, userId: session.userId)
                }
            }
        }
        .sheet(isPresented: $viewModel.showFinishSheet) {
            FinishWorkoutSheet(viewModel: viewModel, onSave: {
                do {
                    try viewModel.completeSession(userId: session.userId)
                    dismiss()
                } catch {
                    viewModel.errorMessage = error.localizedDescription
                    viewModel.showFinishSheet = false
                }
            }, onDiscard: {
                dismiss()
            })
        }
        .alert("Error", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .animation(.spring(duration: 0.3), value: viewModel.showRestTimer)
        .animation(.spring(duration: 0.25), value: viewModel.exerciseCount)
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        HStack(spacing: 12) {
            Group {
                if isEditingName {
                    TextField("Workout name", text: $viewModel.workoutName)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .focused($nameFieldFocused)
                        .submitLabel(.done)
                        .onSubmit { isEditingName = false }
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Button {
                        isEditingName = true
                        nameFieldFocused = true
                    } label: {
                        HStack(spacing: 6) {
                            Text(viewModel.workoutName)
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                            Image(systemName: "pencil")
                                .font(.system(size: 12))
                                .foregroundStyle(Color.kineticsSubtext)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                }
            }

            Text(viewModel.formattedElapsed)
                .font(.system(size: 18, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.kineticsBlue)
                .contentTransition(.numericText())
                .animation(.linear(duration: 0.25), value: viewModel.formattedElapsed)
                .fixedSize()

            Button {
                viewModel.showFinishSheet = true
            } label: {
                Text("Finish")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Color.kineticsBlue, in: Capsule())
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.kineticsDark)
        .overlay(alignment: .bottom) {
            Divider().background(Color.kineticsSubtext.opacity(0.25))
        }
    }

    // MARK: - Exercise Scroll List

    private var exerciseScrollList: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(viewModel.sortedEntries, id: \.id) { entry in
                    ExerciseCard(
                        entry: entry,
                        isExpanded: viewModel.expandedEntries.contains(entry.id),
                        isInSuperset: viewModel.isInSuperset(entry),
                        previousBest: viewModel.previousBests[entry.exerciseId],
                        onToggleExpand: {
                            withAnimation(.spring(duration: 0.28)) {
                                if viewModel.expandedEntries.contains(entry.id) {
                                    viewModel.expandedEntries.remove(entry.id)
                                } else {
                                    viewModel.expandedEntries.insert(entry.id)
                                }
                            }
                        },
                        onLinkSuperset: {
                            let sorted = viewModel.sortedEntries
                            guard let idx = sorted.firstIndex(where: { $0.id == entry.id }),
                                  idx + 1 < sorted.count else { return }
                            viewModel.linkSuperset(entryA: entry, entryB: sorted[idx + 1])
                        },
                        onUnlinkSuperset: {
                            viewModel.unlinkSuperset(entry: entry)
                        },
                        viewModel: viewModel
                    )
                }
                Color.clear.frame(height: 100)
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
        }
    }

    // MARK: - FAB

    private var addExerciseFAB: some View {
        Button {
            viewModel.showExercisePicker = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "dumbbell.fill")
                    .font(.system(size: 16, weight: .semibold))
                Text("Add Exercise")
                    .font(.system(size: 15, weight: .semibold))
            }
            .foregroundStyle(.black)
            .padding(.horizontal, 22)
            .padding(.vertical, 14)
            .background(Color.kineticsBlue, in: Capsule())
            .shadow(color: Color.kineticsBlue.opacity(0.45), radius: 14, x: 0, y: 6)
        }
        .padding(.bottom, 82)
    }

    // MARK: - Bottom Summary Bar

    private var bottomSummaryBar: some View {
        HStack(spacing: 0) {
            summaryItem(
                title: "VOLUME",
                value: viewModel.totalVolumeKg > 0 ? viewModel.formattedTotalVolume : "—",
                color: Color.kineticsGreen
            )
            Divider().frame(height: 28).background(Color.kineticsSubtext.opacity(0.3))
            summaryItem(title: "EXERCISES", value: "\(viewModel.exerciseCount)", color: .white)
            Divider().frame(height: 28).background(Color.kineticsSubtext.opacity(0.3))
            summaryItem(title: "SETS DONE", value: "\(viewModel.completedSetCount)", color: .white)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color.kineticsDark)
        .overlay(alignment: .top) {
            Divider().background(Color.kineticsSubtext.opacity(0.25))
        }
    }

    private func summaryItem(title: String, value: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(color)
                .contentTransition(.numericText())
                .animation(.spring(duration: 0.3), value: value)
            Text(title)
                .font(.system(size: 9, weight: .semibold))
                .tracking(1.2)
                .foregroundStyle(Color.kineticsSubtext)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - ExerciseCard

private struct ExerciseCard: View {

    let entry: WorkoutExerciseEntry
    let isExpanded: Bool
    let isInSuperset: Bool
    let previousBest: (weight: Double, setDescription: String)?
    let onToggleExpand: () -> Void
    let onLinkSuperset: () -> Void
    let onUnlinkSuperset: () -> Void
    let viewModel: ActiveGymSessionViewModel

    @State private var isFlipped = false

    private var completedSets: Int { entry.sets.filter(\.isCompleted).count }
    private var totalSets: Int { entry.sets.count }
    private var entryVolume: Double {
        entry.sets.filter(\.isCompleted).reduce(0) { $0 + $1.weight * Double($1.reps) }
    }
    private var formattedEntryVolume: String {
        entryVolume > 0 ? String(format: "%.0f kg", entryVolume) : "—"
    }
    private var bestCompletedSet: WorkoutSet? {
        entry.sets.filter { $0.isCompleted && $0.weight > 0 }.max(by: { $0.weight < $1.weight })
    }
    private var allCompleted: Bool { completedSets == totalSets && totalSets > 0 }

    var body: some View {
        HStack(spacing: 0) {
            // Superset bracket
            if isInSuperset {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.kineticsBlue)
                    .frame(width: 3)
                    .padding(.vertical, 8)
                    .padding(.trailing, 6)
            }

            ZStack {
                cardFront
                    .opacity(isFlipped ? 0 : 1)
                    .rotation3DEffect(.degrees(isFlipped ? -180 : 0), axis: (x: 0, y: 1, z: 0))

                cardBack
                    .opacity(isFlipped ? 1 : 0)
                    .rotation3DEffect(.degrees(isFlipped ? 0 : 180), axis: (x: 0, y: 1, z: 0))
            }
            .animation(.spring(response: 0.45, dampingFraction: 0.75), value: isFlipped)
        }
        .background(Color.kineticsDark)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(
                    allCompleted
                        ? Color.kineticsGreen.opacity(0.3)
                        : isInSuperset
                            ? Color.kineticsBlue.opacity(0.25)
                            : Color.white.opacity(0.06),
                    lineWidth: 1
                )
        )
        .contextMenu {
            if isInSuperset {
                Button(role: .destructive, action: onUnlinkSuperset) {
                    Label("Remove from Superset", systemImage: "link.badge.minus")
                }
            } else {
                Button(action: onLinkSuperset) {
                    Label("Link as Superset with next", systemImage: "link")
                }
            }
        }
    }

    // MARK: Card Front

    private var cardFront: some View {
        VStack(spacing: 0) {
            cardHeader

            // Previous best row (shown when expanded and not all sets completed)
            if isExpanded, let best = previousBest, best.weight > 0, !allCompleted {
                HStack(spacing: 6) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.kineticsAmber)
                    Text("Last time: \(best.setDescription)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.kineticsAmber.opacity(0.9))
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(Color.kineticsAmber.opacity(0.07))
            }

            if isExpanded {
                VStack(spacing: 0) {
                    columnHeaders
                    let sortedSets = entry.sets.sorted { $0.setNumber < $1.setNumber }
                    ForEach(sortedSets, id: \.id) { set in
                        SetRow(
                            set: set,
                            onComplete: {
                                do {
                                    try viewModel.markSetCompleted(set)
                                } catch {
                                    viewModel.errorMessage = error.localizedDescription
                                }
                            },
                            onDelete: {
                                do {
                                    try viewModel.deleteSet(set, from: entry)
                                } catch {
                                    viewModel.errorMessage = error.localizedDescription
                                }
                            }
                        )
                        if set.id != sortedSets.last?.id {
                            Divider()
                                .background(Color.kineticsSubtext.opacity(0.12))
                                .padding(.horizontal, 14)
                        }
                    }
                    addSetButton
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    // MARK: Card Back

    private var cardBack: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.exerciseName)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                    Text("Exercise Info")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.kineticsBlue)
                }
                Spacer()
                Button {
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.75)) {
                        isFlipped = false
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(Color.kineticsSubtext)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)

            Divider()
                .background(Color.kineticsSubtext.opacity(0.18))
                .padding(.horizontal, 14)

            VStack(alignment: .leading, spacing: 8) {
                Text("TECHNIQUE CUES")
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(1.2)
                    .foregroundStyle(Color.kineticsSubtext)

                Text("Focus on full range of motion. Control the eccentric phase. Brace your core and maintain proper form throughout every rep.")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.75))
                    .lineSpacing(3)
            }
            .padding(.horizontal, 14)

            if let best = bestCompletedSet {
                HStack(spacing: 6) {
                    Image(systemName: "star.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.kineticsAmber)
                    Text("Best set today: \(String(format: "%.1f", best.weight)) kg × \(best.reps)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.kineticsAmber)
                }
                .padding(.horizontal, 14)
            }

            Spacer(minLength: 12)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Card Header

    private var cardHeader: some View {
        Button(action: onToggleExpand) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(entry.exerciseName)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    HStack(spacing: 8) {
                        HStack(spacing: 3) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(completedSets > 0 ? Color.kineticsGreen : Color.kineticsSubtext)
                            Text("\(completedSets)/\(totalSets) sets")
                                .font(.system(size: 12))
                                .foregroundStyle(Color.kineticsSubtext)
                        }
                        if entryVolume > 0 {
                            Text("·").foregroundStyle(Color.kineticsSubtext.opacity(0.5))
                            Text(formattedEntryVolume)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Color.kineticsGreen)
                        }
                    }
                }
                Spacer()

                // Info flip button
                Button {
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.75)) {
                        isFlipped.toggle()
                    }
                } label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: 16))
                        .foregroundStyle(Color.kineticsBlue.opacity(0.75))
                }
                .buttonStyle(.plain)

                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.kineticsSubtext)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
    }

    // MARK: Column Headers

    private var columnHeaders: some View {
        HStack(spacing: 0) {
            Text("SET").frame(width: 44, alignment: .center)
            Text("KG").frame(maxWidth: .infinity, alignment: .center)
            Text("REPS").frame(maxWidth: .infinity, alignment: .center)
            Text("RPE").frame(width: 46, alignment: .center)
            Color.clear.frame(width: 46)
        }
        .font(.system(size: 9, weight: .semibold))
        .tracking(1.5)
        .foregroundStyle(Color.kineticsSubtext)
        .padding(.horizontal, 14)
        .padding(.bottom, 4)
        .overlay(alignment: .top) {
            Divider().background(Color.kineticsSubtext.opacity(0.18))
        }
    }

    // MARK: Add Set Button

    private var addSetButton: some View {
        Button {
            do { try viewModel.addSet(to: entry) } catch { viewModel.errorMessage = error.localizedDescription }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "plus").font(.system(size: 12, weight: .bold))
                Text("Add Set").font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(Color.kineticsBlue)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
        .overlay(alignment: .top) { Divider().background(Color.kineticsSubtext.opacity(0.18)) }
    }
}

// MARK: - SetRow

private struct SetRow: View {

    let set: WorkoutSet
    let onComplete: () -> Void
    let onDelete: () -> Void

    @State private var weight: String
    @State private var reps: String
    @State private var showRPESheet = false
    @State private var showPlateCalc = false

    init(set: WorkoutSet, onComplete: @escaping () -> Void, onDelete: @escaping () -> Void) {
        self.set = set
        self.onComplete = onComplete
        self.onDelete = onDelete
        self._weight = State(initialValue: set.weight > 0 ? String(format: "%.1f", set.weight) : "")
        self._reps = State(initialValue: set.reps > 0 ? "\(set.reps)" : "")
    }

    private var estimated1RM: Double? {
        guard set.isCompleted,
              let w = Double(weight), w > 0,
              let r = Int(reps), r > 0 else { return nil }
        return epley1RM(weight: w, reps: r)
    }

    private var rpeColor: Color {
        guard set.rpe > 0 else { return Color.kineticsSubtext }
        switch set.rpe {
        case 0..<6: return Color.kineticsGreen
        case 6..<8: return Color.kineticsAmber
        default:    return Color.kineticsRed
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                // Set number badge
                ZStack {
                    Circle()
                        .fill(set.isCompleted
                              ? Color.kineticsGreen.opacity(0.2)
                              : Color.kineticsSubtext.opacity(0.12))
                        .frame(width: 28, height: 28)
                    Text("\(set.setNumber)")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(set.isCompleted ? Color.kineticsGreen : Color.kineticsSubtext)
                }
                .frame(width: 44, alignment: .center)

                // Weight input — long press for plate calculator
                TextField("0.0", text: $weight)
                    .font(.system(size: 16, weight: .semibold, design: .monospaced))
                    .foregroundStyle(set.isCompleted ? Color.kineticsGreen : .white)
                    .multilineTextAlignment(.center)
                    .keyboardType(.decimalPad)
                    .disabled(set.isCompleted)
                    .frame(maxWidth: .infinity)
                    .onLongPressGesture(minimumDuration: 0.5) {
                        let impact = UIImpactFeedbackGenerator(style: .light)
                        impact.impactOccurred()
                        showPlateCalc = true
                    }

                // Reps input
                TextField("0", text: $reps)
                    .font(.system(size: 16, weight: .semibold, design: .monospaced))
                    .foregroundStyle(set.isCompleted ? Color.kineticsGreen : .white)
                    .multilineTextAlignment(.center)
                    .keyboardType(.numberPad)
                    .frame(maxWidth: .infinity)
                    .disabled(set.isCompleted)

                // RPE button
                Button { showRPESheet = true } label: {
                    if set.rpe > 0 {
                        Text(String(format: "%.0f", set.rpe))
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(rpeColor)
                            .frame(width: 30, height: 20)
                            .background(rpeColor.opacity(0.15), in: Capsule())
                    } else {
                        Text("RPE")
                            .font(.system(size: 9, weight: .semibold))
                            .tracking(0.5)
                            .foregroundStyle(Color.kineticsSubtext.opacity(0.6))
                            .frame(width: 30, height: 20)
                            .background(Color.kineticsSubtext.opacity(0.08), in: Capsule())
                    }
                }
                .frame(width: 46, alignment: .center)
                .buttonStyle(.plain)

                // Complete button
                Button {
                    guard !set.isCompleted else { return }
                    let parsedWeight = Double(weight) ?? 0
                    let parsedReps = Int(reps) ?? 0
                    try? GymRepository.shared.updateSet(set, weight: parsedWeight, reps: parsedReps, rpe: set.rpe)
                    onComplete()
                } label: {
                    Image(systemName: set.isCompleted ? "checkmark.circle.fill" : "checkmark.circle")
                        .font(.system(size: 24))
                        .foregroundStyle(set.isCompleted ? Color.kineticsGreen : Color.kineticsSubtext)
                }
                .frame(width: 46, alignment: .center)
                .disabled(set.isCompleted)
            }
            .padding(.vertical, 11)
            .padding(.horizontal, 14)
            .background(set.isCompleted ? Color.kineticsGreen.opacity(0.07) : Color.clear)
            .animation(.easeInOut(duration: 0.2), value: set.isCompleted)

            // 1RM estimate row under completed sets
            if let orm = estimated1RM {
                HStack {
                    Spacer()
                    Text("Est. 1RM: \(String(format: "%.0f", orm)) kg")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.kineticsSubtext.opacity(0.65))
                        .padding(.trailing, 14)
                        .padding(.bottom, 5)
                }
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash.fill")
            }
        }
        .sheet(isPresented: $showRPESheet) {
            RPEPickerSheet(currentRPE: set.rpe) { newRPE in
                try? GymRepository.shared.updateSet(
                    set,
                    weight: Double(weight) ?? set.weight,
                    reps: Int(reps) ?? set.reps,
                    rpe: newRPE
                )
            }
        }
        .sheet(isPresented: $showPlateCalc) {
            PlateCalculatorSheet(weightString: weight)
        }
    }
}

// MARK: - RPEPickerSheet

private struct RPEPickerSheet: View {

    let currentRPE: Double
    let onSelect: (Double) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selected: Double

    init(currentRPE: Double, onSelect: @escaping (Double) -> Void) {
        self.currentRPE = currentRPE
        self.onSelect = onSelect
        self._selected = State(initialValue: currentRPE > 0 ? currentRPE : 7)
    }

    private func rpeColor(_ rpe: Double) -> Color {
        switch rpe {
        case 0..<6: return Color.kineticsGreen
        case 6..<8: return Color.kineticsAmber
        default:    return Color.kineticsRed
        }
    }

    private func rpeLabel(_ rpe: Double) -> String {
        switch Int(rpe) {
        case 1:  return "Very Easy"
        case 2:  return "Easy"
        case 3:  return "Moderate"
        case 4:  return "Somewhat Hard"
        case 5:  return "Hard"
        case 6:  return "Very Hard"
        case 7:  return "Heavy"
        case 8:  return "Very Heavy"
        case 9:  return "Near Max"
        case 10: return "Max Effort"
        default: return ""
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.kineticsBackground.ignoresSafeArea()

                VStack(spacing: 28) {
                    VStack(spacing: 6) {
                        Text(String(format: "%.0f", selected))
                            .font(.system(size: 64, weight: .bold, design: .rounded))
                            .foregroundStyle(rpeColor(selected))
                            .contentTransition(.numericText())
                            .animation(.spring(response: 0.35, dampingFraction: 0.72), value: selected)
                        Text(rpeLabel(selected))
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(rpeColor(selected).opacity(0.8))
                            .animation(.easeOut(duration: 0.15), value: selected)
                    }
                    .padding(.top, 8)

                    // Dial buttons 1–10
                    HStack(spacing: 6) {
                        ForEach(1...10, id: \.self) { rpe in
                            let r = Double(rpe)
                            Button {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.72)) {
                                    selected = r
                                }
                            } label: {
                                Text("\(rpe)")
                                    .font(.system(size: 14,
                                                  weight: selected == r ? .bold : .regular,
                                                  design: .rounded))
                                    .foregroundStyle(selected == r ? rpeColor(r) : Color.kineticsSubtext)
                                    .frame(width: 28, height: 28)
                                    .background(Circle().fill(selected == r
                                        ? rpeColor(r).opacity(0.18)
                                        : Color.kineticsDark))
                                    .overlay(Circle().strokeBorder(
                                        selected == r ? rpeColor(r) : Color.clear, lineWidth: 1.5))
                                    .scaleEffect(selected == r ? 1.15 : 1.0)
                                    .animation(.spring(response: 0.35, dampingFraction: 0.72), value: selected)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)

                    // Legend
                    HStack(spacing: 16) {
                        rpeLabel(color: Color.kineticsGreen, label: "1–5 Manageable")
                        rpeLabel(color: Color.kineticsAmber, label: "6–7 Hard")
                        rpeLabel(color: Color.kineticsRed, label: "8–10 Max")
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(Color.kineticsSubtext)

                    Button {
                        onSelect(selected)
                        dismiss()
                    } label: {
                        Text("Set RPE \(String(format: "%.0f", selected))")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(rpeColor(selected),
                                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .padding(.horizontal, 20)

                    if currentRPE > 0 {
                        Button {
                            onSelect(0)
                            dismiss()
                        } label: {
                            Text("Clear RPE")
                                .font(.system(size: 14))
                                .foregroundStyle(Color.kineticsSubtext)
                        }
                        .padding(.bottom, 8)
                    }
                }
            }
            .navigationTitle("Rate of Perceived Effort")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.kineticsDark, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.foregroundStyle(Color.kineticsSubtext)
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.kineticsBackground)
    }

    private func rpeLabel(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label)
        }
    }
}

// MARK: - PlateCalculatorSheet

private struct PlateCalculatorSheet: View {

    let weightString: String
    @Environment(\.dismiss) private var dismiss

    private var totalKg: Double { Double(weightString) ?? 0 }
    private var plates: (pairs: [PlatePair], isValid: Bool) { calculatePlates(totalKg: totalKg) }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.kineticsBackground.ignoresSafeArea()

                VStack(spacing: 24) {
                    VStack(spacing: 4) {
                        Text(String(format: "%.1f kg", totalKg))
                            .font(.system(size: 40, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                        Text("Olympic Barbell (20 kg bar)")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.kineticsSubtext)
                    }
                    .padding(.top, 8)

                    if plates.isValid {
                        barbellVisual(pairs: plates.pairs)

                        Divider()
                            .background(Color.kineticsSubtext.opacity(0.2))
                            .padding(.horizontal, 20)

                        VStack(alignment: .leading, spacing: 10) {
                            Text("EACH SIDE")
                                .font(.system(size: 10, weight: .semibold))
                                .tracking(1.5)
                                .foregroundStyle(Color.kineticsSubtext)
                                .padding(.horizontal, 20)

                            if plates.pairs.isEmpty {
                                Text("Bar only (20 kg)")
                                    .font(.system(size: 15))
                                    .foregroundStyle(Color.kineticsSubtext)
                                    .padding(.horizontal, 20)
                            } else {
                                ForEach(plates.pairs) { pair in
                                    HStack {
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(pair.color)
                                            .frame(width: 20, height: 20)
                                        Text("\(String(format: "%.1f", pair.weightKg)) kg × \(pair.count)")
                                            .font(.system(size: 15, weight: .semibold))
                                            .foregroundStyle(.white)
                                        Spacer()
                                        Text("= \(String(format: "%.1f", pair.weightKg * Double(pair.count))) kg/side")
                                            .font(.system(size: 13))
                                            .foregroundStyle(Color.kineticsSubtext)
                                    }
                                    .padding(.horizontal, 20)
                                }
                            }
                        }
                    } else {
                        VStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.system(size: 32))
                                .foregroundStyle(Color.kineticsAmber)
                            Text("Enter at least 20 kg (bar weight)")
                                .font(.system(size: 14))
                                .foregroundStyle(Color.kineticsSubtext)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.top, 20)
                    }

                    Spacer()
                }
            }
            .navigationTitle("Plate Calculator")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.kineticsDark, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }.foregroundStyle(Color.kineticsBlue)
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.kineticsBackground)
    }

    private func barbellVisual(pairs: [PlatePair]) -> some View {
        HStack(spacing: 2) {
            ForEach(pairs.reversed()) { pair in
                ForEach(0..<pair.count, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(pair.color)
                        .frame(width: pWidth(pair.weightKg), height: pHeight(pair.weightKg))
                }
            }
            Capsule().fill(Color(white: 0.4)).frame(width: 60, height: 12)
            ForEach(pairs) { pair in
                ForEach(0..<pair.count, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(pair.color)
                        .frame(width: pWidth(pair.weightKg), height: pHeight(pair.weightKg))
                }
            }
        }
        .frame(height: 64)
        .padding(.horizontal, 16)
    }

    private func pWidth(_ kg: Double) -> CGFloat {
        switch kg {
        case 25: return 14; case 20: return 13; case 15: return 12
        case 10: return 11; case 5: return 9; default: return 8
        }
    }

    private func pHeight(_ kg: Double) -> CGFloat {
        switch kg {
        case 25: return 58; case 20: return 52; case 15: return 46
        case 10: return 40; case 5: return 32; default: return 24
        }
    }
}

// MARK: - RestTimerOverlay

private struct RestTimerOverlay: View {

    let viewModel: ActiveGymSessionViewModel

    private let presets: [(label: String, seconds: Int)] = [
        ("45s", 45), ("1:00", 60), ("1:30", 90), ("2:00", 120), ("3:00", 180)
    ]

    var body: some View {
        ZStack {
            Color.black.opacity(0.78)
                .ignoresSafeArea()
                .onTapGesture { viewModel.cancelRestTimer() }

            VStack(spacing: 28) {
                Spacer()

                if viewModel.restTimerExpiredBanner {
                    Text("Time to go! 💪")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(Color.kineticsGreen.opacity(0.85), in: Capsule())
                        .transition(.scale.combined(with: .opacity))
                        .animation(.spring(response: 0.35, dampingFraction: 0.72),
                                   value: viewModel.restTimerExpiredBanner)
                }

                // Ring
                ZStack {
                    Circle()
                        .stroke(Color.kineticsBlue.opacity(0.12), lineWidth: 14)
                        .frame(width: 200, height: 200)

                    Circle()
                        .trim(from: 0, to: viewModel.restRingProgress)
                        .stroke(Color.kineticsBlue,
                                style: StrokeStyle(lineWidth: 14, lineCap: .round))
                        .frame(width: 200, height: 200)
                        .rotationEffect(.degrees(-90))
                        .shadow(color: Color.kineticsBlue.opacity(0.5), radius: 8)
                        .animation(.linear(duration: 1), value: viewModel.restSecondsRemaining)

                    VStack(spacing: 4) {
                        Text(viewModel.formattedRest)
                            .font(.system(size: 52, weight: .bold, design: .monospaced))
                            .foregroundStyle(.white)
                            .contentTransition(.numericText())
                            .animation(.linear(duration: 0.25), value: viewModel.formattedRest)
                        Text("remaining")
                            .font(.system(size: 12, weight: .regular))
                            .tracking(1)
                            .foregroundStyle(Color.kineticsSubtext)
                    }
                }

                // Adjust buttons
                HStack(spacing: 20) {
                    adjustBtn(label: "−30s") { viewModel.adjustRestTimer(by: -30) }
                    adjustBtn(label: "+30s") { viewModel.adjustRestTimer(by: 30) }
                }

                // Preset chips
                HStack(spacing: 8) {
                    ForEach(presets, id: \.seconds) { preset in
                        Button {
                            viewModel.startRestTimer(seconds: preset.seconds)
                        } label: {
                            Text(preset.label)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(
                                    viewModel.restTimerInitialSeconds == preset.seconds
                                        ? .black : Color.kineticsBlue)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(Capsule().fill(
                                    viewModel.restTimerInitialSeconds == preset.seconds
                                        ? Color.kineticsBlue
                                        : Color.kineticsBlue.opacity(0.13)))
                        }
                        .buttonStyle(.plain)
                    }
                }

                Button { viewModel.cancelRestTimer() } label: {
                    Text("Skip Rest")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.kineticsSubtext)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(Color.kineticsSubtext.opacity(0.1), in: Capsule())
                }

                Spacer()
            }
        }
    }

    private func adjustBtn(label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 72, height: 40)
                .background(Color.white.opacity(0.1),
                             in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - FinishWorkoutSheet

private struct FinishWorkoutSheet: View {

    let viewModel: ActiveGymSessionViewModel
    let onSave: () -> Void
    let onDiscard: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var notes: String = ""

    var body: some View {
        NavigationStack {
            ZStack {
                Color.kineticsBackground.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        // Header
                        VStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 52))
                                .foregroundStyle(Color.kineticsGreen)
                                .padding(.top, 8)

                            Text("Workout Complete!")
                                .font(.system(size: 26, weight: .bold))
                                .foregroundStyle(.white)

                            HStack(spacing: 4) {
                                Image(systemName: "clock").font(.system(size: 12))
                                    .foregroundStyle(Color.kineticsBlue)
                                Text(viewModel.formattedElapsed)
                                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(Color.kineticsBlue)
                                Text("·").foregroundStyle(Color.kineticsSubtext)
                                Text(viewModel.workoutName)
                                    .font(.system(size: 14))
                                    .foregroundStyle(Color.kineticsSubtext)
                            }

                            // Volume PR badge
                            if viewModel.isVolumePR {
                                HStack(spacing: 6) {
                                    Image(systemName: "chart.line.uptrend.xyaxis")
                                        .font(.system(size: 12))
                                    Text("Volume PR — Best session ever!")
                                        .font(.system(size: 12, weight: .semibold))
                                }
                                .foregroundStyle(.black)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 7)
                                .background(Color.kineticsGreen, in: Capsule())
                            }
                        }
                        .frame(maxWidth: .infinity)

                        // Stats
                        HStack(spacing: 12) {
                            finishStatCard(icon: "scalemass.fill",
                                           value: viewModel.totalVolumeKg > 0 ? viewModel.formattedTotalVolume : "—",
                                           label: "Volume", color: Color.kineticsGreen)
                            finishStatCard(icon: "dumbbell.fill",
                                           value: "\(viewModel.exerciseCount)",
                                           label: "Exercises", color: Color.kineticsBlue)
                        }
                        HStack(spacing: 12) {
                            finishStatCard(icon: "checkmark.circle.fill",
                                           value: "\(viewModel.completedSetCount)",
                                           label: "Sets Done", color: Color.kineticsPurple)
                            finishStatCard(icon: "flame.fill",
                                           value: "\(viewModel.estimatedCalories) kcal",
                                           label: "Est. Calories", color: Color.kineticsAmber)
                        }

                        // Best sets per exercise
                        let bestSets = bestSetsPerExercise()
                        if !bestSets.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack(spacing: 6) {
                                    Image(systemName: "star.fill")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(Color.kineticsBlue)
                                    Text("BEST SETS")
                                        .font(.system(size: 10, weight: .semibold))
                                        .tracking(1.5)
                                        .foregroundStyle(Color.kineticsBlue)
                                }
                                ForEach(bestSets, id: \.exerciseName) { item in
                                    HStack {
                                        Text("✦")
                                            .font(.system(size: 10))
                                            .foregroundStyle(Color.kineticsBlue)
                                        Text(item.exerciseName)
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundStyle(.white)
                                        Spacer()
                                        Text("\(String(format: "%.1f", item.weight)) kg × \(item.reps)")
                                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                                            .foregroundStyle(Color.kineticsBlue)
                                    }
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 9)
                                    .background(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .fill(Color.kineticsBlue.opacity(0.07))
                                    )
                                }
                            }
                        }

                        // PRs
                        if !viewModel.sessionPRs.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack(spacing: 6) {
                                    Image(systemName: "trophy.fill")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(Color.kineticsAmber)
                                    Text("PERSONAL RECORDS")
                                        .font(.system(size: 10, weight: .semibold))
                                        .tracking(1.5)
                                        .foregroundStyle(Color.kineticsAmber)
                                }
                                VStack(spacing: 8) {
                                    ForEach(viewModel.sessionPRs, id: \.exerciseName) { pr in
                                        HStack(spacing: 12) {
                                            ZStack {
                                                Circle().fill(Color.kineticsAmber.opacity(0.15))
                                                    .frame(width: 36, height: 36)
                                                Image(systemName: "trophy.fill")
                                                    .font(.system(size: 14))
                                                    .foregroundStyle(Color.kineticsAmber)
                                            }
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(pr.exerciseName)
                                                    .font(.system(size: 13, weight: .semibold))
                                                    .foregroundStyle(.white)
                                                Text("New PR: \(String(format: "%.1f", pr.weight)) kg × \(pr.reps) reps")
                                                    .font(.system(size: 11))
                                                    .foregroundStyle(Color.kineticsAmber.opacity(0.9))
                                            }
                                            Spacer()
                                        }
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 10)
                                        .background(
                                            RoundedRectangle(cornerRadius: 12)
                                                .fill(Color.kineticsAmber.opacity(0.08))
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 12)
                                                        .strokeBorder(Color.kineticsAmber.opacity(0.2), lineWidth: 1)
                                                )
                                        )
                                    }
                                }
                            }
                        }

                        // Notes
                        VStack(alignment: .leading, spacing: 8) {
                            Text("NOTES")
                                .font(.system(size: 10, weight: .semibold))
                                .tracking(1.5)
                                .foregroundStyle(Color.kineticsSubtext)
                            TextField("How did it go? (optional)", text: $notes, axis: .vertical)
                                .font(.system(size: 14))
                                .foregroundStyle(.white)
                                .lineLimit(3...6)
                                .padding(12)
                                .background(Color.kineticsDark,
                                             in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }

                        Button {
                            if !notes.isEmpty { viewModel.session.notes = notes }
                            onSave()
                        } label: {
                            Text("Save Workout")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(.black)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(Color.kineticsGreen,
                                             in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }

                        Button {
                            dismiss()
                            onDiscard()
                        } label: {
                            Text("Discard Workout")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(Color.kineticsRed.opacity(0.85))
                        }
                        .padding(.bottom, 24)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.kineticsDark, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.foregroundStyle(Color.kineticsSubtext)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.kineticsBackground)
    }

    private func bestSetsPerExercise() -> [(exerciseName: String, weight: Double, reps: Int)] {
        var result: [(exerciseName: String, weight: Double, reps: Int)] = []
        for entry in viewModel.session.entries {
            guard let best = entry.sets.filter({ $0.isCompleted && $0.weight > 0 })
                .max(by: { $0.weight < $1.weight }) else { continue }
            result.append((exerciseName: entry.exerciseName, weight: best.weight, reps: best.reps))
        }
        return result.sorted { $0.exerciseName < $1.exerciseName }
    }

    private func finishStatCard(icon: String, value: String, label: String, color: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 22))
                .foregroundStyle(color).frame(width: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(value).font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text(label).font(.system(size: 11)).foregroundStyle(Color.kineticsSubtext)
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.kineticsDark, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - ExercisePickerView

@MainActor
struct ExercisePickerView: View {

    let onSelect: (Exercise) throws -> Void

    @State private var exercises: [Exercise] = []
    @State private var searchText = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.kineticsBackground.ignoresSafeArea()
                if exercises.isEmpty { emptyState } else { exerciseList }
            }
            .navigationTitle("Add Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.kineticsDark, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.foregroundStyle(Color.kineticsSubtext)
                }
            }
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "Search exercises")
        }
        .task {
            exercises = (try? GymRepository.shared.fetchExercises(filter: nil, category: nil)) ?? []
        }
        .onChange(of: searchText) { _, newValue in
            let filter = newValue.isEmpty ? nil : newValue
            exercises = (try? GymRepository.shared.fetchExercises(filter: filter, category: nil)) ?? []
        }
    }

    private var exerciseList: some View {
        ScrollView {
            LazyVStack(spacing: 6) {
                ForEach(exercises, id: \.id) { exercise in
                    Button {
                        try? onSelect(exercise)
                        dismiss()
                    } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(exercise.name)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .multilineTextAlignment(.leading)
                                Text(exercise.primaryMuscle)
                                    .font(.system(size: 12))
                                    .foregroundStyle(Color.kineticsSubtext)
                            }
                            Spacer()
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 20))
                                .foregroundStyle(Color.kineticsBlue)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(Color.kineticsDark,
                                     in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "dumbbell.fill")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(Color.kineticsBlue.opacity(0.4))
            Text(searchText.isEmpty ? "No exercises found" : "No results for \"\(searchText)\"")
                .font(.headline).foregroundStyle(.white)
            Text(searchText.isEmpty
                 ? "Tap 'Add Exercise' in the library to seed exercises."
                 : "Try a different search term.")
                .font(.subheadline)
                .foregroundStyle(Color.kineticsSubtext)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 40)
    }
}
