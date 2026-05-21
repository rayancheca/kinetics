@preconcurrency import AVFoundation
import FirebaseAnalytics
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

    /// `true` while the session is active but temporarily paused.
    var isPaused: Bool = false

    /// Accumulated duration before the most recent pause, so the timer resumes correctly.
    private var accumulatedDuration: TimeInterval = 0

    /// The result of the most recently completed session; populated after `endSession` saves.
    var lastCompletedSession: SessionResult?

    /// Previous sessions for the same sport, loaded after a session ends.
    /// Passed to `WallBetaSessionReportView` so it can compute personal bests and deltas.
    var previousSessions: [SessionResult] = []

    /// The current real-time coaching cue, derived from live metrics via `CoachingEngine`.
    var currentCoachCue: CoachCue?

    /// Elapsed session time formatted as M:SS for display.
    var formattedDuration: String {
        let total = Int(sessionDuration)
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    /// A real-time coaching cue derived from the current frame metrics.
    var coachingCue: String {
        if metrics.isHipSag { return "Engage your core — prevent your hips from dropping away from the wall" }
        if metrics.hipProximityScore < 40 { return "Push your hips closer to the wall to shift weight onto your feet" }
        if metrics.hipProximityScore < 70 { return "Good proximity — try to keep your hips in and your arms straight" }
        return "Excellent technique — hips close, weight on feet"
    }

    // MARK: - Private — Frame-Level State

    /// Dedicated Vision engine for this module. Re-created on each session start so
    /// temporal smoothing state never leaks across sessions.
    private var poseEngine = PoseDetectionEngine()

    /// Weak reference to the active camera manager — used to read `cameraPosition`
    /// per-frame so pose mirroring stays in sync with the live camera selection.
    private weak var activeCameraManager: CameraManager?

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

    /// Cue cooldown state: maps category key → last fire time.
    private var cueCooldowns: [String: Date] = [:]
    private var lastSpokenCue: String = ""

    // MARK: - Session Lifecycle

    /// Starts the camera and begins real-time pose analysis.
    ///
    /// Safe to call once per session. Calling again while active is a no-op.
    ///
    /// - Parameter cameraManager: The shared `CameraManager` from `AppState`.
    func startProcessing(with cameraManager: CameraManager) async {
        guard !isSessionActive else { return }

        self.activeCameraManager = cameraManager

        // Reset all session-scoped state before starting.
        metrics        = WallBetaMetrics()
        dynoPath       = []
        previousPose   = nil
        hipYBaseline   = nil
        holdStartTime  = Date()   // Assume static until first movement detected.
        errorMessage   = nil
        lastSpokenCue  = ""
        cueCooldowns   = [:]
        currentCoachCue = nil

        // Log the analytics event before the camera rolls so funnel attribution is clean.
        SessionRepository.shared.logSessionStarted(sport: .wallBeta)
        Analytics.logEvent("module_session_started", parameters: [
            "module": "wall",
            "timestamp": Date().timeIntervalSince1970
        ])

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

    /// Fetches the 10 most recent sessions of the same sport for the given user and
    /// stores them in `previousSessions`. Call this right after `endSession` completes,
    /// before presenting `WallBetaSessionReportView`, so the report can show PRs and deltas.
    ///
    /// - Parameter userId: The Firebase Auth UID of the current user.
    func loadPreviousSessions(userId: String) async {
        let all = (try? await SessionRepository.shared.fetchSessions(for: userId, limit: 10)) ?? []
        previousSessions = all.filter { $0.sport == .wallBeta }
    }

    /// Stops the session, cancels all background tasks, and persists the result to Firestore.
    ///
    /// Sessions shorter than 2 seconds are discarded — they represent accidental taps.
    ///
    /// - Parameter userId: The authenticated user's Firebase UID.
    func stopProcessing() {
        processingTask?.cancel()
        timerTask?.cancel()
        processingTask = nil
        timerTask      = nil
        isSessionActive = false
        CoachVoice.shared.stop()
    }

    func endSession(userId: String) async {
        guard isSessionActive else { return }

        processingTask?.cancel()
        timerTask?.cancel()
        processingTask = nil
        timerTask      = nil

        isSessionActive = false
        CoachVoice.shared.stop()

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
        accumulatedDuration = 0
        isPaused = false
        sessionStartDate = nil

        Analytics.logEvent("module_session_completed", parameters: [
            "module": "wall",
            "duration_seconds": finalDuration,
            "timestamp": Date().timeIntervalSince1970
        ])
        do {
            try await SessionRepository.shared.save(result)
            lastCompletedSession = result
        } catch {
            // Non-fatal — the session result may not persist but the app stays stable.
            errorMessage = "Session could not be saved: \(error.localizedDescription)"
        }

        Task {
            await SessionFeedPublisher.publish(
                userId: userId,
                sport: "Wall Beta",
                activityType: "wall",
                itemType: .wallSession,
                durationSeconds: finalDuration,
                metrics: [
                    FeedMetric(label: "HIP PROX",
                               value: "\(Int(metrics.hipProximityScore))",
                               unit: "%"),
                    FeedMetric(label: "HOLD TIME",
                               value: String(format: "%.0fs", metrics.holdTimeSeconds),
                               unit: ""),
                ]
            )
        }
    }

    // MARK: - Pause / Resume

    /// Pauses an active session: cancels the frame loop and timer, preserving elapsed time.
    func pauseSession() {
        guard isSessionActive && !isPaused else { return }
        accumulatedDuration = sessionDuration
        processingTask?.cancel()
        processingTask = nil
        timerTask?.cancel()
        timerTask = nil
        isPaused = true
        CoachVoice.shared.stop()
    }

    /// Resumes a paused session: resets the start timestamp and restarts frame processing.
    func resumeSession(with cameraManager: CameraManager) {
        guard isSessionActive && isPaused else { return }
        isPaused = false
        sessionStartDate = Date()
        startTimer()
        processingTask = Task { [weak self] in
            guard let self else { return }
            for await buffer in cameraManager.frameStream {
                guard !Task.isCancelled else { break }
                await self.processFrame(buffer)
            }
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
            let isFront = activeCameraManager?.cameraPosition == .front
            guard let pose = try await poseEngine.process(buffer, isFrontCamera: isFront) else {
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

            // Build live metrics bag and evaluate for a coaching cue.
            let liveMetrics = LiveCoachingMetrics(
                hipProximityScore: updatedMetrics.hipProximityScore,
                sagDetected: updatedMetrics.isHipSag,
                timeUnderTensionAvg: updatedMetrics.holdTimeSeconds
            )
            if let cue = CoachingEngine.evaluate(
                metrics: liveMetrics,
                sport: .wallBeta,
                cooldowns: &cueCooldowns
            ) {
                currentCoachCue = cue
                CoachVoice.shared.speakIfChanged(cue: cue)
            }

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
                    self.sessionDuration = self.accumulatedDuration + Date().timeIntervalSince(startDate)
                }
            }
        }
    }

    // MARK: - Private — Metrics Snapshot

    /// Converts the final `WallBetaMetrics` snapshot to a `[String: Double]` dictionary
    /// suitable for storage in `SessionResult.metrics`.
    ///
    /// Key names match what `WallBetaSessionReportView` and `CoachingEngine` read.
    /// `hip_proximity_score` is stored as 0–1 (divide the 0–100 live score by 100).
    private func snapshotMetricsDict() -> [String: Double] {
        [
            // Keys read by WallBetaSessionReportView (0–1 fractions where noted)
            "hipProximityScore":        metrics.hipProximityScore,
            "hip_proximity_score":      metrics.hipProximityScore / 100.0,
            "sag_events":               metrics.isHipSag ? 1.0 : 0.0,
            "dyno_arc_smoothness":      metrics.isDynoDetected ? 0.85 : 0.0,
            "time_under_tension_avg":   metrics.holdTimeSeconds,
            // Keys read by CoachingEngine
            "avg_velocity_mph":         metrics.averageVelocityMPH,
            "dyno_detected":            metrics.isDynoDetected ? 1.0 : 0.0,
            "hip_sag_detected":         metrics.isHipSag ? 1.0 : 0.0,
            // Raw values for debugging
            "center_of_mass_x":         Double(metrics.centerOfMass.x),
            "center_of_mass_y":         Double(metrics.centerOfMass.y),
            "duration_seconds":         sessionDuration,
        ]
    }
}
