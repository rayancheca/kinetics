import SwiftUI

// MARK: - SportBentoCard

/// Square bento-grid card representing one sport module.
/// Full sport-color gradient background, large faded icon, stat pill.
struct SportBentoCard: View {

    let sport: SportType
    let sessionCount: Int
    let lastSessionDate: Date?
    let bestMetric: Double?
    let bestMetricLabel: String

    private var accent: Color { Color.moduleColor(for: sport) }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // Base card surface
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.kineticsDark)

            // Sport-color diagonal gradient wash
            LinearGradient(
                colors: [accent.opacity(0.15), .clear],
                startPoint: .bottomLeading,
                endPoint: .topTrailing
            )
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

            // Faded oversized icon — decorative only
            Image(systemName: sport.systemImage)
                .font(.system(size: 80, weight: .black))
                .foregroundStyle(accent.opacity(0.08))
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity,
                    alignment: .topTrailing
                )
                .padding(.top, 10)
                .padding(.trailing, 8)

            // Sport-color border
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(accent.opacity(0.2), lineWidth: 0.75)

            // Content stack pinned to bottom-leading
            VStack(alignment: .leading, spacing: 4) {
                Text(sport.displayName)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Text(sport.tagline)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.45))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer().frame(height: 6)

                statPill
            }
            .padding(14)
        }
        .frame(maxWidth: .infinity, minHeight: 170)
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    // MARK: - Stat Pill

    @ViewBuilder
    private var statPill: some View {
        if let metric = bestMetric {
            TrainStatPill(
                value: String(format: "%.1f", metric),
                label: bestMetricLabel,
                accent: accent
            )
        } else {
            TrainStatPill(
                value: "\(sessionCount)",
                label: sessionCount == 1 ? "session" : "sessions",
                accent: accent
            )
        }
    }
}

// MARK: - TrainWeeklyCalendarStrip

/// A 7-column Mon–Sun training calendar strip.
/// Dots fill in blue on trained days; today's column has a subtle white highlight.
struct TrainWeeklyCalendarStrip: View {

    /// Weekday integers using `Calendar.component(.weekday)` convention:
    /// 1 = Sunday, 2 = Monday … 7 = Saturday.
    let trainedDays: Set<Int>

    // Day labels Mon–Sun (indices 0–6 map to weekday 2–7, then 1)
    private let labels = ["M", "T", "W", "T", "F", "S", "S"]

    /// Calendar weekday integer for each column (Mon = 2 … Sat = 7, Sun = 1)
    private let columnWeekdays: [Int] = [2, 3, 4, 5, 6, 7, 1]

    private var todayWeekday: Int {
        Calendar.current.component(.weekday, from: Date())
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<7, id: \.self) { index in
                let weekday = columnWeekdays[index]
                let isToday = weekday == todayWeekday
                let isTrained = trainedDays.contains(weekday)

                dayColumn(
                    label: labels[index],
                    isTrained: isTrained,
                    isToday: isToday
                )
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 44)
    }

    // MARK: - Day Column

    private func dayColumn(
        label: String,
        isTrained: Bool,
        isToday: Bool
    ) -> some View {
        VStack(spacing: 5) {
            Text(label)
                .font(.system(size: 11, weight: isToday ? .semibold : .regular))
                .foregroundStyle(isToday ? .white : .white.opacity(0.45))

            Circle()
                .fill(
                    isTrained
                        ? Color.kineticsBlue
                        : Color.white.opacity(0.20)
                )
                .frame(width: 7, height: 7)
                .overlay(
                    Circle()
                        .strokeBorder(
                            isToday ? Color.kineticsBlue : .clear,
                            lineWidth: 1.5
                        )
                        .frame(width: 11, height: 11)
                )
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 2)
        .background(
            isToday
                ? Color.white.opacity(0.07)
                : Color.clear
        )
        .clipShape(Capsule())
    }
}

// MARK: - TrainRecommendationCard

/// Full-width AI coach recommendation card with a sport-color left border and glow.
struct TrainRecommendationCard: View {

    let sport: SportType
    let reason: String

    private var accent: Color { Color.moduleColor(for: sport) }

    var body: some View {
        ZStack(alignment: .leading) {
            // Base surface
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.kineticsDark)

            // Top-left sport-color radial glow
            RadialGradient(
                colors: [accent.opacity(0.14), .clear],
                center: .topLeading,
                startRadius: 0,
                endRadius: 120
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            // Left accent border
            HStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(accent)
                    .frame(width: 3)
                    .padding(.vertical, 14)

                Spacer()
            }

            // Content row
            HStack(alignment: .center, spacing: 14) {
                // Left: badge + name + reason
                VStack(alignment: .leading, spacing: 6) {
                    // "AI COACH" badge
                    Text("AI COACH")
                        .font(.system(size: 8, weight: .bold))
                        .tracking(8)
                        .foregroundStyle(accent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(accent.opacity(0.12))
                        .clipShape(Capsule())
                        .overlay(
                            Capsule()
                                .strokeBorder(accent.opacity(0.3), lineWidth: 0.5)
                        )

                    Text(sport.displayName)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)

                    Text(reason)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.kineticsSubtext)
                        .fixedSize(horizontal: false, vertical: true)

                    // CTA capsule
                    HStack(spacing: 4) {
                        Text("START NOW")
                            .font(.system(size: 10, weight: .bold))
                            .tracking(1.5)
                        Text("→")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .foregroundStyle(accent)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(accent.opacity(0.12))
                    .clipShape(Capsule())
                    .overlay(
                        Capsule()
                            .strokeBorder(accent.opacity(0.28), lineWidth: 0.5)
                    )
                    .padding(.top, 2)
                }
                .padding(.leading, 14)

                Spacer(minLength: 8)

                // Right: large sport icon
                Image(systemName: sport.systemImage)
                    .font(.system(size: 48, weight: .semibold))
                    .foregroundStyle(accent)
                    .padding(.trailing, 16)
            }
            .padding(.vertical, 16)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 110)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(accent.opacity(0.18), lineWidth: 0.75)
        )
    }
}

// MARK: - TrainStreakHeader

/// Header row showing the "TRAIN" wordmark left and a streak ring right.
struct TrainStreakHeader: View {

    let streak: Int
    let subtitle: String

    var body: some View {
        HStack(alignment: .center) {
            // Left: title + subtitle
            VStack(alignment: .leading, spacing: 4) {
                Text("TRAIN")
                    .font(.system(size: 32, weight: .black))
                    .tracking(6)
                    .foregroundStyle(.white)

                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.38))
            }

            Spacer()

            // Right: streak indicator — only shown when streak > 0
            if streak > 0 {
                streakRing
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 60)
    }

    // MARK: - Streak Ring

    private var streakRing: some View {
        VStack(spacing: 2) {
            ZStack {
                // Ring track
                Circle()
                    .stroke(Color.kineticsBlue.opacity(0.20), lineWidth: 3)
                    .frame(width: 44, height: 44)

                // Ring progress (fixed visual — streak is contextual)
                Circle()
                    .trim(from: 0, to: min(Double(streak) / 7.0, 1.0))
                    .stroke(
                        Color.kineticsBlue,
                        style: StrokeStyle(
                            lineWidth: 3,
                            lineCap: .round
                        )
                    )
                    .rotationEffect(.degrees(-90))
                    .frame(width: 44, height: 44)

                // Streak number
                Text("\(streak)")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
            }

            Text("day streak")
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.50))
        }
    }
}

// MARK: - TrainStatPill

/// Compact two-part pill: accented value on the left, muted label on the right.
struct TrainStatPill: View {

    let value: String
    let label: String
    let accent: Color

    var body: some View {
        HStack(spacing: 5) {
            Text(value)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(accent)

            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.50))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(accent.opacity(0.10))
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .strokeBorder(accent.opacity(0.25), lineWidth: 0.5)
        )
    }
}

// MARK: - Previews

#if DEBUG
#Preview("SportBentoCard — with metric") {
    HStack(spacing: 12) {
        SportBentoCard(
            sport: .striking,
            sessionCount: 12,
            lastSessionDate: Date(),
            bestMetric: 34.7,
            bestMetricLabel: "mph"
        )
        SportBentoCard(
            sport: .wallBeta,
            sessionCount: 0,
            lastSessionDate: nil,
            bestMetric: nil,
            bestMetricLabel: "sessions"
        )
    }
    .padding()
    .background(Color.kineticsBackground)
}

#Preview("TrainWeeklyCalendarStrip") {
    TrainWeeklyCalendarStrip(trainedDays: [2, 4, 6])
        .padding()
        .background(Color.kineticsBackground)
}

#Preview("TrainRecommendationCard") {
    TrainRecommendationCard(
        sport: .grappling,
        reason: "No grappling sessions in 4 days"
    )
    .padding()
    .background(Color.kineticsBackground)
}

#Preview("TrainStreakHeader") {
    VStack(spacing: 24) {
        TrainStreakHeader(streak: 5, subtitle: "Good evening, it's Thursday")
        TrainStreakHeader(streak: 0, subtitle: "Start your first session today")
    }
    .padding()
    .background(Color.kineticsBackground)
}

#Preview("TrainStatPill") {
    HStack(spacing: 8) {
        TrainStatPill(value: "34.7", label: "mph", accent: .kineticsRed)
        TrainStatPill(value: "12", label: "sessions", accent: .kineticsBlue)
        TrainStatPill(value: "0.92", label: "symmetry", accent: .kineticsGreen)
    }
    .padding()
    .background(Color.kineticsBackground)
}
#endif
