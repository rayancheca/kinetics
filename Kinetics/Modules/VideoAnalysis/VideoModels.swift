import Foundation
import SwiftData

// MARK: - VideoSport

/// Sport classification result from video analysis.
enum VideoSport: String, Codable, CaseIterable, Sendable {
    case striking = "Striking"
    case grappling = "Grappling"
    case ironTracker = "Iron Tracker"
    case wallBeta = "Wall Beta"
    case gym = "Gym"
    case track = "Track"
    case unknown = "Unknown"

    var systemImage: String {
        switch self {
        case .striking:    return "figure.martial.arts"
        case .grappling:   return "figure.wrestling"
        case .ironTracker: return "dumbbell.fill"
        case .wallBeta:    return "figure.climbing"
        case .gym:         return "figure.strengthtraining.traditional"
        case .track:       return "figure.run"
        case .unknown:     return "video.fill"
        }
    }
}

// MARK: - VideoAnalysisStatus

/// Lifecycle state of a video analysis pass.
enum VideoAnalysisStatus: String, Codable, Sendable {
    case pending
    case analyzing
    case complete
    case failed
}

// MARK: - VideoSession

/// Persisted record for a single imported + analysed workout video.
///
/// `sport` and `status` are stored as raw `String` values so SwiftData can
/// persist them without custom transformers; use `videoSport` and
/// `analysisStatus` computed properties for typed access.
///
/// `metricsJSON` holds a JSON-encoded `[String: Double]` dictionary of
/// sport-specific metrics extracted during analysis.
@Model
final class VideoSession {
    var id: String
    var userId: String
    var title: String
    var sport: String           // VideoSport.rawValue
    var confidence: Double      // 0.0 – 1.0 classification confidence
    var status: String          // VideoAnalysisStatus.rawValue
    var localVideoPath: String  // relative path in app's Documents directory
    var thumbnailData: Data?    // JPEG thumbnail
    var durationSeconds: Double
    var recordedAt: Date
    var analyzedAt: Date?
    var notes: String

    /// Key metrics extracted from analysis (JSON-encoded [String: Double]).
    var metricsJSON: String

    init(
        id: String = UUID().uuidString,
        userId: String,
        title: String = "",
        sport: String = VideoSport.unknown.rawValue,
        confidence: Double = 0,
        status: String = VideoAnalysisStatus.pending.rawValue,
        localVideoPath: String,
        thumbnailData: Data? = nil,
        durationSeconds: Double = 0,
        recordedAt: Date = Date(),
        notes: String = "",
        metricsJSON: String = "{}"
    ) {
        self.id = id
        self.userId = userId
        self.title = title
        self.sport = sport
        self.confidence = confidence
        self.status = status
        self.localVideoPath = localVideoPath
        self.thumbnailData = thumbnailData
        self.durationSeconds = durationSeconds
        self.recordedAt = recordedAt
        self.notes = notes
        self.metricsJSON = metricsJSON
    }

    // MARK: - Computed helpers

    var videoSport: VideoSport {
        VideoSport(rawValue: sport) ?? .unknown
    }

    var analysisStatus: VideoAnalysisStatus {
        VideoAnalysisStatus(rawValue: status) ?? .pending
    }

    var metrics: [String: Double] {
        (try? JSONDecoder().decode([String: Double].self, from: Data(metricsJSON.utf8))) ?? [:]
    }
}
