import SwiftData
import SwiftUI

// MARK: - WeeklyPlannerViewModel

@Observable
@MainActor
final class WeeklyPlannerViewModel {

    // MARK: State

    var plans: [WeeklyPlan] = []
    var isLoading = false
    var errorMessage: String?
    var showCreatePlan = false

    // MARK: Load

    func load(userId: String) {
        guard let container = GymRepository.shared.modelContainer else { return }
        let context = ModelContext(container)
        let uid = userId
        let descriptor = FetchDescriptor<WeeklyPlan>(
            predicate: #Predicate { $0.userId == uid },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        plans = (try? context.fetch(descriptor)) ?? []
    }

    func delete(plan: WeeklyPlan, userId: String) {
        guard let container = GymRepository.shared.modelContainer else { return }
        let context = ModelContext(container)
        let planId = plan.id
        let descriptor = FetchDescriptor<WeeklyPlan>(
            predicate: #Predicate { $0.id == planId }
        )
        if let found = try? context.fetch(descriptor).first {
            context.delete(found)
            try? context.save()
        }
        load(userId: userId)
    }

    func setActive(plan: WeeklyPlan, userId: String) {
        guard let container = GymRepository.shared.modelContainer else { return }
        let context = ModelContext(container)
        let uid = userId
        // Deactivate all
        let allDescriptor = FetchDescriptor<WeeklyPlan>(
            predicate: #Predicate { $0.userId == uid }
        )
        if let all = try? context.fetch(allDescriptor) {
            for p in all { p.isActive = false }
        }
        // Activate the selected one
        let planId = plan.id
        let singleDescriptor = FetchDescriptor<WeeklyPlan>(
            predicate: #Predicate { $0.id == planId }
        )
        if let found = try? context.fetch(singleDescriptor).first {
            found.isActive = true
        }
        try? context.save()
        load(userId: userId)
    }

    func activePlan(userId: String) -> WeeklyPlan? {
        plans.first { $0.isActive }
    }
}

// MARK: - WeeklyPlanListView

@MainActor
struct WeeklyPlanListView: View {

    @Environment(AppState.self) private var appState
    @State private var viewModel = WeeklyPlannerViewModel()
    @State private var showCreatePlan = false
    @State private var editingPlan: WeeklyPlan?

    private var uid: String {
        appState.authManager.currentUser?.uid ?? "preview-user"
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 0) {
                listHeader
                if viewModel.plans.isEmpty {
                    emptyState
                } else {
                    planList
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            HStack {
                Spacer()
                createButton
                    .padding(.trailing, 20)
                    .padding(.bottom, 16)
            }
            .background(Color.clear)
        }
        .onAppear { viewModel.load(userId: uid) }
        .sheet(isPresented: $showCreatePlan, onDismiss: { viewModel.load(userId: uid) }) {
            WeeklyPlanEditorView(existingPlan: nil)
        }
        .sheet(item: $editingPlan, onDismiss: { viewModel.load(userId: uid) }) { plan in
            WeeklyPlanEditorView(existingPlan: plan)
        }
    }

    // MARK: - Subviews

    private var listHeader: some View {
        HStack {
            Text("WEEKLY SPLITS")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.kineticsSubtext)
                .kerning(0.8)
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    private var planList: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 12) {
                ForEach(viewModel.plans, id: \.id) { plan in
                    WeeklyPlanCard(
                        plan: plan,
                        onEdit: { editingPlan = plan },
                        onSetActive: { viewModel.setActive(plan: plan, userId: uid) },
                        onDelete: { viewModel.delete(plan: plan, userId: uid) }
                    )
                }
            }
            .padding(.horizontal, 16)
            // Bottom padding so the last card clears the FAB + home indicator
            .padding(.bottom, 80)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "calendar.badge.plus")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(Color.kineticsBlue.opacity(0.4))

            VStack(spacing: 6) {
                Text("No splits yet")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                Text("Create a weekly split to plan your training")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.kineticsSubtext)
                    .multilineTextAlignment(.center)
            }

            Button {
                showCreatePlan = true
            } label: {
                Text("Create Split")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.kineticsBlue)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 11)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.kineticsBlue.opacity(0.12))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .strokeBorder(Color.kineticsBlue.opacity(0.3), lineWidth: 1)
                            )
                    )
            }
            .buttonStyle(.plain)
            Spacer()
        }
        .padding(.horizontal, 32)
    }

    private var createButton: some View {
        Button {
            showCreatePlan = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .bold))
                Text("New Split")
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundStyle(.black)
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(
                Capsule()
                    .fill(Color.kineticsBlue)
                    .shadow(color: Color.kineticsBlue.opacity(0.5), radius: 12, x: 0, y: 6)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - WeeklyPlanCard

private struct WeeklyPlanCard: View {
    let plan: WeeklyPlan
    let onEdit: () -> Void
    let onSetActive: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header row
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(plan.name)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)

                        if plan.isActive {
                            activeBadge
                        }
                    }

                    Text(dateRangeLabel)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(Color.kineticsSubtext)
                }

                Spacer()

                Menu {
                    Button { onEdit() } label: {
                        Label("Edit Split", systemImage: "pencil")
                    }
                    if !plan.isActive {
                        Button { onSetActive() } label: {
                            Label("Set as Active", systemImage: "checkmark.circle")
                        }
                    }
                    Divider()
                    Button(role: .destructive) { onDelete() } label: {
                        Label("Delete", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Color.kineticsSubtext)
                        .frame(width: 32, height: 32)
                }
            }

            // 7-day chip strip
            dayChipStrip

            // Repeat info
            if plan.repeatType != "none" {
                repeatLabel
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(white: 0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(
                            plan.isActive
                                ? Color.kineticsBlue.opacity(0.45)
                                : Color.white.opacity(0.06),
                            lineWidth: plan.isActive ? 1.5 : 1
                        )
                )
        )
    }

    // MARK: Sub-views

    private var activeBadge: some View {
        Text("ACTIVE")
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(Color.kineticsGreen)
            .kerning(0.5)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(Color.kineticsGreen.opacity(0.15))
            )
    }

    private var dayChipStrip: some View {
        let slots = plan.slots
        let weekDays = ["S", "M", "T", "W", "T", "F", "S"]
        return HStack(spacing: 5) {
            ForEach(0..<7, id: \.self) { dow in
                let slot = slots.first { $0.dayOfWeek == dow }
                DayChip(
                    dayLetter: weekDays[dow],
                    slot: slot,
                    isToday: dow == currentDayOfWeek
                )
            }
            Spacer()
        }
    }

    private var repeatLabel: some View {
        HStack(spacing: 5) {
            Image(systemName: "repeat")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.kineticsAmber)
            Text(repeatText)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.kineticsAmber)
        }
    }

    // MARK: Helpers

    private var currentDayOfWeek: Int {
        Calendar.current.component(.weekday, from: Date()) - 1 // 0=Sun
    }

    private var dateRangeLabel: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        let start = formatter.string(from: plan.startDate)
        if plan.repeatType == "none" {
            return "Started \(start)"
        }
        let weeks = plan.repeatWeeks == 0 ? "∞" : "\(plan.repeatWeeks)"
        return "Started \(start) · \(weeks) weeks"
    }

    private var repeatText: String {
        if plan.repeatType == "none" { return "No repeat" }
        if plan.repeatWeeks == 0 { return "Repeats indefinitely" }
        return "Repeats \(plan.repeatWeeks) \(plan.repeatWeeks == 1 ? "week" : "weeks")"
    }
}

// MARK: - DayChip

private struct DayChip: View {
    let dayLetter: String
    let slot: WeeklyDaySlot?
    let isToday: Bool

    private var accentColor: Color {
        guard let slot, slot.routineId != nil else { return Color(white: 0.2) }
        return muscleColor(slot.muscleGroups.first)
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(slot?.routineId != nil ? accentColor.opacity(0.2) : Color(white: 0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(
                            isToday ? Color.kineticsBlue : accentColor.opacity(0.5),
                            lineWidth: isToday ? 1.5 : 1
                        )
                )
                .frame(width: 32, height: 36)

            VStack(spacing: 2) {
                Text(dayLetter)
                    .font(.system(size: 11, weight: isToday ? .bold : .semibold))
                    .foregroundStyle(isToday ? Color.kineticsBlue : .white)

                if slot?.routineId != nil {
                    Circle()
                        .fill(accentColor)
                        .frame(width: 5, height: 5)
                } else {
                    Circle()
                        .fill(Color(white: 0.3))
                        .frame(width: 5, height: 5)
                }
            }
        }
    }

    private func muscleColor(_ group: String?) -> Color {
        guard let group else { return Color.kineticsBlue }
        return GymMuscleGroup(rawValue: group)?.color ?? Color.kineticsBlue
    }
}

// MARK: - WeeklyPlanEditorView

@MainActor
struct WeeklyPlanEditorView: View {

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let existingPlan: WeeklyPlan?

    // MARK: State

    @State private var planName: String = "My Split"
    @State private var startDate: Date = Date()
    @State private var repeatType: String = "none"
    @State private var repeatWeeks: Int = 4
    @State private var slots: [WeeklyDaySlot] = []
    @State private var routines: [Routine] = []
    @State private var editingSlotIndex: Int?
    @State private var isSaving = false

    private let repeatOptions: [(label: String, type: String, weeks: Int)] = [
        ("None", "none", 0),
        ("2 Weeks", "weeks", 2),
        ("4 Weeks", "weeks", 4),
        ("8 Weeks", "weeks", 8)
    ]

    private var uid: String {
        appState.authManager.currentUser?.uid ?? "preview-user"
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 24) {
                        nameField
                        startDateField
                        repeatPicker
                        daySlotsSection
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    // Bottom padding to clear home indicator and keyboard
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle(existingPlan == nil ? "New Split" : "Edit Split")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.black, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.kineticsSubtext)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: save) {
                        if isSaving {
                            ProgressView().tint(Color.kineticsBlue)
                        } else {
                            Text("Save")
                                .foregroundStyle(Color.kineticsBlue)
                                .fontWeight(.semibold)
                        }
                    }
                    .disabled(planName.isEmpty || isSaving)
                }
            }
            .sheet(item: $editingSlotIndex) { index in
                DayAssignmentSheet(
                    slot: slots[index],
                    routines: routines,
                    onSave: { updated in
                        slots[index] = updated
                    }
                )
            }
        }
        .onAppear { configure() }
    }

    // MARK: - Form Fields

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 8) {
            fieldLabel("SPLIT NAME")
            TextField("e.g. PPL Split", text: $planName)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(white: 0.08))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
                        )
                )
        }
    }

    private var startDateField: some View {
        VStack(alignment: .leading, spacing: 8) {
            fieldLabel("START DATE")
            DatePicker("", selection: $startDate, displayedComponents: .date)
                .datePickerStyle(.compact)
                .colorScheme(.dark)
                .labelsHidden()
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(white: 0.08))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
                        )
                )
        }
    }

    private var repeatPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            fieldLabel("REPEAT")
            HStack(spacing: 8) {
                ForEach(repeatOptions, id: \.label) { option in
                    let isSelected = repeatType == option.type && (option.type == "none" || repeatWeeks == option.weeks)
                    Button {
                        repeatType = option.type
                        if option.type == "weeks" { repeatWeeks = option.weeks }
                    } label: {
                        Text(option.label)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(isSelected ? .black : Color.kineticsSubtext)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(
                                Capsule()
                                    .fill(isSelected ? Color.kineticsBlue : Color(white: 0.1))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var daySlotsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                fieldLabel("WEEKLY SCHEDULE")
                Spacer()
                Text("Tap to assign")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.kineticsSubtext)
            }

            VStack(spacing: 8) {
                ForEach(slots.indices, id: \.self) { index in
                    DaySlotRow(
                        slot: slots[index],
                        onTap: { editingSlotIndex = index }
                    )
                }
            }
        }
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Color.kineticsSubtext)
            .kerning(0.8)
    }

    // MARK: - Actions

    private func configure() {
        // Load routines
        if let container = GymRepository.shared.modelContainer {
            let context = ModelContext(container)
            let uidVal = uid
            let descriptor = FetchDescriptor<Routine>(
                predicate: #Predicate { $0.userId == uidVal },
                sortBy: [SortDescriptor(\.name)]
            )
            routines = (try? context.fetch(descriptor)) ?? []
        }

        // Pre-populate from existing plan or build fresh 7-day template
        if let plan = existingPlan {
            planName = plan.name
            startDate = plan.startDate
            repeatType = plan.repeatType
            repeatWeeks = plan.repeatWeeks
            slots = plan.slots
        } else {
            let dayNames = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
            slots = (0..<7).map { dow in
                WeeklyDaySlot(dayIndex: dow, dayOfWeek: dow, label: "Rest", muscleGroups: [])
            }
            _ = dayNames // suppress warning; dayNames are used in DaySlotRow
        }
    }

    private func save() {
        guard !planName.isEmpty else { return }
        guard let container = GymRepository.shared.modelContainer else { return }
        isSaving = true
        let context = ModelContext(container)

        if let existing = existingPlan {
            // Update existing plan in context
            let planId = existing.id
            let descriptor = FetchDescriptor<WeeklyPlan>(
                predicate: #Predicate { $0.id == planId }
            )
            if let found = try? context.fetch(descriptor).first {
                found.name = planName
                found.startDate = startDate
                found.repeatType = repeatType
                found.repeatWeeks = repeatType == "none" ? 0 : repeatWeeks
                found.slots = slots
            }
        } else {
            let plan = WeeklyPlan(
                userId: uid,
                name: planName,
                startDate: startDate,
                repeatType: repeatType,
                repeatWeeks: repeatType == "none" ? 0 : repeatWeeks,
                slots: slots,
                isActive: false
            )
            context.insert(plan)
        }

        try? context.save()
        isSaving = false
        dismiss()
    }
}

// MARK: - DaySlotRow

private struct DaySlotRow: View {
    let slot: WeeklyDaySlot
    let onTap: () -> Void

    private static let dayNames = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
    private var isToday: Bool {
        Calendar.current.component(.weekday, from: Date()) - 1 == slot.dayOfWeek
    }
    private var isRestDay: Bool { slot.routineId == nil }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Left border color indicator
                RoundedRectangle(cornerRadius: 2)
                    .fill(borderColor)
                    .frame(width: 3, height: 42)

                // Day name
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(Self.dayNames[safe: slot.dayOfWeek] ?? "Day \(slot.dayIndex)")
                            .font(.system(size: 14, weight: isToday ? .bold : .semibold))
                            .foregroundStyle(isToday ? Color.kineticsBlue : .white)
                        if isToday {
                            Text("TODAY")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(Color.kineticsBlue)
                                .kerning(0.4)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.kineticsBlue.opacity(0.15)))
                        }
                    }
                    Text(slot.label)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.kineticsSubtext)
                }

                Spacer()

                // Routine chip or Rest
                if let routineName = slot.routineName {
                    Text(routineName)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            Capsule().fill(Color.kineticsBlue.opacity(0.18))
                                .overlay(Capsule().strokeBorder(Color.kineticsBlue.opacity(0.3), lineWidth: 1))
                        )
                } else {
                    Text("REST")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.kineticsSubtext)
                        .kerning(0.4)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Color(white: 0.1)))
                }

                // Muscle group dots
                if !slot.muscleGroups.isEmpty {
                    HStack(spacing: 3) {
                        ForEach(slot.muscleGroups.prefix(3), id: \.self) { group in
                            Circle()
                                .fill(GymMuscleGroup(rawValue: group)?.color ?? Color.kineticsBlue)
                                .frame(width: 7, height: 7)
                        }
                    }
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.kineticsSubtext.opacity(0.5))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(white: 0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(
                                isToday ? Color.kineticsBlue.opacity(0.3) : Color.white.opacity(0.06),
                                lineWidth: 1
                            )
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private var borderColor: Color {
        if isRestDay { return Color(white: 0.25) }
        return GymMuscleGroup(rawValue: slot.muscleGroups.first ?? "")?.color ?? Color.kineticsBlue
    }
}

// MARK: - DayAssignmentSheet

struct DayAssignmentSheet: View {

    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState

    let slot: WeeklyDaySlot
    let onSave: (WeeklyDaySlot) -> Void

    @State private var routines: [Routine]
    @State private var selectedDayOfWeek: Int
    @State private var label: String
    @State private var selectedRoutineId: String?
    @State private var selectedRoutineName: String?
    @State private var muscleGroups: [String]
    @State private var showCreateRoutine = false

    private static let dayNames = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]

    private var uid: String {
        appState.authManager.currentUser?.uid ?? "preview-user"
    }

    init(slot: WeeklyDaySlot, routines: [Routine], onSave: @escaping (WeeklyDaySlot) -> Void) {
        self.slot = slot
        self.onSave = onSave
        _routines = State(initialValue: routines)
        _selectedDayOfWeek = State(initialValue: slot.dayOfWeek)
        _label = State(initialValue: slot.label == "Rest" ? "" : slot.label)
        _selectedRoutineId = State(initialValue: slot.routineId)
        _selectedRoutineName = State(initialValue: slot.routineName)
        _muscleGroups = State(initialValue: slot.muscleGroups)
    }

    private func reloadRoutines() {
        guard let container = GymRepository.shared.modelContainer else { return }
        let context = ModelContext(container)
        let uidVal = uid
        let descriptor = FetchDescriptor<Routine>(
            predicate: #Predicate { $0.userId == uidVal },
            sortBy: [SortDescriptor(\.name)]
        )
        routines = (try? context.fetch(descriptor)) ?? []
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 24) {
                        // Day of week picker
                        dayPicker
                        // Label
                        labelField
                        // Routine picker
                        routinePicker
                        // Muscle groups (manual override)
                        if selectedRoutineId != nil {
                            muscleGroupDisplay
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    // Bottom padding to clear home indicator inside a sheet
                    .padding(.bottom, 34)
                }
                // Reserve space at the bottom so the last item is always scrollable into view
                .safeAreaInset(edge: .bottom) {
                    Color.clear.frame(height: 0)
                }
            }
            .navigationTitle("Assign Day")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.black, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.kineticsSubtext)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { commit() }
                        .foregroundStyle(Color.kineticsBlue)
                        .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(Color.black)
        .sheet(isPresented: $showCreateRoutine, onDismiss: reloadRoutines) {
            RoutineBuilderView(userId: uid) {}
        }
    }

    // MARK: - Sections

    private var dayPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("DAY OF WEEK")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(0..<7, id: \.self) { dow in
                        let name = Self.dayNames[dow]
                        let isSelected = selectedDayOfWeek == dow
                        Button {
                            selectedDayOfWeek = dow
                        } label: {
                            VStack(spacing: 3) {
                                Text(String(name.prefix(3)))
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(isSelected ? .black : Color.kineticsSubtext)
                            }
                            .frame(width: 52, height: 36)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(isSelected ? Color.kineticsBlue : Color(white: 0.1))
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var labelField: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("LABEL (e.g. Push Day, Pull, Legs)")
            TextField("Push Day", text: $label)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(white: 0.08))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
                        )
                )
        }
    }

    private var routinePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("ROUTINE")

            // Create New Routine shortcut
            Button {
                showCreateRoutine = true
            } label: {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Color.kineticsPurple.opacity(0.18))
                            .frame(width: 28, height: 28)
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Color.kineticsPurple)
                    }

                    Text("+ Create New Routine")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.kineticsPurple)

                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.kineticsPurple.opacity(0.08))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(Color.kineticsPurple.opacity(0.25), lineWidth: 1)
                        )
                )
            }
            .buttonStyle(.plain)

            // Rest day option
            routineOption(id: nil, name: "Rest Day", subtitle: "No workout", isRest: true)

            // Routine options
            ForEach(routines, id: \.id) { routine in
                let muscles = routine.muscleGroupStrings.prefix(3).joined(separator: ", ")
                routineOption(
                    id: routine.id,
                    name: routine.name,
                    subtitle: muscles.isEmpty ? "\(routine.exerciseIds.count) exercises" : muscles,
                    isRest: false,
                    routine: routine
                )
            }
        }
    }

    private func routineOption(id: String?, name: String, subtitle: String, isRest: Bool, routine: Routine? = nil) -> some View {
        let isSelected = selectedRoutineId == id
        return Button {
            selectedRoutineId = id
            selectedRoutineName = isRest ? nil : name
            if let r = routine {
                muscleGroups = r.muscleGroupStrings
            } else {
                muscleGroups = []
            }
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(isSelected
                              ? (isRest ? Color.kineticsSubtext : Color.kineticsBlue)
                              : Color(white: 0.12))
                        .frame(width: 28, height: 28)
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.black)
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.kineticsSubtext)
                        .lineLimit(1)
                }

                Spacer()

                if let r = routine, !r.muscleGroups.isEmpty {
                    HStack(spacing: 3) {
                        ForEach(r.muscleGroups.prefix(3), id: \.rawValue) { mg in
                            Circle()
                                .fill(mg.color)
                                .frame(width: 8, height: 8)
                        }
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Color.kineticsBlue.opacity(0.1) : Color(white: 0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(
                                isSelected ? Color.kineticsBlue.opacity(0.4) : Color.white.opacity(0.06),
                                lineWidth: 1
                            )
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private var muscleGroupDisplay: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("MUSCLE GROUPS")
            HStack(spacing: 8) {
                ForEach(muscleGroups, id: \.self) { group in
                    let color = GymMuscleGroup(rawValue: group)?.color ?? Color.kineticsBlue
                    Text(group)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(color)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            Capsule().fill(color.opacity(0.15))
                        )
                }
            }
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Color.kineticsSubtext)
            .kerning(0.8)
    }

    // MARK: - Commit

    private func commit() {
        let resolvedLabel = label.isEmpty ? (selectedRoutineId == nil ? "Rest" : selectedRoutineName ?? "Workout") : label
        let updated = WeeklyDaySlot(
            id: slot.id,
            dayIndex: slot.dayIndex,
            dayOfWeek: selectedDayOfWeek,
            routineId: selectedRoutineId,
            routineName: selectedRoutineName,
            label: resolvedLabel,
            muscleGroups: muscleGroups
        )
        onSave(updated)
        dismiss()
    }
}

// MARK: - WeeklyCalendarStrip

struct WeeklyCalendarStrip: View {

    let activePlan: WeeklyPlan?
    let onDayTap: (WeeklyDaySlot) -> Void
    let onViewPlanTap: () -> Void

    private let calendar = Calendar.current
    private var currentDOW: Int { calendar.component(.weekday, from: Date()) - 1 }

    private static let dayLetters = ["S", "M", "T", "W", "T", "F", "S"]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Row header
            HStack(alignment: .center) {
                if let plan = activePlan {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(plan.name)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                        Text("Active Split")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color.kineticsSubtext)
                    }
                } else {
                    Text("No active split")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.kineticsSubtext)
                }

                Spacer()

                Button(action: onViewPlanTap) {
                    Text("VIEW PLAN")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.kineticsBlue)
                        .kerning(0.5)
                }
                .buttonStyle(.plain)
            }

            // 7-day strip
            HStack(spacing: 6) {
                ForEach(0..<7, id: \.self) { dow in
                    let slot = activePlan?.slots.first { $0.dayOfWeek == dow }
                    let isToday = dow == currentDOW
                    let isPast = dow < currentDOW

                    CalendarDayCell(
                        letter: Self.dayLetters[dow],
                        slot: slot,
                        isToday: isToday,
                        isPast: isPast,
                        onTap: {
                            if let s = slot, s.routineId != nil {
                                onDayTap(s)
                            }
                        }
                    )
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(white: 0.07))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
                )
        )
    }
}

// MARK: - CalendarDayCell

private struct CalendarDayCell: View {
    let letter: String
    let slot: WeeklyDaySlot?
    let isToday: Bool
    let isPast: Bool
    let onTap: () -> Void

    private var accentColor: Color {
        guard let slot, slot.routineId != nil else { return Color.kineticsSubtext }
        return GymMuscleGroup(rawValue: slot.muscleGroups.first ?? "")?.color ?? Color.kineticsBlue
    }

    private var hasRoutine: Bool { slot?.routineId != nil }

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 4) {
                // Day letter
                ZStack {
                    if isToday {
                        Circle()
                            .fill(Color.kineticsBlue)
                            .frame(width: 28, height: 28)
                    } else if hasRoutine {
                        Circle()
                            .fill(accentColor.opacity(0.2))
                            .frame(width: 28, height: 28)
                    } else {
                        Circle()
                            .fill(Color.clear)
                            .frame(width: 28, height: 28)
                    }

                    Text(letter)
                        .font(.system(size: 13, weight: isToday ? .bold : .semibold))
                        .foregroundStyle(
                            isToday ? .black :
                            hasRoutine ? (isPast ? accentColor.opacity(0.5) : accentColor) :
                            Color(white: isPast ? 0.3 : 0.55)
                        )
                }

                // Label below
                if let slot {
                    Text(slot.label)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(
                            isToday ? Color.kineticsBlue :
                            hasRoutine ? (isPast ? accentColor.opacity(0.45) : accentColor.opacity(0.8)) :
                            Color(white: 0.28)
                        )
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                } else {
                    Text("Rest")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(Color(white: isPast ? 0.2 : 0.3))
                }
            }
            .frame(maxWidth: .infinity)
            .opacity(isPast ? 0.6 : 1.0)
        }
        .buttonStyle(.plain)
        .disabled(!hasRoutine && !isToday)
    }
}

// MARK: - StartWorkoutSheet

struct StartWorkoutSheet: View {

    @Environment(\.dismiss) private var dismiss

    let activePlan: WeeklyPlan?
    let routines: [Routine]
    let onStart: (Routine?) -> Void
    /// Optional — pass the user's UID to enable "Create a Routine First" navigation in the empty state.
    var userId: String = ""

    @State private var selectedRoutineId: String?
    @State private var showRoutineBuilder = false

    private var todaySlot: WeeklyDaySlot? {
        let dow = Calendar.current.component(.weekday, from: Date()) - 1
        return activePlan?.slots.first { $0.dayOfWeek == dow }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 20) {
                        if routines.isEmpty {
                            // Empty state: two clear options
                            emptyStateSection
                        } else {
                            // Today's planned workout
                            if let slot = todaySlot, slot.routineId != nil {
                                todaySection(slot: slot)
                            }

                            // All routines
                            allRoutinesSection
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    // Bottom padding so the last routine row clears the sticky start button
                    .padding(.bottom, 20)
                }
                // Push scroll content above the sticky start button
                .safeAreaInset(edge: .bottom) {
                    Color.clear.frame(height: routines.isEmpty ? 20 : 88)
                }
            }
            .navigationTitle("Start Workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.black, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.kineticsSubtext)
                }
            }
            .safeAreaInset(edge: .bottom) {
                if !routines.isEmpty {
                    startButton
                }
            }
            .navigationDestination(isPresented: $showRoutineBuilder) {
                if !userId.isEmpty {
                    RoutineBuilderView(userId: userId) {
                        showRoutineBuilder = false
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(Color.black)
        .onAppear {
            // Pre-select today's planned routine if one exists
            if let slot = todaySlot, let rid = slot.routineId {
                selectedRoutineId = rid
            }
        }
    }

    // MARK: - Empty State

    private var emptyStateSection: some View {
        VStack(spacing: 14) {
            Text("How do you want to train?")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 4)

            // Option 1: Quick Start (Empty)
            Button {
                onStart(nil)
                dismiss()
            } label: {
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.kineticsBlue.opacity(0.15))
                            .frame(width: 50, height: 50)
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 22, weight: .medium))
                            .foregroundStyle(Color.kineticsBlue)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Quick Start (Empty)")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)
                        Text("No plan, just lift. Add exercises as you go.")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.kineticsSubtext)
                            .lineLimit(2)
                    }

                    Spacer()

                    Image(systemName: "arrow.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.kineticsBlue)
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(white: 0.09))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(Color.kineticsBlue.opacity(0.3), lineWidth: 1)
                        )
                )
            }
            .buttonStyle(.plain)

            // Option 2: Create a Routine First
            Button {
                if !userId.isEmpty {
                    showRoutineBuilder = true
                }
            } label: {
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.kineticsPurple.opacity(0.15))
                            .frame(width: 50, height: 50)
                        Image(systemName: "list.bullet.clipboard")
                            .font(.system(size: 22, weight: .medium))
                            .foregroundStyle(Color.kineticsPurple)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Create a Routine First")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)
                        Text("Build a template to reuse. Takes 2 minutes.")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.kineticsSubtext)
                            .lineLimit(2)
                    }

                    Spacer()

                    Image(systemName: "arrow.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.kineticsPurple)
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(white: 0.09))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(Color.kineticsPurple.opacity(0.3), lineWidth: 1)
                        )
                )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Sections

    private func todaySection(slot: WeeklyDaySlot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("TODAY'S PLAN")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.kineticsSubtext)
                .kerning(0.8)

            if let routine = routines.first(where: { $0.id == slot.routineId }) {
                let isSelected = selectedRoutineId == routine.id
                Button {
                    selectedRoutineId = routine.id
                } label: {
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.kineticsBlue.opacity(0.15))
                                .frame(width: 44, height: 44)
                            Image(systemName: "star.fill")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundStyle(Color.kineticsAmber)
                        }

                        VStack(alignment: .leading, spacing: 3) {
                            Text(routine.name)
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(.white)
                            Text("\(slot.label) · \(routine.exerciseIds.count) exercises")
                                .font(.system(size: 12))
                                .foregroundStyle(Color.kineticsSubtext)
                        }

                        Spacer()

                        if isSelected {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 20))
                                .foregroundStyle(Color.kineticsBlue)
                        }
                    }
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(isSelected ? Color.kineticsBlue.opacity(0.1) : Color(white: 0.09))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .strokeBorder(
                                        isSelected ? Color.kineticsBlue.opacity(0.5) : Color.white.opacity(0.08),
                                        lineWidth: 1.5
                                    )
                            )
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var allRoutinesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ALL ROUTINES")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.kineticsSubtext)
                .kerning(0.8)

            // Empty session option
            let isEmptySelected = selectedRoutineId == nil
            Button {
                selectedRoutineId = nil
            } label: {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color(white: 0.12))
                            .frame(width: 44, height: 44)
                        Image(systemName: "plus")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(Color.kineticsSubtext)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Empty Workout")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                        Text("Add exercises as you go")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.kineticsSubtext)
                    }
                    Spacer()
                    if isEmptySelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(Color.kineticsBlue)
                    }
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(isEmptySelected ? Color.kineticsBlue.opacity(0.1) : Color(white: 0.08))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .strokeBorder(
                                    isEmptySelected ? Color.kineticsBlue.opacity(0.5) : Color.white.opacity(0.06),
                                    lineWidth: 1
                                )
                        )
                )
            }
            .buttonStyle(.plain)

            // Each routine
            ForEach(routines, id: \.id) { routine in
                let isSelected = selectedRoutineId == routine.id
                Button {
                    selectedRoutineId = routine.id
                } label: {
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.kineticsBlue.opacity(0.12))
                                .frame(width: 44, height: 44)
                            Image(systemName: "figure.strengthtraining.traditional")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundStyle(Color.kineticsBlue)
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            Text(routine.name)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.white)
                            Text("\(routine.exerciseIds.count) exercises · ~\(routine.estimatedMinutes) min")
                                .font(.system(size: 12))
                                .foregroundStyle(Color.kineticsSubtext)
                        }
                        Spacer()
                        // Muscle color dots
                        HStack(spacing: 3) {
                            ForEach(routine.muscleGroups.prefix(3), id: \.rawValue) { mg in
                                Circle().fill(mg.color).frame(width: 7, height: 7)
                            }
                        }
                        if isSelected {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 20))
                                .foregroundStyle(Color.kineticsBlue)
                        }
                    }
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(isSelected ? Color.kineticsBlue.opacity(0.1) : Color(white: 0.08))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .strokeBorder(
                                        isSelected ? Color.kineticsBlue.opacity(0.5) : Color.white.opacity(0.06),
                                        lineWidth: 1
                                    )
                            )
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var startButton: some View {
        let selectedRoutine = routines.first { $0.id == selectedRoutineId }
        let label = selectedRoutineId == nil ? "Start Empty Workout" : "Start \(selectedRoutine?.name ?? "Workout")"
        return Button {
            let routine = routines.first { $0.id == selectedRoutineId }
            onStart(routine)
            dismiss()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "play.fill")
                    .font(.system(size: 15, weight: .bold))
                Text(label)
                    .font(.system(size: 16, weight: .bold))
                    .lineLimit(1)
            }
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 17)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.kineticsBlue)
                    .shadow(color: Color.kineticsBlue.opacity(0.45), radius: 16, x: 0, y: 6)
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
        // 34pt home indicator + 8pt visual breathing room
        .padding(.bottom, 34)
        .background(
            Color.black
                .ignoresSafeArea(edges: .bottom)
        )
    }
}

// MARK: - Collection Safe Subscript

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

// MARK: - Int Identifiable for Sheet

extension Int: @retroactive Identifiable {
    public var id: Int { self }
}
