import FirebaseAnalytics
import SwiftUI

// MARK: - TrainView

struct TrainView: View {

    @Environment(AppState.self) private var appState
    @State private var vm = TrainViewModel()
    @State private var showPerformance = false

    private var uid: String {
        appState.authManager.currentUser?.uid ?? "preview-user"
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    headerBlock
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                        .padding(.bottom, 20)

                    recommendationBlock
                        .padding(.horizontal, 16)
                        .padding(.bottom, 24)

                    modulesBlock
                        .padding(.bottom, 24)

                    toolsBlock
                        .padding(.horizontal, 16)
                        .padding(.bottom, 80)
                }
            }
            .background(Color.kineticsBackground)
            .navigationBarHidden(true)
            .navigationDestination(for: SportType.self) { sport in
                SportDetailView(
                    sport: sport,
                    sessions: vm.sessions.filter { $0.sport == sport }
                )
            }
            .sheet(isPresented: $showPerformance) {
                TrainPerformanceView()
            }
            .task {
                await vm.load(userId: uid)
            }
        }
    }

    // MARK: - Header Block

    private var headerBlock: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("TRAIN")
                        .font(.system(size: 32, weight: .black))
                        .tracking(6)
                        .foregroundStyle(.white)
                    Text(vm.headerSubtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(Color.kineticsSubtext)
                }
                Spacer()
                TrainStreakHeader(streak: vm.streak, subtitle: "day streak")
            }

            TrainWeeklyCalendarStrip(trainedDays: vm.trainedDaysThisWeek)
        }
    }

    // MARK: - Recommendation Block

    private var recommendationBlock: some View {
        TrainRecommendationCard(
            sport: vm.recommendedSport,
            reason: vm.recommendationReason
        )
    }

    // MARK: - Modules Block (2×2 Bento Grid)

    private var modulesBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("MODULES")
                .padding(.horizontal, 20)

            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible())],
                spacing: 12
            ) {
                ForEach(SportType.allCases, id: \.self) { sport in
                    NavigationLink(value: sport) {
                        SportBentoCard(
                            sport: sport,
                            sessionCount: vm.sessionCount(for: sport),
                            lastSessionDate: vm.lastSessionDate(for: sport),
                            bestMetric: vm.bestMetric(for: sport)?.value,
                            bestMetricLabel: vm.bestMetric(for: sport)?.label ?? "",
                            onTap: {}
                        )
                    }
                    .buttonStyle(ScaleButtonStyle())
                }
            }
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Tools Block

    private var toolsBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("TOOLS")

            HStack(spacing: 12) {
                NavigationLink(destination: VideoLibraryView(userId: uid)) {
                    VideoAnalysisQuickCard()
                }
                .buttonStyle(ScaleButtonStyle())

                Button {
                    showPerformance = true
                } label: {
                    PerformanceQuickCard()
                }
                .buttonStyle(ScaleButtonStyle())
            }
        }
    }

    // MARK: - Helpers

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .tracking(2.5)
            .foregroundStyle(Color.kineticsSubtext)
    }
}

// MARK: - TrainViewModel

@Observable
@MainActor
final class TrainViewModel {

    // MARK: State

    var sessions: [SessionResult] = []
    var streak: Int = 0
    var trainedDaysThisWeek: Set<Int> = []
    var recommendedSport: SportType = .striking
    var recommendationReason: String = ""
    var isLoading = false

    // MARK: Computed

    var headerSubtitle: String {
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: Date())
        let greeting: String
        switch hour {
        case 0..<12: greeting = "Good morning"
        case 12..<17: greeting = "Good afternoon"
        default: greeting = "Good evening"
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        let day = formatter.string(from: Date())
        return "\(greeting) — \(day)"
    }

    // MARK: Load

    func load(userId: String) async {
        isLoading = true
        defer { isLoading = false }

        guard let fetched = try? await SessionRepository.shared
            .fetchSessions(for: userId, limit: 30) else { return }

        sessions = fetched
        computeStreak()
        computeTrainedDaysThisWeek()
        computeRecommendation()
    }

    // MARK: Accessors

    func sessionCount(for sport: SportType) -> Int {
        sessions.filter { $0.sport == sport }.count
    }

    func lastSessionDate(for sport: SportType) -> Date? {
        sessions.first(where: { $0.sport == sport })?.startedAt
    }

    func bestMetric(for sport: SportType) -> (value: Double, label: String)? {
        let sportSessions = sessions.filter { $0.sport == sport }
        guard !sportSessions.isEmpty else { return nil }

        let key: String
        let label: String
        switch sport {
        case .striking:
            key = "strikeVelocityMPH"
            label = "mph"
        case .grappling:
            key = "kuzushiIndex"
            label = "kuzushi"
        case .ironTracker:
            key = "barVelocityMS"
            label = "m/s"
        case .wallBeta:
            key = "hipProximityScore"
            label = "hip score"
        }

        let best = sportSessions.compactMap { $0.metrics[key] }.max()
        guard let best else { return nil }
        return (best, label)
    }

    // MARK: Private — Streak

    private func computeStreak() {
        guard !sessions.isEmpty else {
            streak = 0
            return
        }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        var trainedDays = Set<Date>()
        for session in sessions {
            trainedDays.insert(calendar.startOfDay(for: session.startedAt))
        }

        var count = 0
        var cursor = today
        while trainedDays.contains(cursor) {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        streak = count
    }

    // MARK: Private — Trained Days This Week

    private func computeTrainedDaysThisWeek() {
        let calendar = Calendar.current
        let today = Date()
        guard
            let weekStart = calendar.dateInterval(of: .weekOfYear, for: today)?.start
        else { return }

        var days = Set<Int>()
        for session in sessions {
            let start = session.startedAt
            if start >= weekStart && start <= today {
                let weekday = calendar.component(.weekday, from: start)
                days.insert(weekday)
            }
        }
        trainedDaysThisWeek = days
    }

    // MARK: Private — Recommendation

    private func computeRecommendation() {
        let calendar = Calendar.current
        let today = Date()

        var daysSinceLastTraining: [SportType: Int] = [:]
        for sport in SportType.allCases {
            if let last = lastSessionDate(for: sport) {
                let days = calendar.dateComponents([.day], from: last, to: today).day ?? 0
                daysSinceLastTraining[sport] = days
            } else {
                daysSinceLastTraining[sport] = Int.max
            }
        }

        let sorted = SportType.allCases.sorted { a, b in
            (daysSinceLastTraining[a] ?? 0) > (daysSinceLastTraining[b] ?? 0)
        }

        let pick = sorted.first ?? .striking
        recommendedSport = pick

        let days = daysSinceLastTraining[pick] ?? 0
        if days == Int.max {
            recommendationReason = "You haven't tried \(pick.displayName) yet"
        } else if days == 0 {
            recommendationReason = "Keep the momentum going today"
        } else {
            let unit = days == 1 ? "day" : "days"
            recommendationReason =
                "You haven't trained \(pick.displayName) in \(days) \(unit)"
        }
    }
}

// MARK: - VideoAnalysisQuickCard

struct VideoAnalysisQuickCard: View {

    var body: some View {
        quickCard(
            icon: "video.fill",
            title: "Video Library",
            subtitle: "AI biomechanics",
            accent: Color.kineticsPurple
        )
    }
}

// MARK: - PerformanceQuickCard

struct PerformanceQuickCard: View {

    var body: some View {
        quickCard(
            icon: "chart.line.uptrend.xyaxis",
            title: "Performance",
            subtitle: "Trends & PRs",
            accent: Color.kineticsAmber
        )
    }
}

// MARK: - Quick Card Builder (file-private)

private func quickCard(
    icon: String,
    title: String,
    subtitle: String,
    accent: Color
) -> some View {
    VStack(alignment: .leading, spacing: 0) {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(accent.opacity(0.14))
                .frame(width: 40, height: 40)
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(accent)
        }
        .padding(.bottom, 10)

        Text(title)
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(.white)

        Text(subtitle)
            .font(.system(size: 11))
            .foregroundStyle(Color.kineticsSubtext)
            .padding(.top, 2)

        Spacer(minLength: 0)
    }
    .padding(14)
    .frame(maxWidth: .infinity, minHeight: 100, alignment: .topLeading)
    .background(Color.kineticsDark)
    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    .overlay(
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .strokeBorder(accent.opacity(0.18), lineWidth: 0.75)
    )
}

