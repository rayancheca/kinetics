import SwiftData
import SwiftUI

// MARK: - RoutineListViewModel

@Observable
@MainActor
final class RoutineListViewModel {
    var routines: [Routine] = []
    var isLoading = false
    var errorMessage: String?
    var showBuilder = false
    var navigatingToDetail: Routine?

    func load(userId: String) {
        routines = (try? GymRepository.shared.fetchRoutines(userId: userId)) ?? []
    }

    func delete(_ routine: Routine) {
        try? GymRepository.shared.deleteRoutine(routine)
        routines.removeAll { $0.id == routine.id }
    }

    func duplicate(_ routine: Routine) {
        guard let copy = try? GymRepository.shared.duplicateRoutine(routine) else { return }
        routines.insert(copy, at: 0)
    }
}

// MARK: - RoutineListView

@MainActor
struct RoutineListView: View {

    @Environment(AppState.self) private var appState
    @State private var viewModel = RoutineListViewModel()
    @State private var showBuilder = false
    @State private var selectedRoutine: Routine?
    @State private var activeSession: WorkoutSession?
    @State private var selectedFilter: String = "All"

    private let filterOptions = ["All", "Legs", "Upper", "Lower", "Back", "Full Body"]

    private var filteredRoutines: [Routine] {
        guard selectedFilter != "All" else { return viewModel.routines }
        let filter = selectedFilter
        return viewModel.routines.filter { routine in
            routine.muscleGroups.contains { group in
                switch filter {
                case "Legs":
                    return [GymMuscleGroup.quadriceps, .hamstrings, .glutes, .calves]
                        .contains(group)
                case "Upper":
                    return [GymMuscleGroup.chest, .shoulders, .biceps, .triceps, .forearms]
                        .contains(group)
                case "Lower":
                    return [GymMuscleGroup.quadriceps, .hamstrings, .glutes, .calves]
                        .contains(group)
                case "Back":
                    return group == .back
                case "Full Body":
                    return group == .fullBody
                default:
                    return false
                }
            }
        }
    }

    private var uid: String {
        appState.authManager.currentUser?.uid ?? "preview-user"
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Color.kineticsBackground.ignoresSafeArea()

            content

            // FAB
            Button {
                showBuilder = true
            } label: {
                ZStack {
                    Circle()
                        .fill(Color.kineticsPurple)
                        .frame(width: 56, height: 56)
                        .shadow(color: Color.kineticsPurple.opacity(0.45), radius: 12, x: 0, y: 6)
                    Image(systemName: "plus")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
            .buttonStyle(.plain)
            .padding(.trailing, 20)
            .padding(.bottom, 20)
        }
        .navigationTitle("MY ROUTINES")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.kineticsBackground, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task { viewModel.load(userId: uid) }
        .sheet(isPresented: $showBuilder, onDismiss: { viewModel.load(userId: uid) }) {
            RoutineBuilderView(userId: uid) {
                showBuilder = false
                viewModel.load(userId: uid)
            }
        }
        .sheet(item: $selectedRoutine, onDismiss: { viewModel.load(userId: uid) }) { routine in
            RoutineDetailView(routine: routine, userId: uid) { session in
                selectedRoutine = nil
                activeSession = session
            }
        }
        .sheet(item: $activeSession) { session in
            ActiveGymSessionView(session: session)
        }
    }

    // MARK: - Filter Chips

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(filterOptions, id: \.self) { filter in
                    Button {
                        selectedFilter = filter
                    } label: {
                        Text(filter)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(selectedFilter == filter ? .white : Color.kineticsSubtext)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(
                                Capsule()
                                    .fill(selectedFilter == filter ? Color.kineticsPurple : Color.kineticsDark)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        VStack(spacing: 0) {
            filterChips
            if filteredRoutines.isEmpty && !viewModel.routines.isEmpty {
                // All routines exist but none match the current filter
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .font(.system(size: 40, weight: .medium))
                        .foregroundStyle(Color.kineticsPurple.opacity(0.6))
                    Text("No routines match \"\(selectedFilter)\"")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color.kineticsSubtext)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.routines.isEmpty {
                emptyState
            } else {
                routineList
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer()

            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.kineticsDark)
                    .frame(width: 88, height: 88)
                Image(systemName: "calendar.badge.plus")
                    .font(.system(size: 38, weight: .medium))
                    .foregroundStyle(Color.kineticsPurple.opacity(0.7))
            }

            VStack(spacing: 8) {
                Text("No routines yet")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)

                Text("Save your favourite workout plans here\nso you can start them in one tap.")
                    .font(.subheadline)
                    .foregroundStyle(Color.kineticsSubtext)
                    .multilineTextAlignment(.center)
            }

            Button {
                showBuilder = true
            } label: {
                Text("Create your first routine")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 13)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.kineticsPurple)
                    )
            }
            .buttonStyle(.plain)

            Spacer()
        }
        .padding(.horizontal, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Routine List

    private var routineList: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 12) {
                ForEach(filteredRoutines, id: \.id) { routine in
                    RoutineCard(routine: routine)
                        .contentShape(Rectangle())
                        .onTapGesture { selectedRoutine = routine }
                        .contextMenu {
                            Button {
                                if let session = try? GymRepository.shared.startSession(
                                    from: routine, userId: uid
                                ) {
                                    activeSession = session
                                }
                            } label: {
                                Label("Start Workout", systemImage: "play.fill")
                            }

                            Button {
                                selectedRoutine = routine
                            } label: {
                                Label("Edit", systemImage: "pencil")
                            }

                            Button {
                                viewModel.duplicate(routine)
                            } label: {
                                Label("Duplicate", systemImage: "doc.on.doc")
                            }

                            Divider()

                            Button(role: .destructive) {
                                viewModel.delete(routine)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                viewModel.delete(routine)
                            } label: {
                                Label("Delete", systemImage: "trash.fill")
                            }
                        }
                        .swipeActions(edge: .leading, allowsFullSwipe: false) {
                            Button {
                                viewModel.duplicate(routine)
                            } label: {
                                Label("Duplicate", systemImage: "doc.on.doc.fill")
                            }
                            .tint(Color.kineticsPurple)
                        }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 100)
        }
    }
}

// MARK: - RoutineCard

private struct RoutineCard: View {

    let routine: Routine

    private var lastUsedText: String {
        guard let date = routine.lastUsedAt else { return "Never performed" }
        let days = Calendar.current.dateComponents([.day], from: date, to: Date()).day ?? 0
        switch days {
        case 0: return "Last done today"
        case 1: return "Last done yesterday"
        default: return "Last done \(days) days ago"
        }
    }

    private var exerciseCountText: String {
        let count = routine.slots.count
        return "\(count) exercise\(count == 1 ? "" : "s")"
    }

    private var estimatedTimeText: String {
        let mins = routine.estimatedMinutes
        return "~\(mins) min"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Top row
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(routine.name)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    HStack(spacing: 10) {
                        Label(exerciseCountText, systemImage: "dumbbell.fill")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color.kineticsSubtext)

                        Text("·")
                            .foregroundStyle(Color.kineticsSubtext.opacity(0.5))
                            .font(.system(size: 12))

                        Label(estimatedTimeText, systemImage: "clock")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color.kineticsSubtext)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.kineticsSubtext.opacity(0.5))
                    .padding(.top, 2)
            }

            // Muscle chips
            if !routine.muscleGroups.isEmpty {
                MusclePillRow(muscles: routine.muscleGroups)
            }

            // Footer
            HStack {
                Text(lastUsedText)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.kineticsSubtext.opacity(0.7))

                Spacer()

                if !routine.scheduledDays.isEmpty {
                    scheduledDaysLabel
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.kineticsDark)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.kineticsPurple.opacity(0.18), lineWidth: 1)
                )
        )
    }

    private var scheduledDaysLabel: some View {
        let names = ["S", "M", "T", "W", "T", "F", "S"]
        let set = Set(routine.scheduledDays)
        return HStack(spacing: 3) {
            ForEach(0..<7, id: \.self) { day in
                Text(names[day])
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(set.contains(day) ? Color.kineticsPurple : Color.kineticsSubtext.opacity(0.3))
            }
        }
    }
}

// MARK: - MusclePillRow

private struct MusclePillRow: View {
    /// Accepts either [GymMuscleGroup] (from Routine.muscleGroups) or raw
    /// [String] muscle names by converting lazily.
    let muscles: [GymMuscleGroup]

    init(muscles: [GymMuscleGroup]) {
        self.muscles = muscles
    }

    /// Convenience init for callers passing raw muscle name strings.
    init(muscleNames: [String]) {
        self.muscles = muscleNames.map { GymMuscleGroup(rawValue: $0) ?? .other }
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(muscles, id: \.rawValue) { group in
                    Text(group.rawValue)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(group.color)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(group.color.opacity(0.15))
                        )
                }
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - RoutineDetailViewModel

@Observable
@MainActor
final class RoutineDetailViewModel {
    var routine: Routine
    var slots: [RoutineExerciseSlot]
    var name: String
    var notes: String
    var scheduledDays: Set<Int>
    var showExercisePicker = false
    var editingSlot: RoutineExerciseSlot?
    var isSaving = false

    init(routine: Routine) {
        self.routine = routine
        self.slots = routine.slots
        self.name = routine.name
        self.notes = routine.notes ?? ""
        self.scheduledDays = Set(routine.scheduledDays)
    }

    func moveSlot(from source: IndexSet, to destination: Int) {
        slots.move(fromOffsets: source, toOffset: destination)
        reindex()
    }

    func removeSlot(at offsets: IndexSet) {
        slots.remove(atOffsets: offsets)
        reindex()
    }

    func addExercise(_ exercise: Exercise) {
        guard !slots.contains(where: { $0.exerciseId == exercise.id }) else { return }
        let slot = RoutineExerciseSlot(
            exerciseId: exercise.id,
            exerciseName: exercise.name,
            primaryMuscle: exercise.primaryMuscle,
            orderIndex: slots.count
        )
        slots.append(slot)
    }

    func save() {
        isSaving = true
        routine.name = name.trimmingCharacters(in: .whitespaces)
        routine.notes = notes
        routine.scheduledDays = Array(scheduledDays).sorted()
        routine.slots = slots
        try? GymRepository.shared.saveRoutine(routine)
        isSaving = false
    }

    private func reindex() {
        for index in slots.indices {
            slots[index].orderIndex = index
        }
    }
}

// MARK: - RoutineDetailView

@MainActor
struct RoutineDetailView: View {

    let routine: Routine
    let userId: String
    let onStartSession: (WorkoutSession) -> Void

    @State private var viewModel: RoutineDetailViewModel
    @Environment(\.dismiss) private var dismiss

    init(routine: Routine, userId: String, onStartSession: @escaping (WorkoutSession) -> Void) {
        self.routine = routine
        self.userId = userId
        self.onStartSession = onStartSession
        self._viewModel = State(initialValue: RoutineDetailViewModel(routine: routine))
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                Color.kineticsBackground.ignoresSafeArea()

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 20) {
                        headerCard
                        startButton
                        exercisesSection
                        scheduleSection
                        notesSection
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.kineticsBackground, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(Color.kineticsSubtext)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        viewModel.save()
                    } label: {
                        Text("Save")
                            .fontWeight(.semibold)
                            .foregroundStyle(Color.kineticsPurple)
                    }
                    .disabled(viewModel.name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .sheet(isPresented: $viewModel.showExercisePicker) {
                ExercisePickerView { exercise in
                    viewModel.addExercise(exercise)
                }
            }
            .sheet(item: $viewModel.editingSlot) { slot in
                SlotEditSheet(slot: slot) { updated in
                    if let idx = viewModel.slots.firstIndex(where: { $0.id == updated.id }) {
                        viewModel.slots[idx] = updated
                    }
                }
            }
        }
    }

    // MARK: - Header Card

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Editable title
            TextField("Routine name", text: $viewModel.name)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white)
                .tint(Color.kineticsPurple)

            HStack(spacing: 14) {
                metaStat(
                    icon: "dumbbell.fill",
                    value: "\(viewModel.slots.count)",
                    label: "exercises",
                    color: Color.kineticsPurple
                )

                metaStat(
                    icon: "clock.fill",
                    value: "~\(estimatedMinutes)m",
                    label: "estimated",
                    color: Color.kineticsBlue
                )
            }

            if !muscleGroups.isEmpty {
                MusclePillRow(muscles: muscleGroups)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.kineticsDark)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.kineticsPurple.opacity(0.2), lineWidth: 1)
                )
        )
    }

    private func metaStat(icon: String, value: String, label: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(color)
            Text(value)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(Color.kineticsSubtext)
        }
    }

    // MARK: - Start Button

    private var startButton: some View {
        Button {
            guard let session = try? GymRepository.shared.startSession(from: routine, userId: userId) else { return }
            dismiss()
            onStartSession(session)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "play.fill")
                    .font(.system(size: 14, weight: .semibold))
                Text("Start Routine")
                    .font(.system(size: 16, weight: .semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.kineticsPurple)
                    .shadow(color: Color.kineticsPurple.opacity(0.4), radius: 10, y: 4)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Exercises Section

    private var exercisesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("EXERCISES", count: viewModel.slots.count)

            List {
                ForEach($viewModel.slots, id: \.id) { $slot in
                    DetailExerciseRow(slot: slot) {
                        viewModel.editingSlot = slot
                    }
                    .listRowBackground(Color.kineticsDark)
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                    .listRowSeparator(.hidden)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            if let idx = viewModel.slots.firstIndex(where: { $0.id == slot.id }) {
                                viewModel.slots.remove(at: idx)
                                viewModel.removeSlot(at: IndexSet(integer: idx))
                            }
                        } label: {
                            Label("Remove", systemImage: "minus.circle.fill")
                        }
                    }
                }
                .onMove { source, dest in
                    viewModel.moveSlot(from: source, to: dest)
                }

                // Add exercise button row
                Button {
                    viewModel.showExercisePicker = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(Color.kineticsPurple)
                        Text("Add Exercise")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Color.kineticsPurple)
                    }
                    .padding(.vertical, 4)
                }
                .listRowBackground(Color.kineticsDark)
                .listRowInsets(EdgeInsets(top: 4, leading: 14, bottom: 4, trailing: 14))
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .scrollDisabled(true)
            .frame(height: CGFloat(viewModel.slots.count * 72 + 52))
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.kineticsDark)
            )
            .environment(\.editMode, .constant(.active))
        }
    }

    // MARK: - Schedule Section

    private var scheduleSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("SCHEDULE", count: nil)

            HStack(spacing: 8) {
                ForEach(0..<7, id: \.self) { day in
                    DayChip(
                        day: day,
                        isSelected: viewModel.scheduledDays.contains(day)
                    ) {
                        if viewModel.scheduledDays.contains(day) {
                            viewModel.scheduledDays.remove(day)
                        } else {
                            viewModel.scheduledDays.insert(day)
                        }
                    }
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.kineticsDark)
            )
        }
    }

    // MARK: - Notes Section

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("NOTES", count: nil)

            TextEditor(text: $viewModel.notes)
                .foregroundStyle(.white)
                .tint(Color.kineticsPurple)
                .scrollContentBackground(.hidden)
                .padding(12)
                .frame(minHeight: 80)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.kineticsDark)
                )
                .overlay(
                    Group {
                        if viewModel.notes.isEmpty {
                            Text("Add notes, cues, or reminders…")
                                .font(.system(size: 14))
                                .foregroundStyle(Color.kineticsSubtext.opacity(0.5))
                                .padding(16)
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                                .allowsHitTesting(false)
                        }
                    }
                )
        }
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String, count: Int?) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.kineticsSubtext)
                .kerning(0.8)
            if let count {
                Text("(\(count))")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.kineticsSubtext.opacity(0.6))
                    .kerning(0.8)
            }
        }
    }

    private var muscleGroups: [GymMuscleGroup] {
        var seen = Set<GymMuscleGroup>()
        return viewModel.slots.compactMap { slot -> GymMuscleGroup? in
            let group = GymMuscleGroup(rawValue: slot.primaryMuscle) ?? .other
            guard seen.insert(group).inserted else { return nil }
            return group
        }
    }

    private var estimatedMinutes: Int {
        let totalSets = viewModel.slots.reduce(0) { $0 + $1.targetSets }
        let raw = Double(totalSets) * 2.5
        let rounded = (raw / 5.0).rounded(.up) * 5.0
        return max(5, Int(rounded))
    }
}

// MARK: - DetailExerciseRow

private struct DetailExerciseRow: View {

    let slot: RoutineExerciseSlot
    let onEdit: () -> Void

    private var volumeText: String {
        "\(slot.targetSets) × \(slot.targetReps)"
    }

    private var restText: String {
        let s = slot.restSeconds
        return s >= 60 ? "\(s / 60):\(String(format: "%02d", s % 60)) rest" : "\(s)s rest"
    }

    var body: some View {
        HStack(spacing: 12) {
            // Drag handle
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.kineticsSubtext.opacity(0.5))
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 3) {
                Text(slot.exerciseName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Text(volumeText)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.kineticsGreen)

                    Text("·")
                        .foregroundStyle(Color.kineticsSubtext.opacity(0.4))

                    Text(restText)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.kineticsSubtext)
                }
            }

            Spacer()

            Button {
                onEdit()
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.kineticsSubtext)
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.kineticsSubtext.opacity(0.08))
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

// MARK: - DayChip

private struct DayChip: View {

    let day: Int
    let isSelected: Bool
    let onTap: () -> Void

    private let labels = ["S", "M", "T", "W", "T", "F", "S"]

    var body: some View {
        Button(action: onTap) {
            Text(labels[day])
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(isSelected ? .white : Color.kineticsSubtext)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(isSelected ? Color.kineticsPurple : Color.kineticsMidGray)
                )
                .animation(.spring(duration: 0.2), value: isSelected)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - SlotEditSheet

@MainActor
struct SlotEditSheet: View {

    @State private var slot: RoutineExerciseSlot
    let onSave: (RoutineExerciseSlot) -> Void

    @Environment(\.dismiss) private var dismiss

    private let restPresets: [(label: String, seconds: Int)] = [
        ("30s", 30), ("60s", 60), ("90s", 90), ("2m", 120), ("3m", 180)
    ]

    init(slot: RoutineExerciseSlot, onSave: @escaping (RoutineExerciseSlot) -> Void) {
        self._slot = State(initialValue: slot)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.kineticsBackground.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        // Title
                        Text(slot.exerciseName)
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)
                            .padding(.top, 8)

                        // Sets stepper
                        stepperRow(
                            label: "Target Sets",
                            value: $slot.targetSets,
                            range: 1...20,
                            accentColor: Color.kineticsPurple
                        )

                        // Reps stepper
                        stepperRow(
                            label: "Target Reps",
                            value: $slot.targetReps,
                            range: 1...100,
                            accentColor: Color.kineticsBlue
                        )

                        // Rest presets
                        restSection
                    }
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle("Edit Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.kineticsBackground, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.kineticsSubtext)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        onSave(slot)
                        dismiss()
                    }
                    .foregroundStyle(Color.kineticsPurple)
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.kineticsBackground)
    }

    private func stepperRow(
        label: String,
        value: Binding<Int>,
        range: ClosedRange<Int>,
        accentColor: Color
    ) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)

            Spacer()

            HStack(spacing: 0) {
                Button {
                    if value.wrappedValue > range.lowerBound {
                        value.wrappedValue -= 1
                    }
                } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(accentColor)
                        .frame(width: 40, height: 40)
                }
                .buttonStyle(.plain)

                Text("\(value.wrappedValue)")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(width: 44, alignment: .center)
                    .contentTransition(.numericText())
                    .animation(.spring(duration: 0.2), value: value.wrappedValue)

                Button {
                    if value.wrappedValue < range.upperBound {
                        value.wrappedValue += 1
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(accentColor)
                        .frame(width: 40, height: 40)
                }
                .buttonStyle(.plain)
            }
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.kineticsMidGray)
            )
        }
        .padding(.horizontal, 16)
    }

    private var restSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Rest Between Sets")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(restPresets, id: \.seconds) { preset in
                        Button {
                            slot.restSeconds = preset.seconds
                        } label: {
                            Text(preset.label)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(
                                    slot.restSeconds == preset.seconds ? .white : Color.kineticsSubtext
                                )
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background(
                                    Capsule()
                                        .fill(
                                            slot.restSeconds == preset.seconds
                                                ? Color.kineticsPurple
                                                : Color.kineticsMidGray
                                        )
                                )
                                .animation(.spring(duration: 0.2), value: slot.restSeconds)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }
}

// MARK: - RoutineTemplate

struct RoutineTemplate: Identifiable, Sendable {
    struct ExerciseSpec: Sendable {
        let name: String
        let primaryMuscle: String
    }

    let id: String
    let name: String
    let muscleFocus: String
    let gradientColors: [Color]
    let exercises: [ExerciseSpec]

    var exerciseCount: Int { exercises.count }

    func makeSlots() -> [RoutineExerciseSlot] {
        exercises.enumerated().map { index, spec in
            RoutineExerciseSlot(
                exerciseId: UUID().uuidString,
                exerciseName: spec.name,
                primaryMuscle: spec.primaryMuscle,
                orderIndex: index,
                targetSets: 3,
                targetReps: 10,
                restSeconds: 90
            )
        }
    }

    // MARK: - Built-in presets

    static let all: [RoutineTemplate] = [
        RoutineTemplate(
            id: "push-day",
            name: "Push Day",
            muscleFocus: "Chest · Shoulders · Triceps",
            gradientColors: [Color(red: 0.25, green: 0.72, blue: 1.0), Color(red: 0.55, green: 0.35, blue: 1.0)],
            exercises: [
                .init(name: "Bench Press", primaryMuscle: "Chest"),
                .init(name: "Incline Dumbbell Press", primaryMuscle: "Chest"),
                .init(name: "Overhead Press", primaryMuscle: "Shoulders"),
                .init(name: "Lateral Raises", primaryMuscle: "Shoulders"),
                .init(name: "Tricep Pushdown", primaryMuscle: "Triceps"),
                .init(name: "Skull Crushers", primaryMuscle: "Triceps")
            ]
        ),
        RoutineTemplate(
            id: "pull-day",
            name: "Pull Day",
            muscleFocus: "Back · Biceps",
            gradientColors: [Color(red: 0.22, green: 1.0, blue: 0.69), Color(red: 0.20, green: 0.85, blue: 1.0)],
            exercises: [
                .init(name: "Deadlift", primaryMuscle: "Back"),
                .init(name: "Pull-Ups", primaryMuscle: "Back"),
                .init(name: "Barbell Row", primaryMuscle: "Back"),
                .init(name: "Seated Cable Row", primaryMuscle: "Back"),
                .init(name: "Face Pulls", primaryMuscle: "Shoulders"),
                .init(name: "Barbell Curl", primaryMuscle: "Biceps"),
                .init(name: "Hammer Curl", primaryMuscle: "Biceps")
            ]
        ),
        RoutineTemplate(
            id: "leg-day",
            name: "Leg Day",
            muscleFocus: "Quads · Hamstrings · Glutes",
            gradientColors: [Color(red: 0.95, green: 0.35, blue: 0.45), Color(red: 1.0, green: 0.55, blue: 0.70)],
            exercises: [
                .init(name: "Squat", primaryMuscle: "Quadriceps"),
                .init(name: "Romanian Deadlift", primaryMuscle: "Hamstrings"),
                .init(name: "Leg Press", primaryMuscle: "Quadriceps"),
                .init(name: "Lunges", primaryMuscle: "Quadriceps"),
                .init(name: "Leg Curl", primaryMuscle: "Hamstrings"),
                .init(name: "Calf Raises", primaryMuscle: "Calves")
            ]
        ),
        RoutineTemplate(
            id: "upper-body",
            name: "Upper Body",
            muscleFocus: "Chest · Back · Shoulders",
            gradientColors: [Color(red: 1.0, green: 0.80, blue: 0.20), Color(red: 1.0, green: 0.45, blue: 0.20)],
            exercises: [
                .init(name: "Bench Press", primaryMuscle: "Chest"),
                .init(name: "Pull-Ups", primaryMuscle: "Back"),
                .init(name: "Overhead Press", primaryMuscle: "Shoulders"),
                .init(name: "Barbell Row", primaryMuscle: "Back"),
                .init(name: "Dips", primaryMuscle: "Triceps"),
                .init(name: "Cable Fly", primaryMuscle: "Chest")
            ]
        ),
        RoutineTemplate(
            id: "full-body",
            name: "Full Body",
            muscleFocus: "Full Body",
            gradientColors: [Color.white.opacity(0.7), Color(red: 0.55, green: 0.55, blue: 0.60)],
            exercises: [
                .init(name: "Squat", primaryMuscle: "Quadriceps"),
                .init(name: "Bench Press", primaryMuscle: "Chest"),
                .init(name: "Deadlift", primaryMuscle: "Back"),
                .init(name: "Pull-Ups", primaryMuscle: "Back"),
                .init(name: "Overhead Press", primaryMuscle: "Shoulders")
            ]
        ),
        RoutineTemplate(
            id: "chest-triceps",
            name: "Chest & Triceps",
            muscleFocus: "Chest · Triceps",
            gradientColors: [Color(red: 0.25, green: 0.72, blue: 1.0), Color(red: 0.90, green: 0.35, blue: 0.90)],
            exercises: [
                .init(name: "Bench Press", primaryMuscle: "Chest"),
                .init(name: "Incline Press", primaryMuscle: "Chest"),
                .init(name: "Cable Fly", primaryMuscle: "Chest"),
                .init(name: "Chest Dips", primaryMuscle: "Chest"),
                .init(name: "Tricep Pushdown", primaryMuscle: "Triceps"),
                .init(name: "Close Grip Bench", primaryMuscle: "Triceps")
            ]
        ),
        RoutineTemplate(
            id: "back-biceps",
            name: "Back & Biceps",
            muscleFocus: "Back · Biceps",
            gradientColors: [Color(red: 0.22, green: 1.0, blue: 0.69), Color(red: 0.55, green: 0.35, blue: 1.0)],
            exercises: [
                .init(name: "Deadlift", primaryMuscle: "Back"),
                .init(name: "Pull-Ups", primaryMuscle: "Back"),
                .init(name: "Seated Row", primaryMuscle: "Back"),
                .init(name: "Lat Pulldown", primaryMuscle: "Back"),
                .init(name: "Barbell Curl", primaryMuscle: "Biceps"),
                .init(name: "Incline Curl", primaryMuscle: "Biceps")
            ]
        ),
        RoutineTemplate(
            id: "bro-shoulders",
            name: "Bro Split Shoulders",
            muscleFocus: "Shoulders",
            gradientColors: [Color(red: 1.0, green: 0.80, blue: 0.20), Color(red: 0.22, green: 1.0, blue: 0.69)],
            exercises: [
                .init(name: "Overhead Press", primaryMuscle: "Shoulders"),
                .init(name: "Lateral Raises", primaryMuscle: "Shoulders"),
                .init(name: "Front Raises", primaryMuscle: "Shoulders"),
                .init(name: "Rear Delt Fly", primaryMuscle: "Shoulders"),
                .init(name: "Upright Row", primaryMuscle: "Shoulders"),
                .init(name: "Shrugs", primaryMuscle: "Trapezius")
            ]
        )
    ]
}

// MARK: - RoutineBuilderViewModel

@Observable
@MainActor
final class RoutineBuilderViewModel {
    enum Step: Int, CaseIterable { case name = 1, exercises, schedule }

    var currentStep: Step = .name
    var routineName = ""
    var selectedSlots: [RoutineExerciseSlot] = []
    var scheduledDays = Set<Int>()
    var showExercisePicker = false
    var showTemplatePicker = false
    var editingSlot: RoutineExerciseSlot?
    var isSaving = false

    var canAdvance: Bool {
        switch currentStep {
        case .name: return !routineName.trimmingCharacters(in: .whitespaces).isEmpty
        case .exercises: return !selectedSlots.isEmpty
        case .schedule: return true
        }
    }

    var isLastStep: Bool { currentStep == .schedule }

    func advance() {
        guard let next = Step(rawValue: currentStep.rawValue + 1) else { return }
        currentStep = next
    }

    func addExercise(_ exercise: Exercise) {
        guard !selectedSlots.contains(where: { $0.exerciseId == exercise.id }) else { return }
        let slot = RoutineExerciseSlot(
            exerciseId: exercise.id,
            exerciseName: exercise.name,
            primaryMuscle: exercise.primaryMuscle,
            orderIndex: selectedSlots.count
        )
        selectedSlots.append(slot)
    }

    func applyTemplate(_ template: RoutineTemplate) {
        selectedSlots = template.makeSlots()
        if routineName.trimmingCharacters(in: .whitespaces).isEmpty {
            routineName = template.name
        }
    }

    func removeSlot(at offsets: IndexSet) {
        selectedSlots.remove(atOffsets: offsets)
        reindex()
    }

    func moveSlot(from source: IndexSet, to destination: Int) {
        selectedSlots.move(fromOffsets: source, toOffset: destination)
        reindex()
    }

    func save(userId: String) {
        isSaving = true
        let routine = Routine(
            userId: userId,
            name: routineName.trimmingCharacters(in: .whitespaces),
            slots: selectedSlots,
            scheduledDays: Array(scheduledDays).sorted()
        )
        try? GymRepository.shared.saveRoutine(routine)
        isSaving = false
    }

    private func reindex() {
        for index in selectedSlots.indices {
            selectedSlots[index].orderIndex = index
        }
    }
}

// MARK: - RoutineBuilderView

@MainActor
struct RoutineBuilderView: View {

    let userId: String
    let onSave: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = RoutineBuilderViewModel()

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                Color.kineticsBackground.ignoresSafeArea()

                VStack(spacing: 0) {
                    progressBar
                    stepContent
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                bottomBar
            }
            .navigationTitle("New Routine")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.kineticsBackground, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.kineticsSubtext)
                }
            }
            .sheet(isPresented: $viewModel.showExercisePicker) {
                ExercisePickerView { exercise in
                    viewModel.addExercise(exercise)
                }
            }
            .sheet(isPresented: $viewModel.showTemplatePicker) {
                TemplatePickerSheet { template in
                    viewModel.applyTemplate(template)
                }
            }
            .sheet(item: $viewModel.editingSlot) { slot in
                SlotEditSheet(slot: slot) { updated in
                    if let idx = viewModel.selectedSlots.firstIndex(where: { $0.id == updated.id }) {
                        viewModel.selectedSlots[idx] = updated
                    }
                }
            }
        }
    }

    // MARK: - Progress Bar

    private var progressBar: some View {
        HStack(spacing: 6) {
            ForEach(RoutineBuilderViewModel.Step.allCases, id: \.rawValue) { step in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(
                        step.rawValue <= viewModel.currentStep.rawValue
                            ? Color.kineticsPurple
                            : Color.kineticsMidGray
                    )
                    .frame(height: 3)
                    .animation(.spring(duration: 0.3), value: viewModel.currentStep)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 4)
    }

    // MARK: - Step Content

    @ViewBuilder
    private var stepContent: some View {
        switch viewModel.currentStep {
        case .name:
            nameStep
        case .exercises:
            exercisesStep
        case .schedule:
            scheduleStep
        }
    }

    // MARK: - Step 1: Name

    private var nameStep: some View {
        VStack(alignment: .leading, spacing: 28) {
            VStack(alignment: .leading, spacing: 6) {
                stepLabel("STEP 1 OF 3")
                Text("Name your routine")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)

            VStack(alignment: .leading, spacing: 10) {
                TextField("e.g. Upper Body Push", text: $viewModel.routineName)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
                    .tint(Color.kineticsPurple)
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.kineticsDark)
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .strokeBorder(
                                        viewModel.routineName.isEmpty
                                            ? Color.clear
                                            : Color.kineticsPurple.opacity(0.4),
                                        lineWidth: 1.5
                                    )
                            )
                    )

                HStack(spacing: 6) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.kineticsSubtext.opacity(0.6))
                    Text("Name your routine, add exercises, then save. You can start it anytime from the home screen.")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.kineticsSubtext.opacity(0.6))
                }
                .padding(.horizontal, 4)
            }
            .padding(.horizontal, 20)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Step 2: Exercises

    private var exercisesStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                stepLabel("STEP 2 OF 3")
                Text("Add exercises")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 16)

            if viewModel.selectedSlots.isEmpty {
                addFirstExercisePrompt
            } else {
                exerciseBuilderList
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var addFirstExercisePrompt: some View {
        VStack(spacing: 16) {
            // Template banner — prominent when list is empty
            Button {
                viewModel.showTemplatePicker = true
            } label: {
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.kineticsPurple.opacity(0.18))
                            .frame(width: 44, height: 44)
                        Image(systemName: "rectangle.stack.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Color.kineticsPurple)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Start from a template")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white)
                        Text("8 ready-made routines to get you going")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.kineticsSubtext)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.kineticsSubtext.opacity(0.5))
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.kineticsDark)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(Color.kineticsPurple.opacity(0.35), lineWidth: 1)
                        )
                )
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)

            HStack {
                Rectangle()
                    .fill(Color.kineticsSubtext.opacity(0.15))
                    .frame(height: 1)
                Text("or build from scratch")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.kineticsSubtext.opacity(0.5))
                Rectangle()
                    .fill(Color.kineticsSubtext.opacity(0.15))
                    .frame(height: 1)
            }
            .padding(.horizontal, 20)

            Button {
                viewModel.showExercisePicker = true
            } label: {
                Label("Add Exercise", systemImage: "plus.circle.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.kineticsPurple)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.kineticsPurple.opacity(0.15))
                    )
            }
            .buttonStyle(.plain)

            Spacer()
        }
        .padding(.top, 4)
        .frame(maxWidth: .infinity)
    }

    private var exerciseListSummary: some View {
        HStack(spacing: 6) {
            let count = viewModel.selectedSlots.count
            let mins = builderEstimatedMinutes
            Text("\(count) exercise\(count == 1 ? "" : "s") · ~\(mins) min estimated")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.kineticsSubtext)

            Spacer()

            // Template shortcut when list already has exercises
            Button {
                viewModel.showTemplatePicker = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "rectangle.stack")
                        .font(.system(size: 11, weight: .semibold))
                    Text("Templates")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(Color.kineticsPurple.opacity(0.85))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule()
                        .fill(Color.kineticsPurple.opacity(0.12))
                )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
    }

    private var exerciseBuilderList: some View {
        VStack(spacing: 0) {
            exerciseListSummary

            List {
                ForEach($viewModel.selectedSlots, id: \.id) { $slot in
                    BuilderExerciseRow(slot: slot) {
                        viewModel.editingSlot = slot
                    }
                    .listRowBackground(Color.kineticsDark)
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                    .listRowSeparator(.hidden)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            if let idx = viewModel.selectedSlots.firstIndex(where: { $0.id == slot.id }) {
                                viewModel.removeSlot(at: IndexSet(integer: idx))
                            }
                        } label: {
                            Label("Remove", systemImage: "minus.circle.fill")
                        }
                    }
                }
                .onMove { source, dest in
                    viewModel.moveSlot(from: source, to: dest)
                }
                .onDelete { offsets in
                    viewModel.removeSlot(at: offsets)
                }

                Button {
                    viewModel.showExercisePicker = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 16))
                        Text("Add Exercise")
                            .font(.system(size: 15, weight: .medium))
                    }
                    .foregroundStyle(Color.kineticsPurple)
                    .padding(.vertical, 4)
                }
                .listRowBackground(Color.kineticsDark)
                .listRowInsets(EdgeInsets(top: 4, leading: 14, bottom: 4, trailing: 14))
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .environment(\.editMode, .constant(.active))
        }
    }

    // MARK: - Step 3: Schedule

    private var scheduleStep: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 6) {
                stepLabel("STEP 3 OF 3  ·  OPTIONAL")
                Text("Schedule it")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(.white)

                Text("Pick the days you want to run this routine.")
                    .font(.subheadline)
                    .foregroundStyle(Color.kineticsSubtext)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)

            HStack(spacing: 8) {
                ForEach(0..<7, id: \.self) { day in
                    DayChip(
                        day: day,
                        isSelected: viewModel.scheduledDays.contains(day)
                    ) {
                        if viewModel.scheduledDays.contains(day) {
                            viewModel.scheduledDays.remove(day)
                        } else {
                            viewModel.scheduledDays.insert(day)
                        }
                    }
                }
            }
            .padding(.horizontal, 20)

            // Summary card
            summaryCard
                .padding(.horizontal, 20)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(viewModel.routineName)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(.white)

            HStack(spacing: 16) {
                Label("\(viewModel.selectedSlots.count) exercises", systemImage: "dumbbell.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.kineticsSubtext)
                Label("~\(builderEstimatedMinutes)m", systemImage: "clock")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.kineticsSubtext)
            }

            if !builderMuscleGroups.isEmpty {
                MusclePillRow(muscles: builderMuscleGroups)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.kineticsDark)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.kineticsPurple.opacity(0.25), lineWidth: 1)
                )
        )
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        VStack(spacing: 0) {
            Divider()
                .background(Color.kineticsSubtext.opacity(0.15))

            HStack(spacing: 12) {
                // Back button (hidden on step 1)
                if viewModel.currentStep != .name {
                    Button {
                        if let prev = RoutineBuilderViewModel.Step(rawValue: viewModel.currentStep.rawValue - 1) {
                            viewModel.currentStep = prev
                        }
                    } label: {
                        Text("Back")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color.kineticsSubtext)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(Color.kineticsMidGray)
                            )
                    }
                    .buttonStyle(.plain)
                }

                // Next / Save button
                Button {
                    if viewModel.isLastStep {
                        viewModel.save(userId: userId)
                        onSave()
                    } else {
                        viewModel.advance()
                    }
                } label: {
                    HStack(spacing: 8) {
                        if viewModel.isSaving {
                            ProgressView()
                                .tint(.white)
                                .scaleEffect(0.8)
                        } else {
                            Text(viewModel.isLastStep ? "Save Routine" : "Next")
                                .font(.system(size: 16, weight: .semibold))
                        }
                    }
                    .foregroundStyle(viewModel.canAdvance ? .white : Color.kineticsSubtext)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(
                                viewModel.canAdvance
                                    ? Color.kineticsPurple
                                    : Color.kineticsMidGray
                            )
                    )
                    .animation(.easeInOut(duration: 0.15), value: viewModel.canAdvance)
                }
                .buttonStyle(.plain)
                .disabled(!viewModel.canAdvance || viewModel.isSaving)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 16)
        }
        .background(Color.kineticsBackground)
    }

    // MARK: - Helpers

    private func stepLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Color.kineticsPurple.opacity(0.8))
            .kerning(0.8)
    }

    private var builderMuscleGroups: [GymMuscleGroup] {
        var seen = Set<GymMuscleGroup>()
        return viewModel.selectedSlots.compactMap { slot -> GymMuscleGroup? in
            let group = GymMuscleGroup(rawValue: slot.primaryMuscle) ?? .other
            guard seen.insert(group).inserted else { return nil }
            return group
        }
    }

    private var builderEstimatedMinutes: Int {
        let totalSets = viewModel.selectedSlots.reduce(0) { $0 + $1.targetSets }
        let raw = Double(totalSets) * 2.5
        let rounded = (raw / 5.0).rounded(.up) * 5.0
        return max(5, Int(rounded))
    }
}

// MARK: - TemplatePickerSheet

@MainActor
private struct TemplatePickerSheet: View {

    let onSelect: (RoutineTemplate) -> Void

    @Environment(\.dismiss) private var dismiss

    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        NavigationStack {
            ZStack {
                Color.kineticsBackground.ignoresSafeArea()

                ScrollView(.vertical, showsIndicators: false) {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(RoutineTemplate.all) { template in
                            TemplateCard(template: template) {
                                onSelect(template)
                                dismiss()
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle("Choose a Template")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.kineticsBackground, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.kineticsSubtext)
                }
            }
        }
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.kineticsBackground)
    }
}

// MARK: - TemplateCard

@MainActor
private struct TemplateCard: View {

    let template: RoutineTemplate
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 10) {
                // Gradient accent bar
                LinearGradient(
                    colors: template.gradientColors,
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(height: 3)
                .clipShape(Capsule())

                Text(template.name)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text(template.muscleFocus)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(template.gradientColors.first ?? Color.kineticsPurple)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)

                HStack(spacing: 4) {
                    Image(systemName: "dumbbell.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.kineticsSubtext.opacity(0.6))
                    Text("\(template.exerciseCount) exercises")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.kineticsSubtext.opacity(0.6))
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.kineticsDark)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    colors: template.gradientColors.map { $0.opacity(0.3) },
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - BuilderExerciseRow

private struct BuilderExerciseRow: View {

    let slot: RoutineExerciseSlot
    let onEdit: () -> Void

    private var volumeText: String {
        "\(slot.targetSets) × \(slot.targetReps)"
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 14))
                .foregroundStyle(Color.kineticsSubtext.opacity(0.5))
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 3) {
                Text(slot.exerciseName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Text(volumeText)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.kineticsGreen)
            }

            Spacer()

            Button {
                onEdit()
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.kineticsSubtext)
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.kineticsSubtext.opacity(0.08))
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}
