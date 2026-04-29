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

    // MARK: Body

    var body: some View {
        ZStack(alignment: .top) {
            cameraLayer
            overlayLayer

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
        }
        .ignoresSafeArea()
        .background(Color.kineticsBackground)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            metricsPanel
        }
        .navigationBarHidden(true)
        .task {
            await viewModel.startProcessing(with: appState.cameraManager)
        }
        .overlay(alignment: .topLeading) {
            backButton
                .padding(.top, 56)
                .padding(.leading, 16)
        }
        .alert(
            "Camera Error",
            isPresented: .constant(viewModel.errorMessage != nil),
            actions: {
                Button("Dismiss") {
                    dismiss()
                }
            },
            message: {
                if let msg = viewModel.errorMessage {
                    Text(msg)
                }
            }
        )
    }

    // MARK: - Subviews

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
                appState.cameraManager.stopSession()
                dismiss()
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

    /// Secondary rows: base stability and session timer.
    private var secondaryMetricRows: some View {
        VStack(spacing: 6) {
            MetricRow(
                label: "Base Stability",
                value: viewModel.metrics.baseStabilityDisplay,
                color: viewModel.metrics.isBaseStable ? Color.kineticsGreen : Color.kineticsRed
            )
            MetricRow(
                label: "Session",
                value: formattedDuration,
                color: Color.white.opacity(0.80)
            )
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

// MARK: - Preview

#Preview {
    GrapplingView()
        .environment(AppState.preview)
}
