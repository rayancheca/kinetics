import SwiftUI

extension SportType {
    /// The module card background image for this sport type.
    var cardImage: Image? {
        switch self {
        case .striking:
            return Image("strikingModule")
        case .grappling:
            return Image("grapplingModule")
        case .ironTracker:
            return Image("gymModule")
        case .wallBeta:
            return Image("climbingModule")
        }
    }
}
