@preconcurrency import AVFoundation
import Vision

// MARK: - TrajectoryError

enum TrajectoryError: LocalizedError, Sendable {
    case processingFailed(Error)

    var errorDescription: String? {
        switch self {
        case .processingFailed(let underlying):
            "Trajectory tracking failed: \(underlying.localizedDescription)"
        }
    }
}

// MARK: - TrajectoryTracker

/// An actor that detects movement arcs in video frames using `VNDetectTrajectoriesRequest`.
///
/// **Design notes:**
/// - `actor` isolation keeps Vision work off the main thread, matching `PoseDetectionEngine`'s
///   pattern so both engines run concurrently on their own executors.
/// - `VNDetectTrajectoriesRequest` is stateful — it accumulates frames internally to build
///   trajectory arcs. The trajectory length of 10 frames filters out noise and single-frame
///   flickers, producing arcs that are geometrically meaningful for coaching feedback.
/// - The request is declared `var` so `reset()` can swap in a fresh instance, discarding
///   all accumulated arc state between sessions.
/// - `allTrackedPaths` caches the most recent detection results for read access by ViewModels
///   without forcing another `process` call.
///
/// **Use cases by module:**
/// - **Iron Tracker**: tracks the wrist-midpoint arc (bar path) during a lift.
/// - **Striking Clinic**: captures the fist/foot arc during a strike.
/// - **Wall Beta**: records the full-body Dyno arc during explosive climbing moves.
actor TrajectoryTracker {

    // MARK: - Private

    /// Maintains temporal state across frames. Replaced on `reset()`.
    private var sequenceHandler = VNSequenceRequestHandler()

    /// The Vision request. `trajectoryLength: 10` requires a minimum of 10 consecutive
    /// frames before reporting an arc — balances noise rejection with responsiveness at 30fps
    /// (roughly 333 ms minimum arc length).
    private var trajectoryRequest: VNDetectTrajectoriesRequest

    // MARK: - State

    /// The trajectories detected in the most recent processed frame.
    /// Empty when no arcs have been detected yet or after `reset()`.
    private(set) var allTrackedPaths: [TrajectoryPath] = []

    // MARK: - Init

    init() {
        // `frameAnalysisSpacing: 1` means every frame is analyzed — no skip.
        // Reduce to 2 or 3 on older hardware if CPU pressure is too high.
        trajectoryRequest = VNDetectTrajectoriesRequest(
            frameAnalysisSpacing: .zero,
            trajectoryLength: 10
        )
    }

    // MARK: - Public API

    /// Processes one video frame and returns any movement arcs detected so far.
    ///
    /// Vision accumulates frames internally; arcs are only returned once enough frames
    /// have been observed to satisfy `trajectoryLength`. An empty array is normal for the
    /// first ~10 frames and between movement bursts.
    ///
    /// - Parameter buffer: A `CMSampleBuffer` from `CameraManager.frameStream`.
    /// - Returns: An array of `TrajectoryPath` values describing detected movement arcs,
    ///   or an empty array when no arcs meet the minimum length threshold.
    /// - Throws: `TrajectoryError.processingFailed` on an unrecoverable Vision error.
    func process(_ buffer: CMSampleBuffer) throws -> [TrajectoryPath] {
        do {
            try sequenceHandler.perform([trajectoryRequest], on: buffer, orientation: .up)
        } catch {
            throw TrajectoryError.processingFailed(error)
        }

        guard let observations = trajectoryRequest.results, !observations.isEmpty else {
            // No arcs yet — not an error, just not enough frames accumulated.
            return []
        }

        let timestamp = CACurrentMediaTime()
        let paths = observations.map { observation in
            TrajectoryPath(from: observation, timestamp: timestamp)
        }

        allTrackedPaths = paths
        return paths
    }

    /// Clears all accumulated arc state and resets to a clean baseline.
    ///
    /// Call this when:
    /// - A session ends and the next set of arcs should be tracked independently.
    /// - The user switches between sport modules.
    /// - The camera feed is interrupted for more than a few seconds.
    func reset() {
        allTrackedPaths = []
        // Replace both the sequence handler and the trajectory request so Vision has no
        // memory of prior frames. A fresh request also lets callers adjust `trajectoryLength`
        // between sessions if needed in a future API extension.
        sequenceHandler = VNSequenceRequestHandler()
        trajectoryRequest = VNDetectTrajectoriesRequest(
            frameAnalysisSpacing: .zero,
            trajectoryLength: 10
        )
    }
}
