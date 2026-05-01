import SwiftUI
import UIKit

// MARK: - CoachOverlayView

/// Premium coaching overlay that floats at the TOP of each sport module's camera feed.
///
/// Displays the current `CoachCue` as an icon + text pill that slides in from the top
/// with a spring animation. The pill auto-dismisses after a duration that depends on
/// priority: info cues vanish after 4 seconds, warning/critical after 6 seconds.
///
/// Priority drives both color and haptics:
/// - `.info`     → kineticsBlue icon, no haptic
/// - `.warning`  → kineticsAmber icon, no haptic
/// - `.critical` → Color.red icon + UINotificationFeedbackGenerator.warning haptic
///
/// Usage (inside a ZStack on the camera overlay):
/// ```swift
/// CoachOverlayView(cue: viewModel.currentCoachCue)
///     .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
///     .padding(.top, 100)
///     .allowsHitTesting(false)
/// ```
struct CoachOverlayView: View {

    // MARK: - Input

    let cue: CoachCue?

    // MARK: - Private State

    @State private var visibleCue: CoachCue?
    @State private var isVisible: Bool = false
    @State private var dismissTask: Task<Void, Never>?

    // MARK: - Auto-dismiss durations

    private func dismissDuration(for priority: CoachCue.Priority) -> TimeInterval {
        switch priority {
        case .info:              return 4.0
        case .warning, .critical: return 6.0
        }
    }

    // MARK: - Body

    var body: some View {
        VStack {
            if let activeCue = visibleCue, isVisible {
                cueLabel(activeCue)
                    .transition(
                        .asymmetric(
                            insertion: .move(edge: .top).combined(with: .opacity),
                            removal:   .opacity.combined(with: .scale(scale: 0.95))
                        )
                    )
            }
            Spacer()
        }
        .onChange(of: cue) { _, newCue in
            guard let newCue else { return }
            show(newCue)
        }
        .allowsHitTesting(false)
    }

    // MARK: - Cue Pill

    @ViewBuilder
    private func cueLabel(_ activeCue: CoachCue) -> some View {
        HStack(spacing: 10) {
            Image(systemName: activeCue.icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(iconColor(for: activeCue.priority))

            Text(activeCue.text)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.white)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.black.opacity(0.85))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(
                            iconColor(for: activeCue.priority).opacity(0.35),
                            lineWidth: 1
                        )
                )
        )
        .shadow(color: Color.black.opacity(0.5), radius: 12, x: 0, y: 4)
        .padding(.horizontal, 20)
    }

    // MARK: - Priority Color

    private func iconColor(for priority: CoachCue.Priority) -> Color {
        switch priority {
        case .info:     return Color.kineticsBlue
        case .warning:  return Color.kineticsAmber
        case .critical: return Color.red
        }
    }

    // MARK: - Show / Dismiss Logic

    private func show(_ newCue: CoachCue) {
        dismissTask?.cancel()

        // Trigger haptic for critical cues.
        if newCue.priority == .critical {
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.warning)
        }

        withAnimation(.spring(response: 0.38, dampingFraction: 0.72)) {
            visibleCue = newCue
            isVisible = true
        }

        let duration = dismissDuration(for: newCue.priority)
        dismissTask = Task { [duration] in
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.25)) {
                    isVisible = false
                }
            }
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    ZStack {
        Color.black.ignoresSafeArea()

        CoachOverlayView(
            cue: CoachCue(
                text: "Rotate your hips FIRST — lead with the core, not the arm",
                priority: .warning,
                metric: "hipShoulderSeparation",
                icon: "rotate.right"
            )
        )
        .padding(.top, 80)
    }
}
#endif
