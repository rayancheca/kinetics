import ActivityKit
import SwiftUI
import WidgetKit

// MARK: - LiveSessionWidget

/// Live Activity widget that renders the in-progress Kinetics training session
/// on the iPhone lock screen and inside the Dynamic Island.
///
/// The widget receives `LiveSessionAttributes` (static, set when the activity
/// starts) and `LiveSessionAttributes.ContentState` (dynamic, updated as the
/// session progresses).
///
/// All UI is dark-themed and matches the in-app design system so the lock
/// screen feels like a true extension of the live session screen.
@available(iOS 16.2, *)
struct LiveSessionWidget: Widget {

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LiveSessionAttributes.self) { context in
            LiveSessionLockScreenView(
                attributes: context.attributes,
                state: context.state
            )
            .activityBackgroundTint(Color.black.opacity(0.85))
            .activitySystemActionForegroundColor(Color.white)

        } dynamicIsland: { context in
            DynamicIsland {
                // MARK: Expanded regions
                DynamicIslandExpandedRegion(.leading) {
                    expandedLeading(attributes: context.attributes, state: context.state)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    expandedTrailing(state: context.state)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.attributes.displayName)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.6))
                        .tracking(1.4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    expandedBottom(attributes: context.attributes, state: context.state)
                }
            } compactLeading: {
                Image(systemName: context.attributes.iconName)
                    .foregroundStyle(Color(liveActivityHex: context.attributes.accentHex))

            } compactTrailing: {
                Text(timerInterval: context.attributes.startedAt ... .distantFuture,
                     countsDown: false,
                     showsHours: false)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Color(liveActivityHex: context.attributes.accentHex))
                    .frame(maxWidth: 56)

            } minimal: {
                Image(systemName: context.attributes.iconName)
                    .foregroundStyle(Color(liveActivityHex: context.attributes.accentHex))
            }
            .widgetURL(URL(string: "kinetics://train"))
            .keylineTint(Color(liveActivityHex: context.attributes.accentHex))
        }
    }

    // MARK: - Dynamic Island Regions

    @ViewBuilder
    private func expandedLeading(
        attributes: LiveSessionAttributes,
        state: LiveSessionAttributes.ContentState
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: attributes.iconName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(liveActivityHex: attributes.accentHex))
                Text(attributes.displayName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }
            Text(state.primaryMetric)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
            Text(state.primaryLabel.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white.opacity(0.45))
                .tracking(1.2)
        }
    }

    @ViewBuilder
    private func expandedTrailing(state: LiveSessionAttributes.ContentState) -> some View {
        VStack(alignment: .trailing, spacing: 4) {
            if state.isPaused {
                Label("PAUSED", systemImage: "pause.circle.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.orange)
            } else {
                Label("LIVE", systemImage: "circle.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.red)
            }
            if !state.secondaryMetric.isEmpty {
                Text(state.secondaryMetric)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                Text(state.secondaryLabel.uppercased())
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.45))
                    .tracking(1.2)
            }
        }
    }

    @ViewBuilder
    private func expandedBottom(
        attributes: LiveSessionAttributes,
        state: LiveSessionAttributes.ContentState
    ) -> some View {
        VStack(spacing: 6) {
            if let cue = state.coachCue, !cue.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color(liveActivityHex: attributes.accentHex))
                    Text(cue)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(2)
                    Spacer()
                }
            }
            HStack {
                Text(timerInterval: attributes.startedAt ... .distantFuture,
                     countsDown: false)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.75))
                Spacer()
                Text("TAP TO RESUME")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white.opacity(0.4))
                    .tracking(1.2)
            }
        }
    }
}

// MARK: - LiveSessionLockScreenView

@available(iOS 16.2, *)
struct LiveSessionLockScreenView: View {

    let attributes: LiveSessionAttributes
    let state: LiveSessionAttributes.ContentState

    private var accent: Color { Color(liveActivityHex: attributes.accentHex) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            metricsRow
            if let cue = state.coachCue, !cue.isEmpty {
                coachStrip(cue)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(accent.opacity(0.18))
                    .frame(width: 36, height: 36)
                Image(systemName: attributes.iconName)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(accent)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(attributes.displayName.uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(accent)
                    .tracking(1.5)
                Text(state.isPaused ? "Session Paused" : "Live Session")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
            }
            Spacer()
            Text(timerInterval: attributes.startedAt ... .distantFuture,
                 countsDown: false)
                .font(.system(size: 18, weight: .bold, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(.white)
                .frame(width: 86, alignment: .trailing)
        }
    }

    private var metricsRow: some View {
        HStack(alignment: .top, spacing: 12) {
            metricBlock(value: state.primaryMetric, label: state.primaryLabel, color: accent)
            if !state.secondaryMetric.isEmpty {
                Rectangle()
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 1, height: 36)
                metricBlock(value: state.secondaryMetric, label: state.secondaryLabel, color: .white)
            }
            Spacer()
        }
    }

    private func metricBlock(value: String, label: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(color)
            Text(label.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white.opacity(0.45))
                .tracking(1.2)
        }
    }

    private func coachStrip(_ cue: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(accent)
            Text(cue)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(2)
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(accent.opacity(0.3), lineWidth: 0.75)
                )
        )
    }
}
