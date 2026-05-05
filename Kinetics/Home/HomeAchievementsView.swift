import SwiftUI

// MARK: - KineticsAchievementBadge

struct KineticsAchievementBadge: Identifiable {
    let id: String
    let title: String
    let description: String
    let icon: String        // SF Symbol
    let accentHex: String   // color hex
    let isUnlocked: Bool
}

// MARK: - AchievementsViewModel

@Observable
@MainActor
final class AchievementsViewModel {

    // MARK: State

    var sessions: [SessionResult] = []
    var isLoading = false

    // MARK: Computed — Streak

    var streakDays: Int {
        guard !sessions.isEmpty else { return 0 }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        // Build a set of unique days that have at least one session.
        let activeDays = Set(sessions.map { calendar.startOfDay(for: $0.startedAt) })

        var streak = 0
        var cursor = today

        while activeDays.contains(cursor) {
            streak += 1
            guard let prev = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = prev
        }

        return streak
    }

    // MARK: Computed — Totals

    var totalSessions: Int { sessions.count }

    var totalMinutes: Int {
        Int(sessions.reduce(0) { $0 + $1.duration } / 60)
    }

    var activeSportCount: Int {
        Set(sessions.map(\.sport)).count
    }

    // MARK: Per-Sport

    func sessionCount(for sport: SportType) -> Int {
        sessions.filter { $0.sport == sport }.count
    }

    // MARK: Heatmap — 52 weeks × 7 days (col 0 = oldest, row 0 = Sunday)

    func heatmapData() -> [[Int]] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let daysToSat = (7 - cal.component(.weekday, from: today)) % 7
        guard let saturday = cal.date(byAdding: .day, value: daysToSat, to: today) else { return [] }

        var countMap: [Date: Int] = [:]
        for s in sessions { countMap[cal.startOfDay(for: s.startedAt), default: 0] += 1 }

        return (0 ..< 52).reversed().map { week in
            (0 ..< 7).map { dayOffset in
                let daysBack = week * 7 + (6 - dayOffset)
                guard let d = cal.date(byAdding: .day, value: -daysBack, to: saturday) else { return 0 }
                return countMap[cal.startOfDay(for: d)] ?? 0
            }
        }
    }

    // MARK: Badges

    var unlockedBadges: [KineticsAchievementBadge] { allBadges.filter(\.isUnlocked) }
    var lockedBadges: [KineticsAchievementBadge] { allBadges.filter { !$0.isUnlocked } }

    private var allBadges: [KineticsAchievementBadge] {
        let cal = Calendar.current
        let weekWarrior: Bool = {
            let grouped = Dictionary(
                grouping: sessions,
                by: { cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: $0.startedAt) }
            )
            return grouped.values.contains { $0.count >= 5 }
        }()
        let allRounder = SportType.allCases.allSatisfy { sessionCount(for: $0) >= 5 }

        func badge(
            _ id: String, _ title: String, _ desc: String,
            _ icon: String, _ hex: String, _ unlocked: Bool
        ) -> KineticsAchievementBadge {
            KineticsAchievementBadge(id: id, title: title, description: desc,
                             icon: icon, accentHex: hex, isUnlocked: unlocked)
        }

        return [
            badge("first_strike", "First Strike",
                  "Complete your first Striking Clinic session",
                  "bolt.fill", "#FF4444", sessionCount(for: .striking) >= 1),
            badge("iron_will", "Iron Will",
                  "Complete your first Iron Tracker session",
                  "dumbbell.fill", "#00C2FF", sessionCount(for: .ironTracker) >= 1),
            badge("ground_game", "Ground Game",
                  "Complete your first Grappling Lab session",
                  "person.2.fill", "#FF8C00", sessionCount(for: .grappling) >= 1),
            badge("send_it", "Send It",
                  "Complete your first Wall Beta session",
                  "figure.climbing", "#39FF14", sessionCount(for: .wallBeta) >= 1),
            badge("week_warrior", "Week Warrior",
                  "Log 5 sessions in a single week",
                  "flame.fill", "#FFB800", weekWarrior),
            badge("consistent", "Consistent",
                  "Maintain a 7-day training streak",
                  "calendar.badge.checkmark", "#00C2FF", streakDays >= 7),
            badge("dedicated", "Dedicated",
                  "Complete 30 total sessions",
                  "trophy.fill", "#FFB800", totalSessions >= 30),
            badge("all_rounder", "All-Rounder",
                  "Log at least 5 sessions in every sport",
                  "star.fill", "#8B5CF6", allRounder),
            badge("century", "Century",
                  "Complete 100 total sessions",
                  "crown.fill", "#FFB800", totalSessions >= 100),
            badge("iron_streak", "Iron Streak",
                  "Maintain a 14-day training streak",
                  "bolt.circle.fill", "#00C2FF", streakDays >= 14),
        ]
    }

    // MARK: Load

    func load(userId: String) async {
        isLoading = true
        defer { isLoading = false }
        do {
            sessions = try await SessionRepository.shared.fetchSessions(for: userId, limit: 500)
        } catch {
            sessions = []
        }
    }
}

// MARK: - HomeAchievementsView

struct HomeAchievementsView: View {

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var vm = AchievementsViewModel()

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 24) {
                    headerRow
                    streakHero
                    statsRow
                    sportBreakdownSection
                    heatmapSection
                    badgesSection
                    Spacer(minLength: 60)
                }
                .padding(.top, 24)
            }
            .background(Color.kineticsBackground)
            .toolbar(.hidden, for: .navigationBar)
        }
        .presentationDetents([.large])
        .presentationBackground(Color.kineticsBackground)
        .presentationCornerRadius(24)
        .presentationDragIndicator(.visible)
        .task {
            guard let uid = appState.authManager.currentUser?.uid else { return }
            await vm.load(userId: uid)
        }
    }

    // MARK: - Header Row

    private var headerRow: some View {
        HStack {
            Text("ACHIEVEMENTS")
                .font(.system(size: 26, weight: .black))
                .tracking(4)
                .foregroundStyle(.white)

            Spacer()

            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.55))
                    .frame(width: 32, height: 32)
                    .background(Color.kineticsMidGray)
                    .clipShape(Circle())
            }
        }
        .padding(.horizontal, 24)
    }

    // MARK: - Streak Hero

    private var streakHero: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.08), lineWidth: 12)
                    .frame(width: 130, height: 130)
                Circle()
                    .trim(from: 0, to: min(CGFloat(vm.streakDays) / 365.0, 1.0))
                    .stroke(
                        LinearGradient(
                            colors: [Color.kineticsBlue, Color.kineticsGreen],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ),
                        style: StrokeStyle(lineWidth: 12, lineCap: .round)
                    )
                    .frame(width: 130, height: 130)
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.8), value: vm.streakDays)
                VStack(spacing: 2) {
                    Text("\(vm.streakDays)")
                        .font(.system(size: 52, weight: .black))
                        .foregroundStyle(.white)
                    Text("day streak")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.40))
                }
            }
            Text(streakLabel)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white.opacity(0.60))
        }
    }

    private var streakLabel: String {
        switch vm.streakDays {
        case 0:       return "Start your first session today"
        case 1 ..< 3: return "Great start — keep going!"
        case 3 ..< 7: return "Building momentum"
        case 7 ..< 14: return "Keep it up!"
        case 14 ..< 30: return "You're on fire!"
        default:       return "Unstoppable — incredible streak"
        }
    }

    // MARK: - Stats Row

    private var statsRow: some View {
        HStack(spacing: 12) {
            MiniStatCard(
                label: "Total Sessions",
                value: "\(vm.totalSessions)",
                icon: "figure.run"
            )
            MiniStatCard(
                label: "Total Time",
                value: formattedHours(vm.totalMinutes),
                icon: "clock"
            )
            MiniStatCard(
                label: "Sports",
                value: "\(vm.activeSportCount)",
                icon: "star.fill"
            )
        }
        .padding(.horizontal, 20)
    }

    private func formattedHours(_ minutes: Int) -> String {
        if minutes < 60 { return "\(minutes)m" }
        let hrs = minutes / 60
        let rem = minutes % 60
        return rem == 0 ? "\(hrs)h" : "\(hrs)h \(rem)m"
    }

    // MARK: - Sport Breakdown Section

    private var sportBreakdownSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("BY SPORT")
                .padding(.horizontal, 24)

            VStack(spacing: 10) {
                ForEach(SportType.allCases, id: \.self) { sport in
                    SportBreakdownRow(
                        sport: sport,
                        count: vm.sessionCount(for: sport)
                    )
                }
            }
            .padding(.horizontal, 20)
        }
    }

    // MARK: - Heatmap Section

    private var heatmapSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("TRAINING HISTORY")
                .padding(.horizontal, 24)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    ForEach(Array(vm.heatmapData().enumerated()), id: \.offset) { _, week in
                        VStack(spacing: 2) {
                            ForEach(Array(week.enumerated()), id: \.offset) { _, count in
                                RoundedRectangle(cornerRadius: 2, style: .continuous)
                                    .fill(heatmapColor(for: count))
                                    .frame(width: 9, height: 9)
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }

    private func heatmapColor(for count: Int) -> Color {
        switch count {
        case 0:    return Color.white.opacity(0.05)
        case 1:    return Color.kineticsBlue.opacity(0.35)
        case 2:    return Color.kineticsBlue.opacity(0.65)
        default:   return Color.kineticsBlue
        }
    }

    // MARK: - Badges Section

    private var badgesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("BADGES")
                .padding(.horizontal, 24)

            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible())],
                spacing: 12
            ) {
                ForEach(vm.unlockedBadges) { badge in
                    BadgeCard(badge: badge)
                }
                ForEach(vm.lockedBadges) { badge in
                    BadgeCard(badge: badge)
                }
            }
            .padding(.horizontal, 20)
        }
    }

    // MARK: - Helpers

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .tracking(2.5)
            .foregroundStyle(Color.kineticsSubtext)
    }
}

// MARK: - MiniStatCard

private struct MiniStatCard: View {
    let label: String
    let value: String
    let icon: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.kineticsBlue)

            Text(value)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.white)

            Text(label)
                .font(.system(size: 10, weight: .regular))
                .foregroundStyle(Color.kineticsSubtext)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Color.kineticsDark)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.white.opacity(0.07), lineWidth: 0.5)
        )
    }
}

// MARK: - SportBreakdownRow

private struct SportBreakdownRow: View {
    let sport: SportType
    let count: Int

    private var accent: Color { Color.moduleColor(for: sport) }
    private var progress: Double { min(Double(count) / 50.0, 1.0) }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(accent.opacity(0.15))
                    .frame(width: 40, height: 40)

                Image(systemName: sport.systemImage)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(accent)
            }

            Text(sport.displayName)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)

            Spacer()

            Text("\(count) sessions")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(accent)

            GeometryReader { _ in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(.white.opacity(0.08))

                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(accent)
                        .frame(width: 60 * progress)
                }
            }
            .frame(width: 60, height: 4)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.kineticsDark)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.white.opacity(0.07), lineWidth: 0.5)
        )
    }
}

// MARK: - BadgeCard

private struct BadgeCard: View {
    let badge: KineticsAchievementBadge

    private var accent: Color { Color(hex: badge.accentHex) }

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(badge.isUnlocked ? accent.opacity(0.18) : Color.white.opacity(0.05))
                    .frame(width: 44, height: 44)
                Image(systemName: badge.icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(badge.isUnlocked ? accent : Color.white.opacity(0.25))
                if !badge.isUnlocked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white.opacity(0.45))
                        .frame(width: 44, height: 44, alignment: .bottomTrailing)
                        .offset(x: 6, y: 6)
                }
            }

            VStack(spacing: 3) {
                Text(badge.title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(badge.isUnlocked ? .white : Color.white.opacity(0.30))
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Text(badge.description)
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(.white.opacity(badge.isUnlocked ? 0.50 : 0.22))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .padding(.horizontal, 10)
        .background(Color.kineticsDark)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(
                    badge.isUnlocked
                        ? accent.opacity(0.30)
                        : Color.white.opacity(0.06),
                    lineWidth: 0.75
                )
        )
    }
}

// MARK: - Preview

#Preview {
    HomeAchievementsView()
        .environment(AppState.preview)
}
