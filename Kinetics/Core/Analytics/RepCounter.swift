import Foundation

// MARK: - RepCounter

/// Counts repetitions by detecting peaks/valleys in joint oscillation.
/// Works for any cyclical movement (squats, presses, rows, curls).
struct RepCounter: Sendable {

    // MARK: - Configuration

    /// Minimum movement amplitude to qualify as a rep (normalized 0-1).
    private let amplitudeThreshold: Double = 0.08

    /// Smoothing window size for noise reduction.
    private let windowSize: Int = 5

    // MARK: - State

    private var wristYHistory: [Double] = []
    private var repCount: Int = 0
    private var inBottomPhase: Bool = false
    private var peakValue: Double = 0
    private var valleyValue: Double = Double.infinity

    // MARK: - Public Interface

    /// Call once per frame with the current wrist Y position (normalized 0-1, Vision coords).
    ///
    /// Vision Y is bottom-origin: 0 = bottom of frame, 1 = top. For a squat the wrist
    /// descends (Y decreases) into the bottom phase and ascends (Y increases) on the way up.
    ///
    /// - Parameter wristY: Right wrist Y position in Vision normalized space.
    /// - Returns: The current cumulative rep count after processing this frame.
    mutating func update(wristY: Double) -> Int {
        wristYHistory.append(wristY)
        if wristYHistory.count > windowSize {
            wristYHistory.removeFirst()
        }

        let smoothed = wristYHistory.reduce(0, +) / Double(wristYHistory.count)

        if !inBottomPhase {
            // Looking for valley (bottom of rep).
            if smoothed < valleyValue {
                valleyValue = smoothed
            } else if smoothed - valleyValue > amplitudeThreshold {
                // Started moving up — entered ascent phase.
                inBottomPhase = true
                peakValue = smoothed
            }
        } else {
            // In ascent — looking for peak (top lockout).
            if smoothed > peakValue {
                peakValue = smoothed
            } else if peakValue - smoothed > amplitudeThreshold {
                // Started descending again — rep complete.
                repCount += 1
                inBottomPhase = false
                valleyValue = smoothed
                peakValue = 0
            }
        }

        return repCount
    }

    /// Resets all state. Call when a new session starts or the user resets the rep count.
    mutating func reset() {
        wristYHistory.removeAll()
        repCount = 0
        inBottomPhase = false
        peakValue = 0
        valleyValue = Double.infinity
    }

    /// The current cumulative rep count (read-only convenience accessor).
    var count: Int { repCount }
}
