import SwiftUI
import WidgetKit

// MARK: - Shared data keys (AppGroup: group.com.rayancheca.kinetics)

enum WidgetDataKey {
    static let steps          = "widget_steps"
    static let calories       = "widget_calories"
    static let workoutMinutes = "widget_workout_minutes"
    static let nextWorkout    = "widget_next_workout"
    static let streakDays     = "widget_streak_days"
    static let suiteName      = "group.com.rayancheca.kinetics"
}

// MARK: - WidgetEntry

struct KineticsEntry: TimelineEntry {
    let date: Date
    let steps: Int
    let calories: Int
    let workoutMinutes: Int
    let nextWorkout: String
    let streakDays: Int

    static var placeholder: KineticsEntry {
        KineticsEntry(
            date: Date(),
            steps: 7_842,
            calories: 412,
            workoutMinutes: 45,
            nextWorkout: "Today · 7:00 AM",
            streakDays: 6
        )
    }
}

// MARK: - Provider

struct KineticsProvider: TimelineProvider {

    func placeholder(in context: Context) -> KineticsEntry {
        .placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (KineticsEntry) -> Void) {
        completion(entry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<KineticsEntry>) -> Void) {
        let current = entry()
        // Refresh every 30 minutes
        let nextRefresh = Calendar.current.date(byAdding: .minute, value: 30, to: current.date) ?? current.date
        completion(Timeline(entries: [current], policy: .after(nextRefresh)))
    }

    // MARK: Helpers

    private func entry() -> KineticsEntry {
        let defaults = UserDefaults(suiteName: WidgetDataKey.suiteName)
        return KineticsEntry(
            date: Date(),
            steps: defaults?.integer(forKey: WidgetDataKey.steps) ?? 0,
            calories: defaults?.integer(forKey: WidgetDataKey.calories) ?? 0,
            workoutMinutes: defaults?.integer(forKey: WidgetDataKey.workoutMinutes) ?? 0,
            nextWorkout: defaults?.string(forKey: WidgetDataKey.nextWorkout) ?? "Not scheduled",
            streakDays: defaults?.integer(forKey: WidgetDataKey.streakDays) ?? 0
        )
    }
}

// MARK: - Today Stats Widget

struct TodayStatsWidget: Widget {
    let kind = "TodayStats"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: KineticsProvider()) { entry in
            TodayStatsView(entry: entry)
                .containerBackground(.black, for: .widget)
        }
        .configurationDisplayName("Today's Stats")
        .description("Steps, calories, and active minutes at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - Next Workout Widget

struct NextWorkoutWidget: Widget {
    let kind = "NextWorkout"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: KineticsProvider()) { entry in
            NextWorkoutView(entry: entry)
                .containerBackground(.black, for: .widget)
        }
        .configurationDisplayName("Next Workout")
        .description("See your next scheduled workout.")
        .supportedFamilies([.systemSmall])
    }
}

// MARK: - Widget Bundle

@main
struct KineticsWidgetBundle: WidgetBundle {
    var body: some Widget {
        TodayStatsWidget()
        NextWorkoutWidget()
    }
}

// MARK: - TodayStatsView

struct TodayStatsView: View {

    let entry: KineticsEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color(red: 0, green: 0.76, blue: 1)) // kineticsBlue

                Text("KINETICS")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color(red: 0, green: 0.76, blue: 1))
                    .tracking(1)

                Spacer()

                if entry.streakDays > 0 {
                    HStack(spacing: 2) {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(Color(red: 1, green: 0.722, blue: 0)) // kineticsAmber
                        Text("\(entry.streakDays)")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Color(red: 1, green: 0.722, blue: 0))
                    }
                }
            }
            .padding(.bottom, 10)

            if entry.steps > 0 || entry.calories > 0 {
                VStack(alignment: .leading, spacing: 8) {
                    StatRow(
                        icon: "figure.walk",
                        value: formattedSteps(entry.steps),
                        label: "steps",
                        color: Color(red: 0, green: 0.76, blue: 1)
                    )
                    StatRow(
                        icon: "flame",
                        value: "\(entry.calories)",
                        label: "kcal",
                        color: Color(red: 1, green: 0.722, blue: 0)
                    )
                    StatRow(
                        icon: "clock",
                        value: "\(entry.workoutMinutes)",
                        label: "min",
                        color: Color(red: 0.224, green: 0.906, blue: 0.439)
                    )
                }
            } else {
                Spacer()
                Text("No data yet")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.4))
                Spacer()
            }
        }
        .padding(14)
    }

    private func formattedSteps(_ steps: Int) -> String {
        let fmt = NumberFormatter()
        fmt.numberStyle = .decimal
        return fmt.string(from: NSNumber(value: steps)) ?? "\(steps)"
    }
}

// MARK: - NextWorkoutView

struct NextWorkoutView: View {

    let entry: KineticsEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "dumbbell.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color(red: 0, green: 0.76, blue: 1))

                Text("NEXT")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color(red: 0, green: 0.76, blue: 1))
                    .tracking(1)
            }

            Spacer()

            Text(entry.nextWorkout)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(2)

            Spacer()

            Text("TAP TO OPEN")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.white.opacity(0.3))
                .tracking(0.8)
        }
        .padding(14)
    }
}

// MARK: - StatRow

private struct StatRow: View {

    let icon: String
    let value: String
    let label: String
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(color)
                .frame(width: 16)

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .monospacedDigit()

                Text(label)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
    }
}
