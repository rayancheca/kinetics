import Charts
import SwiftUI

// MARK: - VolumeDataPoint

struct VolumeDataPoint: Identifiable {
    let id = UUID()
    let sessionIndex: Int
    let totalVolume: Double // weight × reps summed across all sets in that session
}

// MARK: - ExerciseLibraryViewModel

@Observable
@MainActor
final class ExerciseLibraryViewModel {

    // MARK: State

    var allExercises: [Exercise] = []
    var searchText: String = ""
    var selectedMuscleGroup: String? = nil
    var selectedEquipment: String? = nil
    var isLoading: Bool = false
    var errorMessage: String? = nil
    var showAddExercise: Bool = false
    var selectedExercise: Exercise? = nil

    // MARK: Add-exercise form fields

    var newExerciseName: String = ""
    var newExercisePrimaryMuscle: String = GymMuscleGroup.chest.rawValue
    var newExerciseEquipment: String = GymEquipment.barbell.rawValue
    var newExerciseSecondaryMuscles: Set<String> = []
    var isSaving: Bool = false

    // MARK: Filters

    let muscleGroupFilters: [String] = ["All"] + GymMuscleGroup.allCases.map(\.rawValue)
    let equipmentFilters: [String] = ["All", "Barbell", "Dumbbell", "Cable", "Machine", "Bodyweight", "Cardio"]

    // MARK: Computed

    var filteredExercises: [Exercise] {
        var results = allExercises

        // Search — case-insensitive, in-memory
        if !searchText.isEmpty {
            let lower = searchText.lowercased()
            results = results.filter {
                $0.name.lowercased().contains(lower) ||
                $0.primaryMuscle.lowercased().contains(lower)
            }
        }

        // Muscle group filter
        if let muscle = selectedMuscleGroup {
            results = results.filter {
                $0.primaryMuscle == muscle || $0.secondaryMuscles.contains(muscle)
            }
        }

        // Equipment filter
        if let equipment = selectedEquipment {
            // "Cardio" is a category, not equipment — filter by category for that case
            if equipment == "Cardio" {
                results = results.filter { $0.category.lowercased() == "cardio" }
            } else {
                results = results.filter { $0.equipment == equipment }
            }
        }

        return results
    }

    // MARK: Load

    func load() async {
        isLoading = true
        await Task.yield()
        do {
            try GymRepository.shared.seedExerciseLibraryIfNeeded()
            allExercises = try GymRepository.shared.fetchExercises()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    // MARK: Add Exercise

    func saveNewExercise() async {
        guard !newExerciseName.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        isSaving = true
        defer { isSaving = false }

        let exercise = Exercise(
            name: newExerciseName.trimmingCharacters(in: .whitespaces),
            category: "Strength",
            primaryMuscle: newExercisePrimaryMuscle,
            secondaryMuscles: Array(newExerciseSecondaryMuscles),
            equipment: newExerciseEquipment,
            isCustom: true
        )

        do {
            try GymRepository.shared.saveExercise(exercise)
            allExercises = try GymRepository.shared.fetchExercises()
            resetNewExerciseForm()
            showAddExercise = false
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func resetNewExerciseForm() {
        newExerciseName = ""
        newExercisePrimaryMuscle = GymMuscleGroup.chest.rawValue
        newExerciseEquipment = GymEquipment.barbell.rawValue
        newExerciseSecondaryMuscles = []
    }

    // MARK: PR helper

    func personalRecord(for exercise: Exercise, userId: String) -> PersonalRecord? {
        let records = (try? GymRepository.shared.fetchPersonalRecords(userId: userId)) ?? []
        return records.first { $0.exerciseId == exercise.id }
    }

    // MARK: Volume history helper

    func volumeHistory(for exercise: Exercise, userId: String) -> [VolumeDataPoint] {
        let sessions = (try? GymRepository.shared.fetchSessions(userId: userId, limit: 100)) ?? []
        let completed = sessions
            .filter { $0.isCompleted }
            .sorted { $0.startedAt < $1.startedAt }

        var points: [VolumeDataPoint] = []
        var sessionIndex = 0

        for session in completed {
            for entry in session.entries where entry.exerciseId == exercise.id {
                let volume = entry.sets.reduce(0.0) { $0 + $1.weight * Double($1.reps) }
                if volume > 0 {
                    points.append(VolumeDataPoint(sessionIndex: sessionIndex, totalVolume: volume))
                    sessionIndex += 1
                }
            }
        }

        return Array(points.suffix(6))
    }
}

// MARK: - ExerciseLibraryView

@MainActor
struct ExerciseLibraryView: View {

    @Environment(AppState.self) private var appState
    @State private var viewModel = ExerciseLibraryViewModel()
    @Environment(\.dismiss) private var dismiss

    private var uid: String {
        appState.authManager.currentUser?.uid ?? "preview-user"
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: 0) {
                    searchBar
                    filterChips
                    Divider()
                        .background(Color.white.opacity(0.06))

                    if viewModel.isLoading {
                        Spacer()
                        ProgressView()
                            .tint(Color.kineticsBlue)
                        Spacer()
                    } else if viewModel.filteredExercises.isEmpty {
                        emptyState
                    } else {
                        exerciseList
                    }
                }
            }
            .navigationTitle("Exercise Library")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.black, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Color.kineticsBlue)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        viewModel.showAddExercise = true
                    } label: {
                        Image(systemName: "plus")
                            .foregroundStyle(Color.kineticsBlue)
                            .fontWeight(.semibold)
                    }
                }
            }
            .sheet(isPresented: $viewModel.showAddExercise) {
                AddExerciseSheet(viewModel: viewModel)
            }
            .sheet(item: $viewModel.selectedExercise) { exercise in
                ExerciseDetailView(exercise: exercise, userId: uid)
            }
            .task { await viewModel.load() }
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

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color.kineticsSubtext)

            TextField("Search exercises", text: $viewModel.searchText)
                .foregroundStyle(.white)
                .tint(Color.kineticsBlue)
                .font(.system(size: 15))
                .autocorrectionDisabled()

            if !viewModel.searchText.isEmpty {
                Button {
                    viewModel.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color.kineticsSubtext)
                        .font(.system(size: 15))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(white: 0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    // MARK: - Filter Chips

    private var filterChips: some View {
        VStack(spacing: 6) {
            // Row 1: Muscle groups (blue)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    ForEach(viewModel.muscleGroupFilters, id: \.self) { filter in
                        let isAll = filter == "All"
                        let isSelected = isAll
                            ? viewModel.selectedMuscleGroup == nil
                            : viewModel.selectedMuscleGroup == filter

                        LibraryFilterChip(
                            title: filter,
                            isSelected: isSelected,
                            accentColor: Color.kineticsBlue
                        ) {
                            viewModel.selectedMuscleGroup = isAll ? nil : filter
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
            }

            // Row 2: Equipment type (green)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    ForEach(viewModel.equipmentFilters, id: \.self) { filter in
                        let isAll = filter == "All"
                        let isSelected = isAll
                            ? viewModel.selectedEquipment == nil
                            : viewModel.selectedEquipment == filter

                        LibraryFilterChip(
                            title: filter,
                            isSelected: isSelected,
                            accentColor: Color.kineticsGreen
                        ) {
                            viewModel.selectedEquipment = isAll ? nil : filter
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
            }
        }
        .padding(.bottom, 6)
    }

    // MARK: - Exercise List

    private var exerciseList: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 8) {
                ForEach(viewModel.filteredExercises, id: \.id) { exercise in
                    ExerciseListCard(
                        exercise: exercise,
                        pr: viewModel.personalRecord(for: exercise, userId: uid)
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        viewModel.selectedExercise = exercise
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 24)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer()

            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color(white: 0.08))
                    .frame(width: 84, height: 84)

                Image(systemName: "dumbbell")
                    .font(.system(size: 36, weight: .light))
                    .foregroundStyle(Color.kineticsBlue.opacity(0.6))
            }

            VStack(spacing: 8) {
                Text(viewModel.searchText.isEmpty && viewModel.selectedMuscleGroup == nil && viewModel.selectedEquipment == nil
                     ? "No exercises yet"
                     : "No matching exercises")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)

                Text(viewModel.searchText.isEmpty && viewModel.selectedMuscleGroup == nil && viewModel.selectedEquipment == nil
                     ? "Add your first one."
                     : "Try adjusting your search or filters.")
                    .font(.subheadline)
                    .foregroundStyle(Color.kineticsSubtext)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            if viewModel.searchText.isEmpty && viewModel.selectedMuscleGroup == nil && viewModel.selectedEquipment == nil {
                Button {
                    viewModel.showAddExercise = true
                } label: {
                    Label("Add Exercise", systemImage: "plus.circle.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(
                            Capsule()
                                .fill(Color.kineticsBlue)
                        )
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    viewModel.searchText = ""
                    viewModel.selectedMuscleGroup = nil
                    viewModel.selectedEquipment = nil
                } label: {
                    Text("Clear Filters")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.kineticsBlue)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.kineticsBlue.opacity(0.12))
                        )
                }
                .buttonStyle(.plain)
            }

            Spacer()
        }
    }
}

// MARK: - LibraryFilterChip

private struct LibraryFilterChip: View {
    let title: String
    let isSelected: Bool
    let accentColor: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? .black : Color.kineticsSubtext)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(isSelected ? accentColor : Color(white: 0.1))
                        .overlay(
                            Capsule()
                                .strokeBorder(
                                    isSelected ? Color.clear : accentColor.opacity(0.2),
                                    lineWidth: 1
                                )
                        )
                )
                .animation(.spring(duration: 0.18), value: isSelected)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - ExerciseListCard

private struct ExerciseListCard: View {

    let exercise: Exercise
    let pr: PersonalRecord?

    // MARK: Muscle group → color mapping

    private var muscleColor: Color {
        switch exercise.primaryMuscle {
        case "Chest":                return Color.kineticsBlue
        case "Back":                 return Color.kineticsPurple
        case "Shoulders", "Rear Delts": return Color.kineticsOrange
        case "Biceps", "Forearms":   return Color.kineticsGreen
        case "Triceps":              return Color(red: 0.2, green: 0.8, blue: 0.6)
        case "Core":                 return Color.kineticsAmber
        case "Quadriceps", "Hamstrings": return Color.kineticsRed
        case "Glutes", "Calves":     return Color.kineticsOrange
        case "Full Body":            return Color.kineticsBlue
        default:                     return Color.kineticsSubtext
        }
    }

    // MARK: Equipment → SF Symbol

    private var equipmentSymbol: String {
        switch exercise.equipment {
        case "Barbell":    return "cylinder.split.1x2"
        case "Dumbbell":   return "dumbbell.fill"
        case "Cable":      return "point.3.connected.trianglepath.dotted"
        case "Machine":    return "gearshape.2.fill"
        case "Bodyweight": return "figure.strengthtraining.traditional"
        case "Kettlebell": return "drop.circle.fill"
        default:           return "figure.mixed.cardio"
        }
    }

    // MARK: PR badge text

    private var prBadgeText: String? {
        guard let pr else { return nil }
        if pr.weight == 0 { return nil }
        let kg = pr.weight.truncatingRemainder(dividingBy: 1) == 0
            ? String(Int(pr.weight)) : String(format: "%.1f", pr.weight)
        return "PR \(kg)kg"
    }

    // MARK: Secondary muscles summary

    private var secondaryText: String {
        let parts = ([exercise.primaryMuscle] + exercise.secondaryMuscles)
            .filter { !$0.isEmpty }
        guard !parts.isEmpty else { return exercise.equipment }
        if parts.count == 1 { return parts[0] }
        return parts[0] + " · " + parts.dropFirst().joined(separator: ", ")
    }

    // MARK: Body

    var body: some View {
        HStack(spacing: 14) {
            // Left: color dot + equipment icon
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(muscleColor.opacity(0.15))
                    .frame(width: 44, height: 44)

                Image(systemName: equipmentSymbol)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(muscleColor)
            }

            // Center
            VStack(alignment: .leading, spacing: 3) {
                Text(exercise.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Text(secondaryText)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.kineticsSubtext)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            // Right: PR badge
            if let badge = prBadgeText {
                Text(badge)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.kineticsAmber)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(Color.kineticsAmber.opacity(0.14))
                    )
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.kineticsSubtext.opacity(0.4))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(white: 0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
                )
        )
    }
}

// MARK: - ExerciseDetailView

struct ExerciseDetailView: View {

    let exercise: Exercise
    let userId: String

    @Environment(\.dismiss) private var dismiss
    @State private var pr: PersonalRecord? = nil
    @State private var volumeHistory: [VolumeDataPoint] = []
    @State private var isLoaded: Bool = false

    // MARK: Muscle color

    private var muscleColor: Color {
        switch exercise.primaryMuscle {
        case "Chest":                return Color.kineticsBlue
        case "Back":                 return Color.kineticsPurple
        case "Shoulders", "Rear Delts": return Color.kineticsOrange
        case "Biceps", "Forearms":   return Color.kineticsGreen
        case "Triceps":              return Color(red: 0.2, green: 0.8, blue: 0.6)
        case "Core":                 return Color.kineticsAmber
        case "Quadriceps", "Hamstrings": return Color.kineticsRed
        case "Glutes", "Calves":     return Color.kineticsOrange
        case "Full Body":            return Color.kineticsBlue
        default:                     return Color.kineticsSubtext
        }
    }

    // MARK: Body

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 16) {
                        headerSection
                        instructionsCard
                        if pr != nil { prCard }
                        if !volumeHistory.isEmpty { volumeChart }
                        actionButtons
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 20)
                    .padding(.bottom, 40)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.black, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Color.kineticsBlue)
                }
            }
            .task { await loadData() }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(exercise.name)
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                // Muscle group chip
                Text(exercise.primaryMuscle)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(muscleColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Capsule()
                            .fill(muscleColor.opacity(0.15))
                    )

                // Equipment chip
                Text(exercise.equipment)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.kineticsSubtext)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Capsule()
                            .fill(Color(white: 0.1))
                    )

                if exercise.isCustom {
                    Text("Custom")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.kineticsPurple)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            Capsule()
                                .fill(Color.kineticsPurple.opacity(0.15))
                        )
                }
            }
        }
    }

    // MARK: - Instructions Card

    private var instructionsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Coaching Cues", systemImage: "list.bullet.clipboard")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.kineticsSubtext)
                .textCase(.uppercase)
                .kerning(0.5)

            if exercise.instructions.isEmpty {
                Text("No instructions available for this exercise.")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.kineticsSubtext)
            } else {
                let steps = exercise.instructions
                    .components(separatedBy: ". ")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }

                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .top, spacing: 12) {
                            Text("\(index + 1)")
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .foregroundStyle(Color.kineticsBlue)
                                .frame(width: 20, height: 20)
                                .background(
                                    Circle()
                                        .fill(Color.kineticsBlue.opacity(0.12))
                                )

                            Text(step + (step.hasSuffix(".") ? "" : "."))
                                .font(.system(size: 14))
                                .foregroundStyle(.white.opacity(0.88))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(white: 0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
                )
        )
    }

    // MARK: - PR Card

    @ViewBuilder
    private var prCard: some View {
        if let record = pr {
            VStack(alignment: .leading, spacing: 12) {
                Label("Personal Record", systemImage: "trophy.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.kineticsAmber)
                    .textCase(.uppercase)
                    .kerning(0.5)

                HStack(spacing: 0) {
                    PRStatCell(
                        label: "Best Weight",
                        value: formattedWeight(record.weight),
                        color: Color.kineticsAmber
                    )
                    Divider()
                        .frame(height: 36)
                        .background(Color.white.opacity(0.08))
                    PRStatCell(
                        label: "Reps",
                        value: "\(record.reps)",
                        color: Color.kineticsAmber
                    )
                    Divider()
                        .frame(height: 36)
                        .background(Color.white.opacity(0.08))
                    PRStatCell(
                        label: "Achieved",
                        value: formattedDate(record.achievedAt),
                        color: Color.kineticsAmber
                    )
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.kineticsAmber.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(Color.kineticsAmber.opacity(0.2), lineWidth: 1)
                    )
            )
        }
    }

    // MARK: - Volume Chart

    @ViewBuilder
    private var volumeChart: some View {
        if !volumeHistory.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Label("Volume History", systemImage: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.kineticsSubtext)
                    .textCase(.uppercase)
                    .kerning(0.5)

                Chart(volumeHistory) { point in
                    AreaMark(
                        x: .value("Session", point.sessionIndex),
                        y: .value("Volume (kg)", point.totalVolume)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.kineticsBlue.opacity(0.3), Color.kineticsBlue.opacity(0.0)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .interpolationMethod(.catmullRom)

                    LineMark(
                        x: .value("Session", point.sessionIndex),
                        y: .value("Volume (kg)", point.totalVolume)
                    )
                    .foregroundStyle(Color.kineticsBlue)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                    .interpolationMethod(.catmullRom)

                    PointMark(
                        x: .value("Session", point.sessionIndex),
                        y: .value("Volume (kg)", point.totalVolume)
                    )
                    .foregroundStyle(Color.kineticsBlue)
                    .symbolSize(30)
                }
                .frame(height: 120)
                .chartXAxis(.hidden)
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) {
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(Color.white.opacity(0.08))
                        AxisValueLabel()
                            .foregroundStyle(Color.kineticsSubtext)
                            .font(.system(size: 10))
                    }
                }
                .padding(.trailing, 4)

                Text("Last \(volumeHistory.count) session\(volumeHistory.count == 1 ? "" : "s") — total volume (kg × reps)")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.kineticsSubtext.opacity(0.7))
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(white: 0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
                    )
            )
        }
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        VStack(spacing: 10) {
            Button {
                dismiss()
            } label: {
                Text("Add to Workout")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(
                                LinearGradient(
                                    colors: [Color.kineticsBlue, Color.kineticsBlue.opacity(0.8)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                    )
            }
            .buttonStyle(.plain)

            Button {
                dismiss()
            } label: {
                Text("Add to Routine")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.kineticsBlue)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(Color.kineticsBlue.opacity(0.6), lineWidth: 1.5)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 8)
    }

    // MARK: - Data Loading

    private func loadData() async {
        let allPRs = await GymRepository.shared.fetchPersonalRecords(userId: userId)
        pr = allPRs.first { $0.exerciseId == exercise.id }

        let sessions = (try? GymRepository.shared.fetchSessions(userId: userId, limit: 100)) ?? []
        let completed = sessions
            .filter { $0.isCompleted }
            .sorted { $0.startedAt < $1.startedAt }

        var points: [VolumeDataPoint] = []
        var idx = 0
        for session in completed {
            for entry in session.entries where entry.exerciseId == exercise.id {
                let vol = entry.sets.reduce(0.0) { $0 + $1.weight * Double($1.reps) }
                if vol > 0 {
                    points.append(VolumeDataPoint(sessionIndex: idx, totalVolume: vol))
                    idx += 1
                }
            }
        }
        volumeHistory = Array(points.suffix(6))
        isLoaded = true
    }

    // MARK: - Formatting helpers

    private func formattedWeight(_ kg: Double) -> String {
        if kg == 0 { return "BW" }
        return kg.truncatingRemainder(dividingBy: 1) == 0
            ? "\(Int(kg)) kg" : String(format: "%.1f kg", kg)
    }

    private func formattedDate(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }
}

// MARK: - PRStatCell

private struct PRStatCell: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(color)

            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(Color.kineticsSubtext)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - AddExerciseSheet

struct AddExerciseSheet: View {

    @Bindable var viewModel: ExerciseLibraryViewModel
    @Environment(\.dismiss) private var dismiss

    private let allMuscles = GymMuscleGroup.allCases.map(\.rawValue)
    private let allEquipment = GymEquipment.allCases.map(\.rawValue)

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 24) {
                        nameField
                        primaryMuscleSection
                        equipmentSection
                        secondaryMusclesSection
                        saveButton
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 24)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("Add Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.black, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        viewModel.resetNewExerciseForm()
                        dismiss()
                    }
                    .foregroundStyle(Color.kineticsSubtext)
                }
            }
        }
    }

    // MARK: - Name Field

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 8) {
            fieldLabel("Exercise Name", required: true)

            TextField("e.g. Incline Dumbbell Curl", text: $viewModel.newExerciseName)
                .foregroundStyle(.white)
                .tint(Color.kineticsBlue)
                .font(.system(size: 15))
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color(white: 0.08))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                        )
                )
        }
    }

    // MARK: - Primary Muscle

    private var primaryMuscleSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            fieldLabel("Primary Muscle", required: false)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    ForEach(allMuscles, id: \.self) { muscle in
                        let isSelected = viewModel.newExercisePrimaryMuscle == muscle
                        Button {
                            viewModel.newExercisePrimaryMuscle = muscle
                        } label: {
                            Text(muscle)
                                .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                                .foregroundStyle(isSelected ? .black : Color.kineticsSubtext)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(
                                    Capsule()
                                        .fill(isSelected ? Color.kineticsBlue : Color(white: 0.1))
                                )
                        }
                        .buttonStyle(.plain)
                        .animation(.spring(duration: 0.18), value: isSelected)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    // MARK: - Equipment

    private var equipmentSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            fieldLabel("Equipment", required: false)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    ForEach(allEquipment, id: \.self) { eq in
                        let isSelected = viewModel.newExerciseEquipment == eq
                        Button {
                            viewModel.newExerciseEquipment = eq
                        } label: {
                            Text(eq)
                                .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                                .foregroundStyle(isSelected ? .black : Color.kineticsSubtext)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(
                                    Capsule()
                                        .fill(isSelected ? Color.kineticsGreen : Color(white: 0.1))
                                )
                        }
                        .buttonStyle(.plain)
                        .animation(.spring(duration: 0.18), value: isSelected)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    // MARK: - Secondary Muscles

    private var secondaryMusclesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            fieldLabel("Secondary Muscles", required: false)

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 8) {
                ForEach(allMuscles.filter { $0 != viewModel.newExercisePrimaryMuscle }, id: \.self) { muscle in
                    let isSelected = viewModel.newExerciseSecondaryMuscles.contains(muscle)
                    Button {
                        if isSelected {
                            viewModel.newExerciseSecondaryMuscles.remove(muscle)
                        } else {
                            viewModel.newExerciseSecondaryMuscles.insert(muscle)
                        }
                    } label: {
                        Text(muscle)
                            .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                            .foregroundStyle(isSelected ? .black : Color.kineticsSubtext)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(isSelected ? Color.kineticsPurple : Color(white: 0.1))
                            )
                    }
                    .buttonStyle(.plain)
                    .animation(.spring(duration: 0.18), value: isSelected)
                }
            }
        }
    }

    // MARK: - Save Button

    private var saveButton: some View {
        Button {
            Task { await viewModel.saveNewExercise() }
        } label: {
            Group {
                if viewModel.isSaving {
                    ProgressView()
                        .tint(.black)
                } else {
                    Text("Save Exercise")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.black)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(
                        viewModel.newExerciseName.trimmingCharacters(in: .whitespaces).isEmpty
                            ? Color.kineticsBlue.opacity(0.3)
                            : Color.kineticsBlue
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(viewModel.newExerciseName.trimmingCharacters(in: .whitespaces).isEmpty || viewModel.isSaving)
        .padding(.top, 8)
    }

    // MARK: - Field Label

    private func fieldLabel(_ text: String, required: Bool) -> some View {
        HStack(spacing: 4) {
            Text(text)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.kineticsSubtext)
                .textCase(.uppercase)
                .kerning(0.5)

            if required {
                Text("*")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.kineticsRed)
            }
        }
    }
}
