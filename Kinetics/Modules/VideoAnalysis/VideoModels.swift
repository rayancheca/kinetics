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

// MARK: - FrameSkeletonData

/// A single-frame snapshot of all detected joint positions for one subject.
/// Stored as compact JSON in `VideoSession.skeletonFramesJSON` to avoid the
/// overhead of a separate SwiftData entity for every frame.
struct FrameSkeletonData: Codable, Sendable {

    /// Offset in seconds from the start of the video clip.
    let timestampSeconds: Double

    /// Joint name (matching `VNHumanBodyPoseObservation.JointName.rawValue`)
    /// mapped to `[normalizedX, normalizedY, confidence]`.
    let joints: [String: [Double]]

    /// The subject label assigned to this skeleton ("You", "Person 2", "Unknown").
    let subjectLabel: String
}

// MARK: - VideoAnalysisResult

/// The output of a completed video analysis pass.
struct VideoAnalysisResult: Sendable {
    let sport: VideoSport
    let confidence: Double
    let durationSeconds: Double
    let metrics: [String: Double]
    /// Display label for the primary subject identified during analysis.
    let subjectLabel: String
    /// Per-frame skeleton snapshots captured during analysis.
    let skeletonFrames: [FrameSkeletonData]
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
///
/// `coachReportJSON` and `skeletonFramesJSON` hold JSON-encoded value types
/// that are decoded on demand via computed properties to avoid keeping large
/// object graphs in memory at all times.
@Model
final class VideoSession {
    // MARK: - Core Fields

    var id: String
    var userId: String
    var title: String
    var sport: String           // VideoSport.rawValue
    var confidence: Double      // 0.0 – 1.0 classification confidence
    var status: String          // VideoAnalysisStatus.rawValue
    var localVideoPath: String  // Relative path in app's Documents directory
    var thumbnailData: Data?    // JPEG thumbnail
    var durationSeconds: Double
    var recordedAt: Date
    var analyzedAt: Date?
    var notes: String

    /// Key metrics extracted from analysis (JSON-encoded [String: Double]).
    var metricsJSON: String

    // MARK: - Enhanced Analysis Fields

    /// Display label for the primary subject ("You", "Person 2", "Unknown").
    var subjectLabel: String = ""

    /// JSON-encoded `CoachReport`. Decoded on demand via `coachReport` computed property.
    var coachReportJSON: String = ""

    /// Firebase Storage download URL for the uploaded video, or empty string when
    /// the video has not yet been uploaded.
    var cloudStorageURL: String = ""

    /// Analysis pipeline version. 0 = original heuristic pass, 1 = enhanced AI pass.
    var analysisVersion: Int = 0

    /// JSON-encoded `[FrameSkeletonData]`. Decoded on demand via `skeletonFrames`.
    var skeletonFramesJSON: String = ""

    // MARK: - Init

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

    // MARK: - Computed Helpers

    var videoSport: VideoSport {
        VideoSport(rawValue: sport) ?? .unknown
    }

    var analysisStatus: VideoAnalysisStatus {
        VideoAnalysisStatus(rawValue: status) ?? .pending
    }

    var metrics: [String: Double] {
        (try? JSONDecoder().decode([String: Double].self, from: Data(metricsJSON.utf8))) ?? [:]
    }

    /// Decodes and returns the AI coaching report, or `nil` when none is available.
    var coachReport: CoachReport? {
        CoachReport.parse(from: coachReportJSON)
    }

    /// Decodes and returns the per-frame skeleton snapshots captured during analysis.
    var skeletonFrames: [FrameSkeletonData] {
        guard !skeletonFramesJSON.isEmpty,
              let data = skeletonFramesJSON.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([FrameSkeletonData].self, from: data)) ?? []
    }

    /// `true` when this session was processed by the enhanced AI pipeline and
    /// a coaching report is present.
    var isAnalyzedWithAI: Bool {
        analysisVersion >= 1 && !coachReportJSON.isEmpty
    }
}
