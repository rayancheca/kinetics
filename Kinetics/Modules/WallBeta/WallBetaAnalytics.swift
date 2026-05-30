import Vision
import Foundation

// MARK: - MovementPhase

/// Describes the climber's current movement state derived from aggregate joint velocity.
enum MovementPhase: String, Sendable {
    case static_hold  = "Static Hold"
    case transitioning = "Moving"
    case dyno          = "DYNO!"
}

// MARK: - WallBetaMetrics

/// A snapshot of Wall Beta analytics for one camera frame.
///
/// All numeric properties use normalized coordinates or mph/seconds so they remain
/// independent of screen resolution. The `Display` computed properties produce
/// pre-formatted strings for direct use in SwiftUI views.
struct WallBetaMetrics: Sendable {

    // MARK: Hip Proximity

    /// How close the climber's hips are to the wall, relative to the estimated wall plane.
    /// Range 0..100: 100 = hips touching the wall; 0 = hips at maximum distance.
    var hipProximityScore: Double = 50

    // MARK: Center of Mass

    /// Centroid of the reliable hip joints in Vision normalized coordinates.
    var centerOfMass: CGPoint = .zero

    // MARK: Wall Plane Estimation

    /// The estimated X coordinate (Vision normalized) of the wall surface, derived from
    /// wrist positions over the session. Updated each frame via exponential smoothing.
    /// Defaults to 0.0 (left frame edge) until the first wrist observation.
    var estimatedWallPlaneX: Double = 0.0

    /// `true` once the wall plane estimate has been seeded from real wrist observations.
    /// Until this is true, the proximity score falls back to the legacy left-edge formula.
    var wallPlaneEstimated: Bool = false

    /// `true` when the wall is on the left side of the frame; `false` when it is on the right.
    /// Inferred once from the first reliable wrist X observation and held fixed for the session.
    var wallIsOnLeft: Bool = true

    // MARK: Technique Flags

    /// `true` when the hip center-of-mass drops below the running baseline, indicating
    /// the climber's hips are sagging away from the wall.
    var isHipSag: Bool = false

    /// `true` while aggregate joint velocity is below `WallBetaAnalytics.staticVelocityThresholdMPH`.
    var isStatic: Bool = true

    /// `true` for the frame(s) where total-body velocity exceeds the Dyno threshold and
    /// the hips are moving upward.
    var isDynoDetected: Bool = false

    // MARK: Time and Velocity

    /// Continuous time spent on the current static hold in seconds.
    var holdTimeSeconds: Double = 0

    /// Average velocity across all tracked joints, in mph.
    var averageVelocityMPH: Double = 0

    // MARK: Movement State

    var movementPhase: MovementPhase = .static_hold

    // MARK: - Formatted Display Strings

    var proximityDisplay: String { String(format: "%.0f%%", hipProximityScore) }
    var holdTimeDisplay:  String { String(format: "%.1fs", holdTimeSeconds) }
    var velocityDisplay:  String { String(format: "%.1f mph", averageVelocityMPH) }
}

// MARK: - WallBetaAnalytics

/// Pure, stateless analytics for the Wall Beta climbing module.
///
/// **Wall plane estimation (no ARKit required):**
/// Climbers' wrists are on the wall surface by definition — they must touch holds.
/// The minimum reliable wrist X observed over the session's early frames gives a
/// running estimate of where the wall plane sits in Vision's normalized coordinate
/// space. This estimate is stored in `WallBetaMetrics.estimatedWallPlaneX` and
/// updated each frame via exponential smoothing. The hip proximity score is then
/// computed relative to this estimate rather than hard-coded to X = 0 (left edge).
///
/// **Hip proximity score (wall-plane-relative):**
/// ```
/// hipDistanceFromWall = avgHipX - wallPlaneX          // 0 = touching wall
/// proximityScore = clamp(100 - (hipDistanceFromWall / maxExpectedDistance) * 100, 0, 100)
/// ```
/// `maxExpectedDistance` is set to 0.45 normalized units — approximately half the
/// frame width, representing hips fully extended away from the wall.
///
/// **Wall side inference:**
/// The side of the frame the wall is on is inferred once from early wrist observations:
/// if avg wrist X < 0.5 the wall is on the left; otherwise on the right. This is
/// stored in `WallBetaMetrics.wallIsOnLeft` and remains fixed for the session.
enum WallBetaAnalytics {

    // MARK: - Tracked Joint Set

    /// The joints used for velocity calculation and activity inference.
    /// Matches the spec: hips, root, ankles, wrists, knees.
    static let activeJoints: Set<VNHumanBodyPoseObservation.JointName> = [
        .leftHip,  .rightHip,  .root,
        .leftAnkle, .rightAnkle,
        .leftWrist, .rightWrist,
        .leftKnee,  .rightKnee
    ]

    // MARK: - Thresholds

    /// Average joint velocity below this value (mph) is considered a static hold.
    static let staticVelocityThresholdMPH = 0.5

    /// Average joint velocity above this value (mph) combined with upward hip motion
    /// constitutes a Dyno detection.
    static let dynoVelocityThresholdMPH = 8.0

    /// Normalized Y-unit drop from the running hip baseline that triggers a sag alert.
    /// Vision Y is 0 (bottom) → 1 (top), so a positive drop means the hips moved down.
    static let sagThreshold = 0.08

    /// Maximum expected normalized-unit distance from hips to wall plane.
    /// Used to map raw distance to a 0–100 score. 0.45 ≈ half the frame width.
    static let maxHipWallDistance = 0.45

    /// Exponential smoothing factor for wall plane X estimate updates.
    /// Lower = slower adaptation (more stable); higher = faster adaptation (more reactive).
    /// 0.05 at 30 fps gives roughly a 0.7-second time constant.
    static let wallPlaneAlpha = 0.05

    // MARK: - Primary Analysis Entry Point

    /// Analyzes one frame of pose data and returns an updated `WallBetaMetrics` snapshot.
    ///
    /// - Parameters:
    ///   - pose: The current-frame body pose from `PoseDetectionEngine`.
    ///   - previous: The immediately preceding frame's pose, used to compute inter-frame velocity.
    ///   - frameRate: Camera frame rate in fps (typically 30).
    ///   - currentMetrics: The metrics snapshot from the previous frame — fields not updated
    ///     this frame are carried forward unchanged.
    ///   - holdStartTime: The `Date` when the current static hold began, or `nil` if the
    ///     climber is currently moving.
    ///   - hipYBaseline: The hip Y position captured at session start, used as the sag reference.
    /// - Returns: A fully populated `WallBetaMetrics` snapshot for this frame.
    static func analyze(
        pose: JointPose,
        previous: JointPose?,
        frameRate: Double,
        currentMetrics: WallBetaMetrics,
        holdStartTime: Date?,
        hipYBaseline: Double?
    ) -> WallBetaMetrics {
        var metrics = currentMetrics

        // ── 0. Wall Plane Estimation ──────────────────────────────────────────────────
        // Wrists are on the wall by definition. Use their X positions to estimate where
        // the wall plane sits in the frame, then update via exponential smoothing.
        let wristJoints: [VNHumanBodyPoseObservation.JointName] = [.leftWrist, .rightWrist]
        let reliableWristXs = wristJoints.compactMap { name -> Double? in
            guard let joint = pose[name], joint.isReliable else { return nil }
            return Double(joint.position.x)
        }

        if !reliableWristXs.isEmpty {
            let avgWristX = reliableWristXs.reduce(0.0, +) / Double(reliableWristXs.count)

            if !metrics.wallPlaneEstimated {
                // First observation: seed the estimate and lock in which side the wall is on.
                metrics.estimatedWallPlaneX = avgWristX
                metrics.wallIsOnLeft = avgWristX < 0.5
                metrics.wallPlaneEstimated = true
            } else {
                // Subsequent frames: exponential moving average.
                // Only update toward the wall side to prevent hip positions pulling
                // the estimate away from the wall (hips are never at the wall plane).
                let candidate = avgWristX
                let currentEstimate = metrics.estimatedWallPlaneX
                let wallSideX = metrics.wallIsOnLeft
                    ? min(candidate, currentEstimate)   // wall is left: keep smallest X
                    : max(candidate, currentEstimate)   // wall is right: keep largest X

                // Blend: slow-adapt toward the extremal wrist position.
                metrics.estimatedWallPlaneX = currentEstimate
                    + wallPlaneAlpha * (wallSideX - currentEstimate)
            }
        }

        // ── 1. Hip Proximity and Center of Mass ───────────────────────────────────────
        let hipJointNames: [VNHumanBodyPoseObservation.JointName] = [.leftHip, .rightHip, .root]
        let reliableHipPoints = hipJointNames.compactMap { name -> CGPoint? in
            guard let joint = pose[name], joint.isReliable else { return nil }
            return joint.position
        }

        if !reliableHipPoints.isEmpty {
            metrics.centerOfMass = BiomechanicsCalculator.calculateCenterOfMass(joints: reliableHipPoints)

            let avgHipX = reliableHipPoints.reduce(0.0) { $0 + Double($1.x) }
                / Double(reliableHipPoints.count)

            // Compute distance of hips from the estimated wall plane.
            // When wallPlaneEstimated is false (no wrist data yet), fall back to
            // the legacy formula anchored to the frame edge, so the score is never stuck.
            let hipDistanceFromWall: Double
            if metrics.wallPlaneEstimated {
                hipDistanceFromWall = metrics.wallIsOnLeft
                    ? avgHipX - metrics.estimatedWallPlaneX     // wall on left: hip should be close to small X
                    : metrics.estimatedWallPlaneX - avgHipX     // wall on right: hip should be close to large X
            } else {
                // Fallback: assume wall is on the left (legacy behaviour).
                hipDistanceFromWall = avgHipX
            }

            // Map distance to 0–100 score. At 0 distance → 100; at maxHipWallDistance → 0.
            let distanceFraction = max(0.0, hipDistanceFromWall) / maxHipWallDistance
            metrics.hipProximityScore = max(0.0, min(100.0, (1.0 - distanceFraction) * 100.0))
        }

        // ── 2. Hip Sag Detection ──────────────────────────────────────────────────────
        // Vision Y: 0 = bottom of frame, 1 = top. A drop in Y means hips moved down.
        if let baseline = hipYBaseline,
           let root = pose[.root], root.isReliable {
            let sagAmount = baseline - Double(root.position.y)
            metrics.isHipSag = sagAmount > sagThreshold
        }

        // ── 3. Average Joint Velocity ─────────────────────────────────────────────────
        if let prev = previous {
            let velocities: [Double] = activeJoints.compactMap { jointName -> Double? in
                guard
                    let current  = pose[jointName],  current.isReliable,
                    let prevJoint = prev[jointName], prevJoint.isReliable
                else { return nil }
                return BiomechanicsCalculator.calculateVelocity(
                    from: prevJoint.position,
                    to: current.position,
                    frameRate: frameRate
                )
            }
            let avgVelocity = velocities.isEmpty
                ? 0.0
                : velocities.reduce(0.0, +) / Double(velocities.count)
            metrics.averageVelocityMPH = avgVelocity

            // ── 4. Static / Moving Classification ────────────────────────────────────
            metrics.isStatic = avgVelocity < staticVelocityThresholdMPH

            // ── 5. Dyno Detection ─────────────────────────────────────────────────────
            // Dyno = explosive upward jump: high aggregate velocity + hips moving upward.
            if let currentRoot = pose[.root], currentRoot.isReliable,
               let prevRoot    = prev[.root], prevRoot.isReliable {
                // Vision Y increases toward the top, so a rising Y means hips going up.
                let hipsMovingUp = currentRoot.position.y > prevRoot.position.y
                metrics.isDynoDetected = avgVelocity > dynoVelocityThresholdMPH && hipsMovingUp
            } else {
                metrics.isDynoDetected = false
            }
        } else {
            // First frame — no previous pose, cannot compute velocity.
            metrics.averageVelocityMPH = 0
            metrics.isStatic = true
            metrics.isDynoDetected = false
        }

        // ── 6. Movement Phase ─────────────────────────────────────────────────────────
        if metrics.isDynoDetected {
            metrics.movementPhase = .dyno
        } else if metrics.isStatic {
            metrics.movementPhase = .static_hold
        } else {
            metrics.movementPhase = .transitioning
        }

        // ── 7. Hold Time ──────────────────────────────────────────────────────────────
        // Hold time is driven by the ViewModel's holdStartTime; we only update here when
        // the climber is still static and a hold start is recorded.
        if let start = holdStartTime, metrics.isStatic {
            metrics.holdTimeSeconds = Date().timeIntervalSince(start)
        } else if !metrics.isStatic {
            // Moving — the ViewModel will reset holdStartTime; zero out display value.
            metrics.holdTimeSeconds = 0
        }

        return metrics
    }
}
