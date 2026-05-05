import SwiftUI

// MARK: - Shared Report Helpers
// These helpers are defined here and used across all four session report views
// within the same compilation target.

extension View {
    func reportCard() -> some View {
        self
            .padding(16)
            .background(Color(red: 0.09, green: 0.09, blue: 0.09))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(.white.opacity(0.07), lineWidth: 0.5)
            )
    }
}

func sectionHeader(_ text: String) -> some View {
    Text(text)
        .font(.system(size: 10, weight: .semibold))
        .tracking(2.5)
        .foregroundStyle(.white.opacity(0.38))
}

// MARK: - CoachingNoteCard
// Shared across all 4 report views — defined once here, visible to the full target.

struct CoachingNoteCard: View {
    let note: CoachingNote

    private var tint: Color {
        switch note.category {
        case "achievement": return Color(hex: "FFB800")
        case "strength":    return Color.kineticsGreen
        default:            return Color.kineticsBlue
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: note.icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 36, height: 36)
                .background(tint.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 3) {
                Text(note.headline)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                Text(note.detail)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .background(Color(red: 0.09, green: 0.09, blue: 0.09))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.white.opacity(0.07), lineWidth: 0.5)
        )
    }
}

// MARK: - StrikingSessionReportView

@MainActor
struct StrikingSessionReportView: View {

    // MARK: Inputs

    let result: SessionResult
    let previousSessions: [SessionResult]

    // MARK: State

    @State private var coachingNotes: [CoachingNote] = []
    @Environment(\.dismiss) private var dismiss

    // MARK: Derived Metrics

    private var prevStriking: SessionResult? {
        previousSessions
            .filter { $0.sport == .striking }
            .sorted { $0.startedAt > $1.startedAt }
            .first
    }

    private var peakVelocity: Double { result.metrics["peak_velocity_mph"] ?? 0 }
    private var strikeCount: Double  { result.metrics["strike_count"]       ?? 0 }
    private var chainScore: Double   { result.metrics["kinematic_score"]    ?? 0 }
    private var hipSep: Double       { result.metrics["hip_shoulder_sep"]   ?? 0 }

    private var isPersonalBest: Bool {
        guard !previousSessions.isEmpty else { return false }
        let prevBest = previousSessions
            .filter { $0.sport == .striking }
            .compactMap { $0.metrics["peak_velocity_mph"] }
            .max() ?? 0
        return peakVelocity > prevBest
    }

    private func delta(key: String) -> Double? {
        guard let prev = prevStriking?.metrics[key],
              let current = result.metrics[key] else { return nil }
        return current - prev
    }

    // MARK: Body

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    headerRow
                    titleBlock
                    metricsSection
                    aiCoachingSection
                    nextSessionSection
                    actionRow
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task {
            coachingNotes = CoachingEngine.generateNotes(
                for: result,
                previousSessions: previousSessions
            )
        }
    }

    // MARK: Sub-Views

    private var headerRow: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(.white.opacity(0.3))
            }
            Spacer()
            Label("STRIKING CLINIC", systemImage: "bolt.fill")
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.5)
                .foregroundStyle(Color.kineticsRed.opacity(0.7))
        }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(result.startedAt.formatted(date: .complete, time: .omitted))
                .font(.system(size: 30, weight: .black))
                .foregroundStyle(.white)

            HStack(spacing: 12) {
                Label(result.formattedDuration, systemImage: "clock")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.5))

                if strikeCount > 0 {
                    Label("\(Int(strikeCount)) strikes", systemImage: "figure.martial.arts")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
        }
    }

    private var metricsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("SESSION METRICS")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    peakVelocityCard
                    chainScoreCard
                    hipSepCard
                }
                .padding(.horizontal, 1)
            }
        }
    }

    private var peakVelocityCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("PEAK VELOCITY")
                .font(.system(size: 9, weight: .semibold))
                .tracking(2)
                .foregroundStyle(.white.opacity(0.4))

            HStack(alignment: .lastTextBaseline, spacing: 3) {
                Text(String(format: "%.1f", peakVelocity))
                    .font(.system(size: 44, weight: .black, design: .rounded))
                    .foregroundStyle(Color.kineticsRed)
                Text("mph")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.5))
            }

            if isPersonalBest {
                Label("Personal Best", systemImage: "trophy.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color(hex: "FFB800"))
            } else if let d = delta(key: "peak_velocity_mph") {
                Text(String(format: "%+.1f mph", d))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(d >= 0 ? Color.kineticsGreen : Color.kineticsRed)
            }
        }
        .frame(width: 160)
        .reportCard()
    }

    private var chainScoreCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("KINEMATIC CHAIN")
                .font(.system(size: 9, weight: .semibold))
                .tracking(2)
                .foregroundStyle(.white.opacity(0.4))

            HStack(alignment: .lastTextBaseline, spacing: 3) {
                Text("\(Int(chainScore))")
                    .font(.system(size: 44, weight: .black, design: .rounded))
                    .foregroundStyle(Color.kineticsBlue)
                Text("/100")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.5))
            }

            Text("Hips loading on \(Int(chainScore * 0.9))% of strikes")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.5))

            if let d = delta(key: "kinematic_score") {
                Text(String(format: "%+.0f pts", d))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(d >= 0 ? Color.kineticsGreen : Color.kineticsRed)
            }
        }
        .frame(width: 180)
        .reportCard()
    }

    private var hipSepCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("HIP-SHOULDER SEP")
                .font(.system(size: 9, weight: .semibold))
                .tracking(2)
                .foregroundStyle(.white.opacity(0.4))

            HStack(alignment: .lastTextBaseline, spacing: 3) {
                Text(String(format: "%.0f°", hipSep))
                    .font(.system(size: 44, weight: .black, design: .rounded))
                    .foregroundStyle(Color.kineticsOrange)
            }

            let goal = 35.0
            VStack(alignment: .leading, spacing: 3) {
                Text("Goal: 35°+")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.4))

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(.white.opacity(0.1))
                            .frame(height: 4)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.kineticsOrange)
                            .frame(width: geo.size.width * min(hipSep / goal, 1.0), height: 4)
                    }
                }
                .frame(height: 4)
            }
        }
        .frame(width: 180)
        .reportCard()
    }

    private var aiCoachingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("AI COACHING")

            if coachingNotes.isEmpty {
                ProgressView()
                    .tint(.white.opacity(0.3))
                    .frame(maxWidth: .infinity)
            } else {
                VStack(spacing: 10) {
                    ForEach(coachingNotes) { note in
                        CoachingNoteCard(note: note)
                    }
                }
            }
        }
    }

    private var nextSessionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("NEXT SESSION")

            HStack(spacing: 12) {
                Image(systemName: "arrow.right.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(Color.kineticsRed)
                Text(CoachingEngine.nextSessionGoal(for: result))
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white)
            }
            .reportCard()
        }
    }

    private var actionRow: some View {
        let shareText = """
        Kinetics — \(result.startedAt.formatted(date: .abbreviated, time: .omitted))
        Striking Clinic
        Peak Velocity: \(String(format: "%.1f", peakVelocity)) mph
        Chain Score: \(Int(chainScore))/100
        \(coachingNotes.first?.headline ?? "")
        """

        return HStack(spacing: 12) {
            Button { dismiss() } label: {
                Text("Done")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Color.kineticsRed)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            ShareLink(item: shareText) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 50, height: 50)
                    .background(Color(red: 0.12, green: 0.12, blue: 0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding(.bottom, 40)
    }
}
