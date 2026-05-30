import ActivityKit
import Foundation
import SwiftUI

// MARK: - LiveSessionAttributes

/// ActivityAttributes shared between the main Kinetics app and the
/// KineticsWidget extension. Defines the static + dynamic state of a
/// Live Activity displayed while a training session is in progress.
///
/// **Static (attributes):**
/// - `sportRaw` — `SportType.rawValue` so we don't pull SportType into the widget.
/// - `displayName` — pre-formatted module label.
/// - `accentHex` — module accent color hex string.
/// - `iconName` — SF Symbol shown in the lock screen + Dynamic Island.
/// - `startedAt` — start timestamp used to drive the live timer counter.
///
/// **Dynamic (ContentState):**
/// - `primaryMetric` — the headline number rendered large (e.g. velocity, kuzushi, hip prox).
/// - `primaryLabel` — the unit/label for the headline number.
/// - `secondaryMetric` — supporting metric.
/// - `secondaryLabel` — unit/label for the supporting metric.
/// - `coachCue` — current coaching cue text (may be nil).
/// - `isPaused` — whether the session is currently paused.
struct LiveSessionAttributes: ActivityAttributes {

    public struct ContentState: Codable, Hashable, Sendable {
        public var primaryMetric: String
        public var primaryLabel: String
        public var secondaryMetric: String
        public var secondaryLabel: String
        public var coachCue: String?
        public var isPaused: Bool

        public init(
            primaryMetric: String,
            primaryLabel: String,
            secondaryMetric: String = "",
            secondaryLabel: String = "",
            coachCue: String? = nil,
            isPaused: Bool = false
        ) {
            self.primaryMetric = primaryMetric
            self.primaryLabel = primaryLabel
            self.secondaryMetric = secondaryMetric
            self.secondaryLabel = secondaryLabel
            self.coachCue = coachCue
            self.isPaused = isPaused
        }
    }

    public var sportRaw: String
    public var displayName: String
    public var accentHex: String
    public var iconName: String
    public var startedAt: Date

    public init(
        sportRaw: String,
        displayName: String,
        accentHex: String,
        iconName: String,
        startedAt: Date
    ) {
        self.sportRaw = sportRaw
        self.displayName = displayName
        self.accentHex = accentHex
        self.iconName = iconName
        self.startedAt = startedAt
    }
}

// MARK: - Color hex helper (shared between widget + app)

public extension Color {
    /// Parses a `#RRGGBB` or `#RRGGBBAA` hex string into a SwiftUI Color.
    /// Falls back to white when the hex string is malformed.
    init(liveActivityHex hex: String) {
        var sanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if sanitized.hasPrefix("#") { sanitized.removeFirst() }

        let scanner = Scanner(string: sanitized)
        var value: UInt64 = 0
        guard scanner.scanHexInt64(&value) else { self = .white; return }

        let r, g, b, a: Double
        switch sanitized.count {
        case 6:
            r = Double((value & 0xFF0000) >> 16) / 255.0
            g = Double((value & 0x00FF00) >> 8)  / 255.0
            b = Double(value & 0x0000FF)         / 255.0
            a = 1.0
        case 8:
            r = Double((value & 0xFF000000) >> 24) / 255.0
            g = Double((value & 0x00FF0000) >> 16) / 255.0
            b = Double((value & 0x0000FF00) >> 8)  / 255.0
            a = Double(value & 0x000000FF)         / 255.0
        default:
            self = .white
            return
        }
        self.init(.sRGB, red: r, green: g, blue: b, opacity: a)
    }
}
