import SwiftUI

// MARK: - GrapplingSessionReportView
// CoachingNoteCard, reportCard(), and sectionHeader() are defined in
// StrikingSessionReportView.swift and are visible across this target.

@MainActor
struct GrapplingSessionReportView: View {

    // MARK: Inputs

    let result: SessionResult
    let previousSessions: [SessionResult]

    // MARK: State

    @State private var coachingNotes: [CoachingNote] = []
    @State private var showFeedComposer = false
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState

    // MARK: Derived Metrics

    private var prevGrappling: SessionResult? {
        previousSessions
            .filter { $0.sport == .grappling }
            .sorted { $0.startedAt > $1.startedAt }
            .first
    }

    private var kuzushi: Double       { result.metrics["kuzushi_index"]    ?? 0 }
    private var baseStability: Double { result.metrics["base_stability"]   ?? 0 }
    private var posturalBreaks: Double { result.metrics["postural_breaks"] ?? 0 }
    private var comControl: Double    { result.metrics["com_control"]      ?? 0 }

    private func delta(key: String) -> Double? {
        guard let prev = prevGrappling?.metrics[key],
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
                    comControlRow
                    aiCoachingSection
                    nextSessionSection
                    actionRow
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showFeedComposer) {
            PostComposerView(
                currentUserId: appState.authManager.currentUser?.uid ?? "preview-user",
                currentDisplayName: appState.authManager.currentUser?.displayName ?? "Athlete",
                username: appState.authManager.currentUser?.displayName?.lowercased().replacingOccurrences(of: " ", with: "_") ?? "athlete",
                initialCaption: "Grappling Lab session · \(result.formattedDuration)",
                initialActivity: PostComposerActivity(
                    kind: .sport(
                        type: result.sport.rawValue,
                        metrics: [
                    FeedMetric(label: "KUZUSHI", value: String(format: "%.0f", result.metrics["kuzushiIndex"] ?? 0), unit: ""),
                    FeedMetric(label: "BASE", value: String(format: "%.0f", result.metrics["base_width_cm"] ?? 0), unit: "cm"),
                    FeedMetric(label: "POSTURE", value: String(format: "%.0f", result.metrics["postural_score"] ?? 0), unit: "/100")
                ]
                    ),
                    sessionTitle: "\(result.sport.displayName) Session"
                ),
                onPost: { _ in }
            )
        }
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
            Label("GRAPPLING LAB", systemImage: "person.2.fill")
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.5)
                .foregroundStyle(Color.kineticsOrange.opacity(0.7))
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
                    kuzushiCard
                    baseStabilityCard
                    posturalBreaksCard
                }
                .padding(.horizontal, 1)
            }
        }
    }

    private var kuzushiCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("KUZUSHI INDEX")
                .font(.system(size: 9, weight: .semibold))
                .tracking(2)
                .foregroundStyle(.white.opacity(0.4))

            HStack(alignment: .lastTextBaseline, spacing: 3) {
                Text("\(Int(kuzushi))")
                    .font(.system(size: 44, weight: .black, design: .rounded))
                    .foregroundStyle(Color.kineticsOrange)
                Text("/100")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.5))
            }

            if let d = delta(key: "kuzushi_index") {
                Text(String(format: "%+.0f pts", d))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(d >= 0 ? Color.kineticsGreen : Color.kineticsRed)
            }
        }
        .frame(width: 160)
        .reportCard()
    }

    private var baseStabilityCard: some View {
        let goal = 0.8
        let progress = min(baseStability / goal, 1.0)

        return VStack(alignment: .leading, spacing: 6) {
            Text("BASE STABILITY")
                .font(.system(size: 9, weight: .semibold))
                .tracking(2)
                .foregroundStyle(.white.opacity(0.4))

            HStack(alignment: .lastTextBaseline, spacing: 3) {
                Text("\(Int(baseStability * 100))%")
                    .font(.system(size: 44, weight: .black, design: .rounded))
                    .foregroundStyle(Color.kineticsBlue)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("Goal: 80%+")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.4))

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(.white.opacity(0.1))
                            .frame(height: 4)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.kineticsBlue)
                            .frame(width: geo.size.width * progress, height: 4)
                    }
                }
                .frame(height: 4)
            }
        }
        .frame(width: 180)
        .reportCard()
    }

    private var posturalBreaksCard: some View {
        let breakCount = Int(posturalBreaks)
        let cardColor: Color = breakCount > 2 ? Color.kineticsRed : Color.kineticsOrange

        return VStack(alignment: .leading, spacing: 6) {
            Text("POSTURAL BREAKS")
                .font(.system(size: 9, weight: .semibold))
                .tracking(2)
                .foregroundStyle(.white.opacity(0.4))

            HStack(alignment: .lastTextBaseline, spacing: 3) {
                Text("\(breakCount)")
                    .font(.system(size: 44, weight: .black, design: .rounded))
                    .foregroundStyle(cardColor)
            }

            Text("0 is perfect")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.5))
        }
        .frame(width: 160)
        .reportCard()
    }

    private var comControlRow: some View {
        HStack {
            Image(systemName: "scope")
                .font(.system(size: 16))
                .foregroundStyle(Color.kineticsOrange.opacity(0.7))
            Text("CoM Control")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
            Spacer()
            Text("\(Int(comControl * 100))%")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
        }
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
                    .foregroundStyle(Color.kineticsOrange)
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
        Grappling Lab
        Kuzushi Index: \(Int(kuzushi))/100
        Base Stability: \(Int(baseStability * 100))%
        \(coachingNotes.first?.headline ?? "")
        """

        return VStack(spacing: 10) {
            Button { showFeedComposer = true } label: {
                HStack(spacing: 8) {
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Share to Feed")
                        .font(.system(size: 15, weight: .semibold))
                }
                .foregroundStyle(Color.kineticsDark)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(Color.kineticsOrange)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            HStack(spacing: 12) {
                Button { dismiss() } label: {
                    Text("Done")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Color.kineticsOrange)
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
        }
        .padding(.bottom, 40)
    }
}
