import SwiftUI

@main
struct KineticsWatchApp: App {
    @StateObject private var sessionManager = WatchSessionManager.shared

    var body: some Scene {
        WindowGroup {
            WatchContentView()
                .environmentObject(sessionManager)
        }
    }
}
