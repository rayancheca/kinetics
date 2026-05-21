import Charts
import SwiftData
import SwiftUI

// MARK: - ProgressTab

enum ProgressTab: String, CaseIterable {
    case overview = "Overview"
    case strength = "Strength"
    case volume = "Volume"
    case body = "Body"
    case consistency = "Consistency"
}

// MARK: - PeriodFilter

enum PeriodFilter: String, CaseIterable {
    case oneWeek = "1W"
    case oneMonth = "1M"
    case threeMonths = "3M"
    case sixMonths = "6M"
    case oneYear = "1Y"

    var days: Int {
        switch self {
        case .oneWeek: return 7
        case .oneMonth: return 30
        case .threeMonths: return 90
        case .sixMonths: return 180
        case .oneYear: return 365
        }
    }
}

// MARK: - GymProgressViewModel

@Observable
@MainActor
final class GymProgressViewModel {

    // MARK: - State

    var selectedTab: ProgressTab = .overview
    var selectedExercise: String = ""
    var availableExercises: [String] = []
    var periodFilter: PeriodFilter = .threeMonths
    var weeklyVolume: [(week: String, weekStart: Date, totalKg: Double)] = []
    var errorMessage: String?

    // MARK: - Derived Lifetime Stats

    private(set) var totalWorkouts: Int = 0
    private(set) var totalVolumeKg: Double = 0
    private(set) var totalPRs: Int = 0
    private(set) var workoutsThisMonth: Int = 0
    private(set) var workoutsThisYear: Int = 0
    private(set) var topPRs: [PersonalRecord] = []
    private(set) var allSessions: [WorkoutSession] = []

    // MARK: - New Dashboard Properties

    /// Muscle group raw names trained in the current ISO week.
    private(set) var musclesTrainedThisWeek: Set<String> = []

    /// Muscle group raw names trained in the current calendar month.
    private(set) var musclesTrainedThisMonth: Set<String> = []

    /// Weekly volume for the last 8 weeks (label + volume in kg).
    private(set) var volumeByWeek: [(weekLabel: String, volume: Double)] = []

    /// Top-5 most-trained exercises mapped to sorted (date, est1RM) data points.
    private(set) var strengthProgressions: [String: [(date: Date, estimatedOneRM: Double)]] = [:]

    /// Sessions completed in the current ISO week.
    private(set) var sessionsThisWeek: Int = 0

    /// Total volume lifted this week (kg).
    private(set) var volumeThisWeek: Double = 0

    /// Total volume lifted last week (kg), used for the volume ring comparison.
    private(set) var volumeLastWeek: Double = 0

    /// Number of distinct calendar days with at least one session this week.
    private(set) var activeDaysThisWeek: Int = 0

    // MARK: - Load

    func load(
        userId: String,
        sessions: [WorkoutSession],
        records: [PersonalRecord],
        measurements: [BodyMeasurement],
        exercises: [Exercise]
    ) {
        let userRecords = records.filter { $0.userId == userId }
        let userSessions = sessions.filter { $0.userId == userId && $0.isCompleted }

        allSessions = userSessions

        let exerciseNames = Array(Set(userRecords.map { $0.exerciseName })).sorted()
        availableExercises = exerciseNames

        if !availableExercises.isEmpty && selectedExercise.isEmpty {
            selectedExercise = availableExercises[0]
        }

        totalWorkouts = userSessions.count
        totalPRs = userRecords.count

        totalVolumeKg = userSessions.reduce(0.0) { total, session in
            total + sessionVolume(session)
        }

        let calendar = Calendar.current
        let now = Date()
        let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now
        let startOfYear = calendar.date(from: calendar.dateComponents([.year], from: now)) ?? now

        workoutsThisMonth = userSessions.filter { $0.startedAt >= startOfMonth }.count
        workoutsThisYear = userSessions.filter { $0.startedAt >= startOfYear }.count

        topPRs = userRecords.sorted { $0.weight > $1.weight }.prefix(5).map { $0 }

        weeklyVolume = buildWeeklyVolume(sessions: userSessions, calendar: calendar, now: now, count: 12)

        buildMuscleSets(sessions: userSessions, exercises: exercises, calendar: calendar, now: now)
        buildVolumeByWeek(sessions: userSessions, calendar: calendar, now: now)
        buildStrengthProgressions(records: userRecords)
        buildWeeklyRings(sessions: userSessions, calendar: calendar, now: now)
    }

    // MARK: - Builders

    private func buildMuscleSets(
        sessions: [WorkoutSession],
        exercises: [Exercise],
        calendar: Calendar,
        now: Date
    ) {
        let muscleById: [String: String] = Dictionary(
            uniqueKeysWithValues: exercises.compactMap { ex -> (String, String)? in
                guard !ex.primaryMuscle.isEmpty else { return nil }
                return (ex.id, ex.primaryMuscle)
            }
        )

        var cal = calendar
        cal.firstWeekday = 2
        let weekStart = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)) ?? now
        let weekEnd = cal.date(byAdding: .weekOfYear, value: 1, to: weekStart) ?? now
        let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now

        var weekMuscles = Set<String>()
        var monthMuscles = Set<String>()

        for session in sessions {
            let inWeek = session.startedAt >= weekStart && session.startedAt < weekEnd
            let inMonth = session.startedAt >= monthStart

            for entry in session.entries {
                if let muscle = muscleById[entry.exerciseId] {
                    if inWeek { weekMuscles.insert(muscle) }
                    if inMonth { monthMuscles.insert(muscle) }
                }
            }
        }

        musclesTrainedThisWeek = weekMuscles
        musclesTrainedThisMonth = monthMuscles
    }

    private func buildVolumeByWeek(sessions: [WorkoutSession], calendar: Calendar, now: Date) {
        let data = buildWeeklyVolume(sessions: sessions, calendar: calendar, now: now, count: 8)
        volumeByWeek = data.map { (weekLabel: $0.week, volume: $0.totalKg) }
    }

    private func buildStrengthProgressions(records: [PersonalRecord]) {
        let grouped = Dictionary(grouping: records) { $0.exerciseName }
        let top5 = grouped.sorted { $0.value.count > $1.value.count }.prefix(5)

        var result: [String: [(date: Date, estimatedOneRM: Double)]] = [:]
        for (name, recs) in top5 {
            let sorted = recs.sorted { $0.achievedAt < $1.achievedAt }.map { rec in
                (date: rec.achievedAt, estimatedOneRM: rec.weight * (1.0 + Double(rec.reps) / 30.0))
            }
            if sorted.count >= 2 { result[name] = sorted }
        }
        strengthProgressions = result
    }

    private func buildWeeklyRings(sessions: [WorkoutSession], calendar: Calendar, now: Date) {
        var cal = calendar
        cal.firstWeekday = 2
        let weekStart = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)) ?? now
        let weekEnd = cal.date(byAdding: .weekOfYear, value: 1, to: weekStart) ?? now
        let lastWeekStart = cal.date(byAdding: .weekOfYear, value: -1, to: weekStart) ?? now

        let thisWeek = sessions.filter { $0.startedAt >= weekStart && $0.startedAt < weekEnd }
        let lastWeek = sessions.filter { $0.startedAt >= lastWeekStart && $0.startedAt < weekStart }

        sessionsThisWeek = thisWeek.count
        volumeThisWeek = thisWeek.reduce(0.0) { $0 + sessionVolume($1) }
        volumeLastWeek = lastWeek.reduce(0.0) { $0 + sessionVolume($1) }
        activeDaysThisWeek = Set(thisWeek.map { calendar.startOfDay(for: $0.startedAt) }).count
    }

    // MARK: - Shared Helpers

    func buildWeeklyVolume(
        sessions: [WorkoutSession],
        calendar: Calendar,
        now: Date,
        count: Int
    ) -> [(week: String, weekStart: Date, totalKg: Double)] {
        let isoWeekStart = startOfISOWeek(for: now, calendar: calendar)
        var buckets: [(weekStart: Date, weekLabel: String, totalKg: Double)] = []

        for offset in (0 ..< count).reversed() {
            guard let ws = calendar.date(byAdding: .weekOfYear, value: -offset, to: isoWeekStart) else { continue }
            let label = "W\(calendar.component(.weekOfYear, from: ws))"
            buckets.append((weekStart: ws, weekLabel: label, totalKg: 0.0))
        }

        let weekInSeconds: TimeInterval = 7 * 24 * 3600
        var result = buckets
        for session in sessions {
            let d = session.startedAt
            let vol = sessionVolume(session)
            for i in result.indices {
                let start = result[i].weekStart
                if d >= start && d < start.addingTimeInterval(weekInSeconds) {
                    result[i].totalKg += vol
                }
            }
        }
        return result.map { (week: $0.weekLabel, weekStart: $0.weekStart, totalKg: $0.totalKg) }
    }

    private func sessionVolume(_ session: WorkoutSession) -> Double {
        session.entries.reduce(0.0) { eTotal, entry in
            eTotal + entry.sets.filter { $0.isCompleted }.reduce(0.0) {
                $0 + ($1.weight * Double($1.reps))
            }
        }
    }

    private func startOfISOWeek(for date: Date, calendar: Calendar) -> Date {
        var cal = calendar
        cal.firstWeekday = 2
        let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return cal.date(from: comps) ?? date
    }
}

// MARK: - GymProgressView

@MainActor
struct GymProgressView: View {

    let userId: String

    @Query(sort: \PersonalRecord.achievedAt, order: .forward)
    private var records: [PersonalRecord]

    @Query(sort: \WorkoutSession.startedAt, order: .forward)
    private var sessions: [WorkoutSession]

    @Query(sort: \BodyMeasurement.recordedAt, order: .forward)
    private var measurements: [BodyMeasurement]

    @Query(sort: \Exercise.name, order: .forward)
    private var exercises: [Exercise]

    @State private var viewModel = GymProgressViewModel()
    @State private var showPaywall = false

    private var subscriptionManager: SubscriptionManager { SubscriptionManager.shared }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.kineticsBackground.ignoresSafeArea()
                VStack(spacing: 0) {
                    tabBar
                    Divider().background(Color.kineticsSubtext.opacity(0.12))
                    tabContent
                }
            }
            .navigationTitle("Progress")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.kineticsBackground, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .sheet(isPresented: $showPaywall) {
                PaywallView(lockedFeature: "Advanced Analytics")
            }
        }
        .task { reload() }
        .onChange(of: sessions.count) { reload() }
        .onChange(of: records.count) { reload() }
    }

    private func reload() {
        viewModel.load(
            userId: userId,
            sessions: sessions,
            records: records,
            measurements: measurements,
            exercises: exercises
        )
    }

    // MARK: - Tab Bar

    private var tabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(ProgressTab.allCases, id: \.self) { tab in
                    ProgressTabButton(
                        tab: tab,
                        isSelected: viewModel.selectedTab == tab,
                        onTap: {
                            withAnimation(.spring(duration: 0.25)) { viewModel.selectedTab = tab }
                        }
                    )
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(Color.kineticsBackground)
    }

    // MARK: - Tab Content

    @ViewBuilder
    private var tabContent: some View {
        if viewModel.selectedTab == .overview || subscriptionManager.isPremium {
            switch viewModel.selectedTab {
            case .overview:    overviewTab
            case .strength:    strengthTab
            case .volume:      volumeTab
            case .body:        bodyTab
            case .consistency: consistencyTab
            }
        } else {
            analyticsLockedView
        }
    }

    // MARK: - Analytics Locked State (free tier)

    private var analyticsLockedView: some View {
        ScrollView {
            VStack(spacing: 28) {
                Spacer(minLength: 40)

                ZStack {
                    Circle()
                        .fill(Color.kineticsBlue.opacity(0.08))
                        .frame(width: 100, height: 100)
                    VStack(spacing: 2) {
                        Image(systemName: "chart.xyaxis.line")
                            .font(.system(size: 30, weight: .light))
                            .foregroundStyle(Color.kineticsBlue)
                        Image(systemName: "lock.fill")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Color.kineticsAmber)
                            .offset(y: 4)
                    }
                }

                VStack(spacing: 10) {
                    Text("Advanced Analytics")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.white)

                    Text("Strength curves, volume trends, body composition charts, and consistency data are available with Kinetics Pro.")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.kineticsSubtext)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                }
                .padding(.horizontal, 32)

                VStack(spacing: 12) {
                    lockedFeatureRow(icon: "dumbbell.fill",      text: "Strength progression curves",   color: Color.kineticsBlue)
                    lockedFeatureRow(icon: "chart.bar.fill",     text: "Weekly & monthly volume trends", color: Color.kineticsGreen)
                    lockedFeatureRow(icon: "figure.arms.open",   text: "Body composition tracking",      color: Color.kineticsPurple)
                    lockedFeatureRow(icon: "flame.fill",         text: "Training consistency analysis",  color: Color.kineticsAmber)
                }
                .padding(.horizontal, 24)

                Button {
                    showPaywall = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 14, weight: .semibold))
                        Text("Unlock Advanced Analytics")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                    }
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.kineticsAmber, in: RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 32)

                Spacer(minLength: 40)
            }
        }
    }

    private func lockedFeatureRow(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.12))
                    .frame(width: 34, height: 34)
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(color)
            }
            Text(text)
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.78))
            Spacer()
            Image(systemName: "lock.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.kineticsAmber.opacity(0.6))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.kineticsDark)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(color.opacity(0.12), lineWidth: 0.75)
                )
        )
    }

    // MARK: - Overview Tab

    private var overviewTab: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                MuscleMapCard(
                    trainedThisWeek: viewModel.musclesTrainedThisWeek,
                    trainedThisMonth: viewModel.musclesTrainedThisMonth
                )
                WeeklyRingsCard(
                    sessionsThisWeek: viewModel.sessionsThisWeek,
                    volumeThisWeek: viewModel.volumeThisWeek,
                    volumeLastWeek: viewModel.volumeLastWeek,
                    activeDaysThisWeek: viewModel.activeDaysThisWeek
                )
                if !viewModel.strengthProgressions.isEmpty {
                    StrengthProgressionCard(progressions: viewModel.strengthProgressions)
                }
                if !viewModel.topPRs.isEmpty {
                    PRTimelineSection(records: viewModel.topPRs)
                }
                let userMeasurements = measurements.filter { $0.userId == userId }
                if let latest = userMeasurements.sorted(by: { $0.recordedAt < $1.recordedAt }).last {
                    BodyCompositionCard(measurement: latest, allMeasurements: userMeasurements)
                }
                if !viewModel.volumeByWeek.isEmpty {
                    VolumeTrendCard(data: viewModel.volumeByWeek)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 20)
            .padding(.bottom, 40)
        }
    }

    // MARK: - Strength Tab

    private var strengthTab: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                if !viewModel.availableExercises.isEmpty { exercisePickerRow }
                periodFilterRow
                StrengthChartCard(records: filteredStrengthRecords, exerciseName: viewModel.selectedExercise)
                if let bestSet = filteredStrengthRecords.max(by: { $0.weight < $1.weight }) {
                    BestSetCard(record: bestSet)
                }
                if viewModel.availableExercises.isEmpty { strengthEmptyState }
            }
            .padding(.horizontal, 16)
            .padding(.top, 20)
            .padding(.bottom, 32)
        }
    }

    private var exercisePickerRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(text: "EXERCISE")
            Menu {
                ForEach(viewModel.availableExercises, id: \.self) { name in
                    Button(name) { viewModel.selectedExercise = name }
                }
            } label: {
                HStack(spacing: 8) {
                    Text(viewModel.selectedExercise.isEmpty ? "Select exercise" : viewModel.selectedExercise)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.kineticsBlue)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.ultraThinMaterial)
                        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.white.opacity(0.08), lineWidth: 0.75))
                )
            }
        }
    }

    private var periodFilterRow: some View {
        HStack(spacing: 6) {
            ForEach(PeriodFilter.allCases, id: \.self) { period in
                Button {
                    viewModel.periodFilter = period
                } label: {
                    Text(period.rawValue)
                        .font(.system(size: 13, weight: viewModel.periodFilter == period ? .bold : .regular))
                        .foregroundStyle(viewModel.periodFilter == period ? Color.black : Color.kineticsSubtext)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            Capsule().fill(viewModel.periodFilter == period ? Color.kineticsBlue : Color.kineticsDark)
                        )
                }
                .buttonStyle(.plain)
                .animation(.spring(duration: 0.2), value: viewModel.periodFilter)
            }
        }
    }

    private var strengthEmptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(Color.kineticsBlue.opacity(0.4))
            Text("No strength data yet")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
            Text("Complete workouts to track your strength progress.")
                .font(.system(size: 13))
                .foregroundStyle(Color.kineticsSubtext)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }

    // MARK: - Volume Tab

    private var volumeTab: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                VolumeBarChartCard(data: viewModel.weeklyVolume)
                if !viewModel.weeklyVolume.allSatisfy({ $0.totalKg == 0 }) {
                    volumeStatsRow
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 20)
            .padding(.bottom, 32)
        }
    }

    private var volumeStatsRow: some View {
        let nonZero = viewModel.weeklyVolume.filter { $0.totalKg > 0 }
        let avg = nonZero.isEmpty ? 0.0 : nonZero.reduce(0.0) { $0 + $1.totalKg } / Double(nonZero.count)
        let maxVol = viewModel.weeklyVolume.map { $0.totalKg }.max() ?? 0

        return HStack(spacing: 12) {
            VolumeStatCell(label: "AVG / WEEK", value: formatVolume(avg))
            VolumeStatCell(label: "BEST WEEK", value: formatVolume(maxVol))
            VolumeStatCell(label: "ACTIVE WEEKS", value: "\(nonZero.count)")
        }
    }

    // MARK: - Body Tab

    private var bodyTab: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                bodyWeightChartCard
                bodyFatChartCard
                recentMeasurementsSection
            }
            .padding(.horizontal, 16)
            .padding(.top, 20)
            .padding(.bottom, 32)
        }
    }

    private var bodyWeightChartCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionLabel(text: "BODY WEIGHT")
            BodyWeightChartView(measurements: measurements.filter { $0.weightKg > 0 })
        }
        .padding(16)
        .glassCard(cornerRadius: 20)
    }

    @ViewBuilder
    private var bodyFatChartCard: some View {
        let fatMeasurements = measurements.filter { $0.bodyFatPercent > 0 }
        if !fatMeasurements.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                SectionLabel(text: "BODY FAT %")
                BodyFatChartView(measurements: fatMeasurements)
            }
            .padding(16)
            .glassCard(cornerRadius: 20)
        }
    }

    @ViewBuilder
    private var recentMeasurementsSection: some View {
        let recentMeasurements = Array(measurements.filter { $0.weightKg > 0 }.suffix(5).reversed())
        if !recentMeasurements.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel(text: "RECENT ENTRIES")
                LazyVStack(spacing: 8) {
                    ForEach(recentMeasurements, id: \.id) { BodyMeasRow(measurement: $0) }
                }
            }
        } else {
            VStack(spacing: 12) {
                Image(systemName: "scalemass")
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(Color.kineticsBlue.opacity(0.45))
                Text("No measurements yet")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                Text("Log your body weight to track progress over time.")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.kineticsSubtext)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 40)
        }
    }

    // MARK: - Consistency Tab

    private var consistencyTab: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                HStack(spacing: 12) {
                    ConsistencyStatCell(label: "THIS MONTH", value: "\(viewModel.workoutsThisMonth)", unit: "sessions", color: Color.kineticsGreen)
                    ConsistencyStatCell(label: "THIS YEAR", value: "\(viewModel.workoutsThisYear)", unit: "sessions", color: Color.kineticsBlue)
                    ConsistencyStatCell(label: "ALL TIME", value: "\(viewModel.totalWorkouts)", unit: "sessions", color: Color.kineticsPurple)
                }
                VStack(alignment: .leading, spacing: 12) {
                    SectionLabel(text: "LAST 12 WEEKS")
                    ContributionHeatmap(sessions: viewModel.allSessions)
                }
                .padding(16)
                .glassCard(cornerRadius: 20)
            }
            .padding(.horizontal, 16)
            .padding(.top, 20)
            .padding(.bottom, 32)
        }
    }

    // MARK: - Helpers

    private var filteredStrengthRecords: [PersonalRecord] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -viewModel.periodFilter.days, to: Date()) ?? Date.distantPast
        return records
            .filter { $0.exerciseName == viewModel.selectedExercise && $0.achievedAt >= cutoff }
            .sorted { $0.achievedAt < $1.achievedAt }
    }

    private func formatVolume(_ kg: Double) -> String {
        kg >= 1_000 ? String(format: "%.1fk kg", kg / 1_000) : String(format: "%.0f kg", kg)
    }
}
