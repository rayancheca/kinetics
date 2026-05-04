import AVFoundation
import CoreImage
import Foundation
import Vision

// MARK: - AnalysisError

enum AnalysisError: Error, LocalizedError {
    case emptyVideo
    case noFrames
    case analysisError(Error)

    var errorDescription: String? {
        switch self {
        case .emptyVideo:
            return "The video has zero duration and cannot be analysed."
        case .noFrames:
            return "No frames could be extracted from the video."
        case .analysisError(let underlying):
            return "Analysis failed: \(underlying.localizedDescription)"
        }
    }
}

// MARK: - VideoAnalysisEngine

/// An actor that samples frames from a video file, runs body-pose detection on
/// each frame, identifies the primary subject via face matching, classifies the
/// sport shown, computes per-sport biomechanics metrics, and returns the result
/// together with per-frame skeleton data for playback overlay.
///
/// **Concurrency model:**
/// All work executes inside the actor's serial executor — no additional queues
/// are needed. `VNImageRequestHandler` instances are created per-frame and never
/// shared across calls. Joint coordinates are extracted from
/// `VNHumanBodyPoseObservation` immediately (before any actor-boundary crossing)
/// and stored in the `Sendable` `FramePoseData` value type.
actor VideoAnalysisEngine {

    // MARK: - Singleton

    static let shared = VideoAnalysisEngine()

    // MARK: - Private value types

    /// Value-type snapshot of a single frame's pose data. All fields are value
    /// types so the struct is `Sendable` without annotation.
    private struct FramePoseData: Sendable {
        /// Offset from video start in seconds.
        let timestampSeconds: Double
        /// Pre-extracted joint positions: joint key → [normalizedX, normalizedY, confidence].
        let joints: [String: [Double]]
        /// The source image retained only for the face-detection pass.
        let cgImage: CGImage
    }

    /// Internal classification result before building the public return value.
    private struct ClassificationResult {
        let sport: VideoSport
        let confidence: Double
    }

    // MARK: - Public API

    /// Analyses a video file and returns a sport classification, biomechanics
    /// metrics, subject label, and per-frame skeleton data.
    ///
    /// - Parameters:
    ///   - videoURL: Local file URL of the video to analyse.
    ///   - faceProfileData: Optional `NSKeyedArchiver`-encoded
    ///     `VNFeaturePrintObservation` representing the user's stored face
    ///     profile. Pass `nil` to skip subject identification — all subjects
    ///     will be labelled `"Unknown"`.
    ///   - maxFrames: Maximum number of frames to sample (default 60).
    /// - Returns: `VideoAnalysisResult` with sport, confidence, metrics,
    ///   subject label, and skeleton frames.
    func analyze(
        videoURL: URL,
        faceProfileData: Data? = nil,
        maxFrames: Int = 60
    ) async throws -> VideoAnalysisResult {

        // 1. Load asset duration.
        let asset = AVURLAsset(url: videoURL)
        let duration = try await asset.load(.duration)
        let durationSeconds = CMTimeGetSeconds(duration)
        guard durationSeconds > 0 else { throw AnalysisError.emptyVideo }

        // 2. Sample frames and extract pose data.
        let framePoses = try sampleAndDetectPoses(
            from: asset,
            count: maxFrames,
            duration: duration
        )
        guard framePoses.count >= 3 else { throw AnalysisError.noFrames }

        // 3. Classify sport using the four-feature heuristic.
        let classification = classifySport(from: framePoses, duration: durationSeconds)

        // 4. Run sport-specific metric extraction.
        let metrics = computeMetrics(
            for: classification.sport,
            poses: framePoses,
            duration: durationSeconds
        )

        // 5. Identify the primary subject via face detection.
        let subjectLabel = await detectSubjectLabel(
            in: framePoses,
            faceProfileData: faceProfileData
        )

        // 6. Build per-frame skeleton array for playback overlay.
        let skeletonFrames = framePoses.map { frame in
            FrameSkeletonData(
                timestampSeconds: frame.timestampSeconds,
                joints: frame.joints,
                subjectLabel: subjectLabel
            )
        }

        return VideoAnalysisResult(
            sport: classification.sport,
            confidence: classification.confidence,
            durationSeconds: durationSeconds,
            metrics: metrics,
            subjectLabel: subjectLabel,
            skeletonFrames: skeletonFrames
        )
    }

    // MARK: - Frame sampling + pose detection

    /// Samples up to `count` frames evenly distributed across `duration`,
    /// runs `VNDetectHumanBodyPoseRequest` on each frame, and returns compact
    /// `FramePoseData` value types with joint coordinates already extracted.
    ///
    /// Joints are extracted inline — inside the `VNImageRequestHandler` result
    /// handler — so the `VNHumanBodyPoseObservation` reference type never crosses
    /// an isolation boundary.
    private func sampleAndDetectPoses(
        from asset: AVURLAsset,
        count: Int,
        duration: CMTime
    ) throws -> [FramePoseData] {

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

        let request = VNDetectHumanBodyPoseRequest()
        var results: [FramePoseData] = []
        results.reserveCapacity(count)

        for time in times {
            guard let cgImage = try? generator.copyCGImage(at: time, actualTime: nil) else {
                continue
            }
            let ts = CMTimeGetSeconds(time)
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            try? handler.perform([request])

            // Extract joints immediately — before storing cgImage across any boundary.
            let joints: [String: [Double]]
            if let observation = request.results?.first {
                joints = buildJointDict(from: observation)
            } else {
                joints = [:]
            }

            results.append(FramePoseData(
                timestampSeconds: ts,
                joints: joints,
                cgImage: cgImage
            ))
        }

        return results
    }

    // MARK: - Joint extraction helper

    /// Builds a compact `[String: [Double]]` joint dictionary from a pose
    /// observation. Keys are the raw string values of `VNRecognizedPointKey`.
    /// Values are `[normalizedX, normalizedY, confidence]`.
    private func buildJointDict(
        from observation: VNHumanBodyPoseObservation
    ) -> [String: [Double]] {
        let jointNames: [VNHumanBodyPoseObservation.JointName] = [
            .nose, .neck, .leftShoulder, .rightShoulder,
            .leftElbow, .rightElbow, .leftWrist, .rightWrist,
            .root, .leftHip, .rightHip,
            .leftKnee, .rightKnee, .leftAnkle, .rightAnkle,
        ]
        var dict: [String: [Double]] = [:]
        dict.reserveCapacity(jointNames.count)
        for name in jointNames {
            guard let point = try? observation.recognizedPoint(name),
                  point.confidence > 0.3 else { continue }
            // VNHumanBodyPoseObservation.JointName.rawValue is VNRecognizedPointKey;
            // VNRecognizedPointKey.rawValue is String.
            dict[name.rawValue.rawValue] = [
                Double(point.location.x),
                Double(point.location.y),
                Double(point.confidence),
            ]
        }
        return dict
    }

    // MARK: - Face detection / subject identification

    /// Runs face detection on the first 10 sampled frames and returns a subject
    /// label via majority vote.
    ///
    /// If `faceProfileData` is provided, the detected face feature print is
    /// compared against the stored profile. A distance below 0.75 identifies the
    /// subject as "You". Additional faces in a frame are labelled "Person 2".
    /// When no face is detected in a frame that frame is excluded from voting.
    private func detectSubjectLabel(
        in frames: [FramePoseData],
        faceProfileData: Data?
    ) async -> String {

        let probeFrames = Array(frames.prefix(10))
        var votes: [String] = []

        let storedPrint: VNFeaturePrintObservation? = faceProfileData.flatMap { data in
            try? NSKeyedUnarchiver.unarchivedObject(
                ofClass: VNFeaturePrintObservation.self,
                from: data
            )
        }

        let faceRequest = VNDetectFaceRectanglesRequest()

        for frame in probeFrames {
            let handler = VNImageRequestHandler(cgImage: frame.cgImage, options: [:])
            try? handler.perform([faceRequest])

            guard let faces = faceRequest.results, !faces.isEmpty else { continue }

            guard let storedPrint else {
                // No profile to compare — label as Unknown for every face found.
                votes.append("Unknown")
                continue
            }

            var foundSelf = false
            var otherCount = 0

            for face in faces {
                guard let crop = cropFace(from: frame.cgImage, boundingBox: face.boundingBox)
                else { continue }

                let featurePrintRequest = VNGenerateImageFeaturePrintRequest()
                let cropHandler = VNImageRequestHandler(cgImage: crop, options: [:])
                try? cropHandler.perform([featurePrintRequest])

                guard let detectedPrint = featurePrintRequest.results?.first else { continue }

                var dist: Float = 0
                try? storedPrint.computeDistance(&dist, to: detectedPrint)

                if dist < 0.75 {
                    foundSelf = true
                } else {
                    otherCount += 1
                }
            }

            if foundSelf {
                votes.append("You")
            } else if otherCount > 0 {
                votes.append("Person 2")
            } else {
                votes.append("Unknown")
            }
        }

        guard !votes.isEmpty else { return "Unknown" }

        // Majority vote.
        let counts = Dictionary(grouping: votes, by: { $0 }).mapValues(\.count)
        return counts.max(by: { $0.value < $1.value })?.key ?? "Unknown"
    }

    /// Crops a face region from a CGImage using a Vision bounding box.
    /// Vision bounding boxes use a normalized coordinate system with the origin
    /// at the bottom-left; we convert to top-left for CGImage operations.
    private func cropFace(from image: CGImage, boundingBox: CGRect) -> CGImage? {
        let w = CGFloat(image.width)
        let h = CGFloat(image.height)
        // Flip Y: Vision origin is bottom-left, CGImage is top-left.
        let rect = CGRect(
            x: boundingBox.minX * w,
            y: (1 - boundingBox.maxY) * h,
            width: boundingBox.width * w,
            height: boundingBox.height * h
        )
        return image.cropping(to: rect)
    }

    // MARK: - Sport classification

    /// Scores each `VideoSport` using four observable motion features and returns
    /// the highest scorer together with a normalized confidence value.
    ///
    /// Feature descriptions:
    /// - **armsAboveRatio**: Fraction of frames where at least one wrist is above
    ///   the same-side shoulder in Vision Y axis (0 = floor, 1 = top).
    ///   High ratio → climbing or overhead lifting.
    /// - **avgWristVelocity**: Mean frame-to-frame right-wrist displacement.
    ///   High velocity → striking.
    /// - **lowHipRatio**: Fraction of frames where root (pelvis) Y < 0.35.
    ///   High ratio → grappling or powerlifting bottom position.
    /// - **narrowRatio**: Fraction of frames where ankle spread < 0.2.
    ///   High ratio → climbing.
    /// - **avgSymmetry**: Fraction of frames where left/right wrists are within
    ///   10% of height — bilateral lifts (barbell pressing, squats).
    private func classifySport(
        from poses: [FramePoseData],
        duration: Double
    ) -> ClassificationResult {
        guard !poses.isEmpty else {
            return ClassificationResult(sport: .unknown, confidence: 0)
        }

        let totalFrames = Double(poses.count)

        // Helper: retrieve a joint's CGPoint-equivalent from FramePoseData.
        func joint(_ frame: FramePoseData, _ name: VNHumanBodyPoseObservation.JointName)
            -> CGPoint? {
            guard let coords = frame.joints[name.rawValue.rawValue],
                  coords.count >= 2 else { return nil }
            return CGPoint(x: coords[0], y: coords[1])
        }

        // Feature: arms above shoulder.
        let armsAboveCount = poses.filter { frame in
            let leftAbove = (joint(frame, .leftWrist)?.y ?? 0)
                > (joint(frame, .leftShoulder)?.y ?? 1)
            let rightAbove = (joint(frame, .rightWrist)?.y ?? 0)
                > (joint(frame, .rightShoulder)?.y ?? 1)
            return leftAbove || rightAbove
        }.count
        let armsAboveRatio = Double(armsAboveCount) / totalFrames

        // Feature: wrist velocity.
        let wristVelocities = computeWristVelocities(poses: poses)
        let avgWristVelocity = wristVelocities.isEmpty
            ? 0
            : wristVelocities.reduce(0, +) / Double(wristVelocities.count)
        let maxWristVelocity = wristVelocities.max() ?? 0

        // Feature: low hip.
        let lowHipCount = poses.filter {
            (joint($0, .root)?.y ?? 0.5) < 0.35
        }.count
        let lowHipRatio = Double(lowHipCount) / totalFrames

        // Feature: narrow stance.
        let narrowStanceCount = poses.filter { frame in
            guard let la = joint(frame, .leftAnkle),
                  let ra = joint(frame, .rightAnkle) else { return false }
            return abs(la.x - ra.x) < 0.2
        }.count
        let narrowRatio = Double(narrowStanceCount) / totalFrames

        // Feature: bilateral wrist symmetry.
        let symmetryScores: [Double] = poses.compactMap { frame in
            guard let lw = joint(frame, .leftWrist),
                  let rw = joint(frame, .rightWrist) else { return nil }
            return abs(lw.y - rw.y) < 0.1 ? 1.0 : 0.0
        }
        let avgSymmetry = symmetryScores.isEmpty
            ? 0
            : symmetryScores.reduce(0, +) / Double(symmetryScores.count)

        // Score each sport.
        var scores: [VideoSport: Double] = [
            .wallBeta:    armsAboveRatio   * 0.6 + narrowRatio * 0.4,
            .striking:    min(1.0, avgWristVelocity * 3) * 0.5
                              + (maxWristVelocity > 0.05 ? 0.5 : 0),
            .grappling:   lowHipRatio      * 0.7 + (1 - armsAboveRatio) * 0.3,
            .ironTracker: avgSymmetry      * 0.5 + lowHipRatio * 0.3
                              + (armsAboveRatio > 0.3 ? 0.2 : 0),
            .gym:         avgSymmetry      * 0.4 + (1 - armsAboveRatio) * 0.3
                              + lowHipRatio * 0.3,
            .track:       (1 - lowHipRatio) * 0.5 + avgWristVelocity * 0.5,
        ]

        scores = scores.mapValues { max(0, $0) }

        let sorted = scores.sorted { $0.value > $1.value }
        guard let top = sorted.first, top.value > 0.1 else {
            return ClassificationResult(sport: .unknown, confidence: 0)
        }

        let total = scores.values.reduce(0, +)
        let rawConfidence = total > 0 ? top.value / total : 0
        let confidence = min(rawConfidence * 1.5, 0.95)

        return ClassificationResult(sport: top.key, confidence: confidence)
    }

    // MARK: - Metric dispatch

    /// Routes to the appropriate sport-specific metric extractor and merges in
    /// the base metrics that are always computed.
    private func computeMetrics(
        for sport: VideoSport,
        poses: [FramePoseData],
        duration: Double
    ) -> [String: Double] {
        let sportMetrics: [String: Double]
        switch sport {
        case .striking:    sportMetrics = computeStrikingMetrics(poses: poses)
        case .grappling:   sportMetrics = computeGrapplingMetrics(poses: poses)
        case .ironTracker: sportMetrics = computeIronTrackerMetrics(poses: poses)
        case .wallBeta:    sportMetrics = computeWallBetaMetrics(poses: poses)
        case .gym:         sportMetrics = computeGymMetrics(poses: poses)
        case .track:       sportMetrics = computeTrackMetrics(poses: poses)
        case .unknown:     sportMetrics = [:]
        }

        // Base metrics always included.
        var base: [String: Double] = sportMetrics
        let detectedCount = poses.filter { !$0.joints.isEmpty }.count
        base["pose_detection_ratio"] = Double(detectedCount) / Double(max(poses.count, 1))
        return base
    }

    // MARK: - Sport-specific metric extractors

    /// Striking Clinic metrics.
    ///
    /// Returns:
    /// - `strikeVelocityMPH`: max wrist velocity in mph
    /// - `hipShoulderSeparationDeg`: max hip-shoulder angular separation
    ///   during high-velocity frames
    /// - `stanceRecoveryFrames`: average frames to return to neutral stance
    ///   after a peak-velocity event
    /// - `kineticChainScore`: 0-100, percentage of high-velocity frames where
    ///   hip velocity precedes wrist velocity by 2–5 frames
    private func computeStrikingMetrics(poses: [FramePoseData]) -> [String: Double] {
        var metrics: [String: Double] = [:]

        let wristVels = computeWristVelocities(poses: poses)
        let hipVels   = computeJointVelocities(poses: poses, joint: .leftHip)
        let maxWristVel = wristVels.max() ?? 0

        // Strike velocity: pixel/frame velocity × 2.5 scale factor → mph.
        metrics["strikeVelocityMPH"] = maxWristVel * 2.5

        // Identify high-velocity frames (top 20% of velocity distribution).
        let threshold = maxWristVel * 0.8
        let highVelIndices = wristVels.indices.filter { wristVels[$0] > threshold }

        // Hip-shoulder separation during high-velocity frames.
        var separations: [Double] = []
        for i in highVelIndices {
            let frameIndex = i + 1  // wristVels[i] corresponds to transition i→i+1
            guard frameIndex < poses.count else { continue }
            let frame = poses[frameIndex]
            guard let lh = jointPoint(frame, .leftHip),
                  let rh = jointPoint(frame, .rightHip),
                  let ls = jointPoint(frame, .leftShoulder),
                  let rs = jointPoint(frame, .rightShoulder) else { continue }
            let sep = BiomechanicsCalculator.calculateHipShoulderSeparation(
                leftHip: lh, rightHip: rh,
                leftShoulder: ls, rightShoulder: rs
            )
            separations.append(abs(sep))
        }
        metrics["hipShoulderSeparationDeg"] = separations.max() ?? 0

        // Stance recovery: frames from peak velocity to return to neutral stance width.
        var recoveryFrameCounts: [Double] = []
        for idx in highVelIndices {
            let peakFrame = min(idx + 1, poses.count - 1)
            guard let baseLA = jointPoint(poses[0], .leftAnkle),
                  let baseRA = jointPoint(poses[0], .rightAnkle) else { break }
            let neutralWidth = abs(baseLA.x - baseRA.x)
            for f in peakFrame..<poses.count {
                guard let la = jointPoint(poses[f], .leftAnkle),
                      let ra = jointPoint(poses[f], .rightAnkle) else { continue }
                if abs(abs(la.x - ra.x) - neutralWidth) < 0.05 {
                    recoveryFrameCounts.append(Double(f - peakFrame))
                    break
                }
            }
        }
        if !recoveryFrameCounts.isEmpty {
            metrics["stanceRecoveryFrames"] =
                recoveryFrameCounts.reduce(0, +) / Double(recoveryFrameCounts.count)
        } else {
            metrics["stanceRecoveryFrames"] = 0
        }

        // Kinetic chain score: fraction of high-velocity wrist frames where hip
        // velocity peak precedes wrist velocity peak by 2–5 frames.
        guard !highVelIndices.isEmpty else {
            metrics["kineticChainScore"] = 0
            return metrics
        }
        var chainCount = 0
        for wristPeakIdx in highVelIndices {
            // Look for a hip velocity peak in the 2–5 frames before this frame.
            let searchStart = max(0, wristPeakIdx - 5)
            let searchEnd   = max(0, wristPeakIdx - 2)
            guard searchStart <= searchEnd, searchEnd < hipVels.count else { continue }
            let precedingHipVels = hipVels[searchStart...searchEnd]
            let hipPeakInWindow = precedingHipVels.max() ?? 0
            let hipOverallMax = hipVels.max() ?? 0
            if hipOverallMax > 0, hipPeakInWindow > hipOverallMax * 0.6 {
                chainCount += 1
            }
        }
        metrics["kineticChainScore"] =
            100.0 * Double(chainCount) / Double(highVelIndices.count)

        return metrics
    }

    /// Grappling Lab metrics.
    ///
    /// Returns:
    /// - `kuzushiIndex`: mean distance of inferred opponent hip from frame centre
    /// - `comStabilityScore`: 100 × (1 - normalised variance of root Y)
    /// - `hipElevationAngle`: max angle between hip-knee line and horizontal
    /// - `bilateralSymmetry`: wrist height symmetry score 0-100
    private func computeGrapplingMetrics(poses: [FramePoseData]) -> [String: Double] {
        var metrics: [String: Double] = [:]

        // Kuzushi: treat the second detected person (approximated via head/nose
        // position being in the opposing half of the frame) as the "opponent".
        // For single-person video, this approximates postural displacement.
        let rootYValues = poses.compactMap { jointPoint($0, .root)?.y }
        let rootXValues = poses.compactMap { jointPoint($0, .root)?.x }
        let kuzushiDists = rootXValues.map { abs($0 - 0.5) }
        metrics["kuzushiIndex"] = kuzushiDists.isEmpty
            ? 0
            : kuzushiDists.reduce(0, +) / Double(kuzushiDists.count)

        // CoM stability: variance of root Y normalised to [0,1].
        if !rootYValues.isEmpty {
            let mean = rootYValues.reduce(0, +) / Double(rootYValues.count)
            let variance = rootYValues.map { ($0 - mean) * ($0 - mean) }
                .reduce(0, +) / Double(rootYValues.count)
            // Normalise by 0.1 (expected variance ceiling for stable base).
            metrics["comStabilityScore"] = max(0, 100 * (1 - variance / 0.1))
        } else {
            metrics["comStabilityScore"] = 0
        }

        // Hip elevation angle: angle between hip-knee line and horizontal.
        var hipAngles: [Double] = []
        for frame in poses {
            guard let lh = jointPoint(frame, .leftHip),
                  let lk = jointPoint(frame, .leftKnee) else { continue }
            let angle = atan2(abs(lh.y - lk.y), abs(lh.x - lk.x)) * 180 / .pi
            hipAngles.append(angle)
        }
        metrics["hipElevationAngle"] = hipAngles.max() ?? 0

        // Bilateral symmetry of wrist height.
        let symmetryValues: [Double] = poses.compactMap { frame in
            guard let lw = jointPoint(frame, .leftWrist),
                  let rw = jointPoint(frame, .rightWrist) else { return nil }
            return 100 * max(0, 1.0 - abs(lw.y - rw.y) / 0.5)
        }
        metrics["bilateralSymmetry"] = symmetryValues.isEmpty
            ? 0
            : symmetryValues.reduce(0, +) / Double(symmetryValues.count)

        return metrics
    }

    /// Iron Tracker metrics.
    ///
    /// Returns:
    /// - `barVelocityMS`: max wrist velocity in m/s
    /// - `barPathDeviationCM`: mean horizontal deviation of wrist midpoint
    ///   from the ideal vertical bar path
    /// - `asymmetryPercent`: left/right wrist velocity asymmetry average
    /// - `rangeOfMotionDeg`: wrist vertical ROM as degrees equivalent
    private func computeIronTrackerMetrics(poses: [FramePoseData]) -> [String: Double] {
        var metrics: [String: Double] = [:]

        // Bar velocity: pixel velocity × 0.003 → m/s.
        let leftVels  = computeJointVelocities(poses: poses, joint: .leftWrist)
        let rightVels = computeJointVelocities(poses: poses, joint: .rightWrist)
        let maxLeftVel  = leftVels.max() ?? 0
        let maxRightVel = rightVels.max() ?? 0
        metrics["barVelocityMS"] = max(maxLeftVel, maxRightVel) * 0.003

        // Bar path deviation: mean |wristMidX - idealX| × 0.3 → cm.
        let midXValues: [Double] = poses.compactMap { frame in
            guard let lw = jointPoint(frame, .leftWrist),
                  let rw = jointPoint(frame, .rightWrist) else { return nil }
            return (Double(lw.x) + Double(rw.x)) / 2.0
        }
        if !midXValues.isEmpty {
            let idealX = midXValues.reduce(0, +) / Double(midXValues.count)
            let deviations = midXValues.map { abs($0 - idealX) }
            let meanDeviation = deviations.reduce(0, +) / Double(deviations.count)
            metrics["barPathDeviationCM"] = meanDeviation * 100 * 0.3
        } else {
            metrics["barPathDeviationCM"] = 0
        }

        // Asymmetry: average |leftVel - rightVel| / max(leftVel, rightVel) × 100
        // computed over high-velocity frames only.
        let velPairs = zip(leftVels, rightVels)
        let maxOverall = max(maxLeftVel, maxRightVel)
        let threshold = maxOverall * 0.5
        var asymmetries: [Double] = []
        for (lv, rv) in velPairs where max(lv, rv) > threshold {
            let denom = max(lv, rv)
            guard denom > 0 else { continue }
            asymmetries.append(abs(lv - rv) / denom * 100)
        }
        metrics["asymmetryPercent"] = asymmetries.isEmpty
            ? 0
            : asymmetries.reduce(0, +) / Double(asymmetries.count)

        // Range of motion: (maxWristY - minWristY) / frameHeight × 90 degrees.
        let avgWristYValues: [Double] = poses.compactMap { frame in
            guard let lw = jointPoint(frame, .leftWrist),
                  let rw = jointPoint(frame, .rightWrist) else { return nil }
            return (Double(lw.y) + Double(rw.y)) / 2.0
        }
        if !avgWristYValues.isEmpty {
            let range = (avgWristYValues.max() ?? 0) - (avgWristYValues.min() ?? 0)
            metrics["rangeOfMotionDeg"] = range * 90
        } else {
            metrics["rangeOfMotionDeg"] = 0
        }

        return metrics
    }

    /// Wall Beta metrics.
    ///
    /// Returns:
    /// - `hipProximityScore`: how close hips are to the lateral frame edges
    /// - `hipSagEvents`: count of frames where root Y drops > 0.05
    /// - `staticHoldAvgSeconds`: mean duration of static hold periods
    /// - `comVariance`: variance of root joint position
    private func computeWallBetaMetrics(poses: [FramePoseData]) -> [String: Double] {
        var metrics: [String: Double] = [:]
        guard !poses.isEmpty else { return metrics }

        // Hip proximity: how close hips are to the nearer lateral edge.
        let proximityValues: [Double] = poses.compactMap { frame in
            guard let lh = jointPoint(frame, .leftHip) else { return nil }
            return 100 * min(Double(lh.x), 1 - Double(lh.x))
        }
        metrics["hipProximityScore"] = proximityValues.isEmpty
            ? 0
            : proximityValues.reduce(0, +) / Double(proximityValues.count)

        // Hip sag events: frames where root Y drops > 0.05 from the rolling mean.
        let rootYValues = poses.compactMap { jointPoint($0, .root)?.y }
        var sagEvents = 0
        for i in 1..<rootYValues.count {
            // In Vision coordinates Y=0 is the bottom, so a drop in climbing means
            // a decrease in Y (sinking toward the ground).
            if rootYValues[i - 1] - rootYValues[i] > 0.05 {
                sagEvents += 1
            }
        }
        metrics["hipSagEvents"] = Double(sagEvents)

        // Static hold duration: consecutive frames where all joints move < 0.01.
        let fps = Double(poses.count) / max(
            poses.last.map { $0.timestampSeconds } ?? 1, 1
        )
        var staticHoldDurations: [Double] = []
        var staticRunLength = 0
        for i in 1..<poses.count {
            if maxJointMovement(from: poses[i - 1], to: poses[i]) < 0.01 {
                staticRunLength += 1
            } else {
                if staticRunLength >= 3 {
                    staticHoldDurations.append(Double(staticRunLength) / fps)
                }
                staticRunLength = 0
            }
        }
        if staticRunLength >= 3 {
            staticHoldDurations.append(Double(staticRunLength) / fps)
        }
        metrics["staticHoldAvgSeconds"] = staticHoldDurations.isEmpty
            ? 0
            : staticHoldDurations.reduce(0, +) / Double(staticHoldDurations.count)

        // CoM variance of root position.
        let rootPositions: [Double] = poses.compactMap { frame in
            guard let root = jointPoint(frame, .root) else { return nil }
            return sqrt(Double(root.x) * Double(root.x) + Double(root.y) * Double(root.y))
        }
        if !rootPositions.isEmpty {
            let mean = rootPositions.reduce(0, +) / Double(rootPositions.count)
            let variance = rootPositions.map { ($0 - mean) * ($0 - mean) }
                .reduce(0, +) / Double(rootPositions.count)
            metrics["comVariance"] = variance
        } else {
            metrics["comVariance"] = 0
        }

        return metrics
    }

    /// Gym Tracker metrics.
    ///
    /// Returns:
    /// - `repCount`: oscillation cycles in wrist Y
    /// - `rangeOfMotion`: wrist vertical ROM as percentage of frame height × 100
    /// - `avgRepDurationSeconds`: total duration / repCount
    /// - `tempoScore`: timing consistency score 0-100
    private func computeGymMetrics(poses: [FramePoseData]) -> [String: Double] {
        var metrics: [String: Double] = [:]
        guard !poses.isEmpty else { return metrics }

        let avgWristYValues: [Double] = poses.compactMap { frame in
            guard let lw = jointPoint(frame, .leftWrist),
                  let rw = jointPoint(frame, .rightWrist) else { return nil }
            return (Double(lw.y) + Double(rw.y)) / 2.0
        }

        guard !avgWristYValues.isEmpty else { return metrics }

        let mean = avgWristYValues.reduce(0, +) / Double(avgWristYValues.count)
        let range = (avgWristYValues.max() ?? 0) - (avgWristYValues.min() ?? 0)
        metrics["rangeOfMotion"] = range * 100

        // Rep count: count peaks above mean.
        var repCount = 0
        var repPeakIndices: [Int] = []
        for i in 1..<(avgWristYValues.count - 1) {
            let prev = avgWristYValues[i - 1]
            let curr = avgWristYValues[i]
            let next = avgWristYValues[i + 1]
            if curr > mean, curr > prev, curr > next {
                repCount += 1
                repPeakIndices.append(i)
            }
        }
        metrics["repCount"] = Double(repCount)

        // Average rep duration.
        let fps = Double(poses.count) / max(
            poses.last.map { $0.timestampSeconds } ?? 1, 1
        )
        let totalDuration = poses.last?.timestampSeconds ?? 0
        metrics["avgRepDurationSeconds"] = repCount > 0
            ? totalDuration / Double(repCount)
            : 0

        // Tempo score: consistency of inter-peak intervals.
        if repPeakIndices.count > 1 {
            let intervals: [Double] = zip(repPeakIndices.dropFirst(), repPeakIndices)
                .map { Double($0 - $1) / fps }
            let meanInterval = intervals.reduce(0, +) / Double(intervals.count)
            if meanInterval > 0 {
                let stdDev = sqrt(
                    intervals.map { ($0 - meanInterval) * ($0 - meanInterval) }
                        .reduce(0, +) / Double(intervals.count)
                )
                let cv = stdDev / meanInterval
                metrics["tempoScore"] = max(0, min(100, 100 * (1 - cv)))
            } else {
                metrics["tempoScore"] = 0
            }
        } else {
            metrics["tempoScore"] = 0
        }

        return metrics
    }

    /// Track metrics.
    ///
    /// Returns:
    /// - `cadenceSPM`: ankle oscillation cycles per minute
    /// - `strideSymmetry`: left/right ankle velocity symmetry 0-100
    /// - `avgWristSwing`: mean wrist velocity (arm swing indicator)
    /// - `postureScore`: upright posture quality 0-100
    private func computeTrackMetrics(poses: [FramePoseData]) -> [String: Double] {
        var metrics: [String: Double] = [:]
        guard !poses.isEmpty else { return metrics }

        let fps = Double(poses.count) / max(
            poses.last.map { $0.timestampSeconds } ?? 1, 1
        )

        // Cadence: count ankle Y oscillation peaks per second × 60.
        let leftAnkleY: [Double] = poses.compactMap {
            jointPoint($0, .leftAnkle).map { Double($0.y) }
        }
        var stridePeaks = 0
        if !leftAnkleY.isEmpty {
            let ankMean = leftAnkleY.reduce(0, +) / Double(leftAnkleY.count)
            for i in 1..<(leftAnkleY.count - 1) {
                if leftAnkleY[i] > ankMean,
                   leftAnkleY[i] > leftAnkleY[i - 1],
                   leftAnkleY[i] > leftAnkleY[i + 1] {
                    stridePeaks += 1
                }
            }
        }
        let durationSeconds = poses.last?.timestampSeconds ?? 0
        let cadenceSPS = durationSeconds > 0
            ? Double(stridePeaks) / durationSeconds
            : 0
        metrics["cadenceSPM"] = cadenceSPS * 60

        // Stride symmetry.
        let leftAnkleVels  = computeJointVelocities(poses: poses, joint: .leftAnkle)
        let rightAnkleVels = computeJointVelocities(poses: poses, joint: .rightAnkle)
        let maxLeft  = leftAnkleVels.max() ?? 0
        let maxRight = rightAnkleVels.max() ?? 0
        let denom = max(maxLeft, maxRight)
        metrics["strideSymmetry"] = denom > 0
            ? max(0, 100 * (1 - abs(maxLeft - maxRight) / denom))
            : 0

        // Arm swing: mean wrist velocity.
        let wristVels = computeWristVelocities(poses: poses)
        metrics["avgWristSwing"] = wristVels.isEmpty
            ? 0
            : wristVels.reduce(0, +) / Double(wristVels.count)

        // Posture score: neck-root vertical distance normalised to 0-100.
        let postureValues: [Double] = poses.compactMap { frame in
            guard let neck = jointPoint(frame, .neck),
                  let root = jointPoint(frame, .root) else { return nil }
            // Clamp to 0-100 using 0.3 as the expected upright separation.
            return min(100, max(0, 100 * (Double(neck.y) - Double(root.y)) / 0.3))
        }
        metrics["postureScore"] = postureValues.isEmpty
            ? 0
            : postureValues.reduce(0, +) / Double(postureValues.count)

        return metrics
    }

    // MARK: - Velocity helpers

    /// Euclidean frame-to-frame displacement of the right wrist.
    private func computeWristVelocities(poses: [FramePoseData]) -> [Double] {
        var velocities: [Double] = []
        velocities.reserveCapacity(max(0, poses.count - 1))
        for i in 1..<poses.count {
            guard let prev = jointPoint(poses[i - 1], .rightWrist),
                  let curr = jointPoint(poses[i], .rightWrist) else { continue }
            let dx = Double(curr.x - prev.x)
            let dy = Double(curr.y - prev.y)
            velocities.append(sqrt(dx * dx + dy * dy))
        }
        return velocities
    }

    /// Euclidean frame-to-frame displacement of a given joint.
    private func computeJointVelocities(
        poses: [FramePoseData],
        joint name: VNHumanBodyPoseObservation.JointName
    ) -> [Double] {
        var velocities: [Double] = []
        velocities.reserveCapacity(max(0, poses.count - 1))
        for i in 1..<poses.count {
            guard let prev = jointPoint(poses[i - 1], name),
                  let curr = jointPoint(poses[i], name) else { continue }
            let dx = Double(curr.x - prev.x)
            let dy = Double(curr.y - prev.y)
            velocities.append(sqrt(dx * dx + dy * dy))
        }
        return velocities
    }

    // MARK: - Geometry helpers

    /// Returns the maximum single-joint movement magnitude between two frames.
    private func maxJointMovement(
        from a: FramePoseData,
        to b: FramePoseData
    ) -> Double {
        var maxMove = 0.0
        for (key, coordsA) in a.joints {
            guard let coordsB = b.joints[key],
                  coordsA.count >= 2, coordsB.count >= 2 else { continue }
            let dx = coordsA[0] - coordsB[0]
            let dy = coordsA[1] - coordsB[1]
            let dist = sqrt(dx * dx + dy * dy)
            if dist > maxMove { maxMove = dist }
        }
        return maxMove
    }

    /// Convenience: extracts a joint position as `CGPoint` from a `FramePoseData`.
    private func jointPoint(
        _ frame: FramePoseData,
        _ name: VNHumanBodyPoseObservation.JointName
    ) -> CGPoint? {
        guard let coords = frame.joints[name.rawValue.rawValue],
              coords.count >= 2 else { return nil }
        return CGPoint(x: coords[0], y: coords[1])
    }
}
