import Vision
import Foundation

// MARK: - GrapplingMetrics

/// A snapshot of all grappling-specific biomechanics for a single video frame.
///
/// Every property has a safe default so the UI can render immediately before
/// the Vision engine produces its first reliable observation.
struct GrapplingMetrics: Sendable {

    // MARK: Center of Mass

    /// Athlete's estimated center of mass in Vision normalized coordinates (0..1).
    /// Derived from leftHip + rightHip + root — the three primary load-bearing nodes.
    var centerOfMass: CGPoint = .zero

    // MARK: Base Stability

    /// `true` when the CoM projects inside the support-base polygon (ankles + knees).
    /// A stable base is the foundation of all effective grappling leverage.
    var isBaseStable: Bool = true

    /// `true` when the CoM has moved significantly outside the base polygon.
    /// Triggers the red "BASE COMPROMISED" banner in the overlay.
    var isPosturalAlert: Bool = false

    // MARK: Spine

    /// Angle of the neck→root spine vector from vertical, in degrees.
    /// 0° = perfectly upright. Increasing angle = forward/lateral lean.
    /// Kuzushi and throw detection both weight this value.
    var spineAngleDegrees: Double = 0

    // MARK: Position Classification

    /// Normalized y-position of the root joint (0..1, Vision space).
    /// Higher values (closer to 1) indicate the hips are lower in the frame —
    /// typically a guard or ground position.
    var hipElevation: Double = 0

    /// `true` when the root joint y-position exceeds 0.55, which reliably
    /// distinguishes standing from guard, sprawl, or ground positions.
    var isGroundPosition: Bool = false

    // MARK: Kuzushi Index

    /// Composite 0–100 score measuring throw-setup effectiveness.
    ///
    /// Blends spine displacement (70 % weight) with body-movement velocity (30 %).
    /// A score above ~60 typically indicates an opponent under structural pressure.
    var kuzushiIndex: Double = 0

    // MARK: - Formatted Display Strings

    /// Spine angle formatted with degree symbol, e.g. "23°".
    var spineAngleDisplay: String { String(format: "%.0f°", spineAngleDegrees) }

    /// Kuzushi index formatted as a whole number, e.g. "74".
    var kuzushiDisplay: String { String(format: "%.0f", kuzushiIndex) }

    /// Human-readable position classification.
    var positionDisplay: String { isGroundPosition ? "Ground" : "Standing" }

    /// Human-readable base-stability label.
    var baseStabilityDisplay: String { isBaseStable ? "Stable" : "Broken" }
}

// MARK: - GrapplingAnalytics

/// Pure, stateless analytics namespace for the Grappling Lab module.
///
/// Every method is a static pure function — no state, no side effects.
/// The ViewModel owns all mutable state and calls these functions once per frame.
enum GrapplingAnalytics {

    // MARK: - Active Joints

    /// The Vision joints this module cares about.
    /// Passed to `PoseOverlayView` so only grappling-relevant joints are highlighted.
    static let activeJoints: Set<VNHumanBodyPoseObservation.JointName> = [
        .root,
        .leftHip, .rightHip,
        .leftKnee, .rightKnee,
        .leftAnkle, .rightAnkle,
        .neck, .nose
    ]

    // MARK: - Primary Analysis Entry Point

    /// Computes a full `GrapplingMetrics` snapshot from a single `JointPose` frame.
    ///
    /// - Parameters:
    ///   - pose:      The current frame's body pose from `PoseDetectionEngine`.
    ///   - previous:  The immediately preceding frame's pose. Pass `nil` for the first frame.
    ///   - frameRate: Camera frame rate in fps, used to convert displacement to velocity.
    /// - Returns: A fully populated `GrapplingMetrics` value.
    static func analyze(
        pose: JointPose,
        previous: JointPose?,
        frameRate: Double
    ) -> GrapplingMetrics {
        var metrics = GrapplingMetrics()

        computeCenterOfMass(pose: pose, metrics: &metrics)
        computeBaseStability(pose: pose, metrics: &metrics)
        computeSpineAndPosition(pose: pose, metrics: &metrics)
        computeKuzushi(pose: pose, previous: previous, frameRate: frameRate, metrics: &metrics)

        return metrics
    }

    // MARK: - Private: Center of Mass

    /// Averages the leftHip, rightHip, and root positions to estimate CoM.
    private static func computeCenterOfMass(
        pose: JointPose,
        metrics: inout GrapplingMetrics
    ) {
        let comJointNames: [VNHumanBodyPoseObservation.JointName] = [.leftHip, .rightHip, .root]
        let reliablePoints = comJointNames.compactMap { name -> CGPoint? in
            guard let joint = pose[name], joint.isReliable else { return nil }
            return joint.position
        }
        guard !reliablePoints.isEmpty else { return }
        metrics.centerOfMass = BiomechanicsCalculator.calculateCenterOfMass(joints: reliablePoints)
    }

    // MARK: - Private: Base Stability

    /// Builds the support-base polygon from available ankle/knee contacts and checks
    /// whether the CoM projects inside it.
    private static func computeBaseStability(
        pose: JointPose,
        metrics: inout GrapplingMetrics
    ) {
        // Ordered clockwise: leftAnkle → rightAnkle → rightKnee → leftKnee.
        // This ordering produces a valid convex polygon for the ray-casting test.
        let baseJointNames: [VNHumanBodyPoseObservation.JointName] = [
            .leftAnkle, .rightAnkle, .rightKnee, .leftKnee
        ]
        let basePoints = baseJointNames.compactMap { name -> CGPoint? in
            guard let joint = pose[name], joint.isReliable else { return nil }
            return joint.position
        }

        // Need at least 3 vertices for a meaningful polygon test.
        guard basePoints.count >= 3 else { return }

        let comInsideBase = BiomechanicsCalculator.isPoint(
            metrics.centerOfMass,
            insidePolygon: basePoints
        )
        metrics.isBaseStable = comInsideBase
        metrics.isPosturalAlert = !comInsideBase
    }

    // MARK: - Private: Spine Angle and Position

    /// Computes the spine tilt angle from the neck→root vector versus vertical,
    /// and classifies the athlete's position as ground or standing.
    private static func computeSpineAndPosition(
        pose: JointPose,
        metrics: inout GrapplingMetrics
    ) {
        guard
            let neck = pose[.neck], neck.isReliable,
            let root = pose[.root], root.isReliable
        else { return }

        // Spine vector: root → neck (bottom to top of torso).
        let spineVector = CGPoint(
            x: neck.position.x - root.position.x,
            y: neck.position.y - root.position.y
        )

        // Vertical unit vector in Vision space (positive y = up).
        let vertical = CGPoint(x: 0.0, y: 1.0)

        let dot = Double(spineVector.x * vertical.x + spineVector.y * vertical.y)
        let magnitude = sqrt(
            Double(spineVector.x * spineVector.x + spineVector.y * spineVector.y)
        )

        if magnitude > 0 {
            let cosAngle = max(-1.0, min(1.0, dot / magnitude))
            metrics.spineAngleDegrees = acos(cosAngle) * (180.0 / .pi)
        }

        // Root y in Vision normalized space: high y = physically lower in the frame.
        // A threshold of 0.55 reliably separates standing (hips up) from ground work.
        metrics.hipElevation = Double(root.position.y)
        metrics.isGroundPosition = root.position.y > 0.55
    }

    // MARK: - Private: Kuzushi Index

    /// Blends spine displacement (structural breakdown) with root velocity (movement)
    /// to produce a 0–100 throw-setup score.
    private static func computeKuzushi(
        pose: JointPose,
        previous: JointPose?,
        frameRate: Double,
        metrics: inout GrapplingMetrics
    ) {
        // Structural factor: how far has the spine deviated from vertical?
        // 45° deviation maps to a factor of 1.0 (fully compromised).
        let spineDeviation = min(metrics.spineAngleDegrees / 45.0, 1.0)

        // Kinetic factor: how fast is the root (hips) moving?
        // 5 mph maps to a factor of 1.0 (rapid throw-entry movement).
        var movementFactor = 0.0
        if let previous,
           let currentRoot = pose[.root], currentRoot.isReliable,
           let previousRoot = previous[.root], previousRoot.isReliable {
            let velocityMPH = BiomechanicsCalculator.calculateVelocity(
                from: previousRoot.position,
                to: currentRoot.position,
                frameRate: frameRate
            )
            movementFactor = min(velocityMPH / 5.0, 1.0)
        }

        metrics.kuzushiIndex = (spineDeviation * 0.7 + movementFactor * 0.3) * 100.0
    }
}
