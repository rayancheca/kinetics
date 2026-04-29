import SwiftUI

struct SessionDetailView: View {
    let session: SessionResult
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @State private var showDeleteConfirm = false

    // MARK: - Metric Display Config

    private let metricLabels: [String: (label: String, format: (Double) -> String)] = [
        "peak_velocity_mph":      ("Peak Strike Velocity",  { String(format: "%.1f mph", $0) }),
        "strike_count":           ("Strikes Detected",      { "\(Int($0))" }),
        "kinematic_score":        ("Kinematic Chain",       { "\(Int($0))/100" }),
        "hip_shoulder_sep":       ("Hip-Shoulder Sep.",     { String(format: "%.1f°", $0) }),
        "kuzushi_index":          ("Kuzushi Index",         { "\(Int($0))/100" }),
        "base_stability":         ("Base Stability",        { "\(Int($0 * 100))%" }),
        "postural_breaks":        ("Postural Breaks",       { "\(Int($0))" }),
        "com_control":            ("CoM Control",           { "\(Int($0 * 100))%" }),
        "bar_path_deviation_cm":  ("Bar Deviation",         { String(format: "%.1f cm", $0) }),
        "vbt_velocity_ms":        ("VBT Speed",             { String(format: "%.2f m/s", $0) }),
        "bilateral_symmetry":     ("Bilateral Symmetry",    { "\(Int($0 * 100))%" }),
        "butt_wink_angle":        ("Pelvic Tilt",           { String(format: "%.0f°", $0) }),
        "hip_proximity_score":    ("Hip Proximity",         { "\(Int($0 * 100))%" }),
        "sag_events":             ("Hip Sag Events",        { "\(Int($0))" }),
        "dyno_arc_smoothness":    ("Dyno Arc",              { "\(Int($0 * 100))% smooth" }),
        "time_under_tension_avg": ("Avg Hold Time",         { String(format: "%.1f s", $0) }),
    ]

    private let knownOrder = [
        "peak_velocity_mph", "strike_count", "kinematic_score", "hip_shoulder_sep",
        "kuzushi_index", "base_stability", "postural_breaks", "com_control",
        "bar_path_deviation_cm", "vbt_velocity_ms", "bilateral_symmetry", "butt_wink_angle",
        "hip_proximity_score", "sag_events", "dyno_arc_smoothness", "time_under_tension_avg"
    ]

    private var accent: Color { Color.moduleColor(for: session.sport) }

    private var sortedMetricKeys: [String] {
        session.metrics.keys.sorted { a, b in
            let ai = knownOrder.firstIndex(of: a) ?? 999
            let bi = knownOrder.firstIndex(of: b) ?? 999
            return ai < bi
        }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    sessionHeader
                    metricsSection
                    if !session.coachingNotes.isEmpty { coachingSection }
                    deleteButton
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
            }
            .background(Color.kineticsBackground)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Color.kineticsBlue)
                }
            }
            .confirmationDialog(
                "Delete this session?",
                isPresented: $showDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    Task {
                        if let uid = appState.authManager.currentUser?.uid {
                            try? await SessionRepository.shared.deleteSession(
                                id: session.id,
                                userId: uid
                            )
                        }
                        dismiss()
                    }
                }
            }
        }
    }

    // MARK: - Subviews

    private var sessionHeader: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(accent.opacity(0.14))
                    .frame(width: 52, height: 52)
                Image(systemName: session.sport.systemImage)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(accent)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(session.sport.displayName)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
                Text(session.formattedDate)
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.45))
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(session.formattedDuration)
                    .font(.system(size: 22, weight: .black, design: .monospaced))
                    .foregroundStyle(.white)
                Text("SESSION \(session.sessionNumber)")
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(1.5)
                    .foregroundStyle(accent.opacity(0.7))
            }
        }
    }

    private var metricsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("METRICS")
                .font(.system(size: 10, weight: .semibold))
                .tracking(2.5)
                .foregroundStyle(.white.opacity(0.38))

            VStack(spacing: 0) {
                ForEach(Array(sortedMetricKeys.enumerated()), id: \.element) { idx, key in
                    let info = metricLabels[key]
                    let label = info?.label ?? key
                    let rawValue = session.metrics[key] ?? 0
                    let value = info?.format(rawValue) ?? String(format: "%.2f", rawValue)

                    HStack {
                        Text(label)
                            .font(.system(.caption))
                            .foregroundStyle(.white.opacity(0.55))
                        Spacer()
                        Text(value)
                            .font(.system(.caption, design: .rounded, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)

                    if idx < sortedMetricKeys.count - 1 {
                        Divider()
                            .background(.white.opacity(0.06))
                            .padding(.horizontal, 14)
                    }
                }
            }
            .background(Color.kineticsDark)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private var coachingSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("COACHING NOTES")
                .font(.system(size: 10, weight: .semibold))
                .tracking(2.5)
                .foregroundStyle(.white.opacity(0.38))

            VStack(spacing: 10) {
                ForEach(session.coachingNotes) { note in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: note.icon)
                            .font(.system(size: 16))
                            .foregroundStyle(accent)
                            .frame(width: 32, height: 32)
                            .background(accent.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 8))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(note.headline)
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(.white)
                            Text(note.detail)
                                .font(.system(size: 12))
                                .foregroundStyle(.white.opacity(0.55))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(12)
                    .background(Color(red: 0.09, green: 0.09, blue: 0.09))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }

    private var deleteButton: some View {
        Button { showDeleteConfirm = true } label: {
            Text("Delete Session")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.kineticsRed)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(Color.kineticsRed.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .padding(.bottom, 40)
    }
}
