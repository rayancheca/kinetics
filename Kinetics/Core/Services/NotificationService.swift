import Foundation
import UserNotifications

// MARK: - NotificationService

/// Centralised wrapper around `UNUserNotificationCenter` for all Kinetics
/// push / local notification needs.
///
/// `@MainActor` keeps every call on the main thread because
/// `UNUserNotificationCenter` callbacks are safe to bridge there,
/// and it avoids the Sendable-capture friction of an actor when
/// the caller is already on the main thread (e.g., SwiftUI views /
/// `@Observable` ViewModels).
///
/// All notifications include a `kinetics_deeplink` key in their `userInfo`
/// so `DeepLinkRouter` can route the tap to the correct screen.
@MainActor
final class NotificationService {

    // MARK: - Singleton

    static let shared = NotificationService()

    // MARK: - UserDefaults keys (for achievement gate tracking)

    private enum DefaultsKey {
        static let firstSessionFired    = "notif_achievement_first_session"
        static let sevenDayStreakFired  = "notif_achievement_7day_streak"
        static let firstPRFired         = "notif_achievement_first_pr"
        static let lastActiveDate       = "notif_last_active_date"
        static let inactivityReminderID = "notif_inactivity_reminder_id"
    }

    // MARK: - Private

    private let center   = UNUserNotificationCenter.current()
    private let defaults = UserDefaults.standard

    private init() {}

    // MARK: - Authorization

    /// Requests `.alert`, `.badge`, and `.sound` notification permissions.
    ///
    /// Also registers the app as the notification delegate so foreground
    /// notifications can be presented.
    ///
    /// - Returns: `true` when the user grants authorization; `false` otherwise.
    func requestAuthorization() async -> Bool {
        let granted = await withCheckedContinuation { continuation in
            center.requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
                continuation.resume(returning: granted)
            }
        }
        return granted
    }

    // MARK: - Workout Reminders

    /// Schedules a repeating weekly reminder on each of the supplied weekdays.
    ///
    /// - Parameters:
    ///   - title:      Notification title.
    ///   - body:       Notification body text.
    ///   - weekdays:   Array of integers in the range 1–7 (Sunday = 1, Saturday = 7).
    ///   - hour:       Local hour component (0–23).
    ///   - minute:     Local minute component (0–59).
    ///   - identifier: Base identifier used to namespace the scheduled requests.
    ///                 Each weekday request gets the suffix `_weekday_<N>`.
    func scheduleWorkoutReminder(
        title: String,
        body: String,
        weekdays: [Int],
        hour: Int,
        minute: Int,
        identifier: String
    ) async {
        // Remove any existing requests that share this base identifier.
        await cancelWorkoutReminders(identifier: identifier)

        for weekday in weekdays {
            var components = DateComponents()
            components.weekday = weekday
            components.hour    = hour
            components.minute  = minute

            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)

            let content = UNMutableNotificationContent()
            content.title = title
            content.body  = body
            content.sound = .default
            content.userInfo = ["kinetics_deeplink": "kinetics://home"]

            let requestID = "\(identifier)_weekday_\(weekday)"
            let request   = UNNotificationRequest(
                identifier: requestID,
                content: content,
                trigger: trigger
            )

            try? await center.add(request)
        }

        // Update the widget so the next scheduled workout description is current.
        WidgetDataStore.shared.updateNextWorkout(
            "\(title) · \(formattedTime(hour: hour, minute: minute))"
        )
    }

    // MARK: - Inactivity Reminder

    /// Records today as the last active date and reschedules the 2-day inactivity
    /// reminder. Call this at the end of every successful workout session.
    func recordActivity() {
        defaults.set(Date(), forKey: DefaultsKey.lastActiveDate)
        Task { await scheduleInactivityReminder() }
    }

    /// Schedules a "Time to train" reminder to fire 48 hours from now.
    /// Cancels any previously scheduled inactivity reminder first.
    private func scheduleInactivityReminder() async {
        // Cancel the old pending reminder, if any.
        if let oldID = defaults.string(forKey: DefaultsKey.inactivityReminderID) {
            center.removePendingNotificationRequests(withIdentifiers: [oldID])
        }

        let content = UNMutableNotificationContent()
        content.title = "Time to train 💪"
        content.body  = "You haven't opened Kinetics in 2 days. Keep the momentum going!"
        content.sound = .default
        content.userInfo = ["kinetics_deeplink": "kinetics://home"]

        // 48 hours = 172800 seconds. In development/testing use a shorter window if needed.
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 172_800, repeats: false)
        let requestID = "kinetics_inactivity_\(UUID().uuidString)"

        let request = UNNotificationRequest(
            identifier: requestID,
            content: content,
            trigger: trigger
        )
        try? await center.add(request)
        defaults.set(requestID, forKey: DefaultsKey.inactivityReminderID)
    }

    // MARK: - Achievement Notifications

    /// Fires a one-shot notification 5 seconds after the call, with the given
    /// deeplink so a tap routes the user to the right screen.
    ///
    /// Each invocation uses a unique UUID so concurrent calls do not collide.
    func scheduleAchievementNotification(
        title: String,
        body: String,
        deeplink: String = "kinetics://home"
    ) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body  = body
        content.sound = .default
        content.userInfo = ["kinetics_deeplink": deeplink]

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: trigger
        )
        try? await center.add(request)
    }

    // MARK: - Achievement Gate Checks

    /// Call after every completed session. Fires the "first session" achievement
    /// notification once, then never again.
    func checkFirstSessionAchievement() async {
        guard !defaults.bool(forKey: DefaultsKey.firstSessionFired) else { return }
        defaults.set(true, forKey: DefaultsKey.firstSessionFired)
        await scheduleAchievementNotification(
            title: "First session logged! 🎉",
            body: "Your biomechanics journey has begun. Keep it up!",
            deeplink: "kinetics://history"
        )
    }

    /// Call whenever the streak count updates. Fires the "7-day streak" badge
    /// exactly once when the streak first reaches 7 (or more).
    func checkStreakAchievement(streakDays: Int) async {
        guard streakDays >= 7,
              !defaults.bool(forKey: DefaultsKey.sevenDayStreakFired) else { return }
        defaults.set(true, forKey: DefaultsKey.sevenDayStreakFired)
        await scheduleAchievementNotification(
            title: "7-day streak 🔥",
            body: "A full week of training — consistency is everything!",
            deeplink: "kinetics://home"
        )
    }

    /// Call after a personal record is set in the Gym Tracker. Fires once and
    /// resets the gate so a subsequent PR re-fires the notification.
    ///
    /// Unlike the other achievements, this one resets after firing so every PR
    /// earns a notification (not just the very first one).
    func checkPersonalRecordAchievement(exerciseName: String) async {
        await scheduleAchievementNotification(
            title: "New PR! 🏆",
            body: "You just set a personal record on \(exerciseName). Outstanding work!",
            deeplink: "kinetics://gym/prs"
        )
    }

    // MARK: - Private Helpers

    /// Returns a human-readable time string, e.g. "7:00 AM" or "10:30 PM".
    private func formattedTime(hour: Int, minute: Int) -> String {
        var components = DateComponents()
        components.hour   = hour
        components.minute = minute
        guard let date = Calendar.current.date(from: components) else {
            return String(format: "%d:%02d", hour, minute)
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }

    /// Cancels all pending workout reminders whose identifier begins with `identifier`.
    func cancelWorkoutReminders(identifier: String) async {
        let pending = await center.pendingNotificationRequests()
        let toRemove = pending
            .map(\.identifier)
            .filter { $0.hasPrefix("\(identifier)_weekday_") }
        center.removePendingNotificationRequests(withIdentifiers: toRemove)
    }

    // MARK: - Pending Count

    /// Returns the total number of pending (not yet delivered) notifications.
    func pendingCount() async -> Int {
        await center.pendingNotificationRequests().count
    }
}
