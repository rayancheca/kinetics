import Foundation
import CoreLocation

// MARK: - WorkoutActivityType

/// The GPS activity types supported by the Track module.
///
/// Each case carries display metadata so the UI layer never needs to
/// switch on the raw value — it delegates to these properties directly.
enum WorkoutActivityType: String, Codable, CaseIterable, Sendable, Hashable {
    case run
    case walk
    case ride
    case hike
    case swim
    case ski

    // MARK: Display

    var displayName: String {
        switch self {
        case .run:  "Run"
        case .walk: "Walk"
        case .ride: "Ride"
        case .hike: "Hike"
        case .swim: "Swim"
        case .ski:  "Ski"
        }
    }

    /// SF Symbol name for the activity type, used in list rows and module cards.
    var systemImage: String {
        switch self {
        case .run:  "figure.run"
        case .walk: "figure.walk"
        case .ride: "bicycle"
        case .hike: "figure.hiking"
        case .swim: "figure.pool.swim"
        case .ski:  "figure.skiing.downhill"
        }
    }

    /// Hex accent color for this activity, matching the Kinetics design token palette.
    ///
    /// - run:  #00C2FF (kineticsBlue)
    /// - walk: #39FF14 (kineticsGreen)
    /// - ride: #FF8C00 (kineticsOrange)
    /// - hike: #8B5CF6 (purple — effort-focused)
    /// - swim: #00C2FF (kineticsBlue — water-associated)
    /// - ski:  #8B5CF6 (purple — altitude-focused)
    var accentColorHex: String {
        switch self {
        case .run:  "#00C2FF"
        case .walk: "#39FF14"
        case .ride: "#FF8C00"
        case .hike: "#8B5CF6"
        case .swim: "#00C2FF"
        case .ski:  "#8B5CF6"
        }
    }
}

// MARK: - WorkoutSplit

/// One distance-based split (default: 1 km) recorded during a GPS workout.
///
/// Splits are immutable once created by `TrackAnalytics.buildSplits` — the
/// ViewModel accumulates them in an array and never mutates individual entries.
struct WorkoutSplit: Codable, Sendable, Identifiable, Hashable {

    // MARK: Identity

    var id: String = UUID().uuidString

    // MARK: Core Fields

    /// 1-based split number (split 1 = first kilometre, etc.).
    let splitNumber: Int
    /// Distance covered in this split, in metres.
    let distance: Double
    /// Wall-clock time elapsed during this split, in seconds.
    let duration: TimeInterval
    /// Average heart rate in bpm for this split interval. Zero when no HR sensor is connected.
    let avgHeartRate: Double

    // MARK: Computed

    /// Pace for this split in seconds per kilometre.
    ///
    /// Guards against division by zero — returns `0` when distance is negligible.
    var pace: Double {
        guard distance > 0 else { return 0 }
        return duration / (distance / 1_000.0)
    }
}

// MARK: - HRZones

/// Accumulated time (seconds) spent in each of the five standard heart-rate zones
/// during a workout. Zones are defined as percentage bands of maximum heart rate.
///
/// | Zone | % Max HR | Character      |
/// |------|----------|----------------|
/// | 1    | < 50%    | Recovery       |
/// | 2    | 50–60%   | Aerobic base   |
/// | 3    | 60–70%   | Tempo          |
/// | 4    | 70–80%   | Threshold      |
/// | 5    | > 80%    | Maximum effort |
struct HRZones: Codable, Sendable, Hashable {
    /// Recovery zone: < 50 % of max HR.
    var zone1: TimeInterval = 0
    /// Aerobic base zone: 50–60 % of max HR.
    var zone2: TimeInterval = 0
    /// Tempo zone: 60–70 % of max HR.
    var zone3: TimeInterval = 0
    /// Threshold zone: 70–80 % of max HR.
    var zone4: TimeInterval = 0
    /// Maximum effort zone: > 80 % of max HR.
    var zone5: TimeInterval = 0

    /// Total tracked HR duration — sum of all five zones.
    var total: TimeInterval { zone1 + zone2 + zone3 + zone4 + zone5 }
}

// MARK: - WorkoutResult

/// A completed GPS workout session, persisted to Firestore under the user's
/// `workouts` sub-collection.
///
/// Routes are encoded as parallel `routeLatitudes` / `routeLongitudes` arrays
/// because Firestore has no native `CLLocationCoordinate2D` type. The arrays are
/// guaranteed to have the same count; consumers zip them to reconstruct coordinates.
///
/// `segmentPaces` contains one pace value (seconds/km) per route segment
/// (consecutive location pair). It drives the map's colour-coded pace overlay —
/// each segment is coloured from blue (fast) through green and orange to red (slow).
/// An empty array is valid when fewer than two route points were recorded.
struct WorkoutResult: Codable, Identifiable, Sendable, Hashable {

    // MARK: Identity

    /// Firestore document ID — pre-populated with a UUID so documents can be written
    /// optimistically before the server acknowledges the write.
    var id: String = UUID().uuidString

    // MARK: Core Fields

    let activityType: WorkoutActivityType
    let startedAt: Date
    /// Total elapsed workout duration in seconds (excludes any auto-paused intervals).
    let duration: TimeInterval
    /// Total distance covered in metres.
    let distance: Double
    /// Average pace across the full workout in seconds per kilometre.
    let avgPaceSecondsPerKm: Double
    /// Session-average heart rate in bpm. Zero when no HR sensor was connected.
    let avgHeartRate: Double
    /// Highest instantaneous heart rate recorded during the workout, in bpm.
    let maxHeartRate: Double
    /// Cumulative positive elevation change in metres.
    let elevationGain: Double
    /// Cumulative negative elevation change in metres (stored as a positive value).
    let elevationLoss: Double
    /// Estimated energy expenditure in kilocalories.
    let calories: Double
    /// Per-kilometre (or per-mile) split records, ordered by split number ascending.
    let splits: [WorkoutSplit]
    /// Time spent in each of the five HR zones.
    let hrZones: HRZones
    /// Human-readable achievement strings detected at session end, e.g.
    /// `["Longest run ever", "First sub-5:00/km km"]`.
    var achievements: [String]
    /// Whether this workout is visible to other users (reserved for a social feed feature).
    var isPublic: Bool = false
    /// Firebase Auth UID of the owning user.
    var userId: String

    // MARK: Route Encoding

    /// Latitude component of each route waypoint, parallel to `routeLongitudes`.
    let routeLatitudes: [Double]
    /// Longitude component of each route waypoint, parallel to `routeLatitudes`.
    let routeLongitudes: [Double]
    /// Pace in seconds/km for each consecutive pair of route points.
    /// May be empty when fewer than two waypoints exist.
    let segmentPaces: [Double]

    // MARK: Computed — Formatted Display

    /// Human-readable duration string, e.g. `"42:12"` or `"1:02:05"`.
    var formattedDuration: String {
        let total = Int(duration)
        let h = total / 3_600
        let m = (total % 3_600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }

    /// Human-readable distance, e.g. `"5.23 km"` or `"840 m"`.
    var formattedDistance: String {
        distance >= 1_000
            ? String(format: "%.2f km", distance / 1_000.0)
            : String(format: "%.0f m", distance)
    }

    /// Human-readable average pace, e.g. `"4:32 /km"`. Returns `"--:-- /km"` when
    /// the workout has no valid pace (e.g. zero distance).
    var formattedAvgPace: String {
        guard avgPaceSecondsPerKm > 0 else { return "--:-- /km" }
        let m = Int(avgPaceSecondsPerKm) / 60
        let s = Int(avgPaceSecondsPerKm) % 60
        return String(format: "%d:%02d /km", m, s)
    }

    /// Abbreviated start date + time string suitable for list rows,
    /// e.g. `"Apr 29, 2026 at 7:15 AM"`.
    var formattedDate: String {
        startedAt.formatted(date: .abbreviated, time: .shortened)
    }
}
