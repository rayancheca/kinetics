@preconcurrency import AVFoundation
import Foundation
import Observation
import Vision

// MARK: - IronTrackerViewModel

/// Owns all state for the Iron Tracker session screen.
///
/// Threading model:
/// - `@Observable @MainActor` keeps all UI-facing properties on the main thread.
/// - Frame processing is dispatched to `PoseDetectionEngine` (an actor) via `await`,
///   so Vision work never blocks the main thread.
/// - The duration timer runs as a structured `Task` that mutates `sessionDuration`
///   back on `@MainActor` through the enclosing isolation.
/// - `barPath` is maintained here rather than in `IronTrackerAnalytics` because
///   it represents session-level history state, not per-frame computed output.
@Observable
@MainActor
final class IronTrackerViewModel {

    // MARK: - Public State

    /// Current-frame biomechanics metrics, updated at ~30 fps while a session is active.
    var metrics = IronTrackerMetrics()

    /// The most recently detected body pose; `nil` before the first successful frame.
    var currentPose: JointPose?

    /// Bar midpoint history in Vision normalized coordinates (origin: bottom-left).
    ///
    /// Capped at `maxBarPathPoints` (90 frames = 3 seconds at 30 fps) by discarding
    /// the oldest point when the cap is exceeded. Used by the View's `Canvas` to draw
    /// a glowing bar path trace over the camera feed.
    var barPath: [CGPoint] = []

    /// Elapsed session time in seconds, updated once per second.
    var sessionDuration: TimeInterval = 0

    /// True from `startProcessing` through `endSession`.
    var isSessionActive: Bool = false

    /// Non-nil when a Vision or camera error has occurred.
    var errorMessage: String?

    /// The result of the most recently completed session; populated after `endSession` saves.
    var lastCompletedSession: SessionResult?

    /// Elapsed session time formatted as M:SS for display.
    var formattedDuration: String {
        let total = Int(sessionDuration)
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    /// A real-time coaching cue derived from the current frame metrics.
    var coachingCue: String {
        if metrics.isButtWink { return "Brace your core — prevent lumbar flexion at the bottom" }
        if metrics.isKneeCave { return "Drive your knees out — align them over your toes" }
        if metrics.isSymmetryAlert { return "Rebalance — one side is leading the lift" }
        return "Good form — focus on bar speed"
    }

    /// Set from the View's `GeometryReader` on every layout pass.
    ///
    /// Passed to `IronTrackerAnalytics.analyze` so `calculateSpeedMS` can convert
    /// normalized joint displacements to pixel distances before applying the m/s calibration.
    var viewSize: CGSize = .zero

    // MARK: - Private

    private let poseEngine = PoseDetectionEngine()
    private var previousPose: JointPose?
    private var sessionStartTime: Date?
    private var durationTask: Task<Void, Never>?
    private var processingTask: Task<Void, Never>?

    private let maxBarPathPoints = 90

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

        SessionRepository.shared.logSessionStarted(sport: .ironTracker)

        await cameraManager.startSession()

        guard cameraManager.cameraError == nil else {
            errorMessage = cameraManager.cameraError?.localizedDescription
                ?? "Camera could not be started."
            return
        }

        isSessionActive = true
        sessionStartTime = Date()
        metrics = IronTrackerMetrics()
        barPath = []
        previousPose = nil
        errorMessage = nil

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
    /// Sessions shorter than 2 seconds are discarded — almost certainly accidental taps.
    ///
    /// - Parameter userId: The Firebase Auth UID of the current user.
    func endSession(userId: String) async {
        guard isSessionActive else { return }

        isSessionActive = false
        processingTask?.cancel()
        processingTask = nil
        durationTask?.cancel()
        durationTask = nil

        await poseEngine.reset()

        guard sessionDuration > 2 else { return }

        let result = SessionResult(
            sport: .ironTracker,
            startedAt: sessionStartTime ?? Date(),
            duration: sessionDuration,
            metrics: [
                "peak_bar_velocity_ms":     metrics.peakBarVelocityMS,
                "bilateral_symmetry_pct":   metrics.bilateralSymmetry,
                "butt_wink_detected":       metrics.isButtWink ? 1.0 : 0.0,
                "knee_cave_detected":       metrics.isKneeCave ? 1.0 : 0.0,
            ],
            userId: userId
        )

        try? await SessionRepository.shared.save(result)
        lastCompletedSession = result
    }

    /// Cancels the active processing and duration tasks and clears session state
    /// without saving to Firestore. Call this when navigating back mid-session.
    func stopProcessing() {
        processingTask?.cancel()
        durationTask?.cancel()
        processingTask = nil
        durationTask = nil
        isSessionActive = false
    }

    // MARK: - Private: Frame Processing

    /// Runs on `@MainActor`. The `await poseEngine.process` hop suspends execution
    /// on the actor's executor (off main thread), then resumes back on main.
    private func processFrame(_ buffer: CMSampleBuffer) async {
        do {
            guard let pose = try await poseEngine.process(buffer) else { return }

            metrics = IronTrackerAnalytics.analyze(
                pose: pose,
                previous: previousPose,
                frameRate: 30,
                currentMetrics: metrics,
                viewSize: viewSize
            )

            appendBarPoint(metrics.barMidpoint)

            previousPose = pose
            currentPose = pose
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Appends `point` to `barPath`, discarding the oldest entry when the history cap is reached.
    ///
    /// Guards against appending `.zero` — the analytics layer returns `.zero` for the bar
    /// midpoint when both wrists are below the confidence threshold.
    private func appendBarPoint(_ point: CGPoint) {
        guard point != .zero else { return }
        barPath.append(point)
        if barPath.count > maxBarPathPoints {
            barPath.removeFirst()
        }
    }

    // MARK: - Private: Timer

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
