import Foundation

// MARK: - UserProfile

/// A Kinetics user account document stored under `users/{uid}` in Firestore.
///
/// `avatarURL` and `primarySport` are denormalised onto every `FeedItem` the
/// user posts so the feed can render without secondary lookups. Keep those two
/// fields in sync whenever a profile update is saved.
struct UserProfile: Codable, Identifiable, Sendable, Hashable {

    // MARK: Identity

    /// Firebase Auth UID — also the Firestore document ID.
    var id: String

    // MARK: Display

    var displayName: String
    /// Unique @-prefixed handle, e.g. "@rayan". Must be unique across all users.
    var username: String
    var bio: String
    /// URL string pointing to the profile photo in Firebase Storage.
    /// Empty string when no photo has been uploaded.
    var avatarURL: String

    // MARK: Sport

    /// Primary activity key, e.g. "run", "striking", "grappling". Drives the
    /// sport badge on the profile card.
    var primarySport: String

    // MARK: Stats

    var totalWorkouts: Int
    var totalDistanceMeters: Double

    // MARK: Meta

    var joinedAt: Date
    /// When `false`, the feed only shows this user's activity to themselves.
    var isPublic: Bool
}

// MARK: UserProfile + Preview

extension UserProfile {

    /// Realistic mock instance for SwiftUI previews and unit tests.
    static var preview: UserProfile {
        UserProfile(
            id: "uid_preview_001",
            displayName: "Rayan Karim-Checa",
            username: "@rayan",
            bio: "MMA fighter • powerlifter • occasional climber",
            avatarURL: "",
            primarySport: "striking",
            totalWorkouts: 142,
            totalDistanceMeters: 312_400,
            joinedAt: Date(timeIntervalSinceNow: -60 * 60 * 24 * 180),
            isPublic: true
        )
    }
}

// MARK: - FeedItemType

/// Discriminates the content category of a `FeedItem` so the feed can choose
/// the correct icon, accent colour, and detail view.
enum FeedItemType: String, Codable, Sendable {
    /// GPS Track session (run, ride, hike, swim, ski, walk).
    case workout
    /// Personal record or milestone achievement unlocked automatically.
    case achievement
    /// Iron Tracker weightlifting or gym log entry.
    case gymSession
    /// Striking Clinic analysis session.
    case strikeSession
    /// Grappling Lab analysis session.
    case grapplingSession
    /// Wall Beta bouldering / sport climbing session.
    case wallSession
}

// MARK: - ExerciseSummary

/// A compact exercise summary attached to gym/iron-tracker feed posts.
/// Encoded into `FeedItem.exerciseSummaries` so the card can render a
/// per-exercise breakdown without a secondary Firestore lookup.
struct ExerciseSummary: Codable, Sendable, Hashable {
    /// Display name of the exercise, e.g. "Bench Press".
    var name: String
    /// Number of sets performed.
    var sets: Int
    /// Heaviest single weight lifted in kilograms across all sets.
    var topWeightKg: Double
    /// Total reps performed across all sets.
    var totalReps: Int
    /// Primary muscle group, e.g. "Chest", "Back", "Legs".
    var muscleGroup: String
}

// MARK: - FeedMetric

/// A single highlighted metric displayed on a `FeedItem` card.
/// Up to three `FeedMetric` values are shown in the metrics strip.
struct FeedMetric: Codable, Sendable, Hashable {
    /// Short uppercase label, e.g. "PACE", "DIST", "AVG HR".
    var label: String
    /// Formatted value string, e.g. "5:26", "5.2", "162".
    var value: String
    /// Unit suffix rendered in a smaller weight, e.g. "/km", "km", "bpm".
    /// Pass an empty string when the unit is already embedded in `value`.
    var unit: String
}

// MARK: FeedMetric + Preview

extension FeedMetric {

    static var previewPace: FeedMetric {
        FeedMetric(label: "PACE", value: "5:26", unit: "/km")
    }

    static var previewDistance: FeedMetric {
        FeedMetric(label: "DIST", value: "5.2", unit: "km")
    }

    static var previewDuration: FeedMetric {
        FeedMetric(label: "TIME", value: "28:14", unit: "")
    }

    static var previewStrikeVelocity: FeedMetric {
        FeedMetric(label: "VELOCITY", value: "8.3", unit: "m/s")
    }

    static var previewSymmetry: FeedMetric {
        FeedMetric(label: "SYMMETRY", value: "94", unit: "%")
    }
}

// MARK: - FeedItem

/// One card in the global social activity feed, stored under `activity/{activityId}`
/// in Firestore.
///
/// Author display fields (`displayName`, `username`, `avatarURL`) are denormalised
/// at write time so the feed renders without fetching individual `UserProfile`
/// documents. Update them on profile changes via a Cloud Function if strict
/// consistency is required in a later phase.
///
/// `isLikedByCurrentUser` is a transient client-side flag — it is never written
/// to Firestore. `SocialRepository.fetchFeed` resolves it by cross-referencing
/// the kudos sub-collection for the signed-in user.
struct FeedItem: Codable, Identifiable, Sendable, Hashable {

    // MARK: Identity

    var id: String = UUID().uuidString
    /// Firebase Auth UID of the athlete who posted this item.
    var userId: String

    // MARK: Denormalised Author

    var displayName: String
    var username: String
    var avatarURL: String

    // MARK: Content

    var itemType: FeedItemType
    /// Primary headline, e.g. "Morning Run • 5.2 km".
    var title: String
    /// Secondary line, e.g. "28:14 • 5:26/km".
    var subtitle: String
    /// Free-text caption the user typed when posting. Nil = no caption.
    var caption: String?
    /// Up to three highlight metrics shown in the metrics strip.
    var metrics: [FeedMetric]
    /// Exercise breakdown for gym/iron-tracker posts. Nil when not a gym session.
    var exerciseSummaries: [ExerciseSummary]?
    /// Array of [lat, lng] coordinate pairs describing the GPS route.
    /// Nil when no route is available. Used to draw a map polyline on the card.
    var routeCoordinates: [[Double]]?
    /// URL to an optional map snapshot or activity photo in Firebase Storage.
    /// Empty string when no image was attached.
    var imageURL: String

    // MARK: Timestamps

    var postedAt: Date

    // MARK: Social Counts

    var kudosCount: Int
    var commentCount: Int

    // MARK: Transient Client State (not stored in Firestore)

    /// Whether the currently signed-in user has kudos'd this item.
    /// Resolved by `SocialRepository` after fetching; not persisted.
    var isLikedByCurrentUser: Bool

    // MARK: Back-links

    /// ID of the `WorkoutResult` that originated this item.
    /// Empty string when the feed item was not generated from a GPS workout.
    var workoutId: String
    /// Activity type key used to select the item's icon and accent colour,
    /// e.g. "run", "striking", "grappling", "iron", "wall".
    var activityType: String

    // MARK: CodingKeys

    /// Exclude `isLikedByCurrentUser` from Firestore serialisation — it is a
    /// computed client state value resolved after each fetch.
    enum CodingKeys: String, CodingKey {
        case id, userId, displayName, username, avatarURL
        case itemType, title, subtitle, caption, metrics
        case exerciseSummaries, routeCoordinates, imageURL
        case postedAt, kudosCount, commentCount
        case workoutId, activityType
    }

    // MARK: Decodable

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        userId = try c.decode(String.self, forKey: .userId)
        displayName = try c.decode(String.self, forKey: .displayName)
        username = try c.decode(String.self, forKey: .username)
        avatarURL = try c.decode(String.self, forKey: .avatarURL)
        itemType = try c.decode(FeedItemType.self, forKey: .itemType)
        title = try c.decode(String.self, forKey: .title)
        subtitle = try c.decode(String.self, forKey: .subtitle)
        caption = try c.decodeIfPresent(String.self, forKey: .caption)
        metrics = try c.decode([FeedMetric].self, forKey: .metrics)
        exerciseSummaries = try c.decodeIfPresent([ExerciseSummary].self, forKey: .exerciseSummaries)
        routeCoordinates = try c.decodeIfPresent([[Double]].self, forKey: .routeCoordinates)
        imageURL = try c.decode(String.self, forKey: .imageURL)
        postedAt = try c.decode(Date.self, forKey: .postedAt)
        kudosCount = try c.decode(Int.self, forKey: .kudosCount)
        commentCount = try c.decode(Int.self, forKey: .commentCount)
        workoutId = try c.decode(String.self, forKey: .workoutId)
        activityType = try c.decode(String.self, forKey: .activityType)
        // Resolved client-side after fetch; default to false on decode.
        isLikedByCurrentUser = false
    }

    // MARK: Memberwise Init

    init(
        id: String = UUID().uuidString,
        userId: String,
        displayName: String,
        username: String,
        avatarURL: String,
        itemType: FeedItemType,
        title: String,
        subtitle: String,
        caption: String? = nil,
        metrics: [FeedMetric],
        exerciseSummaries: [ExerciseSummary]? = nil,
        routeCoordinates: [[Double]]? = nil,
        imageURL: String,
        postedAt: Date,
        kudosCount: Int,
        commentCount: Int,
        isLikedByCurrentUser: Bool,
        workoutId: String,
        activityType: String
    ) {
        self.id = id
        self.userId = userId
        self.displayName = displayName
        self.username = username
        self.avatarURL = avatarURL
        self.itemType = itemType
        self.title = title
        self.subtitle = subtitle
        self.caption = caption
        self.metrics = metrics
        self.exerciseSummaries = exerciseSummaries
        self.routeCoordinates = routeCoordinates
        self.imageURL = imageURL
        self.postedAt = postedAt
        self.kudosCount = kudosCount
        self.commentCount = commentCount
        self.isLikedByCurrentUser = isLikedByCurrentUser
        self.workoutId = workoutId
        self.activityType = activityType
    }
}

// MARK: FeedItem + Preview

extension FeedItem {

    /// Realistic run activity feed card for SwiftUI previews.
    static var previewRun: FeedItem {
        FeedItem(
            id: "feed_preview_run_001",
            userId: "uid_preview_001",
            displayName: "Rayan Karim-Checa",
            username: "@rayan",
            avatarURL: "",
            itemType: .workout,
            title: "Morning Run • 5.2 km",
            subtitle: "28:14 • 5:26/km",
            metrics: [
                FeedMetric(label: "PACE", value: "5:26", unit: "/km"),
                FeedMetric(label: "DIST", value: "5.2", unit: "km"),
                FeedMetric(label: "TIME", value: "28:14", unit: "")
            ],
            imageURL: "",
            postedAt: Date(timeIntervalSinceNow: -3_600),
            kudosCount: 7,
            commentCount: 2,
            isLikedByCurrentUser: false,
            workoutId: "workout_preview_001",
            activityType: "run"
        )
    }

    /// Striking Clinic session feed card for SwiftUI previews.
    static var previewStriking: FeedItem {
        FeedItem(
            id: "feed_preview_strike_001",
            userId: "uid_preview_001",
            displayName: "Rayan Karim-Checa",
            username: "@rayan",
            avatarURL: "",
            itemType: .strikeSession,
            title: "Striking Clinic • 45 strikes",
            subtitle: "Avg velocity 7.9 m/s • 92% symmetry",
            metrics: [
                FeedMetric(label: "VELOCITY", value: "7.9", unit: "m/s"),
                FeedMetric(label: "STRIKES", value: "45", unit: ""),
                FeedMetric(label: "SYMMETRY", value: "92", unit: "%")
            ],
            imageURL: "",
            postedAt: Date(timeIntervalSinceNow: -7_200),
            kudosCount: 12,
            commentCount: 4,
            isLikedByCurrentUser: true,
            workoutId: "",
            activityType: "striking"
        )
    }
}

// MARK: - ActivityComment

/// A comment posted on an activity feed item, stored under
/// `activity/{activityId}/comments/{commentId}` in Firestore.
struct ActivityComment: Codable, Identifiable, Sendable, Hashable {

    // MARK: Identity

    var id: String = UUID().uuidString
    /// Firebase Auth UID of the commenter.
    var userId: String

    // MARK: Denormalised Author

    var displayName: String
    var avatarURL: String

    // MARK: Content

    var text: String
    var postedAt: Date
}

// MARK: ActivityComment + Preview

extension ActivityComment {

    static var preview: ActivityComment {
        ActivityComment(
            id: "comment_preview_001",
            userId: "uid_preview_002",
            displayName: "Alex Guerrero",
            avatarURL: "",
            text: "Crushing it! That pace on the last km was 🔥",
            postedAt: Date(timeIntervalSinceNow: -1_800)
        )
    }
}

// MARK: - CommentModel

/// A simplified comment model used in the redesigned feed comment sheet.
struct CommentModel: Codable, Identifiable, Sendable, Hashable {
    var id: String
    var userId: String
    var displayName: String
    var text: String
    var createdAt: Date
}

// MARK: CommentModel + Preview

extension CommentModel {

    static var preview: CommentModel {
        CommentModel(
            id: "cm_preview_001",
            userId: "uid_preview_002",
            displayName: "Alex Guerrero",
            text: "Crushing it! That velocity on the last combo was insane 🔥",
            createdAt: Date(timeIntervalSinceNow: -1_800)
        )
    }

    static var previewList: [CommentModel] {
        [
            CommentModel(id: "cm_001", userId: "uid_002", displayName: "Alex Guerrero",
                         text: "Those split times are impressive!", createdAt: Date(timeIntervalSinceNow: -3600)),
            CommentModel(id: "cm_002", userId: "uid_003", displayName: "Jordan Kim",
                         text: "What shoes are you training in?", createdAt: Date(timeIntervalSinceNow: -2100)),
            CommentModel(id: "cm_003", userId: "uid_004", displayName: "Sam Torres",
                         text: "Keep grinding 💪", createdAt: Date(timeIntervalSinceNow: -900))
        ]
    }
}

// MARK: - FollowRelationship

/// A denormalised snapshot of a user stored in the following / followers sub-collections.
/// Stored under `users/{uid}/following/{targetUid}` and `users/{uid}/followers/{sourceUid}`.
struct FollowRelationship: Codable, Sendable, Identifiable {
    /// Firebase Auth UID of the followed / following user.
    var userId: String
    var displayName: String
    var username: String
    var avatarURL: String
    var primarySport: String
    var followedAt: Date

    /// `Identifiable` conformance — use `userId` as the stable identity.
    var id: String { userId }
}

// MARK: - FollowStatus

/// Describes the current follow relationship between the signed-in user and a profile.
enum FollowStatus: Sendable {
    /// The signed-in user is not following this profile.
    case notFollowing
    /// A follow request has been sent to a private account and is awaiting approval.
    case requested
    /// The signed-in user is actively following this profile.
    case following
    /// The profile belongs to the currently signed-in user.
    case `self_`
}

// MARK: - StoryModel

/// Represents a recent-session story ring in the feed's horizontal stories bar.
/// Stored under `stories/{storyId}` or derived client-side from recent feed items.
struct StoryModel: Codable, Identifiable, Sendable, Hashable {
    var id: String
    var userId: String
    var displayName: String
    /// Single-character emoji representing the user's avatar when no photo is set.
    var avatarEmoji: String
    /// Activity type key, e.g. "striking", "grappling", "iron", "wall", "run".
    var sport: String
    var sessionId: String
    var createdAt: Date
    /// Whether the current user has already viewed this story ring.
    var seen: Bool
}

// MARK: StoryModel + Preview

extension StoryModel {

    static var previewList: [StoryModel] {
        [
            StoryModel(id: "story_001", userId: "uid_001", displayName: "Rayan",
                       avatarEmoji: "🥊", sport: "striking", sessionId: "sess_001",
                       createdAt: Date(timeIntervalSinceNow: -1_200), seen: false),
            StoryModel(id: "story_002", userId: "uid_002", displayName: "Alex",
                       avatarEmoji: "🤼", sport: "grappling", sessionId: "sess_002",
                       createdAt: Date(timeIntervalSinceNow: -3_600), seen: false),
            StoryModel(id: "story_003", userId: "uid_003", displayName: "Jordan",
                       avatarEmoji: "🏋️", sport: "iron", sessionId: "sess_003",
                       createdAt: Date(timeIntervalSinceNow: -7_200), seen: true),
            StoryModel(id: "story_004", userId: "uid_004", displayName: "Sam",
                       avatarEmoji: "🧗", sport: "wall", sessionId: "sess_004",
                       createdAt: Date(timeIntervalSinceNow: -10_800), seen: true),
            StoryModel(id: "story_005", userId: "uid_005", displayName: "Casey",
                       avatarEmoji: "🏃", sport: "run", sessionId: "sess_005",
                       createdAt: Date(timeIntervalSinceNow: -14_400), seen: false)
        ]
    }
}
