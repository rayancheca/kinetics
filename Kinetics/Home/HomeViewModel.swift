import Foundation
import Observation
import SwiftUI

// MARK: - Shared Home Types

struct HomeCoachInsight: Sendable {
    let sportName: String
    let accentColorHex: String
    let systemImage: String
    let headline: String
    let detail: String
    let metricValue: String
    let metricLabel: String
    let trendUp: Bool
}

struct HomeMilestoneData: Sendable {
    let title: String
    let description: String
    let current: Int
    let target: Int
    let sportImage: String
    let accentColorHex: String
}

enum MetricTrend: Sendable { case up, down, flat }

// MARK: - HomeViewModel

@Observable
@MainActor
final class HomeViewModel {

    // MARK: - Existing State

    var recentSessions: [SessionResult] = []
    var isLoadingHistory = false
    var dashboardStats: HealthKitDashboardStats = .empty
    var streakDays: Int = 0

    // MARK: - New State

    var weeklySessionCount: Int = 0
    var weeklyMinutes: Double = 0
    var prCountThisWeek: Int = 0
    var readinessScore: Int = 0
    var coachInsight: HomeCoachInsight? = nil
    var nextMilestone: HomeMilestoneData? = nil

    // MARK: - Computed

    var readinessLabel: String {
        switch readinessScore {
        case 85...100: return "Peak"
        case 65..<85:  return "Ready"
        case 40..<65:  return "Rested"
        default:       return "Fatigued"
        }
    }

    var readinessColor: Color {
        switch readinessScore {
        case 85...100: return .kineticsGreen
        case 40..<85:  return .kineticsAmber
        default:       return .kineticsRed
        }
    }

    // MARK: - Public Accessors

    func bestMetric(for sport: SportType) -> (value: Double, label: String)? {
        let key: String
        let label: String
        switch sport {
        case .striking:    key = "strikeVelocityMPH"; label = "mph"
        case .grappling:   key = "kuzushiIndex";      label = "kuzushi"
        case .ironTracker: key = "barVelocityMS";      label = "m/s"
        case .wallBeta:    key = "hipProximityScore";  label = "prox%"
        }
        let values = recentSessions
            .filter { $0.sport == sport }
            .compactMap { $0.metrics[key] }
        guard let best = values.max() else { return nil }
        return (best, label)
    }

    func trend(for sport: SportType) -> MetricTrend {
        let key: String
        switch sport {
        case .striking:    key = "strikeVelocityMPH"
        case .grappling:   key = "kuzushiIndex"
        case .ironTracker: key = "barVelocityMS"
        case .wallBeta:    key = "hipProximityScore"
        }
        let sportSessions = recentSessions.filter { $0.sport == sport }
        guard
            let latest = sportSessions.first?.metrics[key],
            let previous = sportSessions.dropFirst().first?.metrics[key],
            previous != 0
        else { return .flat }
        let delta = (latest - previous) / previous
        if delta > 0.03 { return .up }
        if delta < -0.03 { return .down }
        return .flat
    }

    func isPersonalRecord(_ session: SessionResult) -> Bool {
        let prior = recentSessions.filter {
            $0.sport == session.sport && $0.id != session.id
        }
        for (key, val) in session.metrics {
            let prevBest = prior.compactMap { $0.metrics[key] }.max() ?? 0
            if val > prevBest { return true }
        }
        return false
    }

    // MARK: - Load

    func loadHistory(for userId: String) async {
        isLoadingHistory = true
        defer { isLoadingHistory = false }

        do {
            recentSessions = try await SessionRepository.shared.fetchSessions(
                for: userId,
                limit: 20
            )
        } catch {
            recentSessions = []
        }

        computeWeeklyStats()
        computePRCount()
        computeReadiness()
        computeCoachInsight()
        computeNextMilestone()

        let streak = (try? GymRepository.shared.calculateStreak(userId: userId)) ?? 0
        streakDays = streak
        WidgetDataStore.shared.updateStreak(streak)
        await NotificationService.shared.checkStreakAchievement(streakDays: streak)
    }

    func refreshSessionHistory(for userId: String) async {
        await loadHistory(for: userId)
    }

    // MARK: - HealthKit Dashboard

    func loadDashboardStats() async {
        let service = HealthKitService.shared
        try? await service.requestAuthorization()
        dashboardStats = await service.fetchDashboardStats()
        WidgetDataStore.shared.updateTodayStats(
            steps: dashboardStats.steps,
            calories: Int(dashboardStats.activeCalories),
            workoutMinutes: Int(dashboardStats.sleepSeconds / 60)
        )
    }

    // MARK: - Auth

    func signInAnonymouslyIfNeeded(authManager: AuthManager) async {
        guard !authManager.isSignedIn else { return }
        try? await authManager.signInAnonymously()
    }

    // MARK: - Private Computations

    private func computeWeeklyStats() {
        let cal = Calendar.current
        guard let weekStart = cal.dateInterval(of: .weekOfYear, for: Date())?.start else { return }
        let weekly = recentSessions.filter { $0.startedAt >= weekStart }
        weeklySessionCount = weekly.count
        weeklyMinutes = weekly.reduce(0) { $0 + $1.duration } / 60
    }

    private func computePRCount() {
        let cal = Calendar.current
        guard let weekStart = cal.dateInterval(of: .weekOfYear, for: Date())?.start else { return }
        let weekSessions = recentSessions.filter { $0.startedAt >= weekStart }
        let olderSessions = recentSessions.filter { $0.startedAt < weekStart }
        var count = 0
        for session in weekSessions {
            let older = olderSessions.filter { $0.sport == session.sport }
            for (key, val) in session.metrics {
                let prevBest = older.compactMap { $0.metrics[key] }.max() ?? 0
                if val > prevBest { count += 1; break }
            }
        }
        prCountThisWeek = count
    }

    private func computeReadiness() {
        guard let latest = recentSessions.first else { readinessScore = 50; return }
        let daysSince = Calendar.current
            .dateComponents([.day], from: latest.startedAt, to: Date()).day ?? 0
        switch daysSince {
        case 0:  readinessScore = 70
        case 1:  readinessScore = 90
        case 2:  readinessScore = 80
        case 3:  readinessScore = 65
        case 4:  readinessScore = 50
        default: readinessScore = 35
        }
        if weeklySessionCount == 0 && daysSince >= 2 {
            readinessScore = min(readinessScore + 10, 95)
        }
    }

    private func computeCoachInsight() {
        guard let latest = recentSessions.first else { coachInsight = nil; return }
        let sport = latest.sport
        let metricKey: String
        let metricLabel: String
        let advice: String
        switch sport {
        case .striking:
            metricKey = "strikeVelocityMPH"; metricLabel = "mph"
            advice = "Focus on hip-shoulder separation timing — a 0.1s delay between " +
                "hip and shoulder rotation adds ~15% velocity."
        case .grappling:
            metricKey = "kuzushiIndex"; metricLabel = "kuzushi"
            advice = "Commit to breaking posture before footwork — your kuzushi score " +
                "improves most when uke is already off-balance."
        case .ironTracker:
            metricKey = "barVelocityMS"; metricLabel = "m/s"
            advice = "Maintain bar-contact along the leg through the knee. Any deviation " +
                "before the knee adds friction and slows your pull."
        case .wallBeta:
            metricKey = "hipProximityScore"; metricLabel = "prox%"
            advice = "Drive the hip closest to the wall up and in on every reach — " +
                "this shifts load to feet and protects your contact strength."
        }
        guard let val = latest.metrics[metricKey] else { coachInsight = nil; return }

        let prevSessions = recentSessions.filter { $0.sport == sport }.dropFirst()
        let prevVal = prevSessions.first?.metrics[metricKey]
        let trendUp = prevVal.map { val > $0 } ?? true

        let headline: String
        if let prev = prevVal {
            let delta = val - prev
            let sign = delta >= 0 ? "+" : ""
            headline = "\(sport.displayName): \(sign)\(String(format: "%.1f", delta)) " +
                "\(metricLabel) vs last session"
        } else {
            headline = "First \(sport.displayName) session recorded"
        }

        coachInsight = HomeCoachInsight(
            sportName: sport.displayName,
            accentColorHex: sport.accentColor,
            systemImage: sport.systemImage,
            headline: headline,
            detail: advice,
            metricValue: String(format: "%.1f", val),
            metricLabel: metricLabel,
            trendUp: trendUp
        )
    }

    private func computeNextMilestone() {
        let milestones = [10, 25, 50, 100]
        var best: (sport: SportType, current: Int, target: Int)?

        for sport in SportType.allCases {
            let count = recentSessions.filter { $0.sport == sport }.count
            guard let nextTarget = milestones.first(where: { $0 > count }) else { continue }
            let remaining = nextTarget - count
            let bestRemaining = best.map { $0.target - $0.current } ?? Int.max
            if remaining < bestRemaining {
                best = (sport, count, nextTarget)
            }
        }

        guard let b = best else { nextMilestone = nil; return }
        nextMilestone = HomeMilestoneData(
            title: "\(b.sport.displayName) milestone",
            description: "Complete \(b.target) \(b.sport.displayName) sessions",
            current: b.current,
            target: b.target,
            sportImage: b.sport.systemImage,
            accentColorHex: b.sport.accentColor
        )
    }
}
