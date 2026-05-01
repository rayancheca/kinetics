@preconcurrency import AVFoundation
import FirebaseAnalytics
import Foundation
import Observation

// MARK: - GrapplingViewModel

/// Orchestrates the Grappling Lab analysis session.
///
/// Responsibilities:
/// - Starts and stops the shared `CameraManager`.
/// - Feeds each camera frame through `PoseDetectionEngine` on the actor's executor.
/// - Calls `GrapplingAnalytics.analyze` and publishes results back to `@MainActor`.
/// - Drives the session timer and persists the completed result via `SessionRepository`.
///
/// **Threading model:**
/// - This class is `@MainActor` — all `@Observable` property mutations are safe to
///   bind directly in SwiftUI.
/// - The Vision work happens inside `PoseDetectionEngine` (an `actor`), keeping the
///   main thread free for 60 fps rendering.
@Observable
@MainActor
final class GrapplingViewModel {

    // MARK: - Observable State

    /// Latest computed analytics snapshot — updated at the camera frame rate (~30 fps).
    private(set) var metrics = GrapplingMetrics()

    /// Most recently detected body pose. Used by `PoseOverlayView` for skeleton rendering.
    private(set) var currentPose: JointPose?

    /// Elapsed session time in seconds, updated every second while a session is active.
    private(set) var sessionDuration: TimeInterval = 0

    /// `true` while the camera and Vision engine are actively processing frames.
    private(set) var isSessionActive = false

    /// Non-nil when an unrecoverable error occurs (camera denied, Vision failure).
    private(set) var errorMessage: String?

    /// The result of the most recently completed session; populated after `endSession` saves.
    var lastCompletedSession: SessionResult?

    /// The current real-time coaching cue, derived from live metrics via `CoachingEngine`.
    var currentCoachCue: CoachCue?

    /// Elapsed session time formatted as M:SS for display.
    var formattedDuration: String {
        let total = Int(sessionDuration)
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    // MARK: - Private State

    /// Dedicated Vision engine instance for this module. Re-created on each session
    /// start so temporal state never leaks across sessions.
    private var poseEngine = PoseDetectionEngine()

    /// Weak reference to the active `CameraManager`, used to read `cameraPosition`
    /// when mirroring pose coordinates for the front camera.
    private weak var activeCameraManager: CameraManager?

    /// The preceding frame's pose, used to compute inter-frame velocities.
    private var previousPose: JointPose?

    /// Timestamp when the current session began, used to compute `sessionDuration`.
    private var sessionStartDate: Date?

    /// Retains the long-lived frame-processing task so it can be cancelled on session end.
    private var processingTask: Task<Void, Never>?

    /// Retains the repeating timer task that ticks `sessionDuration` every second.
    private var timerTask: Task<Void, Never>?

    /// Cue cooldown state: maps category key → last fire time.
    private var cueCooldowns: [String: Date] = [:]
    /// Tracks the last cue text spoken for CoachVoice deduplication.
    private var lastSpokenCue: String = ""

    // MARK: - Session Lifecycle

    /// Clears the current error message. Called when the user dismisses the error alert.
    func clearError() {
        errorMessage = nil
    }

    /// Starts the camera and begins real-time pose analysis.
    ///
    /// - Parameter cameraManager: The shared `CameraManager` from `AppState`.
    func startProcessing(with cameraManager: CameraManager) async {
        guard !isSessionActive else { return }

        self.activeCameraManager = cameraManager

        // Log analytics event before starting — matches other module patterns.
        SessionRepository.shared.logSessionStarted(sport: .grappling)
        Analytics.logEvent("module_session_started", parameters: [
            "module": "grappling",
            "timestamp": Date().timeIntervalSince1970
        ])

        await cameraManager.startSession()

        guard cameraManager.cameraError == nil else {
            errorMessage = cameraManager.cameraError?.localizedDescription
                ?? "Camera could not be started."
            return
        }

        isSessionActive = true
        sessionStartDate = Date()
        previousPose = nil
        metrics = GrapplingMetrics()
        cueCooldowns = [:]
        currentCoachCue = nil
        lastSpokenCue = ""

        startTimer()
        startProcessingLoop(cameraManager: cameraManager)
    }

    /// Stops the session, cancels all background tasks, and persists the result.
    ///
    /// - Parameter userId: The authenticated user's Firebase UID.
    func stopProcessing() {
        processingTask?.cancel()
        timerTask?.cancel()
        processingTask = nil
        timerTask = nil
        isSessionActive = false
        CoachVoice.shared.stop()
    }

    func endSession(userId: String) async {
        guard isSessionActive else { return }

        processingTask?.cancel()
        timerTask?.cancel()
        processingTask = nil
        timerTask = nil

        isSessionActive = false
        CoachVoice.shared.stop()

        // Capture final duration before clearing the start date.
        let finalDuration = sessionStartDate.map { Date().timeIntervalSince($0) } ?? sessionDuration

        let result = SessionResult(
            sport: .grappling,
            startedAt: sessionStartDate ?? Date(),
            duration: finalDuration,
            metrics: snapshotMetricsDict(),
            userId: userId
        )

        // Reset engine state so stale temporal data doesn't bleed into the next session.
        await poseEngine.reset()
        sessionStartDate = nil

        Analytics.logEvent("module_session_completed", parameters: [
            "module": "grappling",
            "duration_seconds": finalDuration,
            "timestamp": Date().timeIntervalSince1970
        ])
        do {
            try await SessionRepository.shared.save(result)
            lastCompletedSession = result
        } catch {
            // Non-fatal — session data may not persist but the app should remain stable.
            errorMessage = "Session could not be saved: \(error.localizedDescription)"
        }

        Task {
            await SessionFeedPublisher.publish(
                userId: userId,
                displayName: "",
                sport: "Grappling Lab",
                activityType: "grappling",
                itemType: .grapplingSession,
                durationSeconds: finalDuration,
                metrics: [
                    FeedMetric(label: "SPINE",
                               value: String(format: "%.0f°", metrics.spineAngleDegrees),
                               unit: ""),
                    FeedMetric(label: "KUZUSHI",
                               value: "\(Int(metrics.kuzushiIndex))",
                               unit: "/100"),
                ]
            )
        }
    }

    // MARK: - Private: Frame Processing Loop

    /// Consumes the camera frame stream and dispatches pose analysis for each frame.
    private func startProcessingLoop(cameraManager: CameraManager) {
        processingTask = Task { [weak self] in
            guard let self else { return }

            for await buffer in cameraManager.frameStream {
                guard !Task.isCancelled else { break }
                await self.processFrame(buffer)
            }
        }
    }

    /// Processes one `CMSampleBuffer`, runs `GrapplingAnalytics`, and publishes results.
    ///
    /// Pose detection runs inside the `PoseDetectionEngine` actor. The analytics computation
    /// is pure and fast, so it runs synchronously on the calling context after the await.
    private func processFrame(_ buffer: CMSampleBuffer) async {
        do {
            let isFront = activeCameraManager?.cameraPosition == .front
            guard let pose = try await poseEngine.process(buffer, isFrontCamera: isFront) else {
                // No person in frame — keep displaying the last known metrics.
                return
            }

            let updatedMetrics = GrapplingAnalytics.analyze(
                pose: pose,
                previous: previousPose,
                // CameraManager configures a 720p session at ~30 fps.
                frameRate: 30.0
            )

            // All property mutations are on @MainActor — safe without additional dispatch.
            currentPose = pose
            previousPose = pose
            metrics = updatedMetrics

            // Build live metrics bag and evaluate for a coaching cue.
            let liveMetrics = LiveCoachingMetrics(
                isBaseStable: updatedMetrics.isBaseStable,
                spineAngleDegrees: updatedMetrics.spineAngleDegrees,
                kuzushiIndex: updatedMetrics.kuzushiIndex,
                centerOfMassInBase: !updatedMetrics.isPosturalAlert
            )
            if let cue = CoachingEngine.evaluate(
                metrics: liveMetrics,
                sport: .grappling,
                cooldowns: &cueCooldowns
            ) {
                currentCoachCue = cue
                CoachVoice.shared.speakIfChanged(cue: cue)
            }

        } catch {
            // Vision errors are logged but do not terminate the session — a single
            // corrupted frame should not interrupt a live analysis.
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Private: Timer

    /// Starts a 1-second repeating task that ticks `sessionDuration`.
    private func startTimer() {
        timerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { break }
                guard let self else { break }
                if let startDate = self.sessionStartDate {
                    self.sessionDuration = Date().timeIntervalSince(startDate)
                }
            }
        }
    }

    // MARK: - Private: Metrics Snapshot

    /// Converts the final `GrapplingMetrics` to a `[String: Double]` dictionary
    /// for storage in `SessionResult.metrics`.
    ///
    /// Key names match what `GrapplingSessionReportView` and `CoachingEngine` read.
    private func snapshotMetricsDict() -> [String: Double] {
        [
            // Report-view keys (must match GrapplingSessionReportView derived properties)
            "kuzushi_index":     metrics.kuzushiIndex,
            "base_stability":    metrics.isBaseStable ? 1.0 : 0.0,
            "postural_breaks":   metrics.isPosturalAlert ? 1.0 : 0.0,
            "com_control":       metrics.isBaseStable ? 1.0 : 0.0,
            // Additional detail keys
            "spine_angle_deg":   metrics.spineAngleDegrees,
            "hip_elevation":     metrics.hipElevation,
            "is_ground_position": metrics.isGroundPosition ? 1.0 : 0.0,
            "center_of_mass_x":  Double(metrics.centerOfMass.x),
            "center_of_mass_y":  Double(metrics.centerOfMass.y),
            "duration_seconds":  sessionDuration
        ]
    }
}
