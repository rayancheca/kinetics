import Charts
import CoreLocation
import MapKit
import SwiftUI

// MARK: - WorkoutSummaryView

/// Full-screen post-workout summary presented as a `.fullScreenCover` immediately
/// after `endWorkout()` completes and `showSummary` flips to `true`.
///
/// Mirrors the design language of `StrikingSessionReportView` — dark background,
/// Kinetics accent colors, same `sectionHeader` / `reportCard` helper vocabulary —
/// but is tailored for GPS workout data: route map, splits table, HR zone bar,
/// AI coaching notes, and an achievements ribbon.
@MainActor
struct WorkoutSummaryView: View {

    // MARK: - Inputs

    let workout: WorkoutResult

    // MARK: - Environment

    @Environment(\.dismiss) private var dismiss

    // MARK: - Computed Route

    private var routeCoordinates: [CLLocationCoordinate2D] {
        zip(workout.routeLatitudes, workout.routeLongitudes).map {
            CLLocationCoordinate2D(latitude: $0, longitude: $1)
        }
    }

    // MARK: - Activity Accent

    private var accent: Color { Color(hex: workout.activityType.accentColorHex) }

    // MARK: - Coaching Notes (rule-based)

    private var coachingNotes: [(icon: String, text: String)] {
        var notes: [(icon: String, text: String)] = []

        if workout.avgPaceSecondsPerKm > 0, workout.avgPaceSecondsPerKm < 300 {
            notes.append((
                icon: "bolt.fill",
                text: "Excellent pace — you're running sub-5 min/km consistently."
            ))
        }

        if workout.elevationGain > 100 {
            notes.append((
                icon: "mountain.2.fill",
                text: String(format: "Strong hill work — +%.0fm elevation shows excellent fitness.", workout.elevationGain)
            ))
        }

        if notes.isEmpty {
            notes.append((
                icon: "checkmark.seal.fill",
                text: "Great session. Stay consistent and your pace will keep improving."
            ))
        }

        return notes
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    titleBlock
                    routeMapCard
                    primaryMetricsBlock
                    secondaryMetricsBlock
                    hrZonesSection
                    splitsSection
                    achievementsSection
                    aiCoachingSection
                    doneButton
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 40)
            }
        }
    }

    // MARK: - Title Block

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            // "WORKOUT COMPLETE" badge
            HStack(spacing: 8) {
                Image(systemName: workout.activityType.systemImage)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(accent)

                Text("WORKOUT COMPLETE")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(2)
                    .foregroundStyle(accent)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(accent.opacity(0.12))
            .clipShape(Capsule())

            Text(workout.activityType.displayName.uppercased())
                .font(.system(size: 36, weight: .black))
                .foregroundStyle(.white)

            Text(workout.startedAt.formatted(date: .complete, time: .omitted))
                .font(.system(size: 15))
                .foregroundStyle(.white.opacity(0.45))
        }
    }

    // MARK: - Route Map

    private var routeMapCard: some View {
        Group {
            if routeCoordinates.count >= 2 {
                RouteMapView.routeSummary(coordinates: routeCoordinates)
                    .frame(height: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(.white.opacity(0.07), lineWidth: 0.5)
                    )
            } else {
                // No route recorded — show a placeholder tile
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.kineticsDark)
                    .frame(height: 220)
                    .overlay(
                        VStack(spacing: 8) {
                            Image(systemName: "map.fill")
                                .font(.system(size: 32))
                                .foregroundStyle(.white.opacity(0.2))
                            Text("No route recorded")
                                .font(.system(size: 14))
                                .foregroundStyle(.white.opacity(0.3))
                        }
                    )
            }
        }
    }

    // MARK: - Primary Metrics

    private var primaryMetricsBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("PRIMARY METRICS")

            HStack(spacing: 0) {
                primaryMetricCell(
                    value: workout.formattedDistance,
                    label: "Distance",
                    isFirst: true
                )
                Divider()
                    .frame(width: 0.5)
                    .background(.white.opacity(0.1))
                primaryMetricCell(
                    value: workout.formattedDuration,
                    label: "Time"
                )
                Divider()
                    .frame(width: 0.5)
                    .background(.white.opacity(0.1))
                primaryMetricCell(
                    value: workout.formattedAvgPace,
                    label: "Avg Pace",
                    isLast: true
                )
            }
            .frame(maxWidth: .infinity)
            .background(Color.kineticsDark)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(.white.opacity(0.07), lineWidth: 0.5)
            )
        }
    }

    private func primaryMetricCell(
        value: String,
        label: String,
        isFirst: Bool = false,
        isLast: Bool = false
    ) -> some View {
        VStack(alignment: .center, spacing: 4) {
            Text(value)
                .font(.system(size: 20, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .tracking(1)
                .foregroundStyle(.white.opacity(0.4))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
    }

    // MARK: - Secondary Metrics

    private var secondaryMetricsBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("SECONDARY METRICS")

            HStack(spacing: 12) {
                secondaryMetricCard(
                    icon: "heart.fill",
                    iconColor: Color.kineticsRed,
                    title: "Heart Rate",
                    value: workout.avgHeartRate > 0
                        ? String(format: "%.0f avg bpm", workout.avgHeartRate)
                        : "-- bpm"
                )
                secondaryMetricCard(
                    icon: "mountain.2.fill",
                    iconColor: Color.kineticsGreen,
                    title: "Elevation",
                    value: String(format: "+%.0fm gain", workout.elevationGain)
                )
                secondaryMetricCard(
                    icon: "flame.fill",
                    iconColor: Color.kineticsOrange,
                    title: "Calories",
                    value: String(format: "%.0f kcal", workout.calories)
                )
            }
        }
    }

    private func secondaryMetricCard(
        icon: String,
        iconColor: Color,
        title: String,
        value: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(iconColor)

            Text(title)
                .font(.system(size: 9, weight: .semibold))
                .tracking(1.5)
                .foregroundStyle(.white.opacity(0.38))

            Text(value)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .minimumScaleFactor(0.7)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.kineticsDark)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.white.opacity(0.07), lineWidth: 0.5)
        )
    }

    // MARK: - HR Zones

    private var hrZonesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("HEART RATE ZONES")

            HRZoneBar(zones: workout.hrZones)
                .reportCard()
        }
    }

    // MARK: - Splits

    private var splitsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("SPLITS")

            if workout.splits.isEmpty {
                Text("No splits recorded — session too short.")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.38))
                    .padding(.horizontal, 2)
            } else {
                SplitsTable(splits: workout.splits)
                    .reportCard()
            }
        }
    }

    // MARK: - Achievements

    @ViewBuilder
    private var achievementsSection: some View {
        if !workout.achievements.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                sectionHeader("ACHIEVEMENTS")

                VStack(spacing: 8) {
                    ForEach(workout.achievements, id: \.self) { achievement in
                        HStack(spacing: 10) {
                            Image(systemName: "trophy.fill")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Color(hex: "FFB800"))
                                .frame(width: 32, height: 32)
                                .background(Color(hex: "FFB800").opacity(0.12))
                                .clipShape(RoundedRectangle(cornerRadius: 8))

                            Text(achievement)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.white)

                            Spacer()
                        }
                        .padding(12)
                        .background(Color.kineticsDark)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(Color(hex: "FFB800").opacity(0.2), lineWidth: 0.5)
                        )
                    }
                }
            }
        }
    }

    // MARK: - AI Coaching

    private var aiCoachingSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("AI COACHING")

            VStack(spacing: 8) {
                ForEach(Array(coachingNotes.enumerated()), id: \.offset) { _, note in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: note.icon)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(accent)
                            .frame(width: 34, height: 34)
                            .background(accent.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 8))

                        Text(note.text)
                            .font(.system(size: 14))
                            .foregroundStyle(.white.opacity(0.75))
                            .fixedSize(horizontal: false, vertical: true)

                        Spacer()
                    }
                    .padding(14)
                    .background(Color.kineticsDark)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(.white.opacity(0.07), lineWidth: 0.5)
                    )
                }
            }
        }
    }

    // MARK: - Done Button

    private var doneButton: some View {
        let shareText = """
        Kinetics — \(workout.activityType.displayName) — \(workout.formattedDate)
        Distance: \(workout.formattedDistance)
        Time: \(workout.formattedDuration)
        Avg Pace: \(workout.formattedAvgPace)
        """

        return HStack(spacing: 12) {
            Button { dismiss() } label: {
                Text("Done")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(accent)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }

            ShareLink(item: shareText) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .background(Color(red: 0.12, green: 0.12, blue: 0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
        }
    }
}

// MARK: - HRZoneBar

/// Horizontal stacked bar showing the proportion of workout time in each of the
/// five HR zones, coloured from cool blue (Z1) through warm red (Z5).
struct HRZoneBar: View {

    let zones: HRZones

    // MARK: Zone Metadata

    private struct ZoneInfo {
        let label: String
        let color: Color
        let duration: TimeInterval
    }

    private func zoneInfos() -> [ZoneInfo] {
        [
            ZoneInfo(label: "Z1", color: Color(hex: "00C2FF"), duration: zones.zone1),
            ZoneInfo(label: "Z2", color: Color(hex: "39FF14"), duration: zones.zone2),
            ZoneInfo(label: "Z3", color: Color(hex: "FFD700"), duration: zones.zone3),
            ZoneInfo(label: "Z4", color: Color(hex: "FF8C00"), duration: zones.zone4),
            ZoneInfo(label: "Z5", color: Color(hex: "FF4444"), duration: zones.zone5),
        ]
    }

    var body: some View {
        let infos = zoneInfos()
        let total = zones.total

        VStack(alignment: .leading, spacing: 10) {
            if total > 0 {
                // Stacked proportion bar
                GeometryReader { geo in
                    HStack(spacing: 2) {
                        ForEach(infos, id: \.label) { zone in
                            if zone.duration > 0 {
                                let fraction = zone.duration / total
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(zone.color)
                                    .frame(width: geo.size.width * fraction - 2)
                            }
                        }
                    }
                }
                .frame(height: 10)
                .clipShape(RoundedRectangle(cornerRadius: 5))
            } else {
                // No HR data fallback
                RoundedRectangle(cornerRadius: 5)
                    .fill(.white.opacity(0.08))
                    .frame(maxWidth: .infinity)
                    .frame(height: 10)
            }

            // Zone legend row
            HStack {
                ForEach(infos, id: \.label) { zone in
                    VStack(spacing: 3) {
                        Circle()
                            .fill(zone.color)
                            .frame(width: 6, height: 6)

                        Text(zone.label)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.5))

                        if total > 0, zone.duration > 0 {
                            Text(String(format: "%.0f%%", zone.duration / total * 100))
                                .font(.system(size: 9, weight: .medium, design: .rounded))
                                .foregroundStyle(.white.opacity(0.7))
                        } else {
                            Text("--")
                                .font(.system(size: 9))
                                .foregroundStyle(.white.opacity(0.25))
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }
}

// MARK: - SplitsTable

/// Compact table rendering per-kilometre splits with columns for split number,
/// pace, and average heart rate.
struct SplitsTable: View {

    let splits: [WorkoutSplit]

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("KM")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("Pace")
                    .frame(width: 80, alignment: .center)
                Text("Avg HR")
                    .frame(width: 64, alignment: .trailing)
            }
            .font(.system(size: 9, weight: .semibold))
            .tracking(1.5)
            .foregroundStyle(.white.opacity(0.35))
            .padding(.bottom, 8)

            Divider()
                .background(.white.opacity(0.08))

            ForEach(splits) { split in
                HStack {
                    Text("\(split.splitNumber)")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text(formattedPace(split.pace))
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundStyle(paceColor(split.pace))
                        .frame(width: 80, alignment: .center)

                    Text(split.avgHeartRate > 0
                         ? String(format: "%.0f bpm", split.avgHeartRate)
                         : "--")
                        .font(.system(size: 13, design: .rounded))
                        .foregroundStyle(.white.opacity(0.6))
                        .frame(width: 64, alignment: .trailing)
                }
                .padding(.vertical, 9)

                if split.id != splits.last?.id {
                    Divider()
                        .background(.white.opacity(0.06))
                }
            }
        }
    }

    // MARK: - Helpers

    private func formattedPace(_ secondsPerKm: Double) -> String {
        guard secondsPerKm > 0 else { return "--:--" }
        let total = Int(secondsPerKm.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    /// Fast splits glow green; slow splits trend red. Threshold: 5:00/km = 300 s/km.
    private func paceColor(_ pace: Double) -> Color {
        guard pace > 0 else { return .white.opacity(0.4) }
        if pace < 240 { return Color.kineticsGreen }
        if pace < 300 { return Color.kineticsBlue }
        if pace < 360 { return Color.kineticsOrange }
        return Color.kineticsRed
    }
}
