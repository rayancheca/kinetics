import FirebaseAnalytics
import FirebaseCore
import FirebaseFirestore
import Foundation

// MARK: - SessionRepository

/// Persists `SessionResult` documents to Firestore and emits Firebase Analytics
/// events for module engagement tracking (the Phase 2 telemetry pipeline).
///
/// Uses a JSON round-trip encode/decode strategy instead of Firestore's native
/// `Codable` support, keeping the model layer free of Firestore SDK types.
///
/// Sessions are stored under `users/{userId}/sessions/{sessionId}` so Firestore
/// security rules can scope reads and writes to the owning user only.
///
/// All Firebase calls are guarded by `isFirebaseReady` so the repository
/// silently no-ops when the placeholder `GoogleService-Info.plist` is active.
final class SessionRepository: Sendable {

    // MARK: - Singleton

    static let shared = SessionRepository()

    // MARK: - Private

    /// Returns `true` only when a real Firebase app has been configured.
    private var isFirebaseReady: Bool { FirebaseApp.app() != nil }

    private init() {
        configurePersistence()
    }

    // MARK: - Save

    /// Writes a completed session to Firestore under the user-scoped path
    /// `users/{userId}/sessions/{sessionId}` and fires the
    /// `module_session_completed` Analytics event.
    /// No-ops silently when Firebase is not configured.
    func save(_ result: SessionResult) async throws {
        guard isFirebaseReady else { return }

        let db = Firestore.firestore()
        let data = try encodeToDict(result)

        try await db
            .collection("users")
            .document(result.userId)
            .collection("sessions")
            .document(result.id)
            .setData(data)

        logSessionCompleted(result)
    }

    // MARK: - Fetch

    /// Returns the most recent `limit` sessions belonging to `userId`, ordered
    /// newest-first. The query is scoped to the user's subcollection, so no
    /// client-side `whereField` filter is needed.
    /// Returns an empty array when Firebase is not configured.
    func fetchSessions(for userId: String, limit: Int = 20) async throws -> [SessionResult] {
        guard isFirebaseReady else { return [] }

        let db = Firestore.firestore()
        let snapshot = try await db
            .collection("users")
            .document(userId)
            .collection("sessions")
            .order(by: "startedAt", descending: true)
            .limit(to: limit)
            .getDocuments()

        return snapshot.documents.compactMap { document in
            try? decodeFromDict(document.data())
        }
    }

    // MARK: - Analytics: Session Started

    /// Call this when the user begins a session, before recording starts.
    /// Fires `module_session_started` with the sport name for funnel tracking.
    func logSessionStarted(sport: SportType) {
        guard isFirebaseReady else { return }
        Analytics.logEvent("module_session_started", parameters: [
            "sport": sport.rawValue as NSString,
            "module_name": sport.displayName as NSString
        ])
    }

    // MARK: - Private: Persistence

    /// Enables Firestore's on-device persistent cache so sessions are readable
    /// offline and writes are queued until connectivity is restored.
    /// No-ops silently when Firebase is not configured.
    private func configurePersistence() {
        guard isFirebaseReady else { return }
        let settings = FirestoreSettings()
        settings.cacheSettings = PersistentCacheSettings()
        Firestore.firestore().settings = settings
    }

    // MARK: - Private: Analytics

    private func logSessionCompleted(_ result: SessionResult) {
        Analytics.logEvent("module_session_completed", parameters: [
            "sport": result.sport.rawValue as NSString,
            "duration_seconds": result.duration as NSNumber,
            "module_name": result.sport.displayName as NSString
        ])
    }

    // MARK: - Private: Encode / Decode

    /// Converts a `SessionResult` to a `[String: Any]` dictionary suitable for
    /// `Firestore.setData(_:)`. Uses `JSONEncoder` → `JSONSerialization` so the
    /// model layer stays free of Firestore-specific conformances.
    private func encodeToDict(_ result: SessionResult) throws -> [String: Any] {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        let data = try encoder.encode(result)

        guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw RepositoryError.encodingFailed
        }
        return dict
    }

    /// Reconstructs a `SessionResult` from a raw Firestore document dictionary.
    private func decodeFromDict(_ dict: [String: Any]) throws -> SessionResult {
        let data = try JSONSerialization.data(withJSONObject: dict)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return try decoder.decode(SessionResult.self, from: data)
    }
}

// MARK: - RepositoryError

enum RepositoryError: LocalizedError {
    case encodingFailed
    case decodingFailed

    var errorDescription: String? {
        switch self {
        case .encodingFailed: "Failed to encode session data for Firestore."
        case .decodingFailed: "Failed to decode session data from Firestore."
        }
    }
}
