import Foundation
import WatchConnectivity

// MARK: - WatchConnectivityService

@MainActor
final class WatchConnectivityService: NSObject, ObservableObject {
    static let shared = WatchConnectivityService()

    // MARK: Published State

    @Published var isWatchReachable = false

    // MARK: Init

    private override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    // MARK: Send Methods

    func sendSessionUpdate(_ data: [String: Any]) {
        guard WCSession.default.isReachable else { return }
        WCSession.default.sendMessage(data, replyHandler: nil, errorHandler: nil)
    }

    func sendHeartRate(_ bpm: Double) {
        sendSessionUpdate(["heartRate": bpm])
    }

    func sendTrackMetrics(distance: Double, pace: Double) {
        sendSessionUpdate(["distance": distance, "pace": pace])
    }
}

// MARK: - WCSessionDelegate

extension WatchConnectivityService: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith state: WCSessionActivationState,
        error: Error?
    ) {
        // Extract Sendable values before crossing isolation boundary (Swift 6)
        let activated = state == .activated && session.isReachable
        Task { @MainActor in
            self.isWatchReachable = activated
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        // Extract Sendable value before crossing isolation boundary (Swift 6)
        let reachable = session.isReachable
        Task { @MainActor in
            self.isWatchReachable = reachable
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        WCSession.default.activate()
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any]
    ) {
        // Only post notification if action key is present.
        // Capture only the action string (Sendable) across the isolation boundary.
        guard message["action"] != nil else { return }
        let notificationName = Notification.Name.watchAction
        Task { @MainActor in
            NotificationCenter.default.post(
                name: notificationName,
                object: nil
            )
        }
    }
}

// MARK: - Notification Name

extension Notification.Name {
    static let watchAction = Notification.Name("com.kinetics.watchAction")
}
