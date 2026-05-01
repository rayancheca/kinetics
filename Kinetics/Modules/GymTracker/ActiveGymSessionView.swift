import SwiftUI
import SwiftData

// MARK: - ActiveGymSessionViewModel

@Observable
@MainActor
final class ActiveGymSessionViewModel {

    // MARK: State

    var session: WorkoutSession
    var elapsedTime: TimeInterval = 0
    var showExercisePicker = false
    var errorMessage: String?

    // MARK: Rest Timer State

    /// Seconds remaining on the active rest timer. `nil` means no timer is running.
    var restSecondsRemaining: Int? = nil
    var showRestTimer = false

    // MARK: Private

    private var timerTask: Task<Void, Never>?
    private var restTimerTask: Task<Void, Never>?

    // MARK: Init

    init(session: WorkoutSession) {
        self.session = session
    }

    // MARK: Workout Timer

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

    // MARK: Rest Timer

    /// Starts a countdown rest timer for `seconds`. Replaces any existing timer.
    func startRestTimer(seconds: Int = 90) {
        restTimerTask?.cancel()
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

    /// Formatted rest countdown label, e.g. "1:30".
    var formattedRest: String {
        guard let secs = restSecondsRemaining else { return "0:00" }
        let minutes = secs / 60
        let seconds = secs % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    // MARK: Exercise Management

    func addExercise(_ exercise: Exercise) throws {
        let entry = WorkoutExerciseEntry(
            exerciseId: exercise.id,
            exerciseName: exercise.name,
            orderIndex: session.entries.count
        )
        let firstSet = WorkoutSet(setNumber: 1)
        entry.sets.append(firstSet)
        session.entries.append(entry)
        try GymRepository.shared.saveSession(session)
    }

    // MARK: Set Management

    func addSet(to entry: WorkoutExerciseEntry) throws {
        let lastWeight = entry.sets.last?.weight ?? 0
        let lastReps = entry.sets.last?.reps ?? 10
        let nextNumber = entry.sets.count + 1
        let newSet = try GymRepository.shared.addSet(
            to: entry,
            weight: lastWeight,
            reps: lastReps
        )
        // addSet returns the inserted set; setNumber may differ from the
        // repository default so we align it here.
        newSet.setNumber = nextNumber
    }

    func markSetCompleted(_ set: WorkoutSet) throws {
        try GymRepository.shared.markSetCompleted(set)
        startRestTimer()
    }

    func deleteSet(_ set: WorkoutSet, from entry: WorkoutExerciseEntry) throws {
        try GymRepository.shared.deleteSet(set)
        // Re-sequence remaining sets so numbers stay contiguous.
        let sorted = entry.sets.sorted { $0.setNumber < $1.setNumber }
        for (index, s) in sorted.enumerated() {
            s.setNumber = index + 1
        }
    }

    // MARK: Session Completion

    func completeSession() throws {
        stopTimer()
        cancelRestTimer()
        try GymRepository.shared.completeSession(session)
    }

    // MARK: Computed

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
}

// MARK: - ActiveGymSessionView

@MainActor
struct ActiveGymSessionView: View {

    // MARK: Properties

    let session: WorkoutSession
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: ActiveGymSessionViewModel

    // MARK: Init

    init(session: WorkoutSession) {
        self.session = session
        self._viewModel = State(initialValue: ActiveGymSessionViewModel(session: session))
    }

    // MARK: Body

    var body: some View {
        ZStack {
            Color.kineticsBackground
                .ignoresSafeArea()

            VStack(spacing: 0) {
                headerSection
                Divider()
                    .background(Color.kineticsSubtext.opacity(0.3))
                exerciseList
                bottomToolbar
            }

            // Rest Timer Overlay — appears above content when a set is completed
            if viewModel.showRestTimer {
                RestTimerOverlay(viewModel: viewModel)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(10)
            }
        }
        .navigationBarBackButtonHidden()
        .onAppear { viewModel.startTimer() }
        .onDisappear { viewModel.stopTimer() }
        .sheet(isPresented: $viewModel.showExercisePicker) {
            ExercisePickerView { exercise in
                try viewModel.addExercise(exercise)
            }
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
    }

    // MARK: Header

    private var headerSection: some View {
        VStack(spacing: 4) {
            Text(viewModel.formattedElapsed)
                .font(.system(size: 48, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.kineticsBlue)
                .contentTransition(.numericText())
                .animation(.linear(duration: 0.25), value: viewModel.formattedElapsed)

            Text("ACTIVE WORKOUT")
                .font(.system(size: 11, weight: .semibold, design: .default))
                .tracking(2.5)
                .foregroundStyle(Color.kineticsSubtext)
        }
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity)
        .background(Color.kineticsDark)
    }

    // MARK: Exercise List

    private var exerciseList: some View {
        ScrollView {
            LazyVStack(spacing: 12, pinnedViews: []) {
                ForEach(
                    viewModel.session.entries.sorted { $0.orderIndex < $1.orderIndex },
                    id: \.id
                ) { entry in
                    ExerciseEntrySection(entry: entry, viewModel: viewModel)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
        }
    }

    // MARK: Bottom Toolbar

    private var bottomToolbar: some View {
        HStack {
            Button {
                viewModel.showExercisePicker = true
            } label: {
                Label("Add Exercise", systemImage: "plus.circle.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.kineticsGreen)
            }

            Spacer()

            Button {
                do {
                    try viewModel.completeSession()
                    dismiss()
                } catch {
                    viewModel.errorMessage = error.localizedDescription
                }
            } label: {
                Label("Finish", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.kineticsBlue)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(Color.kineticsDark)
        .overlay(alignment: .top) {
            Divider()
                .background(Color.kineticsSubtext.opacity(0.3))
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
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 20) {
                // Header row
                HStack {
                    Text("REST TIMER")
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(2)
                        .foregroundStyle(Color.kineticsSubtext)
                    Spacer()
                    Button { viewModel.cancelRestTimer() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(Color.kineticsSubtext)
                    }
                }

                // Countdown ring
                ZStack {
                    Circle()
                        .stroke(Color.kineticsBlue.opacity(0.15), lineWidth: 8)
                        .frame(width: 120, height: 120)

                    Circle()
                        .trim(from: 0, to: ringProgress)
                        .stroke(
                            Color.kineticsBlue,
                            style: StrokeStyle(lineWidth: 8, lineCap: .round)
                        )
                        .frame(width: 120, height: 120)
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 1), value: viewModel.restSecondsRemaining)

                    VStack(spacing: 2) {
                        Text(viewModel.formattedRest)
                            .font(.system(size: 30, weight: .bold, design: .monospaced))
                            .foregroundStyle(.white)
                            .contentTransition(.numericText())
                            .animation(.linear(duration: 0.25), value: viewModel.formattedRest)
                        Text("remaining")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.kineticsSubtext)
                    }
                }

                // Preset duration chips
                HStack(spacing: 8) {
                    ForEach(presets, id: \.seconds) { preset in
                        Button {
                            viewModel.startRestTimer(seconds: preset.seconds)
                        } label: {
                            Text(preset.label)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(
                                    viewModel.restSecondsRemaining == preset.seconds
                                        ? Color.black : Color.kineticsBlue
                                )
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(
                                    Capsule().fill(
                                        viewModel.restSecondsRemaining == preset.seconds
                                            ? Color.kineticsBlue
                                            : Color.kineticsBlue.opacity(0.15)
                                    )
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }

                // Skip
                Button { viewModel.cancelRestTimer() } label: {
                    Text("Skip Rest")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.kineticsSubtext)
                }
            }
            .padding(24)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color.kineticsDark)
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .strokeBorder(Color.kineticsBlue.opacity(0.25), lineWidth: 1)
                    )
            )
            .shadow(color: Color.black.opacity(0.5), radius: 24, x: 0, y: -8)
            .padding(.horizontal, 16)
            .padding(.bottom, 110)
        }
    }

    private var ringProgress: Double {
        guard let secs = viewModel.restSecondsRemaining, secs > 0 else { return 0 }
        // Ring drains from full (1.0) to empty as time elapses.
        // We track relative to the full 90s default; clamp at 1.0 for longer presets.
        return min(Double(secs) / 90.0, 1.0)
    }
}

// MARK: - ExerciseEntrySection

private struct ExerciseEntrySection: View {

    let entry: WorkoutExerciseEntry
    let viewModel: ActiveGymSessionViewModel

    /// Best weight from already-completed sets in this entry — shown as a hint in pending rows.
    private var previousBestWeight: Double? {
        let completedWeights = entry.sets.filter { $0.isCompleted && $0.weight > 0 }.map(\.weight)
        return completedWeights.max()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Exercise header
            HStack {
                Text(entry.exerciseName)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Color.white)

                Spacer()

                Button {
                    do {
                        try viewModel.addSet(to: entry)
                    } catch {
                        viewModel.errorMessage = error.localizedDescription
                    }
                } label: {
                    Text("Add Set")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.kineticsBlue)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)

            // Column headers
            HStack(spacing: 0) {
                Text("SET")
                    .frame(width: 40, alignment: .center)
                Text("KG")
                    .frame(maxWidth: .infinity, alignment: .center)
                Text("REPS")
                    .frame(maxWidth: .infinity, alignment: .center)
                Color.clear.frame(width: 44)
            }
            .font(.system(size: 10, weight: .semibold))
            .tracking(1.5)
            .foregroundStyle(Color.kineticsSubtext)
            .padding(.horizontal, 14)

            Divider()
                .background(Color.kineticsSubtext.opacity(0.2))
                .padding(.horizontal, 14)

            // Set rows
            let sortedSets = entry.sets.sorted { $0.setNumber < $1.setNumber }
            ForEach(sortedSets, id: \.id) { set in
                SetRowView(
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
            }
            .padding(.bottom, 8)
        }
        .background(Color.kineticsDark)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - SetRowView

struct SetRowView: View {

    // MARK: Properties

    let set: WorkoutSet
    /// Best weight from previously completed sets — shown as a small amber hint below the input.
    let previousBestWeight: Double?
    let onComplete: () -> Void
    let onDelete: () -> Void

    @State private var weight: String
    @State private var reps: String

    // MARK: Init

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

    // MARK: Body

    var body: some View {
        HStack(spacing: 0) {
            // Set number badge
            ZStack {
                Circle()
                    .fill(set.isCompleted ? Color.kineticsGreen.opacity(0.2) : Color.kineticsSubtext.opacity(0.15))
                    .frame(width: 28, height: 28)

                Text("\(set.setNumber)")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(set.isCompleted ? Color.kineticsGreen : Color.kineticsSubtext)
            }
            .frame(width: 40, alignment: .center)

            // Weight input + prev-best hint
            VStack(spacing: 2) {
                TextField(weightPlaceholder, text: $weight)
                    .font(.system(size: 16, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.white)
                    .multilineTextAlignment(.center)
                    .keyboardType(.decimalPad)
                    .disabled(set.isCompleted)

                if let best = previousBestWeight, best > 0 {
                    Text("prev \(String(format: "%.1f", best))")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(Color.kineticsAmber.opacity(0.75))
                }
            }
            .frame(maxWidth: .infinity)

            // Reps input
            TextField("0", text: $reps)
                .font(.system(size: 16, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.white)
                .multilineTextAlignment(.center)
                .keyboardType(.numberPad)
                .frame(maxWidth: .infinity)
                .disabled(set.isCompleted)

            // Checkmark button
            Button {
                guard !set.isCompleted else { return }
                let parsedWeight = Double(weight) ?? 0
                let parsedReps = Int(reps) ?? 0
                do {
                    try GymRepository.shared.updateSet(set, weight: parsedWeight, reps: parsedReps, rpe: set.rpe)
                } catch {
                    // save failure is non-fatal; still invoke onComplete to trigger rest timer
                }
                onComplete()
            } label: {
                Image(systemName: set.isCompleted ? "checkmark.circle.fill" : "checkmark.circle")
                    .font(.system(size: 22))
                    .foregroundStyle(set.isCompleted ? Color.kineticsGreen : Color.kineticsSubtext)
            }
            .frame(width: 44, alignment: .center)
            .disabled(set.isCompleted)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .background(
            set.isCompleted
                ? Color.kineticsGreen.opacity(0.07)
                : Color.clear
        )
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete", systemImage: "trash.fill")
            }
        }
        .animation(.easeInOut(duration: 0.2), value: set.isCompleted)
    }

    // MARK: Helpers

    private var weightPlaceholder: String {
        guard let best = previousBestWeight, best > 0 else { return "0.0" }
        return String(format: "%.1f", best)
    }
}

// MARK: - ExercisePickerView

@MainActor
struct ExercisePickerView: View {

    // MARK: Properties

    let onSelect: (Exercise) throws -> Void

    @State private var exercises: [Exercise] = []
    @State private var searchText = ""
    @Environment(\.dismiss) private var dismiss

    // MARK: Body

    var body: some View {
        NavigationStack {
            ZStack {
                Color.kineticsBackground
                    .ignoresSafeArea()

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

    // MARK: Exercise List

    private var exerciseList: some View {
        ScrollView {
            LazyVStack(spacing: 1) {
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
                        .foregroundStyle(Color.white)
                        .multilineTextAlignment(.leading)

                    Text(exercise.primaryMuscle)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(Color.kineticsSubtext)
                }

                Spacer()

                Image(systemName: "plus.circle")
                    .font(.system(size: 18))
                    .foregroundStyle(Color.kineticsBlue)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color.kineticsDark)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.bottom, 6)
    }

    // MARK: Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "dumbbell.fill")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(Color.kineticsBlue.opacity(0.45))
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
