import AppIntents
import Foundation

// MARK: - KineticsShortcutsProvider

/// Registers App Shortcuts so Siri can suggest them without the user manually
/// adding anything in the Shortcuts app.
///
/// **iOS 16+ behaviour:** Each shortcut surface appears in:
/// - Spotlight ("training session", "kinetics", etc.)
/// - Siri suggestions ("Hey Siri, start a grappling session")
/// - Shortcuts app gallery under the Kinetics row
///
/// Phrases must contain `\(.applicationName)` for the system to surface them.
@available(iOS 17.0, *)
struct KineticsShortcutsProvider: AppShortcutsProvider {

    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartSessionIntent(),
            phrases: [
                "Start a session in \(.applicationName)",
                "Train with \(.applicationName)",
                "Start \(\.$module) in \(.applicationName)",
                "Begin a \(\.$module) workout in \(.applicationName)"
            ],
            shortTitle: "Start Session",
            systemImageName: "play.circle.fill"
        )

        AppShortcut(
            intent: LogGymWorkoutIntent(),
            phrases: [
                "Open gym in \(.applicationName)",
                "Log a gym workout in \(.applicationName)",
                "Start lifting in \(.applicationName)"
            ],
            shortTitle: "Gym Tracker",
            systemImageName: "dumbbell.fill"
        )

        AppShortcut(
            intent: StartTrackIntent(),
            phrases: [
                "Track an outdoor workout in \(.applicationName)",
                "Start tracking in \(.applicationName)",
                "Begin a run in \(.applicationName)"
            ],
            shortTitle: "Track Run",
            systemImageName: "figure.run"
        )

        AppShortcut(
            intent: ViewStreakIntent(),
            phrases: [
                "Show my streak in \(.applicationName)",
                "What is my \(.applicationName) streak"
            ],
            shortTitle: "Check Streak",
            systemImageName: "flame.fill"
        )
    }

    static let shortcutTileColor: ShortcutTileColor = .navy
}
