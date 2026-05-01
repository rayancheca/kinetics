import Foundation
import Vision

// MARK: - InjuryRiskDetector

/// Flags dangerous movement patterns that commonly cause injury during resistance training.
///
/// Stateless — call `evaluate(joints:)` on each frame and receive a fresh array of flags.
/// The ViewModel is responsible for caching and acting on the results.
struct InjuryRiskDetector: Sendable {

    // MARK: - RiskFlag

    /// A single detected injury-risk condition.
    struct RiskFlag: Identifiable, Equatable, Sendable {
        let id: UUID
        let severity: RiskSeverity
        let message: String
        /// The joint or body region responsible for the flag (used for logging/analytics).
        let joint: String

        init(severity: RiskSeverity, message: String, joint: String) {
            self.id = UUID()
            self.severity = severity
            self.message = message
            self.joint = joint
        }
    }

    // MARK: - RiskSeverity

    enum RiskSeverity: String, Sendable {
        case warning = "Warning"
        case danger  = "Danger"
    }

    // MARK: - Thresholds

    /// X offset (normalized) a knee must track inside the ankle before valgus is flagged.
    private let kneeCaveThreshold: Double = 0.05

    /// Nose must be this far ahead of the shoulder midpoint (X) to flag forward head posture.
    private let forwardHeadThreshold: Double = 0.10

    /// Elbow must be this far below the wrist (Y) to flag hyperextension risk.
    private let elbowHyperextensionThreshold: Double = 0.12

    /// Hip Y position below which the "squat bottom" lumbar check activates.
    private let squatBottomHipYThreshold: Double = 0.35

    /// Minimum hip-to-shoulder vertical span at squat bottom. If the torso collapses
    /// (span shrinks), lumbar flexion under load is implied.
    private let buttWinkTorsoSpanMin: Double = 0.08

    /// Shoulder Y asymmetry (normalized) above which uneven loading is flagged.
    private let shoulderAsymmetryThreshold: Double = 0.08

    // MARK: - Public Interface

    /// Evaluates the joint map for this frame and returns any active risk flags.
    ///
    /// Returns an empty array when no dangerous conditions are present.
    /// Multiple flags can coexist (e.g. knee cave AND forward head simultaneously).
    ///
    /// - Parameter joints: A dictionary of joint names to their normalized Vision positions.
    ///   Use `JointPose`'s subscript and filter for `isReliable` before building this map.
    /// - Returns: Array of active `RiskFlag` values, ordered by detection priority.
    func evaluate(
        joints: [VNHumanBodyPoseObservation.JointName: CGPoint]
    ) -> [RiskFlag] {
        var flags: [RiskFlag] = []

        // 1. Knee cave (valgus collapse) — knees tracking inside ankles during squats.
        if let leftKnee  = joints[.leftKnee],
           let leftAnkle = joints[.leftAnkle],
           let rightKnee  = joints[.rightKnee],
           let rightAnkle = joints[.rightAnkle] {
            let leftCave  = Double(leftKnee.x - leftAnkle.x)   >  kneeCaveThreshold
            let rightCave = Double(rightAnkle.x - rightKnee.x) >  kneeCaveThreshold
            if leftCave || rightCave {
                flags.append(RiskFlag(
                    severity: .warning,
                    message: "Knee cave detected — push knees out",
                    joint: "knee"
                ))
            }
        }

        // 2. Forward head posture — nose significantly ahead of shoulder midpoint.
        if let nose          = joints[.nose],
           let leftShoulder  = joints[.leftShoulder],
           let rightShoulder = joints[.rightShoulder] {
            let shoulderMidX = (leftShoulder.x + rightShoulder.x) / 2
            if Double(nose.x - shoulderMidX) > forwardHeadThreshold {
                flags.append(RiskFlag(
                    severity: .warning,
                    message: "Forward head — tuck chin",
                    joint: "neck"
                ))
            }
        }

        // 3. Hyperextended elbow — elbow Y below wrist Y on pressing movements.
        if let leftElbow = joints[.leftElbow],
           let leftWrist = joints[.leftWrist] {
            if Double(leftWrist.y - leftElbow.y) > elbowHyperextensionThreshold {
                flags.append(RiskFlag(
                    severity: .danger,
                    message: "Lock-out risk — don't hyperextend elbow",
                    joint: "elbow"
                ))
            }
        }

        // 4. Lumbar rounding (butt wink) — hips low and torso collapsed at squat bottom.
        if let root          = joints[.root],
           let leftShoulder  = joints[.leftShoulder] {
            let atBottom    = Double(root.y) < squatBottomHipYThreshold
            let torsoSpan   = Double(leftShoulder.y - root.y)
            let isCollapsed = torsoSpan < buttWinkTorsoSpanMin
            if atBottom && isCollapsed {
                flags.append(RiskFlag(
                    severity: .danger,
                    message: "Butt wink detected — protect lower back",
                    joint: "spine"
                ))
            }
        }

        // 5. Asymmetric shoulder loading — one shoulder significantly higher than the other.
        if let leftShoulder  = joints[.leftShoulder],
           let rightShoulder = joints[.rightShoulder] {
            let diff = abs(Double(leftShoulder.y - rightShoulder.y))
            if diff > shoulderAsymmetryThreshold {
                flags.append(RiskFlag(
                    severity: .warning,
                    message: "Uneven load — check bar position",
                    joint: "shoulder"
                ))
            }
        }

        return flags
    }
}
