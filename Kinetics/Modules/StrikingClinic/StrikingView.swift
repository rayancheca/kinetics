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
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = StrikingViewModel()

    // MARK: - Onboarding / Report State

    @AppStorage("seen_striking_onboarding") private var hasSeenOnboarding = false
    @AppStorage("camera_position_striking") private var preferFrontCamera = false
    @State private var showOnboarding = false
    @State private var showReport = false
    @State private var isLivePulsing = false

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

            // Layer 4: AI coach cue overlay — slides in from top above the HUD.
            CoachOverlayView(cue: viewModel.currentCoachCue)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.top, 108)

            // Layer 5: Floating camera flip button — interactive overlay.
            cameraFlipButton
        }
        .ignoresSafeArea()
        .navigationBarBackButtonHidden()
        .toolbar { backButton }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            metricsPanel
        }
        .task {
            await viewModel.startProcessing(with: appState.cameraManager)
        }
        .onAppear {
            if !hasSeenOnboarding { showOnboarding = true }
            isLivePulsing = true
        }
        .onDisappear {
            viewModel.stopProcessing()
            appState.cameraManager.stopSession()
        }
        .sheet(isPresented: $showOnboarding) {
            StrikingOnboardingView(onDismiss: {
                hasSeenOnboarding = true
                showOnboarding = false
            })
        }
        .fullScreenCover(isPresented: $showReport) {
            if let s = viewModel.lastCompletedSession {
                NavigationStack {
                    StrikingSessionReportView(result: s, previousSessions: [])
                }
            }
        }
        .overlay {
            if viewModel.isSessionActive && viewModel.currentPose == nil {
                NobodyDetectedOverlay()
            }
        }
        .overlay {
            if appState.cameraManager.permissionDenied {
                CameraPermissionDeniedOverlay {
                    appState.cameraManager.openSettings()
                }
            }
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
        Group {
            if viewModel.isSessionActive {
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 6, height: 6)
                        .shadow(color: .red.opacity(0.8), radius: 4)
                        .scaleEffect(isLivePulsing ? 1.3 : 1.0)
                        .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isLivePulsing)
                    Text(formattedDuration)
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white)
                }
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
            } else {
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

    // MARK: - Camera Flip Button

    private var cameraFlipButton: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button {
                    Task {
                        await appState.cameraManager.switchCamera()
                        preferFrontCamera = appState.cameraManager.cameraPosition == .front
                    }
                } label: {
                    Image(systemName: "camera.rotate.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(12)
                        .background(.ultraThinMaterial)
                        .clipShape(Circle())
                        .shadow(color: .black.opacity(0.4), radius: 6)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 104) // Below the module label row (56 safe area + 48 label height).
            Spacer()
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
                    if viewModel.lastCompletedSession != nil { showReport = true }
                    dismiss()
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

        ToolbarItem(placement: .navigationBarTrailing) {
            Button {
                showOnboarding = true
            } label: {
                Image(systemName: "info.circle")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(Color.white.opacity(0.75))
            }
        }
    }
}

// MARK: - NobodyDetectedOverlay

private struct NobodyDetectedOverlay: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "person.fill.viewfinder")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.white.opacity(0.7))
            Text("Point camera at yourself")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: Capsule())
        .padding(.top, 120)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .allowsHitTesting(false)
    }
}

// MARK: - CameraPermissionDeniedOverlay

private struct CameraPermissionDeniedOverlay: View {
    let onOpenSettings: () -> Void
    var body: some View {
        ZStack {
            Color.black.opacity(0.92).ignoresSafeArea()
            VStack(spacing: 20) {
                Image(systemName: "camera.slash.fill")
                    .font(.system(size: 52, weight: .thin))
                    .foregroundStyle(Color(red: 0, green: 0.76, blue: 1))
                Text("Camera Access Required")
                    .font(.system(.title2, design: .rounded, weight: .semibold))
                    .foregroundStyle(.white)
                Text("Kinetics needs camera access to analyze your movement in real time.")
                    .font(.system(.subheadline))
                    .foregroundStyle(.white.opacity(0.55))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                Button("Open Settings", action: onOpenSettings)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color(red: 0, green: 0, blue: 0.1))
                    .padding(.horizontal, 32)
                    .padding(.vertical, 14)
                    .background(Color(red: 0, green: 0.76, blue: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            }
        }
    }
}
