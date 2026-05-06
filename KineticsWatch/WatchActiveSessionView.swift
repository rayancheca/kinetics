import SwiftUI

// MARK: - WatchActiveSessionView

struct WatchActiveSessionView: View {
    @EnvironmentObject private var session: WatchSessionManager

    var body: some View {
        VStack(spacing: 0) {
            WatchMetricsHeader()

            Spacer(minLength: 6)

            WatchHeartRateRow()

            if let module = session.activeModule, module == "Track" {
                WatchTrackMetrics()
                    .padding(.top, 6)
            }

            Spacer(minLength: 6)

            WatchSessionControls()
        }
        .padding(.horizontal, 4)
    }
}

// MARK: - WatchMetricsHeader

struct WatchMetricsHeader: View {
    @EnvironmentObject private var session: WatchSessionManager

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(session.activeModule?.uppercased() ?? "ACTIVE")
                    .font(.system(.caption2, design: .rounded, weight: .bold))
                    .foregroundStyle(Color(red: 0, green: 0.76, blue: 1.0))

                Text(session.formattedElapsed)
                    .font(.system(.title2, design: .rounded, weight: .black))
                    .monospacedDigit()
            }

            Spacer()

            Circle()
                .fill(Color(red: 0.22, green: 0.82, blue: 0.38))
                .frame(width: 8, height: 8)
                .opacity(session.isSessionActive ? 1 : 0.3)
        }
    }
}

// MARK: - WatchHeartRateRow

struct WatchHeartRateRow: View {
    @EnvironmentObject private var session: WatchSessionManager

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "heart.fill")
                .foregroundStyle(.red)
                .font(.caption)

            if session.heartRate > 0 {
                Text("\(Int(session.heartRate))")
                    .font(.system(.title3, design: .rounded, weight: .bold))
                    .monospacedDigit()
                Text("BPM")
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(.secondary)
            } else {
                Text("--")
                    .font(.system(.title3, design: .rounded, weight: .bold))
                    .foregroundStyle(.secondary)
                Text("BPM")
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - WatchTrackMetrics

struct WatchTrackMetrics: View {
    @EnvironmentObject private var session: WatchSessionManager

    private var formattedDistance: String {
        let km = session.distance / 1000.0
        return String(format: "%.2f km", km)
    }

    private var formattedPace: String {
        guard session.pace > 0 else { return "--'--\"" }
        let totalSeconds = Int(60.0 / (session.pace / 1000.0))
        let min = totalSeconds / 60
        let sec = totalSeconds % 60
        return String(format: "%d'%02d\"", min, sec)
    }

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(formattedDistance)
                    .font(.system(.callout, design: .rounded, weight: .bold))
                    .monospacedDigit()
                Text("DIST")
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text(formattedPace)
                    .font(.system(.callout, design: .rounded, weight: .bold))
                    .monospacedDigit()
                Text("PACE")
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - WatchSessionControls

struct WatchSessionControls: View {
    @EnvironmentObject private var session: WatchSessionManager
    @State private var showEndConfirm = false

    var body: some View {
        HStack(spacing: 12) {
            Button {
                if session.isSessionActive {
                    session.pauseSession()
                } else {
                    session.startSession(module: session.activeModule ?? "Workout")
                }
            } label: {
                Image(systemName: session.isSessionActive ? "pause.fill" : "play.fill")
                    .font(.title3)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        Color(red: 0, green: 0.76, blue: 1.0),
                        in: RoundedRectangle(cornerRadius: 10)
                    )
            }
            .buttonStyle(.plain)

            Button {
                showEndConfirm = true
            } label: {
                Image(systemName: "xmark")
                    .font(.title3)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        Color.red.opacity(0.8),
                        in: RoundedRectangle(cornerRadius: 10)
                    )
            }
            .buttonStyle(.plain)
            .confirmationDialog("End Session?", isPresented: $showEndConfirm) {
                Button("End", role: .destructive) { session.endSession() }
                Button("Cancel", role: .cancel) {}
            }
        }
    }
}
