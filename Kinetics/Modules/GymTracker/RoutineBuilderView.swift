import SwiftData
import SwiftUI

// MARK: - RoutineListViewModel

@Observable
@MainActor
final class RoutineListViewModel {
    var isLoading = false
    var errorMessage: String?
    var showBuilder = false
    var editingRoutine: Routine?
}

// MARK: - RoutineListView

@MainActor
struct RoutineListView: View {

    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Routine.createdAt, order: .reverse) private var routines: [Routine]
    @State private var viewModel = RoutineListViewModel()
    @State private var showBuilder = false
    @State private var editingRoutine: Routine?

    private var uid: String {
        appState.authManager.currentUser?.uid ?? "preview-user"
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.kineticsBackground.ignoresSafeArea()
                content
            }
            .navigationTitle("Routines")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(Color.kineticsBackground, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        editingRoutine = nil
                        showBuilder = true
                    } label: {
                        Image(systemName: "plus")
                            .foregroundStyle(Color.kineticsBlue)
                            .fontWeight(.semibold)
                    }
                }
            }
            .sheet(isPresented: $showBuilder) {
                RoutineBuilderView(
                    userId: uid,
                    onSave: { showBuilder = false },
                    existingRoutine: editingRoutine
                )
            }
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if routines.isEmpty {
            emptyState
        } else {
            routineList
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "rectangle.stack.badge.plus")
                .font(.system(size: 52, weight: .light))
                .foregroundStyle(Color.kineticsBlue.opacity(0.5))

            Text("No routines yet")
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundStyle(.white)

            Text("Build a routine to save your favourite workouts.")
                .font(.subheadline)
                .foregroundStyle(Color.kineticsSubtext)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Routine List

    private var routineList: some View {
        List {
            ForEach(routines, id: \.id) { routine in
                Button {
                    editingRoutine = routine
                    showBuilder = true
                } label: {
                    RoutineRow(routine: routine)
                }
                .buttonStyle(.plain)
                .listRowBackground(Color.kineticsDark)
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            }
            .onDelete { indexSet in
                for index in indexSet {
                    modelContext.delete(routines[index])
                }
                try? modelContext.save()
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }
}

// MARK: - RoutineRow (private)

private struct RoutineRow: View {

    let routine: Routine

    private var exerciseCountText: String {
        let count = routine.exerciseIds.count
        return "\(count) exercise\(count == 1 ? "" : "s")"
    }

    private var lastUsedText: String {
        guard let date = routine.lastUsedAt else { return "Never used" }
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "Last used today"
        } else if calendar.isDateInYesterday(date) {
            return "Last used yesterday"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d"
            return "Last used \(formatter.string(from: date))"
        }
    }

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(routine.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text(exerciseCountText)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.kineticsSubtext)

                    Text("·")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.kineticsSubtext.opacity(0.5))

                    Text(lastUsedText)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.kineticsSubtext)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.kineticsSubtext.opacity(0.5))
        }
        .padding(.vertical, 8)
    }
}

// MARK: - RoutineBuilderView

@MainActor
struct RoutineBuilderView: View {

    let userId: String
    let onSave: () -> Void
    var existingRoutine: Routine?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var routineDescription: String
    @State private var selectedExercises: [(id: String, name: String)]
    @State private var exercises: [Exercise] = []
    @State private var searchText = ""
    @State private var showExercisePicker = false
    @State private var isSaveDisabled = false

    // MARK: - Init

    init(userId: String, onSave: @escaping () -> Void, existingRoutine: Routine? = nil) {
        self.userId = userId
        self.onSave = onSave
        self.existingRoutine = existingRoutine
        self._name = State(initialValue: existingRoutine?.name ?? "")
        self._routineDescription = State(initialValue: existingRoutine?.routineDescription ?? "")
        self._selectedExercises = State(initialValue: zip(
            existingRoutine?.exerciseIds ?? [],
            existingRoutine?.exerciseNames ?? []
        ).map { (id: $0, name: $1) })
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                Color.kineticsBackground.ignoresSafeArea()
                builderForm
            }
            .navigationTitle(existingRoutine?.name.isEmpty == false ? existingRoutine!.name : "New Routine")
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
                    Button("Save") { saveRoutine() }
                        .foregroundStyle(name.trimmingCharacters(in: .whitespaces).isEmpty
                            ? Color.kineticsSubtext
                            : Color.kineticsBlue)
                        .fontWeight(.semibold)
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isSaveDisabled)
                }
            }
            .sheet(isPresented: $showExercisePicker) {
                ExercisePickerSheet(
                    selectedIds: selectedExercises.map(\.id),
                    onSelect: { exercise in
                        guard !selectedExercises.contains(where: { $0.id == exercise.id }) else { return }
                        selectedExercises.append((id: exercise.id, name: exercise.name))
                    }
                )
            }
        }
    }

    // MARK: - Form

    private var builderForm: some View {
        Form {
            // MARK: Details Section
            Section {
                TextField("Routine name", text: $name)
                    .foregroundStyle(.white)
                    .tint(Color.kineticsBlue)

                TextField("Description (optional)", text: $routineDescription)
                    .foregroundStyle(.white)
                    .tint(Color.kineticsBlue)
            } header: {
                Text("DETAILS")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.kineticsSubtext)
                    .kerning(0.8)
            }
            .listRowBackground(Color.kineticsDark)

            // MARK: Exercises Section
            Section {
                ForEach(Array(selectedExercises.enumerated()), id: \.element.id) { index, exercise in
                    RoutineExerciseRow(name: exercise.name, order: index + 1)
                        .listRowBackground(Color.kineticsDark)
                }
                .onDelete { indexSet in
                    selectedExercises.remove(atOffsets: indexSet)
                }
                .onMove { indices, newOffset in
                    selectedExercises.move(fromOffsets: indices, toOffset: newOffset)
                }

                Button {
                    showExercisePicker = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 16, weight: .medium))
                        Text("Add Exercise")
                            .font(.system(size: 15, weight: .medium))
                    }
                    .foregroundStyle(Color.kineticsBlue)
                }
                .listRowBackground(Color.kineticsDark)
            } header: {
                Text("EXERCISES (\(selectedExercises.count))")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.kineticsSubtext)
                    .kerning(0.8)
            }
        }
        .scrollContentBackground(.hidden)
        .environment(\.editMode, .constant(.active))
    }

    // MARK: - Save

    private func saveRoutine() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return }
        isSaveDisabled = true

        let ids = selectedExercises.map(\.id)
        let names = selectedExercises.map(\.name)

        if let existing = existingRoutine {
            existing.name = trimmedName
            existing.routineDescription = routineDescription
            existing.exerciseIds = ids
            existing.exerciseNames = names
        } else {
            let routine = Routine(
                userId: userId,
                name: trimmedName,
                routineDescription: routineDescription,
                exerciseIds: ids,
                exerciseNames: names
            )
            modelContext.insert(routine)
        }

        try? modelContext.save()
        onSave()
    }
}

// MARK: - RoutineExerciseRow (private)

private struct RoutineExerciseRow: View {

    let name: String
    let order: Int

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.kineticsSubtext.opacity(0.6))

            Text(name)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)

            Spacer()

            ZStack {
                Circle()
                    .fill(Color.kineticsBlue.opacity(0.18))
                    .frame(width: 26, height: 26)

                Text("\(order)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.kineticsBlue)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - ExercisePickerSheet (private)

private struct ExercisePickerSheet: View {

    let selectedIds: [String]
    let onSelect: (Exercise) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var exercises: [Exercise] = []
    @State private var searchText = ""

    var body: some View {
        NavigationStack {
            ZStack {
                Color.kineticsBackground.ignoresSafeArea()
                pickerContent
            }
            .navigationTitle("Add Exercise")
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
        }
    }

    // MARK: - Picker Content

    @ViewBuilder
    private var pickerContent: some View {
        if exercises.isEmpty {
            VStack(spacing: 16) {
                Spacer()
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(Color.kineticsSubtext.opacity(0.4))
                Text(searchText.isEmpty ? "No exercises found" : "No results for \"\(searchText)\"")
                    .font(.headline)
                    .foregroundStyle(.white)
                Text("Try a different search term")
                    .font(.subheadline)
                    .foregroundStyle(Color.kineticsSubtext)
                Spacer()
            }
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 8) {
                    ForEach(exercises, id: \.id) { exercise in
                        PickerExerciseRow(
                            exercise: exercise,
                            isAlreadyAdded: selectedIds.contains(exercise.id)
                        ) {
                            onSelect(exercise)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
        }
    }

    // MARK: - Load

    private func loadExercises() {
        let filter = searchText.isEmpty ? nil : searchText
        exercises = (try? GymRepository.shared.fetchExercises(filter: filter)) ?? []
    }
}

// MARK: - PickerExerciseRow (private)

private struct PickerExerciseRow: View {

    let exercise: Exercise
    let isAlreadyAdded: Bool
    let onTap: () -> Void

    @State private var justAdded = false

    private var detailText: String {
        [exercise.primaryMuscle, exercise.equipment]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    var body: some View {
        Button {
            guard !isAlreadyAdded && !justAdded else { return }
            justAdded = true
            onTap()
        } label: {
            HStack(spacing: 14) {
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

                if isAlreadyAdded || justAdded {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(Color.kineticsBlue)
                } else {
                    Image(systemName: "plus.circle")
                        .font(.system(size: 20))
                        .foregroundStyle(Color.kineticsBlue.opacity(0.8))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.kineticsDark)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(
                                (isAlreadyAdded || justAdded)
                                    ? Color.kineticsBlue.opacity(0.3)
                                    : Color.clear,
                                lineWidth: 1
                            )
                    )
            )
        }
        .buttonStyle(.plain)
        .animation(.spring(duration: 0.2), value: justAdded)
    }
}
