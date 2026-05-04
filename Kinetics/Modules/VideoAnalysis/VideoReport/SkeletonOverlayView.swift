import SwiftUI

// MARK: - SkeletonOverlayView

/// Canvas-based skeleton overlay rendered on top of the video player.
///
/// Coordinate system notes:
/// - Apple Vision uses (0, 0) at **bottom-left**, (1, 1) at **top-right**.
/// - SwiftUI `Canvas` uses (0, 0) at **top-left**.
/// - Y-axis must be flipped: `displayY = (1 - normalizedY) * height`
///
/// `allowsHitTesting(false)` ensures tap gestures pass through to the
/// video controls underneath.
struct SkeletonOverlayView: View {

    // MARK: - Inputs

    /// All skeleton frames decoded from the session.
    let frames: [FrameSkeletonData]
    /// Current playback position in seconds.
    let currentTime: Double
    /// The module's accent colour — used for active joints and wrists/ankles.
    let sportColor: Color
    /// When `true`, a small label badge is drawn near the subject's neck joint.
    var showSubjectLabel: Bool = true

    // MARK: - Nearest Frame

    /// Returns the frame whose `timestampSeconds` is closest to `currentTime`.
    private var currentFrame: FrameSkeletonData? {
        guard !frames.isEmpty else { return nil }
        // Linear scan is fast enough for typical frame counts (< 1 800 frames).
        return frames.min(by: {
            abs($0.timestampSeconds - currentTime) < abs($1.timestampSeconds - currentTime)
        })
    }

    // MARK: - Body

    var body: some View {
        Canvas { context, size in
            guard let frame = currentFrame else { return }
            drawSkeleton(frame: frame, in: context, size: size)
        }
        .allowsHitTesting(false)
    }

    // MARK: - Drawing

    private func drawSkeleton(
        frame: FrameSkeletonData,
        in context: GraphicsContext,
        size: CGSize
    ) {
        // Global opacity modifier based on subject identity.
        let isPrimary = frame.subjectLabel == "You"
        let globalAlpha: Double = isPrimary ? 1.0 : 0.5

        // Helper: convert Vision normalised coords → canvas point.
        func point(for name: String) -> CGPoint? {
            guard let arr = frame.joints[name],
                  arr.count >= 3,
                  arr[2] >= 0.1 else { return nil }   // minimum confidence gate
            return CGPoint(
                x: arr[0] * size.width,
                y: (1.0 - arr[1]) * size.height
            )
        }

        func confidence(for name: String) -> Double {
            guard let arr = frame.joints[name], arr.count >= 3 else { return 0 }
            return arr[2]
        }

        // MARK: Bone Connections

        // (start joint name, end joint name)
        let bones: [(String, String)] = [
            // Shoulders bar
            ("left_shoulder_1_joint",   "right_shoulder_1_joint"),
            // Neck to shoulders
            ("neck_1_joint",            "left_shoulder_1_joint"),
            ("neck_1_joint",            "right_shoulder_1_joint"),
            // Left arm
            ("left_shoulder_1_joint",   "left_forearm_joint"),
            ("left_forearm_joint",      "left_hand_joint"),
            // Right arm
            ("right_shoulder_1_joint",  "right_forearm_joint"),
            ("right_forearm_joint",     "right_hand_joint"),
            // Hips bar
            ("left_upLeg_joint",        "right_upLeg_joint"),
            // Left leg
            ("left_upLeg_joint",        "left_leg_joint"),
            ("left_leg_joint",          "left_foot_joint"),
            // Right leg
            ("right_upLeg_joint",       "right_leg_joint"),
            ("right_leg_joint",         "right_foot_joint"),
        ]

        // Spine: neck → midpoint of hips (root).
        // We approximate root as midpoint of left/right upLeg joints.
        let spineColor = Color.white.opacity(0.6 * globalAlpha)
        let boneColor  = Color.white.opacity(0.6 * globalAlpha)

        // Draw spine first (behind everything else).
        if let neckPt = point(for: "neck_1_joint"),
           let lHip   = point(for: "left_upLeg_joint"),
           let rHip   = point(for: "right_upLeg_joint") {
            let rootPt = CGPoint(
                x: (lHip.x + rHip.x) / 2.0,
                y: (lHip.y + rHip.y) / 2.0
            )
            drawLine(
                from: neckPt,
                to: rootPt,
                color: spineColor,
                lineWidth: 2.5,
                in: context
            )
        }

        // Determine which joint names get the accent colour treatment.
        let accentJointNames: Set<String> = [
            "left_hand_joint", "right_hand_joint",
            "left_foot_joint", "right_foot_joint"
        ]

        // Draw regular bones.
        for (startName, endName) in bones {
            guard let startPt = point(for: startName),
                  let endPt   = point(for: endName) else { continue }
            drawLine(
                from: startPt,
                to: endPt,
                color: boneColor,
                lineWidth: 2.5,
                in: context
            )
        }

        // MARK: Joint Dots

        let allJointNames = Set(bones.flatMap { [$0.0, $0.1] })
            .union(["neck_1_joint"])

        for name in allJointNames {
            guard let pt = point(for: name) else { continue }
            let conf = confidence(for: name)
            let isAccent = accentJointNames.contains(name)

            let fillColor: Color
            let radius: CGFloat

            if conf > 0.7 {
                fillColor = isAccent
                    ? sportColor.opacity(0.9 * globalAlpha)
                    : sportColor.opacity(0.75 * globalAlpha)
                radius = isAccent ? 5.5 : 4.5
            } else {
                // Low confidence — render as a dimmer, smaller dot.
                fillColor = Color.white.opacity(0.4 * globalAlpha)
                radius = 3.0
            }

            let rect = CGRect(
                x: pt.x - radius,
                y: pt.y - radius,
                width: radius * 2,
                height: radius * 2
            )
            context.fill(Path(ellipseIn: rect), with: .color(fillColor))
        }

        // MARK: Subject Label Badge

        if showSubjectLabel {
            let labelText = frame.subjectLabel.isEmpty ? "Unknown" : frame.subjectLabel
            let labelColor: Color = (frame.subjectLabel == "You")
                ? Color.kineticsGreen
                : Color.kineticsAmber

            // Anchor the label just above the neck or nose joint.
            let anchorName = frame.joints["nose_2_joint"] != nil
                ? "nose_2_joint"
                : "neck_1_joint"

            if let anchorPt = point(for: anchorName) {
                drawSubjectBadge(
                    text: labelText,
                    at: CGPoint(x: anchorPt.x, y: anchorPt.y - 20),
                    color: labelColor,
                    alpha: globalAlpha,
                    in: context
                )
            }
        }
    }

    // MARK: - Draw Helpers

    private func drawLine(
        from start: CGPoint,
        to end: CGPoint,
        color: Color,
        lineWidth: CGFloat,
        in context: GraphicsContext
    ) {
        var path = Path()
        path.move(to: start)
        path.addLine(to: end)
        context.stroke(
            path,
            with: .color(color),
            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
        )
    }

    private func drawSubjectBadge(
        text: String,
        at center: CGPoint,
        color: Color,
        alpha: Double,
        in context: GraphicsContext
    ) {
        let resolved = context.resolve(
            Text(text)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundColor(color.opacity(alpha))
        )

        // Measure text to build the capsule background.
        let textSize = resolved.measure(in: CGSize(width: 200, height: 40))
        let padding: CGFloat = 5
        let badgeRect = CGRect(
            x: center.x - textSize.width / 2.0 - padding,
            y: center.y - textSize.height / 2.0 - 2,
            width: textSize.width + padding * 2,
            height: textSize.height + 4
        )
        let capsulePath = Path(
            roundedRect: badgeRect,
            cornerRadius: badgeRect.height / 2
        )
        context.fill(
            capsulePath,
            with: .color(Color.black.opacity(0.55 * alpha))
        )
        context.draw(
            resolved,
            at: CGPoint(x: center.x, y: center.y),
            anchor: .center
        )
    }
}
