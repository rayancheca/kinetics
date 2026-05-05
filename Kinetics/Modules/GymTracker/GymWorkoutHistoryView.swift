import SwiftUI

// MARK: - GymWorkoutHistoryViewModel

@Observable
@MainActor
final class GymWorkoutHistoryViewModel {

    // MARK: State

    var sessions: [WorkoutSession] = []
    var isLoading = false
    var errorMessage: String?
    var expandedSessionIds: Set<String> = []

    // MARK: - Derived: Stats

    var totalVolumeKg: Double {
        sessions.reduce(0) { $0 + $1.totalVolumeKg }
    }

    var avgSessionMinutes: Int {
        guard !sessions.isEmpty else { return 0 }
        let totalSeconds = sessions.reduce(0.0) { $0 + $1.duration }
        return Int(totalSeconds / Double(sessions.count) / 60)
    }

    var longestStreakDays: Int {
        guard !sessions.isEmpty else { return 0 }
        let sorted = sessions
            .filter { $0.isCompleted }
            .map { Calendar.current.startOfDay(for: $0.startedAt) }
            .sorted()
        var uniqueDays = Array(Set(sorted)).sorted()
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

    // MARK: - Derived: Calendar heatmap (12-week rolling)

    struct HeatDay: Identifiable {
        let id: String
        let date: Date
        let volumeKg: Double
        let hasWorkout: Bool
    }

    var heatDays: [HeatDay] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        guard let start = cal.date(byAdding: .day, value: -83, to: today) else { return [] }

        // Build a lookup: startOfDay -> totalVolume
        var volumeByDay: [Date: Double] = [:]
        for session in sessions {
            let day = cal.startOfDay(for: session.startedAt)
            volumeByDay[day, default: 0] += session.totalVolumeKg
        }

        var days: [HeatDay] = []
        var cursor = start
        while cursor <= today {
            let vol = volumeByDay[cursor] ?? 0
            days.append(HeatDay(
                id: cursor.timeIntervalSince1970.description,
                date: cursor,
                volumeKg: vol,
                hasWorkout: vol > 0
            ))
            cursor = cal.date(byAdding: .day, value: 1, to: cursor) ?? cursor
        }
        return days
    }

    var maxVolumeInHeatmap: Double {
        heatDays.map(\.volumeKg).max() ?? 1
    }

    // MARK: - Derived: Grouped sessions by month

    struct MonthGroup: Identifiable {
        let id: String
        let title: String
        let sessions: [WorkoutSession]
        var totalVolumeKg: Double {
            sessions.reduce(0) { $0 + $1.totalVolumeKg }
        }
    }

    var groupedByMonth: [MonthGroup] {
        let cal = Calendar.current
        var map: [Date: [WorkoutSession]] = [:]
        for session in sessions {
            let components = cal.dateComponents([.year, .month], from: session.startedAt)
            let key = cal.date(from: components) ?? session.startedAt
            map[key, default: []].append(session)
        }
        let fmt = DateFormatter()
        fmt.dateFormat = "MMMM yyyy"
        return map.keys
            .sorted(by: >)
            .compactMap { key -> MonthGroup? in
                guard let list = map[key], !list.isEmpty else { return nil }
                let sorted = list.sorted { $0.startedAt > $1.startedAt }
                return MonthGroup(
                    id: key.timeIntervalSince1970.description,
                    title: fmt.string(from: key),
                    sessions: sorted
                )
            }
    }

    // MARK: - Toggle expansion

    func toggleExpansion(for session: WorkoutSession) {
        if expandedSessionIds.contains(session.id) {
            expandedSessionIds.remove(session.id)
        } else {
            expandedSessionIds.insert(session.id)
        }
    }

    // MARK: - Load

    func load(userId: String) async {
        isLoading = true
        defer { isLoading = false }
        errorMessage = nil
        do {
            sessions = try GymRepository.shared.fetchSessions(userId: userId, limit: 200)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Delete

    func delete(_ session: WorkoutSession) {
        do {
            try GymRepository.shared.deleteSession(session)
            sessions.removeAll { $0.id == session.id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - GymWorkoutHistoryView

@MainActor
struct GymWorkoutHistoryView: View {

    let userId: String

    @State private var viewModel = GymWorkoutHistoryViewModel()
    @State private var path = NavigationPath()
    @State private var scrollProxy: ScrollViewProxy? = nil
    @State private var highlightedDay: Date? = nil
    @State private var sessionToShare: WorkoutSession?

    // MARK: - Share helpers

    private func activity(from session: WorkoutSession) -> PostComposerActivity {
        let exercises: [ExerciseSummary] = session.entries.map { entry in
            let completedSets = entry.sets.filter { $0.isCompleted }
            let topWeight = completedSets.map(\.weight).max() ?? 0
            return ExerciseSummary(
                name: entry.exerciseName,
                sets: completedSets.count,
                topWeightKg: topWeight,
                totalReps: completedSets.reduce(0) { $0 + $1.reps },
                muscleGroup: ""
            )
        }
        let totalVolume = session.totalVolumeKg
        let durationMinutes = Int(session.duration) / 60
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MMM d"
        let dateStr = dateFormatter.string(from: session.startedAt)
        return PostComposerActivity(
            kind: .gym(exercises: exercises, totalVolume: totalVolume, durationMinutes: durationMinutes),
            sessionTitle: session.notes ?? "Workout · \(dateStr)"
        )
    }

    var body: some View {
        // NOTE: No NavigationStack wrapper here — this view is pushed
        // into the parent NavigationStack from GymHomeView via navigationPath.
        ZStack {
            Color.black.ignoresSafeArea()
            mainContent
        }
        .navigationTitle("History")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.black, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task { await viewModel.load(userId: userId) }
        .sheet(item: $sessionToShare) { session in
            PostComposerView(
                currentUserId: userId,
                currentDisplayName: session.notes ?? "Athlete",
                username: "",
                initialCaption: "Just finished \(session.notes ?? "a workout")! 💪",
                initialActivity: activity(from: session),
                onPost: { _ in }
            )
        }
    }

    // MARK: - Main Content

    @ViewBuilder
    private var mainContent: some View {
        if viewModel.isLoading {
            loadingState
        } else if viewModel.sessions.isEmpty {
            emptyState
        } else {
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 0, pinnedViews: []) {
                        // Large header
                        headerSection
                            .padding(.bottom, 20)

                        // Stats bar
                        statsBar
                            .padding(.horizontal, 16)
                            .padding(.bottom, 24)

                        // Calendar heatmap
                        heatmapSection
                            .padding(.bottom, 24)

                        // Month groups
                        ForEach(viewModel.groupedByMonth) { group in
                            monthSection(group: group)
                        }

                        Spacer().frame(height: 48)
                    }
                }
                .onAppear { scrollProxy = proxy }
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("History")
                .font(.system(size: 38, weight: .black))
                .foregroundStyle(.white)

            HStack(spacing: 6) {
                Text("\(viewModel.sessions.count) sessions total")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.kineticsSubtext)

                Text("·")
                    .foregroundStyle(Color.kineticsSubtext.opacity(0.5))

                Text(formattedTotalVolume)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.kineticsGreen)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
    }

    private var formattedTotalVolume: String {
        let kg = viewModel.totalVolumeKg
        if kg == 0 { return "0 kg" }
        if kg >= 1_000_000 { return String(format: "%.1fM kg", kg / 1_000_000) }
        if kg >= 1000 { return String(format: "%.1fk kg", kg / 1000) }
        return "\(Int(kg)) kg"
    }

    // MARK: - Stats Bar

    private var statsBar: some View {
        HStack(spacing: 10) {
            statTile(
                label: "Longest Streak",
                value: "\(viewModel.longestStreakDays)",
                unit: "days",
                icon: "flame.fill",
                color: Color.kineticsAmber
            )
            statTile(
                label: "Total Volume",
                value: compactVolume(viewModel.totalVolumeKg),
                unit: "kg",
                icon: "scalemass.fill",
                color: Color.kineticsGreen
            )
            statTile(
                label: "Avg Duration",
                value: "\(viewModel.avgSessionMinutes)",
                unit: "min",
                icon: "clock.fill",
                color: Color.kineticsBlue
            )
        }
    }

    private func compactVolume(_ kg: Double) -> String {
        if kg >= 1_000_000 { return String(format: "%.1fM", kg / 1_000_000) }
        if kg >= 1000 { return String(format: "%.1fk", kg / 1000) }
        return "\(Int(kg))"
    }

    private func statTile(label: String, value: String, unit: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(color)
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.kineticsSubtext)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            HStack(alignment: .lastTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                Text(unit)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(color.opacity(0.8))
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(white: 0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(color.opacity(0.18), lineWidth: 1)
                )
        )
    }

    // MARK: - Heatmap

    private var heatmapSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Activity")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.kineticsSubtext)
                    .textCase(.uppercase)
                    .kerning(0.8)
                Spacer()
                Text("12 weeks")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.kineticsSubtext.opacity(0.5))
            }
            .padding(.horizontal, 20)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 4) {
                    Spacer().frame(width: 12)
                    ForEach(viewModel.heatDays) { day in
                        HeatDayCell(
                            day: day,
                            maxVolume: viewModel.maxVolumeInHeatmap,
                            isHighlighted: highlightedDay.map {
                                Calendar.current.isDate($0, inSameDayAs: day.date)
                            } ?? false
                        )
                        .id("heat-\(day.id)")
                        .onTapGesture {
                            scrollToDay(day.date)
                        }
                    }
                    Spacer().frame(width: 12)
                }
                .padding(.vertical, 4)
            }
            .frame(height: 44)
        }
    }

    private func scrollToDay(_ date: Date) {
        highlightedDay = date
        // Find the nearest session on that day and scroll to it
        let cal = Calendar.current
        let target = cal.startOfDay(for: date)
        guard let session = viewModel.sessions.first(where: {
            cal.startOfDay(for: $0.startedAt) == target
        }) else { return }
        withAnimation(.spring(duration: 0.4)) {
            scrollProxy?.scrollTo("session-\(session.id)", anchor: .top)
        }
    }

    // MARK: - Month Section

    private func monthSection(group: GymWorkoutHistoryViewModel.MonthGroup) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Section header
            HStack {
                Text(group.title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    Text("\(group.sessions.count) session\(group.sessions.count == 1 ? "" : "s")")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.kineticsSubtext)
                    Text(compactVolume(group.totalVolumeKg) + " kg")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.kineticsGreen.opacity(0.8))
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)

            // Sessions in this month
            VStack(spacing: 8) {
                ForEach(group.sessions, id: \.id) { session in
                    GymHistorySessionRow(
                        session: session,
                        isExpanded: viewModel.expandedSessionIds.contains(session.id),
                        onTap: {
                            withAnimation(.spring(duration: 0.3)) {
                                viewModel.toggleExpansion(for: session)
                            }
                        },
                        onDelete: { viewModel.delete(session) },
                        onShare: { sessionToShare = session }
                    )
                    .id("session-\(session.id)")
                    .padding(.horizontal, 16)
                }
            }
            .padding(.bottom, 16)

            Divider()
                .background(Color.white.opacity(0.06))
        }
    }

    // MARK: - Loading State

    private var loadingState: some View {
        VStack(spacing: 20) {
            Spacer()
            ProgressView()
                .tint(Color.kineticsBlue)
                .scaleEffect(1.3)
            Text("Loading workouts…")
                .font(.system(size: 14))
                .foregroundStyle(Color.kineticsSubtext)
            Spacer()
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()

            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color(white: 0.08))
                    .frame(width: 80, height: 80)
                Image(systemName: "dumbbell")
                    .font(.system(size: 34, weight: .medium))
                    .foregroundStyle(Color.kineticsBlue.opacity(0.5))
            }

            VStack(spacing: 8) {
                Text("No workouts logged yet")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)

                Text("Complete your first session to see it here.")
                    .font(.subheadline)
                    .foregroundStyle(Color.kineticsSubtext)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Spacer()
        }
    }
}

// MARK: - HeatDayCell

private struct HeatDayCell: View {

    let day: GymWorkoutHistoryViewModel.HeatDay
    let maxVolume: Double
    let isHighlighted: Bool

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "d"
        return f
    }()

    private var intensity: Double {
        guard maxVolume > 0, day.volumeKg > 0 else { return 0 }
        return min(1.0, day.volumeKg / maxVolume)
    }

    private var cellColor: Color {
        if !day.hasWorkout { return Color(white: 0.1) }
        return Color.kineticsBlue.opacity(0.2 + intensity * 0.8)
    }

    private var dayLabel: String {
        Self.dayFormatter.string(from: day.date)
    }

    private var isToday: Bool {
        Calendar.current.isDateInToday(day.date)
    }

    var body: some View {
        VStack(spacing: 3) {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(cellColor)
                .overlay(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(
                            isHighlighted
                                ? Color.white.opacity(0.7)
                                : isToday
                                    ? Color.kineticsBlue.opacity(0.8)
                                    : Color.clear,
                            lineWidth: isHighlighted ? 1.5 : 1
                        )
                )
                .frame(width: 28, height: 28)

            if isToday {
                Circle()
                    .fill(Color.kineticsBlue)
                    .frame(width: 4, height: 4)
            } else {
                Color.clear.frame(width: 4, height: 4)
            }
        }
    }
}

// MARK: - GymHistorySessionRow

private struct GymHistorySessionRow: View {

    let session: WorkoutSession
    let isExpanded: Bool
    let onTap: () -> Void
    let onDelete: () -> Void
    let onShare: () -> Void

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMM d"
        return f
    }()

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f
    }()

    // MARK: Computed

    private var dateText: String {
        let cal = Calendar.current
        if cal.isDateInToday(session.startedAt) { return "Today" }
        if cal.isDateInYesterday(session.startedAt) { return "Yesterday" }
        return Self.dateFormatter.string(from: session.startedAt)
    }

    private var timeText: String {
        Self.timeFormatter.string(from: session.startedAt)
    }

    private var durationText: String {
        let mins = max(0, Int(session.duration / 60))
        if mins < 60 { return "\(mins)m" }
        let h = mins / 60
        let m = mins % 60
        return m > 0 ? "\(h)h \(m)m" : "\(h)h"
    }

    private var volumeText: String {
        let kg = session.totalVolumeKg
        if kg == 0 { return "—" }
        if kg >= 1000 { return String(format: "%.1fk", kg / 1000) + " kg" }
        return "\(Int(kg)) kg"
    }

    private var muscleGroupColors: [Color] {
        let muscles = Set(
            session.entries
                .compactMap { GymMuscleGroup(rawValue: $0.exerciseName) }
                .prefix(5)
        )
        // Fallback: derive from exercise names by hashing if no typed match
        if muscles.isEmpty {
            let groups = session.entries
                .compactMap { entry -> GymMuscleGroup? in
                    GymMuscleGroup.allCases.first { entry.exerciseName.localizedCaseInsensitiveContains($0.rawValue) }
                }
                .prefix(5)
            return Array(Set(groups).prefix(4)).map(\.color)
        }
        return Array(muscles.prefix(4)).map(\.color)
    }

    // MARK: Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Main row — tappable to expand
            Button(action: onTap) {
                HStack(alignment: .top, spacing: 0) {
                    // Left: date / time / muscle dots
                    VStack(alignment: .leading, spacing: 4) {
                        Text(dateText)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white)
                        Text(timeText)
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(Color.kineticsSubtext)

                        // Muscle group dots
                        if !muscleGroupColors.isEmpty {
                            HStack(spacing: 4) {
                                ForEach(Array(muscleGroupColors.enumerated()), id: \.offset) { _, color in
                                    Circle()
                                        .fill(color)
                                        .frame(width: 7, height: 7)
                                }
                            }
                            .padding(.top, 4)
                        }
                    }

                    Spacer()

                    // Right: duration + volume + chevron
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(durationText)
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.kineticsBlue)
                        Text(volumeText)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.kineticsGreen)

                        if session.isCompleted {
                            Text("Completed")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(Color.kineticsGreen.opacity(0.7))
                                .padding(.top, 2)
                        }
                    }

                    // Expand chevron
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.kineticsSubtext)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                        .animation(.spring(duration: 0.25), value: isExpanded)
                        .padding(.leading, 10)
                        .padding(.top, 2)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 14)
            }
            .buttonStyle(.plain)

            // Expanded exercise list
            if isExpanded {
                exerciseList
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(white: 0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(
                            isExpanded ? Color.kineticsBlue.opacity(0.2) : Color.white.opacity(0.06),
                            lineWidth: 1
                        )
                )
        )
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash.fill")
            }
            Button(action: onShare) {
                Label("Share", systemImage: "square.and.arrow.up")
            }
            .tint(Color.kineticsBlue)
        }
    }

    // MARK: - Exercise list (expanded)

    private var exerciseList: some View {
        VStack(alignment: .leading, spacing: 0) {
            Divider()
                .background(Color.white.opacity(0.06))
                .padding(.horizontal, 14)

            VStack(alignment: .leading, spacing: 0) {
                ForEach(
                    session.entries.sorted { $0.orderIndex < $1.orderIndex },
                    id: \.id
                ) { entry in
                    exerciseRow(entry: entry)
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 12)
            .padding(.top, 8)
        }
    }

    private func exerciseRow(entry: WorkoutExerciseEntry) -> some View {
        HStack(spacing: 10) {
            // Small muscle-group colour dot
            let muscleColor: Color = GymMuscleGroup.allCases
                .first { entry.exerciseName.localizedCaseInsensitiveContains($0.rawValue) }
                .map(\.color) ?? Color.kineticsSubtext.opacity(0.4)

            Circle()
                .fill(muscleColor.opacity(0.7))
                .frame(width: 6, height: 6)

            Text(entry.exerciseName)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)

            Spacer()

            let completedSets = entry.sets.filter(\.isCompleted).count
            Text("\(completedSets) set\(completedSets == 1 ? "" : "s")")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.kineticsSubtext)
        }
        .padding(.vertical, 7)
    }
}
