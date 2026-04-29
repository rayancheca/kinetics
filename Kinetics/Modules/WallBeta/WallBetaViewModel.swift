import AVFoundation
import Foundation
import Observation
import Vision

// MARK: - WallBetaViewModel

/// Orchestrates the Wall Beta climbing analysis session.
///
/// Responsibilities:
/// - Starts and stops the shared `CameraManager`.
/// - Feeds each camera frame through `PoseDetectionEngine` on the actor's executor.
/// - Manages session-level state: hip baseline, hold timer, Dyno path capture.
/// - Calls `WallBetaAnalytics.analyze` and publishes results to `@MainActor`.
/// - Drives the session duration timer and persists the completed result via `SessionRepository`.
///
/// **Threading model:**
/// - `@Observable @MainActor` — all `@Observable` property mutations are safe to bind in SwiftUI.
/// - Vision work runs inside `PoseDetectionEngine` (an `actor`), keeping the main thread
///   free for 60 fps rendering.
/// - Background tasks are structured (`Task`) so cancellation is cooperative and automatic.
@Observable
@MainActor
final class WallBetaViewModel {

    // MARK: - Public State

    /// Latest analytics snapshot — updated at the camera frame rate (~30 fps).
    private(set) var metrics = WallBetaMetrics()

    /// Most recently detected body pose. Consumed by `PoseOverlayView` for skeleton rendering.
    private(set) var currentPose: JointPose?

    /// Center-of-mass positions captured during a Dyno event, in Vision normalized coordinates.
    /// Capped at `maxDynoPoints` entries to bound memory usage. Consumed by the Dyno arc overlay.
    private(set) var dynoPath: [CGPoint] = []

    /// Elapsed session time in seconds, ticked once per second while a session is active.
    private(set) var sessionDuration: TimeInterval = 0

    /// `true` while the camera and Vision engine are actively processing frames.
    private(set) var isSessionActive = false

    /// Non-nil when an unrecoverable camera or Vision error has occurred.
    private(set) var errorMessage: String?

    // MARK: - Private — Frame-Level State

    /// Dedicated Vision engine for this module. Re-created on each session start so
    /// temporal smoothing state never leaks across sessions.
    private var poseEngine = PoseDetectionEngine()

    /// The preceding frame's pose, used to compute inter-frame velocities.
    private var previousPose: JointPose?

    // MARK: - Private — Session-Level State

    /// Wall-clock timestamp when the current session began.
    private var sessionStartDate: Date?

    /// The hip Y position (Vision normalized) from the first reliable root observation.
    /// Acts as a stable reference point for sag detection throughout the session.
    private var hipYBaseline: Double?

    /// The wall-clock timestamp when the current static hold started.
    /// `nil` while the climber is moving.
    private var holdStartTime: Date?

    // MARK: - Private — Constants

    /// Maximum number of CoM points stored for the Dyno arc overlay.
    private let maxDynoPoints = 60

    // MARK: - Private — Background Tasks

    /// Retains the long-lived frame-processing loop so it can be cancelled on session end.
    private var processingTask: Task<Void, Never>?

    /// Retains the 1-second timer task that ticks `sessionDuration`.
    private var timerTask: Task<Void, Never>?

    // MARK: - Session Lifecycle

    /// Starts the camera and begins real-time pose analysis.
    ///
    /// Safe to call once per session. Calling again while active is a no-op.
    ///
    /// - Parameter cameraManager: The shared `CameraManager` from `AppState`.
    func startProcessing(with cameraManager: CameraManager) async {
        guard !isSessionActive else { return }

        // Reset all session-scoped state before starting.
        metrics        = WallBetaMetrics()
        dynoPath       = []
        previousPose   = nil
        hipYBaseline   = nil
        holdStartTime  = Date()   // Assume static until first movement detected.
        errorMessage   = nil

        // Log the analytics event before the camera rolls so funnel attribution is clean.
        SessionRepository.shared.logSessionStarted(sport: .wallBeta)

        await cameraManager.startSession()

        guard cameraManager.cameraError == nil else {
            errorMessage = cameraManager.cameraError?.localizedDescription
                ?? "Camera could not be started."
            return
        }

        isSessionActive  = true
        sessionStartDate = Date()

        startTimer()
        startProcessingLoop(cameraManager: cameraManager)
    }

    /// Stops the session, cancels all background tasks, and persists the result to Firestore.
    ///
    /// Sessions shorter than 2 seconds are discarded — they represent accidental taps.
    ///
    /// - Parameter userId: The authenticated user's Firebase UID.
    func endSession(userId: String) async {
        guard isSessionActive else { return }

        processingTask?.cancel()
        timerTask?.cancel()
        processingTask = nil
        timerTask      = nil

        isSessionActive = false

        // Capture the final duration before clearing the start date.
        let finalDuration = sessionStartDate.map { Date().timeIntervalSince($0) } ?? sessionDuration

        // Discard sessions too short to contain meaningful data.
        guard finalDuration > 2 else {
            sessionStartDate = nil
            return
        }

        let result = SessionResult(
            sport: .wallBeta,
            startedAt: sessionStartDate ?? Date(),
            duration: finalDuration,
            metrics: snapshotMetricsDict(),
            userId: userId
        )

        // Reset the Vision engine's temporal state before the next session.
        await poseEngine.reset()
        sessionStartDate = nil

        do {
            try await SessionRepository.shared.save(result)
        } catch {
            // Non-fatal — the session result may not persist but the app stays stable.
            errorMessage = "Session could not be saved: \(error.localizedDescription)"
        }
    }

    // MARK: - Private — Frame Processing Loop

    /// Starts an unstructured task that consumes `cameraManager.frameStream` indefinitely
    /// until `processingTask` is cancelled by `endSession`.
    private func startProcessingLoop(cameraManager: CameraManager) {
        processingTask = Task { [weak self] in
            guard let self else { return }
            for await buffer in cameraManager.frameStream {
                guard !Task.isCancelled else { break }
                await self.processFrame(buffer)
            }
        }
    }

    /// Processes one `CMSampleBuffer`, runs analytics, and publishes updated state.
    ///
    /// The `await poseEngine.process(buffer)` call suspends on the actor's executor,
    /// returning to `@MainActor` on resumption — no manual `DispatchQueue.main` needed.
    private func processFrame(_ buffer: CMSampleBuffer) async {
        do {
            guard let pose = try await poseEngine.process(buffer) else {
                // No person detected in this frame — carry forward the last known metrics.
                return
            }

            // Capture the very first reliable root Y as the hip sag baseline.
            if hipYBaseline == nil,
               let root = pose[.root], root.isReliable {
                hipYBaseline = Double(root.position.y)
            }

            // Record whether the climber was static before this frame's analysis
            // so we can detect static → moving transitions below.
            let wasStatic = metrics.isStatic

            let updatedMetrics = WallBetaAnalytics.analyze(
                pose: pose,
                previous: previousPose,
                frameRate: 30.0,
                currentMetrics: metrics,
                holdStartTime: holdStartTime,
                hipYBaseline: hipYBaseline
            )

            // ── Hold-timer state machine ──────────────────────────────────────────
            // Transition: static → moving — stop the hold timer.
            if wasStatic && !updatedMetrics.isStatic {
                holdStartTime = nil
            }
            // Transition: moving → static — start a new hold timer.
            if !wasStatic && updatedMetrics.isStatic {
                holdStartTime = Date()
            }

            // ── Dyno path capture ─────────────────────────────────────────────────
            // Accumulate CoM points during a Dyno for the arc overlay, capping the buffer.
            if updatedMetrics.isDynoDetected, updatedMetrics.centerOfMass != .zero {
                if dynoPath.count >= maxDynoPoints {
                    dynoPath.removeFirst()
                }
                dynoPath.append(updatedMetrics.centerOfMass)
            }

            // Publish — all mutations are on @MainActor.
            metrics      = updatedMetrics
            previousPose = pose
            currentPose  = pose

        } catch {
            // Vision errors are surfaced but do not terminate the session.
            // A single corrupted or unprocessable frame should not interrupt live analysis.
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Private — Duration Timer

    /// Fires once per second to keep `sessionDuration` in sync with wall-clock time.
    private func startTimer() {
        timerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, let self else { break }
                if let startDate = self.sessionStartDate {
                    self.sessionDuration = Date().timeIntervalSince(startDate)
                }
            }
        }
    }

    // MARK: - Private — Metrics Snapshot

    /// Converts the final `WallBetaMetrics` snapshot to a `[String: Double]` dictionary
    /// suitable for storage in `SessionResult.metrics`.
    private func snapshotMetricsDict() -> [String: Double] {
        [
            "avg_hip_proximity":    metrics.hipProximityScore,
            "hold_time_seconds":    metrics.holdTimeSeconds,
            "avg_velocity_mph":     metrics.averageVelocityMPH,
            "dyno_detected":        metrics.isDynoDetected ? 1.0 : 0.0,
            "hip_sag_detected":     metrics.isHipSag ? 1.0 : 0.0,
            "center_of_mass_x":     Double(metrics.centerOfMass.x),
            "center_of_mass_y":     Double(metrics.centerOfMass.y),
            "duration_seconds":     sessionDuration,
        ]
    }
}
