import Vision
import Foundation

// MARK: - StrikingMetrics

/// All biomechanics data surfaces for a single striking session frame.
/// Immutable once produced per frame — the ViewModel holds a `var` copy and
/// replaces it in full on each `analyze` call.
struct StrikingMetrics: Sendable {

    // MARK: Velocity

    /// Current-frame wrist speed in mph — whichever hand is moving faster.
    var strikeVelocityMPH: Double = 0
    /// Highest wrist speed recorded this session.
    var peakVelocityMPH: Double = 0

    // MARK: Strike Detection

    /// True during the frames where wrist speed exceeds the strike threshold.
    var isStrikeDetected: Bool = false
    /// Total number of discrete strikes detected this session.
    var strikeCount: Int = 0

    // MARK: Kinetic Chain

    /// Hip-to-shoulder separation angle in degrees.
    /// Positive values indicate the hips are rotated ahead of the shoulders — the
    /// "coil" that stores elastic energy before it's released into the strike.
    var hipShoulderSeparation: Double = 0

    /// 0..100 composite score for kinetic chain quality.
    /// Higher scores mean the hips are driving more of the movement than the shoulders,
    /// which indicates correct power transfer from the floor up.
    var kinematicScore: Double = 0

    // MARK: Stance Recovery

    /// Seconds elapsed since the last completed strike, used to track reset speed.
    var recoveryTimeSeconds: Double = 0

    // MARK: - Display Helpers

    var velocityDisplay: String { String(format: "%.1f", strikeVelocityMPH) }
    var peakDisplay: String { String(format: "%.1f", peakVelocityMPH) }
    var separationDisplay: String { String(format: "%.0f°", abs(hipShoulderSeparation)) }
    var scoreDisplay: String { String(format: "%.0f", kinematicScore) }
}

// MARK: - StrikingAnalytics

/// Pure, stateless analytics namespace for the Striking Clinic module.
///
/// Every method is static. The ViewModel calls `analyze(pose:previous:frameRate:currentMetrics:)`
/// once per frame and receives a fully-updated `StrikingMetrics` value. No mutation occurs here.
enum StrikingAnalytics {

    // MARK: - Active Joints

    /// The joints this module highlights in the pose overlay.
    static let activeJoints: Set<VNHumanBodyPoseObservation.JointName> = [
        .leftWrist,    .rightWrist,
        .leftElbow,    .rightElbow,
        .leftShoulder, .rightShoulder,
        .leftHip,      .rightHip,
        .leftAnkle,    .rightAnkle,
    ]

    // MARK: - Threshold

    /// Minimum wrist speed in mph to classify a movement as a strike.
    /// Below this threshold the hand is considered to be in guard or returning.
    static let strikeVelocityThresholdMPH: Double = 5.0

    // MARK: - Main Entry Point

    /// Analyzes one frame of pose data and returns a fully-updated `StrikingMetrics`.
    ///
    /// - Parameters:
    ///   - pose: The body pose for the current frame.
    ///   - previous: The body pose from the immediately preceding frame, or `nil` on frame 1.
    ///   - frameRate: Camera capture rate in fps (typically 30).
    ///   - currentMetrics: The metrics struct from the previous frame — carried forward fields
    ///     such as `peakVelocityMPH` and `strikeCount` accumulate across the session.
    /// - Returns: A new `StrikingMetrics` value reflecting this frame.
    static func analyze(
        pose: JointPose,
        previous: JointPose?,
        frameRate: Double,
        currentMetrics: StrikingMetrics
    ) -> StrikingMetrics {
        var metrics = currentMetrics

        // 1. Velocity — requires a previous frame for displacement calculation.
        if let prev = previous {
            let leftV  = wristVelocity(pose: pose, previous: prev, side: .left,  frameRate: frameRate)
            let rightV = wristVelocity(pose: pose, previous: prev, side: .right, frameRate: frameRate)
            let maxV   = max(leftV, rightV)

            metrics.strikeVelocityMPH = maxV

            let wasStriking = metrics.isStrikeDetected
            metrics.isStrikeDetected = maxV > strikeVelocityThresholdMPH

            // Rising edge: new strike begins.
            if metrics.isStrikeDetected, !wasStriking {
                metrics.strikeCount += 1
                metrics.recoveryTimeSeconds = 0
            }

            // Falling edge: strike ended, start recovery timer.
            if !metrics.isStrikeDetected, wasStriking {
                metrics.recoveryTimeSeconds = 0
            }

            // Recovery counter increments every frame while not striking.
            if !metrics.isStrikeDetected {
                let secondsPerFrame = frameRate > 0 ? 1.0 / frameRate : 0
                metrics.recoveryTimeSeconds += secondsPerFrame
            }

            if maxV > metrics.peakVelocityMPH {
                metrics.peakVelocityMPH = maxV
            }
        }

        // 2. Hip-shoulder separation — uses BiomechanicsCalculator's dedicated method.
        metrics.hipShoulderSeparation = hipShoulderSeparation(pose: pose)

        // 3. Kinematic chain score — hips-drive-shoulders ratio.
        if let prev = previous {
            metrics.kinematicScore = kinematicChainScore(
                pose: pose,
                previous: prev,
                frameRate: frameRate
            )
        }

        return metrics
    }

    // MARK: - Velocity

    private enum Side { case left, right }

    private static func wristVelocity(
        pose: JointPose,
        previous: JointPose,
        side: Side,
        frameRate: Double
    ) -> Double {
        let jointName: VNHumanBodyPoseObservation.JointName = side == .left ? .leftWrist : .rightWrist

        guard
            let current = pose[jointName],     current.isReliable,
            let prev    = previous[jointName], prev.isReliable
        else { return 0 }

        return BiomechanicsCalculator.calculateVelocity(
            from: prev.position,
            to: current.position,
            frameRate: frameRate
        )
    }

    // MARK: - Hip-Shoulder Separation

    /// Delegates to the shared `calculateHipShoulderSeparation` method in BiomechanicsCalculator.
    /// Returns 0 when any of the four required joints are below confidence threshold.
    private static func hipShoulderSeparation(pose: JointPose) -> Double {
        guard
            let lHip  = pose[.leftHip],      lHip.isReliable,
            let rHip  = pose[.rightHip],     rHip.isReliable,
            let lSh   = pose[.leftShoulder], lSh.isReliable,
            let rSh   = pose[.rightShoulder], rSh.isReliable
        else { return 0 }

        return BiomechanicsCalculator.calculateHipShoulderSeparation(
            leftHip: lHip.position,
            rightHip: rHip.position,
            leftShoulder: lSh.position,
            rightShoulder: rSh.position
        )
    }

    // MARK: - Kinematic Chain Score

    /// Produces a 0–100 score representing how much the hips are driving the movement
    /// relative to the shoulders. A score of 100 means the hips are solely responsible
    /// for the movement this frame; 0 means only the shoulders moved.
    ///
    /// The score is neutral (50) when neither segment is moving or joint data is unreliable.
    private static func kinematicChainScore(
        pose: JointPose,
        previous: JointPose,
        frameRate: Double
    ) -> Double {
        guard
            let lHip  = pose[.leftHip],      lHip.isReliable,
            let rHip  = pose[.rightHip],     rHip.isReliable,
            let lSh   = pose[.leftShoulder], lSh.isReliable,
            let rSh   = pose[.rightShoulder], rSh.isReliable,
            let pLHip = previous[.leftHip],   pLHip.isReliable,
            let pRHip = previous[.rightHip],  pRHip.isReliable,
            let pLSh  = previous[.leftShoulder], pLSh.isReliable,
            let pRSh  = previous[.rightShoulder], pRSh.isReliable
        else { return 50 }

        let hipCenter = CGPoint(
            x: (lHip.position.x + rHip.position.x) / 2,
            y: (lHip.position.y + rHip.position.y) / 2
        )
        let prevHipCenter = CGPoint(
            x: (pLHip.position.x + pRHip.position.x) / 2,
            y: (pLHip.position.y + pRHip.position.y) / 2
        )
        let shoulderCenter = CGPoint(
            x: (lSh.position.x + rSh.position.x) / 2,
            y: (lSh.position.y + rSh.position.y) / 2
        )
        let prevShoulderCenter = CGPoint(
            x: (pLSh.position.x + pRSh.position.x) / 2,
            y: (pLSh.position.y + pRSh.position.y) / 2
        )

        let hipSpeed      = BiomechanicsCalculator.calculateVelocity(from: prevHipCenter,      to: hipCenter,      frameRate: frameRate)
        let shoulderSpeed = BiomechanicsCalculator.calculateVelocity(from: prevShoulderCenter, to: shoulderCenter, frameRate: frameRate)

        let total = hipSpeed + shoulderSpeed
        guard total > 0 else { return 50 }

        // Hip dominance of 0.67+ maps to 100; below 0.33 maps toward 0.
        let hipDominance = hipSpeed / total
        return min(100, hipDominance * 150)
    }
}
