import FirebaseAnalytics
import FirebaseCore
import FirebaseFirestore
import Foundation

// MARK: - SocialRepository

/// Handles all Firestore reads and writes for the Kinetics social layer.
///
/// **Firestore schema**
/// ```
/// users/{uid}                                      ← UserProfile
/// activity/{activityId}                            ← FeedItem (global collection)
/// activity/{activityId}/kudos/{uid}                ← kudos presence doc
/// activity/{activityId}/comments/{commentId}       ← ActivityComment
/// ```
///
/// **Encoding strategy**
/// All model types are serialised via a JSON round-trip:
/// `JSONEncoder` → `Data` → `JSONSerialization` → `[String: Any]` stored under
/// the key `"data"` in each Firestore document. `Date` values are encoded as
/// milliseconds since 1970. This keeps every model free of Firestore conformances
/// and makes the repository straightforward to test with any `Codable` snapshot.
///
/// **Firebase guard**
/// Every public method checks `isFirebaseReady` and returns a sensible empty
/// value (or no-ops) when the placeholder `GoogleService-Info.plist` is active,
/// so development builds run without a live Firebase project.
@MainActor
final class SocialRepository {

    // MARK: - Singleton

    static let shared = SocialRepository()

    // MARK: - Private

    private let db = Firestore.firestore()

    /// `true` only when a real Firebase app has been configured.
    private var isFirebaseReady: Bool { FirebaseApp.app() != nil }

    private init() {}

    // MARK: - Feed

    /// Fetches the most recent `limit` feed items from the global `activity`
    /// collection, ordered by `postedAt` descending.
    ///
    /// Documents that fail to decode are silently skipped so a single corrupt
    /// document cannot surface an error to the UI.
    ///
    /// Returns an empty array when Firebase is not configured.
    func fetchFeed(limit: Int = 30) async throws -> [FeedItem] {
        guard isFirebaseReady else { return [] }

        let snapshot = try await db
            .collection("activity")
            .order(by: "postedAt", descending: true)
            .limit(to: limit)
            .getDocuments()

        return snapshot.documents.compactMap { document in
            try? decodeFeedItem(from: document.data())
        }
    }

    // MARK: - User Activities

    /// Fetches the most recent `limit` feed items posted by `userId`, ordered
    /// by `postedAt` descending.
    ///
    /// Returns an empty array when Firebase is not configured.
    func fetchUserActivities(userId: String, limit: Int = 20) async throws -> [FeedItem] {
        guard isFirebaseReady else { return [] }

        let snapshot = try await db
            .collection("activity")
            .whereField("userId", isEqualTo: userId)
            .order(by: "postedAt", descending: true)
            .limit(to: limit)
            .getDocuments()

        return snapshot.documents.compactMap { document in
            try? decodeFeedItem(from: document.data())
        }
    }

    // MARK: - Post Activity

    /// Writes a `FeedItem` to `activity/{item.id}` in Firestore.
    ///
    /// Uses the item's pre-populated UUID as the document ID so the write can
    /// be performed optimistically before the server acknowledges it.
    ///
    /// No-ops when Firebase is not configured.
    func postActivity(_ item: FeedItem) async throws {
        guard isFirebaseReady else { return }

        let dict = try encodeFeedItem(item)
        try await db
            .collection("activity")
            .document(item.id)
            .setData(["data": dict, "postedAt": item.postedAt.timeIntervalSince1970 * 1_000])

        logActivity(event: "posted", parameters: [
            "item_type": item.itemType.rawValue as NSString,
            "activity_type": item.activityType as NSString
        ])
    }

    // MARK: - Delete Activity

    /// Deletes the `activity/{activityId}` document.
    ///
    /// Verifies that `userId` matches the item's owner before deleting to
    /// prevent one user from removing another user's posts.
    ///
    /// Throws `SocialRepositoryError.permissionDenied` when the document exists
    /// but belongs to a different user.
    ///
    /// No-ops when Firebase is not configured.
    func deleteActivity(activityId: String, userId: String) async throws {
        guard isFirebaseReady else { return }

        let ref = db.collection("activity").document(activityId)
        let doc = try await ref.getDocument()

        guard doc.exists else { return }

        if let data = doc.data()?["data"] as? [String: Any],
           let ownerId = data["userId"] as? String,
           ownerId != userId {
            throw SocialRepositoryError.permissionDenied
        }

        try await ref.delete()

        logActivity(event: "deleted", parameters: [
            "activity_id": activityId as NSString
        ])
    }

    // MARK: - Kudos

    /// Toggles the kudos state for `fromUserId` on `activityId`.
    ///
    /// - If a kudos document already exists for this user, it is deleted (unlike).
    /// - If no kudos document exists, one is created (like).
    ///
    /// Returns the **new** liked state (`true` = now liked, `false` = now unliked).
    ///
    /// Returns `false` without throwing when Firebase is not configured.
    @discardableResult
    func toggleKudos(activityId: String, fromUserId: String) async throws -> Bool {
        guard isFirebaseReady else { return false }

        let kudosRef = db
            .collection("activity")
            .document(activityId)
            .collection("kudos")
            .document(fromUserId)

        let existing = try await kudosRef.getDocument()

        if existing.exists {
            try await kudosRef.delete()
            logActivity(event: "kudos_removed", parameters: [
                "activity_id": activityId as NSString
            ])
            return false
        } else {
            try await kudosRef.setData([
                "userId": fromUserId,
                "likedAt": Date().timeIntervalSince1970 * 1_000
            ])
            logActivity(event: "kudos_added", parameters: [
                "activity_id": activityId as NSString
            ])
            return true
        }
    }

    /// Returns the total number of kudos documents in the `kudos` sub-collection
    /// for `activityId`.
    ///
    /// Returns `0` when Firebase is not configured.
    func fetchKudosCount(activityId: String) async throws -> Int {
        guard isFirebaseReady else { return 0 }

        let snapshot = try await db
            .collection("activity")
            .document(activityId)
            .collection("kudos")
            .getDocuments()

        return snapshot.documents.count
    }

    // MARK: - Comments

    /// Writes an `ActivityComment` to `activity/{activityId}/comments/{comment.id}`.
    ///
    /// No-ops when Firebase is not configured.
    func postComment(_ comment: ActivityComment, activityId: String) async throws {
        guard isFirebaseReady else { return }

        let dict = try encodeComment(comment)
        try await db
            .collection("activity")
            .document(activityId)
            .collection("comments")
            .document(comment.id)
            .setData(["data": dict])

        logActivity(event: "comment_posted", parameters: [
            "activity_id": activityId as NSString
        ])
    }

    /// Fetches all comments for `activityId`, ordered by `postedAt` ascending.
    ///
    /// Documents that fail to decode are silently skipped.
    ///
    /// Returns an empty array when Firebase is not configured.
    func fetchComments(activityId: String) async throws -> [ActivityComment] {
        guard isFirebaseReady else { return [] }

        let snapshot = try await db
            .collection("activity")
            .document(activityId)
            .collection("comments")
            .order(by: "postedAt", descending: false)
            .getDocuments()

        return snapshot.documents.compactMap { document in
            try? decodeComment(from: document.data())
        }
    }

    // MARK: - User Profile

    /// Fetches the `UserProfile` stored at `users/{userId}`.
    ///
    /// Throws `SocialRepositoryError.notFound` when the document does not exist.
    func fetchProfile(userId: String) async throws -> UserProfile {
        guard isFirebaseReady else { throw SocialRepositoryError.firebaseNotReady }

        let doc = try await db
            .collection("users")
            .document(userId)
            .getDocument()

        guard doc.exists, let raw = doc.data()?["data"] as? [String: Any] else {
            throw SocialRepositoryError.notFound
        }

        return try decodeProfile(from: raw)
    }

    /// Writes a `UserProfile` to `users/{profile.id}`, creating or overwriting
    /// the document.
    ///
    /// No-ops when Firebase is not configured.
    func updateProfile(_ profile: UserProfile) async throws {
        guard isFirebaseReady else { return }

        let dict = try encodeProfile(profile)
        try await db
            .collection("users")
            .document(profile.id)
            .setData(["data": dict])

        logActivity(event: "profile_updated", parameters: [
            "user_id": profile.id as NSString
        ])
    }

    // MARK: - Private: Encode / Decode — FeedItem

    private func encodeFeedItem(_ item: FeedItem) throws -> [String: Any] {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970

        let data = try encoder.encode(item)

        guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SocialRepositoryError.encodingFailed
        }
        return dict
    }

    private func decodeFeedItem(from wrapper: [String: Any]) throws -> FeedItem {
        guard let dict = wrapper["data"] as? [String: Any] else {
            throw SocialRepositoryError.decodingFailed
        }

        let jsonData = try JSONSerialization.data(withJSONObject: dict)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970

        return try decoder.decode(FeedItem.self, from: jsonData)
    }

    // MARK: - Private: Encode / Decode — ActivityComment

    private func encodeComment(_ comment: ActivityComment) throws -> [String: Any] {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970

        let data = try encoder.encode(comment)

        guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SocialRepositoryError.encodingFailed
        }
        return dict
    }

    private func decodeComment(from wrapper: [String: Any]) throws -> ActivityComment {
        guard let dict = wrapper["data"] as? [String: Any] else {
            throw SocialRepositoryError.decodingFailed
        }

        let jsonData = try JSONSerialization.data(withJSONObject: dict)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970

        return try decoder.decode(ActivityComment.self, from: jsonData)
    }

    // MARK: - Private: Encode / Decode — UserProfile

    private func encodeProfile(_ profile: UserProfile) throws -> [String: Any] {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970

        let data = try encoder.encode(profile)

        guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SocialRepositoryError.encodingFailed
        }
        return dict
    }

    private func decodeProfile(from dict: [String: Any]) throws -> UserProfile {
        let jsonData = try JSONSerialization.data(withJSONObject: dict)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970

        return try decoder.decode(UserProfile.self, from: jsonData)
    }

    // MARK: - Private: Analytics

    /// Fires a `social_{event}` event via Firebase Analytics.
    ///
    /// All parameters must be `NSString` or `NSNumber` to satisfy the Analytics SDK.
    private func logActivity(event: String, parameters: [String: NSObject] = [:]) {
        guard isFirebaseReady else { return }
        Analytics.logEvent("social_\(event)", parameters: parameters)
    }
}

// MARK: - SocialRepositoryError

/// Typed errors thrown by `SocialRepository` operations.
enum SocialRepositoryError: LocalizedError {

    case firebaseNotReady
    case notFound
    case permissionDenied
    case encodingFailed
    case decodingFailed

    var errorDescription: String? {
        switch self {
        case .firebaseNotReady:
            "Firebase is not configured. Check GoogleService-Info.plist."
        case .notFound:
            "The requested document does not exist in Firestore."
        case .permissionDenied:
            "You do not have permission to modify this activity."
        case .encodingFailed:
            "Failed to encode model data for Firestore."
        case .decodingFailed:
            "Failed to decode model data from Firestore."
        }
    }
}
