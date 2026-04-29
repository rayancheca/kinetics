import SwiftUI
import Vision

// MARK: - StrikingView

/// Full-screen camera + real-time biomechanics overlay for the Striking Clinic module.
///
/// Layout:
/// - Z-layer 0: Camera feed, edge-to-edge.
/// - Z-layer 1: Skeleton pose overlay (Canvas, non-interactive).
/// - Z-layer 2: Strike flash — brief red pulse on strike detection.
/// - Z-layer 3: Top HUD (module label + session timer).
/// - safeAreaInset(.bottom): Metrics panel with live stats.
///
/// The view owns a `StrikingViewModel` instance via `@State` so it lives exactly as long
/// as this view is on screen. `AppState` is injected from the environment.
struct StrikingView: View {

    // MARK: - Dependencies

    @Environment(AppState.self) private var appState
    @State private var viewModel = StrikingViewModel()

    // MARK: - Flash State

    @State private var showStrikeFlash = false

    // MARK: - Body

    var body: some View {
        ZStack {
            // Layer 0: Camera feed — fills safe area and beyond.
            cameraLayer

            // Layer 1: 19-joint skeleton overlay in striking red.
            overlayLayer

            // Layer 2: Red screen flash on each detected strike.
            strikeFlashLayer

            // Layer 3: Module label + session timer HUD at the top.
            hudLayer
        }
        .ignoresSafeArea()
        .navigationBarBackButtonHidden()
        .toolbar { backButton }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            metricsPanel
        }
        .onAppear {
            viewModel.startProcessing(with: appState.cameraManager)
        }
        .onDisappear {
            appState.cameraManager.stopSession()
        }
    }

    // MARK: - Camera

    private var cameraLayer: some View {
        CameraPreviewView(cameraManager: appState.cameraManager)
            .ignoresSafeArea()
    }

    // MARK: - Skeleton Overlay

    private var overlayLayer: some View {
        PoseOverlayView(
            pose: viewModel.currentPose,
            activeJoints: StrikingAnalytics.activeJoints,
            color: .kineticsRed
        )
        .ignoresSafeArea()
    }

    // MARK: - Strike Flash

    private var strikeFlashLayer: some View {
        Color.kineticsRed
            .opacity(showStrikeFlash ? 0.22 : 0)
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .animation(.easeOut(duration: 0.15), value: showStrikeFlash)
            .onChange(of: viewModel.metrics.isStrikeDetected) { _, isDetected in
                guard isDetected else { return }
                showStrikeFlash = true
                Task {
                    try? await Task.sleep(for: .milliseconds(140))
                    showStrikeFlash = false
                }
            }
    }

    // MARK: - Top HUD

    private var hudLayer: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center) {
                moduleLabel
                Spacer()
                sessionTimerBadge
            }
            .padding(.horizontal, 16)
            .padding(.top, 56) // Clear the status bar safely.
            Spacer()
        }
        .allowsHitTesting(false)
    }

    private var moduleLabel: some View {
        HStack(spacing: 7) {
            Image(systemName: "bolt.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color.kineticsRed)

            Text("STRIKING CLINIC")
                .font(.system(size: 11, weight: .bold, design: .default))
                .tracking(2.2)
                .foregroundStyle(Color.white.opacity(0.90))
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 7)
        .background {
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay {
                    Capsule()
                        .fill(Color.black.opacity(0.35))
                }
        }
    }

    private var sessionTimerBadge: some View {
        Text(formattedDuration)
            .font(.system(.caption, design: .monospaced, weight: .medium))
            .foregroundStyle(Color.white.opacity(0.75))
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background {
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay {
                        Capsule()
                            .fill(Color.black.opacity(0.35))
                    }
            }
    }

    private var formattedDuration: String {
        let total = Int(viewModel.sessionDuration)
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    // MARK: - Metrics Panel

    private var metricsPanel: some View {
        MetricsCardView {
            VStack(spacing: 12) {
                // ── Strike detected indicator ──────────────────────────────
                if viewModel.metrics.isStrikeDetected {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color.kineticsRed)
                            .frame(width: 6, height: 6)

                        Text("STRIKE DETECTED")
                            .font(.system(size: 10, weight: .bold, design: .default))
                            .tracking(2.0)
                            .foregroundStyle(Color.kineticsRed)
                    }
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.9)),
                        removal:   .opacity
                    ))
                }

                // ── Primary metrics row ────────────────────────────────────
                HStack(spacing: 0) {
                    MetricBadge(
                        value: viewModel.metrics.velocityDisplay,
                        label: "MPH",
                        color: .kineticsGreen,
                        isAlert: viewModel.metrics.isStrikeDetected
                    )
                    .frame(maxWidth: .infinity)

                    panelDivider

                    MetricBadge(
                        value: viewModel.metrics.peakDisplay,
                        label: "PEAK MPH",
                        color: .kineticsBlue
                    )
                    .frame(maxWidth: .infinity)

                    panelDivider

                    MetricBadge(
                        value: "\(viewModel.metrics.strikeCount)",
                        label: "STRIKES",
                        color: .kineticsRed
                    )
                    .frame(maxWidth: .infinity)
                }

                // ── Separator ──────────────────────────────────────────────
                Rectangle()
                    .fill(Color.white.opacity(0.08))
                    .frame(height: 1)
                    .padding(.horizontal, 4)

                // ── Secondary metrics ──────────────────────────────────────
                VStack(spacing: 5) {
                    MetricRow(
                        label: "Kinematic Score",
                        value: viewModel.metrics.scoreDisplay + " / 100",
                        color: kinematicScoreColor
                    )
                    MetricRow(
                        label: "Hip – Shoulder Sep.",
                        value: viewModel.metrics.separationDisplay,
                        color: Color.white.opacity(0.85)
                    )
                }
                .padding(.horizontal, 4)
            }
            .animation(.easeInOut(duration: 0.2), value: viewModel.metrics.isStrikeDetected)
        }
    }

    /// A thin vertical rule between primary metric badges.
    private var panelDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.10))
            .frame(width: 1, height: 40)
    }

    /// Transitions the kinematic score color through red → blue → green as quality improves.
    private var kinematicScoreColor: Color {
        let score = viewModel.metrics.kinematicScore
        switch score {
        case 75...: return .kineticsGreen
        case 50...: return .kineticsBlue
        default:    return .kineticsRed
        }
    }

    // MARK: - Navigation Bar

    @ToolbarContentBuilder
    private var backButton: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            Button {
                Task {
                    let uid = appState.authManager.currentUser?.uid ?? "anonymous"
                    await viewModel.endSession(userId: uid)
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .semibold))
                    Text("End")
                        .font(.system(size: 15, weight: .medium))
                }
                .foregroundStyle(Color.kineticsRed)
            }
        }
    }
}
