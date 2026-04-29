import Vision
import Foundation

// MARK: - JointPoint

/// A single joint's position and detection confidence from a Vision body pose observation.
/// Position is in Vision's normalized coordinate space (0..1, origin at bottom-left).
struct JointPoint: Sendable {
    /// Normalized position in Vision coordinate space (origin: bottom-left).
    let position: CGPoint
    /// Detection confidence in [0, 1].
    let confidence: Float
    /// True when confidence exceeds the reliability threshold of 0.5.
    var isReliable: Bool { confidence > 0.5 }
}

// MARK: - JointPose

/// A complete body pose snapshot for a single video frame.
/// All 19 Vision skeleton joints are captured with their positions and confidence values.
struct JointPose: Sendable {
    /// All recognized joints keyed by their Vision joint name.
    let joints: [VNHumanBodyPoseObservation.JointName: JointPoint]
    /// Presentation timestamp in seconds, derived from the observation's time range end.
    let timestamp: TimeInterval

    // MARK: Subscript

    /// Convenience accessor — returns nil when the joint was not detected.
    subscript(joint: VNHumanBodyPoseObservation.JointName) -> JointPoint? {
        joints[joint]
    }
}

// MARK: - JointPose + VNHumanBodyPoseObservation

extension JointPose {
    /// Creates a `JointPose` by extracting all recognized points from a Vision observation.
    /// - Parameter observation: A `VNHumanBodyPoseObservation` produced by `VNDetectHumanBodyPoseRequest`.
    /// - Throws: Any error thrown by `recognizedPoints(_:)` (e.g., unsupported joint group).
    init(from observation: VNHumanBodyPoseObservation) throws {
        let recognizedPoints = try observation.recognizedPoints(.all)

        var mappedJoints: [VNHumanBodyPoseObservation.JointName: JointPoint] = [:]
        mappedJoints.reserveCapacity(recognizedPoints.count)

        for (name, point) in recognizedPoints {
            mappedJoints[name] = JointPoint(
                position: point.location,
                confidence: point.confidence
            )
        }

        self.joints = mappedJoints
        // timeRange.end gives the presentation timestamp of the frame that produced this observation.
        self.timestamp = observation.timeRange.end.seconds
    }
}
