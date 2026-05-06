import CoreLocation
import Foundation
import Observation

// MARK: - TrackViewModel

/// Owns all mutable state for the Track (GPS workout) session screen.
///
/// Threading model:
/// - `@Observable @MainActor` keeps every UI-facing property on the main thread.
/// - `LocationService` is an `actor`; all calls hop to its executor via `await`
///   and return results back to `@MainActor` through the enclosing isolation.
/// - `HealthKitService` is also an `actor`; heart-rate stream consumption
///   follows the same pattern.
/// - The duration timer runs as a structured `Task` that increments `elapsedTime`
///   once per second, safely on the main actor.
/// - Auto-pause logic tracks consecutive low-speed location samples without
///   interrupting the timer — the clock always runs, only distance accumulation
///   pauses during detected stillness.
@Observable
@MainActor
final class TrackViewModel {

    // MARK: - Session State

    private(set) var isTracking = false
    private(set) var isPaused = false

    /// Total elapsed wall-clock time in seconds. Always increments while a session is active,
    /// even during auto-paused (low-speed) intervals.
    var elapsedTime: TimeInterval = 0

    /// Total distance accumulated in metres. Does not increment during auto-pause.
    var distance: Double = 0

    /// Current pace as a formatted M:SS /km string. "--:--" before valid GPS data.
    var currentPace: String = "--:--"

    /// Session-average pace as a formatted M:SS /km string. "--:--" before valid GPS data.
    var avgPace: String = "--:--"

    /// Most recent heart rate sample in bpm. Zero when no HR data has been received.
    var currentHeartRate: Double = 0

    /// Running mean of all heart-rate samples this session. Zero until the first sample arrives.
    var avgHeartRate: Double = 0

    /// Most recent GPS speed in metres per second.
    var currentSpeed: Double = 0

    /// Cumulative positive elevation gain in metres.
    var elevationGain: Double = 0

    /// Per-kilometre split records, appended in real time as each split completes.
    var splits: [WorkoutSplit] = []

    /// Ordered route waypoints exposed for `RouteMapView`. Updated alongside `splits`
    /// whenever a new GPS fix arrives.
    var routeCoordinates: [CLLocationCoordinate2D] = []

    /// Maximum speed recorded this session, in metres per second.
    var maxSpeed: Double = 0

    /// Heart rate zone (1–5) derived from the most recent HR sample.
    /// Zero until the first HR sample arrives.
    var currentHeartRateZone: Int = 0

    /// Assumed maximum heart rate used for zone calculations.
    /// Defaults to 190 bpm when no HealthKit age data is available.
    var assumedMaxHR: Double = 190

    /// Auto-coaching message shown in the live overlay pill. Set by pace milestone
    /// triggers and auto-dismissed after 4 seconds.
    var currentCoachMessage: String?

    /// Target pace in seconds per km. Derived from `targetDistance` and `targetDuration`
    /// when both are set; `nil` otherwise.
    var targetPaceSecondsPerKm: Double? {
        guard let dist = targetDistance, let dur = targetDuration,
              dist > 0, dur > 0 else { return nil }
        let km = dist
        return dur / km
    }

    /// Target distance in kilometres. Bound to the goal selector in the pre-session UI.
    var targetDistance: Double?

    /// Target duration in seconds. Bound to the goal duration picker in the pre-session UI.
    var targetDuration: TimeInterval?

    /// Per-km pace values collected as each split completes. Parallel to `splits`.
    var splitPaces: [Double] = []

    // MARK: - Today Stats

    /// Number of workouts completed today.
    var todayWorkoutCount: Int = 0

    /// Total distance covered today, in kilometres.
    var todayDistanceKm: Double = 0

    /// Total workout duration today, in seconds.
    var todayDurationSeconds: TimeInterval = 0

    /// Human-readable today distance, e.g. `"8.3 km"` or `"840m"`.
    var formattedTodayDistance: String {
        todayDistanceKm < 1.0
            ? String(format: "%.0fm", todayDistanceKm * 1000)
            : String(format: "%.1f km", todayDistanceKm)
    }

    /// Human-readable today total duration, e.g. `"42:17"` or `"1:02:05"`.
    var formattedTodayDuration: String {
        let total = Int(todayDurationSeconds)
        let h = total / 3_600
        let m = (total % 3_600) / 60
        let s = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }

    // MARK: - Permission State

    /// `true` when the user has explicitly denied location access. Used to surface
    /// a "Go to Settings" prompt in the pre-session UI instead of silently doing nothing.
    private(set) var locationPermissionDenied = false

    // MARK: - Selection

    /// The activity the athlete is about to start. Bound to the horizontal selector in the pre-session UI.
    var selectedActivityType: WorkoutActivityType = .run

    // MARK: - Completed Session

    /// Populated after `endWorkout` builds and persists the final `WorkoutResult`.
    var lastCompletedWorkout: WorkoutResult?

    /// Drives the presentation of the post-session summary sheet.
    var showSummary = false

    // MARK: - Formatted Properties

    /// Human-readable elapsed time. Shows H:MM:SS when the workout exceeds one hour.
    var formattedElapsedTime: String {
        let total = Int(elapsedTime)
        let h = total / 3_600
        let m = (total % 3_600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }

    /// Human-readable distance string, e.g. `"5.24 km"` or `"840 m"`.
    var formattedDistance: String {
        distance >= 1_000
            ? String(format: "%.2f km", distance / 1_000.0)
            : String(format: "%.0f m", distance)
    }

    /// Human-readable cumulative elevation gain, e.g. `"+84m"`.
    var formattedElevation: String {
        String(format: "+%.0fm", elevationGain)
    }

    /// Current speed formatted as km/h, e.g. `"12.4 km/h"`. Shows `"0.0 km/h"` at rest.
    var formattedCurrentSpeed: String {
        let kmh = currentSpeed * 3.6
        return String(format: "%.1f km/h", kmh)
    }

    /// Maximum speed this session formatted as km/h, e.g. `"15.2 km/h"`.
    var formattedMaxSpeed: String {
        let kmh = maxSpeed * 3.6
        return String(format: "%.1f km/h", kmh)
    }

    /// Average speed this session formatted as km/h. Returns `"0.0 km/h"` before
    /// any distance has been accumulated.
    var formattedAvgSpeed: String {
        guard elapsedTime > 0 else { return "0.0 km/h" }
        let kmh = (distance / elapsedTime) * 3.6
        return String(format: "%.1f km/h", kmh)
    }

    // MARK: - Services

    private let locationService = LocationService()
    private let healthKit = HealthKitService.shared

    // MARK: - Internal Bookkeeping

    private var hrSamples: [(timestamp: Date, bpm: Double)] = []
    private var startTime: Date?

    /// Structured tasks — cancelled as a group on `endWorkout` / `discardWorkout`.
    private var durationTask: Task<Void, Never>?
    private var locationTask: Task<Void, Never>?
    private var hrTask: Task<Void, Never>?
    private var coachMessageTask: Task<Void, Never>?

    /// Tracks the number of completed km splits to trigger split-milestone cue once per km.
    private var lastSplitCountForCue: Int = 0
    /// Tracks the last time a 5-minute interval cue was fired.
    private var lastMinuteCueTime: TimeInterval = 0

    /// Counts consecutive location samples where speed < 0.5 m/s.
    /// When this reaches `autoPauseThreshold` the location consumer stops accumulating distance.
    private var lowSpeedConsecutiveCount: Int = 0
    private let autoPauseThreshold: Int = 3

    /// `true` while `lowSpeedConsecutiveCount >= autoPauseThreshold`.
    private var isAutoPaused: Bool = false

    // MARK: - Public API

    // MARK: Permissions

    /// Requests location and HealthKit authorisation from the user.
    ///
    /// Call this from a `.task {}` modifier on the pre-session picker screen so the
    /// permission prompts appear before the athlete taps Start — not mid-workout.
    func requestPermissions() async {
        let granted = await locationService.requestAuthorization()
        locationPermissionDenied = !granted
        try? await healthKit.requestAuthorization()
    }

    // MARK: Today Stats

    /// Loads today's aggregate workout stats (count, distance, duration) from Firestore
    /// and updates the three `today*` properties.
    ///
    /// Uses `Calendar.startOfDay` to bucket workouts by the device's local calendar day.
    /// Silently no-ops when `WorkoutRepository.fetchAll` throws or returns an empty array
    /// (e.g. Firebase not configured in development builds).
    ///
    /// - Parameter userId: Firebase Auth UID of the current user.
    func loadTodayStats(userId: String) async {
        guard let workouts = try? await WorkoutRepository.shared.fetchAll(userId: userId) else { return }
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let todayWorkouts = workouts.filter { cal.startOfDay(for: $0.startedAt) == today }
        todayWorkoutCount = todayWorkouts.count
        todayDistanceKm = todayWorkouts.reduce(0) { $0 + $1.distance / 1_000 }
        todayDurationSeconds = todayWorkouts.reduce(0) { $0 + $1.duration }
    }

    // MARK: Start

    /// Starts a new GPS workout for `selectedActivityType`.
    ///
    /// Resets all session state, begins location tracking, starts HealthKit HR monitoring,
    /// and launches three structured child tasks:
    /// 1. Duration timer — increments `elapsedTime` every second.
    /// 2. Location consumer — reads from `locationService.locationStream`.
    /// 3. HR consumer — reads from `healthKit.heartRateStream`.
    func startWorkout() async {
        guard !isTracking else { return }

        // Reset all session state to a clean baseline.
        resetSessionState()

        let authorised = await locationService.requestAuthorization()
        guard authorised else { return }

        await locationService.startTracking()

        await healthKit.startHeartRateMonitoring()

        isTracking = true
        isPaused = false
        startTime = Date()

        WorkoutRepository.shared.logWorkoutStarted(activityType: selectedActivityType)

        startDurationTimer()
        startLocationConsumer()
        startHRConsumer()
    }

    // MARK: Pause

    /// Pauses GPS distance accumulation. The duration timer continues to run.
    func pauseWorkout() {
        guard isTracking, !isPaused else { return }
        isPaused = true
        Task { await locationService.stopTracking() }
    }

    // MARK: Resume

    /// Resumes GPS tracking after a manual pause.
    func resumeWorkout() async {
        guard isTracking, isPaused else { return }
        await locationService.startTracking()
        isPaused = false
        startLocationConsumer()
    }

    // MARK: End

    /// Stops all tracking, assembles the final `WorkoutResult`, persists it to Firestore
    /// and HealthKit, then triggers the summary sheet.
    ///
    /// Sessions shorter than 5 seconds are silently discarded — they are almost always
    /// accidental taps rather than real workouts.
    ///
    /// - Parameter userId: Firebase Auth UID of the current user.
    func endWorkout(userId: String) async {
        guard isTracking else { return }

        isTracking = false
        isPaused = false

        cancelAllTasks()
        await locationService.stopTracking()
        await healthKit.stopHeartRateMonitoring()

        guard elapsedTime > 5, distance > 0 else { return }

        let route = await locationService.route
        let gain = await locationService.elevationGain
        let loss = await locationService.elevationLoss

        let finalSplits = TrackAnalytics.buildSplits(
            route: route,
            hrSamples: hrSamples,
            splitDistanceMeters: 1_000
        )

        let maxHR = hrSamples.map(\.bpm).max() ?? 0
        let computedHRZones = TrackAnalytics.computeHRZones(
            samples: hrSamples,
            maxHR: maxHR > 0 ? maxHR : 190
        )

        let avgPaceSecondsPerKm = TrackAnalytics.pace(distance: distance, duration: elapsedTime)
        let segs = TrackAnalytics.segmentPaces(route: route, segmentSize: 1)
        let calories = estimateCalories(duration: elapsedTime, activityType: selectedActivityType)

        let lats = route.map { $0.coordinate.latitude }
        let lons = route.map { $0.coordinate.longitude }

        var result = WorkoutResult(
            activityType: selectedActivityType,
            startedAt: startTime ?? Date(),
            duration: elapsedTime,
            distance: distance,
            avgPaceSecondsPerKm: avgPaceSecondsPerKm,
            avgHeartRate: avgHeartRate,
            maxHeartRate: maxHR,
            elevationGain: gain,
            elevationLoss: loss,
            calories: calories,
            splits: finalSplits,
            hrZones: computedHRZones,
            achievements: [],
            userId: userId,
            routeLatitudes: lats,
            routeLongitudes: lons,
            segmentPaces: segs
        )

        // Achievements require the complete result — detect after building it.
        let history = (try? await WorkoutRepository.shared.fetchAll(userId: userId)) ?? []
        result.achievements = TrackAnalytics.detectAchievements(result: result, history: history)

        try? await WorkoutRepository.shared.save(result)
        try? await healthKit.saveWorkout(result)

        lastCompletedWorkout = result
        showSummary = true
    }

    // MARK: Discard

    /// Cancels the active session without saving anything.
    ///
    /// Call this when the user dismisses the session screen early or when
    /// elapsed time is under the minimum threshold.
    func discardWorkout() {
        isTracking = false
        isPaused = false
        cancelAllTasks()
        Task {
            await locationService.stopTracking()
            await healthKit.stopHeartRateMonitoring()
            await locationService.reset()
        }
        resetSessionState()
    }

    // MARK: - Private: Task Launchers

    /// Fires every second and updates `elapsedTime` relative to `startTime`.
    private func startDurationTimer() {
        durationTask?.cancel()
        durationTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, !Task.isCancelled else { return }
                guard let start = self.startTime else { return }
                self.elapsedTime = Date().timeIntervalSince(start)
            }
        }
    }

    /// Consumes `locationService.locationStream` and updates all GPS-derived metrics.
    private func startLocationConsumer() {
        locationTask?.cancel()
        locationTask = Task { [weak self] in
            guard let self else { return }
            let stream = await self.locationService.locationStream
            for await location in stream {
                guard !Task.isCancelled else { break }
                await self.handleNewLocation(location)
            }
        }
    }

    /// Consumes `healthKit.heartRateStream` and updates HR-derived metrics.
    private func startHRConsumer() {
        hrTask?.cancel()
        hrTask = Task { [weak self] in
            guard let self else { return }
            let stream = await self.healthKit.heartRateStream
            for await bpm in stream {
                guard !Task.isCancelled else { break }
                await self.handleNewHeartRate(bpm)
            }
        }
    }

    // MARK: - Private: Location Handling

    /// Processes one incoming GPS fix, updating distance, pace, elevation, splits, and coach cues.
    ///
    /// Auto-pause logic: if speed is below 0.5 m/s for `autoPauseThreshold` consecutive
    /// samples, `isAutoPaused` becomes `true` and distance accumulation halts until
    /// speed recovers. The wall-clock timer is unaffected.
    private func handleNewLocation(_ location: CLLocation) async {
        currentSpeed = await locationService.currentSpeedMS
        currentPace = TrackAnalytics.formatPace(await locationService.currentPaceSecondsPerKm)

        // Track maximum speed.
        if currentSpeed > maxSpeed {
            maxSpeed = currentSpeed
        }

        // Auto-pause detection.
        if location.speed >= 0 && location.speed < 0.5 {
            lowSpeedConsecutiveCount += 1
            if lowSpeedConsecutiveCount >= autoPauseThreshold {
                isAutoPaused = true
            }
        } else {
            lowSpeedConsecutiveCount = 0
            isAutoPaused = false
        }

        // Only accumulate distance when not auto-paused and not manually paused.
        if !isAutoPaused && !isPaused {
            distance = await locationService.totalDistance
            elevationGain = await locationService.elevationGain

            // Refresh splits and route overlay from the full route on every fix.
            let route = await locationService.route
            let newSplits = TrackAnalytics.buildSplits(
                route: route,
                hrSamples: hrSamples,
                splitDistanceMeters: 1_000
            )
            splits = newSplits
            splitPaces = newSplits.map { $0.pace }
            routeCoordinates = route.map { $0.coordinate }

            // Fire a split milestone cue when a new completed (full 1 km) split appears.
            let completedSplitCount = newSplits.filter { $0.distance >= 999 }.count
            if completedSplitCount > lastSplitCountForCue {
                lastSplitCountForCue = completedSplitCount
                if let latestSplit = newSplits.first(where: { $0.splitNumber == completedSplitCount }) {
                    let msg = TrackAnalytics.splitMilestoneMessage(
                        splitNumber: completedSplitCount,
                        splitPace: latestSplit.pace,
                        targetPace: targetPaceSecondsPerKm
                    )
                    showCoachMessage(msg)
                }
            }
        }

        // Always update avg pace from total distance + elapsed time.
        let paceSeconds = TrackAnalytics.pace(distance: distance, duration: elapsedTime)
        avgPace = TrackAnalytics.formatPace(paceSeconds)

        // 5-minute interval cue (300 s increments).
        let minuteMark = floor(elapsedTime / 300) * 300
        if elapsedTime >= 300, minuteMark > lastMinuteCueTime {
            lastMinuteCueTime = minuteMark
            let currentPaceSeconds = TrackAnalytics.pace(
                distance: distance,
                duration: elapsedTime
            )
            if let msg = TrackAnalytics.paceCoachMessage(
                currentPace: currentPaceSeconds,
                targetPace: targetPaceSecondsPerKm
            ) {
                showCoachMessage(msg)
            }
        }
    }

    /// Shows `message` in `currentCoachMessage` and auto-clears it after 4 seconds.
    private func showCoachMessage(_ message: String) {
        coachMessageTask?.cancel()
        currentCoachMessage = message
        coachMessageTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            self?.currentCoachMessage = nil
        }
    }

    // MARK: - Private: Heart Rate Handling

    /// Appends a new HR sample, updates `currentHeartRate`, recomputes `avgHeartRate`,
    /// and derives the current HR zone using `assumedMaxHR`.
    private func handleNewHeartRate(_ bpm: Double) async {
        guard bpm > 0 else { return }
        currentHeartRate = bpm
        currentHeartRateZone = TrackAnalytics.calculateHeartRateZone(hr: bpm, maxHR: assumedMaxHR)
        hrSamples.append((timestamp: Date(), bpm: bpm))

        // Running mean — avoids storing a growing sum separately.
        let count = Double(hrSamples.count)
        if count == 1 {
            avgHeartRate = bpm
        } else {
            avgHeartRate = ((avgHeartRate * (count - 1)) + bpm) / count
        }
    }

    // MARK: - Private: Helpers

    private func cancelAllTasks() {
        durationTask?.cancel()
        locationTask?.cancel()
        hrTask?.cancel()
        coachMessageTask?.cancel()
        durationTask = nil
        locationTask = nil
        hrTask = nil
        coachMessageTask = nil
    }

    private func resetSessionState() {
        elapsedTime = 0
        distance = 0
        currentPace = "--:--"
        avgPace = "--:--"
        currentHeartRate = 0
        avgHeartRate = 0
        currentSpeed = 0
        elevationGain = 0
        maxSpeed = 0
        currentHeartRateZone = 0
        currentCoachMessage = nil
        splits = []
        splitPaces = []
        routeCoordinates = []
        hrSamples = []
        startTime = nil
        lowSpeedConsecutiveCount = 0
        isAutoPaused = false
        lastSplitCountForCue = 0
        lastMinuteCueTime = 0
        lastCompletedWorkout = nil
        showSummary = false
        Task { await locationService.reset() }
    }

    /// Rough MET-based calorie estimate — not a substitute for HealthKit's algorithm
    /// but provides a sensible placeholder when HealthKit is unavailable.
    ///
    /// Formula: kcal = MET × weight_kg × duration_hours
    /// Assumes a default weight of 70 kg when no HealthKit body mass is available.
    private func estimateCalories(duration: TimeInterval, activityType: WorkoutActivityType) -> Double {
        let met: Double
        switch activityType {
        case .run:  met = 9.8
        case .walk: met = 3.5
        case .ride: met = 7.5
        case .hike: met = 6.0
        case .swim: met = 8.0
        case .ski:  met = 6.8
        }
        let weightKg = 70.0
        let hours = duration / 3_600.0
        return met * weightKg * hours
    }
}
