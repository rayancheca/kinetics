import SwiftUI

// MARK: - TrainPerformanceViewModel

@Observable @MainActor
final class TrainPerformanceViewModel {

    // MARK: State

    var sessions: [SessionResult] = []
    var isLoading = false

    // MARK: - Filtered Access

    func sessions(for sport: SportType) -> [SessionResult] {
        sessions.filter { $0.sport == sport }
    }

    func totalSessions(for sport: SportType) -> Int {
        sessions(for: sport).count
    }

    func totalDuration(for sport: SportType) -> TimeInterval {
        sessions(for: sport).reduce(0) { $0 + $1.duration }
    }

    /// Returns the personal-best primary metric for the given sport.
    ///
    /// Metric keys and labels per sport:
    /// - striking     → `strikeVelocityMPH` / "mph"
    /// - grappling    → `kuzushiIndex` / "kuzushi"
    /// - ironTracker  → `barVelocityMS` / "m/s"
    /// - wallBeta     → `hipProximityScore` / "prox%"
    func personalBest(
        for sport: SportType
    ) -> (value: Double, label: String, date: Date)? {
        let key: String
        let label: String
        switch sport {
        case .striking:    key = "strikeVelocityMPH"; label = "mph"
        case .grappling:   key = "kuzushiIndex";      label = "kuzushi"
        case .ironTracker: key = "barVelocityMS";     label = "m/s"
        case .wallBeta:    key = "hipProximityScore"; label = "prox%"
        }
        let candidates = sessions(for: sport).compactMap { s -> (Double, Date)? in
            guard let v = s.metrics[key] else { return nil }
            return (v, s.startedAt)
        }
        guard let best = candidates.max(by: { $0.0 < $1.0 }) else { return nil }
        return (best.0, label, best.1)
    }

    /// Returns the last 10 sessions' primary metric values for the given sport,
    /// ordered oldest-first.
    func trendData(for sport: SportType) -> [Double] {
        let key: String
        switch sport {
        case .striking:    key = "strikeVelocityMPH"
        case .grappling:   key = "kuzushiIndex"
        case .ironTracker: key = "barVelocityMS"
        case .wallBeta:    key = "hipProximityScore"
        }
        return sessions(for: sport)
            .sorted { $0.startedAt < $1.startedAt }
            .suffix(10)
            .compactMap { $0.metrics[key] }
    }

    /// Returns a 52 × 7 grid (week × day, Sunday = 0) of session counts
    /// across all sports for the trailing 52 weeks.
    func heatmapData() -> [[Int]] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        // Anchor to the most-recent Sunday so the grid starts on a full week.
        let weekday = calendar.component(.weekday, from: today) // 1=Sun
        guard let anchor = calendar.date(
            byAdding: .day, value: -(weekday - 1), to: today
        ) else { return [] }

        // Build a Set<Date> of session start days for O(1) lookup.
        var dayCounts: [Date: Int] = [:]
        for session in sessions {
            let day = calendar.startOfDay(for: session.startedAt)
            dayCounts[day, default: 0] += 1
        }

        var grid: [[Int]] = []
        for week in 0..<52 {
            var weekRow: [Int] = []
            for day in 0..<7 {
                let offset = week * 7 + day - (52 * 7 - 7)
                guard let date = calendar.date(
                    byAdding: .day, value: offset, to: anchor
                ) else {
                    weekRow.append(0)
                    continue
                }
                weekRow.append(dayCounts[date] ?? 0)
            }
            grid.append(weekRow)
        }
        return grid
    }

    // MARK: - Load

    func load(userId: String) async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            sessions = try await SessionRepository.shared.fetchSessions(
                for: userId, limit: 200
            )
        } catch {
            sessions = []
        }
    }
}

// MARK: - TrainPerformanceView

struct TrainPerformanceView: View {

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var vm = TrainPerformanceViewModel()
    @State private var selectedSport: SportType = .striking
    @Namespace private var pillNS

    private var uid: String {
        appState.authManager.currentUser?.uid ?? "preview-user"
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 24) {
                    headerRow
                    sportSelector
                    overviewGrid
                    trendSection
                    heatmapSection
                    personalRecordsSection
                    volumeBreakdownSection
                }
                .padding(.top, 20)
                .padding(.bottom, 80)
            }
            .background(Color.kineticsBackground)
            .navigationBarHidden(true)
            .task { await vm.load(userId: uid) }
        }
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack {
            Text("PERFORMANCE")
                .font(.system(size: 26, weight: .black))
                .tracking(4)
                .foregroundStyle(.white)
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.kineticsSubtext)
                    .padding(10)
                    .background(Color.kineticsDark, in: Circle())
            }
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Sport Selector

    private var sportSelector: some View {
        HStack(spacing: 8) {
            ForEach(SportType.allCases, id: \.self) { sport in
                sportPill(sport)
            }
        }
        .padding(.horizontal, 20)
    }

    @ViewBuilder
    private func sportPill(_ sport: SportType) -> some View {
        let isSelected = selectedSport == sport
        let accent = Color.moduleColor(for: sport)

        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                selectedSport = sport
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: sport.systemImage)
                    .font(.system(size: 11, weight: .semibold))
                if isSelected {
                    Text(sport.displayName
                        .components(separatedBy: " ").first ?? sport.displayName)
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(1)
                }
            }
            .foregroundStyle(isSelected ? .white : Color.kineticsSubtext)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(isSelected ? accent : Color.kineticsDark)
                    .matchedGeometryEffect(
                        id: isSelected ? "pill" : sport.rawValue,
                        in: pillNS
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Overview Grid

    private var overviewGrid: some View {
        let accent = Color.moduleColor(for: selectedSport)
        let count = vm.totalSessions(for: selectedSport)
        let secs = vm.totalDuration(for: selectedSport)
        let hours = Int(secs) / 3600
        let minutes = (Int(secs) % 3600) / 60
        let timeStr = hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
        let pb = vm.personalBest(for: selectedSport)
        let pbStr = pb.map {
            String(format: "%.1f %@", $0.value, $0.label)
        } ?? "—"
        let thisMonth = vm.sessions(for: selectedSport).filter {
            Calendar.current.isDate($0.startedAt, equalTo: Date(), toGranularity: .month)
        }.count

        return LazyVGrid(
            columns: [GridItem(.flexible()), GridItem(.flexible())],
            spacing: 12
        ) {
            PerformanceStatCard(title: "Sessions", value: "\(count)", accent: accent)
            PerformanceStatCard(title: "Total Time", value: timeStr, accent: accent)
            PerformanceStatCard(title: "Personal Best", value: pbStr, accent: accent)
            PerformanceStatCard(title: "This Month", value: "\(thisMonth)", accent: accent)
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Trend Chart

    private var trendSection: some View {
        let data = vm.trendData(for: selectedSport)
        let accent = Color.moduleColor(for: selectedSport)
        let label: String = {
            switch selectedSport {
            case .striking:    return "Strike Velocity (mph)"
            case .grappling:   return "Kuzushi Index"
            case .ironTracker: return "Bar Velocity (m/s)"
            case .wallBeta:    return "Hip Proximity (%)"
            }
        }()

        return VStack(alignment: .leading, spacing: 12) {
            sectionHeader("RECENT TREND", subtitle: label)

            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.kineticsDark)

                if data.count < 2 {
                    Text("Not enough data yet")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.kineticsSubtext)
                        .padding()
                } else {
                    SparklineCanvas(data: data, accent: accent)
                        .padding(16)
                }
            }
            .frame(height: 120)
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Heatmap

    private var heatmapSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("TRAINING FREQUENCY", subtitle: "All sports · Last 52 weeks")

            VStack(alignment: .leading, spacing: 6) {
                monthLabelsRow
                ScrollView(.horizontal, showsIndicators: false) {
                    HeatmapGrid(data: vm.heatmapData())
                }
            }
            .padding(16)
            .background(Color.kineticsDark, in: RoundedRectangle(cornerRadius: 16))
        }
        .padding(.horizontal, 20)
    }

    private var monthLabelsRow: some View {
        let months = abbreviatedMonthLabels()
        return HStack(spacing: 0) {
            // Day-label gutter
            Text("   ")
                .font(.system(size: 9))
            ForEach(months.indices, id: \.self) { idx in
                Text(months[idx])
                    .font(.system(size: 9))
                    .foregroundStyle(Color.kineticsSubtext)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// Builds ~12 abbreviated month labels spread across 52 weeks.
    private func abbreviatedMonthLabels() -> [String] {
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: Date())
        guard let anchor = calendar.date(
            byAdding: .day, value: -(weekday - 1), to: calendar.startOfDay(for: Date())
        ) else { return [] }

        var labels: [String] = []
        var lastMonth = -1
        for week in 0..<52 {
            let offset = week * 7 - (52 * 7 - 7)
            guard let date = calendar.date(
                byAdding: .day, value: offset, to: anchor
            ) else { labels.append(""); continue }
            let month = calendar.component(.month, from: date)
            if month != lastMonth {
                let fmt = DateFormatter()
                fmt.dateFormat = "MMM"
                labels.append(fmt.string(from: date))
                lastMonth = month
            } else {
                labels.append("")
            }
        }
        return labels
    }

    // MARK: - Personal Records

    private var personalRecordsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("PERSONAL RECORDS", subtitle: "All-time best per sport")

            VStack(spacing: 10) {
                ForEach(SportType.allCases, id: \.self) { sport in
                    PersonalRecordRow(
                        sport: sport,
                        best: vm.personalBest(for: sport)
                    )
                }
            }
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Volume Breakdown

    private var volumeBreakdownSection: some View {
        let counts = SportType.allCases.map { (sport: $0, count: vm.totalSessions(for: $0)) }
        let maxCount = counts.map(\.count).max() ?? 1

        return VStack(alignment: .leading, spacing: 12) {
            sectionHeader("VOLUME BREAKDOWN", subtitle: "Sessions per sport")

            VStack(spacing: 10) {
                ForEach(counts, id: \.sport) { item in
                    VolumeBar(
                        sport: item.sport,
                        count: item.count,
                        maxCount: max(maxCount, 1)
                    )
                }
            }
            .padding(16)
            .background(Color.kineticsDark, in: RoundedRectangle(cornerRadius: 16))
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Helpers

    @ViewBuilder
    private func sectionHeader(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .tracking(2)
                .foregroundStyle(Color.kineticsSubtext)
            Text(subtitle)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.6))
        }
    }
}

// MARK: - SparklineCanvas

private struct SparklineCanvas: View {

    let data: [Double]
    let accent: Color

    var body: some View {
        VStack(spacing: 6) {
            Canvas { ctx, size in
                guard data.count >= 2 else { return }
                let minVal = data.min() ?? 0
                let maxVal = data.max() ?? 1
                let range = max(maxVal - minVal, 0.01)

                let points = data.enumerated().map { i, v -> CGPoint in
                    CGPoint(
                        x: size.width * CGFloat(i) / CGFloat(data.count - 1),
                        y: size.height * (1 - CGFloat((v - minVal) / range))
                    )
                }

                // Area fill
                var fillPath = Path()
                fillPath.move(to: CGPoint(x: 0, y: size.height))
                points.forEach { fillPath.addLine(to: $0) }
                fillPath.addLine(to: CGPoint(x: size.width, y: size.height))
                fillPath.closeSubpath()
                ctx.fill(fillPath, with: .linearGradient(
                    Gradient(colors: [accent.opacity(0.3), accent.opacity(0.0)]),
                    startPoint: .zero,
                    endPoint: CGPoint(x: 0, y: size.height)
                ))

                // Line
                var linePath = Path()
                linePath.move(to: points[0])
                points.dropFirst().forEach { linePath.addLine(to: $0) }
                ctx.stroke(linePath, with: .color(accent), lineWidth: 2)

                // Dots
                points.forEach { pt in
                    ctx.fill(
                        Circle().path(in: CGRect(
                            x: pt.x - 3, y: pt.y - 3, width: 6, height: 6
                        )),
                        with: .color(accent)
                    )
                }
            }
            .frame(height: 80)

            // X-axis labels
            HStack {
                ForEach(data.indices, id: \.self) { i in
                    Text("\(i + 1)")
                        .font(.system(size: 9))
                        .foregroundStyle(Color.kineticsSubtext)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }
}

// MARK: - HeatmapGrid

private struct HeatmapGrid: View {

    let data: [[Int]]

    private let cellSize: CGFloat = 9
    private let gap: CGFloat = 2
    private let dayLabels = ["S", "M", "T", "W", "T", "F", "S"]

    var body: some View {
        HStack(alignment: .top, spacing: gap) {
            // Day labels column
            VStack(spacing: gap) {
                ForEach(dayLabels.indices, id: \.self) { idx in
                    let show = idx == 1 || idx == 3 || idx == 5
                    Text(show ? dayLabels[idx] : "")
                        .font(.system(size: 8))
                        .foregroundStyle(Color.kineticsSubtext)
                        .frame(width: cellSize, height: cellSize)
                }
            }

            // 52 week columns
            ForEach(data.indices, id: \.self) { weekIdx in
                VStack(spacing: gap) {
                    ForEach(0..<7, id: \.self) { dayIdx in
                        let count = weekIdx < data.count && dayIdx < data[weekIdx].count
                            ? data[weekIdx][dayIdx] : 0
                        RoundedRectangle(cornerRadius: 2)
                            .fill(cellColor(count: count))
                            .frame(width: cellSize, height: cellSize)
                    }
                }
            }
        }
    }

    private func cellColor(count: Int) -> Color {
        switch count {
        case 0:    return Color.kineticsMidGray
        case 1:    return Color.kineticsBlue.opacity(0.4)
        case 2:    return Color.kineticsBlue.opacity(0.7)
        default:   return Color.kineticsBlue.opacity(1.0)
        }
    }
}

// MARK: - PerformanceStatCard

struct PerformanceStatCard: View {

    let title: String
    let value: String
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .tracking(1.5)
                .foregroundStyle(Color.kineticsSubtext)
            Text(value)
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.kineticsDark, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(accent.opacity(0.25), lineWidth: 1)
        )
    }
}

// MARK: - PersonalRecordRow

private struct PersonalRecordRow: View {

    let sport: SportType
    let best: (value: Double, label: String, date: Date)?

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: sport.systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.moduleColor(for: sport))
                .frame(width: 36, height: 36)
                .background(
                    Color.moduleColor(for: sport).opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 10)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(sport.displayName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
                if let best {
                    Text(best.date.formatted(date: .abbreviated, time: .omitted))
                        .font(.system(size: 11))
                        .foregroundStyle(Color.kineticsSubtext)
                } else {
                    Text("No sessions yet")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.kineticsSubtext)
                }
            }

            Spacer()

            if let best {
                VStack(alignment: .trailing, spacing: 1) {
                    Text(String(format: "%.1f", best.value))
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(Color.moduleColor(for: sport))
                    Text(best.label)
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(0.5)
                        .foregroundStyle(Color.kineticsSubtext)
                }
            } else {
                Text("—")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(Color.kineticsSubtext)
            }
        }
        .padding(14)
        .background(Color.kineticsDark, in: RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - VolumeBar

private struct VolumeBar: View {

    let sport: SportType
    let count: Int
    let maxCount: Int

    private var proportion: CGFloat {
        guard maxCount > 0 else { return 0 }
        return CGFloat(count) / CGFloat(maxCount)
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: sport.systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.moduleColor(for: sport))
                .frame(width: 20)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.kineticsMidGray)
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.moduleColor(for: sport))
                        .frame(width: max(geo.size.width * proportion, count > 0 ? 6 : 0))
                }
            }
            .frame(height: 10)

            Text("\(count)")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 28, alignment: .trailing)
        }
    }
}

// MARK: - Preview

#Preview {
    TrainPerformanceView()
        .environment(AppState.preview)
}
