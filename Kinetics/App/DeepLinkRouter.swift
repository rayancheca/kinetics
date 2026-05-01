import SwiftUI

// MARK: - DeepLink

enum DeepLink: Equatable {
    case home
    case gym
    case gymPRs        // kinetics://gym/prs  — scrolls to PRs in Gym tab
    case history       // kinetics://history  — opens session history
    case track
    case train
    case feed
    case profile
    case todayStats
    case notifications

    init?(url: URL) {
        guard url.scheme == "kinetics" else { return nil }
        switch url.host {
        case "home":          self = .home
        case "gym":
            // Support sub-paths: kinetics://gym/prs
            if url.pathComponents.contains("prs") {
                self = .gymPRs
            } else {
                self = .gym
            }
        case "history":       self = .history
        case "track":         self = .track
        case "train":         self = .train
        case "feed":          self = .feed
        case "profile":       self = .profile
        case "today-stats":   self = .todayStats
        case "notifications": self = .notifications
        default:              return nil
        }
    }
}
