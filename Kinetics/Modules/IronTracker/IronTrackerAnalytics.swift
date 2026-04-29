import Vision
import Foundation

// MARK: - LiftPhase

/// The current phase of a barbell lift, detected from hip-joint displacement across frames.
enum LiftPhase: String, Sendable {
    case ready   = "Ready"
    case descent = "Descent"
    case bottom  = "Bottom"
    case ascent  = "Ascent"
    case lockout = "Lockout"
}

// MARK: - IronTrackerMetrics

/// All biomechanics values surfaced for a single Iron Tracker session frame.
///
/// Immutable once produced per frame — the ViewModel holds a `var` copy and
/// replaces it in full on each `analyze` call.
struct IronTrackerMetrics: Sendable {

    // MARK: Bar Path

    /// Current bar position (wrist midpoint) in Vision normalized coordinates (origin: bottom-left).
    var barMidpoint: CGPoint = .zero

    // MARK: Velocity-Based Training (VBT)

    /// Concentric bar speed this frame in m/s.
    var barVelocityMS: Double = 0
    /// Highest bar speed recorded this session in m/s.
    /// For powerlifting, values > 0.5 m/s indicate competitive bar speed.
    var peakBarVelocityMS: Double = 0

    // MARK: Bilateral Symmetry

    /// Percentage deviation between left and right wrist ascent speeds.
    /// 0 = perfect symmetry. Positive = right side faster. Negative = left side faster.
    var bilateralSymmetry: Double = 0
    /// True when `abs(bilateralSymmetry)` exceeds the 15 % alert threshold.
    var isSymmetryAlert: Bool = false

    // MARK: Posture

    /// Interior hip angle (degrees) at the left side: knee → hip → shoulder.
    /// Values < 70° at squat bottom indicate lumbar flexion under load (butt wink).
    var leftHipAngle: Double = 0
    /// True when the athlete is at the squat bottom AND the hip angle indicates butt wink.
    var isButtWink: Bool = false
    /// True when either knee is collapsing inward relative to the corresponding ankle.
    var isKneeCave: Bool = false

    // MARK: Lift State

    /// Detected phase of the current rep.
    var liftPhase: LiftPhase = .ready

    // MARK: - Display Helpers

    var velocityDisplay: String     { String(format: "%.2f m/s", barVelocityMS) }
    var peakVelocityDisplay: String { String(format: "%.2f", peakBarVelocityMS) }
    var symmetryDisplay: String     { String(format: "%.0f%%", abs(bilateralSymmetry)) }
    var hipAngleDisplay: String     { String(format: "%.0f°", leftHipAngle) }
}

// MARK: - IronTrackerAnalytics

/// Pure, stateless analytics namespace for the Iron Tracker module.
///
/// Every method is static. The ViewModel calls `analyze(pose:previous:frameRate:currentMetrics:viewSize:)`
/// once per frame and receives a fully-updated `IronTrackerMetrics` value. No mutation occurs here.
///
/// **Bar proxy:** Vision cannot detect a barbell directly. This module uses the midpoint
/// of `leftWrist` and `rightWrist` as the bar position — accurate for bilateral lifts
/// where both hands grip the bar symmetrically (squat, bench, deadlift, clean, snatch).
///
/// **Coordinate system:** Vision normalized coordinates have the origin at the bottom-left
/// of the frame. "Higher Y = higher in the frame." For Y displacement:
///   - Hip descending → deltaY is negative (squatting down).
///   - Hip ascending  → deltaY is positive (standing up).
enum IronTrackerAnalytics {

    // MARK: - Active Joints

    /// The joints this module highlights in the pose overlay.
    static let activeJoints: Set<VNHumanBodyPoseObservation.JointName> = [
        .leftWrist,    .rightWrist,
        .leftElbow,    .rightElbow,
        .leftShoulder, .rightShoulder,
        .leftHip,      .rightHip,
        .leftKnee,     .rightKnee,
        .leftAnkle,    .rightAnkle,
    ]

    // MARK: - Thresholds

    /// Bilateral wrist-speed deviation above which asymmetric loading is flagged.
    static let symmetryAlertThreshold: Double = 15.0

    /// Left hip angle (knee → hip → shoulder) below which butt wink is considered present.
    static let buttWinkAngleThreshold: Double = 70.0

    /// Minimum concentric bar velocity (m/s) for a powerlifting rep to be rated "good speed."
    static let vbtGoodThreshold: Double = 0.5

    /// Normalized distance threshold: knee must be this far inside the ankle's X to trigger valgus.
    private static let kneeCaveThreshold: CGFloat = 0.04

    /// Y-axis delta below which hips are considered stationary (dead zone to filter noise).
    private static let hipMovementDeadZone: Double = 0.005

    // MARK: - Main Entry Point

    /// Analyzes one frame of pose data and returns a fully-updated `IronTrackerMetrics`.
    ///
    /// - Parameters:
    ///   - pose:           The body pose for the current frame.
    ///   - previous:       The body pose from the immediately preceding frame, or `nil` on frame 1.
    ///   - frameRate:      Camera capture rate in fps (typically 30).
    ///   - currentMetrics: The metrics struct from the previous frame — session-accumulating
    ///                     fields (`peakBarVelocityMS`) are carried forward.
    ///   - viewSize:       Rendered camera preview size in points; used by `calculateSpeedMS`
    ///                     for pixel-accurate velocity conversion.
    /// - Returns: A new `IronTrackerMetrics` value reflecting this frame.
    static func analyze(
        pose: JointPose,
        previous: JointPose?,
        frameRate: Double,
        currentMetrics: IronTrackerMetrics,
        viewSize: CGSize
    ) -> IronTrackerMetrics {
        var metrics = currentMetrics

        metrics = updateBarMetrics(
            metrics: metrics,
            pose: pose,
            previous: previous,
            frameRate: frameRate,
            viewSize: viewSize
        )
        metrics = updatePostureMetrics(metrics: metrics, pose: pose)
        metrics.liftPhase = detectPhase(pose: pose, previous: previous)

        return metrics
    }

    // MARK: - Bar Midpoint + VBT + Symmetry

    /// Updates bar position, VBT velocity, peak velocity, and bilateral symmetry.
    ///
    /// Returns `metrics` unchanged when either wrist joint is below the confidence threshold.
    private static func updateBarMetrics(
        metrics: IronTrackerMetrics,
        pose: JointPose,
        previous: JointPose?,
        frameRate: Double,
        viewSize: CGSize
    ) -> IronTrackerMetrics {
        guard
            let lWrist = pose[.leftWrist],  lWrist.isReliable,
            let rWrist = pose[.rightWrist], rWrist.isReliable
        else { return metrics }

        var updated = metrics

        // 1. Bar midpoint — wrist average in Vision normalized coords.
        updated.barMidpoint = CGPoint(
            x: (lWrist.position.x + rWrist.position.x) / 2,
            y: (lWrist.position.y + rWrist.position.y) / 2
        )

        guard
            let prev = previous,
            let prevLWrist = prev[.leftWrist],  prevLWrist.isReliable,
            let prevRWrist = prev[.rightWrist], prevRWrist.isReliable
        else { return updated }

        let prevMidpoint = CGPoint(
            x: (prevLWrist.position.x + prevRWrist.position.x) / 2,
            y: (prevLWrist.position.y + prevRWrist.position.y) / 2
        )

        // 2. VBT bar speed in m/s.
        let barSpeed = BiomechanicsCalculator.calculateSpeedMS(
            from: prevMidpoint,
            to: updated.barMidpoint,
            frameRate: frameRate,
            viewSize: viewSize
        )
        updated.barVelocityMS = barSpeed

        if barSpeed > updated.peakBarVelocityMS {
            updated.peakBarVelocityMS = barSpeed
        }

        // 3. Bilateral symmetry — compare each wrist's individual travel speed.
        let leftSpeed = BiomechanicsCalculator.calculateSpeedMS(
            from: prevLWrist.position,
            to: lWrist.position,
            frameRate: frameRate,
            viewSize: viewSize
        )
        let rightSpeed = BiomechanicsCalculator.calculateSpeedMS(
            from: prevRWrist.position,
            to: rWrist.position,
            frameRate: frameRate,
            viewSize: viewSize
        )
        updated.bilateralSymmetry = BiomechanicsCalculator.calculateBilateralSymmetry(
            left: leftSpeed,
            right: rightSpeed
        )
        updated.isSymmetryAlert = abs(updated.bilateralSymmetry) > symmetryAlertThreshold

        return updated
    }

    // MARK: - Posture: Butt Wink + Knee Cave

    /// Updates butt wink and knee cave flags from the current pose.
    private static func updatePostureMetrics(
        metrics: IronTrackerMetrics,
        pose: JointPose
    ) -> IronTrackerMetrics {
        var updated = metrics

        // 4. Butt wink — hip angle at the squat bottom.
        if let lKnee     = pose[.leftKnee],     lKnee.isReliable,
           let lHip      = pose[.leftHip],       lHip.isReliable,
           let lShoulder = pose[.leftShoulder],  lShoulder.isReliable {
            updated.leftHipAngle = BiomechanicsCalculator.calculateAngle(
                joint1: lKnee.position,
                vertex: lHip.position,
                joint2: lShoulder.position
            )
            // Only flag butt wink when hips are at or below knee height (squat bottom position).
            // Vision Y: a higher value means higher in the frame.
            // At squat bottom, hipY ≤ kneeY (hips are level with or below the knees).
            let atSquatBottom = lHip.position.y <= lKnee.position.y + 0.05
            updated.isButtWink = atSquatBottom && updated.leftHipAngle < buttWinkAngleThreshold
        }

        // 5. Knee cave (valgus collapse) — knee X-position drifting inside the ankle.
        if let lKnee  = pose[.leftKnee],   lKnee.isReliable,
           let lAnkle = pose[.leftAnkle],  lAnkle.isReliable,
           let rKnee  = pose[.rightKnee],  rKnee.isReliable,
           let rAnkle = pose[.rightAnkle], rAnkle.isReliable {
            // Left knee collapsing rightward (higher X in Vision normalized space).
            let leftCave  = lKnee.position.x > lAnkle.position.x + kneeCaveThreshold
            // Right knee collapsing leftward (lower X in Vision normalized space).
            let rightCave = rKnee.position.x < rAnkle.position.x - kneeCaveThreshold
            updated.isKneeCave = leftCave || rightCave
        }

        return updated
    }

    // MARK: - Lift Phase Detection

    /// Infers the current phase of a rep by tracking hip displacement between frames.
    ///
    /// Uses the left hip as the reference joint. Falls back to `.ready` when joint data
    /// is unavailable or displacement is within the noise dead zone.
    private static func detectPhase(
        pose: JointPose,
        previous: JointPose?
    ) -> LiftPhase {
        guard
            let lHip     = pose[.leftHip],         lHip.isReliable,
            let prev     = previous,
            let prevLHip = prev[.leftHip],          prevLHip.isReliable
        else { return .ready }

        // Positive deltaY = hips moving upward (ascending); negative = downward (descending).
        let deltaY = Double(lHip.position.y - prevLHip.position.y)

        if abs(deltaY) < hipMovementDeadZone { return .ready }
        return deltaY < 0 ? .descent : .ascent
    }
}
