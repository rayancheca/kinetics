@preconcurrency import ActivityKit
import Foundation
import Observation

// MARK: - LiveSessionController

/// Public API for starting, updating, and ending the Kinetics Live Activity.
///
/// ViewModels call this controller at session boundaries — the controller takes
/// care of ActivityKit auth checks, gracefully no-ops when Live Activities are
/// disabled, and applies a small in-memory throttle so frame-rate metric updates
/// don't flood the system (ActivityKit rejects updates faster than once per
/// second on most devices).
///
/// Threading: `@MainActor` because every call site already lives on the main
/// actor (SwiftUI views, `@Observable @MainActor` ViewModels).
@MainActor
final class LiveSessionController {

    // MARK: - Singleton

    static let shared = LiveSessionController()

    // MARK: - State

    private var activity: Activity<LiveSessionAttributes>?
    private var lastUpdate: Date = .distantPast

    /// Minimum gap between dynamic-state updates pushed to ActivityKit.
    /// Frame-rate updates (~30 fps) would otherwise overwhelm the system.
    private let updateThrottle: TimeInterval = 1.0

    private init() {}

    // MARK: - Lifecycle

    /// Starts a Live Activity for the supplied module if Live Activities are
    /// enabled on this device. Replaces any in-flight activity for safety.
    func start(
        sportRaw: String,
        displayName: String,
        accentHex: String,
        iconName: String,
        initialState: LiveSessionAttributes.ContentState
    ) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        // Cancel any stale activity left from a previous session.
        if activity != nil {
            activity = nil
            Self.endAllOrphaned()
        }

        let attributes = LiveSessionAttributes(
            sportRaw: sportRaw,
            displayName: displayName,
            accentHex: accentHex,
            iconName: iconName,
            startedAt: Date()
        )

        do {
            let content = ActivityContent(state: initialState, staleDate: nil)
            activity = try Activity.request(
                attributes: attributes,
                content: content,
                pushType: nil
            )
            lastUpdate = Date()
        } catch {
            // Swallowing — Live Activities are an enhancement, not a critical path.
            activity = nil
        }
    }

    /// Updates the Live Activity's dynamic state, applying the throttle window.
    func update(
        _ state: LiveSessionAttributes.ContentState,
        force: Bool = false
    ) {
        guard let current = activity else { return }
        let now = Date()
        if !force, now.timeIntervalSince(lastUpdate) < updateThrottle { return }
        lastUpdate = now

        let content = ActivityContent(state: state, staleDate: now.addingTimeInterval(120))
        Self.performUpdate(current, content: content)
    }

    /// Ends the active Live Activity, optionally publishing one final state.
    func end(
        finalState: LiveSessionAttributes.ContentState? = nil,
        dismissalPolicy: ActivityUIDismissalPolicy = .immediate
    ) {
        guard let current = activity else { return }
        activity = nil

        let content: ActivityContent<LiveSessionAttributes.ContentState>? = finalState.map {
            ActivityContent(state: $0, staleDate: nil)
        }
        Self.performEnd(current, content: content, policy: dismissalPolicy)
    }

    /// Force-ends any orphaned activities from prior runs. Safe to call at app launch.
    nonisolated static func endAllOrphaned() {
        Task.detached(priority: .utility) {
            for activity in Activity<LiveSessionAttributes>.activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }

    // MARK: - Nonisolated helpers
    //
    // These exist so the async work that ActivityKit requires can happen
    // outside the main actor's isolation domain. The Activity reference is
    // itself Sendable (it conforms via the framework) and content is a value
    // type, so handing them off here is data-race-safe.

    nonisolated private static func performUpdate(
        _ activity: Activity<LiveSessionAttributes>,
        content: ActivityContent<LiveSessionAttributes.ContentState>
    ) {
        Task.detached(priority: .utility) {
            await activity.update(content)
        }
    }

    nonisolated private static func performEnd(
        _ activity: Activity<LiveSessionAttributes>,
        content: ActivityContent<LiveSessionAttributes.ContentState>?,
        policy: ActivityUIDismissalPolicy
    ) {
        Task.detached(priority: .utility) {
            await activity.end(content, dismissalPolicy: policy)
        }
    }
}
