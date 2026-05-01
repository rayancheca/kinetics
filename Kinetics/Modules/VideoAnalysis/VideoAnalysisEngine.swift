import AVFoundation
import CoreImage
import Foundation
import Vision

// MARK: - VideoAnalysisResult

/// The output of a completed video analysis pass.
struct VideoAnalysisResult: Sendable {
    let sport: VideoSport
    let confidence: Double
    let metrics: [String: Double]
    let frameCount: Int
    let durationSeconds: Double
}

// MARK: - AnalysisError

enum AnalysisError: Error, LocalizedError {
    case emptyVideo
    case noFrames

    var errorDescription: String? {
        switch self {
        case .emptyVideo:  return "The video has zero duration and cannot be analysed."
        case .noFrames:    return "No frames could be extracted from the video."
        }
    }
}

// MARK: - VideoAnalysisEngine

/// An actor that samples frames from a video file, runs body-pose detection on
/// each frame, classifies the sport shown, and returns key biomechanics metrics.
///
/// **Design notes:**
/// - Running as an `actor` keeps all Vision work off the main thread, matching
///   the pattern used by `PoseDetectionEngine` for the live-camera path.
/// - Frames are decoded by `AVAssetImageGenerator` at a capped resolution
///   (640 × 640) to stay within the Vision pipeline's sweet spot — large enough
///   for accurate joint localization, small enough to keep per-frame latency low.
/// - `VNImageRequestHandler` (not `VNSequenceRequestHandler`) is used here
///   because the frames come from a file, not a temporal capture stream. We
///   don't have continuous sequence history between sampled frames, so the
///   sequence handler's temporal smoothing would be misleading.
/// - Sport classification is heuristic rather than ML-based: we score four
///   observable features (arms-above-head ratio, wrist velocity, hip height,
///   bilateral symmetry) and pick the highest-scoring `VideoSport`. This is
///   intentionally simple — it runs entirely on-device with zero network calls.
actor VideoAnalysisEngine {

    // MARK: - Singleton

    static let shared = VideoAnalysisEngine()

    // MARK: - Private types

    private struct ClassificationResult {
        let sport: VideoSport
        let confidence: Double
    }

    // MARK: - Public API

    /// Analyses a video file and returns a sport classification with metrics.
    ///
    /// Frames are sampled evenly across the video's duration. If the video is
    /// too short to yield any frames the method throws `AnalysisError.emptyVideo`.
    ///
    /// - Parameters:
    ///   - videoURL: Local file URL of the video to analyse.
    ///   - maxFrames: Maximum number of frames to sample (default 60). Actual
    ///     count may be lower if the frame generator fails on some time offsets.
    /// - Returns: `VideoAnalysisResult` with sport, confidence, and metrics.
    func analyze(videoURL: URL, maxFrames: Int = 60) async throws -> VideoAnalysisResult {
        let asset = AVURLAsset(url: videoURL)
        let duration = try await asset.load(.duration)
        let durationSeconds = CMTimeGetSeconds(duration)

        guard durationSeconds > 0 else { throw AnalysisError.emptyVideo }

        let frames = try await sampleFrames(from: asset, count: maxFrames, duration: duration)

        guard !frames.isEmpty else { throw AnalysisError.noFrames }

        let poseObservations = detectPoses(in: frames)

        let classification = classifySport(from: poseObservations, duration: durationSeconds)
        let metrics = extractMetrics(
            from: poseObservations,
            duration: durationSeconds,
            sport: classification.sport
        )

        return VideoAnalysisResult(
            sport: classification.sport,
            confidence: classification.confidence,
            metrics: metrics,
            frameCount: frames.count,
            durationSeconds: durationSeconds
        )
    }

    // MARK: - Frame sampling

    /// Samples up to `count` frames evenly distributed across `duration`.
    ///
    /// `AVAssetImageGenerator.copyCGImage(at:actualTime:)` is used with a
    /// ±100 ms tolerance so the generator can pick the nearest key-frame rather
    /// than performing an expensive seek to an exact non-key frame.
    private func sampleFrames(
        from asset: AVURLAsset,
        count: Int,
        duration: CMTime
    ) async throws -> [CGImage] {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 640, height: 640)
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.1, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter  = CMTime(seconds: 0.1, preferredTimescale: 600)

        let totalSeconds = CMTimeGetSeconds(duration)
        let interval = totalSeconds / Double(count)

        let times = (0..<count).map { i in
            CMTime(
                seconds: Double(i) * interval + interval / 2,
                preferredTimescale: 600
            )
        }

        var frames: [CGImage] = []
        frames.reserveCapacity(count)
        for time in times {
            if let image = try? generator.copyCGImage(at: time, actualTime: nil) {
                frames.append(image)
            }
        }
        return frames
    }

    // MARK: - Pose detection

    /// Runs `VNDetectHumanBodyPoseRequest` on each frame.
    ///
    /// Returns one dictionary per frame. An empty dictionary means no person
    /// was detected in that frame — callers must tolerate this gracefully.
    private func detectPoses(
        in frames: [CGImage]
    ) -> [[VNHumanBodyPoseObservation.JointName: CGPoint]] {
        var allPoses: [[VNHumanBodyPoseObservation.JointName: CGPoint]] = []
        allPoses.reserveCapacity(frames.count)

        // Reuse a single request object across frames to avoid repeated allocation.
        let request = VNDetectHumanBodyPoseRequest()

        let jointNames: [VNHumanBodyPoseObservation.JointName] = [
            .leftWrist,     .rightWrist,
            .leftElbow,     .rightElbow,
            .leftShoulder,  .rightShoulder,
            .leftHip,       .rightHip,
            .leftKnee,      .rightKnee,
            .leftAnkle,     .rightAnkle,
            .nose,          .neck,          .root,
        ]

        for frame in frames {
            let handler = VNImageRequestHandler(cgImage: frame, options: [:])
            try? handler.perform([request])

            guard let observation = request.results?.first else {
                allPoses.append([:])
                continue
            }

            var joints: [VNHumanBodyPoseObservation.JointName: CGPoint] = [:]
            for name in jointNames {
                // Only accept joints the model has reasonable confidence in.
                guard let point = try? observation.recognizedPoint(name),
                      point.confidence > 0.3 else { continue }
                // Vision normalizes to (0,0) = bottom-left, (1,1) = top-right.
                joints[name] = CGPoint(x: point.location.x, y: point.location.y)
            }
            allPoses.append(joints)
        }

        return allPoses
    }

    // MARK: - Sport classification

    /// Scores each `VideoSport` using four observable motion features and
    /// returns the highest scorer together with a normalized confidence value.
    ///
    /// Feature descriptions:
    /// - **armsAboveRatio**: Fraction of frames where at least one wrist is
    ///   above the same-side shoulder in the Vision Y axis (0 = floor, 1 = top).
    ///   High ratio → climbing or overhead lifting.
    /// - **avgWristVelocity**: Mean frame-to-frame right-wrist displacement.
    ///   High velocity → striking.
    /// - **lowHipRatio**: Fraction of frames where the root (pelvis) Y < 0.35.
    ///   High ratio → grappling (guard / takedown) or powerlifting bottom position.
    /// - **avgSymmetry**: Fraction of frames where left and right wrists are
    ///   within 10% of height — bilateral lifts (barbell pressing, squats).
    private func classifySport(
        from poses: [[VNHumanBodyPoseObservation.JointName: CGPoint]],
        duration: Double
    ) -> ClassificationResult {
        guard !poses.isEmpty else {
            return ClassificationResult(sport: .unknown, confidence: 0)
        }

        let totalFrames = Double(poses.count)

        // Feature: arms above shoulder height (Vision Y: 0 = bottom, 1 = top).
        let armsAboveCount = poses.filter { pose in
            let leftAbove  = (pose[.leftWrist]?.y  ?? 0) > (pose[.leftShoulder]?.y  ?? 1)
            let rightAbove = (pose[.rightWrist]?.y ?? 0) > (pose[.rightShoulder]?.y ?? 1)
            return leftAbove || rightAbove
        }.count
        let armsAboveRatio = Double(armsAboveCount) / totalFrames

        // Feature: frame-to-frame right-wrist velocity.
        let wristVelocities = computeWristVelocities(poses: poses)
        let avgWristVelocity = wristVelocities.isEmpty
            ? 0
            : wristVelocities.reduce(0, +) / Double(wristVelocities.count)
        let maxWristVelocity = wristVelocities.max() ?? 0

        // Feature: low hip / pelvis position (grappling or bottom of a lift).
        let lowHipCount = poses.filter { ($0[.root]?.y ?? 0.5) < 0.35 }.count
        let lowHipRatio = Double(lowHipCount) / totalFrames

        // Feature: narrow foot stance (climbing vs. wide powerlifting stance).
        let narrowStanceCount = poses.filter { pose in
            guard let la = pose[.leftAnkle], let ra = pose[.rightAnkle] else { return false }
            return abs(la.x - ra.x) < 0.2
        }.count
        let narrowRatio = Double(narrowStanceCount) / totalFrames

        // Feature: bilateral wrist height symmetry (barbell lifts).
        let symmetryScores: [Double] = poses.compactMap { pose in
            guard let lw = pose[.leftWrist], let rw = pose[.rightWrist] else { return nil }
            return abs(lw.y - rw.y) < 0.1 ? 1.0 : 0.0
        }
        let avgSymmetry = symmetryScores.isEmpty
            ? 0
            : symmetryScores.reduce(0, +) / Double(symmetryScores.count)

        // Score each sport. Coefficients weight features toward that sport's
        // characteristic movement signature.
        var scores: [VideoSport: Double] = [
            .wallBeta:    armsAboveRatio   * 0.6  + narrowRatio      * 0.4,
            .striking:    min(1.0, avgWristVelocity * 3) * 0.5
                              + (maxWristVelocity > 0.05 ? 0.5 : 0),
            .grappling:   lowHipRatio      * 0.7  + (1 - armsAboveRatio) * 0.3,
            .ironTracker: avgSymmetry      * 0.5  + lowHipRatio      * 0.3
                              + (armsAboveRatio > 0.3 ? 0.2 : 0),
            .gym:         avgSymmetry      * 0.4  + (1 - armsAboveRatio) * 0.3
                              + lowHipRatio * 0.3,
            .track:       (1 - lowHipRatio) * 0.5 + avgWristVelocity  * 0.5,
        ]

        // Floor scores at zero to avoid negative contributions.
        scores = scores.mapValues { max(0, $0) }

        let sorted = scores.sorted { $0.value > $1.value }
        guard let top = sorted.first, top.value > 0.1 else {
            return ClassificationResult(sport: .unknown, confidence: 0)
        }

        let total = scores.values.reduce(0, +)
        let rawConfidence = total > 0 ? top.value / total : 0
        // Boost confidence slightly since the top scorer genuinely dominates, but
        // cap at 0.95 — we never claim certainty from heuristics alone.
        let confidence = min(rawConfidence * 1.5, 0.95)

        return ClassificationResult(sport: top.key, confidence: confidence)
    }

    // MARK: - Metrics extraction

    /// Extracts a sport-agnostic set of biomechanics metrics from pose data.
    ///
    /// All values use Vision's normalized coordinate space (0..1) except where
    /// noted. Consumers can apply `BiomechanicsCalculator` for unit conversion.
    private func extractMetrics(
        from poses: [[VNHumanBodyPoseObservation.JointName: CGPoint]],
        duration: Double,
        sport: VideoSport
    ) -> [String: Double] {
        var metrics: [String: Double] = [:]

        // Wrist velocity (normalized displacement per frame).
        let wristVelocities = computeWristVelocities(poses: poses)
        if !wristVelocities.isEmpty {
            metrics["avg_wrist_velocity"] = wristVelocities.reduce(0, +) / Double(wristVelocities.count)
            metrics["max_wrist_velocity"] = wristVelocities.max() ?? 0
        }

        // Hip height: posture depth indicator (low = crouching / grappling).
        let hipHeights = poses.compactMap { $0[.root]?.y }
        if !hipHeights.isEmpty {
            metrics["avg_hip_height"] = hipHeights.reduce(0, +) / Double(hipHeights.count)
            metrics["min_hip_height"] = hipHeights.min() ?? 0
        }

        // Arms-above-head ratio.
        let armsAboveCount = poses.filter { pose in
            (pose[.leftWrist]?.y ?? 0) > (pose[.leftShoulder]?.y ?? 1)
            || (pose[.rightWrist]?.y ?? 0) > (pose[.rightShoulder]?.y ?? 1)
        }.count
        metrics["arms_above_head_ratio"] = Double(armsAboveCount) / Double(max(poses.count, 1))

        // Bilateral wrist symmetry (0 = fully asymmetric, 1 = perfectly symmetric).
        let symmetryValues: [Double] = poses.compactMap { pose in
            guard let lw = pose[.leftWrist], let rw = pose[.rightWrist] else { return nil }
            // Score falls linearly from 1 → 0 as height difference grows to 0.2 units.
            return max(0, 1.0 - abs(lw.y - rw.y) * 5.0)
        }
        if !symmetryValues.isEmpty {
            metrics["bilateral_symmetry"] = symmetryValues.reduce(0, +) / Double(symmetryValues.count)
        }

        // Hip-shoulder separation (striking power indicator, degrees-equivalent).
        let separationValues: [Double] = poses.compactMap { pose in
            guard let lh = pose[.leftHip],   let rh = pose[.rightHip],
                  let ls = pose[.leftShoulder], let rs = pose[.rightShoulder]
            else { return nil }
            return BiomechanicsCalculator.calculateHipShoulderSeparation(
                leftHip:       lh, rightHip:       rh,
                leftShoulder:  ls, rightShoulder:  rs
            )
        }
        if !separationValues.isEmpty {
            metrics["avg_hip_shoulder_separation"] = separationValues.reduce(0, +) / Double(separationValues.count)
            metrics["max_hip_shoulder_separation"] = separationValues.map(abs).max() ?? 0
        }

        // Pose coverage: fraction of frames where a person was detected at all.
        let detectedCount = poses.filter { !$0.isEmpty }.count
        metrics["pose_detection_ratio"] = Double(detectedCount) / Double(max(poses.count, 1))

        return metrics
    }

    // MARK: - Private helpers

    /// Returns the Euclidean frame-to-frame displacement of the right wrist
    /// for each consecutive pair of pose dictionaries.
    private func computeWristVelocities(
        poses: [[VNHumanBodyPoseObservation.JointName: CGPoint]]
    ) -> [Double] {
        var velocities: [Double] = []
        velocities.reserveCapacity(max(0, poses.count - 1))

        for i in 1..<poses.count {
            guard let prev = poses[i - 1][.rightWrist],
                  let curr = poses[i][.rightWrist] else { continue }
            let dx = curr.x - prev.x
            let dy = curr.y - prev.y
            velocities.append(sqrt(Double(dx * dx + dy * dy)))
        }

        return velocities
    }
}
