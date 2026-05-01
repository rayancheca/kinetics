import SwiftUI

// MARK: - TrendDirection

enum TrendDirection { case up, down, flat }

// MARK: - SportDetailViewModel

@Observable
@MainActor
final class SportDetailViewModel {

    let sport: SportType
    let sessions: [SessionResult]

    // MARK: Computed — Counts

    var totalSessions: Int { sessions.count }

    var lastSession: SessionResult? { sessions.first }

    var lastSessionDaysAgo: Int {
        guard let last = lastSession else { return 0 }
        let days = Calendar.current.dateComponents(
            [.day], from: last.startedAt, to: Date()
        ).day ?? 0
        return max(0, days)
    }

    // MARK: Computed — Metrics

    private var primaryMetricKey: String {
        switch sport {
        case .striking:    "strikeVelocityMPH"
        case .grappling:   "kuzushiIndex"
        case .ironTracker: "barVelocityMS"
        case .wallBeta:    "hipProximityScore"
        }
    }

    var primaryMetricLabel: String {
        switch sport {
        case .striking:    "mph"
        case .grappling:   "kuzushi"
        case .ironTracker: "m/s"
        case .wallBeta:    "prox%"
        }
    }

    var primaryMetricValue: Double? {
        lastSession?.metrics[primaryMetricKey]
    }

    var personalBest: Double? {
        sessions.compactMap { $0.metrics[primaryMetricKey] }.max()
    }

    // MARK: Computed — Coach Tip

    var lastCoachingNote: CoachingNote? { lastSession?.coachingNotes.first }

    // MARK: Computed — Trend

    var recentTrend: [Double] {
        sessions
            .suffix(5)
            .reversed()
            .compactMap { $0.metrics[primaryMetricKey] }
    }

    var trendDirection: TrendDirection {
        guard recentTrend.count >= 2,
              let first = recentTrend.first,
              let last = recentTrend.last else { return .flat }
        let delta = last - first
        if delta > 0.5 { return .up }
        if delta < -0.5 { return .down }
        return .flat
    }

    // MARK: Init

    init(sport: SportType, sessions: [SessionResult]) {
        self.sport = sport
        self.sessions = sessions
    }
}

// MARK: - SportDetailView

struct SportDetailView: View {

    let sport: SportType
    let sessions: [SessionResult]

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var showLiveSession = false
    @State private var vm: SportDetailViewModel

    init(sport: SportType, sessions: [SessionResult]) {
        self.sport = sport
        self.sessions = sessions
        _vm = State(wrappedValue: SportDetailViewModel(sport: sport, sessions: sessions))
    }

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.kineticsBackground.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    heroSection
                    contentSection
                        .padding(.bottom, 120)
                }
            }

            bottomCTA
        }
        .navigationTitle(sport.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .fullScreenCover(isPresented: $showLiveSession) {
            moduleView(for: sport)
                .environment(appState)
        }
    }

    // MARK: - Hero Section

    private var heroSection: some View {
        ZStack(alignment: .bottom) {
            // Base
            Color.kineticsDark

            // Diagonal gradient from sport color (bottom-left) to clear (top-right)
            LinearGradient(
                colors: [accent.opacity(0.30), Color.clear],
                startPoint: .bottomLeading,
                endPoint: .topTrailing
            )

            // Radial glow top-right
            RadialGradient(
                colors: [accent.opacity(0.22), Color.clear],
                center: .topTrailing,
                startRadius: 0,
                endRadius: 200
            )

            // Large background icon
            Image(systemName: sport.systemImage)
                .font(.system(size: 90, weight: .black))
                .foregroundStyle(accent.opacity(0.10))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(.top, 20)
                .padding(.trailing, 16)

            // Bottom-aligned content
            VStack(alignment: .leading, spacing: 8) {
                // Sport name badge
                Text(sport.displayName.uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(2.5)
                    .foregroundStyle(accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(accent.opacity(0.15), in: Capsule())

                // Big sport name
                Text(sport.displayName)
                    .font(.system(size: 28, weight: .black))
                    .foregroundStyle(.white)

                // Tagline
                Text(sport.tagline)
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.50))

                // Stats row
                HStack(spacing: 8) {
                    heroPill("\(vm.totalSessions) sessions")
                    if vm.totalSessions > 0 {
                        heroPill(lastSessionLabel)
                    } else {
                        heroPill("First session!")
                    }
                }
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .frame(height: 240)
        .clipShape(RoundedRectangle(cornerRadius: 0))
        .overlay(
            Rectangle()
                .strokeBorder(accent.opacity(0.25), lineWidth: 0.75)
        )
    }

    private func heroPill(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(accent)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(accent.opacity(0.12), in: Capsule())
    }

    private var lastSessionLabel: String {
        let days = vm.lastSessionDaysAgo
        switch days {
        case 0: return "Last: today"
        case 1: return "Last: yesterday"
        default: return "Last: \(days)d ago"
        }
    }

    // MARK: - Content Section

    private var contentSection: some View {
        VStack(spacing: 16) {
            if let pb = vm.personalBest {
                personalBestCard(pb)
            }

            if let last = vm.lastSession {
                lastSessionCard(last)
            }

            if vm.recentTrend.count >= 3 {
                trendCard
            }

            if let note = vm.lastCoachingNote {
                coachTipCard(note)
            }

            sportTipsCard
        }
        .padding(.horizontal, 16)
        .padding(.top, 20)
    }

    // MARK: - Personal Best Card

    private func personalBestCard(_ value: Double) -> some View {
        HStack(spacing: 12) {
            accent
                .frame(width: 3)
                .clipShape(Capsule())

            VStack(alignment: .leading, spacing: 4) {
                Text("PERSONAL BEST")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(2)
                    .foregroundStyle(accent)

                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(formatted(value))
                        .font(.system(size: 36, weight: .black))
                        .foregroundStyle(.white)
                    Text(vm.primaryMetricLabel)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.kineticsSubtext)
                }
            }
            Spacer(minLength: 0)

            Image(systemName: "trophy.fill")
                .font(.system(size: 22))
                .foregroundStyle(Color.kineticsAmber)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .background(Color.kineticsDark)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(accent.opacity(0.20), lineWidth: 0.75)
        )
    }

    // MARK: - Last Session Card

    private func lastSessionCard(_ session: SessionResult) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("LAST SESSION")

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.formattedDate)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white)
                    Text(session.formattedDuration)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.kineticsSubtext)
                }
                Spacer(minLength: 0)

                if let val = session.metrics[primaryMetricKey] {
                    VStack(alignment: .trailing, spacing: 2) {
                        HStack(alignment: .firstTextBaseline, spacing: 3) {
                            Text(formatted(val))
                                .font(.system(size: 22, weight: .bold))
                                .foregroundStyle(.white)
                            Text(vm.primaryMetricLabel)
                                .font(.system(size: 12))
                                .foregroundStyle(Color.kineticsSubtext)
                        }
                        if let pb = vm.personalBest, val >= pb {
                            Text("PB")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(Color.kineticsAmber)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.kineticsAmber.opacity(0.15), in: Capsule())
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(Color.kineticsDark)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.07), lineWidth: 0.75)
        )
    }

    // MARK: - Trend Card

    private var trendCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                sectionLabel("RECENT TREND")
                Spacer(minLength: 0)
                trendBadge
            }

            SparklineView(values: vm.recentTrend, accent: accent)
                .frame(height: 60)
        }
        .padding(16)
        .background(Color.kineticsDark)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.07), lineWidth: 0.75)
        )
    }

    private var trendBadge: some View {
        let (icon, color, label): (String, Color, String) = {
            switch vm.trendDirection {
            case .up:   return ("arrow.up.right", Color.kineticsGreen, "Improving")
            case .down: return ("arrow.down.right", Color.kineticsRed, "Declining")
            case .flat: return ("minus", Color.kineticsSubtext, "Steady")
            }
        }()
        return Label(label, systemImage: icon)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.12), in: Capsule())
    }

    // MARK: - Coach Tip Card

    private func coachTipCard(_ note: CoachingNote) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(accent.opacity(0.15))
                    .frame(width: 36, height: 36)
                Image(systemName: note.icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(accent)
            }

            VStack(alignment: .leading, spacing: 4) {
                sectionLabel("COACH TIP")
                Text(note.headline)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                Text(note.detail)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.kineticsSubtext)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .background(Color.kineticsDark)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(accent.opacity(0.18), lineWidth: 0.75)
        )
    }

    // MARK: - Sport Tips Card

    private var sportTipsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("TIPS")

            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(sportTips.enumerated()), id: \.offset) { _, tip in
                    HStack(alignment: .top, spacing: 10) {
                        Circle()
                            .fill(accent)
                            .frame(width: 5, height: 5)
                            .padding(.top, 6)
                        Text(tip)
                            .font(.system(size: 13))
                            .foregroundStyle(Color.kineticsSubtext)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(16)
        .background(Color.kineticsDark)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.07), lineWidth: 0.75)
        )
    }

    private var sportTips: [String] {
        switch sport {
        case .striking:
            return [
                "Rotate hips before shoulders to maximise kinetic chain transfer.",
                "Keep your stance width consistent — fast recovery means a stronger base.",
                "Aim for hip-to-shoulder separation above 40° for elite power output."
            ]
        case .grappling:
            return [
                "Break your opponent's posture (kuzushi) before committing to a throw.",
                "Keep your centre of mass inside your base at all times to avoid sweeps.",
                "Use hip elevation in guard — higher hips create sharper submission angles."
            ]
        case .ironTracker:
            return [
                "Chase a vertical bar path — any lateral deviation above 2 cm costs reps.",
                "Use VBT: aim for >0.8 m/s on working sets to train speed-strength.",
                "Monitor bilateral symmetry — a >10 % side difference signals a weak link."
            ]
        case .wallBeta:
            return [
                "Keep your hips close to the wall — it shifts load from arms to feet.",
                "Flagging one foot outward lowers your centre of mass for steep terrain.",
                "Time under tension reveals inefficiency; long pauses mean grip fatigue."
            ]
        }
    }

    // MARK: - Bottom CTA

    private var bottomCTA: some View {
        VStack(spacing: 10) {
            Button {
                showLiveSession = true
            } label: {
                Text("START SESSION")
                    .font(.system(size: 16, weight: .black))
                    .tracking(2)
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(accent, in: Capsule())
            }
            .buttonStyle(ScaleButtonStyle())
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 24)
        .padding(.top, 12)
        .background(.ultraThinMaterial)
    }

    // MARK: - Module Router

    @ViewBuilder private func moduleView(for sport: SportType) -> some View {
        switch sport {
        case .striking:    StrikingView()
        case .grappling:   GrapplingView()
        case .ironTracker: IronTrackerView()
        case .wallBeta:    WallBetaView()
        }
    }

    // MARK: - Helpers

    private var accent: Color { .moduleColor(for: sport) }

    private var primaryMetricKey: String {
        switch sport {
        case .striking:    "strikeVelocityMPH"
        case .grappling:   "kuzushiIndex"
        case .ironTracker: "barVelocityMS"
        case .wallBeta:    "hipProximityScore"
        }
    }

    private func formatted(_ value: Double) -> String {
        String(format: value < 10 ? "%.2f" : "%.1f", value)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .tracking(2)
            .foregroundStyle(Color.kineticsSubtext)
    }
}

// MARK: - SparklineView

private struct SparklineView: View {

    let values: [Double]
    let accent: Color

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            let points = normalizedPoints(width: width, height: height)

            Canvas { ctx, _ in
                guard points.count >= 2 else { return }

                // Shaded fill under the line
                var fillPath = Path()
                fillPath.move(to: CGPoint(x: points[0].x, y: height))
                for pt in points { fillPath.addLine(to: pt) }
                fillPath.addLine(to: CGPoint(x: points[points.count - 1].x, y: height))
                fillPath.closeSubpath()
                ctx.fill(
                    fillPath,
                    with: .linearGradient(
                        Gradient(colors: [accent.opacity(0.20), accent.opacity(0)]),
                        startPoint: CGPoint(x: width / 2, y: 0),
                        endPoint: CGPoint(x: width / 2, y: height)
                    )
                )

                // Line
                var linePath = Path()
                linePath.move(to: points[0])
                for pt in points.dropFirst() { linePath.addLine(to: pt) }
                ctx.stroke(
                    linePath,
                    with: .color(accent),
                    style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
                )

                // Dots
                for pt in points {
                    let dotRect = CGRect(
                        x: pt.x - 4, y: pt.y - 4, width: 8, height: 8
                    )
                    ctx.fill(Path(ellipseIn: dotRect), with: .color(accent))
                    ctx.fill(
                        Path(ellipseIn: dotRect.insetBy(dx: 2, dy: 2)),
                        with: .color(Color.kineticsDark)
                    )
                }
            }
        }
    }

    private func normalizedPoints(width: CGFloat, height: CGFloat) -> [CGPoint] {
        guard values.count >= 2,
              let minVal = values.min(),
              let maxVal = values.max() else { return [] }

        let range = maxVal - minVal
        let step = width / CGFloat(values.count - 1)
        let padding: CGFloat = 6

        return values.enumerated().map { idx, val in
            let x = CGFloat(idx) * step
            let normalized = range > 0 ? (val - minVal) / range : 0.5
            let y = height - padding - CGFloat(normalized) * (height - padding * 2)
            return CGPoint(x: x, y: y)
        }
    }
}
