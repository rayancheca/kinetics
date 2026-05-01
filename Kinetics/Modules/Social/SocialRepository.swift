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

    private var db: Firestore { Firestore.firestore() }

    /// `true` only when a real Firebase app has been configured.
    private var isFirebaseReady: Bool { FirebaseApp.app() != nil }

    private init() {}

    // MARK: - Feed

    /// Fetches the most recent `limit` feed items from the global `activity`
    /// collection, ordered by `postedAt` descending.
    ///
    /// When `after` is provided, the query returns only items with a `postedAt`
    /// timestamp (milliseconds since epoch) strictly less than that value,
    /// enabling cursor-based pagination.
    ///
    /// Documents that fail to decode are silently skipped so a single corrupt
    /// document cannot surface an error to the UI.
    ///
    /// Returns an empty array when Firebase is not configured.
    func fetchFeed(after lastPostedAt: Double? = nil, limit: Int = 15) async throws -> [FeedItem] {
        guard isFirebaseReady else { return [] }

        var query = db
            .collection("activity")
            .order(by: "postedAt", descending: true)
            .limit(to: limit)

        if let cursor = lastPostedAt {
            query = query.whereField("postedAt", isLessThan: cursor)
        }

        let snapshot = try await query.getDocuments()

        return snapshot.documents.compactMap { document in
            try? decodeFeedItem(from: document.data())
        }
    }

    /// Fetches the user IDs that `userId` is following.
    ///
    /// Returns an empty array when Firebase is not configured.
    func fetchFollowingIds(for userId: String) async throws -> [String] {
        guard isFirebaseReady else { return [] }
        let snap = try await db
            .collection("users").document(userId)
            .collection("following")
            .getDocuments()
        return snap.documents.compactMap { $0.data()["userId"] as? String }
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

    // MARK: - Post (alias used by PostComposerViewModel)

    /// Convenience wrapper around `postActivity(_:)` used by `PostComposerViewModel`.
    func post(item: FeedItem) async throws {
        try await postActivity(item)
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

    // MARK: - CommentModel Helpers

    /// Writes a new comment (as `CommentModel`) to the Firestore comments sub-collection.
    ///
    /// No-ops when Firebase is not configured.
    func addComment(to postId: String, text: String, userId: String, displayName: String) async throws {
        guard isFirebaseReady else { return }

        let comment = CommentModel(
            id: UUID().uuidString,
            userId: userId,
            displayName: displayName,
            text: text,
            createdAt: Date()
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        let data = try encoder.encode(comment)
        guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SocialRepositoryError.encodingFailed
        }

        try await db
            .collection("activity")
            .document(postId)
            .collection("comments")
            .document(comment.id)
            .setData(["data": dict])
    }

    /// Fetches all `CommentModel` comments for `postId`, ordered by `createdAt` ascending.
    ///
    /// Returns an empty array when Firebase is not configured.
    func fetchCommentModels(for postId: String) async throws -> [CommentModel] {
        guard isFirebaseReady else { return [] }

        let snapshot = try await db
            .collection("activity")
            .document(postId)
            .collection("comments")
            .order(by: "createdAt", descending: false)
            .getDocuments()

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970

        return snapshot.documents.compactMap { doc -> CommentModel? in
            guard let dict = doc.data()["data"] as? [String: Any],
                  let jsonData = try? JSONSerialization.data(withJSONObject: dict) else { return nil }
            return try? decoder.decode(CommentModel.self, from: jsonData)
        }
    }

    // MARK: - Reactions

    /// Adds a typed reaction from `userId` to `activityId`.
    ///
    /// Firestore path: `kudos/{activityId}/reactions/{userId}`
    /// Document: `{"type": reactionType, "addedAt": millisecondTimestamp}`
    ///
    /// No-ops when Firebase is not configured.
    func addReaction(_ type: String, to activityId: String, userId: String) async throws {
        guard isFirebaseReady else { return }

        try await db
            .collection("kudos")
            .document(activityId)
            .collection("reactions")
            .document(userId)
            .setData([
                "type": type,
                "addedAt": Date().timeIntervalSince1970 * 1_000
            ])

        logActivity(event: "reaction_added", parameters: [
            "activity_id": activityId as NSString,
            "reaction_type": type as NSString
        ])
    }

    /// Removes a typed reaction from `userId` on `activityId`.
    ///
    /// No-ops when Firebase is not configured.
    func removeReaction(_ type: String, from activityId: String, userId: String) async throws {
        guard isFirebaseReady else { return }

        try await db
            .collection("kudos")
            .document(activityId)
            .collection("reactions")
            .document(userId)
            .delete()

        logActivity(event: "reaction_removed", parameters: [
            "activity_id": activityId as NSString,
            "reaction_type": type as NSString
        ])
    }

    // MARK: - postComment convenience (CommentSheetView)

    /// Posts a comment using individual fields — convenience wrapper for `CommentSheetView`.
    ///
    /// No-ops when Firebase is not configured.
    func postComment(
        activityId: String,
        userId: String,
        displayName: String,
        username: String,
        text: String
    ) async throws {
        let comment = ActivityComment(
            id: UUID().uuidString,
            userId: userId,
            displayName: displayName,
            avatarURL: "",
            text: text,
            postedAt: Date()
        )
        try await postComment(comment, activityId: activityId)
    }

    /// Fetches comments for the given activity ID (alias matching `CommentSheetView` call-site).
    ///
    /// Returns an empty array when Firebase is not configured.
    func fetchComments(for activityId: String) async throws -> [ActivityComment] {
        try await fetchComments(activityId: activityId)
    }

    // MARK: - Stories

    /// Derives story rings from recent feed items for the given `userId` and any followed users.
    ///
    /// In Phase 1 this is client-side — returns the most recent session from each unique
    /// poster in the last 24h feed batch. No separate Firestore stories collection is required.
    ///
    /// Returns an empty array when Firebase is not configured.
    func fetchStories(for userId: String) async throws -> [StoryModel] {
        guard isFirebaseReady else { return [] }

        let since = Date(timeIntervalSinceNow: -86_400)

        let snapshot = try await db
            .collection("activity")
            .whereField("postedAt", isGreaterThan: since.timeIntervalSince1970 * 1_000)
            .order(by: "postedAt", descending: true)
            .limit(to: 50)
            .getDocuments()

        // One story per unique userId, most recent first.
        var seen = Set<String>()
        var stories: [StoryModel] = []

        for doc in snapshot.documents {
            guard let item = try? decodeFeedItem(from: doc.data()) else { continue }
            guard !seen.contains(item.userId) else { continue }
            seen.insert(item.userId)

            let emoji = sportEmoji(for: item.activityType)
            let story = StoryModel(
                id: "story_\(item.id)",
                userId: item.userId,
                displayName: item.displayName,
                avatarEmoji: emoji,
                sport: item.activityType,
                sessionId: item.id,
                createdAt: item.postedAt,
                seen: false
            )
            stories.append(story)
        }

        return stories
    }

    // MARK: - Social Graph

    /// Returns the current follow status between `currentUserId` and `targetUserId`.
    ///
    /// Returns `.notFollowing` when Firebase is not configured.
    func followStatus(currentUserId: String, targetUserId: String) async -> FollowStatus {
        guard isFirebaseReady else { return .notFollowing }
        if currentUserId == targetUserId { return .self_ }

        let followDoc = try? await db
            .collection("users").document(currentUserId)
            .collection("following").document(targetUserId)
            .getDocument()
        if followDoc?.exists == true { return .following }

        let requestDoc = try? await db
            .collection("users").document(targetUserId)
            .collection("followRequests").document(currentUserId)
            .getDocument()
        if requestDoc?.exists == true { return .requested }

        return .notFollowing
    }

    /// Follows `targetUserId` from `currentUserId`.
    ///
    /// - For public accounts the following/followers documents are written immediately.
    /// - For private accounts a follow-request document is written instead.
    ///
    /// No-ops when Firebase is not configured.
    func follow(
        currentUserId: String,
        currentDisplayName: String,
        currentUsername: String,
        targetUserId: String,
        targetDisplayName: String,
        targetUsername: String,
        isTargetPublic: Bool
    ) async throws {
        guard isFirebaseReady else { return }
        let now = Date().timeIntervalSince1970 * 1_000

        if isTargetPublic {
            let followData: [String: Any] = [
                "userId": targetUserId,
                "displayName": targetDisplayName,
                "username": targetUsername,
                "avatarURL": "",
                "primarySport": "",
                "followedAt": now
            ]
            try await db
                .collection("users").document(currentUserId)
                .collection("following").document(targetUserId)
                .setData(followData)

            let followerData: [String: Any] = [
                "userId": currentUserId,
                "displayName": currentDisplayName,
                "username": currentUsername,
                "avatarURL": "",
                "primarySport": "",
                "followedAt": now
            ]
            try await db
                .collection("users").document(targetUserId)
                .collection("followers").document(currentUserId)
                .setData(followerData)

            logActivity(event: "follow", parameters: [
                "target_user_id": targetUserId as NSString
            ])
        } else {
            let requestData: [String: Any] = [
                "userId": currentUserId,
                "displayName": currentDisplayName,
                "username": currentUsername,
                "avatarURL": "",
                "primarySport": "",
                "requestedAt": now
            ]
            try await db
                .collection("users").document(targetUserId)
                .collection("followRequests").document(currentUserId)
                .setData(requestData)

            logActivity(event: "follow_request_sent", parameters: [
                "target_user_id": targetUserId as NSString
            ])
        }
    }

    /// Removes the follow relationship between `currentUserId` and `targetUserId`.
    ///
    /// Deletes both the following doc on the current user and the followers doc on the target.
    /// No-ops when Firebase is not configured.
    func unfollow(currentUserId: String, targetUserId: String) async throws {
        guard isFirebaseReady else { return }
        try await db
            .collection("users").document(currentUserId)
            .collection("following").document(targetUserId)
            .delete()
        try await db
            .collection("users").document(targetUserId)
            .collection("followers").document(currentUserId)
            .delete()

        logActivity(event: "unfollow", parameters: [
            "target_user_id": targetUserId as NSString
        ])
    }

    /// Withdraws a pending follow request sent by `currentUserId` to `targetUserId`.
    ///
    /// No-ops when Firebase is not configured.
    func cancelFollowRequest(currentUserId: String, targetUserId: String) async throws {
        guard isFirebaseReady else { return }
        try await db
            .collection("users").document(targetUserId)
            .collection("followRequests").document(currentUserId)
            .delete()

        logActivity(event: "follow_request_cancelled", parameters: [
            "target_user_id": targetUserId as NSString
        ])
    }

    /// Fetches all followers of `userId`.
    ///
    /// Returns an empty array when Firebase is not configured.
    func fetchFollowers(userId: String) async throws -> [FollowRelationship] {
        guard isFirebaseReady else { return [] }
        let snap = try await db
            .collection("users").document(userId)
            .collection("followers")
            .getDocuments()
        return snap.documents.compactMap { decodeFollowRelationship(from: $0.data()) }
    }

    /// Fetches all accounts that `userId` is following.
    ///
    /// Returns an empty array when Firebase is not configured.
    func fetchFollowing(userId: String) async throws -> [FollowRelationship] {
        guard isFirebaseReady else { return [] }
        let snap = try await db
            .collection("users").document(userId)
            .collection("following")
            .getDocuments()
        return snap.documents.compactMap { decodeFollowRelationship(from: $0.data()) }
    }

    /// Returns the number of followers for `userId`.
    ///
    /// Returns `0` when Firebase is not configured.
    func fetchFollowerCount(userId: String) async -> Int {
        guard isFirebaseReady else { return 0 }
        let snap = try? await db
            .collection("users").document(userId)
            .collection("followers")
            .getDocuments()
        return snap?.documents.count ?? 0
    }

    /// Returns the number of accounts `userId` is following.
    ///
    /// Returns `0` when Firebase is not configured.
    func fetchFollowingCount(userId: String) async -> Int {
        guard isFirebaseReady else { return 0 }
        let snap = try? await db
            .collection("users").document(userId)
            .collection("following")
            .getDocuments()
        return snap?.documents.count ?? 0
    }

    // MARK: - Private Helpers

    private func decodeFollowRelationship(from d: [String: Any]) -> FollowRelationship? {
        guard
            let uid = d["userId"] as? String,
            let name = d["displayName"] as? String,
            let uname = d["username"] as? String,
            let ts = d["followedAt"] as? Double
        else { return nil }
        return FollowRelationship(
            userId: uid,
            displayName: name,
            username: uname,
            avatarURL: d["avatarURL"] as? String ?? "",
            primarySport: d["primarySport"] as? String ?? "",
            followedAt: Date(timeIntervalSince1970: ts / 1_000)
        )
    }

    private func sportEmoji(for activityType: String) -> String {
        switch activityType {
        case "striking":   return "🥊"
        case "grappling":  return "🤼"
        case "iron", "ironTracker", "gym": return "🏋️"
        case "wall":       return "🧗"
        case "run":        return "🏃"
        case "ride":       return "🚴"
        default:           return "⚡️"
        }
    }

    // MARK: - Search & Discover

    /// Searches for users whose username starts with the lowercased `query` string.
    ///
    /// Uses Firestore prefix matching: `startAt(query) endAt(query + "\u{f8ff}")`.
    /// Returns an empty array when Firebase is not configured.
    func searchUsers(query: String) async throws -> [UserProfile] {
        guard isFirebaseReady else { return [] }
        let lower = query.lowercased()
        let snapshot = try await db
            .collection("users")
            .order(by: "data.username")
            .start(at: [lower])
            .end(at: [lower + "\u{f8ff}"])
            .limit(to: 20)
            .getDocuments()
        return snapshot.documents.compactMap { doc -> UserProfile? in
            guard let raw = doc.data()["data"] as? [String: Any] else { return nil }
            return try? decodeProfile(from: raw)
        }
    }

    /// Fetches a `UserProfile` for `userId` or returns `nil` when not found.
    ///
    /// Returns `nil` when Firebase is not configured.
    func fetchUserProfile(userId: String) async throws -> UserProfile? {
        guard isFirebaseReady else { return nil }
        let doc = try await db.collection("users").document(userId).getDocument()
        guard doc.exists, let raw = doc.data()?["data"] as? [String: Any] else { return nil }
        return try? decodeProfile(from: raw)
    }

    /// Returns the number of activity documents posted by `userId`.
    ///
    /// Returns `0` when Firebase is not configured.
    func fetchUserPostCount(userId: String) async throws -> Int {
        guard isFirebaseReady else { return 0 }
        let snap = try await db
            .collection("activity")
            .whereField("userId", isEqualTo: userId)
            .getDocuments()
        return snap.documents.count
    }

    /// Returns up to `limit` user profiles sorted by `totalWorkouts` descending.
    ///
    /// Returns an empty array when Firebase is not configured.
    func fetchTopAthletes(limit: Int = 8) async throws -> [UserProfile] {
        guard isFirebaseReady else { return [] }
        let snapshot = try await db
            .collection("users")
            .order(by: "data.totalWorkouts", descending: true)
            .limit(to: limit)
            .getDocuments()
        return snapshot.documents.compactMap { doc -> UserProfile? in
            guard let raw = doc.data()["data"] as? [String: Any] else { return nil }
            return try? decodeProfile(from: raw)
        }
    }

    /// Returns up to `limit` feed items with the highest kudos count posted in the last 7 days.
    ///
    /// Returns an empty array when Firebase is not configured.
    func fetchTrendingWorkouts(limit: Int = 3) async throws -> [FeedItem] {
        guard isFirebaseReady else { return [] }
        let since = Date(timeIntervalSinceNow: -7 * 86_400).timeIntervalSince1970 * 1_000
        let snapshot = try await db
            .collection("activity")
            .whereField("postedAt", isGreaterThan: since)
            .order(by: "postedAt", descending: true)
            .limit(to: 50)
            .getDocuments()
        let items = snapshot.documents.compactMap { try? decodeFeedItem(from: $0.data()) }
        return Array(items.sorted { $0.kudosCount > $1.kudosCount }.prefix(limit))
    }

    /// Fetches users that `currentUserId` is not yet following, up to `limit`.
    ///
    /// Returns an empty array when Firebase is not configured.
    func fetchSuggestedAthletes(currentUserId: String, limit: Int = 10) async throws -> [UserProfile] {
        guard isFirebaseReady else { return [] }
        let followingIds = (try? await fetchFollowingIds(for: currentUserId)) ?? []
        var excluded = Set(followingIds)
        excluded.insert(currentUserId)

        let snapshot = try await db
            .collection("users")
            .limit(to: limit + excluded.count)
            .getDocuments()

        let profiles = snapshot.documents.compactMap { doc -> UserProfile? in
            guard let raw = doc.data()["data"] as? [String: Any] else { return nil }
            return try? decodeProfile(from: raw)
        }
        return Array(profiles.filter { !excluded.contains($0.id) }.prefix(limit))
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

        guard var dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SocialRepositoryError.encodingFailed
        }
        // Firestore rejects nested arrays ([[Double]]). Serialize routeCoordinates as a JSON string.
        if let coords = dict["routeCoordinates"],
           let coordData = try? JSONSerialization.data(withJSONObject: coords) {
            dict["routeCoordinates"] = String(data: coordData, encoding: .utf8)
        }
        return dict
    }

    private func decodeFeedItem(from wrapper: [String: Any]) throws -> FeedItem {
        guard var dict = wrapper["data"] as? [String: Any] else {
            throw SocialRepositoryError.decodingFailed
        }
        // Deserialize routeCoordinates back from JSON string to [[Double]].
        if let coordString = dict["routeCoordinates"] as? String,
           let coordData = coordString.data(using: .utf8),
           let coords = try? JSONSerialization.jsonObject(with: coordData) {
            dict["routeCoordinates"] = coords
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
