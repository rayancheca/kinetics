import SwiftUI
import FirebaseCore

@main
struct KineticsApp: App {

    @State private var appState = AppState()

    init() {
        configureFirebaseIfReady()
    }

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environment(appState)
                .preferredColorScheme(.dark)
        }
    }

    // MARK: - Private

    /// Only initialises Firebase when a real GoogleService-Info.plist has been dropped in.
    /// The placeholder plist sets API_KEY to "PLACEHOLDER-REPLACE-WITH-REAL-PLIST",
    /// which we use as a sentinel to skip configuration during development.
    private func configureFirebaseIfReady() {
        guard
            let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
            let plist = NSDictionary(contentsOfFile: path),
            let apiKey = plist["API_KEY"] as? String,
            !apiKey.contains("PLACEHOLDER")
        else { return }

        FirebaseApp.configure()
    }
}
