import Foundation
import WatchConnectivity
import HealthKit
import WatchKit

// MARK: - WatchSessionManager

@MainActor
final class WatchSessionManager: NSObject, ObservableObject {
    static let shared = WatchSessionManager()

    // MARK: Published State

    @Published var activeModule: String? = nil
    @Published var isSessionActive = false
    @Published var heartRate: Double = 0
    @Published var distance: Double = 0
    @Published var pace: Double = 0
    @Published var elapsedSeconds: Int = 0
    @Published var sessionMetrics: [String: Double] = [:]

    // MARK: Private Properties

    private let healthStore = HKHealthStore()
    private var heartRateQuery: HKQuery?
    private var sessionTimer: Timer?

    // MARK: Init

    private override init() {
        super.init()
        setupWatchConnectivity()
    }

    // MARK: Connectivity Setup

    private func setupWatchConnectivity() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    // MARK: Session Control

    func startSession(module: String) {
        isSessionActive = true
        activeModule = module
        elapsedSeconds = 0
        startHeartRateMonitoring()
        sessionTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.elapsedSeconds += 1
            }
        }
        sendToPhone(["action": "start", "module": module])
        WKInterfaceDevice.current().play(.start)
    }

    func pauseSession() {
        isSessionActive = false
        sessionTimer?.invalidate()
        sendToPhone(["action": "pause"])
        WKInterfaceDevice.current().play(.stop)
    }

    func endSession() {
        isSessionActive = false
        activeModule = nil
        sessionTimer?.invalidate()
        sessionTimer = nil
        heartRate = 0
        distance = 0
        stopHeartRateMonitoring()
        sendToPhone(["action": "end"])
        WKInterfaceDevice.current().play(.success)
    }

    // MARK: Messaging

    private func sendToPhone(_ message: [String: Any]) {
        guard WCSession.default.isReachable else { return }
        WCSession.default.sendMessage(message, replyHandler: nil, errorHandler: nil)
    }

    // MARK: Heart Rate

    private func startHeartRateMonitoring() {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let hrType = HKQuantityType(.heartRate)
        // Authorization request is non-isolated — dispatch back to main actor
        let store = healthStore
        Task {
            try? await store.requestAuthorization(toShare: [], read: [hrType])
            await MainActor.run {
                self.beginHeartRateQuery(type: hrType)
            }
        }
    }

    private func beginHeartRateQuery(type: HKQuantityType) {
        let store = healthStore
        let query = HKAnchoredObjectQuery(
            type: type,
            predicate: nil,
            anchor: nil,
            limit: HKObjectQueryNoLimit
        ) { [weak self] _, samples, _, _, _ in
            Task { @MainActor in
                self?.processHeartRateSamples(samples)
            }
        }
        query.updateHandler = { [weak self] _, samples, _, _, _ in
            Task { @MainActor in
                self?.processHeartRateSamples(samples)
            }
        }
        store.execute(query)
        heartRateQuery = query
    }

    private func processHeartRateSamples(_ samples: [HKSample]?) {
        guard let samples = samples as? [HKQuantitySample],
              let latest = samples.last else { return }
        heartRate = latest.quantity.doubleValue(for: HKUnit(from: "count/min"))
    }

    private func stopHeartRateMonitoring() {
        if let query = heartRateQuery {
            healthStore.stop(query)
            heartRateQuery = nil
        }
    }

    // MARK: Formatting

    var formattedElapsed: String {
        let h = elapsedSeconds / 3600
        let m = (elapsedSeconds % 3600) / 60
        let s = elapsedSeconds % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%02d:%02d", m, s)
    }
}

// MARK: - WCSessionDelegate

extension WatchSessionManager: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {}

    nonisolated func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any]
    ) {
        // Extract Sendable values before crossing actor boundary (Swift 6 strict concurrency)
        let hr = message["heartRate"] as? Double
        let dist = message["distance"] as? Double
        let pace = message["pace"] as? Double
        let metrics = message["metrics"] as? [String: Double]
        Task { @MainActor in
            if let hr { self.heartRate = hr }
            if let dist { self.distance = dist }
            if let pace { self.pace = pace }
            if let metrics { self.sessionMetrics = metrics }
        }
    }
}
