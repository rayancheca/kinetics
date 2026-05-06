import SwiftUI

// MARK: - GrapplingView

/// Full-screen grappling analysis view.
///
/// **Layer order (back to front):**
/// 1. `CameraPreviewView` — live camera feed, fills the entire screen edge-to-edge.
/// 2. `PoseOverlayView` — 19-joint skeleton rendered in orange for grappling joints.
/// 3. CoM dot — orange/red circle tracking the athlete's center of mass in real time.
/// 4. Module label — top-left identifier.
/// 5. Postural alert banner — red banner shown when the base is compromised.
/// 6. Metrics panel — `safeAreaInset` bottom card with live analytics.
struct GrapplingView: View {

    // MARK: Dependencies

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    // MARK: Private State

    @State private var viewModel = GrapplingViewModel()
    @AppStorage("seen_grappling_onboarding") private var hasSeenOnboarding = false
    @AppStorage("camera_position_grappling") private var preferFrontCamera = true
    @State private var showOnboarding = false
    @State private var showReport = false
    @State private var isLivePulsing = false

    // MARK: Body

    var body: some View {
        ZStack(alignment: .top) {
            cameraLayer
            overlayLayer

            cameraFlipButton

            VStack(spacing: 0) {
                moduleLabel
                    .padding(.top, 16)
                    .padding(.leading, 16)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if viewModel.metrics.isPosturalAlert {
                    posturalAlertBanner
                        .padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                Spacer()
            }

            // AI coach cue overlay — sits just below the module label row.
            CoachOverlayView(cue: viewModel.currentCoachCue)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.top, 108)
        }
        .ignoresSafeArea()
        .background(Color.kineticsBackground)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            metricsPanel
        }
        .toolbar(.hidden, for: .navigationBar)
        .task {
            await viewModel.startProcessing(with: appState.cameraManager)
        }
        .onAppear {
            if !hasSeenOnboarding { showOnboarding = true }
            isLivePulsing = true
        }
        .sheet(isPresented: $showOnboarding) {
            GrapplingOnboardingView(onDismiss: {
                hasSeenOnboarding = true
                showOnboarding = false
            })
        }
        .fullScreenCover(isPresented: $showReport, onDismiss: {
            dismiss()
        }) {
            if let s = viewModel.lastCompletedSession {
                NavigationStack {
                    GrapplingSessionReportView(result: s, previousSessions: [])
                }
            }
        }
        .overlay(alignment: .topLeading) {
            backButton
                .padding(.top, 56)
                .padding(.leading, 16)
        }
        .overlay(alignment: .topTrailing) {
            Button {
                showOnboarding = true
            } label: {
                Image(systemName: "info.circle")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(Color.white.opacity(0.75))
            }
            .padding(.top, 62)
            .padding(.trailing, 16)
        }
        .alert(
            "Camera Error",
            isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.clearError() } }
            ),
            actions: {
                Button("Dismiss") {
                    viewModel.clearError()
                    dismiss()
                }
            },
            message: {
                if let msg = viewModel.errorMessage {
                    Text(msg)
                }
            }
        )
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

    // MARK: - Subviews

    /// Camera flip button anchored to the top-right corner, below the status bar.
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
            .padding(.top, 104)
            Spacer()
        }
    }

    /// Full-screen live camera feed.
    private var cameraLayer: some View {
        CameraPreviewView(cameraManager: appState.cameraManager)
            .ignoresSafeArea()
    }

    /// Skeleton overlay + CoM dot stacked over the camera feed.
    private var overlayLayer: some View {
        ZStack {
            PoseOverlayView(
                pose: viewModel.currentPose,
                activeJoints: GrapplingAnalytics.activeJoints,
                color: .kineticsOrange
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)

            centerOfMassDot
        }
    }

    /// Animated orange/red dot tracking the athlete's computed center of mass.
    ///
    /// Coordinate mapping:
    /// - Vision x (0..1, left-to-right) → screen x unchanged.
    /// - Vision y (0..1, bottom-to-top) → screen y is flipped: `(1 - y) * height`.
    private var centerOfMassDot: some View {
        GeometryReader { geo in
            if viewModel.metrics.centerOfMass != .zero {
                let screenX = viewModel.metrics.centerOfMass.x * geo.size.width
                let screenY = (1.0 - viewModel.metrics.centerOfMass.y) * geo.size.height

                Circle()
                    .fill(
                        viewModel.metrics.isPosturalAlert
                            ? Color.kineticsRed
                            : Color.kineticsOrange
                    )
                    .frame(width: 16, height: 16)
                    .shadow(
                        color: (viewModel.metrics.isPosturalAlert
                            ? Color.kineticsRed
                            : Color.kineticsOrange).opacity(0.7),
                        radius: 10
                    )
                    .overlay(
                        // Subtle outer ring for visibility against varied backgrounds.
                        Circle()
                            .strokeBorder(Color.white.opacity(0.4), lineWidth: 1.5)
                    )
                    .position(x: screenX, y: screenY)
                    .animation(.easeInOut(duration: 0.1), value: viewModel.metrics.centerOfMass)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    /// Module identifier badge in the top-left corner.
    private var moduleLabel: some View {
        HStack(spacing: 6) {
            Image(systemName: "person.2.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.kineticsOrange)

            Text("GRAPPLING LAB")
                .font(.system(size: 11, weight: .bold))
                .tracking(2.0)
                .foregroundStyle(Color.white)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(Color.black.opacity(0.55))
                .overlay(
                    Capsule()
                        .strokeBorder(Color.kineticsOrange.opacity(0.45), lineWidth: 1)
                )
        )
    }

    /// Red alert banner shown when the CoM exits the support polygon.
    private var posturalAlertBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.white)

            Text("BASE COMPROMISED")
                .font(.system(size: 12, weight: .bold))
                .tracking(1.5)
                .foregroundStyle(Color.white)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.kineticsRed.opacity(0.90))
                .shadow(color: Color.kineticsRed.opacity(0.6), radius: 12)
        )
        .animation(.easeInOut(duration: 0.2), value: viewModel.metrics.isPosturalAlert)
    }

    /// Back button overlay anchored to the top-leading corner.
    private var backButton: some View {
        Button {
            Task {
                await viewModel.endSession(
                    userId: appState.authManager.currentUser?.uid ?? ""
                )
                viewModel.stopProcessing()
                appState.cameraManager.stopSession()
                if viewModel.lastCompletedSession != nil {
                    showReport = true
                } else {
                    dismiss()
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .semibold))
                Text("Back")
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundStyle(Color.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(Color.black.opacity(0.55))
            )
        }
    }

    // MARK: - Metrics Panel

    /// Bottom safe-area metrics card with all live analytics for the session.
    private var metricsPanel: some View {
        MetricsCardView {
            VStack(spacing: 10) {
                primaryBadgeRow
                Divider()
                    .background(Color.white.opacity(0.12))
                secondaryMetricRows
            }
        }
    }

    /// Top row: three primary metric badges (spine angle, kuzushi index, position).
    private var primaryBadgeRow: some View {
        HStack(spacing: 0) {
            MetricBadge(
                value: viewModel.metrics.spineAngleDisplay,
                label: "Spine Lean",
                color: spineAngleColor
            )
            .frame(maxWidth: .infinity)

            dividerLine

            MetricBadge(
                value: viewModel.metrics.kuzushiDisplay,
                label: "Kuzushi /100",
                color: kuzushiColor
            )
            .frame(maxWidth: .infinity)

            dividerLine

            MetricBadge(
                value: viewModel.metrics.positionDisplay,
                label: "Position",
                color: Color.kineticsOrange
            )
            .frame(maxWidth: .infinity)
        }
    }

    /// Thin vertical separator between badge columns.
    private var dividerLine: some View {
        Rectangle()
            .fill(Color.white.opacity(0.12))
            .frame(width: 1, height: 36)
    }

    /// Secondary rows: base stability, session timer, and coaching cue.
    private var secondaryMetricRows: some View {
        VStack(spacing: 6) {
            MetricRow(
                label: "Base Stability",
                value: viewModel.metrics.baseStabilityDisplay,
                color: viewModel.metrics.isBaseStable ? Color.kineticsGreen : Color.kineticsRed
            )
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
                    Spacer()
                    Text("SESSION")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.50))
                        .tracking(1.0)
                }
                .padding(.horizontal, 4)
            } else {
                MetricRow(
                    label: "Session",
                    value: formattedDuration,
                    color: Color.white.opacity(0.80)
                )
            }
        }
    }

    // MARK: - Helpers

    /// Formats `sessionDuration` as M:SS for the metrics row.
    private var formattedDuration: String {
        let total = Int(viewModel.sessionDuration)
        let minutes = total / 60
        let seconds = total % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    /// Color-codes spine angle: green (good) → orange (moderate) → red (severe).
    private var spineAngleColor: Color {
        switch viewModel.metrics.spineAngleDegrees {
        case ..<15: return Color.kineticsGreen
        case 15..<30: return Color.kineticsOrange
        default: return Color.kineticsRed
        }
    }

    /// Color-codes the kuzushi index: neutral until high, then orange, then green
    /// (a high kuzushi is positive — it means you have structural advantage).
    private var kuzushiColor: Color {
        switch viewModel.metrics.kuzushiIndex {
        case ..<30: return Color.white.opacity(0.6)
        case 30..<60: return Color.kineticsOrange
        default: return Color.kineticsGreen
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

// MARK: - Preview

#Preview {
    GrapplingView()
        .environment(AppState.preview)
}
