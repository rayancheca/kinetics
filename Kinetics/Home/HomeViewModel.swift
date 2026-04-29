import Foundation
import Observation

// MARK: - HomeViewModel

/// Drives the Home screen: loads session history and handles anonymous sign-in
/// on first launch so every user has a Firestore identity immediately.
///
/// Created as a `@State` property inside `HomeView`, so its lifetime is tied
/// exactly to the Home screen being on-screen.
@Observable
@MainActor
final class HomeViewModel {

    // MARK: - State

    /// The five most recent sessions for the signed-in user, newest-first.
    var recentSessions: [SessionResult] = []

    /// `true` while a Firestore fetch is in flight — used to show a skeleton
    /// placeholder in the recent sessions list.
    var isLoadingHistory = false

    /// Passive HealthKit dashboard snapshot for the stats card.
    /// Defaults to `.empty` until the first successful read.
    var dashboardStats: HealthKitDashboardStats = .empty

    /// Current consecutive-day workout streak. Updated each time history loads.
    var streakDays: Int = 0

    // MARK: - History

    /// Fetches the five most recent sessions for `userId` from Firestore.
    /// Silently sets `recentSessions` to empty on any error — the home screen
    /// should never block on Firestore availability.
    func loadHistory(for userId: String) async {
        isLoadingHistory = true
        defer { isLoadingHistory = false }

        do {
            recentSessions = try await SessionRepository.shared.fetchSessions(
                for: userId,
                limit: 5
            )
        } catch {
            recentSessions = []
        }

        let streak = (try? GymRepository.shared.calculateStreak(userId: userId)) ?? 0
        streakDays = streak
        WidgetDataStore.shared.updateStreak(streak)
    }

    /// Convenience wrapper so the view can trigger a reload by name without
    /// exposing the underlying `loadHistory(for:)` signature at every call site.
    func refreshSessionHistory(for userId: String) async {
        await loadHistory(for: userId)
    }

    // MARK: - HealthKit Dashboard

    /// Reads the passive dashboard stats from HealthKit and updates `dashboardStats`.
    ///
    /// Requests authorization on first call. Silently no-ops when HealthKit is
    /// unavailable (e.g. simulator) — the dashboard stats card shows "--" values.
    func loadDashboardStats() async {
        let service = HealthKitService.shared
        // Authorization is idempotent; ignore the error — unavailability produces
        // .empty stats rather than a hard failure.
        try? await service.requestAuthorization()
        dashboardStats = await service.fetchDashboardStats()
        WidgetDataStore.shared.updateTodayStats(
            steps: dashboardStats.steps,
            calories: Int(dashboardStats.activeCalories),
            workoutMinutes: Int(dashboardStats.sleepSeconds / 60)
        )
    }

    // MARK: - Auth

    /// Silently signs the user in anonymously if no session is active.
    /// This ensures every launch creates a Firestore user ID so session
    /// history can be written even before the user creates a full account.
    func signInAnonymouslyIfNeeded(authManager: AuthManager) async {
        guard !authManager.isSignedIn else { return }
        try? await authManager.signInAnonymously()
    }
}
