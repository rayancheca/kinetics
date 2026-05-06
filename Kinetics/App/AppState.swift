import FirebaseCore
import Foundation
import Observation

/// Global app state shared across all views via `.environment(appState)`.
/// The camera and auth managers live here so they are created once and shared.
///
/// Firebase is configured inside `init()` — before `AuthManager()` is created —
/// so the auth state listener is guaranteed to attach to a live Firebase app.
@Observable
@MainActor
final class AppState {

    // MARK: - Navigation

    var selectedModule: SportType?
    var isSessionActive: Bool = false
    /// Drives the custom tab bar in MainTabView so any view can switch tabs.
    var selectedTab: KineticsTab = .home

    // MARK: - Shared Services

    let authManager: AuthManager
    let cameraManager = CameraManager()

    // MARK: - Init

    init() {
        AppState.configureFirebaseIfReady()
        authManager = AuthManager()
    }

    // MARK: - Preview Support

    static let preview = AppState()

    // MARK: - Private

    /// Only initialises Firebase when a real GoogleService-Info.plist has been dropped in.
    /// The placeholder plist sets API_KEY to "PLACEHOLDER-REPLACE-WITH-REAL-PLIST",
    /// which we use as a sentinel to skip configuration during development.
    /// Guards against double-configuration with a `FirebaseApp.app() == nil` check.
    private static func configureFirebaseIfReady() {
        guard FirebaseApp.app() == nil else { return }
        guard
            let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
            let plist = NSDictionary(contentsOfFile: path),
            let apiKey = plist["API_KEY"] as? String,
            !apiKey.contains("PLACEHOLDER")
        else { return }

        FirebaseApp.configure()
    }
}
