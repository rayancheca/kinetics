import SwiftUI
import Vision

// MARK: - PoseOverlayView

/// Canvas-based overlay that draws a 19-joint skeleton on top of the camera feed.
///
/// **Coordinate system note:**
/// Vision produces normalized joint positions with the origin at the **bottom-left**
/// of the frame. SwiftUI's `Canvas` origin is at the **top-left**. The Y axis must
/// be flipped before drawing: `screenY = (1 - jointY) * height`.
///
/// **Draw order:**
/// 1. Bones (lines) — rendered first so joints appear on top.
/// 2. Joints (filled circles with optional accent rings) — rendered last.
///
/// **Confidence gating:**
/// Only joints with `isReliable == true` (confidence > 0.5) are drawn.
/// A bone is drawn only when both of its endpoint joints are reliable.
///
/// Usage:
/// ```swift
/// PoseOverlayView(pose: viewModel.currentPose, activeJoints: StrikingAnalytics.trackedJoints)
///     .allowsHitTesting(false)
/// ```
struct PoseOverlayView: View {

    // MARK: Input

    /// The body pose snapshot for the current frame. Pass `nil` when no pose is detected.
    let pose: JointPose?

    /// The joints to highlight in `color` (module-specific active joints).
    let activeJoints: Set<VNHumanBodyPoseObservation.JointName>

    /// Accent color for active joints and bones — defaults to electric blue.
    var color: Color = .kineticsBlue

    // MARK: Bone Topology

    /// Ordered pairs of joint names that define the skeleton's bone connections.
    /// Only pairs where both joints are reliable will be drawn.
    private let boneConnections: [(VNHumanBodyPoseObservation.JointName, VNHumanBodyPoseObservation.JointName)] = [
        // Left arm
        (.leftShoulder, .leftElbow),
        (.leftElbow, .leftWrist),
        // Right arm
        (.rightShoulder, .rightElbow),
        (.rightElbow, .rightWrist),
        // Shoulder girdle
        (.leftShoulder, .rightShoulder),
        // Torso laterals
        (.leftShoulder, .leftHip),
        (.rightShoulder, .rightHip),
        // Hip girdle
        (.leftHip, .rightHip),
        // Neck to shoulders
        (.neck, .leftShoulder),
        (.neck, .rightShoulder),
        // Root to hips
        (.root, .leftHip),
        (.root, .rightHip),
        // Left leg
        (.leftHip, .leftKnee),
        (.leftKnee, .leftAnkle),
        // Right leg
        (.rightHip, .rightKnee),
        (.rightKnee, .rightAnkle),
        // Head
        (.neck, .nose),
    ]

    // MARK: Body

    var body: some View {
        GeometryReader { geometry in
            Canvas { ctx, size in
                guard let pose else { return }
                drawSkeleton(ctx: ctx, size: size, pose: pose)
            }
        }
        // Overlay must never intercept touches intended for the underlying camera feed.
        .allowsHitTesting(false)
    }

    // MARK: - Drawing Helpers

    /// Draws all bones then all joints for the given pose.
    private func drawSkeleton(ctx: GraphicsContext, size: CGSize, pose: JointPose) {
        // Bones first — joints are drawn on top.
        for (a, b) in boneConnections {
            drawBone(ctx: ctx, size: size, pose: pose, from: a, to: b)
        }
        for (name, point) in pose.joints where point.isReliable {
            drawJoint(ctx: ctx, size: size, joint: point, name: name)
        }
    }

    /// Draws a single bone line between two joints when both are reliably detected.
    private func drawBone(
        ctx: GraphicsContext,
        size: CGSize,
        pose: JointPose,
        from nameA: VNHumanBodyPoseObservation.JointName,
        to nameB: VNHumanBodyPoseObservation.JointName
    ) {
        guard
            let a = pose[nameA], a.isReliable,
            let b = pose[nameB], b.isReliable
        else { return }

        let ptA = visionToScreen(a.position, size: size)
        let ptB = visionToScreen(b.position, size: size)

        let isActive = activeJoints.contains(nameA) || activeJoints.contains(nameB)

        var path = Path()
        path.move(to: ptA)
        path.addLine(to: ptB)

        ctx.stroke(
            path,
            with: .color(isActive ? color.opacity(0.7) : Color.white.opacity(0.3)),
            lineWidth: isActive ? 2.5 : 1.5
        )
    }

    /// Draws a single joint as a filled circle with an optional accent ring for active joints.
    private func drawJoint(
        ctx: GraphicsContext,
        size: CGSize,
        joint: JointPoint,
        name: VNHumanBodyPoseObservation.JointName
    ) {
        let screenPt = visionToScreen(joint.position, size: size)
        let isActive = activeJoints.contains(name)

        let radius: CGFloat = isActive ? 6 : 4
        let fillColor: Color = isActive ? color : Color.white.opacity(0.5)

        let rect = CGRect(
            x: screenPt.x - radius,
            y: screenPt.y - radius,
            width: radius * 2,
            height: radius * 2
        )

        ctx.fill(Path(ellipseIn: rect), with: .color(fillColor))

        // Outer glow ring to help active joints stand out against complex backgrounds.
        if isActive {
            ctx.stroke(
                Path(ellipseIn: rect.insetBy(dx: -2, dy: -2)),
                with: .color(color.opacity(0.4)),
                lineWidth: 1
            )
        }
    }

    // MARK: - Coordinate Conversion

    /// Converts a Vision normalized coordinate (origin: bottom-left) to a
    /// SwiftUI/Core Graphics screen coordinate (origin: top-left).
    private func visionToScreen(_ point: CGPoint, size: CGSize) -> CGPoint {
        CGPoint(
            x: point.x * size.width,
            y: (1.0 - point.y) * size.height  // Flip Y axis
        )
    }
}
