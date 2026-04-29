import SwiftUI
import Vision

// MARK: - IronTrackerView

/// Full-screen session screen for the Iron Tracker module.
///
/// **Landscape-first design:** Iron Tracker is designed for phone-on-tripod at hip height,
/// capturing the full lift from the side. A dedicated `LandscapePromptView` is shown
/// whenever the device is in portrait orientation, guiding the user to rotate before starting.
///
/// **Overlay stack (bottom to top):**
/// 1. `CameraPreviewView` — full-screen live feed, ignores safe area.
/// 2. `PoseOverlayView`   — 19-joint skeleton in electric blue.
/// 3. `BarPathCanvas`     — glowing bar path trace rendered via `Canvas`.
/// 4. Alert badges        — butt wink, knee cave, symmetry flags.
/// 5. `MetricsCardView`   — VBT speed, peak velocity, symmetry %, lift phase.
struct IronTrackerView: View {

    // MARK: Environment

    @Environment(AppState.self) private var appState

    // MARK: State

    @State private var viewModel = IronTrackerViewModel()

    // MARK: Body

    var body: some View {
        GeometryReader { geometry in
            let isLandscape = geometry.size.width > geometry.size.height

            ZStack {
                Color.kineticsBackground
                    .ignoresSafeArea()

                if isLandscape {
                    sessionContent(geometry: geometry)
                } else {
                    LandscapePromptView()
                }
            }
            .onChange(of: geometry.size) { _, newSize in
                viewModel.viewSize = newSize
            }
            .onAppear {
                viewModel.viewSize = geometry.size
            }
        }
        .navigationTitle("Iron Tracker")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .task {
            await viewModel.startProcessing(with: appState.cameraManager)
        }
        .onDisappear {
            Task {
                let uid = appState.authManager.currentUser?.uid ?? "anonymous"
                await viewModel.endSession(userId: uid)
                appState.cameraManager.stopSession()
            }
        }
    }

    // MARK: - Session Content

    @ViewBuilder
    private func sessionContent(geometry: GeometryProxy) -> some View {
        ZStack(alignment: .bottom) {
            // Layer 1: Live camera feed
            CameraPreviewView(cameraManager: appState.cameraManager)
                .ignoresSafeArea()

            // Layer 2: Skeleton overlay
            PoseOverlayView(
                pose: viewModel.currentPose,
                activeJoints: IronTrackerAnalytics.activeJoints,
                color: .kineticsBlue
            )
            .ignoresSafeArea()

            // Layer 3: Bar path trace
            BarPathCanvas(barPath: viewModel.barPath)
                .ignoresSafeArea()

            // Layer 4: Alert badges
            alertBadgeStack
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            // Layer 5: Metrics panel
            metricsPanel
        }
        .alert("Camera Error", isPresented: .constant(viewModel.errorMessage != nil)) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    // MARK: - Alert Badges

    @ViewBuilder
    private var alertBadgeStack: some View {
        VStack(alignment: .leading, spacing: 8) {
            if viewModel.metrics.isButtWink {
                AlertBadge(
                    icon: "exclamationmark.triangle.fill",
                    label: "LUMBAR FLEX",
                    color: .kineticsRed
                )
                .transition(.asymmetric(
                    insertion: .move(edge: .leading).combined(with: .opacity),
                    removal: .opacity
                ))
            }

            if viewModel.metrics.isKneeCave {
                AlertBadge(
                    icon: "exclamationmark.triangle.fill",
                    label: "KNEE CAVE",
                    color: .kineticsOrange
                )
                .transition(.asymmetric(
                    insertion: .move(edge: .leading).combined(with: .opacity),
                    removal: .opacity
                ))
            }

            if viewModel.metrics.isSymmetryAlert {
                AlertBadge(
                    icon: "arrow.left.arrow.right",
                    label: "ASYMMETRIC",
                    color: .yellow
                )
                .transition(.asymmetric(
                    insertion: .move(edge: .leading).combined(with: .opacity),
                    removal: .opacity
                ))
            }
        }
        .animation(.spring(duration: 0.3), value: viewModel.metrics.isButtWink)
        .animation(.spring(duration: 0.3), value: viewModel.metrics.isKneeCave)
        .animation(.spring(duration: 0.3), value: viewModel.metrics.isSymmetryAlert)
    }

    // MARK: - Metrics Panel

    private var metricsPanel: some View {
        MetricsCardView {
            VStack(spacing: 10) {
                // Primary row: VBT speed (hero metric) + peak + symmetry
                HStack(spacing: 0) {
                    // VBT speed — largest, green when above good threshold
                    VStack(spacing: 2) {
                        Text(viewModel.metrics.velocityDisplay)
                            .font(.system(.title, design: .rounded, weight: .bold))
                            .foregroundStyle(
                                viewModel.metrics.barVelocityMS >= IronTrackerAnalytics.vbtGoodThreshold
                                ? Color.kineticsGreen
                                : Color.white
                            )
                            .monospacedDigit()
                            .contentTransition(.numericText())
                            .animation(.easeInOut(duration: 0.15), value: viewModel.metrics.velocityDisplay)

                        Text("BAR SPEED")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.50))
                            .tracking(1.2)
                    }
                    .frame(maxWidth: .infinity)

                    Divider()
                        .frame(height: 36)
                        .background(Color.white.opacity(0.15))

                    MetricBadge(
                        value: viewModel.metrics.peakVelocityDisplay,
                        label: "peak m/s",
                        color: .kineticsBlue
                    )
                    .frame(maxWidth: .infinity)

                    Divider()
                        .frame(height: 36)
                        .background(Color.white.opacity(0.15))

                    MetricBadge(
                        value: viewModel.metrics.symmetryDisplay,
                        label: "asymmetry",
                        color: viewModel.metrics.isSymmetryAlert ? .kineticsRed : .white,
                        isAlert: viewModel.metrics.isSymmetryAlert
                    )
                    .frame(maxWidth: .infinity)
                }

                Divider()
                    .background(Color.white.opacity(0.10))

                // Secondary row: hip angle, lift phase, session time
                HStack {
                    MetricRow(
                        label: "Hip Angle",
                        value: viewModel.metrics.hipAngleDisplay,
                        color: viewModel.metrics.isButtWink ? .kineticsRed : .white
                    )

                    Spacer()
                        .frame(width: 24)

                    MetricRow(
                        label: "Phase",
                        value: viewModel.metrics.liftPhase.rawValue,
                        color: .kineticsBlue
                    )

                    Spacer()
                        .frame(width: 24)

                    MetricRow(
                        label: "Time",
                        value: formattedDuration,
                        color: .white
                    )
                }
            }
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            StatusBadge(
                text: viewModel.isSessionActive ? "Live" : "Ready",
                isActive: viewModel.isSessionActive
            )
        }
    }

    // MARK: - Helpers

    private var formattedDuration: String {
        let total = Int(viewModel.sessionDuration)
        let minutes = total / 60
        let seconds = total % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - BarPathCanvas

/// A `Canvas`-based overlay that renders the bar path as a glowing electric blue line.
///
/// The bar path is stored in Vision normalized coordinates (origin: bottom-left).
/// Before drawing, each point is converted to SwiftUI screen coordinates by:
///   - scaling X: `x * width`
///   - flipping and scaling Y: `(1 - y) * height`
///
/// Two stroke passes create the glow effect:
/// 1. A narrow, opaque core stroke (3 pt, 85% opacity).
/// 2. A wider, transparent halo stroke (8 pt, 25% opacity).
private struct BarPathCanvas: View {

    let barPath: [CGPoint]

    var body: some View {
        Canvas { ctx, size in
            guard barPath.count > 1 else { return }

            // Convert all Vision coords to screen coords.
            let screenPoints = barPath.map { pt in
                CGPoint(
                    x: pt.x * size.width,
                    y: (1.0 - pt.y) * size.height   // flip Y axis
                )
            }

            var path = Path()
            path.move(to: screenPoints[0])
            for point in screenPoints.dropFirst() {
                path.addLine(to: point)
            }

            // Wide halo — drawn first so the core renders on top.
            ctx.stroke(
                path,
                with: .color(Color.kineticsBlue.opacity(0.25)),
                style: StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .round)
            )

            // Narrow core.
            ctx.stroke(
                path,
                with: .color(Color.kineticsBlue.opacity(0.85)),
                style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)
            )
        }
        .allowsHitTesting(false)
    }
}

// MARK: - AlertBadge

/// A pill-shaped alert indicator displayed in the top-left corner during form breakdown events.
///
/// Used for three conditions: butt wink (red), knee cave (orange), and asymmetric loading (yellow).
private struct AlertBadge: View {

    let icon: String
    let label: String
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))

            Text(label)
                .font(.system(size: 11, weight: .bold))
                .tracking(0.8)
        }
        .foregroundStyle(Color.black)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(color)
        )
        .shadow(color: color.opacity(0.5), radius: 8, x: 0, y: 2)
    }
}

// MARK: - LandscapePromptView

/// Instructional overlay shown when the device is in portrait orientation.
///
/// Iron Tracker is designed for landscape capture — the phone sits on a tripod at hip
/// height with the camera pointed at the athlete from the side, giving Vision a clear
/// view of the full movement arc from ankles to shoulders.
private struct LandscapePromptView: View {

    var body: some View {
        VStack(spacing: 24) {
            // Animated rotation cue
            Image(systemName: "rotate.right")
                .font(.system(size: 56, weight: .thin))
                .foregroundStyle(Color.kineticsBlue)
                .symbolEffect(.pulse, options: .repeating)

            VStack(spacing: 8) {
                Text("Rotate to Landscape")
                    .font(.system(.title2, design: .rounded, weight: .semibold))
                    .foregroundStyle(Color.white)

                Text("Iron Tracker captures your full lift\nfrom the side. Mount your phone on a\ntripod at hip height before starting.")
                    .font(.system(.subheadline))
                    .foregroundStyle(Color.white.opacity(0.60))
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }

            // Setup hint pill
            HStack(spacing: 8) {
                Image(systemName: "video.fill")
                    .font(.system(size: 12))
                Image(systemName: "arrow.right")
                    .font(.system(size: 10))
                Image(systemName: "figure.strengthtraining.traditional")
                    .font(.system(size: 12))
            }
            .foregroundStyle(Color.kineticsBlue.opacity(0.80))
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(Color.kineticsBlue.opacity(0.12))
                    .overlay(
                        Capsule()
                            .strokeBorder(Color.kineticsBlue.opacity(0.25), lineWidth: 1)
                    )
            )
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.kineticsBackground)
    }
}
