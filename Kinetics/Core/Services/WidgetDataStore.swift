import Foundation
import WidgetKit

// Writes live data to the AppGroup UserDefaults so the WidgetKit extension can read it.
// Call updateTodayStats() from HomeViewModel after fetching HealthKit data.
@MainActor
final class WidgetDataStore {

    static let shared = WidgetDataStore()

    private let defaults = UserDefaults(suiteName: "group.com.rayancheca.kinetics")

    func updateTodayStats(steps: Int, calories: Int, workoutMinutes: Int) {
        defaults?.set(steps, forKey: "widget_steps")
        defaults?.set(calories, forKey: "widget_calories")
        defaults?.set(workoutMinutes, forKey: "widget_workout_minutes")
        WidgetCenter.shared.reloadTimelines(ofKind: "TodayStats")
    }

    func updateNextWorkout(_ description: String) {
        defaults?.set(description, forKey: "widget_next_workout")
        WidgetCenter.shared.reloadTimelines(ofKind: "NextWorkout")
    }

    func updateStreak(_ days: Int) {
        defaults?.set(days, forKey: "widget_streak_days")
        WidgetCenter.shared.reloadAllTimelines()
    }
}
