import AppIntents
import Foundation
import UIKit

// MARK: - StartSessionIntent

/// "Start a Kinetics session" — invoked by Siri, Shortcuts, Spotlight or any
/// other system surface that can launch App Intents.
///
/// Routes through the existing `kinetics://` deep-link scheme so the App
/// Intent UI does not need direct access to AppState / cameraManager.
@available(iOS 17.0, *)
struct StartSessionIntent: AppIntent {

    static let title: LocalizedStringResource = "Start Training Session"
    static let description: IntentDescription = IntentDescription(
        "Launches Kinetics and opens the selected sport module ready for live biomechanics analysis."
    )

    /// Tells Siri to open the app rather than perform purely in the background.
    static let openAppWhenRun: Bool = true

    @Parameter(
        title: "Module",
        description: "Which sport module would you like to train?",
        default: .striking
    )
    var module: SportAppEnum

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        if let url = module.deepLinkURL {
            await UIApplication.shared.open(url)
        }
        return .result(
            dialog: IntentDialog(
                stringLiteral: "Starting \(module.sportType.displayName). Get into frame and let's train."
            )
        )
    }

    static var parameterSummary: some ParameterSummary {
        Summary("Start a \(\.$module) session")
    }

    // swiftlint:disable:next discouraged_static_let
    nonisolated(unsafe) private static let _intentTypeMarker = ()
}

// MARK: - LogGymWorkoutIntent

/// Quickly opens the Gym Tracker tab to log a workout. Useful when the user is
/// at the gym and wants a one-tap (or Siri command) entry point.
@available(iOS 17.0, *)
struct LogGymWorkoutIntent: AppIntent {

    static let title: LocalizedStringResource = "Open Gym Tracker"
    static let description: IntentDescription = IntentDescription(
        "Jumps straight to the Gym Tracker so you can log sets, reps, and weight."
    )

    static let openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        if let url = URL(string: "kinetics://gym") {
            await UIApplication.shared.open(url)
        }
        return .result()
    }
}

// MARK: - StartTrackIntent

/// Opens the GPS Track screen for outdoor workouts (run/ride/hike/walk).
@available(iOS 17.0, *)
struct StartTrackIntent: AppIntent {

    static let title: LocalizedStringResource = "Track Outdoor Workout"
    static let description: IntentDescription = IntentDescription(
        "Opens the Track tab so you can record a GPS-tracked outdoor workout."
    )

    static let openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        if let url = URL(string: "kinetics://track") {
            await UIApplication.shared.open(url)
        }
        return .result()
    }
}

// MARK: - ViewStreakIntent

/// Opens the Home tab and surfaces the current streak.
@available(iOS 17.0, *)
struct ViewStreakIntent: AppIntent {

    static let title: LocalizedStringResource = "Check Training Streak"
    static let description: IntentDescription = IntentDescription(
        "Opens Kinetics and shows your current training streak."
    )

    static let openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        if let url = URL(string: "kinetics://home") {
            await UIApplication.shared.open(url)
        }
        return .result()
    }
}
