import SwiftUI

// MARK: - MetricsCardView

/// Semi-transparent bottom panel that surfaces real-time analytics for any sport module.
///
/// Intended as the content of `.safeAreaInset(edge: .bottom)` so it never occludes
/// the camera feed above it. The electric blue top border keeps it visually anchored
/// to the Kinetics design system regardless of which sport module is active.
///
/// Usage:
/// ```swift
/// CameraPreviewView(cameraManager: cameraManager)
///     .ignoresSafeArea()
///     .safeAreaInset(edge: .bottom, spacing: 0) {
///         MetricsCardView {
///             HStack {
///                 MetricBadge(value: "47", label: "mph")
///                 MetricBadge(value: "0.82", label: "chain", color: .kineticsBlue)
///             }
///         }
///     }
/// ```
struct MetricsCardView<Content: View>: View {

    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 16)
            .frame(maxWidth: .infinity)
            .background(
                // Build the layered background manually because `.ultraThinMaterial`
                // alone is too transparent against a bright outdoor scene.
                ZStack(alignment: .top) {
                    // Blur material for depth.
                    Rectangle()
                        .fill(.ultraThinMaterial)
                    // Dark overlay to ensure metric text remains legible over any background.
                    Rectangle()
                        .fill(Color.black.opacity(0.60))
                    // Electric blue top border — 1 pt accent line.
                    Rectangle()
                        .frame(height: 1)
                        .foregroundStyle(Color.kineticsBlue.opacity(0.60))
                }
            )
    }
}

// MARK: - MetricBadge

/// A vertically-stacked value + label pair for displaying a single real-time metric.
///
/// The value text transitions smoothly when the numeric string changes.
/// Pass `isAlert: true` to display the value in warning red (e.g. postural breakdown).
///
/// ```swift
/// MetricBadge(value: "\(Int(strikeVelocity))", label: "mph")
/// MetricBadge(value: "HIGH", label: "risk", color: .kineticsOrange, isAlert: true)
/// ```
struct MetricBadge: View {

    let value: String
    let label: String
    var color: Color = .kineticsGreen
    var isAlert: Bool = false

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(.title2, design: .rounded, weight: .bold))
                .foregroundStyle(isAlert ? Color.kineticsRed : color)
                .monospacedDigit()
                // Smooth numeric transitions without jarring layout shifts.
                .contentTransition(.numericText())
                .animation(.easeInOut(duration: 0.2), value: value)

            Text(label.uppercased())
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.50))
                .tracking(1.2)
        }
    }
}

// MARK: - MetricRow

/// A horizontal label + value row for secondary or auxiliary metrics.
///
/// Intended to be stacked inside a `VStack` within `MetricsCardView` for less
/// prominent data that doesn't need the visual weight of a `MetricBadge`.
///
/// ```swift
/// MetricRow(label: "Hip-Shoulder Sep.", value: "34°", color: .kineticsBlue)
/// MetricRow(label: "Reset Time", value: "0.31 s")
/// ```
struct MetricRow: View {

    let label: String
    let value: String
    var color: Color = .white

    var body: some View {
        HStack {
            Text(label)
                .font(.system(.caption, design: .default, weight: .regular))
                .foregroundStyle(Color.white.opacity(0.60))

            Spacer()

            Text(value)
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .foregroundStyle(color)
                .monospacedDigit()
        }
    }
}

// MARK: - StatusBadge

/// A pill-shaped label indicating the current session state (e.g. "Live", "Paused", "Ready").
///
/// When `isActive` is true the badge inverts to a neon green fill with dark text,
/// signalling that the vision engine is processing frames.
///
/// ```swift
/// StatusBadge(text: "Live", isActive: viewModel.isDetecting)
/// ```
struct StatusBadge: View {

    let text: String
    var isActive: Bool = false

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .tracking(1.5)
            .foregroundStyle(isActive ? Color.kineticsDark : Color.white.opacity(0.50))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(isActive ? Color.kineticsGreen : Color.white.opacity(0.10))
            )
            .animation(.easeInOut(duration: 0.2), value: isActive)
    }
}
