import Charts
import SwiftUI

// MARK: - StrengthChartCard

struct StrengthChartCard: View {

    let records: [PersonalRecord]
    let exerciseName: String

    private var oneRMData: [(date: Date, oneRM: Double)] {
        records.map { ($0.achievedAt, $0.weight * (1 + Double($0.reps) / 30.0)) }
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
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Capsule().fill(Color.kineticsAmber.opacity(0.12)))
                }
            }
            if oneRMData.isEmpty { emptyState } else { chart }
        }
        .padding(16)
        .glassCard(cornerRadius: 20)
    }

    private var chart: some View {
        Chart(oneRMData, id: \.date) { item in
            AreaMark(x: .value("Date", item.date), y: .value("Est 1RM", item.oneRM))
                .foregroundStyle(LinearGradient(
                    colors: [Color.kineticsAmber.opacity(0.18), Color.kineticsAmber.opacity(0.02)],
                    startPoint: .top, endPoint: .bottom))
                .interpolationMethod(.catmullRom)
            LineMark(x: .value("Date", item.date), y: .value("Est 1RM", item.oneRM))
                .foregroundStyle(Color.kineticsAmber)
                .lineStyle(StrokeStyle(lineWidth: 2.5))
                .interpolationMethod(.catmullRom)
            PointMark(x: .value("Date", item.date), y: .value("Est 1RM", item.oneRM))
                .foregroundStyle(Color.kineticsAmber).symbolSize(56)
            PointMark(x: .value("Date", item.date), y: .value("Est 1RM", item.oneRM))
                .foregroundStyle(Color.kineticsDark).symbolSize(18)
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4, 4]))
                    .foregroundStyle(Color.kineticsSubtext.opacity(0.2))
                AxisValueLabel {
                    if let d = value.as(Date.self) {
                        Text(d, format: .dateTime.month(.abbreviated).day())
                            .font(.system(size: 10)).foregroundStyle(Color.kineticsSubtext)
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
                        Text("\(Int(kg)) kg").font(.system(size: 10)).foregroundStyle(Color.kineticsSubtext)
                    }
                }
            }
        }
        .chartPlotStyle { $0.background(Color.clear) }
        .frame(height: 220)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 30, weight: .light)).foregroundStyle(Color.kineticsAmber.opacity(0.35))
            Text("No data for this period").font(.system(size: 13)).foregroundStyle(Color.kineticsSubtext)
        }
        .frame(maxWidth: .infinity).frame(height: 180)
    }

    private func formatWeight(_ kg: Double) -> String {
        kg.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(kg)) kg" : String(format: "%.1f kg", kg)
    }
}

// MARK: - VolumeBarChartCard

struct VolumeBarChartCard: View {

    let data: [(week: String, weekStart: Date, totalKg: Double)]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                SectionLabel(text: "WEEKLY VOLUME")
                Spacer()
                if let peak = data.max(by: { $0.totalKg < $1.totalKg }), peak.totalKg > 0 {
                    Text("Peak: \(formatVolume(peak.totalKg))")
                        .font(.system(size: 11, weight: .medium)).foregroundStyle(Color.kineticsSubtext)
                }
            }
            if data.isEmpty || data.allSatisfy({ $0.totalKg == 0 }) { emptyState } else { chart }
        }
        .padding(16)
        .glassCard(cornerRadius: 20)
    }

    private var chart: some View {
        let nonZero = data.filter { $0.totalKg > 0 }
        let avg = nonZero.isEmpty ? 0.0 : nonZero.reduce(0.0) { $0 + $1.totalKg } / Double(nonZero.count)

        return Chart {
            ForEach(data, id: \.week) { item in
                BarMark(
                    x: .value("Week", item.weekStart, unit: .weekOfYear),
                    y: .value("Volume (kg)", item.totalKg)
                )
                .foregroundStyle(LinearGradient(
                    colors: [Color.kineticsBlue, Color.kineticsBlue.opacity(0.5)],
                    startPoint: .top, endPoint: .bottom))
                .cornerRadius(4)
            }
            if avg > 0 {
                RuleMark(y: .value("Average", avg))
                    .foregroundStyle(Color.kineticsGreen.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                    .annotation(position: .top, alignment: .trailing) {
                        Text("avg").font(.system(size: 9, weight: .medium)).foregroundStyle(Color.kineticsGreen.opacity(0.8))
                    }
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .weekOfYear)) { value in
                AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                    .font(.system(size: 9)).foregroundStyle(Color.kineticsSubtext)
            }
        }
        .chartYAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Color.kineticsSubtext.opacity(0.2))
                AxisValueLabel {
                    if let kg = value.as(Double.self) {
                        Text(formatVolume(kg)).font(.system(size: 10)).foregroundStyle(Color.kineticsSubtext)
                    }
                }
            }
        }
        .chartPlotStyle { $0.background(Color.clear) }
        .frame(height: 200)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "chart.bar").font(.system(size: 30, weight: .light)).foregroundStyle(Color.kineticsBlue.opacity(0.4))
            Text("Complete workouts to see your volume trend.")
                .font(.system(size: 13)).foregroundStyle(Color.kineticsSubtext).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).frame(height: 180)
    }

    private func formatVolume(_ kg: Double) -> String {
        kg >= 1_000 ? String(format: "%.0fk", kg / 1_000) : String(format: "%.0f", kg)
    }
}

// MARK: - BodyWeightChartView

struct BodyWeightChartView: View {

    let measurements: [BodyMeasurement]

    var body: some View {
        if measurements.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "figure.stand").font(.system(size: 30, weight: .light)).foregroundStyle(Color.kineticsBlue.opacity(0.4))
                Text("No body weight data recorded yet.")
                    .font(.system(size: 13)).foregroundStyle(Color.kineticsSubtext).multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity).frame(height: 160)
        } else {
            Chart(measurements, id: \.id) { m in
                AreaMark(x: .value("Date", m.recordedAt), y: .value("Weight (kg)", m.weightKg))
                    .foregroundStyle(LinearGradient(
                        colors: [Color.kineticsBlue.opacity(0.22), Color.kineticsBlue.opacity(0.03)],
                        startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.catmullRom)
                LineMark(x: .value("Date", m.recordedAt), y: .value("Weight (kg)", m.weightKg))
                    .foregroundStyle(Color.kineticsBlue).lineStyle(StrokeStyle(lineWidth: 2.5)).interpolationMethod(.catmullRom)
                PointMark(x: .value("Date", m.recordedAt), y: .value("Weight (kg)", m.weightKg))
                    .foregroundStyle(Color.kineticsBlue).symbolSize(52)
                PointMark(x: .value("Date", m.recordedAt), y: .value("Weight (kg)", m.weightKg))
                    .foregroundStyle(Color.kineticsDark).symbolSize(18)
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4, 4])).foregroundStyle(Color.kineticsSubtext.opacity(0.2))
                    AxisValueLabel {
                        if let d = value.as(Date.self) {
                            Text(d, format: .dateTime.month(.abbreviated).day()).font(.system(size: 10)).foregroundStyle(Color.kineticsSubtext)
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4, 4])).foregroundStyle(Color.kineticsSubtext.opacity(0.2))
                    AxisValueLabel {
                        if let kg = value.as(Double.self) {
                            Text(String(format: "%.1f", kg)).font(.system(size: 10)).foregroundStyle(Color.kineticsSubtext)
                        }
                    }
                }
            }
            .chartPlotStyle { $0.background(Color.clear) }
            .frame(height: 200)
        }
    }
}

// MARK: - BodyFatChartView

struct BodyFatChartView: View {

    let measurements: [BodyMeasurement]

    var body: some View {
        Chart(measurements, id: \.id) { m in
            AreaMark(x: .value("Date", m.recordedAt), y: .value("Body Fat %", m.bodyFatPercent))
                .foregroundStyle(LinearGradient(
                    colors: [Color.kineticsPurple.opacity(0.22), Color.kineticsPurple.opacity(0.03)],
                    startPoint: .top, endPoint: .bottom))
                .interpolationMethod(.catmullRom)
            LineMark(x: .value("Date", m.recordedAt), y: .value("Body Fat %", m.bodyFatPercent))
                .foregroundStyle(Color.kineticsPurple).lineStyle(StrokeStyle(lineWidth: 2.5)).interpolationMethod(.catmullRom)
            PointMark(x: .value("Date", m.recordedAt), y: .value("Body Fat %", m.bodyFatPercent))
                .foregroundStyle(Color.kineticsPurple).symbolSize(52)
            PointMark(x: .value("Date", m.recordedAt), y: .value("Body Fat %", m.bodyFatPercent))
                .foregroundStyle(Color.kineticsDark).symbolSize(18)
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4, 4])).foregroundStyle(Color.kineticsSubtext.opacity(0.2))
                AxisValueLabel {
                    if let d = value.as(Date.self) {
                        Text(d, format: .dateTime.month(.abbreviated).day()).font(.system(size: 10)).foregroundStyle(Color.kineticsSubtext)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4, 4])).foregroundStyle(Color.kineticsSubtext.opacity(0.2))
                AxisValueLabel {
                    if let pct = value.as(Double.self) {
                        Text(String(format: "%.1f%%", pct)).font(.system(size: 10)).foregroundStyle(Color.kineticsSubtext)
                    }
                }
            }
        }
        .chartPlotStyle { $0.background(Color.clear) }
        .frame(height: 180)
    }
}

// MARK: - ContributionHeatmap

struct ContributionHeatmap: View {

    let sessions: [WorkoutSession]

    private let columns = 12
    private let cellSize: CGFloat = 22
    private let cellSpacing: CGFloat = 4
    private let dayLabels = ["M", "T", "W", "T", "F", "S", "S"]

    private var trainedDays: Set<String> {
        let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"
        return Set(sessions.map { fmt.string(from: $0.startedAt) })
    }

    private var weeks: [[Date?]] {
        var cal = Calendar.current; cal.firstWeekday = 2
        let today = cal.startOfDay(for: Date())
        guard let ago = cal.date(byAdding: .weekOfYear, value: -(columns - 1), to: today) else { return [] }
        let ws = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: ago)) ?? ago
        var result: [[Date?]] = []
        for w in 0 ..< columns {
            result.append((0 ..< 7).map { d -> Date? in
                guard let day = cal.date(byAdding: .day, value: w * 7 + d, to: ws) else { return nil }
                return day <= today ? day : nil
            })
        }
        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: cellSpacing) {
                VStack(spacing: cellSpacing) {
                    ForEach(0 ..< 7, id: \.self) { i in
                        Text(dayLabels[i])
                            .font(.system(size: 9, weight: .medium)).foregroundStyle(Color.kineticsSubtext)
                            .frame(width: 12, height: cellSize)
                    }
                }
                HStack(alignment: .top, spacing: cellSpacing) {
                    ForEach(0 ..< weeks.count, id: \.self) { wi in
                        VStack(spacing: cellSpacing) {
                            ForEach(0 ..< 7, id: \.self) { di in heatCell(weeks[wi][di]) }
                        }
                    }
                }
            }
            HStack(spacing: 8) {
                Text("Less").font(.system(size: 10)).foregroundStyle(Color.kineticsSubtext)
                HStack(spacing: 3) {
                    ForEach([0.0, 0.35, 0.65, 1.0], id: \.self) { op in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(op == 0 ? Color.kineticsSubtext.opacity(0.15) : Color.kineticsGreen.opacity(op))
                            .frame(width: cellSize, height: cellSize)
                    }
                }
                Text("More").font(.system(size: 10)).foregroundStyle(Color.kineticsSubtext)
            }
            .padding(.top, 4)
        }
    }

    private static let heatDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    @ViewBuilder
    private func heatCell(_ day: Date?) -> some View {
        if let day {
            let key = Self.heatDateFormatter.string(from: day)
            RoundedRectangle(cornerRadius: 4)
                .fill(trainedDays.contains(key) ? Color.kineticsGreen : Color.kineticsSubtext.opacity(0.12))
                .frame(width: cellSize, height: cellSize)
        } else {
            RoundedRectangle(cornerRadius: 4).fill(Color.clear).frame(width: cellSize, height: cellSize)
        }
    }
}

// MARK: - BestSetCard

struct BestSetCard: View {

    let record: PersonalRecord

    private var weightText: String {
        guard record.weight > 0 else { return "Bodyweight" }
        return record.weight.truncatingRemainder(dividingBy: 1) == 0
            ? "\(Int(record.weight)) kg" : String(format: "%.1f kg", record.weight)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionLabel(text: "BEST SET")
            HStack(spacing: 0) {
                statColumn(value: weightText, label: "Weight")
                rowDivider
                statColumn(value: "\(record.reps)", label: "Reps")
                rowDivider
                VStack(alignment: .leading, spacing: 4) {
                    Text(record.achievedAt, format: .dateTime.month(.abbreviated).day().year())
                        .font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
                        .lineLimit(1).minimumScaleFactor(0.7)
                    Text("Date").font(.system(size: 11)).foregroundStyle(Color.kineticsSubtext)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(.ultraThinMaterial)
                    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.kineticsBlue.opacity(0.2), lineWidth: 0.75))
            )
        }
    }

    private func statColumn(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value).font(.system(size: 26, weight: .bold, design: .rounded)).foregroundStyle(.white)
            Text(label).font(.system(size: 11)).foregroundStyle(Color.kineticsSubtext)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var rowDivider: some View {
        Divider()
            .background(Color.kineticsSubtext.opacity(0.3))
            .frame(height: 44)
            .padding(.horizontal, 18)
    }
}

// MARK: - VolumeStatCell

struct VolumeStatCell: View {

    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 9, weight: .bold)).foregroundStyle(Color.kineticsSubtext).tracking(0.7)
            Text(value).font(.system(size: 16, weight: .bold, design: .rounded)).foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .glassCard(cornerRadius: 12)
    }
}

// MARK: - ConsistencyStatCell

struct ConsistencyStatCell: View {

    let label: String
    let value: String
    let unit: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 9, weight: .bold)).foregroundStyle(Color.kineticsSubtext).tracking(0.7)
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(color)
                .monospacedDigit()
                .contentTransition(.numericText())
            Text(unit).font(.system(size: 11)).foregroundStyle(Color.kineticsSubtext)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(.ultraThinMaterial)
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(color.opacity(0.2), lineWidth: 0.75))
        )
    }
}

// MARK: - BodyMeasRow

struct BodyMeasRow: View {

    let measurement: BodyMeasurement

    private var weightText: String {
        measurement.weightKg.truncatingRemainder(dividingBy: 1) == 0
            ? "\(Int(measurement.weightKg)) kg"
            : String(format: "%.1f kg", measurement.weightKg)
    }

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "scalemass.fill")
                .font(.system(size: 15, weight: .medium)).foregroundStyle(Color.kineticsBlue)
                .frame(width: 34, height: 34)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.kineticsBlue.opacity(0.15)))

            VStack(alignment: .leading, spacing: 2) {
                Text(measurement.recordedAt, format: .dateTime.month(.abbreviated).day().year())
                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                if measurement.bodyFatPercent > 0 {
                    Text("Body fat: \(String(format: "%.1f%%", measurement.bodyFatPercent))")
                        .font(.system(size: 12)).foregroundStyle(Color.kineticsSubtext)
                }
            }

            Spacer()
            Text(weightText).font(.system(size: 15, weight: .semibold, design: .rounded)).foregroundStyle(Color.kineticsBlue)
        }
        .padding(14)
        .glassCard(cornerRadius: 12)
    }
}
