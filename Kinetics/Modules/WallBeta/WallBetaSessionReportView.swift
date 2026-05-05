import SwiftUI

// MARK: - WallBetaSessionReportView
// CoachingNoteCard, reportCard(), and sectionHeader() are defined in
// StrikingSessionReportView.swift and are visible across this target.

@MainActor
struct WallBetaSessionReportView: View {

    // MARK: Inputs

    let result: SessionResult
    let previousSessions: [SessionResult]

    // MARK: State

    @State private var coachingNotes: [CoachingNote] = []
    @Environment(\.dismiss) private var dismiss

    // MARK: Derived Metrics

    private var prevWall: SessionResult? {
        previousSessions
            .filter { $0.sport == .wallBeta }
            .sorted { $0.startedAt > $1.startedAt }
            .first
    }

    private var hipProximity: Double     { result.metrics["hip_proximity_score"]    ?? 0 }
    private var sagEvents: Double        { result.metrics["sag_events"]             ?? 0 }
    private var dynoSmoothness: Double   { result.metrics["dyno_arc_smoothness"]    ?? 0 }
    private var avgHoldTime: Double      { result.metrics["time_under_tension_avg"] ?? 0 }

    private func delta(key: String) -> Double? {
        guard let prev = prevWall?.metrics[key],
              let current = result.metrics[key] else { return nil }
        return current - prev
    }

    // MARK: Hip Proximity Helpers

    private var hipQualityLabel: String {
        let pct = hipProximity * 100
        switch pct {
        case 75...: return "Solid"
        case 50..<75: return "Developing"
        default: return "Needs Work"
        }
    }

    private var hipQualityColor: Color {
        let pct = hipProximity * 100
        switch pct {
        case 75...: return Color.kineticsGreen
        case 50..<75: return Color.kineticsOrange
        default: return Color.kineticsRed
        }
    }

    // MARK: Sag Event Helpers

    private var sagLabel: String {
        let count = Int(sagEvents)
        switch count {
        case 0:     return "Perfect"
        case 1...2: return "Minor"
        default:    return "Core Needed"
        }
    }

    private var sagColor: Color {
        let count = Int(sagEvents)
        switch count {
        case 0:     return Color.kineticsGreen
        case 1...2: return Color.kineticsOrange
        default:    return Color.kineticsRed
        }
    }

    // MARK: Hold Time Helpers

    private var holdTimeLabel: String {
        switch avgHoldTime {
        case ..<2:  return "Decisive"
        case 2...3: return "Steady"
        default:    return "Hesitant"
        }
    }

    private var holdTimeColor: Color {
        switch avgHoldTime {
        case ..<2:  return Color.kineticsGreen
        case 2...3: return Color.kineticsBlue
        default:    return Color.kineticsOrange
        }
    }

    private var holdTimeCue: String? {
        guard avgHoldTime > 3 else { return nil }
        return "Long pauses on holds burn arm strength fast. Try committing to the next move within 2 seconds of stabilising."
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
                    if dynoSmoothness > 0 {
                        dynoSection
                    }
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
            Label("WALL BETA", systemImage: "figure.climbing")
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.5)
                .foregroundStyle(Color.kineticsGreen.opacity(0.8))
        }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(result.startedAt.formatted(date: .complete, time: .omitted))
                .font(.system(size: 30, weight: .black))
                .foregroundStyle(.white)

            Label(result.formattedDuration, systemImage: "clock")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.5))
        }
    }

    private var metricsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("SESSION METRICS")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    hipProximityCard
                    sagEventsCard
                    holdTimeCard
                }
                .padding(.horizontal, 1)
            }
        }
    }

    private var hipProximityCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("HIP PROXIMITY")
                .font(.system(size: 9, weight: .semibold))
                .tracking(2)
                .foregroundStyle(.white.opacity(0.4))

            HStack(alignment: .lastTextBaseline, spacing: 3) {
                Text("\(Int(hipProximity * 100))%")
                    .font(.system(size: 44, weight: .black, design: .rounded))
                    .foregroundStyle(Color.kineticsGreen)
            }

            Text(hipQualityLabel)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(hipQualityColor)

            if let d = delta(key: "hip_proximity_score") {
                Text(String(format: "%+.0f%%", d * 100))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(d >= 0 ? Color.kineticsGreen : Color.kineticsRed)
            }
        }
        .frame(width: 160)
        .reportCard()
    }

    private var sagEventsCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("HIP SAG EVENTS")
                .font(.system(size: 9, weight: .semibold))
                .tracking(2)
                .foregroundStyle(.white.opacity(0.4))

            HStack(alignment: .lastTextBaseline, spacing: 3) {
                Text("\(Int(sagEvents))")
                    .font(.system(size: 44, weight: .black, design: .rounded))
                    .foregroundStyle(sagColor)
            }

            Text(sagLabel)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(sagColor)
        }
        .frame(width: 160)
        .reportCard()
    }

    private var holdTimeCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("AVG HOLD TIME")
                .font(.system(size: 9, weight: .semibold))
                .tracking(2)
                .foregroundStyle(.white.opacity(0.4))

            HStack(alignment: .lastTextBaseline, spacing: 3) {
                Text(String(format: "%.1f", avgHoldTime))
                    .font(.system(size: 44, weight: .black, design: .rounded))
                    .foregroundStyle(holdTimeColor)
                Text("s")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.5))
            }

            Text(holdTimeLabel)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(holdTimeColor)

            if let cue = holdTimeCue {
                Text(cue)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.5))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(width: 200)
        .reportCard()
    }

    private var dynoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("DYNO ARC")

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(dynoSmoothness >= 0.7 ? "Clean arc" : "Choppy — work explosive hip drive")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.8))
                    Spacer()
                    Text("\(Int(dynoSmoothness * 100))%")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(dynoSmoothness >= 0.7 ? Color.kineticsGreen : Color.kineticsOrange)
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(.white.opacity(0.1))
                            .frame(height: 6)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(dynoSmoothness >= 0.7 ? Color.kineticsGreen : Color.kineticsOrange)
                            .frame(width: geo.size.width * dynoSmoothness, height: 6)
                    }
                }
                .frame(height: 6)
            }
            .reportCard()
        }
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
                    .foregroundStyle(Color.kineticsGreen)
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
        Wall Beta
        Hip Proximity: \(Int(hipProximity * 100))% (\(hipQualityLabel))
        Sag Events: \(Int(sagEvents)) — \(sagLabel)
        Avg Hold Time: \(String(format: "%.1f", avgHoldTime))s (\(holdTimeLabel))
        \(coachingNotes.first?.headline ?? "")
        """

        return HStack(spacing: 12) {
            Button { dismiss() } label: {
                Text("Done")
                    .font(.system(size: 16, weight: .semibold))
                    // kineticsGreen is very bright — use dark text for contrast
                    .foregroundStyle(Color.kineticsDark)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Color.kineticsGreen)
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
