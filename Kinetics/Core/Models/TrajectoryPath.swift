import Vision
import Foundation

// MARK: - TimedPoint

/// A point in normalized Vision coordinate space paired with its capture timestamp.
struct TimedPoint: Sendable {
    /// Normalized position (0..1, Vision bottom-left origin).
    let position: CGPoint
    /// Capture timestamp in seconds.
    let timestamp: TimeInterval
}

// MARK: - TrajectoryPath

/// A sequence of timed positions that describe a detected movement arc —
/// used for bar paths (Iron Tracker), strike arcs (Striking Clinic), and Dyno traces (Wall Beta).
struct TrajectoryPath: Identifiable, Sendable {
    let id: UUID
    /// Ordered series of positions with associated timestamps.
    let points: [TimedPoint]
    /// Wall-clock time at which Vision first reported this trajectory.
    let detectedAt: Date

    // MARK: - Computed Metrics

    /// Mean speed across all consecutive point pairs, expressed in normalized units per second.
    /// Returns 0 when fewer than two points are available.
    var averageVelocity: CGFloat {
        guard points.count >= 2 else { return 0 }

        var totalDistance: CGFloat = 0
        var totalTime: TimeInterval = 0

        for index in 1..<points.count {
            let previous = points[index - 1]
            let current = points[index]

            let dx = current.position.x - previous.position.x
            let dy = current.position.y - previous.position.y
            totalDistance += sqrt(dx * dx + dy * dy)

            let dt = current.timestamp - previous.timestamp
            // Guard against identical timestamps (duplicate frames).
            if dt > 0 {
                totalTime += dt
            }
        }

        guard totalTime > 0 else { return 0 }
        return totalDistance / CGFloat(totalTime)
    }

    /// Total arc length of the trajectory in normalized units.
    var totalDistance: CGFloat {
        guard points.count >= 2 else { return 0 }
        return (1..<points.count).reduce(CGFloat(0)) { acc, index in
            let dx = points[index].position.x - points[index - 1].position.x
            let dy = points[index].position.y - points[index - 1].position.y
            return acc + sqrt(dx * dx + dy * dy)
        }
    }

    /// Duration of the trajectory from first to last detected point, in seconds.
    var duration: TimeInterval {
        guard let first = points.first, let last = points.last else { return 0 }
        return last.timestamp - first.timestamp
    }
}

// MARK: - TrajectoryPath + VNTrajectoryObservation

extension TrajectoryPath {
    /// Creates a `TrajectoryPath` from a Vision trajectory observation.
    ///
    /// `VNTrajectoryObservation.detectedPoints` contains the actual sampled positions along the
    /// arc, stored as `VNPoint` values with normalized x/y coordinates. We use the supplied
    /// `timestamp` as a monotonically increasing base and distribute points evenly across it
    /// when per-point timestamps are unavailable.
    ///
    /// - Parameters:
    ///   - observation: The `VNTrajectoryObservation` from `VNDetectTrajectoriesRequest`.
    ///   - timestamp: Presentation timestamp (seconds) of the frame that produced the observation.
    init(from observation: VNTrajectoryObservation, timestamp: TimeInterval) {
        let detected = observation.detectedPoints
        let count = detected.count

        // Distribute points evenly over the observation's time range when available.
        let timeRange = observation.timeRange
        let startTime: TimeInterval
        let endTime: TimeInterval

        if timeRange.duration.seconds > 0 {
            startTime = timeRange.start.seconds
            endTime = timeRange.end.seconds
        } else {
            // Fall back: place all points at the provided frame timestamp.
            startTime = timestamp
            endTime = timestamp
        }

        let timedPoints: [TimedPoint] = detected.enumerated().map { index, vnPoint in
            let interpolationFactor: TimeInterval = count > 1
                ? TimeInterval(index) / TimeInterval(count - 1)
                : 0
            let pointTimestamp = startTime + (endTime - startTime) * interpolationFactor
            return TimedPoint(
                position: CGPoint(x: CGFloat(vnPoint.x), y: CGFloat(vnPoint.y)),
                timestamp: pointTimestamp
            )
        }

        self.id = UUID()
        self.points = timedPoints
        self.detectedAt = Date()
    }
}
