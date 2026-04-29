import SwiftUI

// MARK: - DeepLink

enum DeepLink: Equatable {
    case home
    case gym
    case track
    case train
    case feed
    case todayStats
    case notifications

    init?(url: URL) {
        guard url.scheme == "kinetics" else { return nil }
        switch url.host {
        case "home":          self = .home
        case "gym":           self = .gym
        case "track":         self = .track
        case "train":         self = .train
        case "feed":          self = .feed
        case "today-stats":   self = .todayStats
        case "notifications": self = .notifications
        default:              return nil
        }
    }
}
