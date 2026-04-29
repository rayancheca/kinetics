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
@MainActor
final class NotificationService {

    // MARK: - Singleton

    static let shared = NotificationService()

    // MARK: - Private

    private let center = UNUserNotificationCenter.current()

    private init() {}

    // MARK: - Authorization

    /// Requests `.alert`, `.badge`, and `.sound` notification permissions.
    ///
    /// - Returns: `true` when the user grants authorization; `false` otherwise.
    func requestAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            center.requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
                continuation.resume(returning: granted)
            }
        }
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

            let requestID = "\(identifier)_weekday_\(weekday)"
            let request   = UNNotificationRequest(
                identifier: requestID,
                content: content,
                trigger: trigger
            )

            try? await center.add(request)
        }
    }

    /// Cancels all pending workout reminders whose identifier begins with `identifier`.
    func cancelWorkoutReminders(identifier: String) async {
        let pending = await center.pendingNotificationRequests()
        let toRemove = pending
            .map(\.identifier)
            .filter { $0.hasPrefix("\(identifier)_weekday_") }
        center.removePendingNotificationRequests(withIdentifiers: toRemove)
    }

    // MARK: - Achievement Notifications

    /// Fires a one-shot notification 5 seconds after the call.
    ///
    /// Each invocation uses a unique UUID so concurrent calls do not collide.
    func scheduleAchievementNotification(title: String, body: String) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body  = body
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: trigger
        )
        try? await center.add(request)
    }

    // MARK: - Pending Count

    /// Returns the total number of pending (not yet delivered) notifications.
    func pendingCount() async -> Int {
        await center.pendingNotificationRequests().count
    }
}
