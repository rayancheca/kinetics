@preconcurrency import CoreMotion
import SwiftUI

// MARK: - MotionManager

/// Tracks device attitude via CoreMotion and publishes roll/pitch angles.
/// Uses a singleton so all parallax views share the same CMMotionManager instance.
@Observable
@MainActor
final class MotionManager {

    // MARK: Singleton

    static let shared = MotionManager()

    // MARK: Published State

    /// Left/right tilt in degrees.
    var roll: Double = 0

    /// Forward/back tilt in degrees.
    var pitch: Double = 0

    // MARK: Private

    private let manager = CMMotionManager()

    private init() {
        start()
    }

    // MARK: Start

    func start() {
        guard manager.isDeviceMotionAvailable else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 60.0
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, let motion else { return }
            // Dispatch to MainActor for Swift 6 actor isolation compliance.
            Task { @MainActor in
                self.roll  = motion.attitude.roll  * 180 / .pi
                self.pitch = motion.attitude.pitch * 180 / .pi
            }
        }
    }

    deinit {
        manager.stopDeviceMotionUpdates()
    }
}

// MARK: - ParallaxCard ViewModifier

/// Applies a subtle gyroscope-driven 3D parallax to any view.
///
/// - Parameter depth: Multiplier for the effect intensity.
///   - `1.0` — very subtle (hero cards)
///   - `2.0` — noticeable (module grid cards)
///   - `2.5` — strong (featured / full-width cards)
struct ParallaxCard: ViewModifier {

    // MARK: Dependencies

    @State private var motion = MotionManager.shared

    // MARK: Configuration

    let depth: Double

    // MARK: Body

    func body(content: Content) -> some View {
        content
            .rotation3DEffect(
                .degrees(motion.roll * 0.3 * depth),
                axis: (x: 0, y: 1, z: 0),
                perspective: 0.5
            )
            .rotation3DEffect(
                .degrees(-motion.pitch * 0.3 * depth),
                axis: (x: 1, y: 0, z: 0),
                perspective: 0.5
            )
    }
}

// MARK: - View Extension

extension View {
    /// Adds gyroscope-driven parallax to this view.
    ///
    /// - Parameter depth: Effect intensity (default `1.0`).
    func parallaxCard(depth: Double = 1.0) -> some View {
        modifier(ParallaxCard(depth: depth))
    }
}
