import Foundation

// MARK: - SessionFeedPublisher

/// Posts a completed session as a `FeedItem` to the social feed.
///
/// Call after any module session completes, passing the module name and key metrics.
/// All writes are fire-and-forget — errors are silently discarded so a Firestore
/// hiccup never interrupts the post-session report flow.
@MainActor
enum SessionFeedPublisher {

    // MARK: - Public

    /// Builds a `FeedItem` from the session details and writes it to Firestore via
    /// `SocialRepository`. No-ops when `userId` is empty.
    ///
    /// - Parameters:
    ///   - userId: Firebase Auth UID of the current user. Pass an empty string to skip posting.
    ///   - displayName: Human-readable name shown on the feed card. Falls back to "Athlete".
    ///   - sport: Module display name, e.g. "Striking", "Grappling", "Iron Tracker", "Wall Beta".
    ///   - activityType: Short key used for icon/accent lookup, e.g. "striking", "grappling", "iron", "wall".
    ///   - itemType: `FeedItemType` discriminator for the card renderer.
    ///   - durationSeconds: Session length in seconds.
    ///   - metrics: Up to three `FeedMetric` values shown in the metrics strip.
    static func publish(
        userId: String,
        displayName: String,
        sport: String,
        activityType: String,
        itemType: FeedItemType,
        durationSeconds: Double,
        metrics: [FeedMetric]
    ) async {
        guard !userId.isEmpty else { return }
        // Default is true (opt-out model). Only skip when the user has explicitly disabled it.
        let autoPublish = UserDefaults.standard.object(forKey: "auto_publish_sessions") as? Bool ?? true
        guard autoPublish else { return }

        let name = displayName.isEmpty ? "Athlete" : displayName
        let durationString = formatted(durationSeconds)
        let title = "\(sport) • \(durationString)"

        let item = FeedItem(
            id: UUID().uuidString,
            userId: userId,
            displayName: name,
            username: "",
            avatarURL: "",
            itemType: itemType,
            title: title,
            subtitle: durationString,
            metrics: Array(metrics.prefix(3)),
            imageURL: "",
            postedAt: Date(),
            kudosCount: 0,
            commentCount: 0,
            isLikedByCurrentUser: false,
            workoutId: UUID().uuidString,
            activityType: activityType
        )

        try? await SocialRepository.shared.postActivity(item)
    }

    // MARK: - Private

    private static func formatted(_ seconds: Double) -> String {
        let total = Int(seconds)
        let mins = total / 60
        let secs = total % 60
        return mins > 0 ? "\(mins)m \(secs)s" : "\(secs)s"
    }
}
