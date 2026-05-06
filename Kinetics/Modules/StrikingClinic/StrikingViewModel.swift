@preconcurrency import AVFoundation
import FirebaseAnalytics
import Foundation
import Observation
import Vision

// MARK: - StrikingViewModel

/// Owns all state for the Striking Clinic session screen.
///
/// Threading model:
/// - `@Observable @MainActor` keeps all UI-facing properties on the main thread.
/// - Frame processing is dispatched to `PoseDetectionEngine` (an actor) via `await`,
///   so Vision work never blocks the main thread.
/// - The duration timer runs as a structured `Task` that mutates `sessionDuration`
///   back on `@MainActor` through the enclosing isolation.
@Observable
@MainActor
final class StrikingViewModel {

    // MARK: - Public State

    /// Current-frame biomechanics metrics, updated at ~30 fps while a session is active.
    var metrics = StrikingMetrics()
    /// The most recently detected body pose; `nil` before the first successful frame.
    var currentPose: JointPose?
    /// Elapsed session time in seconds, updated once per second.
    var sessionDuration: TimeInterval = 0
    /// True from `startProcessing` through `endSession`.
    var isSessionActive: Bool = false
    /// Non-nil when a Vision or camera error has occurred.
    var errorMessage: String?
    /// True when the session is temporarily paused (tasks cancelled, timer stopped).
    var isPaused: Bool = false
    private var accumulatedDuration: TimeInterval = 0

    /// The result of the most recently completed session; populated after `endSession` saves.
    var lastCompletedSession: SessionResult?

    /// Previous sessions for the same sport, loaded after a session ends.
    /// Passed to `StrikingSessionReportView` so it can compute personal bests and deltas.
    var previousSessions: [SessionResult] = []

    /// The current real-time coaching cue, derived from live metrics via `CoachingEngine`.
    /// `nil` when no condition is triggered or no session is active.
    var currentCoachCue: CoachCue?

    /// Elapsed session time formatted as M:SS for display.
    var formattedDuration: String {
        let total = Int(sessionDuration)
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    // MARK: - Private

    private let poseEngine = PoseDetectionEngine()
    private weak var activeCameraManager: CameraManager?
    private var previousPose: JointPose?
    private var sessionStartTime: Date?
    private var durationTask: Task<Void, Never>?
    private var processingTask: Task<Void, Never>?
    /// Cue cooldown state: maps category key → last fire time. Prevents flooding at 30 fps.
    private var cueCooldowns: [String: Date] = [:]
    /// Tracks the last cue spoken so CoachVoice deduplication works across frames.
    private var lastSpokenCue: String = ""

    // MARK: - Session Lifecycle

    /// Starts camera capture and begins processing frames into `metrics`.
    ///
    /// Safe to call once per session. Calling again while a session is active is a no-op.
    /// Awaits `cameraManager.startSession()` directly so the `.task { }` view modifier
    /// can drive this as a proper async function — consistent with `GrapplingViewModel`
    /// and `WallBetaViewModel`.
    ///
    /// - Parameter cameraManager: The shared camera manager from `AppState`.
    func startProcessing(with cameraManager: CameraManager) async {
        guard !isSessionActive else { return }
        self.activeCameraManager = cameraManager

        SessionRepository.shared.logSessionStarted(sport: .striking)
        Analytics.logEvent("module_session_started", parameters: [
            "module": "striking",
            "timestamp": Date().timeIntervalSince1970
        ])

        await cameraManager.startSession()

        guard cameraManager.cameraError == nil else {
            errorMessage = cameraManager.cameraError?.localizedDescription
                ?? "Camera could not be started."
            return
        }

        isSessionActive = true
        sessionStartTime = Date()
        metrics = StrikingMetrics()
        previousPose = nil
        errorMessage = nil
        lastSpokenCue = ""
        cueCooldowns = [:]
        currentCoachCue = nil

        startDurationTimer()

        processingTask = Task { [weak self] in
            guard let self else { return }
            for await buffer in cameraManager.frameStream {
                guard !Task.isCancelled else { break }
                await self.processFrame(buffer)
            }
        }
    }

    /// Stops processing, persists the session to Firestore, and resets active state.
    ///
    /// Sessions shorter than 2 seconds are discarded — they are almost certainly
    /// accidental taps rather than real training sessions.
    ///
    /// - Parameter userId: The Firebase Auth UID of the current user.
    func endSession(userId: String) async {
        guard isSessionActive else { return }

        isSessionActive = false
        accumulatedDuration = 0
        isPaused = false
        processingTask?.cancel()
        processingTask = nil
        durationTask?.cancel()
        durationTask = nil
        CoachVoice.shared.stop()

        await poseEngine.reset()

        guard sessionDuration > 2 else { return }

        let result = SessionResult(
            sport: .striking,
            startedAt: sessionStartTime ?? Date(),
            duration: sessionDuration,
            metrics: [
                "peak_velocity_mph":  metrics.peakVelocityMPH,
                "strike_count":       Double(metrics.strikeCount),
                "kinematic_score":    metrics.kinematicScore,
                "hip_shoulder_sep":   metrics.hipShoulderSeparation,
            ],
            userId: userId
        )

        Analytics.logEvent("module_session_completed", parameters: [
            "module": "striking",
            "duration_seconds": sessionDuration,
            "timestamp": Date().timeIntervalSince1970
        ])
        try? await SessionRepository.shared.save(result)
        lastCompletedSession = result

        Task {
            await SessionFeedPublisher.publish(
                userId: userId,
                displayName: "",
                sport: "Striking Clinic",
                activityType: "striking",
                itemType: .strikeSession,
                durationSeconds: sessionDuration,
                metrics: [
                    FeedMetric(label: "VELOCITY",
                               value: String(format: "%.1f", metrics.peakVelocityMPH),
                               unit: "mph"),
                    FeedMetric(label: "STRIKES",
                               value: "\(metrics.strikeCount)",
                               unit: ""),
                    FeedMetric(label: "CHAIN",
                               value: "\(Int(metrics.kinematicScore))",
                               unit: "/100"),
                ]
            )
        }
    }

    /// Fetches the 10 most recent sessions of the same sport for the given user and
    /// stores them in `previousSessions`. Call this right after `endSession` completes,
    /// before presenting `StrikingSessionReportView`, so the report can show PRs and deltas.
    ///
    /// - Parameter userId: The Firebase Auth UID of the current user.
    func loadPreviousSessions(userId: String) async {
        let all = (try? await SessionRepository.shared.fetchSessions(for: userId, limit: 10)) ?? []
        previousSessions = all.filter { $0.sport == .striking }
    }

    /// Pauses an active session: cancels processing and timer tasks without saving.
    func pauseSession() {
        guard isSessionActive && !isPaused else { return }
        accumulatedDuration = sessionDuration
        processingTask?.cancel()
        processingTask = nil
        durationTask?.cancel()
        durationTask = nil
        isPaused = true
        CoachVoice.shared.stop()
    }

    /// Resumes a paused session: restarts the timer and frame-processing pipeline.
    func resumeSession(with cameraManager: CameraManager) {
        guard isSessionActive && isPaused else { return }
        isPaused = false
        sessionStartTime = Date()
        startDurationTimer()
        processingTask = Task { [weak self] in
            guard let self else { return }
            for await buffer in cameraManager.frameStream {
                guard !Task.isCancelled else { break }
                await self.processFrame(buffer)
            }
        }
    }

    /// Cancels the active processing and duration tasks and clears session state
    /// without saving to Firestore. Call this when navigating back mid-session.
    func stopProcessing() {
        processingTask?.cancel()
        durationTask?.cancel()
        processingTask = nil
        durationTask = nil
        isSessionActive = false
        CoachVoice.shared.stop()
    }

    // MARK: - Private Frame Processing

    /// Runs on `@MainActor` — the `await poseEngine.process` hop suspends and
    /// executes on the actor's executor, returning cleanly back to main on resumption.
    private func processFrame(_ buffer: CMSampleBuffer) async {
        do {
            let isFront = activeCameraManager?.cameraPosition == .front
            guard let pose = try await poseEngine.process(buffer, isFrontCamera: isFront) else { return }

            metrics = StrikingAnalytics.analyze(
                pose: pose,
                previous: previousPose,
                frameRate: 30,
                currentMetrics: metrics
            )
            previousPose = pose
            currentPose = pose

            // Build live metrics bag and ask CoachingEngine for the best cue this frame.
            let liveMetrics = LiveCoachingMetrics(
                hipShoulderSeparation: metrics.hipShoulderSeparation,
                strikeVelocityMPH: metrics.strikeVelocityMPH,
                stanceRecoveryTime: metrics.recoveryTimeSeconds,
                isSessionActive: isSessionActive
            )
            if let cue = CoachingEngine.evaluate(
                metrics: liveMetrics,
                sport: .striking,
                cooldowns: &cueCooldowns
            ) {
                currentCoachCue = cue
                CoachVoice.shared.speakIfChanged(cue: cue)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Private Timer

    /// Fires once per second to keep `sessionDuration` in sync with wall-clock time.
    /// Uses structured concurrency so cancellation is automatic when `endSession` runs.
    private func startDurationTimer() {
        durationTask?.cancel()
        durationTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, !Task.isCancelled else { return }
                guard let start = self.sessionStartTime else { return }
                self.sessionDuration = self.accumulatedDuration + Date().timeIntervalSince(start)
            }
        }
    }
}
