import Charts
import SwiftData
import SwiftUI

// MARK: - GymProgressViewModel

@Observable
@MainActor
final class GymProgressViewModel {

    // MARK: State

    var selectedTab = 0
    var selectedExercise: String = ""
    var availableExercises: [String] = []
    var weeklyVolume: [(week: String, totalKg: Double)] = []
    var errorMessage: String?

    // MARK: Derived Lifetime Stats

    private(set) var totalWorkouts: Int = 0
    private(set) var totalVolumeKg: Double = 0
    private(set) var totalPRs: Int = 0
    private(set) var workoutsThisMonth: Int = 0
    private(set) var topPRs: [PersonalRecord] = []

    // MARK: Load

    func load(
        userId: String,
        sessions: [WorkoutSession],
        records: [PersonalRecord],
        measurements: [BodyMeasurement]
    ) {
        let userRecords = records.filter { $0.userId == userId }
        let userSessions = sessions.filter { $0.userId == userId && $0.isCompleted }

        // Available exercises from PRs, deduplicated and sorted
        let exerciseNames = Array(
            Set(userRecords.map { $0.exerciseName })
        ).sorted()
        availableExercises = exerciseNames

        if !availableExercises.isEmpty && selectedExercise.isEmpty {
            selectedExercise = availableExercises[0]
        }

        // Lifetime stats
        totalWorkouts = userSessions.count
        totalPRs = userRecords.count

        totalVolumeKg = userSessions.reduce(0.0) { sessionTotal, session in
            sessionTotal + session.entries.reduce(0.0) { entryTotal, entry in
                entryTotal + entry.sets.filter { $0.isCompleted }.reduce(0.0) { setTotal, set in
                    setTotal + (set.weight * Double(set.reps))
                }
            }
        }

        let calendar = Calendar.current
        let now = Date()
        let startOfMonth = calendar.date(
            from: calendar.dateComponents([.year, .month], from: now)
        ) ?? now
        workoutsThisMonth = userSessions.filter { $0.startedAt >= startOfMonth }.count

        // Top PRs — top 3 by weight
        topPRs = userRecords
            .sorted { $0.weight > $1.weight }
            .prefix(3)
            .map { $0 }

        // Weekly volume — last 8 weeks
        weeklyVolume = buildWeeklyVolume(sessions: userSessions, calendar: calendar, now: now)
    }

    // MARK: - Private Helpers

    private func buildWeeklyVolume(
        sessions: [WorkoutSession],
        calendar: Calendar,
        now: Date
    ) -> [(week: String, totalKg: Double)] {
        // Build a bucket for each of the last 8 ISO weeks ending today
        var buckets: [(weekStart: Date, weekLabel: String, totalKg: Double)] = []

        for weekOffset in (0..<8).reversed() {
            guard let weekStart = calendar.date(
                byAdding: .weekOfYear, value: -weekOffset, to: startOfISOWeek(for: now, calendar: calendar)
            ) else { continue }

            let weekOfYear = calendar.component(.weekOfYear, from: weekStart)
            let label = "W\(weekOfYear)"
            buckets.append((weekStart: weekStart, weekLabel: label, totalKg: 0.0))
        }

        // Sum volume for sessions that fall inside each bucket
        let weekInSeconds: TimeInterval = 7 * 24 * 3600
        var result = buckets

        for session in sessions {
            let sessionDate = session.startedAt
            for index in result.indices {
                let bucketStart = result[index].weekStart
                let bucketEnd = bucketStart.addingTimeInterval(weekInSeconds)
                guard sessionDate >= bucketStart && sessionDate < bucketEnd else { continue }

                let sessionVolume = session.entries.reduce(0.0) { entryTotal, entry in
                    entryTotal + entry.sets.filter { $0.isCompleted }.reduce(0.0) { setTotal, set in
                        setTotal + (set.weight * Double(set.reps))
                    }
                }
                result[index].totalKg += sessionVolume
            }
        }

        return result.map { (week: $0.weekLabel, totalKg: $0.totalKg) }
    }

    private func startOfISOWeek(for date: Date, calendar: Calendar) -> Date {
        var cal = calendar
        cal.firstWeekday = 2 // Monday
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
                    tabPicker
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

    // MARK: - Tab Picker

    private var tabPicker: some View {
        Picker("", selection: $viewModel.selectedTab) {
            Text("Overview").tag(0)
            Text("Strength").tag(1)
            Text("Body").tag(2)
        }
        .pickerStyle(.segmented)
        .tint(Color.kineticsBlue)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.kineticsDark)
    }

    // MARK: - Tab Content

    @ViewBuilder
    private var tabContent: some View {
        TabView(selection: $viewModel.selectedTab) {
            overviewTab
                .tag(0)
            strengthTab
                .tag(1)
            bodyTab
                .tag(2)
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .animation(.easeInOut(duration: 0.22), value: viewModel.selectedTab)
    }

    // MARK: - Overview Tab

    private var overviewTab: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {

                // Lifetime Stats
                ProgressSectionHeader(title: "Lifetime Stats")

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    StatCell(
                        label: "Total Workouts",
                        value: "\(viewModel.totalWorkouts)",
                        icon: "dumbbell.fill",
                        color: Color.kineticsBlue
                    )
                    StatCell(
                        label: "Total Volume",
                        value: formatVolume(viewModel.totalVolumeKg),
                        icon: "scalemass.fill",
                        color: Color.kineticsGreen
                    )
                    StatCell(
                        label: "PRs Set",
                        value: "\(viewModel.totalPRs)",
                        icon: "trophy.fill",
                        color: Color.kineticsAmber
                    )
                    StatCell(
                        label: "This Month",
                        value: "\(viewModel.workoutsThisMonth)",
                        icon: "calendar",
                        color: Color.kineticsPurple
                    )
                }

                // Weekly Volume
                ProgressSectionHeader(title: "Weekly Volume")
                VolumeChartView(data: viewModel.weeklyVolume)
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color.kineticsDark)
                    )

                // Top Lifts
                if !viewModel.topPRs.isEmpty {
                    ProgressSectionHeader(title: "Top Lifts")
                    VStack(spacing: 8) {
                        ForEach(viewModel.topPRs, id: \.id) { record in
                            TopLiftRow(record: record)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 20)
            .padding(.bottom, 32)
        }
    }

    // MARK: - Strength Tab

    private var strengthTab: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {

                // Exercise Picker
                if !viewModel.availableExercises.isEmpty {
                    Picker("Exercise", selection: $viewModel.selectedExercise) {
                        ForEach(viewModel.availableExercises, id: \.self) { name in
                            Text(name).tag(name)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(Color.kineticsBlue)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.kineticsDark)
                    )
                }

                // PR Progression Chart
                StrengthChartView(records: filteredStrengthRecords)
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color.kineticsDark)
                    )

                // Best Set Card
                if let bestSet = filteredStrengthRecords.max(by: { $0.weight < $1.weight }) {
                    BestSetCard(record: bestSet)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 20)
            .padding(.bottom, 32)
        }
    }

    // MARK: - Body Tab

    private var bodyTab: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {

                ProgressSectionHeader(title: "Body Weight")

                BodyWeightChartView(measurements: measurements.filter { $0.weightKg > 0 })
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color.kineticsDark)
                    )

                // Recent Measurements
                let recentMeasurements = Array(
                    measurements.filter { $0.weightKg > 0 }.suffix(5).reversed()
                )

                if !recentMeasurements.isEmpty {
                    ProgressSectionHeader(title: "Recent Entries")
                    VStack(spacing: 8) {
                        ForEach(recentMeasurements, id: \.id) { measurement in
                            MeasurementRow(measurement: measurement)
                        }
                    }
                } else {
                    emptyBodyState
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 20)
            .padding(.bottom, 32)
        }
    }

    // MARK: - Empty Body State

    private var emptyBodyState: some View {
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

    // MARK: - Computed Helpers

    private var filteredStrengthRecords: [PersonalRecord] {
        records
            .filter { $0.exerciseName == viewModel.selectedExercise }
            .sorted { $0.achievedAt < $1.achievedAt }
    }

    private func formatVolume(_ kg: Double) -> String {
        if kg >= 1_000 {
            return String(format: "%.1fk kg", kg / 1_000)
        }
        return String(format: "%.0f kg", kg)
    }
}

// MARK: - StrengthChartView (private)

private struct StrengthChartView: View {

    let records: [PersonalRecord]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("PR Progression")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.kineticsSubtext)
                .textCase(.uppercase)
                .kerning(0.6)

            if records.isEmpty {
                emptyState
            } else {
                chart
            }
        }
    }

    // MARK: Chart

    @ViewBuilder
    private var chart: some View {
        let lastRecord = records.last

        Chart(records, id: \.id) { record in
            // Gradient area fill below the line
            AreaMark(
                x: .value("Date", record.achievedAt),
                y: .value("Weight (kg)", record.weight)
            )
            .foregroundStyle(
                LinearGradient(
                    colors: [
                        Color.kineticsBlue.opacity(0.22),
                        Color.kineticsBlue.opacity(0.03)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .interpolationMethod(.catmullRom)

            // Primary line
            LineMark(
                x: .value("Date", record.achievedAt),
                y: .value("Weight (kg)", record.weight)
            )
            .foregroundStyle(Color.kineticsBlue)
            .lineStyle(StrokeStyle(lineWidth: 2.5))
            .interpolationMethod(.catmullRom)

            // Point markers — filled circle with white center dot
            PointMark(
                x: .value("Date", record.achievedAt),
                y: .value("Weight (kg)", record.weight)
            )
            .foregroundStyle(Color.kineticsBlue)
            .symbolSize(64)

            PointMark(
                x: .value("Date", record.achievedAt),
                y: .value("Weight (kg)", record.weight)
            )
            .foregroundStyle(Color.kineticsDark)
            .symbolSize(20)

            // Floating weight badge on the latest point
            if let last = lastRecord, record.id == last.id {
                PointMark(
                    x: .value("Date", record.achievedAt),
                    y: .value("Weight (kg)", record.weight)
                )
                .annotation(position: .top, alignment: .center, spacing: 8) {
                    Text(formatWeight(record.weight))
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(Color.kineticsBlue)
                        )
                }
                .foregroundStyle(Color.clear)
                .symbolSize(0)
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4, 4]))
                    .foregroundStyle(Color.kineticsSubtext.opacity(0.2))
                AxisTick()
                    .foregroundStyle(Color.kineticsSubtext.opacity(0.3))
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

    // MARK: Empty State

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(Color.kineticsBlue.opacity(0.4))
            Text("No data yet")
                .font(.system(size: 14))
                .foregroundStyle(Color.kineticsSubtext)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 200)
    }

    private func formatWeight(_ kg: Double) -> String {
        kg.truncatingRemainder(dividingBy: 1) == 0
            ? "\(Int(kg)) kg"
            : String(format: "%.1f kg", kg)
    }
}

// MARK: - VolumeChartView (private)

private struct VolumeChartView: View {

    let data: [(week: String, totalKg: Double)]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if data.isEmpty || data.allSatisfy({ $0.totalKg == 0 }) {
                emptyState
            } else {
                chart
            }
        }
    }

    @ViewBuilder
    private var chart: some View {
        Chart(data, id: \.week) { item in
            BarMark(
                x: .value("Week", item.week),
                y: .value("Volume (kg)", item.totalKg)
            )
            .foregroundStyle(Color.kineticsBlue.gradient)
            .cornerRadius(4)
        }
        .chartXAxis {
            AxisMarks { value in
                AxisValueLabel {
                    if let label = value.as(String.self) {
                        Text(label)
                            .font(.system(size: 10))
                            .foregroundStyle(Color.kineticsSubtext)
                    }
                }
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
        .frame(height: 180)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "chart.bar")
                .font(.system(size: 32, weight: .light))
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

// MARK: - BodyWeightChartView (private)

private struct BodyWeightChartView: View {

    let measurements: [BodyMeasurement]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if measurements.isEmpty {
                emptyState
            } else {
                chart
            }
        }
    }

    @ViewBuilder
    private var chart: some View {
        let lastMeasurement = measurements.last

        Chart(measurements, id: \.id) { m in
            AreaMark(
                x: .value("Date", m.recordedAt),
                y: .value("Weight (kg)", m.weightKg)
            )
            .foregroundStyle(
                LinearGradient(
                    colors: [
                        Color.kineticsBlue.opacity(0.25),
                        Color.kineticsBlue.opacity(0.03)
                    ],
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

            // Point marker — filled outer + dark inner dot
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

            // Latest entry label
            if let last = lastMeasurement, m.id == last.id {
                PointMark(
                    x: .value("Date", m.recordedAt),
                    y: .value("Weight (kg)", m.weightKg)
                )
                .annotation(position: .top, alignment: .center, spacing: 8) {
                    Text(String(format: "%.1f kg", m.weightKg))
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.kineticsBlue))
                }
                .foregroundStyle(Color.clear)
                .symbolSize(0)
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4, 4]))
                    .foregroundStyle(Color.kineticsSubtext.opacity(0.2))
                AxisTick()
                    .foregroundStyle(Color.kineticsSubtext.opacity(0.3))
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
                        Text(String(format: "%.1f kg", kg))
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

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "figure.stand")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(Color.kineticsBlue.opacity(0.4))
            Text("No body weight data recorded yet.")
                .font(.system(size: 13))
                .foregroundStyle(Color.kineticsSubtext)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 180)
    }
}

// MARK: - ProgressSectionHeader (private)

private struct ProgressSectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Color.kineticsSubtext)
            .textCase(.uppercase)
            .kerning(0.8)
    }
}

// MARK: - StatCell (private)

private struct StatCell: View {
    let label: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(color)
                    .frame(width: 28, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 7)
                            .fill(color.opacity(0.15))
                    )
                Spacer()
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Text(label)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.kineticsSubtext)
                    .lineLimit(1)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.kineticsDark)
        )
    }
}

// MARK: - TopLiftRow (private)

private struct TopLiftRow: View {
    let record: PersonalRecord

    private var weightText: String {
        let kg = record.weight
        if kg == 0 { return "BW × \(record.reps)" }
        let formatted = kg.truncatingRemainder(dividingBy: 1) == 0
            ? String(Int(kg))
            : String(format: "%.1f", kg)
        return "\(formatted) kg × \(record.reps)"
    }

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "trophy.fill")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color.kineticsAmber)
                .frame(width: 34, height: 34)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.kineticsAmber.opacity(0.15))
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(record.exerciseName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Text(weightText)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.kineticsSubtext)
            }

            Spacer()

            Text(record.achievedAt, format: .dateTime.month(.abbreviated).day())
                .font(.system(size: 12))
                .foregroundStyle(Color.kineticsSubtext.opacity(0.7))
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.kineticsDark)
        )
    }
}

// MARK: - BestSetCard (private)

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
            ProgressSectionHeader(title: "Best Set")

            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(weightText)
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("Weight")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.kineticsSubtext)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Divider()
                    .background(Color.kineticsSubtext.opacity(0.3))
                    .frame(height: 44)
                    .padding(.horizontal, 20)

                VStack(alignment: .leading, spacing: 4) {
                    Text("\(record.reps)")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("Reps")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.kineticsSubtext)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Divider()
                    .background(Color.kineticsSubtext.opacity(0.3))
                    .frame(height: 44)
                    .padding(.horizontal, 20)

                VStack(alignment: .leading, spacing: 4) {
                    Text(record.achievedAt, format: .dateTime.month(.abbreviated).day().year())
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text("Achieved")
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

// MARK: - MeasurementRow (private)

private struct MeasurementRow: View {
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
