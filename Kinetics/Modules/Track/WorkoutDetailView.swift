import Charts
import CoreLocation
import MapKit
import SwiftUI

// MARK: - WorkoutDetailView

/// Full detail view for a single past GPS workout.
///
/// Pushed onto the navigation stack from `WorkoutHistoryView` when the user taps a row.
/// Mirrors the structure of `SessionDetailView` for the sports modules, but surfaces
/// GPS-specific data: route map, HR zone bar, pace-by-km bar chart, and splits table.
@MainActor
struct WorkoutDetailView: View {

    // MARK: - Inputs

    let workout: WorkoutResult

    // MARK: - State

    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @State private var showDeleteConfirm = false

    // MARK: - Computed

    private var accent: Color { Color(hex: workout.activityType.accentColorHex) }

    private var routeCoordinates: [CLLocationCoordinate2D] {
        zip(workout.routeLatitudes, workout.routeLongitudes).map {
            CLLocationCoordinate2D(latitude: $0, longitude: $1)
        }
    }

    /// Min pace across splits — used to scale the bar chart y-axis lower bound.
    private var minSplitPace: Double {
        workout.splits.compactMap { $0.pace > 0 ? $0.pace : nil }.min() ?? 0
    }

    /// Max pace across splits — used to scale the bar chart y-axis upper bound.
    private var maxSplitPace: Double {
        workout.splits.map(\.pace).max() ?? 0
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            Color.kineticsBackground.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    routeMapSection
                    highlightsSection
                    metricsSection
                    hrZonesSection
                    paceBySplitSection
                    splitsSection
                    deleteButton
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 40)
            }
        }
        .navigationTitle(
            "\(workout.activityType.displayName.uppercased()) SESSION"
        )
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.kineticsBackground, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                shareButton
            }
        }
        .confirmationDialog(
            "Delete this workout?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                Task {
                    guard let uid = appState.authManager.currentUser?.uid else { return }
                    try? await WorkoutRepository.shared.delete(id: workout.id, userId: uid)
                    dismiss()
                }
            }
        }
    }

    // MARK: - Route Map

    private var routeMapSection: some View {
        Group {
            if routeCoordinates.count >= 2 {
                RouteMapView.routeSummary(coordinates: routeCoordinates)
                    .frame(maxWidth: .infinity)
                    .frame(height: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(.white.opacity(0.07), lineWidth: 0.5)
                    )
            } else {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.kineticsDark)
                    .frame(maxWidth: .infinity)
                    .frame(height: 200)
                    .overlay(
                        VStack(spacing: 8) {
                            Image(systemName: "map.fill")
                                .font(.system(size: 28))
                                .foregroundStyle(.white.opacity(0.18))
                            Text("No route recorded")
                                .font(.system(size: 13))
                                .foregroundStyle(.white.opacity(0.28))
                        }
                    )
            }
        }
    }

    // MARK: - Highlights (Achievements)

    @ViewBuilder
    private var highlightsSection: some View {
        if !workout.achievements.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                sectionHeader("HIGHLIGHTS")

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(workout.achievements, id: \.self) { achievement in
                            HStack(spacing: 6) {
                                Image(systemName: "trophy.fill")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(Color(hex: "FFB800"))

                                Text(achievement)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(.white)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color(hex: "FFB800").opacity(0.1))
                            .clipShape(Capsule())
                            .overlay(
                                Capsule()
                                    .strokeBorder(Color(hex: "FFB800").opacity(0.25), lineWidth: 0.5)
                            )
                        }
                    }
                    .padding(.horizontal, 1)
                }
            }
        }
    }

    // MARK: - Metrics

    private var metricsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("METRICS")

            // Primary row: distance, duration, pace
            HStack(spacing: 0) {
                detailMetricCell(
                    value: workout.formattedDistance,
                    label: "Distance"
                )
                verticalDivider
                detailMetricCell(
                    value: workout.formattedDuration,
                    label: "Time"
                )
                verticalDivider
                detailMetricCell(
                    value: workout.formattedAvgPace,
                    label: "Avg Pace"
                )
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            .background(Color.kineticsDark)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(.white.opacity(0.07), lineWidth: 0.5)
            )

            // Secondary row: elevation, heart rate, calories
            HStack(spacing: 0) {
                detailMetricCell(
                    value: String(format: "+%.0fm", workout.elevationGain),
                    label: "Elevation",
                    valueColor: Color.kineticsGreen
                )
                verticalDivider
                detailMetricCell(
                    value: workout.avgHeartRate > 0
                        ? String(format: "%.0f bpm", workout.avgHeartRate)
                        : "-- bpm",
                    label: "Avg HR",
                    valueColor: Color.kineticsRed
                )
                verticalDivider
                detailMetricCell(
                    value: String(format: "%.0f kcal", workout.calories),
                    label: "Calories",
                    valueColor: Color.kineticsOrange
                )
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            .background(Color.kineticsDark)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(.white.opacity(0.07), lineWidth: 0.5)
            )
        }
    }

    private var verticalDivider: some View {
        Rectangle()
            .fill(.white.opacity(0.08))
            .frame(width: 0.5)
            .padding(.vertical, 12)
    }

    private func detailMetricCell(
        value: String,
        label: String,
        valueColor: Color = .white
    ) -> some View {
        VStack(alignment: .center, spacing: 4) {
            Text(value)
                .font(.system(size: 16, weight: .black, design: .rounded))
                .foregroundStyle(valueColor)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .tracking(1.2)
                .foregroundStyle(.white.opacity(0.38))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }

    // MARK: - HR Zones

    private var hrZonesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("HEART RATE ZONES")
            HRZoneBar(zones: workout.hrZones)
                .reportCard()
        }
    }

    // MARK: - Pace By Km (Swift Charts)

    @ViewBuilder
    private var paceBySplitSection: some View {
        if !workout.splits.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                sectionHeader("PACE BY KM")

                Chart(workout.splits) { split in
                    BarMark(
                        x: .value("Split", split.splitNumber),
                        y: .value("Pace (s/km)", split.pace)
                    )
                    .foregroundStyle(paceBarColor(split.pace))
                    .cornerRadius(4)
                    .annotation(position: .top, alignment: .center) {
                        if split.pace > 0 {
                            Text(shortPace(split.pace))
                                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.55))
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.3))
                            .foregroundStyle(.white.opacity(0.1))
                        AxisValueLabel {
                            if let km = value.as(Int.self) {
                                Text("K\(km)")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.white.opacity(0.35))
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.3))
                            .foregroundStyle(.white.opacity(0.1))
                        AxisValueLabel {
                            if let seconds = value.as(Double.self) {
                                Text(shortPace(seconds))
                                    .font(.system(size: 9))
                                    .foregroundStyle(.white.opacity(0.35))
                            }
                        }
                    }
                }
                // Invert y-axis — lower seconds/km = faster pace at the top.
                .chartYScale(domain: {
                    let margin = 30.0
                    let lo = max(0, minSplitPace - margin)
                    let hi = maxSplitPace + margin
                    return lo ... hi
                }())
                .frame(height: 160)
                .padding(16)
                .background(Color.kineticsDark)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(.white.opacity(0.07), lineWidth: 0.5)
                )
            }
        }
    }

    /// Color-codes bars: fast (green) → moderate (blue) → slow (red).
    private func paceBarColor(_ pace: Double) -> Color {
        guard pace > 0 else { return .white.opacity(0.3) }
        if pace < 240 { return Color.kineticsGreen }
        if pace < 300 { return Color.kineticsBlue }
        if pace < 360 { return Color.kineticsOrange }
        return Color.kineticsRed
    }

    /// Short pace label for chart annotations, e.g. "4:32".
    private func shortPace(_ secondsPerKm: Double) -> String {
        guard secondsPerKm > 0 else { return "--" }
        let total = Int(secondsPerKm.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    // MARK: - Splits Table

    @ViewBuilder
    private var splitsSection: some View {
        if !workout.splits.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                sectionHeader("SPLITS")
                SplitsTable(splits: workout.splits)
                    .reportCard()
            }
        }
    }

    // MARK: - Delete Button

    private var deleteButton: some View {
        Button { showDeleteConfirm = true } label: {
            Text("Delete Workout")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.kineticsRed)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(Color.kineticsRed.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: - Share Button

    private var shareButton: some View {
        let text = """
        Kinetics — \(workout.activityType.displayName) — \(workout.formattedDate)
        Distance: \(workout.formattedDistance)
        Time: \(workout.formattedDuration)
        Avg Pace: \(workout.formattedAvgPace)
        Elevation: +\(String(format: "%.0f", workout.elevationGain))m
        """

        return ShareLink(item: text) {
            Image(systemName: "square.and.arrow.up")
                .font(.system(size: 15))
                .foregroundStyle(Color.kineticsBlue)
        }
    }
}
