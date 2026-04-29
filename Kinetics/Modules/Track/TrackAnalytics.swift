import Foundation
import CoreLocation

// MARK: - TrackAnalytics

/// Pure, stateless analytics namespace for the Track (GPS workout) module.
///
/// All methods are static — `TrackAnalytics` is a computation namespace, not an object.
/// No side effects, no dependencies on actors or services; every function is safe to
/// call from any isolation context and from tests without any setup.
///
/// Relationship to the Vision modules: this mirrors the `StrikingAnalytics` / `GrapplingAnalytics`
/// pattern — the ViewModel calls these functions and stores the returned value types. The
/// analytics layer never holds state.
enum TrackAnalytics {

    // MARK: - Pace

    /// Converts a distance (metres) and duration (seconds) into a pace value in seconds per km.
    ///
    /// Returns `0` when either argument is non-positive to prevent division by zero
    /// and to signal "no valid pace" to callers.
    ///
    /// - Parameters:
    ///   - distance: Distance covered in metres.
    ///   - duration: Elapsed time in seconds.
    /// - Returns: Pace in seconds per kilometre, or `0` for degenerate inputs.
    static func pace(distance: Double, duration: TimeInterval) -> Double {
        guard distance > 0, duration > 0 else { return 0 }
        let km = distance / 1_000.0
        return duration / km
    }

    /// Formats a pace value (seconds/km) as a `"M:SS /km"` string.
    ///
    /// Returns `"--:-- /km"` for non-positive or infinite inputs so callers can
    /// display it directly in the UI without an additional guard.
    ///
    /// - Parameter secondsPerKm: Pace in seconds per kilometre.
    /// - Returns: Formatted string, e.g. `"4:32 /km"` or `"--:-- /km"`.
    static func formatPace(_ secondsPerKm: Double) -> String {
        guard secondsPerKm > 0, secondsPerKm.isFinite else { return "--:-- /km" }
        let totalSeconds = Int(secondsPerKm.rounded())
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d /km", minutes, seconds)
    }

    // MARK: - Heart Rate Zones

    /// Distributes total workout time into the five standard HR zones from a
    /// continuous stream of timestamped heart-rate samples.
    ///
    /// The algorithm walks consecutive sample pairs and proportionally accumulates
    /// the inter-sample duration into the zone that corresponds to the **average**
    /// bpm in that interval. This produces smoother zone totals than snapping each
    /// sample independently, and is the same approach used by Garmin Connect and
    /// Polar Flow.
    ///
    /// Zone thresholds (fraction of maxHR):
    /// | Zone | Range       |
    /// |------|-------------|
    /// | 1    | < 0.50      |
    /// | 2    | 0.50–0.60   |
    /// | 3    | 0.60–0.70   |
    /// | 4    | 0.70–0.80   |
    /// | 5    | > 0.80      |
    ///
    /// - Parameters:
    ///   - samples: Ordered array of `(timestamp, bpm)` pairs. May be empty.
    ///   - maxHR: Athlete's maximum heart rate in bpm. Provide `220 - age` as a
    ///     reasonable default when the true value is unknown; pass `190` as a
    ///     safe fallback when age is unavailable.
    /// - Returns: `HRZones` with cumulative seconds in each zone.
    static func computeHRZones(
        samples: [(timestamp: Date, bpm: Double)],
        maxHR: Double
    ) -> HRZones {
        guard maxHR > 0, samples.count >= 2 else { return HRZones() }

        var zones = HRZones()

        for index in 0 ..< samples.count - 1 {
            let current = samples[index]
            let next    = samples[index + 1]

            // Only accumulate forward-moving time to guard against out-of-order samples.
            let interval = next.timestamp.timeIntervalSince(current.timestamp)
            guard interval > 0 else { continue }

            // Use the mid-point bpm for the interval for smoother zone attribution.
            let avgBpm = (current.bpm + next.bpm) / 2.0
            let zone   = hrZone(bpm: avgBpm, maxHR: maxHR)

            switch zone {
            case 1: zones.zone1 += interval
            case 2: zones.zone2 += interval
            case 3: zones.zone3 += interval
            case 4: zones.zone4 += interval
            default: zones.zone5 += interval
            }
        }

        return zones
    }

    /// Maps a heart-rate sample to a zone index (1–5) given the athlete's maximum HR.
    ///
    /// Zone thresholds:
    /// - Zone 1: < 50 % of maxHR (recovery)
    /// - Zone 2: 50–60 % (aerobic base)
    /// - Zone 3: 60–70 % (tempo)
    /// - Zone 4: 70–80 % (threshold)
    /// - Zone 5: > 80 % (maximum effort)
    ///
    /// - Parameters:
    ///   - bpm: Heart rate sample in beats per minute.
    ///   - maxHR: Maximum heart rate in beats per minute.
    /// - Returns: Zone index from 1 (lowest) to 5 (highest).
    static func hrZone(bpm: Double, maxHR: Double) -> Int {
        guard maxHR > 0 else { return 1 }
        let fraction = bpm / maxHR
        switch fraction {
        case ..<0.50: return 1
        case 0.50 ..< 0.60: return 2
        case 0.60 ..< 0.70: return 3
        case 0.70 ..< 0.80: return 4
        default: return 5
        }
    }

    // MARK: - Splits

    /// Builds an ordered array of `WorkoutSplit` values from a continuous route
    /// and a parallel HR sample stream.
    ///
    /// The function walks the route point-by-point, accumulating Haversine distance.
    /// Each time the accumulated distance crosses a multiple of `splitDistanceMeters`,
    /// a split is closed and a new one begins. A partial final split is recorded only
    /// when it covers at least 1 m, preventing a zero-distance trailing entry.
    ///
    /// HR for each split is computed by finding all HR samples whose timestamp falls
    /// within the split's time window and averaging their bpm values. Splits that
    /// contain no HR samples report `0`.
    ///
    /// - Parameters:
    ///   - route: Ordered array of `CLLocation` waypoints. Must have at least 2 entries
    ///     for any split to be produced.
    ///   - hrSamples: Ordered `(timestamp, bpm)` pairs from the HR sensor. May be empty.
    ///   - splitDistanceMeters: Distance threshold per split, in metres. Defaults to 1 000 m.
    /// - Returns: Array of `WorkoutSplit` values, or an empty array when the route is too
    ///   short to complete even one split.
    static func buildSplits(
        route: [CLLocation],
        hrSamples: [(timestamp: Date, bpm: Double)],
        splitDistanceMeters: Double = 1_000.0
    ) -> [WorkoutSplit] {
        guard route.count >= 2, splitDistanceMeters > 0 else { return [] }

        var splits: [WorkoutSplit] = []
        var splitNumber = 1
        var accumulatedDistance: Double = 0
        var splitStartDistance: Double = 0
        var splitStartTime = route[0].timestamp

        for index in 1 ..< route.count {
            let previous = route[index - 1]
            let current  = route[index]

            let segmentDistance = current.distance(from: previous)
            accumulatedDistance += segmentDistance

            // Check whether we have crossed the next split boundary.
            while accumulatedDistance - splitStartDistance >= splitDistanceMeters {
                let splitEndDistance = splitStartDistance + splitDistanceMeters

                // Interpolate the timestamp at the exact split boundary.
                // The fraction represents how far into this segment the boundary falls.
                let remainingInSegment = splitEndDistance - (accumulatedDistance - segmentDistance)
                let fraction = segmentDistance > 0 ? remainingInSegment / segmentDistance : 1.0
                let segmentDuration = current.timestamp.timeIntervalSince(previous.timestamp)
                let splitEndTime = previous.timestamp.addingTimeInterval(segmentDuration * fraction)

                let splitDuration = splitEndTime.timeIntervalSince(splitStartTime)
                let splitHR = averageHR(
                    samples: hrSamples,
                    from: splitStartTime,
                    to: splitEndTime
                )

                splits.append(
                    WorkoutSplit(
                        splitNumber: splitNumber,
                        distance: splitDistanceMeters,
                        duration: max(splitDuration, 0),
                        avgHeartRate: splitHR
                    )
                )

                splitNumber += 1
                splitStartDistance += splitDistanceMeters
                splitStartTime = splitEndTime
            }
        }

        // Record a partial final split if any distance remains.
        let remainingDistance = accumulatedDistance - splitStartDistance
        if remainingDistance >= 1.0 {
            let lastTime = route[route.count - 1].timestamp
            let finalDuration = lastTime.timeIntervalSince(splitStartTime)
            let finalHR = averageHR(
                samples: hrSamples,
                from: splitStartTime,
                to: lastTime
            )
            splits.append(
                WorkoutSplit(
                    splitNumber: splitNumber,
                    distance: remainingDistance,
                    duration: max(finalDuration, 0),
                    avgHeartRate: finalHR
                )
            )
        }

        return splits
    }

    // MARK: - Elevation

    /// Computes cumulative elevation gain and loss from an ordered route array.
    ///
    /// Only elevation deltas that exceed a ±1 m noise threshold are counted, which
    /// reduces GPS altitude jitter from accumulating into misleading totals. This
    /// threshold matches the approach used by Wahoo and Apple Fitness+.
    ///
    /// - Parameter route: Ordered array of `CLLocation` waypoints.
    /// - Returns: A tuple of `(gain, loss)` in metres, both as non-negative values.
    static func elevationMetrics(route: [CLLocation]) -> (gain: Double, loss: Double) {
        guard route.count >= 2 else { return (0, 0) }

        let noiseThresholdMeters = 1.0
        var gain: Double = 0
        var loss: Double = 0

        for index in 1 ..< route.count {
            let delta = route[index].altitude - route[index - 1].altitude
            if delta > noiseThresholdMeters {
                gain += delta
            } else if delta < -noiseThresholdMeters {
                loss += abs(delta)
            }
        }

        return (gain, loss)
    }

    // MARK: - Achievements

    /// Compares a newly completed workout against the athlete's historical results
    /// and returns an array of human-readable achievement strings.
    ///
    /// Checks performed (in evaluation order):
    /// 1. Longest distance ever for this activity type.
    /// 2. Longest duration ever for this activity type.
    /// 3. Best average pace ever (lowest seconds/km) for this activity type.
    /// 4. First time completing a sub-5:00/km kilometre split.
    /// 5. First time completing a sub-4:00/km kilometre split.
    /// 6. First workout of this activity type.
    ///
    /// History should exclude the new `result` itself — pass only previously persisted
    /// sessions so comparisons reflect historical bests, not the current workout.
    ///
    /// - Parameters:
    ///   - result: The newly completed workout to evaluate.
    ///   - history: All previously completed workouts for this user.
    /// - Returns: Array of achievement strings; empty when no milestones are reached.
    static func detectAchievements(
        result: WorkoutResult,
        history: [WorkoutResult]
    ) -> [String] {
        let sameType = history.filter { $0.activityType == result.activityType }
        var achievements: [String] = []

        // First workout of this activity type.
        if sameType.isEmpty {
            achievements.append("First \(result.activityType.displayName.lowercased()) ever")
            return achievements  // Can't beat personal bests with no history — return early.
        }

        // Longest distance ever.
        let previousMaxDistance = sameType.map(\.distance).max() ?? 0
        if result.distance > previousMaxDistance {
            achievements.append("Longest \(result.activityType.displayName.lowercased()) ever")
        }

        // Longest duration ever.
        let previousMaxDuration = sameType.map(\.duration).max() ?? 0
        if result.duration > previousMaxDuration {
            achievements.append("Longest time on a \(result.activityType.displayName.lowercased()) ever")
        }

        // Best average pace (lower seconds/km is faster).
        let previousBestPace = sameType
            .filter { $0.avgPaceSecondsPerKm > 0 }
            .map(\.avgPaceSecondsPerKm)
            .min() ?? Double.greatestFiniteMagnitude

        if result.avgPaceSecondsPerKm > 0, result.avgPaceSecondsPerKm < previousBestPace {
            achievements.append("New personal best pace — \(formatPace(result.avgPaceSecondsPerKm))")
        }

        // Sub-5:00/km split milestone.
        let sub5ThresholdSec: Double = 5 * 60  // 300 s/km
        let hadSub5Previously = sameType.contains { workout in
            workout.splits.contains { $0.pace < sub5ThresholdSec && $0.pace > 0 }
        }
        if !hadSub5Previously {
            let achievedSub5 = result.splits.contains { $0.pace < sub5ThresholdSec && $0.pace > 0 }
            if achievedSub5 {
                achievements.append("First sub-5:00/km km")
            }
        }

        // Sub-4:00/km split milestone.
        let sub4ThresholdSec: Double = 4 * 60  // 240 s/km
        let hadSub4Previously = sameType.contains { workout in
            workout.splits.contains { $0.pace < sub4ThresholdSec && $0.pace > 0 }
        }
        if !hadSub4Previously {
            let achievedSub4 = result.splits.contains { $0.pace < sub4ThresholdSec && $0.pace > 0 }
            if achievedSub4 {
                achievements.append("First sub-4:00/km km")
            }
        }

        return achievements
    }

    // MARK: - Segment Paces

    /// Produces a pace value (seconds/km) for each consecutive N-point segment of the route.
    ///
    /// Segments are formed by grouping route points into windows of `segmentSize`.
    /// The pace for each window is derived from the Haversine distance between the
    /// first and last point in the window and the elapsed time between those timestamps.
    /// This produces the float array consumed by the map overlay to colour-code the
    /// route from blue (fast) through green and orange to red (slow).
    ///
    /// - Parameters:
    ///   - route: Ordered array of `CLLocation` waypoints. Returns empty when fewer
    ///     than 2 points exist.
    ///   - segmentSize: Number of route points per segment window. Must be ≥ 2.
    ///     Typical values: 5–10 for city runs, 3 for dense tracks.
    /// - Returns: Array of pace values (seconds/km), one per segment. May be empty.
    static func segmentPaces(route: [CLLocation], segmentSize: Int) -> [Double] {
        guard route.count >= 2, segmentSize >= 2 else { return [] }

        var paces: [Double] = []
        var windowStart = 0

        while windowStart + segmentSize - 1 < route.count {
            let windowEnd = windowStart + segmentSize - 1
            let startPoint = route[windowStart]
            let endPoint   = route[windowEnd]

            let distance = endPoint.distance(from: startPoint)
            let duration = endPoint.timestamp.timeIntervalSince(startPoint.timestamp)
            let segPace  = pace(distance: distance, duration: duration)

            paces.append(segPace)
            windowStart += segmentSize
        }

        // Handle trailing points that don't fill a full window — only record if
        // at least 2 points remain, so distance and time can be computed.
        if windowStart < route.count - 1 {
            let startPoint = route[windowStart]
            let endPoint   = route[route.count - 1]
            let distance   = endPoint.distance(from: startPoint)
            let duration   = endPoint.timestamp.timeIntervalSince(startPoint.timestamp)
            let tailPace   = pace(distance: distance, duration: duration)
            if tailPace > 0 {
                paces.append(tailPace)
            }
        }

        return paces
    }

    // MARK: - Private Helpers

    /// Returns the average bpm of all HR samples whose timestamp falls within
    /// the half-open interval `[from, to)`. Returns `0` when no samples match.
    private static func averageHR(
        samples: [(timestamp: Date, bpm: Double)],
        from startTime: Date,
        to endTime: Date
    ) -> Double {
        let window = samples.filter {
            $0.timestamp >= startTime && $0.timestamp < endTime
        }
        guard !window.isEmpty else { return 0 }
        let totalBpm = window.reduce(0.0) { $0 + $1.bpm }
        return totalBpm / Double(window.count)
    }
}
