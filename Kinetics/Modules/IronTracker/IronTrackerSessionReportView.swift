import SwiftUI

// MARK: - IronTrackerSessionReportView
// CoachingNoteCard, reportCard(), and sectionHeader() are defined in
// StrikingSessionReportView.swift and are visible across this target.

@MainActor
struct IronTrackerSessionReportView: View {

    // MARK: Inputs

    let result: SessionResult
    let previousSessions: [SessionResult]

    // MARK: State

    @State private var coachingNotes: [CoachingNote] = []
    @Environment(\.dismiss) private var dismiss

    // MARK: Derived Metrics

    private var prevIron: SessionResult? {
        previousSessions
            .filter { $0.sport == .ironTracker }
            .sorted { $0.startedAt > $1.startedAt }
            .first
    }

    private var barDeviation: Double    { result.metrics["bar_path_deviation_cm"] ?? 0 }
    private var vbtVelocity: Double     { result.metrics["vbt_velocity_ms"]       ?? 0 }
    private var bilateralSym: Double    { result.metrics["bilateral_symmetry"]    ?? 0 }
    private var buttWinkAngle: Double   { result.metrics["butt_wink_angle"]       ?? 0 }

    private func delta(key: String) -> Double? {
        guard let prev = prevIron?.metrics[key],
              let current = result.metrics[key] else { return nil }
        return current - prev
    }

    // MARK: Bar Deviation Helpers

    private var deviationColor: Color {
        switch barDeviation {
        case ..<2:   return Color.kineticsBlue
        case 2..<5:  return Color.kineticsOrange
        default:     return Color.kineticsRed
        }
    }

    private var deviationQuality: String {
        switch barDeviation {
        case ..<2:  return "Excellent"
        case 2..<5: return "Acceptable"
        default:    return "Needs Work"
        }
    }

    // MARK: VBT Zone Helpers

    private var vbtZoneLabel: String {
        switch vbtVelocity {
        case 1.0...: return "SPEED"
        case 0.6..<1.0: return "POWER"
        default: return "STRENGTH"
        }
    }

    private var vbtZoneColor: Color {
        switch vbtVelocity {
        case 1.0...: return Color.kineticsGreen
        case 0.6..<1.0: return Color.kineticsOrange
        default: return Color.kineticsBlue
        }
    }

    // MARK: Symmetry Helpers

    private var symmetryColor: Color {
        let pct = bilateralSym * 100
        switch pct {
        case 90...: return Color.kineticsGreen
        case 80..<90: return Color.kineticsOrange
        default: return Color.kineticsRed
        }
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
                    if buttWinkAngle > 10 {
                        buttWinkWarningCard
                    }
                    barPathVisualSection
                    aiCoachingSection
                    nextSessionSection
                    actionRow
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
            }
        }
        .navigationBarHidden(true)
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
            Label("IRON TRACKER", systemImage: "dumbbell.fill")
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.5)
                .foregroundStyle(Color.kineticsBlue.opacity(0.7))
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
                    barDeviationCard
                    vbtSpeedCard
                    bilateralSymCard
                }
                .padding(.horizontal, 1)
            }
        }
    }

    private var barDeviationCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("BAR DEVIATION")
                .font(.system(size: 9, weight: .semibold))
                .tracking(2)
                .foregroundStyle(.white.opacity(0.4))

            HStack(alignment: .lastTextBaseline, spacing: 3) {
                Text(String(format: "%.1f", barDeviation))
                    .font(.system(size: 44, weight: .black, design: .rounded))
                    .foregroundStyle(deviationColor)
                Text("cm")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.5))
            }

            Text(deviationQuality)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(deviationColor)
        }
        .frame(width: 160)
        .reportCard()
    }

    private var vbtSpeedCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("VBT SPEED")
                .font(.system(size: 9, weight: .semibold))
                .tracking(2)
                .foregroundStyle(.white.opacity(0.4))

            HStack(alignment: .lastTextBaseline, spacing: 3) {
                Text(String(format: "%.2f", vbtVelocity))
                    .font(.system(size: 44, weight: .black, design: .rounded))
                    .foregroundStyle(Color.kineticsBlue)
                Text("m/s")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.5))
            }

            Text(vbtZoneLabel)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(vbtZoneColor)

            if let d = delta(key: "vbt_velocity_ms") {
                Text(String(format: "%+.2f m/s", d))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(d >= 0 ? Color.kineticsGreen : Color.kineticsRed)
            }
        }
        .frame(width: 160)
        .reportCard()
    }

    private var bilateralSymCard: some View {
        let goal = 0.9
        let progress = min(bilateralSym / goal, 1.0)

        return VStack(alignment: .leading, spacing: 6) {
            Text("BILATERAL SYM")
                .font(.system(size: 9, weight: .semibold))
                .tracking(2)
                .foregroundStyle(.white.opacity(0.4))

            HStack(alignment: .lastTextBaseline, spacing: 3) {
                Text("\(Int(bilateralSym * 100))%")
                    .font(.system(size: 44, weight: .black, design: .rounded))
                    .foregroundStyle(symmetryColor)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("Goal: 90%+")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.4))

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(.white.opacity(0.1))
                            .frame(height: 4)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(symmetryColor)
                            .frame(width: geo.size.width * progress, height: 4)
                    }
                }
                .frame(height: 4)
            }
        }
        .frame(width: 180)
        .reportCard()
    }

    private var buttWinkWarningCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 18))
                .foregroundStyle(Color.kineticsOrange)

            Text("Pelvic tilt detected at \(Int(buttWinkAngle))° — reduce squat depth until hip mobility improves.")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(Color.kineticsOrange.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.kineticsOrange.opacity(0.3), lineWidth: 1)
        )
    }

    private var barPathVisualSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("BAR PATH TRACE")

            Canvas { context, size in
                let midY = size.height / 2
                let amplitude = barDeviation * 3
                let steps = Int(size.width)

                // Dashed ideal vertical line
                var dashPath = Path()
                dashPath.move(to: CGPoint(x: size.width / 2, y: 0))
                dashPath.addLine(to: CGPoint(x: size.width / 2, y: size.height))
                context.stroke(
                    dashPath,
                    with: .color(.white.opacity(0.2)),
                    style: StrokeStyle(lineWidth: 1, dash: [4, 4])
                )

                // Actual bar path: a sine-wave offset from centre
                var barPath = Path()
                for step in 0...steps {
                    let x = (size.width / Double(steps)) * Double(step)
                    let progress = Double(step) / Double(steps)
                    let sineY = midY + sin(progress * .pi * 2) * amplitude
                    if step == 0 {
                        barPath.move(to: CGPoint(x: x, y: sineY))
                    } else {
                        barPath.addLine(to: CGPoint(x: x, y: sineY))
                    }
                }
                context.stroke(
                    barPath,
                    with: .color(Color.kineticsBlue),
                    style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round)
                )
            }
            .frame(height: 80)
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
                    .foregroundStyle(Color.kineticsBlue)
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
        Iron Tracker
        Bar Deviation: \(String(format: "%.1f", barDeviation)) cm (\(deviationQuality))
        VBT Speed: \(String(format: "%.2f", vbtVelocity)) m/s — \(vbtZoneLabel)
        Bilateral Symmetry: \(Int(bilateralSym * 100))%
        \(coachingNotes.first?.headline ?? "")
        """

        return HStack(spacing: 12) {
            Button { dismiss() } label: {
                Text("Done")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Color.kineticsBlue)
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
