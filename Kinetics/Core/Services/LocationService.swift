import CoreLocation
import Foundation

// MARK: - LocationError

enum LocationError: LocalizedError, Sendable {
    case authorizationDenied
    case authorizationRestricted
    case locationUnavailable

    var errorDescription: String? {
        switch self {
        case .authorizationDenied:
            "Location access was denied. Please enable it in Settings > Kinetics > Location."
        case .authorizationRestricted:
            "Location access is restricted on this device."
        case .locationUnavailable:
            "Unable to determine your location. Please check your GPS signal."
        }
    }
}

// MARK: - LocationService

/// Actor isolating CLLocationManager to prevent data races on location data.
/// Delivers a continuous stream of CLLocation during active GPS tracking.
///
/// Usage pattern:
/// ```swift
/// let service = LocationService()
/// let granted = await service.requestAuthorization()
/// guard granted else { return }
/// await service.startTracking()
/// for await location in await service.locationStream {
///     // update map, accumulate distance, etc.
/// }
/// await service.stopTracking()
/// ```
actor LocationService: NSObject {

    // MARK: - Published State

    private(set) var isTracking = false
    private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined
    private(set) var currentLocation: CLLocation?
    /// Total GPS distance accumulated since `startTracking()` in metres.
    private(set) var totalDistance: Double = 0
    /// Cumulative positive elevation change since `startTracking()` in metres.
    private(set) var elevationGain: Double = 0
    /// Cumulative negative elevation change since `startTracking()` in metres (positive value).
    private(set) var elevationLoss: Double = 0
    /// All recorded locations in chronological order since `startTracking()`.
    private(set) var route: [CLLocation] = []
    /// Most recent speed in metres per second. Zero if unavailable or negative.
    private(set) var currentSpeedMS: Double = 0
    /// Most recent pace in seconds per kilometre. Zero when speed is below 0.5 m/s.
    private(set) var currentPaceSecondsPerKm: Double = 0

    // MARK: - Location Stream

    /// Delivers each new valid CLLocation to consumers during an active tracking session.
    ///
    /// The stream is replaced on each call to `startTracking()` so callers that iterate
    /// over a previous stream stop receiving updates after `stopTracking()` is called.
    var locationStream: AsyncStream<CLLocation> { _locationStream }
    private var _locationStream: AsyncStream<CLLocation>
    private var locationContinuation: AsyncStream<CLLocation>.Continuation?

    // MARK: - Private

    nonisolated(unsafe) private let manager: CLLocationManager
    private var authorizationContinuation: CheckedContinuation<Bool, Never>?
    private var previousLocation: CLLocation?

    // MARK: - Init

    override init() {
        manager = CLLocationManager()
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.distanceFilter = 5 // metres — suppress micro-updates
        manager.allowsBackgroundLocationUpdates = true
        manager.pausesLocationUpdatesAutomatically = false
        manager.activityType = .fitness

        // Create the initial stream before super.init so the stored properties are set.
        var cont: AsyncStream<CLLocation>.Continuation!
        _locationStream = AsyncStream(CLLocation.self, bufferingPolicy: .bufferingNewest(1)) { cont = $0 }
        locationContinuation = cont

        super.init()
        manager.delegate = self
        authorizationStatus = manager.authorizationStatus
    }

    // MARK: - Authorization

    /// Requests always-on location authorization.
    ///
    /// Returns `true` immediately if authorization is already granted.
    /// Suspends until the user responds to the system prompt otherwise.
    func requestAuthorization() async -> Bool {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            return true
        case .denied:
            return false
        case .restricted:
            return false
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                // Store so the delegate can resume it.
                authorizationContinuation = continuation
                manager.requestAlwaysAuthorization()
            }
        @unknown default:
            return false
        }
    }

    // MARK: - Tracking Lifecycle

    /// Starts GPS tracking at the highest available accuracy.
    ///
    /// Replaces the current `locationStream` with a fresh one — callers should
    /// re-subscribe after calling this method if they stopped a previous tracking session.
    func startTracking() async {
        guard !isTracking else { return }

        // Create a fresh stream for this tracking session.
        var cont: AsyncStream<CLLocation>.Continuation!
        _locationStream = AsyncStream(CLLocation.self, bufferingPolicy: .bufferingNewest(1)) { cont = $0 }
        locationContinuation = cont

        previousLocation = nil
        isTracking = true
        manager.startUpdatingLocation()
    }

    /// Stops GPS tracking and finalises all accumulated metrics.
    func stopTracking() async {
        guard isTracking else { return }
        manager.stopUpdatingLocation()
        isTracking = false
        locationContinuation?.finish()
        locationContinuation = nil
    }

    /// Resets all accumulated workout state. Call before starting a new workout.
    func reset() {
        totalDistance = 0
        elevationGain = 0
        elevationLoss = 0
        route = []
        currentLocation = nil
        currentSpeedMS = 0
        currentPaceSecondsPerKm = 0
        previousLocation = nil
    }

    // MARK: - Internal Update Processing

    /// Processes a validated CLLocation, updating all accumulated metrics.
    /// Called from the nonisolated delegate method after basic filtering passes.
    private func processLocation(_ location: CLLocation) {
        currentLocation = location

        // Speed (CLLocation returns negative when unavailable).
        let speed = max(0, location.speed)
        currentSpeedMS = speed
        currentPaceSecondsPerKm = speed > 0.5 ? 1_000.0 / speed : 0

        if let previous = previousLocation {
            // Distance accumulation.
            let segment = location.distance(from: previous)
            totalDistance += segment

            // Elevation change with 0.5 m noise threshold.
            let altitudeDelta = location.altitude - previous.altitude
            if altitudeDelta > 0.5 {
                elevationGain += altitudeDelta
            } else if altitudeDelta < -0.5 {
                elevationLoss += abs(altitudeDelta)
            }
        }

        route.append(location)
        previousLocation = location
        locationContinuation?.yield(location)
    }
}

// MARK: - CLLocationManagerDelegate

extension LocationService: CLLocationManagerDelegate {

    /// Called on the main thread by CLLocationManager. The `nonisolated` requirement is
    /// satisfied because all mutation goes through the `Task { await self.… }` hop to the actor.
    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        // Filter: keep only high-quality fixes.
        let validLocations = locations.filter { location in
            // Negative accuracy means invalid fix.
            guard location.horizontalAccuracy >= 0 else { return false }
            // Reject horizontally inaccurate fixes (> 50 m).
            guard location.horizontalAccuracy <= 50 else { return false }
            // Reject vertically inaccurate fixes (> 20 m) when altitude is used.
            guard location.verticalAccuracy <= 20 else { return false }
            // Discard stale locations (older than 5 seconds).
            guard location.timestamp.timeIntervalSinceNow > -5 else { return false }
            return true
        }

        guard !validLocations.isEmpty else { return }

        Task {
            for location in validLocations {
                await processLocation(location)
            }
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task {
            await updateAuthorization(status)
        }
    }

    // MARK: Private helpers called from nonisolated delegate

    private func updateAuthorization(_ status: CLAuthorizationStatus) {
        authorizationStatus = status
        guard let continuation = authorizationContinuation else { return }
        authorizationContinuation = nil
        switch status {
        case .authorizedAlways, .authorizedWhenInUse:
            continuation.resume(returning: true)
        default:
            continuation.resume(returning: false)
        }
    }
}
