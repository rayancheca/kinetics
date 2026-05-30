@preconcurrency import AVFoundation
import ActivityKit
import FirebaseAnalytics
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

    /// Previous sessions for the same sport, loaded after a session ends.
    /// Passed to `IronTrackerSessionReportView` so it can compute personal bests and deltas.
    var previousSessions: [SessionResult] = []

    /// Automatically-counted rep total, incremented by `RepCounter` each time a full
    /// wrist oscillation cycle is detected.
    var autoRepCount: Int = 0

    /// Active injury-risk flags from the most recently processed frame.
    ///
    /// Empty when no dangerous conditions are detected. The view reads this to render
    /// the top-of-overlay warning banner and to drive CoachVoice danger cues.
    var activeRiskFlags: [InjuryRiskDetector.RiskFlag] = []

    /// The current real-time coaching cue, derived from live metrics via `CoachingEngine`.
    var currentCoachCue: CoachCue?

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
    private weak var activeCameraManager: CameraManager?
    private var previousPose: JointPose?
    private var sessionStartTime: Date?
    private var durationTask: Task<Void, Never>?
    private var processingTask: Task<Void, Never>?
    /// Cue cooldown state: maps category key → last fire time.
    private var cueCooldowns: [String: Date] = [:]
    private var lastSpokenCue: String = ""

    private var repCounter = RepCounter()
    private let injuryDetector = InjuryRiskDetector()

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

        self.activeCameraManager = cameraManager

        SessionRepository.shared.logSessionStarted(sport: .ironTracker)
        Analytics.logEvent("module_session_started", parameters: [
            "module": "iron",
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
        if #available(iOS 16.2, *) {
            LiveSessionController.shared.start(
                sportRaw: SportType.ironTracker.rawValue,
                displayName: SportType.ironTracker.displayName,
                accentHex: SportType.ironTracker.accentColor,
                iconName: SportType.ironTracker.systemImage,
                initialState: .init(
                    primaryMetric: "0.00",
                    primaryLabel: "M/S",
                    secondaryMetric: "0",
                    secondaryLabel: "REPS",
                    coachCue: nil,
                    isPaused: false
                )
            )
        }
        metrics = IronTrackerMetrics()
        barPath = []
        previousPose = nil
        errorMessage = nil
        lastSpokenCue = ""
        cueCooldowns = [:]
        currentCoachCue = nil
        autoRepCount = 0
        activeRiskFlags = []
        repCounter.reset()

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
        CoachVoice.shared.stop()

        await poseEngine.reset()

        guard sessionDuration > 2 else { return }

        // Compute a bar path deviation proxy: average perpendicular spread of the
        // accumulated bar path from an ideal vertical line, scaled to centimetres.
        // We use the horizontal range of the bar path (max X – min X) as a simple
        // stand-in for deviation since exact path history is not stored here.
        let barDeviationCM: Double = {
            guard !barPath.isEmpty else { return 0 }
            let xs = barPath.map { Double($0.x) }
            let spread = (xs.max() ?? 0) - (xs.min() ?? 0)
            // 1 normalized unit ≈ 50 cm at typical filming distance; convert to cm.
            return spread * 50.0
        }()

        let result = SessionResult(
            sport: .ironTracker,
            startedAt: sessionStartTime ?? Date(),
            duration: sessionDuration,
            metrics: [
                // Keys read by IronTrackerSessionReportView
                "barVelocityMS":          metrics.peakBarVelocityMS,
                "bar_path_deviation_cm":  barDeviationCM,
                "vbt_velocity_ms":        metrics.peakBarVelocityMS,
                "bilateral_symmetry":     max(0.0, 1.0 - abs(metrics.bilateralSymmetry) / 100.0),
                "butt_wink_angle":        metrics.isButtWink ? (180.0 - metrics.leftHipAngle) : 0.0,
                // Keys read by CoachingEngine
                "peak_bar_velocity_ms":   metrics.peakBarVelocityMS,
                "bilateral_symmetry_pct": metrics.bilateralSymmetry,
                "butt_wink_detected":     metrics.isButtWink ? 1.0 : 0.0,
                "knee_cave_detected":     metrics.isKneeCave ? 1.0 : 0.0,
                "auto_rep_count":         Double(autoRepCount),
            ],
            userId: userId
        )

        Analytics.logEvent("module_session_completed", parameters: [
            "module": "iron",
            "duration_seconds": sessionDuration,
            "timestamp": Date().timeIntervalSince1970
        ])
        try? await SessionRepository.shared.save(result)
        lastCompletedSession = result

        if #available(iOS 16.2, *) {
            LiveSessionController.shared.end(finalState: .init(
                primaryMetric: "\(autoRepCount)",
                primaryLabel: "REPS",
                secondaryMetric: "DONE",
                secondaryLabel: "",
                coachCue: nil,
                isPaused: false
            ), dismissalPolicy: .default)
        }

        Task {
            await SessionFeedPublisher.publish(
                userId: userId,
                sport: "Iron Tracker",
                activityType: "iron",
                itemType: .gymSession,
                durationSeconds: sessionDuration,
                metrics: [
                    FeedMetric(label: "BAR VEL",
                               value: String(format: "%.2f", metrics.peakBarVelocityMS),
                               unit: "m/s"),
                    FeedMetric(label: "SYMMETRY",
                               value: "\(Int(metrics.bilateralSymmetry))",
                               unit: "%"),
                ]
            )
        }
    }

    /// Fetches the 10 most recent sessions of the same sport for the given user and
    /// stores them in `previousSessions`. Call this right after `endSession` completes,
    /// before presenting `IronTrackerSessionReportView`, so the report can show PRs and deltas.
    ///
    /// - Parameter userId: The Firebase Auth UID of the current user.
    func loadPreviousSessions(userId: String) async {
        let all = (try? await SessionRepository.shared.fetchSessions(for: userId, limit: 10)) ?? []
        previousSessions = all.filter { $0.sport == .ironTracker }
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

    // MARK: - Private: Frame Processing

    /// Runs on `@MainActor`. The `await poseEngine.process` hop suspends execution
    /// on the actor's executor (off main thread), then resumes back on main.
    private func processFrame(_ buffer: CMSampleBuffer) async {
        do {
            let isFront = activeCameraManager?.cameraPosition == .front
            guard let pose = try await poseEngine.process(buffer, isFrontCamera: isFront) else { return }

            metrics = IronTrackerAnalytics.analyze(
                pose: pose,
                previous: previousPose,
                frameRate: 30,
                currentMetrics: metrics,
                viewSize: viewSize
            )

            appendBarPoint(metrics.barMidpoint)

            // Rep counting — track right wrist Y oscillation.
            if let rightWrist = pose[.rightWrist], rightWrist.isReliable {
                autoRepCount = repCounter.update(wristY: Double(rightWrist.position.y))
            }

            // Injury risk detection — build joint map from reliable joints only.
            let jointNames: [VNHumanBodyPoseObservation.JointName] = [
                .leftKnee, .leftAnkle, .rightKnee, .rightAnkle,
                .nose, .leftShoulder, .rightShoulder,
                .leftElbow, .leftWrist,
                .root,
            ]
            let jointMap = jointNames.reduce(
                into: [VNHumanBodyPoseObservation.JointName: CGPoint]()
            ) { dict, name in
                if let joint = pose[name], joint.isReliable {
                    dict[name] = joint.position
                }
            }
            activeRiskFlags = injuryDetector.evaluate(joints: jointMap)

            // Speak danger-level flags immediately — athlete needs to stop or correct now.
            for flag in activeRiskFlags where flag.severity == .danger {
                CoachVoice.shared.speak(flag.message, priority: .high)
            }

            previousPose = pose
            currentPose = pose

            // Build live metrics bag and evaluate for a coaching cue.
            let liveMetrics = LiveCoachingMetrics(
                vbtVelocityMs: Double(metrics.barVelocityMS),
                bilateralSymmetry: max(0.0, 1.0 - abs(metrics.bilateralSymmetry) / 100.0),
                buttWinkDetected: metrics.isButtWink,
                autoRepCount: autoRepCount
            )
            if let cue = CoachingEngine.evaluate(
                metrics: liveMetrics,
                sport: .ironTracker,
                cooldowns: &cueCooldowns
            ) {
                currentCoachCue = cue
                CoachVoice.shared.speakIfChanged(cue: cue)
            }

            if #available(iOS 16.2, *) {
                LiveSessionController.shared.update(.init(
                    primaryMetric: String(format: "%.2f", metrics.barVelocityMS),
                    primaryLabel: "M/S",
                    secondaryMetric: "\(autoRepCount)",
                    secondaryLabel: "REPS",
                    coachCue: currentCoachCue?.text,
                    isPaused: false
                ))
            }
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
