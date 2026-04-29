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

    /// How close the climber's hips are to the wall (left side of the frame).
    /// Range 0..100: 100 = hips touching the wall; 0 = hips at the right edge.
    var hipProximityScore: Double = 50

    // MARK: Center of Mass

    /// Centroid of the reliable hip joints in Vision normalized coordinates.
    var centerOfMass: CGPoint = .zero

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
/// **Wall convention:**
/// In portrait orientation the wall is on the LEFT side of the camera frame.
/// Vision's normalized X axis runs 0 (left) → 1 (right), so a low hip X value
/// means the hips are close to the wall — good technique.
///
/// **Hip proximity score:**
/// ```
/// proximityScore = clamp((0.5 - avgHipX) * 200 + 50, 0, 100)
/// ```
/// At avgHipX = 0.0 (wall):  score ≈ 150 → clamped to 100
/// At avgHipX = 0.25 (mid-left): score ≈ 100
/// At avgHipX = 0.5 (center): score ≈  50
/// At avgHipX = 1.0 (far right): score ≈ -50 → clamped to 0
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

        // ── 1. Hip Proximity and Center of Mass ───────────────────────────────────────
        let hipJointNames: [VNHumanBodyPoseObservation.JointName] = [.leftHip, .rightHip, .root]
        let reliableHipPoints = hipJointNames.compactMap { name -> CGPoint? in
            guard let joint = pose[name], joint.isReliable else { return nil }
            return joint.position
        }

        if !reliableHipPoints.isEmpty {
            metrics.centerOfMass = BiomechanicsCalculator.calculateCenterOfMass(joints: reliableHipPoints)

            // Proximity score: lower X → closer to left wall → higher score.
            // Formula maps 0.0 (wall) → ~150 clamped to 100, 0.5 (center) → 50.
            let avgHipX = reliableHipPoints.reduce(0.0) { $0 + Double($1.x) }
                / Double(reliableHipPoints.count)
            let rawScore = (0.5 - avgHipX) * 200.0 + 50.0
            metrics.hipProximityScore = max(0.0, min(100.0, rawScore))
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
