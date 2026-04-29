import Foundation

// MARK: - SportType

/// The four sport modules available in Kinetics.
enum SportType: String, Codable, CaseIterable, Sendable {
    case striking = "striking"
    case grappling = "grappling"
    case ironTracker = "iron_tracker"
    case wallBeta = "wall_beta"

    // MARK: Display

    var displayName: String {
        switch self {
        case .striking:    "Striking Clinic"
        case .grappling:   "Grappling Lab"
        case .ironTracker: "Iron Tracker"
        case .wallBeta:    "Wall Beta"
        }
    }

    var tagline: String {
        switch self {
        case .striking:    "Track velocity & kinetic chain"
        case .grappling:   "Monitor base & leverage"
        case .ironTracker: "Analyze bar path & symmetry"
        case .wallBeta:    "Hip proximity & Dyno arcs"
        }
    }

    // MARK: SF Symbols

    var systemImage: String {
        switch self {
        case .striking:    "bolt.fill"
        case .grappling:   "person.2.fill"
        case .ironTracker: "dumbbell.fill"
        case .wallBeta:    "figure.climbing"
        }
    }

    // MARK: Brand Color

    /// Hex string for the module's accent color, used by `Color(hex:)` in the UI layer.
    var accentColor: String {
        switch self {
        case .striking:    "#FF4444"
        case .grappling:   "#FF8C00"
        case .ironTracker: "#00C2FF"
        case .wallBeta:    "#39FF14"
        }
    }
}

// MARK: - CoachingNote

/// A single piece of AI-generated coaching feedback attached to a completed session.
///
/// `category` drives visual treatment in the UI (achievement vs. technique correction vs.
/// consistency prompt). `metricKey` / `metricValue` allow the UI to highlight the specific
/// data point that triggered this note.
struct CoachingNote: Codable, Sendable, Identifiable {
    var id: String = UUID().uuidString
    /// Drives visual styling: "technique", "achievement", "strength", "consistency".
    let category: String
    /// SF Symbol name for the note's leading icon.
    let icon: String
    let headline: String
    let detail: String
    /// The `metrics` dictionary key that triggered this note, if any.
    let metricKey: String?
    /// The raw metric value that triggered this note, if any.
    let metricValue: Double?
}

// MARK: - SessionResult

/// A completed analysis session, persisted to Firestore and cached locally via SwiftData.
///
/// `metrics` is a flexible dictionary so each sport module can store its own domain-specific
/// values (e.g. `"strikeVelocityMPH"`, `"barPathDeviationCM"`) without requiring schema
/// migrations when new analytics are added to a module.
struct SessionResult: Codable, Identifiable, Sendable {
    // MARK: Identity

    /// Firestore document ID — pre-populated with a UUID string so documents can be written
    /// optimistically before the server acknowledges the write.
    var id: String = UUID().uuidString

    // MARK: Core Fields

    let sport: SportType
    let startedAt: Date
    /// Total session duration in seconds.
    let duration: TimeInterval
    /// Sport-specific performance metrics (keys defined by each Analytics module).
    var metrics: [String: Double]
    /// Firebase Auth UID of the owning user.
    var userId: String

    // MARK: Coaching Fields (optional — default values keep old Firestore documents decodable)

    /// AI-generated coaching notes produced by `CoachingEngine` after session analysis.
    var coachingNotes: [CoachingNote] = []
    /// 1-based ordinal indicating how many sessions the user has completed for this sport.
    var sessionNumber: Int = 1
    /// Personal-best values keyed by metric name, snapshot at the time this session was saved.
    var personalBests: [String: Double] = [:]

    // MARK: - Formatted Properties

    /// Human-readable duration string, e.g. "3:07".
    var formattedDuration: String {
        let totalSeconds = Int(duration)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    /// Abbreviated date + time string suitable for list rows, e.g. "Apr 29, 2026 at 4:15 PM".
    var formattedDate: String {
        startedAt.formatted(date: .abbreviated, time: .shortened)
    }
}
