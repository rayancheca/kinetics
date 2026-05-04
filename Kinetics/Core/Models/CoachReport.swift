import Foundation

// MARK: - CoachReport

/// A fully-structured AI coaching report generated after video analysis.
/// All types are pure `Codable` value types — no SwiftData persistence.
/// Persisted indirectly via `VideoSession.coachReportJSON` (JSON string).
struct CoachReport: Codable, Sendable {

    // MARK: - Top-Level Fields

    let summary: String
    let overallScore: Int                        // 0–100
    let tips: [TimestampedTip]
    let strengths: [String]
    let improvements: [String]
    let drillRecommendations: [DrillRecommendation]
    let generatedAt: Date

    // MARK: - Nested Types

    /// A coaching observation anchored to a specific moment in the video.
    struct TimestampedTip: Codable, Identifiable, Sendable {
        let id: String
        let timestampSeconds: Double             // Seconds into the video
        let category: TipCategory
        let severity: TipSeverity
        let text: String

        // MARK: TipCategory

        enum TipCategory: String, Codable, Sendable {
            case form
            case power
            case technique
            case safety
            case breathing
            case positioning
        }

        // MARK: TipSeverity

        enum TipSeverity: String, Codable, Sendable {
            case info
            case warning
            case critical
        }
    }

    /// A recommended practice drill surfaced by the AI coach.
    struct DrillRecommendation: Codable, Identifiable, Sendable {
        let id: String
        let name: String
        let reason: String
        let sport: String
        let durationMinutes: Int
    }
}

// MARK: - Parsing & Serialisation

extension CoachReport {

    /// Decodes a `CoachReport` from a JSON string. Returns `nil` if the string is
    /// empty, malformed, or missing required fields.
    static func parse(from jsonString: String) -> CoachReport? {
        guard !jsonString.isEmpty,
              let data = jsonString.data(using: .utf8) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try? decoder.decode(CoachReport.self, from: data)
    }

    /// Encodes this `CoachReport` to a compact JSON string. Returns `nil` on
    /// encoding failure (should never occur for valid model data).
    func jsonString() -> String? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        guard let data = try? encoder.encode(self) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

// MARK: - Convenience

extension CoachReport {

    /// An empty placeholder used while a report is loading or unavailable.
    static let empty = CoachReport(
        summary: "",
        overallScore: 0,
        tips: [],
        strengths: [],
        improvements: [],
        drillRecommendations: [],
        generatedAt: Date(timeIntervalSince1970: 0)
    )

    /// Returns `true` when this report carries real content (non-empty summary,
    /// valid score range, generated after the Unix epoch).
    var hasContent: Bool {
        !summary.isEmpty && overallScore > 0 && generatedAt.timeIntervalSince1970 > 0
    }

    /// Tips filtered to `critical` severity — useful for surfacing urgent alerts.
    var criticalTips: [TimestampedTip] {
        tips.filter { $0.severity == .critical }
    }
}
