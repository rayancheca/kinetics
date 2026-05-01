import FirebaseAnalytics
import FirebaseCore
import FirebaseFirestore
import Foundation

// MARK: - WorkoutRepository

/// Persists `WorkoutResult` documents to Firestore under the user-scoped path
/// `users/{userId}/workouts/{workoutId}` and fires Firebase Analytics events
/// for Track module engagement tracking (the Phase 2 telemetry pipeline).
///
/// Uses a JSON round-trip encode/decode strategy — `JSONEncoder` serialises the
/// model to `Data`, then `JSONSerialization` converts it to the `[String: Any]`
/// dictionary that Firestore's `setData(_:)` expects. This keeps `WorkoutResult`
/// free of Firestore-specific conformances and makes the repository trivially
/// testable with any `Codable` snapshot.
///
/// All Firebase calls are guarded by `isFirebaseReady` so the repository
/// silently no-ops when the placeholder `GoogleService-Info.plist` is active.
///
/// Fetch queries are ordered by `startedAt` descending and limited to the 50
/// most recent workouts to avoid unbounded reads as a user's history grows.
@MainActor
final class WorkoutRepository {

    // MARK: - Singleton

    static let shared = WorkoutRepository()

    // MARK: - Private

    private var db: Firestore { Firestore.firestore() }

    /// Returns `true` only when a real Firebase app has been configured.
    private var isFirebaseReady: Bool { FirebaseApp.app() != nil }

    private init() {}

    // MARK: - Save

    /// Writes a completed workout to Firestore under `users/{userId}/workouts/{workoutId}`
    /// using the workout's pre-populated UUID as the document ID.
    ///
    /// An `isFirebaseReady` guard makes this a no-op against the placeholder plist,
    /// so development builds run without a live Firebase project.
    func save(_ workout: WorkoutResult) async throws {
        guard isFirebaseReady else { return }

        let data = try encodeToDict(workout)

        try await db
            .collection("users")
            .document(workout.userId)
            .collection("workouts")
            .document(workout.id)
            .setData(data)
    }

    // MARK: - Fetch

    /// Returns the 50 most recent workouts for `userId`, ordered newest-first.
    ///
    /// Documents that fail to decode are silently skipped via `compactMap` so a single
    /// corrupt document cannot surface an error to the UI.
    ///
    /// Returns an empty array when Firebase is not configured.
    func fetchAll(userId: String) async throws -> [WorkoutResult] {
        guard isFirebaseReady else { return [] }

        let snapshot = try await db
            .collection("users")
            .document(userId)
            .collection("workouts")
            .order(by: "startedAt", descending: true)
            .limit(to: 50)
            .getDocuments()

        return snapshot.documents.compactMap { document in
            try? decodeFromDict(document.data())
        }
    }

    // MARK: - Delete

    /// Removes a single workout document from the user-scoped Firestore subcollection.
    ///
    /// No-ops silently when Firebase is not configured.
    func delete(id: String, userId: String) async throws {
        guard isFirebaseReady else { return }

        try await db
            .collection("users")
            .document(userId)
            .collection("workouts")
            .document(id)
            .delete()
    }

    // MARK: - Analytics

    /// Fires a `workout_started` event with the `activity_type` parameter.
    ///
    /// Call this at the moment the athlete initiates a session — before GPS lock
    /// is confirmed — so the funnel captures intent, not just completion.
    ///
    /// No-ops silently when Firebase is not configured.
    func logWorkoutStarted(activityType: WorkoutActivityType) {
        guard isFirebaseReady else { return }
        Analytics.logEvent("workout_started", parameters: [
            "activity_type": activityType.rawValue as NSString,
            "activity_display_name": activityType.displayName as NSString
        ])
    }

    // MARK: - Private: Encode / Decode

    /// Converts a `WorkoutResult` to a `[String: Any]` dictionary suitable for
    /// `Firestore.setData(_:)`.
    ///
    /// `Date` values are encoded as milliseconds since 1970 (a plain `Double`) so
    /// Firestore stores them as numbers. Consumers reading via `decodeFromDict`
    /// use the matching `.millisecondsSince1970` decoder strategy.
    ///
    /// `splits` are serialised as an array of dictionaries; `routeLatitudes`,
    /// `routeLongitudes`, and `segmentPaces` are stored as native Firestore arrays
    /// of `Double`, which round-trip without any special handling.
    private func encodeToDict(_ workout: WorkoutResult) throws -> [String: Any] {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970

        let data = try encoder.encode(workout)

        guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw WorkoutRepositoryError.encodingFailed
        }
        return dict
    }

    /// Reconstructs a `WorkoutResult` from a raw Firestore document dictionary.
    ///
    /// Throws `WorkoutRepositoryError.decodingFailed` when the dictionary cannot be
    /// deserialised — callers that use `compactMap` will simply skip the document.
    private func decodeFromDict(_ dict: [String: Any]) throws -> WorkoutResult {
        let data = try JSONSerialization.data(withJSONObject: dict)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970

        return try decoder.decode(WorkoutResult.self, from: data)
    }
}

// MARK: - WorkoutRepositoryError

/// Typed errors surfaced by `WorkoutRepository` encode / decode operations.
enum WorkoutRepositoryError: LocalizedError {

    case encodingFailed
    case decodingFailed

    var errorDescription: String? {
        switch self {
        case .encodingFailed: "Failed to encode workout data for Firestore."
        case .decodingFailed: "Failed to decode workout data from Firestore."
        }
    }
}
