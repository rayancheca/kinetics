import Foundation
import Observation

/// Global app state shared across all views via `.environment(appState)`.
/// The camera and auth managers live here so they are created once and shared.
@Observable
@MainActor
final class AppState {

    // MARK: - Navigation

    var selectedModule: SportType?
    var isSessionActive: Bool = false

    // MARK: - Shared Services

    let authManager = AuthManager()
    let cameraManager = CameraManager()

    // MARK: - Preview Support

    static let preview = AppState()
}
