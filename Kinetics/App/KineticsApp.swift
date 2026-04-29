import SwiftUI

@main
struct KineticsApp: App {

    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environment(appState)
                .preferredColorScheme(.dark)
        }
    }
}
