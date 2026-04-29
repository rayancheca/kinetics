import MapKit
import SwiftUI

// MARK: - ActiveWorkoutView

/// Full-screen live GPS recording UI.
///
/// Layout (portrait):
///   • `RouteMapView` fills ~40 % of the screen height, auto-following the user.
///   • Primary metric trio (distance / pace / time) rendered large in SF Rounded Bold.
///   • Secondary metrics row (heart rate / elevation / avg pace).
///   • Horizontally scrollable splits strip.
///   • Top toolbar: END (left) + PAUSE / RESUME (right).
///
/// Lifecycle:
///   • On appear: `requestPermissions()` is awaited via `.task { }`.
///   • END → `endWorkout(userId:)` → presents `WorkoutSummaryView` via `viewModel.showSummary`.
///   • PAUSE → `pauseWorkout()` / RESUME → `resumeWorkout()`.
struct ActiveWorkoutView: View {

    // MARK: - Dependencies

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    /// Injected from `TrackView` so both views share the same ViewModel instance.
    @Bindable var viewModel: TrackViewModel

    // MARK: - Private State

    @State private var isPulsingDot = false
    @State private var isEnding = false

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                mapSection
                metricsSection
                splitsSection
            }

            // Floating top toolbar drawn over the map
            topToolbar
        }
        .ignoresSafeArea(edges: .bottom)
        .navigationBarHidden(true)
        .task {
            await viewModel.requestPermissions()
        }
        .fullScreenCover(isPresented: $viewModel.showSummary) {
            if let result = viewModel.lastCompletedWorkout {
                WorkoutSummaryView(workout: result)
            }
        }
    }

    // MARK: - Map

    private var mapSection: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottomLeading) {
                RouteMapView(
                    coordinates: viewModel.routeCoordinates,
                    currentLocation: viewModel.routeCoordinates.last,
                    followsUser: true
                )
                .ignoresSafeArea(edges: .top)

                // Live-recording indicator badge overlaid on the map
                if viewModel.isTracking && !viewModel.isPaused {
                    recordingBadge
                        .padding(.leading, 16)
                        .padding(.bottom, 12)
                }

                // Paused state overlay
                if viewModel.isPaused {
                    pausedOverlay
                }
            }
            .frame(height: geo.size.height * 0.42)
        }
        .frame(height: UIScreen.main.bounds.height * 0.42)
    }

    private var recordingBadge: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Color.kineticsRed)
                .frame(width: 7, height: 7)
                .shadow(color: Color.kineticsRed.opacity(0.8), radius: 4)
                .scaleEffect(isPulsingDot ? 1.35 : 1.0)
                .animation(
                    .easeInOut(duration: 0.75).repeatForever(autoreverses: true),
                    value: isPulsingDot
                )
                .onAppear { isPulsingDot = true }

            Text("REC")
                .font(.system(size: 11, weight: .bold))
                .tracking(1.5)
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
    }

    private var pausedOverlay: some View {
        Color.black.opacity(0.45)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay {
                VStack(spacing: 6) {
                    Image(systemName: "pause.fill")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.white.opacity(0.9))
                    Text("PAUSED")
                        .font(.system(size: 11, weight: .bold))
                        .tracking(3)
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
    }

    // MARK: - Metrics Section

    private var metricsSection: some View {
        VStack(spacing: 0) {
            // ── Primary metrics ────────────────────────────────────────────
            HStack(spacing: 0) {
                PrimaryMetric(
                    value: viewModel.formattedDistance,
                    label: "DISTANCE",
                    color: .white
                )
                .frame(maxWidth: .infinity)

                metricDivider

                PrimaryMetric(
                    value: viewModel.currentPace,
                    label: "PACE",
                    color: Color.kineticsGreen
                )
                .frame(maxWidth: .infinity)

                metricDivider

                PrimaryMetric(
                    value: viewModel.formattedElapsedTime,
                    label: "TIME",
                    color: .white
                )
                .frame(maxWidth: .infinity)
            }
            .padding(.vertical, 20)
            .background(Color(red: 0.07, green: 0.07, blue: 0.07))

            // ── Hairline divider ───────────────────────────────────────────
            Rectangle()
                .fill(Color.white.opacity(0.07))
                .frame(height: 1)

            // ── Secondary metrics ──────────────────────────────────────────
            HStack(spacing: 0) {
                SecondaryMetric(
                    value: heartRateDisplay,
                    unit: "bpm",
                    label: "HEART RATE",
                    color: Color.kineticsRed
                )
                .frame(maxWidth: .infinity)

                metricDivider

                SecondaryMetric(
                    value: viewModel.formattedElevation,
                    unit: "",
                    label: "ELEVATION",
                    color: Color.kineticsOrange
                )
                .frame(maxWidth: .infinity)

                metricDivider

                SecondaryMetric(
                    value: viewModel.avgPace,
                    unit: "",
                    label: "AVG PACE",
                    color: Color.kineticsBlue
                )
                .frame(maxWidth: .infinity)
            }
            .padding(.vertical, 14)
            .background(Color(red: 0.06, green: 0.06, blue: 0.06))
        }
    }

    private var metricDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.08))
            .frame(width: 1, height: 44)
    }

    private var heartRateDisplay: String {
        viewModel.currentHeartRate > 0
            ? "\(Int(viewModel.currentHeartRate))"
            : "--"
    }

    // MARK: - Splits

    private var splitsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !viewModel.splits.isEmpty {
                HStack {
                    Text("SPLITS")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(2.5)
                        .foregroundStyle(.white.opacity(0.35))
                    Spacer()
                    Text("\(viewModel.splits.count) km")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.25))
                }
                .padding(.horizontal, 16)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(viewModel.splits) { split in
                            SplitChip(split: split)
                        }
                    }
                    .padding(.horizontal, 16)
                }
            } else {
                // Placeholder until first split is recorded
                HStack(spacing: 8) {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.22))
                    Text("Splits appear after each kilometre")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.22))
                }
                .padding(.horizontal, 16)
            }
        }
        .padding(.vertical, 14)
        .background(Color(red: 0.05, green: 0.05, blue: 0.05))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Top Toolbar

    private var topToolbar: some View {
        HStack {
            // END button
            Button {
                guard !isEnding else { return }
                isEnding = true
                Task {
                    let uid = appState.authManager.currentUser?.uid ?? "anonymous"
                    await viewModel.endWorkout(userId: uid)
                    isEnding = false
                    // showSummary is set by the ViewModel; dismiss happens from the summary sheet
                    if !viewModel.showSummary {
                        dismiss()
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    if isEnding {
                        ProgressView()
                            .tint(.white)
                            .scaleEffect(0.75)
                    } else {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 12, weight: .bold))
                    }
                    Text("END")
                        .font(.system(size: 14, weight: .bold))
                        .tracking(0.5)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .background(Color.kineticsRed.opacity(0.85), in: Capsule())
                .shadow(color: Color.kineticsRed.opacity(0.35), radius: 8, y: 3)
            }
            .disabled(isEnding)

            Spacer()

            // PAUSE / RESUME button
            Button {
                if viewModel.isPaused {
                    Task { await viewModel.resumeWorkout() }
                } else {
                    viewModel.pauseWorkout()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: viewModel.isPaused ? "play.fill" : "pause.fill")
                        .font(.system(size: 12, weight: .bold))
                    Text(viewModel.isPaused ? "RESUME" : "PAUSE")
                        .font(.system(size: 14, weight: .bold))
                        .tracking(0.5)
                }
                .foregroundStyle(viewModel.isPaused ? Color.kineticsDark : .white)
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .background(
                    viewModel.isPaused
                        ? Color.kineticsGreen
                        : Color.white.opacity(0.14),
                    in: Capsule()
                )
                .animation(.easeInOut(duration: 0.2), value: viewModel.isPaused)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 56) // Clear system status bar
    }
}

// MARK: - PrimaryMetric

private struct PrimaryMetric: View {

    let value: String
    let label: String
    var color: Color

    var body: some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(color)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .contentTransition(.numericText())
                .animation(.easeInOut(duration: 0.25), value: value)

            Text(label)
                .font(.system(size: 9, weight: .medium))
                .tracking(1.8)
                .foregroundStyle(.white.opacity(0.40))
        }
        .padding(.horizontal, 8)
    }
}

// MARK: - SecondaryMetric

private struct SecondaryMetric: View {

    let value: String
    let unit: String
    let label: String
    var color: Color

    var body: some View {
        VStack(spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(color)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(.easeInOut(duration: 0.25), value: value)

                if !unit.isEmpty {
                    Text(unit)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(color.opacity(0.7))
                }
            }

            Text(label)
                .font(.system(size: 8, weight: .medium))
                .tracking(1.8)
                .foregroundStyle(.white.opacity(0.32))
        }
        .padding(.horizontal, 6)
    }
}

// MARK: - SplitChip

private struct SplitChip: View {

    let split: WorkoutSplit

    private var paceString: String {
        guard split.pace > 0 else { return "--:--" }
        let m = Int(split.pace) / 60
        let s = Int(split.pace) % 60
        return String(format: "%d:%02d", m, s)
    }

    var body: some View {
        VStack(spacing: 4) {
            Text("km \(split.splitNumber)")
                .font(.system(size: 9, weight: .semibold))
                .tracking(1)
                .foregroundStyle(.white.opacity(0.40))

            Text(paceString)
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 9)
        .background(Color(red: 0.10, green: 0.10, blue: 0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
    }
}
