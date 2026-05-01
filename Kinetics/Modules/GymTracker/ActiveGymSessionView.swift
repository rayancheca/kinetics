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

    // MARK: - Private

    private var timerTask: Task<Void, Never>?
    private var restTimerTask: Task<Void, Never>?

    // MARK: - Init

    init(session: WorkoutSession) {
        self.session = session
        // Use a friendly default name derived from the time of day.
        let hour = Calendar.current.component(.hour, from: session.startedAt)
        switch hour {
        case 5..<12:  workoutName = "Morning Session"
        case 12..<17: workoutName = "Afternoon Session"
        case 17..<21: workoutName = "Evening Session"
        default:      workoutName = "Night Session"
        }
        // Expand the first entry by default so the UI isn't completely empty.
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

        restTimerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, let self else { return }
                let current = self.restSecondsRemaining ?? 0
                if current <= 1 {
                    self.restSecondsRemaining = nil
                    self.showRestTimer = false
                    return
                }
                self.restSecondsRemaining = current - 1
            }
        }
    }

    func cancelRestTimer() {
        restTimerTask?.cancel()
        restTimerTask = nil
        restSecondsRemaining = nil
        showRestTimer = false
    }

    var formattedRest: String {
        guard let secs = restSecondsRemaining else { return "0:00" }
        let minutes = secs / 60
        let seconds = secs % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    /// Progress from 1.0 (full) down to 0.0 (empty).
    var restRingProgress: Double {
        guard let secs = restSecondsRemaining, restTimerInitialSeconds > 0 else { return 0 }
        return Double(secs) / Double(restTimerInitialSeconds)
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
        // Auto-expand the newly added entry.
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
        // Haptic feedback: medium impact on set completion
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
    }

    /// Checks if the completed set is a new PR for this exercise and records it.
    func checkAndRecordPR(for entry: WorkoutExerciseEntry, set: WorkoutSet, userId: String) async {
        guard set.weight > 0, set.reps > 0 else { return }
        let existingPR = await GymRepository.shared.fetchPersonalRecord(
            exerciseId: entry.exerciseId,
            userId: userId
        )
        if existingPR == nil || set.weight > (existingPR?.weight ?? 0) {
            // New PR — record it for the finish sheet and give haptic celebration
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

    // MARK: - Session Completion

    func completeSession(userId: String) throws {
        stopTimer()
        cancelRestTimer()
        session.notes = workoutName

        // Build the sessionPRs list by checking what actually set records.
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
        // Refresh widget data — fire-and-forget, failure is non-fatal.
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
}

// MARK: - ActiveGymSessionView

@MainActor
struct ActiveGymSessionView: View {

    // MARK: - Properties

    let session: WorkoutSession
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: ActiveGymSessionViewModel
    @State private var isEditingName = false
    @FocusState private var nameFieldFocused: Bool

    // MARK: - Init

    init(session: WorkoutSession) {
        self.session = session
        self._viewModel = State(initialValue: ActiveGymSessionViewModel(session: session))
    }

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.kineticsBackground
                .ignoresSafeArea()

            VStack(spacing: 0) {
                headerBar
                exerciseScrollList
                bottomSummaryBar
            }

            // Floating Add Exercise Button
            if !viewModel.showRestTimer {
                addExerciseFAB
                    .transition(.scale.combined(with: .opacity))
            }

            // Rest Timer — slides up from bottom
            if viewModel.showRestTimer {
                RestTimerPanel(viewModel: viewModel)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(10)
            }
        }
        .navigationBarBackButtonHidden()
        .onAppear { viewModel.startTimer() }
        .onDisappear { viewModel.stopTimer() }
        .onTapGesture {
            nameFieldFocused = false
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                            to: nil, from: nil, for: nil)
        }
        .sheet(isPresented: $viewModel.showExercisePicker) {
            ExercisePickerView { exercise in
                try viewModel.addExercise(exercise)
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
            // Workout name — tappable to edit
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

            // Live timer
            Text(viewModel.formattedElapsed)
                .font(.system(size: 18, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.kineticsBlue)
                .contentTransition(.numericText())
                .animation(.linear(duration: 0.25), value: viewModel.formattedElapsed)
                .fixedSize()

            // Finish button
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
                        onToggleExpand: {
                            withAnimation(.spring(duration: 0.28)) {
                                if viewModel.expandedEntries.contains(entry.id) {
                                    viewModel.expandedEntries.remove(entry.id)
                                } else {
                                    viewModel.expandedEntries.insert(entry.id)
                                }
                            }
                        },
                        viewModel: viewModel
                    )
                }

                // Bottom padding so FAB doesn't cover last card
                Color.clear.frame(height: 100)
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
        }
    }

    // MARK: - Floating Add Exercise Button

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

            Divider()
                .frame(height: 28)
                .background(Color.kineticsSubtext.opacity(0.3))

            summaryItem(
                title: "EXERCISES",
                value: "\(viewModel.exerciseCount)",
                color: .white
            )

            Divider()
                .frame(height: 28)
                .background(Color.kineticsSubtext.opacity(0.3))

            summaryItem(
                title: "SETS DONE",
                value: "\(viewModel.completedSetCount)",
                color: .white
            )
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
    let onToggleExpand: () -> Void
    let viewModel: ActiveGymSessionViewModel

    private var completedSets: Int {
        entry.sets.filter(\.isCompleted).count
    }

    private var totalSets: Int {
        entry.sets.count
    }

    private var entryVolume: Double {
        entry.sets.filter(\.isCompleted).reduce(0) { $0 + $1.weight * Double($1.reps) }
    }

    private var formattedEntryVolume: String {
        entryVolume > 0 ? String(format: "%.0f kg", entryVolume) : "—"
    }

    /// Best weight from completed sets — used as previous-best hint.
    private var previousBestWeight: Double? {
        let weights = entry.sets.filter { $0.isCompleted && $0.weight > 0 }.map(\.weight)
        return weights.max()
    }

    var body: some View {
        VStack(spacing: 0) {
            // MARK: Card Header (always visible)
            cardHeader

            // MARK: Expanded Content
            if isExpanded {
                VStack(spacing: 0) {
                    // Column headers
                    columnHeaders

                    // Set rows
                    let sortedSets = entry.sets.sorted { $0.setNumber < $1.setNumber }
                    ForEach(sortedSets, id: \.id) { set in
                        SetRow(
                            set: set,
                            previousBestWeight: set.isCompleted ? nil : previousBestWeight,
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

                    // Add Set button
                    addSetButton
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(Color.kineticsDark)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(
                    completedSets == totalSets && totalSets > 0
                        ? Color.kineticsGreen.opacity(0.3)
                        : Color.white.opacity(0.06),
                    lineWidth: 1
                )
        )
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
                        // Set progress
                        HStack(spacing: 3) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(
                                    completedSets > 0 ? Color.kineticsGreen : Color.kineticsSubtext
                                )
                            Text("\(completedSets)/\(totalSets) sets")
                                .font(.system(size: 12))
                                .foregroundStyle(Color.kineticsSubtext)
                        }

                        if entryVolume > 0 {
                            Text("·")
                                .foregroundStyle(Color.kineticsSubtext.opacity(0.5))
                            Text(formattedEntryVolume)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Color.kineticsGreen)
                        }
                    }
                }

                Spacer()

                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.kineticsSubtext)
                    .rotationEffect(.degrees(isExpanded ? 0 : 0))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
    }

    // MARK: Column Headers

    private var columnHeaders: some View {
        HStack(spacing: 0) {
            Text("SET")
                .frame(width: 44, alignment: .center)
            Text("KG")
                .frame(maxWidth: .infinity, alignment: .center)
            Text("REPS")
                .frame(maxWidth: .infinity, alignment: .center)
            Color.clear.frame(width: 46)
        }
        .font(.system(size: 9, weight: .semibold))
        .tracking(1.5)
        .foregroundStyle(Color.kineticsSubtext)
        .padding(.horizontal, 14)
        .padding(.bottom, 4)

        .overlay(alignment: .top) {
            Divider()
                .background(Color.kineticsSubtext.opacity(0.18))
        }
    }

    // MARK: Add Set Button

    private var addSetButton: some View {
        Button {
            do {
                try viewModel.addSet(to: entry)
            } catch {
                viewModel.errorMessage = error.localizedDescription
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .bold))
                Text("Add Set")
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(Color.kineticsBlue)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
        .overlay(alignment: .top) {
            Divider()
                .background(Color.kineticsSubtext.opacity(0.18))
        }
    }
}

// MARK: - SetRow

private struct SetRow: View {

    // MARK: - Properties

    let set: WorkoutSet
    let previousBestWeight: Double?
    let onComplete: () -> Void
    let onDelete: () -> Void

    @State private var weight: String
    @State private var reps: String

    // MARK: - Init

    init(
        set: WorkoutSet,
        previousBestWeight: Double? = nil,
        onComplete: @escaping () -> Void,
        onDelete: @escaping () -> Void
    ) {
        self.set = set
        self.previousBestWeight = previousBestWeight
        self.onComplete = onComplete
        self.onDelete = onDelete
        self._weight = State(initialValue: set.weight > 0 ? String(format: "%.1f", set.weight) : "")
        self._reps = State(initialValue: set.reps > 0 ? "\(set.reps)" : "")
    }

    // MARK: - Body

    var body: some View {
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

            // Weight input
            VStack(spacing: 1) {
                TextField(weightPlaceholder, text: $weight)
                    .font(.system(size: 16, weight: .semibold, design: .monospaced))
                    .foregroundStyle(set.isCompleted ? Color.kineticsGreen : .white)
                    .multilineTextAlignment(.center)
                    .keyboardType(.decimalPad)
                    .disabled(set.isCompleted)
                    .frame(maxWidth: .infinity)

                if let best = previousBestWeight, best > 0, !set.isCompleted {
                    Text("prev \(String(format: "%.1f", best))")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(Color.kineticsAmber.opacity(0.8))
                }
            }
            .frame(maxWidth: .infinity)

            // Reps input
            TextField("0", text: $reps)
                .font(.system(size: 16, weight: .semibold, design: .monospaced))
                .foregroundStyle(set.isCompleted ? Color.kineticsGreen : .white)
                .multilineTextAlignment(.center)
                .keyboardType(.numberPad)
                .frame(maxWidth: .infinity)
                .disabled(set.isCompleted)

            // Complete / done button
            Button {
                guard !set.isCompleted else { return }
                let parsedWeight = Double(weight) ?? 0
                let parsedReps = Int(reps) ?? 0
                do {
                    try GymRepository.shared.updateSet(set,
                                                       weight: parsedWeight,
                                                       reps: parsedReps,
                                                       rpe: set.rpe)
                } catch {
                    // Non-fatal — still complete the set to trigger rest timer.
                }
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
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete", systemImage: "trash.fill")
            }
        }
    }

    // MARK: - Helpers

    private var weightPlaceholder: String {
        guard let best = previousBestWeight, best > 0 else { return "0.0" }
        return String(format: "%.1f", best)
    }
}

// MARK: - RestTimerPanel

private struct RestTimerPanel: View {

    let viewModel: ActiveGymSessionViewModel

    private let presets: [(label: String, seconds: Int)] = [
        ("45s", 45), ("1:00", 60), ("1:30", 90), ("2:00", 120), ("3:00", 180)
    ]

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 18) {
                // Header row
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("REST TIMER")
                            .font(.system(size: 10, weight: .semibold))
                            .tracking(2)
                            .foregroundStyle(Color.kineticsSubtext)
                        Text("Take a breath")
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(Color.kineticsSubtext.opacity(0.7))
                    }
                    Spacer()
                    Button { viewModel.cancelRestTimer() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(Color.kineticsSubtext)
                    }
                }

                // Countdown ring + time
                ZStack {
                    // Track
                    Circle()
                        .stroke(Color.kineticsBlue.opacity(0.12), lineWidth: 10)
                        .frame(width: 112, height: 112)

                    // Fill
                    Circle()
                        .trim(from: 0, to: viewModel.restRingProgress)
                        .stroke(
                            Color.kineticsBlue,
                            style: StrokeStyle(lineWidth: 10, lineCap: .round)
                        )
                        .frame(width: 112, height: 112)
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 1), value: viewModel.restSecondsRemaining)

                    VStack(spacing: 0) {
                        Text(viewModel.formattedRest)
                            .font(.system(size: 28, weight: .bold, design: .monospaced))
                            .foregroundStyle(.white)
                            .contentTransition(.numericText())
                            .animation(.linear(duration: 0.25), value: viewModel.formattedRest)
                        Text("remaining")
                            .font(.system(size: 9, weight: .regular))
                            .foregroundStyle(Color.kineticsSubtext)
                    }
                }

                // Preset chips
                HStack(spacing: 6) {
                    ForEach(presets, id: \.seconds) { preset in
                        Button {
                            viewModel.startRestTimer(seconds: preset.seconds)
                        } label: {
                            Text(preset.label)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(
                                    viewModel.restTimerInitialSeconds == preset.seconds
                                        ? Color.black : Color.kineticsBlue
                                )
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(
                                    Capsule().fill(
                                        viewModel.restTimerInitialSeconds == preset.seconds
                                            ? Color.kineticsBlue
                                            : Color.kineticsBlue.opacity(0.13)
                                    )
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }

                // Skip
                Button { viewModel.cancelRestTimer() } label: {
                    Text("Skip Rest")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.kineticsSubtext)
                }
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 22)
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(Color.kineticsDark)
                    .overlay(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .strokeBorder(Color.kineticsBlue.opacity(0.22), lineWidth: 1)
                    )
            )
            .shadow(color: .black.opacity(0.55), radius: 28, x: 0, y: -10)
            .padding(.horizontal, 14)
            .padding(.bottom, 90)
        }
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
                        // Header trophy area
                        VStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 52))
                                .foregroundStyle(Color.kineticsGreen)
                                .padding(.top, 8)

                            Text("Workout Complete!")
                                .font(.system(size: 26, weight: .bold))
                                .foregroundStyle(.white)

                            HStack(spacing: 4) {
                                Image(systemName: "clock")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Color.kineticsBlue)
                                Text(viewModel.formattedElapsed)
                                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(Color.kineticsBlue)
                                Text("·")
                                    .foregroundStyle(Color.kineticsSubtext)
                                Text(viewModel.workoutName)
                                    .font(.system(size: 14))
                                    .foregroundStyle(Color.kineticsSubtext)
                            }
                        }
                        .frame(maxWidth: .infinity)

                        // Stats grid — 2×2
                        HStack(spacing: 12) {
                            finishStatCard(
                                icon: "scalemass.fill",
                                value: viewModel.totalVolumeKg > 0 ? viewModel.formattedTotalVolume : "—",
                                label: "Volume",
                                color: Color.kineticsGreen
                            )
                            finishStatCard(
                                icon: "dumbbell.fill",
                                value: "\(viewModel.exerciseCount)",
                                label: "Exercises",
                                color: Color.kineticsBlue
                            )
                        }

                        HStack(spacing: 12) {
                            finishStatCard(
                                icon: "checkmark.circle.fill",
                                value: "\(viewModel.completedSetCount)",
                                label: "Sets Done",
                                color: Color.kineticsPurple
                            )
                            finishStatCard(
                                icon: "trophy.fill",
                                value: "\(viewModel.sessionPRs.count)",
                                label: "New PRs",
                                color: Color.kineticsAmber
                            )
                        }

                        // Personal Records achieved this session
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
                                                Circle()
                                                    .fill(Color.kineticsAmber.opacity(0.15))
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

                        // Notes field
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
                                .background(Color.kineticsDark, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }

                        // Save button
                        Button {
                            if !notes.isEmpty {
                                viewModel.session.notes = notes
                            }
                            onSave()
                        } label: {
                            Text("Save Workout")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(.black)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(Color.kineticsGreen, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }

                        // Discard link
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
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.kineticsSubtext)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.kineticsBackground)
    }

    private func finishStatCard(
        icon: String,
        value: String,
        label: String,
        color: Color
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 22))
                .foregroundStyle(color)
                .frame(width: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text(label)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.kineticsSubtext)
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

    // MARK: - Properties

    let onSelect: (Exercise) throws -> Void

    @State private var exercises: [Exercise] = []
    @State private var searchText = ""
    @Environment(\.dismiss) private var dismiss

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                Color.kineticsBackground.ignoresSafeArea()

                if exercises.isEmpty {
                    emptyState
                } else {
                    exerciseList
                }
            }
            .navigationTitle("Add Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.kineticsDark, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.kineticsSubtext)
                }
            }
            .searchable(
                text: $searchText,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Search exercises"
            )
        }
        .task {
            exercises = (try? GymRepository.shared.fetchExercises(filter: nil, category: nil)) ?? []
        }
        .onChange(of: searchText) { _, newValue in
            let filter = newValue.isEmpty ? nil : newValue
            exercises = (try? GymRepository.shared.fetchExercises(filter: filter, category: nil)) ?? []
        }
    }

    // MARK: - Exercise List

    private var exerciseList: some View {
        ScrollView {
            LazyVStack(spacing: 6) {
                ForEach(exercises, id: \.id) { exercise in
                    exerciseRow(exercise)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    private func exerciseRow(_ exercise: Exercise) -> some View {
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
            .background(Color.kineticsDark, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "dumbbell.fill")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(Color.kineticsBlue.opacity(0.4))
            Text(searchText.isEmpty ? "No exercises found" : "No results for \"\(searchText)\"")
                .font(.headline)
                .foregroundStyle(.white)
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
