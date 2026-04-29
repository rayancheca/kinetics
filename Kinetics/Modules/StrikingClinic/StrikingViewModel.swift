import AVFoundation
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

    // MARK: - Private

    private let poseEngine = PoseDetectionEngine()
    private var previousPose: JointPose?
    private var sessionStartTime: Date?
    private var durationTask: Task<Void, Never>?
    private var processingTask: Task<Void, Never>?

    // MARK: - Session Lifecycle

    /// Starts camera capture and begins processing frames into `metrics`.
    ///
    /// Safe to call once per session. Calling again while a session is active is a no-op.
    /// The camera feed runs until `endSession` is called or the view disappears.
    ///
    /// - Parameter cameraManager: The shared camera manager from `AppState`.
    func startProcessing(with cameraManager: CameraManager) {
        guard !isSessionActive else { return }

        isSessionActive = true
        sessionStartTime = Date()
        metrics = StrikingMetrics()
        previousPose = nil
        errorMessage = nil

        SessionRepository.shared.logSessionStarted(sport: .striking)
        startDurationTimer()

        processingTask = Task { [weak self] in
            guard let self else { return }
            await cameraManager.startSession()
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
        processingTask?.cancel()
        processingTask = nil
        durationTask?.cancel()
        durationTask = nil

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

        try? await SessionRepository.shared.save(result)
    }

    // MARK: - Private Frame Processing

    /// Runs on `@MainActor` — the `await poseEngine.process` hop suspends and
    /// executes on the actor's executor, returning cleanly back to main on resumption.
    private func processFrame(_ buffer: CMSampleBuffer) async {
        do {
            guard let pose = try await poseEngine.process(buffer) else { return }

            metrics = StrikingAnalytics.analyze(
                pose: pose,
                previous: previousPose,
                frameRate: 30,
                currentMetrics: metrics
            )
            previousPose = pose
            currentPose = pose
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
                self.sessionDuration = Date().timeIntervalSince(start)
            }
        }
    }
}
