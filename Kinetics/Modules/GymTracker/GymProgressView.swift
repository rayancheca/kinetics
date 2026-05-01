import Charts
import SwiftData
import SwiftUI

// MARK: - ProgressTab

enum ProgressTab: String, CaseIterable {
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

    // MARK: State

    var selectedTab: ProgressTab = .strength
    var selectedExercise: String = ""
    var availableExercises: [String] = []
    var periodFilter: PeriodFilter = .threeMonths
    var weeklyVolume: [(week: String, weekStart: Date, totalKg: Double)] = []
    var errorMessage: String?

    // MARK: Derived Lifetime Stats

    private(set) var totalWorkouts: Int = 0
    private(set) var totalVolumeKg: Double = 0
    private(set) var totalPRs: Int = 0
    private(set) var workoutsThisMonth: Int = 0
    private(set) var workoutsThisYear: Int = 0
    private(set) var topPRs: [PersonalRecord] = []
    private(set) var allSessions: [WorkoutSession] = []

    // MARK: Load

    func load(
        userId: String,
        sessions: [WorkoutSession],
        records: [PersonalRecord],
        measurements: [BodyMeasurement]
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

        totalVolumeKg = userSessions.reduce(0.0) { sessionTotal, session in
            sessionTotal + session.entries.reduce(0.0) { entryTotal, entry in
                entryTotal + entry.sets.filter { $0.isCompleted }.reduce(0.0) {
                    $0 + ($1.weight * Double($1.reps))
                }
            }
        }

        let calendar = Calendar.current
        let now = Date()
        let startOfMonth = calendar.date(
            from: calendar.dateComponents([.year, .month], from: now)
        ) ?? now
        let startOfYear = calendar.date(
            from: calendar.dateComponents([.year], from: now)
        ) ?? now

        workoutsThisMonth = userSessions.filter { $0.startedAt >= startOfMonth }.count
        workoutsThisYear = userSessions.filter { $0.startedAt >= startOfYear }.count

        topPRs = userRecords
            .sorted { $0.weight > $1.weight }
            .prefix(3)
            .map { $0 }

        weeklyVolume = buildWeeklyVolume(sessions: userSessions, calendar: calendar, now: now)
    }

    // MARK: - Private Helpers

    private func buildWeeklyVolume(
        sessions: [WorkoutSession],
        calendar: Calendar,
        now: Date
    ) -> [(week: String, weekStart: Date, totalKg: Double)] {
        var buckets: [(weekStart: Date, weekLabel: String, totalKg: Double)] = []

        for weekOffset in (0 ..< 12).reversed() {
            guard let weekStart = calendar.date(
                byAdding: .weekOfYear,
                value: -weekOffset,
                to: startOfISOWeek(for: now, calendar: calendar)
            ) else { continue }

            let weekOfYear = calendar.component(.weekOfYear, from: weekStart)
            let label = "W\(weekOfYear)"
            buckets.append((weekStart: weekStart, weekLabel: label, totalKg: 0.0))
        }

        let weekInSeconds: TimeInterval = 7 * 24 * 3600
        var result = buckets

        for session in sessions {
            let sessionDate = session.startedAt
            for index in result.indices {
                let bucketStart = result[index].weekStart
                let bucketEnd = bucketStart.addingTimeInterval(weekInSeconds)
                guard sessionDate >= bucketStart && sessionDate < bucketEnd else { continue }

                let sessionVolume = session.entries.reduce(0.0) { entryTotal, entry in
                    entryTotal + entry.sets.filter { $0.isCompleted }.reduce(0.0) {
                        $0 + ($1.weight * Double($1.reps))
                    }
                }
                result[index].totalKg += sessionVolume
            }
        }

        return result.map { (week: $0.weekLabel, weekStart: $0.weekStart, totalKg: $0.totalKg) }
    }

    private func startOfISOWeek(for date: Date, calendar: Calendar) -> Date {
        var cal = calendar
        cal.firstWeekday = 2
        let components = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return cal.date(from: components) ?? date
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

    @State private var viewModel = GymProgressViewModel()

    var body: some View {
        NavigationStack {
            ZStack {
                Color.kineticsBackground.ignoresSafeArea()

                VStack(spacing: 0) {
                    tabBar
                    Divider()
                        .background(Color.kineticsSubtext.opacity(0.15))
                    tabContent
                }
            }
            .navigationTitle("Progress")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.kineticsBackground, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .task {
            viewModel.load(
                userId: userId,
                sessions: sessions,
                records: records,
                measurements: measurements
            )
        }
        .onChange(of: sessions.count) {
            viewModel.load(
                userId: userId,
                sessions: sessions,
                records: records,
                measurements: measurements
            )
        }
        .onChange(of: records.count) {
            viewModel.load(
                userId: userId,
                sessions: sessions,
                records: records,
                measurements: measurements
            )
        }
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
                            withAnimation(.spring(duration: 0.25)) {
                                viewModel.selectedTab = tab
                            }
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
        switch viewModel.selectedTab {
        case .strength:
            strengthTab
        case .volume:
            volumeTab
        case .body:
            bodyTab
        case .consistency:
            consistencyTab
        }
    }

    // MARK: - Strength Tab

    private var strengthTab: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {

                // Exercise Picker
                if !viewModel.availableExercises.isEmpty {
                    exercisePickerRow
                }

                // Period Filter
                periodFilterRow

                // 1RM Chart
                StrengthChartCard(
                    records: filteredStrengthRecords,
                    exerciseName: viewModel.selectedExercise
                )

                // Best Set Card
                if let bestSet = filteredStrengthRecords.max(by: { $0.weight < $1.weight }) {
                    BestSetCard(record: bestSet)
                }

                if viewModel.availableExercises.isEmpty {
                    strengthEmptyState
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 20)
            .padding(.bottom, 32)
        }
    }

    private var exercisePickerRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("EXERCISE")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Color.kineticsSubtext)
                .tracking(1.0)

            Menu {
                ForEach(viewModel.availableExercises, id: \.self) { name in
                    Button(name) {
                        viewModel.selectedExercise = name
                    }
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
                        .fill(Color.kineticsDark)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(Color.kineticsBlue.opacity(0.2), lineWidth: 1)
                        )
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
                            Capsule()
                                .fill(viewModel.periodFilter == period
                                      ? Color.kineticsBlue
                                      : Color.kineticsDark)
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

                // Volume stats row
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
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.kineticsDark)
        )
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
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.kineticsDark)
            )
        }
    }

    @ViewBuilder
    private var recentMeasurementsSection: some View {
        let recentMeasurements = Array(
            measurements.filter { $0.weightKg > 0 }.suffix(5).reversed()
        )
        if !recentMeasurements.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel(text: "RECENT ENTRIES")
                LazyVStack(spacing: 8) {
                    ForEach(recentMeasurements, id: \.id) { measurement in
                        BodyMeasRow(measurement: measurement)
                    }
                }
            }
        } else {
            bodyEmptyState
        }
    }

    private var bodyEmptyState: some View {
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

    // MARK: - Consistency Tab

    private var consistencyTab: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {

                // Stats row
                consistencyStats

                // Heatmap
                VStack(alignment: .leading, spacing: 12) {
                    SectionLabel(text: "LAST 12 WEEKS")
                    ContributionHeatmap(sessions: viewModel.allSessions)
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.kineticsDark)
                )
            }
            .padding(.horizontal, 16)
            .padding(.top, 20)
            .padding(.bottom, 32)
        }
    }

    private var consistencyStats: some View {
        HStack(spacing: 12) {
            ConsistencyStatCell(
                label: "THIS MONTH",
                value: "\(viewModel.workoutsThisMonth)",
                unit: "sessions",
                color: Color.kineticsGreen
            )
            ConsistencyStatCell(
                label: "THIS YEAR",
                value: "\(viewModel.workoutsThisYear)",
                unit: "sessions",
                color: Color.kineticsBlue
            )
            ConsistencyStatCell(
                label: "ALL TIME",
                value: "\(viewModel.totalWorkouts)",
                unit: "sessions",
                color: Color.kineticsPurple
            )
        }
    }

    // MARK: - Computed Helpers

    private var filteredStrengthRecords: [PersonalRecord] {
        let cutoff = Calendar.current.date(
            byAdding: .day,
            value: -viewModel.periodFilter.days,
            to: Date()
        ) ?? Date.distantPast

        return records
            .filter { $0.exerciseName == viewModel.selectedExercise && $0.achievedAt >= cutoff }
            .sorted { $0.achievedAt < $1.achievedAt }
    }

    private func formatVolume(_ kg: Double) -> String {
        if kg >= 1_000 {
            return String(format: "%.1fk kg", kg / 1_000)
        }
        return String(format: "%.0f kg", kg)
    }
}

// MARK: - StrengthChartCard

private struct StrengthChartCard: View {

    let records: [PersonalRecord]
    let exerciseName: String

    // Estimated 1RM = weight × (1 + reps / 30)
    private var oneRMData: [(date: Date, oneRM: Double)] {
        records.map { record in
            let value = record.weight * (1 + Double(record.reps) / 30.0)
            return (date: record.achievedAt, oneRM: value)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                SectionLabel(text: "ESTIMATED 1RM")
                Spacer()
                if let best = oneRMData.max(by: { $0.oneRM < $1.oneRM }) {
                    Text(formatWeight(best.oneRM))
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.kineticsAmber)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.kineticsAmber.opacity(0.12)))
                }
            }

            if oneRMData.isEmpty {
                chartEmptyState
            } else {
                oneRMChart
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.kineticsDark)
        )
    }

    @ViewBuilder
    private var oneRMChart: some View {
        Chart(oneRMData, id: \.date) { item in
            AreaMark(
                x: .value("Date", item.date),
                y: .value("Est 1RM (kg)", item.oneRM)
            )
            .foregroundStyle(
                LinearGradient(
                    colors: [Color.kineticsAmber.opacity(0.18), Color.kineticsAmber.opacity(0.02)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .interpolationMethod(.catmullRom)

            LineMark(
                x: .value("Date", item.date),
                y: .value("Est 1RM (kg)", item.oneRM)
            )
            .foregroundStyle(Color.kineticsAmber)
            .lineStyle(StrokeStyle(lineWidth: 2.5))
            .interpolationMethod(.catmullRom)

            PointMark(
                x: .value("Date", item.date),
                y: .value("Est 1RM (kg)", item.oneRM)
            )
            .foregroundStyle(Color.kineticsAmber)
            .symbolSize(56)

            PointMark(
                x: .value("Date", item.date),
                y: .value("Est 1RM (kg)", item.oneRM)
            )
            .foregroundStyle(Color.kineticsDark)
            .symbolSize(18)
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4, 4]))
                    .foregroundStyle(Color.kineticsSubtext.opacity(0.2))
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(date, format: .dateTime.month(.abbreviated).day())
                            .font(.system(size: 10))
                            .foregroundStyle(Color.kineticsSubtext)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4, 4]))
                    .foregroundStyle(Color.kineticsSubtext.opacity(0.2))
                AxisValueLabel {
                    if let kg = value.as(Double.self) {
                        Text("\(Int(kg)) kg")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.kineticsSubtext)
                    }
                }
            }
        }
        .chartPlotStyle { plot in
            plot.background(Color.clear)
        }
        .frame(height: 220)
    }

    private var chartEmptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(Color.kineticsAmber.opacity(0.35))
            Text("No data for this period")
                .font(.system(size: 13))
                .foregroundStyle(Color.kineticsSubtext)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 180)
    }

    private func formatWeight(_ kg: Double) -> String {
        kg.truncatingRemainder(dividingBy: 1) == 0
            ? "\(Int(kg)) kg"
            : String(format: "%.1f kg", kg)
    }
}

// MARK: - VolumeBarChartCard

private struct VolumeBarChartCard: View {

    let data: [(week: String, weekStart: Date, totalKg: Double)]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                SectionLabel(text: "WEEKLY VOLUME")
                Spacer()
                if let maxWeek = data.max(by: { $0.totalKg < $1.totalKg }), maxWeek.totalKg > 0 {
                    Text("Peak: \(formatVolume(maxWeek.totalKg))")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.kineticsSubtext)
                }
            }

            if data.isEmpty || data.allSatisfy({ $0.totalKg == 0 }) {
                volumeEmptyState
            } else {
                volumeChart
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.kineticsDark)
        )
    }

    private var volumeChart: some View {
        let avgVolume = {
            let nonZero = data.filter { $0.totalKg > 0 }
            guard !nonZero.isEmpty else { return 0.0 }
            return nonZero.reduce(0.0) { $0 + $1.totalKg } / Double(nonZero.count)
        }()

        return Chart {
            ForEach(data, id: \.week) { item in
                BarMark(
                    x: .value("Week", item.weekStart, unit: .weekOfYear),
                    y: .value("Volume (kg)", item.totalKg)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.kineticsBlue, Color.kineticsBlue.opacity(0.5)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .cornerRadius(4)
            }

            if avgVolume > 0 {
                RuleMark(y: .value("Average", avgVolume))
                    .foregroundStyle(Color.kineticsGreen.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                    .annotation(position: .top, alignment: .trailing) {
                        Text("avg")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(Color.kineticsGreen.opacity(0.8))
                    }
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .weekOfYear)) { value in
                AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                    .font(.system(size: 9))
                    .foregroundStyle(Color.kineticsSubtext)
            }
        }
        .chartYAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(Color.kineticsSubtext.opacity(0.2))
                AxisValueLabel {
                    if let kg = value.as(Double.self) {
                        Text(formatVolume(kg))
                            .font(.system(size: 10))
                            .foregroundStyle(Color.kineticsSubtext)
                    }
                }
            }
        }
        .chartPlotStyle { plot in
            plot.background(Color.clear)
        }
        .frame(height: 200)
    }

    private var volumeEmptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "chart.bar")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(Color.kineticsBlue.opacity(0.4))
            Text("Complete workouts to see your volume trend.")
                .font(.system(size: 13))
                .foregroundStyle(Color.kineticsSubtext)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 180)
    }

    private func formatVolume(_ kg: Double) -> String {
        kg >= 1_000 ? String(format: "%.0fk", kg / 1_000) : String(format: "%.0f", kg)
    }
}

// MARK: - BodyWeightChartView

private struct BodyWeightChartView: View {

    let measurements: [BodyMeasurement]

    var body: some View {
        if measurements.isEmpty {
            bodyEmptyState
        } else {
            chart
        }
    }

    @ViewBuilder
    private var chart: some View {
        Chart(measurements, id: \.id) { m in
            AreaMark(
                x: .value("Date", m.recordedAt),
                y: .value("Weight (kg)", m.weightKg)
            )
            .foregroundStyle(
                LinearGradient(
                    colors: [Color.kineticsBlue.opacity(0.22), Color.kineticsBlue.opacity(0.03)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .interpolationMethod(.catmullRom)

            LineMark(
                x: .value("Date", m.recordedAt),
                y: .value("Weight (kg)", m.weightKg)
            )
            .foregroundStyle(Color.kineticsBlue)
            .lineStyle(StrokeStyle(lineWidth: 2.5))
            .interpolationMethod(.catmullRom)

            PointMark(
                x: .value("Date", m.recordedAt),
                y: .value("Weight (kg)", m.weightKg)
            )
            .foregroundStyle(Color.kineticsBlue)
            .symbolSize(52)

            PointMark(
                x: .value("Date", m.recordedAt),
                y: .value("Weight (kg)", m.weightKg)
            )
            .foregroundStyle(Color.kineticsDark)
            .symbolSize(18)
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4, 4]))
                    .foregroundStyle(Color.kineticsSubtext.opacity(0.2))
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(date, format: .dateTime.month(.abbreviated).day())
                            .font(.system(size: 10))
                            .foregroundStyle(Color.kineticsSubtext)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4, 4]))
                    .foregroundStyle(Color.kineticsSubtext.opacity(0.2))
                AxisValueLabel {
                    if let kg = value.as(Double.self) {
                        Text(String(format: "%.1f", kg))
                            .font(.system(size: 10))
                            .foregroundStyle(Color.kineticsSubtext)
                    }
                }
            }
        }
        .chartPlotStyle { plot in
            plot.background(Color.clear)
        }
        .frame(height: 200)
    }

    private var bodyEmptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "figure.stand")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(Color.kineticsBlue.opacity(0.4))
            Text("No body weight data recorded yet.")
                .font(.system(size: 13))
                .foregroundStyle(Color.kineticsSubtext)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 160)
    }
}

// MARK: - BodyFatChartView

private struct BodyFatChartView: View {

    let measurements: [BodyMeasurement]

    var body: some View {
        Chart(measurements, id: \.id) { m in
            AreaMark(
                x: .value("Date", m.recordedAt),
                y: .value("Body Fat %", m.bodyFatPercent)
            )
            .foregroundStyle(
                LinearGradient(
                    colors: [Color.kineticsPurple.opacity(0.22), Color.kineticsPurple.opacity(0.03)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .interpolationMethod(.catmullRom)

            LineMark(
                x: .value("Date", m.recordedAt),
                y: .value("Body Fat %", m.bodyFatPercent)
            )
            .foregroundStyle(Color.kineticsPurple)
            .lineStyle(StrokeStyle(lineWidth: 2.5))
            .interpolationMethod(.catmullRom)

            PointMark(
                x: .value("Date", m.recordedAt),
                y: .value("Body Fat %", m.bodyFatPercent)
            )
            .foregroundStyle(Color.kineticsPurple)
            .symbolSize(52)

            PointMark(
                x: .value("Date", m.recordedAt),
                y: .value("Body Fat %", m.bodyFatPercent)
            )
            .foregroundStyle(Color.kineticsDark)
            .symbolSize(18)
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4, 4]))
                    .foregroundStyle(Color.kineticsSubtext.opacity(0.2))
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(date, format: .dateTime.month(.abbreviated).day())
                            .font(.system(size: 10))
                            .foregroundStyle(Color.kineticsSubtext)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4, 4]))
                    .foregroundStyle(Color.kineticsSubtext.opacity(0.2))
                AxisValueLabel {
                    if let pct = value.as(Double.self) {
                        Text(String(format: "%.1f%%", pct))
                            .font(.system(size: 10))
                            .foregroundStyle(Color.kineticsSubtext)
                    }
                }
            }
        }
        .chartPlotStyle { plot in
            plot.background(Color.clear)
        }
        .frame(height: 180)
    }
}

// MARK: - ContributionHeatmap

private struct ContributionHeatmap: View {

    let sessions: [WorkoutSession]

    private let columns = 12
    private let cellSize: CGFloat = 22
    private let cellSpacing: CGFloat = 4

    private var trainedDays: Set<String> {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return Set(sessions.map { formatter.string(from: $0.startedAt) })
    }

    private var weeks: [[Date?]] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        // Start of 12 weeks ago (Monday)
        var cal = calendar
        cal.firstWeekday = 2
        guard let twelveWeeksAgo = cal.date(byAdding: .weekOfYear, value: -(columns - 1), to: today) else {
            return []
        }

        // Find the Monday of that week
        let weekStart: Date = {
            let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: twelveWeeksAgo)
            return cal.date(from: comps) ?? twelveWeeksAgo
        }()

        var result: [[Date?]] = []
        for weekIndex in 0 ..< columns {
            var week: [Date?] = []
            for dayIndex in 0 ..< 7 {
                let offset = weekIndex * 7 + dayIndex
                if let day = cal.date(byAdding: .day, value: offset, to: weekStart) {
                    week.append(day <= today ? day : nil)
                } else {
                    week.append(nil)
                }
            }
            result.append(week)
        }
        return result
    }

    private let dayLabels = ["M", "T", "W", "T", "F", "S", "S"]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Day labels column
            HStack(alignment: .top, spacing: cellSpacing) {
                // Day label column
                VStack(spacing: cellSpacing) {
                    ForEach(0 ..< 7, id: \.self) { dayIndex in
                        Text(dayLabels[dayIndex])
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(Color.kineticsSubtext)
                            .frame(width: 12, height: cellSize)
                    }
                }

                // Weeks grid
                HStack(alignment: .top, spacing: cellSpacing) {
                    ForEach(0 ..< weeks.count, id: \.self) { weekIndex in
                        VStack(spacing: cellSpacing) {
                            ForEach(0 ..< 7, id: \.self) { dayIndex in
                                let day = weeks[weekIndex][dayIndex]
                                cell(for: day)
                            }
                        }
                    }
                }
            }

            // Legend
            HStack(spacing: 8) {
                Text("Less")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.kineticsSubtext)

                HStack(spacing: 3) {
                    ForEach([0.0, 0.35, 0.65, 1.0], id: \.self) { opacity in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(opacity == 0 ? Color.kineticsSubtext.opacity(0.15) : Color.kineticsGreen.opacity(opacity))
                            .frame(width: cellSize, height: cellSize)
                    }
                }

                Text("More")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.kineticsSubtext)
            }
            .padding(.top, 4)
        }
    }

    @ViewBuilder
    private func cell(for day: Date?) -> some View {
        if let day {
            let formatter: DateFormatter = {
                let f = DateFormatter()
                f.dateFormat = "yyyy-MM-dd"
                return f
            }()
            let key = formatter.string(from: day)
            let trained = trainedDays.contains(key)

            RoundedRectangle(cornerRadius: 4)
                .fill(trained ? Color.kineticsGreen : Color.kineticsSubtext.opacity(0.12))
                .frame(width: cellSize, height: cellSize)
        } else {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.clear)
                .frame(width: cellSize, height: cellSize)
        }
    }
}

// MARK: - BestSetCard

private struct BestSetCard: View {

    let record: PersonalRecord

    private var weightText: String {
        let kg = record.weight
        if kg == 0 { return "Bodyweight" }
        let formatted = kg.truncatingRemainder(dividingBy: 1) == 0
            ? String(Int(kg))
            : String(format: "%.1f", kg)
        return "\(formatted) kg"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionLabel(text: "BEST SET")

            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(weightText)
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("Weight")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.kineticsSubtext)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Divider()
                    .background(Color.kineticsSubtext.opacity(0.3))
                    .frame(height: 44)
                    .padding(.horizontal, 18)

                VStack(alignment: .leading, spacing: 4) {
                    Text("\(record.reps)")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("Reps")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.kineticsSubtext)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Divider()
                    .background(Color.kineticsSubtext.opacity(0.3))
                    .frame(height: 44)
                    .padding(.horizontal, 18)

                VStack(alignment: .leading, spacing: 4) {
                    Text(record.achievedAt, format: .dateTime.month(.abbreviated).day().year())
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text("Date")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.kineticsSubtext)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.kineticsDark)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(Color.kineticsBlue.opacity(0.2), lineWidth: 1)
                    )
            )
        }
    }
}

// MARK: - VolumeStatCell

private struct VolumeStatCell: View {

    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Color.kineticsSubtext)
                .tracking(0.7)

            Text(value)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.kineticsDark)
        )
    }
}

// MARK: - ConsistencyStatCell

private struct ConsistencyStatCell: View {

    let label: String
    let value: String
    let unit: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Color.kineticsSubtext)
                .tracking(0.7)

            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(color)
                .monospacedDigit()

            Text(unit)
                .font(.system(size: 11))
                .foregroundStyle(Color.kineticsSubtext)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.kineticsDark)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(color.opacity(0.2), lineWidth: 1)
                )
        )
    }
}

// MARK: - BodyMeasRow (named to avoid conflicts)

private struct BodyMeasRow: View {

    let measurement: BodyMeasurement

    private var weightText: String {
        measurement.weightKg.truncatingRemainder(dividingBy: 1) == 0
            ? "\(Int(measurement.weightKg)) kg"
            : String(format: "%.1f kg", measurement.weightKg)
    }

    private var bodyFatText: String? {
        guard measurement.bodyFatPercent > 0 else { return nil }
        return String(format: "%.1f%%", measurement.bodyFatPercent)
    }

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "scalemass.fill")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color.kineticsBlue)
                .frame(width: 34, height: 34)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.kineticsBlue.opacity(0.15))
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(measurement.recordedAt, format: .dateTime.month(.abbreviated).day().year())
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)

                if let bf = bodyFatText {
                    Text("Body fat: \(bf)")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.kineticsSubtext)
                }
            }

            Spacer()

            Text(weightText)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.kineticsBlue)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.kineticsDark)
        )
    }
}

// MARK: - ProgressTabButton

private struct ProgressTabButton: View {

    let tab: ProgressTab
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            tabLabel
        }
        .buttonStyle(.plain)
        .animation(.spring(duration: 0.2), value: isSelected)
    }

    private var tabLabel: some View {
        let weight: Font.Weight = isSelected ? .bold : .regular
        let fg: Color = isSelected ? .white : Color.kineticsSubtext
        let bgFill: Color = isSelected ? Color.kineticsBlue.opacity(0.18) : Color.clear
        let border: Color = isSelected ? Color.kineticsBlue.opacity(0.4) : Color.clear

        return Text(tab.rawValue)
            .font(.system(size: 14, weight: weight))
            .foregroundStyle(fg)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(bgFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(border, lineWidth: 1)
                    )
            )
    }
}

// MARK: - SectionLabel

private struct SectionLabel: View {

    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(Color.kineticsSubtext)
            .tracking(1.0)
    }
}
