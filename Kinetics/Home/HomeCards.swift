import SwiftUI

// MARK: - HomeReadinessCard

/// Hero card: readiness score, HealthKit stats, and weekly progress rings.
struct HomeReadinessCard: View {

    let vm: HomeViewModel

    var body: some View {
        ZStack(alignment: .topLeading) {
            backgroundLayers
            content
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.kineticsBlue.opacity(0.18), lineWidth: 0.75)
        )
        .frame(minHeight: 200)
    }

    // MARK: - Background

    private var backgroundLayers: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.04, green: 0.08, blue: 0.18),
                            Color(red: 0.04, green: 0.04, blue: 0.10)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            RadialGradient(
                colors: [Color.kineticsBlue.opacity(0.15), .clear],
                center: .topTrailing,
                startRadius: 0,
                endRadius: 180
            )
        }
    }

    // MARK: - Content

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 0) {
                scoreColumn
                    .frame(maxWidth: .infinity * 0.6, alignment: .leading)
                Spacer(minLength: 12)
                ringsColumn
            }
            .padding(.horizontal, 18)
            .padding(.top, 18)

            Divider()
                .background(.white.opacity(0.08))
                .padding(.horizontal, 18)
                .padding(.vertical, 12)

            miniStatsRow
                .padding(.horizontal, 18)

            bottomRow
                .padding(.horizontal, 18)
                .padding(.top, 10)
                .padding(.bottom, 16)
        }
    }

    // MARK: - Score Column

    private var scoreColumn: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("READINESS")
                .font(.system(size: 8, weight: .semibold))
                .tracking(2.0)
                .foregroundStyle(.white.opacity(0.40))

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(vm.readinessScore)")
                    .font(.system(size: 52, weight: .black, design: .rounded))
                    .foregroundStyle(vm.readinessColor)
                Text("/100")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.30))
                    .padding(.bottom, 4)
            }

            Text(vm.readinessLabel)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white.opacity(0.75))
        }
    }

    // MARK: - Rings Column

    private var ringsColumn: some View {
        let sP = min(Double(vm.weeklySessionCount) / 5.0, 1.0)
        let mP = min(vm.weeklyMinutes / 150.0, 1.0)
        return VStack(spacing: 4) {
            ZStack {
                // Outer ring track (sessions)
                Circle()
                    .stroke(.white.opacity(0.08), lineWidth: 7)
                    .frame(width: 76, height: 76)

                // Outer ring fill (sessions, blue)
                Circle()
                    .trim(from: 0, to: sP)
                    .stroke(
                        LinearGradient(
                            colors: [Color.kineticsBlue, Color.kineticsBlue.opacity(0.6)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        style: StrokeStyle(lineWidth: 7, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .frame(width: 76, height: 76)
                    .animation(.spring(response: 0.6, dampingFraction: 0.8), value: sP)

                Circle()
                    .stroke(.white.opacity(0.08), lineWidth: 5)
                    .frame(width: 56, height: 56)

                Circle()
                    .trim(from: 0, to: mP)
                    .stroke(
                        LinearGradient(
                            colors: [Color.kineticsGreen, Color.kineticsGreen.opacity(0.6)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        style: StrokeStyle(lineWidth: 5, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .frame(width: 56, height: 56)
                    .animation(.spring(response: 0.6, dampingFraction: 0.8), value: mP)

                // Centre text
                VStack(spacing: 1) {
                    Text("\(vm.weeklySessionCount)")
                        .font(.system(size: 15, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                    Text("/5")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.38))
                }
            }

            Text("WEEKLY GOAL")
                .font(.system(size: 8, weight: .semibold))
                .tracking(1.5)
                .foregroundStyle(.white.opacity(0.40))
        }
    }

    // MARK: - Mini Stats Row

    private var miniStatsRow: some View {
        HStack(spacing: 12) {
            miniStatItem(
                icon: "figure.run",
                color: .kineticsBlue,
                value: vm.dashboardStats.steps > 0
                    ? HomeReadinessCard.formattedSteps(vm.dashboardStats.steps) : "--"
            )
            miniStatItem(
                icon: "flame.fill",
                color: .kineticsAmber,
                value: vm.dashboardStats.activeCalories > 0
                    ? String(Int(vm.dashboardStats.activeCalories)) : "--"
            )
            miniStatItem(
                icon: "heart.fill",
                color: .kineticsGreen,
                value: vm.dashboardStats.restingHeartRate > 0
                    ? "\(Int(vm.dashboardStats.restingHeartRate)) bpm" : "--"
            )
        }
    }

    private func miniStatItem(icon: String, color: Color, value: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(color)
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.80))
        }
    }

    // MARK: - Bottom Row

    private var bottomRow: some View {
        HStack(spacing: 6) {
            Text("Updated just now")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.25))

            if vm.dashboardStats.restingHeartRate > 0 {
                Text("·")
                    .foregroundStyle(.white.opacity(0.20))
                    .font(.system(size: 10))
                Text("HealthKit")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.25))
            }

            Spacer()
        }
    }

    // MARK: - Helpers

    private static func formattedSteps(_ steps: Int) -> String {
        let fmt = NumberFormatter()
        fmt.numberStyle = .decimal
        return fmt.string(from: NSNumber(value: steps)) ?? "\(steps)"
    }
}

// MARK: - HomeCoachInsightCard

/// Coaching card: sport-colour left border, metric, trend arrow, advice copy.
struct HomeCoachInsightCard: View {

    let insight: HomeCoachInsight?

    var body: some View {
        if let insight {
            filledCard(insight)
        } else {
            emptyCard
        }
    }

    // MARK: - Empty State

    private var emptyCard: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.kineticsPurple.opacity(0.14))
                    .frame(width: 40, height: 40)
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.kineticsPurple)
            }
            Text("Complete your first session to unlock AI coaching.")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(.white.opacity(0.55))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(white: 0.08))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.white.opacity(0.07), lineWidth: 0.5)
        )
    }

    // MARK: - Filled Card

    private func filledCard(_ ins: HomeCoachInsight) -> some View {
        let accent = Color(hex: ins.accentColorHex)
        return ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(white: 0.08))
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.white.opacity(0.07), lineWidth: 0.5)

            // Left colour strip
            HStack(spacing: 0) {
                LinearGradient(
                    colors: [accent, accent.opacity(0.4)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(width: 4)
                .clipShape(
                    UnevenRoundedRectangle(
                        topLeadingRadius: 16,
                        bottomLeadingRadius: 16
                    )
                )
                Spacer()
            }

            VStack(alignment: .leading, spacing: 10) {
                // Header row
                HStack(spacing: 8) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(accent.opacity(0.14))
                            .frame(width: 30, height: 30)
                        Image(systemName: ins.systemImage)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(accent)
                    }
                    Text("AI COACH")
                        .font(.system(size: 8, weight: .semibold))
                        .tracking(1.8)
                        .foregroundStyle(.white.opacity(0.40))
                    Spacer()
                    Text(ins.sportName)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(accent.opacity(0.85))
                }

                // Metric + trend
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(ins.metricValue)
                        .font(.system(size: 34, weight: .black, design: .rounded))
                        .foregroundStyle(accent)
                    Text(ins.metricLabel)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.50))
                        .padding(.bottom, 2)
                    Spacer()
                    Image(systemName: ins.trendUp ? "chevron.up" : "chevron.down")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(ins.trendUp ? Color.kineticsGreen : Color.kineticsRed)
                }

                // Headline comparison
                Text(ins.headline)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.white.opacity(0.65))

                // Advice detail
                Text(ins.detail)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.white.opacity(0.70))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxHeight: 52)

                // CTA
                Button(action: {}) {
                    Text("Practice this →")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(accent)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(accent.opacity(0.12))
                        .clipShape(Capsule())
                        .overlay(
                            Capsule()
                                .strokeBorder(accent.opacity(0.30), lineWidth: 0.5)
                        )
                }
            }
            .padding(.leading, 20)
            .padding(.trailing, 16)
            .padding(.vertical, 14)
        }
        .frame(minHeight: 160)
    }
}

// MARK: - HomeQuickLaunchCard

/// Compact quick-launch sport card: gradient, ghost icon, badge, metric + trend.
struct HomeQuickLaunchCard: View {

    let sport: SportType
    let lastSession: SessionResult?
    let bestMetricValue: Double?
    let bestMetricLabel: String?
    let trend: MetricTrend

    private var accent: Color { Color.moduleColor(for: sport) }

    private var relativeTime: String {
        guard let session = lastSession else { return "Never" }
        let interval = Date().timeIntervalSince(session.startedAt)
        let days = Int(interval / 86_400)
        if days == 0 { return "Today" }
        if days == 1 { return "Yesterday" }
        return "\(days) days ago"
    }

    private var trendIcon: String {
        switch trend {
        case .up:   return "chevron.up"
        case .down: return "chevron.down"
        case .flat: return "minus"
        }
    }

    private var trendColor: Color {
        switch trend {
        case .up:   return .kineticsGreen
        case .down: return .kineticsRed
        case .flat: return .white.opacity(0.40)
        }
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.kineticsDark)
            Image(systemName: sport.systemImage)
                .font(.system(size: 62, weight: .black))
                .foregroundStyle(accent.opacity(0.10))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(.top, 8).padding(.trailing, 8)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            LinearGradient(
                colors: [.clear, accent.opacity(0.26)],
                startPoint: .top,
                endPoint: .bottom
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(accent.opacity(0.22), lineWidth: 0.75)

            VStack(alignment: .leading, spacing: 4) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(accent.opacity(0.18))
                        .frame(width: 36, height: 36)
                    Image(systemName: sport.systemImage)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(accent)
                }

                Spacer()

                Text(sport.displayName)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Text(relativeTime)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(.white.opacity(0.42))

                if let val = bestMetricValue, let unit = bestMetricLabel {
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text(String(format: "%.1f", val))
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(accent)
                        Text(unit)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.white.opacity(0.40))
                        Image(systemName: trendIcon)
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(trendColor)
                    }
                }
            }
            .padding(12)
        }
        .frame(width: 138, height: 178)
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

// MARK: - HomeActivityRow

/// Recent Activity row: badge, sport name, date, top metric, duration, PR flag.
struct HomeActivityRow: View {

    let session: SessionResult
    let isPR: Bool

    private var accent: Color { Color.moduleColor(for: session.sport) }

    private var relativeDate: String {
        let interval = Date().timeIntervalSince(session.startedAt)
        let days = Int(interval / 86_400)
        if days == 0 { return "Today" }
        if days == 1 { return "Yesterday" }
        return "\(days) days ago"
    }

    private var topMetric: String {
        if let v = session.metrics["strikeVelocityMPH"] {
            return String(format: "%.1f mph", v)
        }
        if let v = session.metrics["barVelocityMS"] {
            return String(format: "%.2f m/s", v)
        }
        if let v = session.metrics["hipProximityScore"] {
            return String(format: "%.0f%% prox", v * 100)
        }
        if let v = session.metrics["barPathDeviationCM"] {
            return String(format: "%.1f cm dev", v)
        }
        return session.formattedDuration
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(accent.opacity(0.14))
                    .frame(width: 40, height: 40)
                Image(systemName: session.sport.systemImage)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(accent)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(session.sport.displayName)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                Text(relativeDate)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(.white.opacity(0.40))
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(topMetric)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.kineticsGreen)

                Text(session.formattedDuration)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(.white.opacity(0.40))

                if isPR {
                    Text("PR")
                        .font(.system(size: 6, weight: .bold))
                        .foregroundStyle(Color.kineticsAmber)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.kineticsAmber.opacity(0.15))
                        .clipShape(Capsule())
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

// MARK: - HomeMilestoneCard

/// Full-width card showing the user's next milestone target with an animated
/// progress bar and session counter.
struct HomeMilestoneCard: View {

    let milestone: HomeMilestoneData

    // MARK: Computed

    private var accent: Color { Color(hex: milestone.accentColorHex) }

    private var progress: Double {
        guard milestone.target > 0 else { return 0 }
        return min(Double(milestone.current) / Double(milestone.target), 1.0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(accent.opacity(0.14))
                        .frame(width: 32, height: 32)
                    Image(systemName: milestone.sportImage)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(accent)
                }
                Text("NEXT MILESTONE")
                    .font(.system(size: 8, weight: .semibold))
                    .tracking(1.8)
                    .foregroundStyle(.white.opacity(0.40))
                Spacer()
            }
            Text(milestone.title)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
            Text(milestone.description)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(.white.opacity(0.50))

            VStack(alignment: .trailing, spacing: 4) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(.white.opacity(0.08))
                            .frame(height: 6)
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [accent, accent.opacity(0.6)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: geo.size.width * progress, height: 6)
                            .animation(.spring(response: 0.5, dampingFraction: 0.8),
                                       value: progress)
                    }
                }
                .frame(height: 6)
                Text("\(milestone.current) / \(milestone.target) sessions")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(.white.opacity(0.40))
            }
        }
        .padding(16)
        .background(Color.kineticsDark)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(accent.opacity(0.18), lineWidth: 0.5)
        )
    }
}

// MARK: - HomeSocialPreviewCard

/// Community teaser card — visual only; navigation happens via the tab bar.
struct HomeSocialPreviewCard: View {

    var body: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(red: 0.07, green: 0.05, blue: 0.14))
            RadialGradient(
                colors: [Color.kineticsPurple.opacity(0.22), .clear],
                center: .leading,
                startRadius: 0,
                endRadius: 120
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.kineticsPurple.opacity(0.18), lineWidth: 0.5)

            HStack(spacing: 14) {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundStyle(Color.kineticsPurple.opacity(0.70))
                    .frame(width: 52)
                VStack(alignment: .leading, spacing: 4) {
                    Text("COMMUNITY")
                        .font(.system(size: 8, weight: .semibold))
                        .tracking(1.8)
                        .foregroundStyle(.white.opacity(0.40))
                    Text("See what's happening on the Feed")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                    Text("Athletes you follow are training →")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(.white.opacity(0.50))
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.25))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 18)
        }
        .frame(minHeight: 90)
        .onTapGesture {}
    }
}
