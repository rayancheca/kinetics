import Foundation
import CoreGraphics

// MARK: - BiomechanicsCalculator

/// Pure, stateless biomechanics math shared across all four sport modules.
///
/// All methods are static — `BiomechanicsCalculator` is a namespace, not an object.
/// Inputs use Vision's normalized coordinate space (0..1) unless a `viewSize` overload
/// is supplied for pixel-accurate calculations.
enum BiomechanicsCalculator {

    // MARK: - Velocity

    /// Estimates strike or limb velocity in **mph** from two consecutive normalized joint positions.
    ///
    /// Vision coordinates are unitless (0..1), so a conversion factor is applied.
    /// At a typical 3-metre filming distance, 1 normalized unit ≈ 2 metres.
    ///
    /// - Parameters:
    ///   - from: Starting joint position (normalized).
    ///   - to: Ending joint position (normalized), captured one frame later.
    ///   - frameRate: Camera frame rate in frames per second (e.g. 30, 60, 240).
    /// - Returns: Approximate velocity in miles per hour.
    static func calculateVelocity(from: CGPoint, to: CGPoint, frameRate: Double) -> Double {
        guard frameRate > 0 else { return 0 }
        let dx = Double(to.x - from.x)
        let dy = Double(to.y - from.y)
        let displacementNormalized = sqrt(dx * dx + dy * dy)

        // 1 normalized unit ≈ 2 metres at typical filming distance.
        let metersPerUnit = 2.0
        let metersPerFrame = displacementNormalized * metersPerUnit
        let metersPerSecond = metersPerFrame * frameRate
        let milesPerHour = metersPerSecond * 2.237
        return milesPerHour
    }

    /// Estimates limb or bar speed in **m/s**, using the rendered view size for higher accuracy.
    ///
    /// This overload converts normalized coordinates to pixels first, then applies a
    /// pixels-per-metre calibration, avoiding the fixed-distance assumption in `calculateVelocity`.
    ///
    /// - Parameters:
    ///   - from: Starting joint position (normalized).
    ///   - to: Ending joint position (normalized).
    ///   - frameRate: Camera frame rate in fps.
    ///   - viewSize: Size of the camera preview view in points; used to scale normalized coords.
    /// - Returns: Approximate speed in metres per second.
    static func calculateSpeedMS(
        from: CGPoint,
        to: CGPoint,
        frameRate: Double,
        viewSize: CGSize
    ) -> Double {
        guard frameRate > 0, viewSize.width > 0, viewSize.height > 0 else { return 0 }
        let dx = Double((to.x - from.x) * viewSize.width)
        let dy = Double((to.y - from.y) * viewSize.height)
        let pixelDisplacement = sqrt(dx * dx + dy * dy)

        // Calibration: 100 pixels ≈ 0.5 metres at typical filming distance.
        let metersPerPixel = 0.005
        let metersPerFrame = pixelDisplacement * metersPerPixel
        return metersPerFrame * frameRate
    }

    // MARK: - Angles

    /// Calculates the interior angle (in degrees, range 0..180) at `vertex`,
    /// formed by the vectors `vertex → joint1` and `vertex → joint2`.
    ///
    /// Typical uses:
    /// - Elbow flexion: `joint1 = shoulder`, `vertex = elbow`, `joint2 = wrist`
    /// - Knee angle: `joint1 = hip`, `vertex = knee`, `joint2 = ankle`
    ///
    /// - Returns: Angle in degrees, or `0` if either vector is degenerate (zero length).
    static func calculateAngle(
        joint1: CGPoint,
        vertex: CGPoint,
        joint2: CGPoint
    ) -> Double {
        let v1 = CGPoint(x: joint1.x - vertex.x, y: joint1.y - vertex.y)
        let v2 = CGPoint(x: joint2.x - vertex.x, y: joint2.y - vertex.y)

        let dot = Double(v1.x * v2.x + v1.y * v2.y)
        let mag1 = sqrt(Double(v1.x * v1.x + v1.y * v1.y))
        let mag2 = sqrt(Double(v2.x * v2.x + v2.y * v2.y))

        guard mag1 > 0, mag2 > 0 else { return 0 }

        // Clamp to [-1, 1] to guard against floating-point drift outside acos domain.
        let cosAngle = max(-1.0, min(1.0, dot / (mag1 * mag2)))
        return acos(cosAngle) * (180.0 / .pi)
    }

    /// Returns the bearing angle (degrees, -180..180) of the vector from `from` to `to`
    /// relative to the positive x-axis (rightward).
    ///
    /// Useful for measuring spine lean, bar path tilt, and limb orientation.
    static func calculateVectorAngle(from: CGPoint, to: CGPoint) -> Double {
        let dx = Double(to.x - from.x)
        let dy = Double(to.y - from.y)
        return atan2(dy, dx) * (180.0 / .pi)
    }

    /// Calculates the hip-to-shoulder separation angle in degrees.
    ///
    /// A positive value means hips are rotated ahead of shoulders (coiled for power delivery).
    /// Used by Striking Clinic to verify correct kinetic chain sequencing.
    ///
    /// - Parameters:
    ///   - leftHip: Normalized position of the left hip.
    ///   - rightHip: Normalized position of the right hip.
    ///   - leftShoulder: Normalized position of the left shoulder.
    ///   - rightShoulder: Normalized position of the right shoulder.
    /// - Returns: Separation angle in degrees; positive = hips lead shoulders.
    static func calculateHipShoulderSeparation(
        leftHip: CGPoint,
        rightHip: CGPoint,
        leftShoulder: CGPoint,
        rightShoulder: CGPoint
    ) -> Double {
        let hipAngle = calculateVectorAngle(from: leftHip, to: rightHip)
        let shoulderAngle = calculateVectorAngle(from: leftShoulder, to: rightShoulder)
        // Normalize to (-180, 180].
        var separation = hipAngle - shoulderAngle
        if separation > 180 { separation -= 360 }
        if separation < -180 { separation += 360 }
        return separation
    }

    // MARK: - Center of Mass

    /// Returns the unweighted centroid of the supplied joint positions.
    ///
    /// For a more anatomically accurate CoM, pass only the major load-bearing joints
    /// (hips, shoulders, knees, ankles) rather than all 19 skeleton points.
    ///
    /// - Parameter joints: Array of normalized joint positions (must not be empty).
    /// - Returns: Centroid point, or `.zero` if `joints` is empty.
    static func calculateCenterOfMass(joints: [CGPoint]) -> CGPoint {
        guard !joints.isEmpty else { return .zero }
        let sum = joints.reduce(CGPoint.zero) { accumulated, point in
            CGPoint(x: accumulated.x + point.x, y: accumulated.y + point.y)
        }
        return CGPoint(
            x: sum.x / CGFloat(joints.count),
            y: sum.y / CGFloat(joints.count)
        )
    }

    // MARK: - Bilateral Symmetry

    /// Returns the percentage difference between left and right values.
    ///
    /// - `0` = perfect symmetry.
    /// - Positive result = right side is higher / faster.
    /// - Negative result = left side is higher / faster.
    ///
    /// Used by Iron Tracker to flag asymmetric loading during bilateral lifts.
    ///
    /// - Parameters:
    ///   - left: Left-side measurement (e.g. wrist ascent speed in m/s).
    ///   - right: Right-side measurement.
    /// - Returns: Symmetry deviation in percent, or `0` if both values are zero.
    static func calculateBilateralSymmetry(left: Double, right: Double) -> Double {
        let total = left + right
        guard total > 0 else { return 0 }
        return ((right - left) / total) * 100.0
    }

    // MARK: - Geometry Helpers

    /// Euclidean distance between two normalized points.
    static func distance(from: CGPoint, to: CGPoint) -> Double {
        let dx = Double(to.x - from.x)
        let dy = Double(to.y - from.y)
        return sqrt(dx * dx + dy * dy)
    }

    /// Tests whether `point` lies inside the convex or concave `polygon` defined by
    /// an ordered array of vertices, using the ray-casting algorithm.
    ///
    /// Used by Grappling Lab to determine whether the athlete's center of mass
    /// is still within their support base polygon (feet/knees on the mat).
    ///
    /// - Parameters:
    ///   - point: The point to test (normalized coordinates).
    ///   - polygon: Ordered vertices of the polygon (minimum 3 points).
    /// - Returns: `true` if the point is inside the polygon.
    static func isPoint(_ point: CGPoint, insidePolygon polygon: [CGPoint]) -> Bool {
        guard polygon.count >= 3 else { return false }
        var inside = false
        var j = polygon.count - 1

        for i in 0..<polygon.count {
            let xi = polygon[i].x
            let yi = polygon[i].y
            let xj = polygon[j].x
            let yj = polygon[j].y

            let crossesHorizontal = (yi > point.y) != (yj > point.y)
            let intersectsRay = point.x < (xj - xi) * (point.y - yi) / (yj - yi) + xi

            if crossesHorizontal && intersectsRay {
                inside = !inside
            }
            j = i
        }
        return inside
    }

    /// Calculates the perpendicular deviation of `point` from the line defined by `lineStart`
    /// and `lineEnd`. Used by Iron Tracker to measure bar path deviation from vertical.
    ///
    /// - Returns: Signed perpendicular distance in normalized units.
    static func perpendicularDistance(
        point: CGPoint,
        lineStart: CGPoint,
        lineEnd: CGPoint
    ) -> Double {
        let dx = Double(lineEnd.x - lineStart.x)
        let dy = Double(lineEnd.y - lineStart.y)
        let lineLength = sqrt(dx * dx + dy * dy)
        guard lineLength > 0 else {
            return distance(from: point, to: lineStart)
        }
        // Signed area of the triangle formed by the three points, divided by line length.
        let numerator = abs(
            dy * Double(point.x)
            - dx * Double(point.y)
            + Double(lineEnd.x) * Double(lineStart.y)
            - Double(lineEnd.y) * Double(lineStart.x)
        )
        return numerator / lineLength
    }
}
