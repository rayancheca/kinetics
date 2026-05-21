import Foundation
import Observation
import SwiftData
import SwiftUI

// MARK: - VideoReportViewModel

/// ViewModel for the Video Analysis Report screen.
///
/// Owns the `VideoPlayerController`, surfaces sport-specific metrics,
/// and coordinates AI coach report generation via `AICoachService`.
@Observable
@MainActor
final class VideoReportViewModel {

    // MARK: - Types

    enum ReportSection: String, CaseIterable {
        case overview = "Overview"
        case coaching = "Coaching"
        case drills   = "Drills"
    }

    // MARK: - Inputs

    let session: VideoSession

    // MARK: - Child Controllers

    var playerController = VideoPlayerController()

    // MARK: - UI State

    var isGeneratingCoachReport = false
    var coachReportError: String?
    var selectedTipIndex: Int?
    var showSkeletonOverlay = true
    var activeSection: ReportSection = .overview

    // MARK: - Cloud Upload State

    var isUploadingToCloud = false
    var cloudUploadProgress: Double = 0.0
    var cloudUploadError: String?

    // MARK: - Init

    init(session: VideoSession) {
        self.session = session
    }

    // MARK: - Computed — Session-Level

    var sport: VideoSport { session.videoSport }
    var coachReport: CoachReport? { session.coachReport }
    var hasCoachReport: Bool { session.isAnalyzedWithAI }
    var skeletonFrames: [FrameSkeletonData] { session.skeletonFrames }
    var subjectLabel: String {
        session.subjectLabel.isEmpty ? "Unknown" : session.subjectLabel
    }

    // MARK: - Computed — Primary Metrics

    /// Returns the top sport-specific metrics formatted for display cards.
    var primaryMetrics: [(label: String, value: String, unit: String)] {
        let raw = session.metrics
        switch sport {

        case .striking:
            return buildMetrics(from: raw, keys: [
                ("max_wrist_velocity",          "Peak Strike Velocity",  "m/s",  .velocity),
                ("avg_wrist_velocity",          "Avg. Wrist Speed",      "m/s",  .velocity),
                ("max_hip_shoulder_separation", "Peak Hip-Shoulder Sep", "°",    .angle),
                ("avg_hip_shoulder_separation", "Avg. Hip Separation",   "°",    .angle),
                ("bilateral_symmetry",          "Bilateral Symmetry",    "%",    .percent),
                ("pose_detection_ratio",        "Pose Coverage",         "%",    .percent)
            ])

        case .grappling:
            return buildMetrics(from: raw, keys: [
                ("avg_hip_height",              "Avg. Hip Height",       "",     .ratio),
                ("min_hip_height",              "Min. Hip Height",       "",     .ratio),
                ("bilateral_symmetry",          "COM Stability",         "%",    .percent),
                ("avg_hip_shoulder_separation", "Hip Elevation Angle",   "°",    .angle),
                ("arms_above_head_ratio",       "Arms Raised",           "%",    .percent),
                ("pose_detection_ratio",        "Pose Coverage",         "%",    .percent)
            ])

        case .ironTracker:
            return buildMetrics(from: raw, keys: [
                ("avg_wrist_velocity",          "Bar Velocity",          "m/s",  .velocity),
                ("max_wrist_velocity",          "Peak Bar Velocity",     "m/s",  .velocity),
                ("bilateral_symmetry",          "Bilateral Symmetry",    "%",    .percent),
                ("avg_hip_shoulder_separation", "Range of Motion",       "°",    .angle),
                ("arms_above_head_ratio",       "Arms Overhead Ratio",   "%",    .percent),
                ("pose_detection_ratio",        "Pose Coverage",         "%",    .percent)
            ])

        case .wallBeta:
            return buildMetrics(from: raw, keys: [
                ("arms_above_head_ratio",       "Hip Proximity Score",   "%",    .percent),
                ("avg_hip_height",              "Avg. Hip Height",       "",     .ratio),
                ("min_hip_height",              "Min. Hip Height",       "",     .ratio),
                ("bilateral_symmetry",          "COM Variance",          "%",    .percent),
                ("avg_wrist_velocity",          "Avg. Movement Speed",   "m/s",  .velocity),
                ("pose_detection_ratio",        "Pose Coverage",         "%",    .percent)
            ])

        case .gym:
            return buildMetrics(from: raw, keys: [
                ("bilateral_symmetry",          "Rep Symmetry",          "%",    .percent),
                ("avg_hip_shoulder_separation", "Range of Motion",       "°",    .angle),
                ("avg_wrist_velocity",          "Avg. Rep Speed",        "m/s",  .velocity),
                ("arms_above_head_ratio",       "Arms Raised Ratio",     "%",    .percent),
                ("pose_detection_ratio",        "Pose Coverage",         "%",    .percent)
            ])

        case .track:
            return buildMetrics(from: raw, keys: [
                ("avg_wrist_velocity",          "Cadence",               "spm",  .velocity),
                ("bilateral_symmetry",          "Stride Symmetry",       "%",    .percent),
                ("avg_hip_shoulder_separation", "Posture Score",         "°",    .angle),
                ("arms_above_head_ratio",       "Arm Drive",             "%",    .percent),
                ("pose_detection_ratio",        "Pose Coverage",         "%",    .percent)
            ])

        case .unknown:
            return buildMetrics(from: raw, keys: [
                ("avg_wrist_velocity",          "Avg. Speed",            "m/s",  .velocity),
                ("bilateral_symmetry",          "Symmetry",              "%",    .percent),
                ("pose_detection_ratio",        "Pose Coverage",         "%",    .percent)
            ])
        }
    }

    // MARK: - Lifecycle

    /// Called from the view's `onAppear`. Sets up the player with the local video.
    func onAppear(modelContext: ModelContext) {
        guard let url = resolvedVideoURL() else { return }
        playerController.setup(url: url)
    }

    /// Called from the view's `onDisappear`. Stops playback and removes observers.
    func cleanup() {
        playerController.cleanup()
    }

    // MARK: - AI Coach Report

    /// Generates an AI coaching report for this session and persists it to SwiftData.
    func generateCoachReport(userId: String, modelContext: ModelContext) async {
        guard !isGeneratingCoachReport else { return }
        isGeneratingCoachReport = true
        coachReportError = nil

        defer { isGeneratingCoachReport = false }

        // Resolve optional body context from latest BodyMeasurement.
        let bodyContext = fetchBodyContext(userId: userId, modelContext: modelContext)

        // Build human-readable key observations from raw metrics.
        let keyObservations = buildKeyObservations(for: sport, metrics: session.metrics)

        // Fetch prior session count for experience-level calibration.
        let sessionCount = fetchSessionCount(userId: userId, modelContext: modelContext)

        do {
            let report = try await AICoachService.shared.generateReport(
                sport: sport.rawValue,
                metrics: session.metrics,
                bodyContext: bodyContext,
                sessionCount: sessionCount,
                subjectLabel: subjectLabel,
                videoDurationSeconds: session.durationSeconds,
                keyObservations: keyObservations
            )

            guard let jsonString = report.jsonString() else {
                coachReportError = "Failed to encode coach report."
                return
            }

            session.coachReportJSON = jsonString
            session.analysisVersion = 1

            do {
                try modelContext.save()
            } catch {
                coachReportError = "Failed to save report: \(error.localizedDescription)"
            }

        } catch {
            coachReportError = error.localizedDescription
        }
    }

    // MARK: - Cloud Upload

    /// Uploads the session's local video file to Firebase Storage.
    /// Updates `cloudUploadProgress` during the transfer and writes the
    /// returned download URL back to `session.cloudStorageURL`.
    func uploadToCloud(userId: String, modelContext: ModelContext) async {
        guard !isUploadingToCloud else { return }

        let path = session.localVideoPath
        guard !path.isEmpty else {
            cloudUploadError = "No local video file found for this session."
            return
        }

        let localURL: URL
        if path.hasPrefix("/") {
            localURL = URL(fileURLWithPath: path)
        } else {
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            localURL = docs.appendingPathComponent(path)
        }

        guard FileManager.default.fileExists(atPath: localURL.path) else {
            cloudUploadError = "Local video file is missing — re-import the video to enable cloud upload."
            return
        }

        isUploadingToCloud = true
        cloudUploadProgress = 0.0
        cloudUploadError = nil

        do {
            // `uploadVideo` is an `actor` method; we capture `self` (the VM, a
            // class) via a `@Sendable` closure that hops back to MainActor to
            // update observable state.
            let downloadURL = try await VideoStorageService.shared.uploadVideo(
                localURL: localURL,
                userId: userId,
                videoId: session.id,
                progressHandler: { [weak self] fraction in
                    Task { @MainActor [weak self] in
                        self?.cloudUploadProgress = fraction
                    }
                }
            )

            session.cloudStorageURL = downloadURL
            try? modelContext.save()

        } catch {
            cloudUploadError = error.localizedDescription
        }

        isUploadingToCloud = false
    }

    // MARK: - Seek to Tip

    /// Seeks the video player to the timestamp of the given tip.
    func seekToTip(_ tip: CoachReport.TimestampedTip) {
        playerController.seek(to: tip.timestampSeconds)
        if !playerController.isPlaying {
            playerController.play()
        }
    }

    // MARK: - Private Helpers

    /// Resolves the local video URL from `session.localVideoPath`.
    /// Handles both absolute paths (starts with "/") and paths relative
    /// to the Documents/KineticsVideos directory.
    private func resolvedVideoURL() -> URL? {
        let path = session.localVideoPath
        guard !path.isEmpty else { return nil }

        if path.hasPrefix("/") {
            let url = URL(fileURLWithPath: path)
            return FileManager.default.fileExists(atPath: url.path) ? url : nil
        }

        let docs = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        )[0]
        let url = docs.appendingPathComponent(path)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// Fetches the most-recent `BodyMeasurement` for the user and converts
    /// it to a `BodyCompositionContext` for the AI prompt.
    private func fetchBodyContext(
        userId: String,
        modelContext: ModelContext
    ) -> BodyCompositionContext? {
        var descriptor = FetchDescriptor<BodyMeasurement>(
            predicate: #Predicate<BodyMeasurement> { m in
                m.userId == userId
            },
            sortBy: [SortDescriptor(\BodyMeasurement.recordedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1

        guard
            let latest = try? modelContext.fetch(descriptor).first,
            latest.weightKg > 0
        else { return nil }

        return BodyCompositionContext(
            weightKg: latest.weightKg,
            heightCm: latest.heightCm > 0 ? latest.heightCm : 170,
            bodyFatPercent: latest.bodyFatPercent,
            ageYears: latest.ageYears > 0 ? latest.ageYears : 25,
            skeletalMuscleMassKg: latest.skeletalMuscleMassKg
        )
    }

    /// Counts total completed `VideoSession` records for this user to gauge
    /// experience level for the AI prompt.
    private func fetchSessionCount(
        userId: String,
        modelContext: ModelContext
    ) -> Int {
        let descriptor = FetchDescriptor<VideoSession>(
            predicate: #Predicate<VideoSession> { s in
                s.userId == userId && s.status == "complete"
            }
        )
        return (try? modelContext.fetchCount(descriptor)) ?? 1
    }

    /// Converts raw metric values into natural-language coaching observations.
    private func buildKeyObservations(
        for sport: VideoSport,
        metrics: [String: Double]
    ) -> [String] {
        var obs: [String] = []

        if let vel = metrics["max_wrist_velocity"] {
            obs.append(String(format: "Peak wrist/bar velocity: %.2f m/s", vel))
        }
        if let sym = metrics["bilateral_symmetry"] {
            obs.append(String(format: "Bilateral symmetry: %.0f%%", sym * 100))
        }
        if let sep = metrics["avg_hip_shoulder_separation"] {
            obs.append(String(format: "Average hip-shoulder separation: %.1f°", sep))
        }
        if let maxSep = metrics["max_hip_shoulder_separation"] {
            obs.append(String(format: "Peak hip-shoulder separation: %.1f°", maxSep))
        }
        if let hip = metrics["avg_hip_height"] {
            obs.append(String(format: "Average hip height (normalised): %.2f", hip))
        }
        if let arms = metrics["arms_above_head_ratio"] {
            obs.append(String(format: "Arms-above-head ratio: %.0f%%", arms * 100))
        }
        if let cov = metrics["pose_detection_ratio"] {
            obs.append(String(format: "Pose detected in %.0f%% of frames", cov * 100))
        }
        return obs
    }
}

// MARK: - Metric Formatting Helpers

private enum MetricFormat {
    case velocity   // m/s   → "%.2f"
    case angle      // degrees → "%.1f"
    case percent    // 0-1 ratio → "%.0f" * 100
    case ratio      // normalised 0-1 → "%.2f"
}

private func buildMetrics(
    from raw: [String: Double],
    keys: [(String, String, String, MetricFormat)]
) -> [(label: String, value: String, unit: String)] {
    keys.compactMap { (key, label, unit, fmt) in
        guard let v = raw[key] else { return nil }
        let formatted: String
        switch fmt {
        case .velocity: formatted = String(format: "%.2f", v)
        case .angle:    formatted = String(format: "%.1f", v)
        case .percent:  formatted = String(format: "%.0f", v * 100)
        case .ratio:    formatted = String(format: "%.2f", v)
        }
        return (label: label, value: formatted, unit: unit)
    }
}
