import Foundation
import HealthKit

// MARK: - WorkoutActivityType + HealthKit

/// Extends the GPS-focused `WorkoutActivityType` with its closest
/// `HKWorkoutActivityType` mapping.  Kept here so the model layer stays
/// free of HealthKit imports.
private extension WorkoutActivityType {
    var hkActivityType: HKWorkoutActivityType {
        switch self {
        case .run:  .running
        case .walk: .walking
        case .ride: .cycling
        case .hike: .hiking
        case .swim: .swimming
        case .ski:  .downhillSkiing
        }
    }
}

// MARK: - HealthKitError

enum HealthKitError: LocalizedError, Sendable {
    case notAvailable
    case authorizationFailed(Error)
    case saveFailed(Error)
    case queryFailed(Error)

    var errorDescription: String? {
        switch self {
        case .notAvailable:
            "Apple Health is not available on this device."
        case .authorizationFailed(let error):
            "HealthKit authorization failed: \(error.localizedDescription)"
        case .saveFailed(let error):
            "Failed to save workout to Health: \(error.localizedDescription)"
        case .queryFailed(let error):
            "Failed to read data from Health: \(error.localizedDescription)"
        }
    }
}

// MARK: - HealthKitService

/// Actor isolating HKHealthStore interactions to prevent data races.
///
/// Reads live heart rate during workouts via `HKAnchoredObjectQuery` and writes
/// completed sessions to Apple Health as `HKWorkout` records.
///
/// All public methods are safe to call from any isolation domain — the actor
/// serialises access internally. On devices where HealthKit is unavailable
/// (e.g. simulators), every method returns a sensible default or throws
/// `HealthKitError.notAvailable` instead of crashing.
actor HealthKitService {

    // MARK: - Singleton

    static let shared = HealthKitService()

    // MARK: - Published State

    /// `true` when `HKHealthStore.isHealthDataAvailable()` returns `true`.
    private(set) var isAvailable: Bool
    /// `true` after the user has granted the required read/write permissions.
    private(set) var isAuthorized: Bool = false
    /// Most recent heart rate in beats per minute. Zero when no HR sensor is connected
    /// or when `stopHeartRateMonitoring()` has been called.
    private(set) var currentHeartRate: Double = 0

    // MARK: - Heart Rate Stream

    /// Delivers each new heart rate sample (in bpm) during an active workout.
    ///
    /// The stream is replaced on each call to `startHeartRateMonitoring()`.
    var heartRateStream: AsyncStream<Double> { _heartRateStream }
    private var _heartRateStream: AsyncStream<Double>
    private var heartRateContinuation: AsyncStream<Double>.Continuation?

    // MARK: - Private

    private let store: HKHealthStore
    private var anchoredQuery: HKAnchoredObjectQuery?
    private var heartRateAnchor: HKQueryAnchor?

    // MARK: - HealthKit Type Definitions

    // Using lazy type-resolution to avoid force-unwraps: these identifiers are
    // defined in the SDK, so `quantityType(forIdentifier:)` is non-nil.
    private static let heartRateType = HKQuantityType(.heartRate)
    private static let stepCountType = HKQuantityType(.stepCount)
    private static let activeEnergyType = HKQuantityType(.activeEnergyBurned)
    private static let distanceType = HKQuantityType(.distanceWalkingRunning)

    private static let readTypes: Set<HKObjectType> = [
        heartRateType,
        stepCountType,
        activeEnergyType,
        HKQuantityType(.vo2Max)
    ]

    private static let writeTypes: Set<HKSampleType> = [
        HKObjectType.workoutType(),
        distanceType,
        activeEnergyType
    ]

    // MARK: - Init

    private init() {
        isAvailable = HKHealthStore.isHealthDataAvailable()
        store = HKHealthStore()

        var cont: AsyncStream<Double>.Continuation!
        _heartRateStream = AsyncStream(Double.self, bufferingPolicy: .bufferingNewest(1)) { cont = $0 }
        heartRateContinuation = cont
    }

    // MARK: - Authorization

    /// Requests read and write authorization from HealthKit.
    ///
    /// - Read:  heartRate, stepCount, activeEnergyBurned, vo2Max
    /// - Write: workoutType, distanceWalkingRunning, activeEnergyBurned
    ///
    /// Throws `HealthKitError.notAvailable` when HealthKit is unavailable (simulator).
    /// Throws `HealthKitError.authorizationFailed` when the underlying HK call errors.
    func requestAuthorization() async throws {
        guard isAvailable else { throw HealthKitError.notAvailable }
        do {
            try await store.requestAuthorization(
                toShare: HealthKitService.writeTypes,
                read: HealthKitService.readTypes
            )
            isAuthorized = true
        } catch {
            throw HealthKitError.authorizationFailed(error)
        }
    }

    // MARK: - Live Heart Rate Monitoring

    /// Starts an anchored HealthKit query that fires for every new heart rate sample.
    ///
    /// - Yields each bpm value into `heartRateStream`.
    /// - Updates `currentHeartRate` on the actor.
    /// - Safe to call multiple times — stops any active query first.
    func startHeartRateMonitoring() {
        guard isAvailable, isAuthorized else { return }

        // Stop any previous query cleanly.
        stopHeartRateMonitoring()

        // Fresh stream for this monitoring session.
        var cont: AsyncStream<Double>.Continuation!
        _heartRateStream = AsyncStream(Double.self, bufferingPolicy: .bufferingNewest(1)) { cont = $0 }
        heartRateContinuation = cont

        let hrType = HealthKitService.heartRateType
        let bpmUnit = HKUnit.count().unitDivided(by: .minute())

        // Predicate: only samples from the last 60 seconds on first run, then anchor-based.
        let predicate = HKQuery.predicateForSamples(
            withStart: Date().addingTimeInterval(-60),
            end: nil,
            options: .strictStartDate
        )

        let query = HKAnchoredObjectQuery(
            type: hrType,
            predicate: predicate,
            anchor: heartRateAnchor,
            limit: HKObjectQueryNoLimit
        ) { [weak self] _, samples, _, newAnchor, error in
            guard error == nil else { return }
            Task {
                await self?.handleHeartRateSamples(samples, anchor: newAnchor, unit: bpmUnit)
            }
        }

        // updateHandler fires for every new sample after the initial result.
        query.updateHandler = { [weak self] _, samples, _, newAnchor, error in
            guard error == nil else { return }
            Task {
                await self?.handleHeartRateSamples(samples, anchor: newAnchor, unit: bpmUnit)
            }
        }

        store.execute(query)
        anchoredQuery = query
    }

    /// Stops the live heart rate query and resets `currentHeartRate` to zero.
    func stopHeartRateMonitoring() {
        if let query = anchoredQuery {
            store.stop(query)
            anchoredQuery = nil
        }
        currentHeartRate = 0
        heartRateContinuation?.finish()
        heartRateContinuation = nil
    }

    // MARK: - Workout Writing

    /// Saves a completed `WorkoutResult` to Apple Health as an `HKWorkout`.
    ///
    /// Maps `WorkoutActivityType` to `HKWorkoutActivityType`, then writes
    /// energy and distance samples alongside the workout record.
    ///
    /// Throws `HealthKitError.notAvailable` on simulator.
    /// Throws `HealthKitError.saveFailed` when the HK write fails.
    func saveWorkout(_ result: WorkoutResult) async throws {
        guard isAvailable else { throw HealthKitError.notAvailable }
        guard isAuthorized else { throw HealthKitError.authorizationFailed(
            NSError(domain: "HealthKitService", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "HealthKit not authorized."])
        ) }

        let startDate = result.startedAt
        let endDate = startDate.addingTimeInterval(result.duration)
        let hkType = result.activityType.hkActivityType

        // Build associated quantity samples to attach to the workout.
        var samples: [HKSample] = []

        // Active energy burned sample.
        if result.calories > 0 {
            let energyQuantity = HKQuantity(unit: .kilocalorie(), doubleValue: result.calories)
            let energySample = HKQuantitySample(
                type: HealthKitService.activeEnergyType,
                quantity: energyQuantity,
                start: startDate,
                end: endDate
            )
            samples.append(energySample)
        }

        // Distance sample (walking/running distance covers most Kinetics activities).
        if result.distance > 0 {
            let distanceQuantity = HKQuantity(unit: .meter(), doubleValue: result.distance)
            let distanceSample = HKQuantitySample(
                type: HealthKitService.distanceType,
                quantity: distanceQuantity,
                start: startDate,
                end: endDate
            )
            samples.append(distanceSample)
        }

        // Build the HKWorkout.
        let totalEnergy = result.calories > 0
            ? HKQuantity(unit: .kilocalorie(), doubleValue: result.calories)
            : nil
        let totalDistance = result.distance > 0
            ? HKQuantity(unit: .meter(), doubleValue: result.distance)
            : nil

        let workout = HKWorkout(
            activityType: hkType,
            start: startDate,
            end: endDate,
            duration: result.duration,
            totalEnergyBurned: totalEnergy,
            totalDistance: totalDistance,
            metadata: [
                HKMetadataKeyWorkoutBrandName: "Kinetics",
                "activity_display_name": result.activityType.displayName
            ]
        )

        do {
            // Save the workout first, then add its associated samples.
            try await store.save(workout)
            if !samples.isEmpty {
                // HKHealthStore.add(_:to:) has no async overload — wrap with continuation.
                try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                    store.add(samples, to: workout) { _, error in
                        if let error { cont.resume(throwing: error) }
                        else { cont.resume() }
                    }
                }
            }
        } catch {
            throw HealthKitError.saveFailed(error)
        }
    }

    // MARK: - Historical Reads

    /// Returns the total step count for today from HealthKit.
    ///
    /// Returns `0` when HealthKit is unavailable or the user has not granted step
    /// count read permission — never throws.
    func fetchTodayStepCount() async -> Int {
        guard isAvailable, isAuthorized else { return 0 }

        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(
            withStart: startOfDay,
            end: Date(),
            options: .strictStartDate
        )

        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: HealthKitService.stepCountType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, statistics, error in
                guard error == nil,
                      let statistics,
                      let quantity = statistics.sumQuantity()
                else {
                    continuation.resume(returning: 0)
                    return
                }
                let steps = Int(quantity.doubleValue(for: .count()))
                continuation.resume(returning: steps)
            }
            store.execute(query)
        }
    }

    // MARK: - Private Helpers

    /// Extracts bpm from HealthKit quantity samples and updates actor state.
    private func handleHeartRateSamples(
        _ samples: [HKSample]?,
        anchor: HKQueryAnchor?,
        unit: HKUnit
    ) {
        heartRateAnchor = anchor

        guard let quantitySamples = samples?.compactMap({ $0 as? HKQuantitySample }),
              !quantitySamples.isEmpty
        else { return }

        // Use the most recent sample in this batch.
        let latest = quantitySamples.sorted { $0.startDate < $1.startDate }.last!
        let bpm = latest.quantity.doubleValue(for: unit)

        currentHeartRate = bpm
        heartRateContinuation?.yield(bpm)
    }
}
