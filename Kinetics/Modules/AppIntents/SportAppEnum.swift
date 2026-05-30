import AppIntents
import Foundation

// MARK: - SportAppEnum

/// `AppEnum` mirror of `SportType` used inside App Intents.
///
/// We keep this enum separate from the model `SportType` so the App Intents
/// framework can serialise it for system surfaces (Shortcuts, Spotlight, Siri)
/// without coupling the framework requirement back into model code.
@available(iOS 17.0, *)
enum SportAppEnum: String, AppEnum, Sendable {
    case striking
    case grappling
    case ironTracker
    case wallBeta

    static let typeDisplayRepresentation: TypeDisplayRepresentation = TypeDisplayRepresentation(name: "Kinetics Module")

    static let caseDisplayRepresentations: [SportAppEnum: DisplayRepresentation] = [
        .striking:    DisplayRepresentation(title: "Striking Clinic",
                                            subtitle: "Velocity & kinetic chain",
                                            image: .init(systemName: "bolt.fill")),
        .grappling:   DisplayRepresentation(title: "Grappling Lab",
                                            subtitle: "Base, leverage, kuzushi",
                                            image: .init(systemName: "person.2.fill")),
        .ironTracker: DisplayRepresentation(title: "Iron Tracker",
                                            subtitle: "Bar path & symmetry",
                                            image: .init(systemName: "dumbbell.fill")),
        .wallBeta:    DisplayRepresentation(title: "Wall Beta",
                                            subtitle: "Hip proximity & Dynos",
                                            image: .init(systemName: "figure.climbing"))
    ]

    /// Resolves back to the model `SportType`.
    var sportType: SportType {
        switch self {
        case .striking:    .striking
        case .grappling:   .grappling
        case .ironTracker: .ironTracker
        case .wallBeta:    .wallBeta
        }
    }

    /// The kinetics:// deep-link URL that launches the matching module.
    var deepLinkURL: URL? {
        switch self {
        case .striking:    URL(string: "kinetics://train?module=striking")
        case .grappling:   URL(string: "kinetics://train?module=grappling")
        case .ironTracker: URL(string: "kinetics://train?module=iron")
        case .wallBeta:    URL(string: "kinetics://train?module=wall")
        }
    }
}
