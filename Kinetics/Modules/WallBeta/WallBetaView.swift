import SwiftUI
import Vision

// MARK: - WallBetaView

/// Full-screen camera + real-time biomechanics overlay for the Wall Beta climbing module.
///
/// Layout (Z order, bottom → top):
/// 1. Camera feed — edge-to-edge, `ignoresSafeArea`.
/// 2. Skeleton overlay — 19-joint rig in neon green, non-interactive.
/// 3. Dyno arc Canvas — CoM trajectory drawn during explosive jumps.
/// 4. Left-edge hip proximity gauge — vertical bar showing wall proximity.
/// 5. Top HUD — module label, movement phase badge, session timer, sag warning.
/// 6. `safeAreaInset(.bottom)` — metrics panel with proximity %, hold time, velocity.
///
/// The view owns its `WallBetaViewModel` via `@State` so the instance lives exactly
/// as long as this screen is on screen. `AppState` is injected from the environment.
struct WallBetaView: View {

    // MARK: - Dependencies

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = WallBetaViewModel()
    @AppStorage("seen_wall_beta_onboarding") private var hasSeenOnboarding = false
    @State private var showOnboarding = false
    @State private var showReport = false
    @State private var isLivePulsing = false

    // MARK: - Body

    var body: some View {
        ZStack {
            // ── Layer 0: Camera feed ──────────────────────────────────────────────
            cameraLayer

            // ── Layer 1: Skeleton overlay in neon green ───────────────────────────
            skeletonOverlay

            // ── Layer 2: Dyno arc Canvas ──────────────────────────────────────────
            dynoArcOverlay

            // ── Layer 3: Left-edge hip proximity gauge ────────────────────────────
            HStack(spacing: 0) {
                proximityGauge
                Spacer()
            }
            .padding(.leading, 12)
            .ignoresSafeArea(edges: .top)

            // ── Layer 4: Top HUD ──────────────────────────────────────────────────
            hudLayer
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
            WallBetaOnboardingView(onDismiss: {
                hasSeenOnboarding = true
                showOnboarding = false
            })
        }
        .fullScreenCover(isPresented: $showReport) {
            if let s = viewModel.lastCompletedSession {
                NavigationStack {
                    WallBetaSessionReportView(result: s, previousSessions: [])
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

    private var skeletonOverlay: some View {
        PoseOverlayView(
            pose: viewModel.currentPose,
            activeJoints: WallBetaAnalytics.activeJoints,
            color: .kineticsGreen
        )
        .ignoresSafeArea()
    }

    // MARK: - Dyno Arc Canvas

    /// Renders the center-of-mass trajectory arc during a detected Dyno.
    /// A double-stroke technique — a narrow, vivid inner line over a wide, soft glow —
    /// gives the path visibility against both light and dark backgrounds.
    private var dynoArcOverlay: some View {
        Canvas { ctx, size in
            guard viewModel.dynoPath.count > 1 else { return }

            // Vision Y is bottom-origin; screen Y is top-origin — flip before drawing.
            let screenPoints = viewModel.dynoPath.map { pt in
                CGPoint(
                    x: Double(pt.x) * size.width,
                    y: (1.0 - Double(pt.y)) * size.height
                )
            }

            var path = Path()
            path.move(to: screenPoints[0])
            for pt in screenPoints.dropFirst() {
                path.addLine(to: pt)
            }

            // Soft glow halo — wide, low opacity.
            ctx.stroke(
                path,
                with: .color(Color.kineticsGreen.opacity(0.30)),
                style: StrokeStyle(lineWidth: 10, lineCap: .round, lineJoin: .round)
            )

            // Vivid core line.
            ctx.stroke(
                path,
                with: .color(Color.kineticsGreen.opacity(0.90)),
                style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)
            )
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    // MARK: - Hip Proximity Gauge

    /// Vertical bar anchored to the left edge of the screen.
    /// Height grows proportionally to `hipProximityScore`; color signals technique quality.
    private var proximityGauge: some View {
        VStack(spacing: 6) {
            Spacer()

            // Gauge bar — grows from the bottom up via VStack gravity.
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                RoundedRectangle(cornerRadius: 4)
                    .fill(proximityGaugeColor)
                    .frame(width: 8, height: gaugeBarHeight)
                    .shadow(color: proximityGaugeColor.opacity(0.6), radius: 4, x: 0, y: 0)
                    .animation(.easeInOut(duration: 0.15), value: viewModel.metrics.hipProximityScore)
            }
            .frame(width: 8, height: 200)
            .background(
                // Dim track behind the bar.
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.white.opacity(0.10))
            )

            Text("HIP\nPROX")
                .font(.system(size: 8, weight: .medium))
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.white.opacity(0.40))
                .tracking(0.5)

            Spacer()
        }
        .frame(height: 250)
    }

    /// Filled track height in points, scaled from `hipProximityScore`.
    private var gaugeBarHeight: CGFloat {
        CGFloat(viewModel.metrics.hipProximityScore / 100.0) * 200.0
    }

    /// Color encodes technique quality: green (excellent) → yellow (average) → red (poor).
    private var proximityGaugeColor: Color {
        switch viewModel.metrics.hipProximityScore {
        case 70...: return .kineticsGreen
        case 30...: return Color(red: 1.0, green: 0.84, blue: 0.0) // amber
        default:    return .kineticsRed
        }
    }

    // MARK: - Top HUD

    private var hudLayer: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 8) {
                moduleLabel
                Spacer()
                movementPhaseBadge
                sessionTimerBadge
            }
            .padding(.horizontal, 16)
            .padding(.top, 56) // Clears the status bar.

            // Hip sag warning — appears immediately below the top bar when active.
            if viewModel.metrics.isHipSag {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.kineticsOrange)

                    Text("HIP SAG")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(2.0)
                        .foregroundStyle(Color.kineticsOrange)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background {
                    Capsule()
                        .fill(Color.black.opacity(0.55))
                        .overlay {
                            Capsule()
                                .strokeBorder(Color.kineticsOrange.opacity(0.50), lineWidth: 1)
                        }
                }
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .scale(scale: 0.85)),
                    removal:   .opacity
                ))
                .padding(.top, 8)
            }

            Spacer()
        }
        .allowsHitTesting(false)
        .animation(.easeInOut(duration: 0.2), value: viewModel.metrics.isHipSag)
    }

    private var moduleLabel: some View {
        HStack(spacing: 7) {
            Image(systemName: "figure.climbing")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color.kineticsGreen)

            Text("WALL BETA")
                .font(.system(size: 11, weight: .bold))
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

    /// Color-coded badge showing the current movement phase.
    private var movementPhaseBadge: some View {
        let phase = viewModel.metrics.movementPhase

        return Text(phaseBadgeLabel(phase))
            .font(.system(size: 10, weight: .bold))
            .tracking(1.5)
            .foregroundStyle(phaseBadgeForeground(phase))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background {
                Capsule()
                    .fill(phaseBadgeBackground(phase))
                    .overlay {
                        Capsule()
                            .strokeBorder(phaseBadgeBorder(phase), lineWidth: 1)
                    }
            }
            .animation(.easeInOut(duration: 0.2), value: phase)
    }

    private func phaseBadgeLabel(_ phase: MovementPhase) -> String {
        switch phase {
        case .static_hold:  return "STATIC HOLD"
        case .transitioning: return "MOVING"
        case .dyno:         return "⚡ DYNO!"
        }
    }

    private func phaseBadgeForeground(_ phase: MovementPhase) -> Color {
        switch phase {
        case .static_hold:  return .kineticsGreen
        case .transitioning: return Color.white.opacity(0.80)
        case .dyno:         return Color.kineticsDark
        }
    }

    private func phaseBadgeBackground(_ phase: MovementPhase) -> Color {
        switch phase {
        case .static_hold:  return Color.black.opacity(0.50)
        case .transitioning: return Color.white.opacity(0.12)
        case .dyno:         return .kineticsGreen
        }
    }

    private func phaseBadgeBorder(_ phase: MovementPhase) -> Color {
        switch phase {
        case .static_hold:  return Color.kineticsGreen.opacity(0.50)
        case .transitioning: return Color.clear
        case .dyno:         return Color.clear
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
                // ── Primary metrics ────────────────────────────────────────────────
                HStack(spacing: 0) {
                    MetricBadge(
                        value: viewModel.metrics.proximityDisplay,
                        label: "HIP PROX",
                        color: proximityBadgeColor
                    )
                    .frame(maxWidth: .infinity)

                    panelDivider

                    MetricBadge(
                        value: viewModel.metrics.holdTimeDisplay,
                        label: "HOLD TIME",
                        color: .kineticsGreen
                    )
                    .frame(maxWidth: .infinity)

                    panelDivider

                    MetricBadge(
                        value: viewModel.metrics.velocityDisplay,
                        label: "AVG SPEED",
                        color: .kineticsBlue
                    )
                    .frame(maxWidth: .infinity)
                }

                // ── Separator ──────────────────────────────────────────────────────
                Rectangle()
                    .fill(Color.white.opacity(0.08))
                    .frame(height: 1)
                    .padding(.horizontal, 4)

                // ── Secondary rows ─────────────────────────────────────────────────
                VStack(spacing: 5) {
                    MetricRow(
                        label: "Movement Phase",
                        value: viewModel.metrics.movementPhase.rawValue,
                        color: phaseRowColor
                    )
                    MetricRow(
                        label: "Hip Sag",
                        value: viewModel.metrics.isHipSag ? "DETECTED" : "OK",
                        color: viewModel.metrics.isHipSag ? .kineticsOrange : .kineticsGreen
                    )
                }
                .padding(.horizontal, 4)

                // ── Coaching cue ───────────────────────────────────────────────────
                Text(viewModel.coachingCue)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.65))
                    .multilineTextAlignment(.center)
                    .padding(.top, 2)
                    .animation(.easeInOut(duration: 0.4), value: viewModel.coachingCue)
            }
            .animation(.easeInOut(duration: 0.2), value: viewModel.metrics.movementPhase)
        }
    }

    private var panelDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.10))
            .frame(width: 1, height: 40)
    }

    /// Badge color mirrors the gauge: green → amber → red.
    private var proximityBadgeColor: Color {
        switch viewModel.metrics.hipProximityScore {
        case 70...: return .kineticsGreen
        case 30...: return Color(red: 1.0, green: 0.84, blue: 0.0)
        default:    return .kineticsRed
        }
    }

    private var phaseRowColor: Color {
        switch viewModel.metrics.movementPhase {
        case .static_hold:  return .kineticsGreen
        case .transitioning: return Color.white.opacity(0.75)
        case .dyno:         return .kineticsGreen
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
                .foregroundStyle(Color.kineticsGreen)
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
