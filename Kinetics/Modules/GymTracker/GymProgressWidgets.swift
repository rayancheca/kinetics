import Charts
import SwiftUI

// MARK: - View+GlassCard

extension View {
    /// Applies the shared glassmorphism card background used throughout the progress dashboard.
    func glassCard(cornerRadius: CGFloat = 16) -> some View {
        self.background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .strokeBorder(.white.opacity(0.08), lineWidth: 0.75)
                )
        )
    }
}

// MARK: - SectionLabel

struct SectionLabel: View {

    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(Color.kineticsSubtext)
            .tracking(2.5)
    }
}

// MARK: - ProgressTabButton

struct ProgressTabButton: View {

    let tab: ProgressTab
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Text(tab.rawValue)
                .font(.system(size: 14, weight: isSelected ? .bold : .regular))
                .foregroundStyle(isSelected ? .white : Color.kineticsSubtext)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isSelected ? Color.kineticsBlue.opacity(0.18) : Color.clear)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(isSelected ? Color.kineticsBlue.opacity(0.4) : Color.clear, lineWidth: 1)
                        )
                )
        }
        .buttonStyle(.plain)
        .animation(.spring(duration: 0.2), value: isSelected)
    }
}

// MARK: - MuscleMapCard

struct MuscleMapCard: View {

    let trainedThisWeek: Set<String>
    let trainedThisMonth: Set<String>

    @State private var appeared = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionLabel(text: "MUSCLE MAP")

            HStack(alignment: .top, spacing: 20) {
                BodySilhouetteView(
                    trainedThisWeek: trainedThisWeek,
                    trainedThisMonth: trainedThisMonth,
                    appeared: appeared
                )
                .frame(width: 120, height: 220)

                VStack(alignment: .leading, spacing: 12) {
                    legendRow(label: "This Week", color: Color.kineticsBlue, opacity: 0.85)
                    legendRow(label: "This Month", color: Color.kineticsBlue, opacity: 0.28)
                    legendRow(label: "Not Trained", color: Color.kineticsSubtext, opacity: 0.18)

                    Spacer(minLength: 8)

                    if !trainedThisWeek.isEmpty {
                        Text("TRAINED THIS WEEK")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Color.kineticsSubtext)
                            .tracking(1.5)

                        FlowLayout(spacing: 6) {
                            ForEach(Array(trainedThisWeek).sorted(), id: \.self) { muscle in
                                let group = GymMuscleGroup(rawValue: muscle) ?? .other
                                MuscleChip(name: muscle, color: group.color, appeared: appeared)
                            }
                        }
                    } else {
                        Text("Train today to light up your map")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.kineticsSubtext)
                            .italic()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(20)
        .glassCard(cornerRadius: 20)
        .onAppear {
            withAnimation(.easeOut(duration: 0.6)) { appeared = true }
        }
    }

    private func legendRow(label: String, color: Color, opacity: Double) -> some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 3)
                .fill(color.opacity(opacity))
                .frame(width: 14, height: 14)
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(Color.kineticsSubtext)
        }
    }
}

// MARK: - BodySilhouetteView

struct BodySilhouetteView: View {

    let trainedThisWeek: Set<String>
    let trainedThisMonth: Set<String>
    let appeared: Bool

    private func opacity(for muscle: GymMuscleGroup) -> Double {
        let name = muscle.rawValue
        if trainedThisWeek.contains(name) { return appeared ? 0.85 : 0 }
        if trainedThisMonth.contains(name) { return appeared ? 0.28 : 0 }
        return 0.08
    }

    var body: some View {
        Canvas { context, size in
            let w = size.width
            let h = size.height

            context.stroke(
                bodyOutlinePath(w: w, h: h),
                with: .color(.white.opacity(0.18)),
                lineWidth: 1.5
            )

            let zones: [(GymMuscleGroup, Path)] = [
                (.chest, chestZone(w: w, h: h)),
                (.core, coreZone(w: w, h: h)),
                (.shoulders, shouldersZone(w: w, h: h)),
                (.biceps, bicepsZone(w: w, h: h)),
                (.triceps, tricepsZone(w: w, h: h)),
                (.forearms, forearmsZone(w: w, h: h)),
                (.quadriceps, quadsZone(w: w, h: h)),
                (.hamstrings, hamsZone(w: w, h: h)),
                (.glutes, glutesZone(w: w, h: h)),
                (.calves, calvesZone(w: w, h: h)),
                (.back, backZone(w: w, h: h)),
            ]

            for (muscle, path) in zones {
                context.fill(path, with: .color(muscle.color.opacity(opacity(for: muscle))))
            }
        }
        .animation(.easeOut(duration: 0.8), value: appeared)
    }

    // MARK: Outline

    private func bodyOutlinePath(w: CGFloat, h: CGFloat) -> Path {
        var path = Path()
        let headR = w * 0.13
        let headCX = w * 0.5
        let headCY = h * 0.07
        path.addEllipse(in: CGRect(x: headCX - headR, y: headCY - headR, width: headR * 2, height: headR * 2))
        path.move(to: CGPoint(x: w * 0.43, y: headCY + headR))
        path.addLine(to: CGPoint(x: w * 0.43, y: h * 0.20))
        path.move(to: CGPoint(x: w * 0.57, y: headCY + headR))
        path.addLine(to: CGPoint(x: w * 0.57, y: h * 0.20))
        path.addRoundedRect(in: CGRect(x: w * 0.22, y: h * 0.18, width: w * 0.56, height: h * 0.33), cornerSize: CGSize(width: 8, height: 8))
        path.addRoundedRect(in: CGRect(x: w * 0.03, y: h * 0.19, width: w * 0.17, height: h * 0.20), cornerSize: CGSize(width: 6, height: 6))
        path.addRoundedRect(in: CGRect(x: w * 0.04, y: h * 0.41, width: w * 0.14, height: h * 0.17), cornerSize: CGSize(width: 5, height: 5))
        path.addRoundedRect(in: CGRect(x: w * 0.80, y: h * 0.19, width: w * 0.17, height: h * 0.20), cornerSize: CGSize(width: 6, height: 6))
        path.addRoundedRect(in: CGRect(x: w * 0.82, y: h * 0.41, width: w * 0.14, height: h * 0.17), cornerSize: CGSize(width: 5, height: 5))
        path.addRoundedRect(in: CGRect(x: w * 0.23, y: h * 0.52, width: w * 0.23, height: h * 0.24), cornerSize: CGSize(width: 7, height: 7))
        path.addRoundedRect(in: CGRect(x: w * 0.25, y: h * 0.78, width: w * 0.20, height: h * 0.19), cornerSize: CGSize(width: 6, height: 6))
        path.addRoundedRect(in: CGRect(x: w * 0.54, y: h * 0.52, width: w * 0.23, height: h * 0.24), cornerSize: CGSize(width: 7, height: 7))
        path.addRoundedRect(in: CGRect(x: w * 0.55, y: h * 0.78, width: w * 0.20, height: h * 0.19), cornerSize: CGSize(width: 6, height: 6))
        return path
    }

    // MARK: Zones

    private func chestZone(w: CGFloat, h: CGFloat) -> Path { Path(CGRect(x: w * 0.25, y: h * 0.19, width: w * 0.50, height: h * 0.13)) }
    private func coreZone(w: CGFloat, h: CGFloat) -> Path { Path(CGRect(x: w * 0.27, y: h * 0.32, width: w * 0.46, height: h * 0.18)) }
    private func glutesZone(w: CGFloat, h: CGFloat) -> Path { Path(CGRect(x: w * 0.27, y: h * 0.49, width: w * 0.46, height: h * 0.09)) }
    private func backZone(w: CGFloat, h: CGFloat) -> Path { Path(CGRect(x: w * 0.29, y: h * 0.22, width: w * 0.42, height: h * 0.08)) }

    private func shouldersZone(w: CGFloat, h: CGFloat) -> Path {
        var p = Path()
        p.addEllipse(in: CGRect(x: w * 0.05, y: h * 0.18, width: w * 0.19, height: h * 0.11))
        p.addEllipse(in: CGRect(x: w * 0.76, y: h * 0.18, width: w * 0.19, height: h * 0.11))
        return p
    }

    private func bicepsZone(w: CGFloat, h: CGFloat) -> Path {
        var p = Path()
        p.addRoundedRect(in: CGRect(x: w * 0.04, y: h * 0.29, width: w * 0.15, height: h * 0.11), cornerSize: CGSize(width: 5, height: 5))
        p.addRoundedRect(in: CGRect(x: w * 0.81, y: h * 0.29, width: w * 0.15, height: h * 0.11), cornerSize: CGSize(width: 5, height: 5))
        return p
    }

    private func tricepsZone(w: CGFloat, h: CGFloat) -> Path {
        var p = Path()
        p.addRoundedRect(in: CGRect(x: w * 0.04, y: h * 0.41, width: w * 0.14, height: h * 0.10), cornerSize: CGSize(width: 5, height: 5))
        p.addRoundedRect(in: CGRect(x: w * 0.82, y: h * 0.41, width: w * 0.14, height: h * 0.10), cornerSize: CGSize(width: 5, height: 5))
        return p
    }

    private func forearmsZone(w: CGFloat, h: CGFloat) -> Path {
        var p = Path()
        p.addRoundedRect(in: CGRect(x: w * 0.05, y: h * 0.52, width: w * 0.13, height: h * 0.10), cornerSize: CGSize(width: 4, height: 4))
        p.addRoundedRect(in: CGRect(x: w * 0.82, y: h * 0.52, width: w * 0.13, height: h * 0.10), cornerSize: CGSize(width: 4, height: 4))
        return p
    }

    private func quadsZone(w: CGFloat, h: CGFloat) -> Path {
        var p = Path()
        p.addRoundedRect(in: CGRect(x: w * 0.24, y: h * 0.53, width: w * 0.21, height: h * 0.22), cornerSize: CGSize(width: 6, height: 6))
        p.addRoundedRect(in: CGRect(x: w * 0.55, y: h * 0.53, width: w * 0.21, height: h * 0.22), cornerSize: CGSize(width: 6, height: 6))
        return p
    }

    private func hamsZone(w: CGFloat, h: CGFloat) -> Path {
        var p = Path()
        p.addRoundedRect(in: CGRect(x: w * 0.25, y: h * 0.78, width: w * 0.19, height: h * 0.10), cornerSize: CGSize(width: 5, height: 5))
        p.addRoundedRect(in: CGRect(x: w * 0.56, y: h * 0.78, width: w * 0.19, height: h * 0.10), cornerSize: CGSize(width: 5, height: 5))
        return p
    }

    private func calvesZone(w: CGFloat, h: CGFloat) -> Path {
        var p = Path()
        p.addRoundedRect(in: CGRect(x: w * 0.26, y: h * 0.88, width: w * 0.18, height: h * 0.09), cornerSize: CGSize(width: 4, height: 4))
        p.addRoundedRect(in: CGRect(x: w * 0.56, y: h * 0.88, width: w * 0.18, height: h * 0.09), cornerSize: CGSize(width: 4, height: 4))
        return p
    }
}

// MARK: - MuscleChip

struct MuscleChip: View {

    let name: String
    let color: Color
    let appeared: Bool

    var body: some View {
        Text(name)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(color.opacity(0.15))
                    .overlay(Capsule().strokeBorder(color.opacity(0.3), lineWidth: 0.75))
            )
            .scaleEffect(appeared ? 1.0 : 0.7)
            .opacity(appeared ? 1.0 : 0)
            .animation(.spring(duration: 0.4, bounce: 0.3), value: appeared)
    }
}

// MARK: - FlowLayout

struct FlowLayout: Layout {

    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? 0
        var height: CGFloat = 0
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0

        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if rowWidth + size.width > maxWidth, rowWidth > 0 {
                height += rowHeight + spacing
                rowWidth = 0
                rowHeight = 0
            }
            rowWidth += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth, height: height + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                y += rowHeight + spacing
                x = bounds.minX
                rowHeight = 0
            }
            sub.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

// MARK: - WeeklyRingsCard

struct WeeklyRingsCard: View {

    let sessionsThisWeek: Int
    let volumeThisWeek: Double
    let volumeLastWeek: Double
    let activeDaysThisWeek: Int

    private let sessionTarget: Double = 5
    private let dayTarget: Double = 7

    @State private var appeared = false

    private var volumeRingProgress: Double {
        guard volumeLastWeek > 0 else { return min(Double(sessionsThisWeek) / sessionTarget, 1.0) }
        return min(volumeThisWeek / (volumeLastWeek * 1.5), 1.0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SectionLabel(text: "THIS WEEK")

            HStack(alignment: .center, spacing: 28) {
                ZStack {
                    ActivityRing(progress: appeared ? min(Double(sessionsThisWeek) / sessionTarget, 1.0) : 0, color: Color.kineticsBlue, lineWidth: 10, radius: 58)
                    ActivityRing(progress: appeared ? volumeRingProgress : 0, color: Color.kineticsGreen, lineWidth: 10, radius: 42)
                    ActivityRing(progress: appeared ? min(Double(activeDaysThisWeek) / dayTarget, 1.0) : 0, color: Color.kineticsOrange, lineWidth: 10, radius: 26)
                    Image(systemName: "flame.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color.kineticsAmber)
                }
                .frame(width: 136, height: 136)

                VStack(alignment: .leading, spacing: 14) {
                    ringLabel(color: Color.kineticsBlue, value: "\(sessionsThisWeek)", label: "Sessions", sub: "of \(Int(sessionTarget)) target")
                    ringLabel(
                        color: Color.kineticsGreen,
                        value: formatVolume(volumeThisWeek),
                        label: "Volume",
                        sub: volumeLastWeek > 0
                            ? (volumeThisWeek >= volumeLastWeek ? "↑ vs last week" : "↓ vs last week")
                            : "this week"
                    )
                    ringLabel(color: Color.kineticsOrange, value: "\(activeDaysThisWeek)", label: "Active days", sub: "of 7")
                }
            }
        }
        .padding(20)
        .glassCard(cornerRadius: 20)
        .onAppear {
            withAnimation(.easeOut(duration: 1.0)) { appeared = true }
        }
    }

    private func ringLabel(color: Color, value: String, label: String, sub: String) -> some View {
        HStack(spacing: 10) {
            Circle().fill(color).frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 1) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(value)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                    Text(label)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.kineticsSubtext)
                }
                Text(sub)
                    .font(.system(size: 10))
                    .foregroundStyle(color.opacity(0.8))
            }
        }
    }

    private func formatVolume(_ kg: Double) -> String {
        kg >= 1_000 ? String(format: "%.1fk", kg / 1_000) : String(format: "%.0f kg", kg)
    }
}

// MARK: - ActivityRing

struct ActivityRing: View {

    let progress: Double
    let color: Color
    let lineWidth: CGFloat
    let radius: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.12), lineWidth: lineWidth)
                .frame(width: radius * 2, height: radius * 2)
            Circle()
                .trim(from: 0, to: CGFloat(progress))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .frame(width: radius * 2, height: radius * 2)
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 1.0), value: progress)
        }
    }
}

// MARK: - StrengthProgressionCard

struct StrengthProgressionCard: View {

    let progressions: [String: [(date: Date, estimatedOneRM: Double)]]

    @State private var appeared = false

    private let palette: [Color] = [
        Color.kineticsBlue, Color.kineticsGreen, Color.kineticsAmber,
        Color.kineticsPurple, Color.kineticsOrange,
    ]

    private var sortedKeys: [String] {
        progressions.keys.sorted { (progressions[$0]?.count ?? 0) > (progressions[$1]?.count ?? 0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionLabel(text: "STRENGTH PROGRESSION — TOP 5")

            if appeared {
                Chart {
                    ForEach(Array(sortedKeys.enumerated()), id: \.element) { index, exercise in
                        let color = palette[index % palette.count]
                        let data = progressions[exercise] ?? []
                        ForEach(data.indices, id: \.self) { i in
                            AreaMark(
                                x: .value("Date", data[i].date),
                                y: .value("1RM", data[i].estimatedOneRM),
                                series: .value("Exercise", exercise)
                            )
                            .foregroundStyle(color.opacity(0.08))
                            .interpolationMethod(.catmullRom)

                            LineMark(
                                x: .value("Date", data[i].date),
                                y: .value("1RM", data[i].estimatedOneRM),
                                series: .value("Exercise", exercise)
                            )
                            .foregroundStyle(color)
                            .lineStyle(StrokeStyle(lineWidth: 2))
                            .interpolationMethod(.catmullRom)

                            PointMark(
                                x: .value("Date", data[i].date),
                                y: .value("1RM", data[i].estimatedOneRM)
                            )
                            .foregroundStyle(color)
                            .symbolSize(32)
                        }
                    }
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
                                Text("\(Int(kg)) kg").font(.system(size: 10)).foregroundStyle(Color.kineticsSubtext)
                            }
                        }
                    }
                }
                .chartPlotStyle { $0.background(Color.clear) }
                .frame(height: 200)
                .transition(.opacity.combined(with: .scale(scale: 0.96)))

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(Array(sortedKeys.enumerated()), id: \.element) { index, name in
                            HStack(spacing: 6) {
                                RoundedRectangle(cornerRadius: 2).fill(palette[index % palette.count]).frame(width: 16, height: 3)
                                Text(name).font(.system(size: 11)).foregroundStyle(Color.kineticsSubtext).lineLimit(1)
                            }
                        }
                    }
                }
            }
        }
        .padding(20)
        .glassCard(cornerRadius: 20)
        .onAppear {
            withAnimation(.easeOut(duration: 0.5).delay(0.2)) { appeared = true }
        }
    }
}

// MARK: - PRTimelineSection

struct PRTimelineSection: View {

    let records: [PersonalRecord]

    @State private var appeared = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionLabel(text: "PERSONAL RECORDS")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(Array(records.enumerated()), id: \.element.id) { index, record in
                        PRTimelineCard(record: record, appeared: appeared, index: index)
                    }
                }
                .padding(.horizontal, 2)
            }
        }
        .onAppear {
            withAnimation(.spring(duration: 0.5, bounce: 0.2)) { appeared = true }
        }
    }
}

// MARK: - PRCard

struct PRTimelineCard: View {

    let record: PersonalRecord
    let appeared: Bool
    let index: Int

    private var weightText: String {
        guard record.weight > 0 else { return "BW" }
        return record.weight.truncatingRemainder(dividingBy: 1) == 0
            ? "\(Int(record.weight))"
            : String(format: "%.1f", record.weight)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "trophy.fill").font(.system(size: 14, weight: .bold)).foregroundStyle(Color.kineticsAmber)
                Spacer()
                Text(record.achievedAt, format: .dateTime.month(.abbreviated).day().year())
                    .font(.system(size: 10))
                    .foregroundStyle(Color.kineticsSubtext)
            }
            Text(record.exerciseName)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(2)

            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(weightText)
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .foregroundStyle(Color.kineticsAmber)
                Text("kg").font(.system(size: 12, weight: .medium)).foregroundStyle(Color.kineticsSubtext)
            }
            Text("× \(record.reps) reps")
                .font(.system(size: 11))
                .foregroundStyle(Color.kineticsSubtext)
        }
        .padding(16)
        .frame(width: 150)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.kineticsAmber.opacity(0.25), lineWidth: 0.75))
        )
        .scaleEffect(appeared ? 1.0 : 0.85)
        .opacity(appeared ? 1.0 : 0)
        .animation(.spring(duration: 0.45, bounce: 0.25).delay(Double(index) * 0.08), value: appeared)
    }
}

// MARK: - BodyCompositionCard

struct BodyCompositionCard: View {

    let measurement: BodyMeasurement
    let allMeasurements: [BodyMeasurement]

    private var weightTrend: Double? {
        let sorted = allMeasurements.filter { $0.weightKg > 0 }.sorted { $0.recordedAt < $1.recordedAt }
        guard sorted.count >= 2, let last = sorted.last, let prev = sorted.dropLast().last else { return nil }
        return last.weightKg - prev.weightKg
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionLabel(text: "BODY COMPOSITION")
            HStack(spacing: 12) {
                tile(icon: "scalemass.fill", color: Color.kineticsBlue, title: "Weight",
                     value: measurement.weightKg > 0 ? String(format: "%.1f kg", measurement.weightKg) : "—",
                     trendText: weightTrend.map {
                         $0 >= 0
                             ? "↑ \(String(format: "%.1f", abs($0))) kg"
                             : "↓ \(String(format: "%.1f", abs($0))) kg"
                     },
                     trendColor: weightTrend.map { $0 >= 0 ? Color.kineticsGreen : Color.kineticsRed })

                if measurement.bodyFatPercent > 0 {
                    tile(icon: "percent", color: Color.kineticsPurple, title: "Body Fat",
                         value: String(format: "%.1f%%", measurement.bodyFatPercent),
                         trendText: nil, trendColor: nil)
                }
                if measurement.skeletalMuscleMassKg > 0 {
                    tile(icon: "figure.strengthtraining.traditional", color: Color.kineticsGreen, title: "Muscle",
                         value: String(format: "%.1f kg", measurement.skeletalMuscleMassKg),
                         trendText: nil, trendColor: nil)
                }
            }
        }
        .padding(20)
        .glassCard(cornerRadius: 20)
    }

    private func tile(
        icon: String, color: Color, title: String,
        value: String, trendText: String?, trendColor: Color?
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon).font(.system(size: 14, weight: .medium)).foregroundStyle(color)
            Text(value).font(.system(size: 17, weight: .bold, design: .rounded)).foregroundStyle(.white)
            if let t = trendText, let tc = trendColor {
                Text(t).font(.system(size: 10, weight: .medium)).foregroundStyle(tc)
            }
            Text(title).font(.system(size: 10)).foregroundStyle(Color.kineticsSubtext)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(color.opacity(0.08))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(color.opacity(0.2), lineWidth: 0.75))
        )
    }
}

// MARK: - VolumeTrendCard

struct VolumeTrendCard: View {

    let data: [(weekLabel: String, volume: Double)]

    @State private var appeared = false

    private var currentWeekLabel: String { data.last?.weekLabel ?? "" }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionLabel(text: "8-WEEK VOLUME TREND")

            if appeared {
                Chart {
                    ForEach(data, id: \.weekLabel) { item in
                        let isCurrent = item.weekLabel == currentWeekLabel
                        BarMark(x: .value("Week", item.weekLabel), y: .value("Volume", item.volume))
                            .foregroundStyle(
                                isCurrent
                                    ? AnyShapeStyle(Color.kineticsBlue)
                                    : AnyShapeStyle(LinearGradient(
                                        colors: [Color.kineticsBlue.opacity(0.7), Color.kineticsBlue.opacity(0.3)],
                                        startPoint: .top, endPoint: .bottom
                                    ))
                            )
                            .cornerRadius(5)
                    }
                }
                .chartXAxis {
                    AxisMarks { value in
                        AxisValueLabel {
                            if let label = value.as(String.self) {
                                Text(label)
                                    .font(.system(size: 9))
                                    .foregroundStyle(label == currentWeekLabel ? Color.kineticsBlue : Color.kineticsSubtext)
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Color.kineticsSubtext.opacity(0.2))
                        AxisValueLabel {
                            if let kg = value.as(Double.self) {
                                Text(kg >= 1_000 ? String(format: "%.0fk", kg / 1_000) : String(format: "%.0f", kg))
                                    .font(.system(size: 10)).foregroundStyle(Color.kineticsSubtext)
                            }
                        }
                    }
                }
                .chartPlotStyle { $0.background(Color.clear) }
                .frame(height: 180)
                .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .bottom)))
            }
        }
        .padding(20)
        .glassCard(cornerRadius: 20)
        .onAppear {
            withAnimation(.easeOut(duration: 0.6).delay(0.3)) { appeared = true }
        }
    }
}

// NOTE: StrengthChartCard, VolumeBarChartCard, BodyWeightChartView, BodyFatChartView,
// ContributionHeatmap, BestSetCard, VolumeStatCell, ConsistencyStatCell, and BodyMeasRow
// are defined in GymProgressCharts.swift to keep file sizes under 800 lines.
