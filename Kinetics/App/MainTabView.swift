import FirebaseAnalytics
import SwiftUI

struct MainTabView: View {
    @Environment(AppState.self) private var appState
    @State private var selectedTab = 0
    @State private var tabEnteredAt: Date = Date()
    @State private var previousTab: Int = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView()
                .tabItem { Label("Home", systemImage: "house.fill") }
                .tag(0)

            TrainView()
                .tabItem { Label("Train", systemImage: "figure.run") }
                .tag(1)

            TrackView()
                .tabItem { Label("Track", systemImage: "map.fill") }
                .tag(2)

            GymHomeView()
                .tabItem { Label("Gym", systemImage: "dumbbell.fill") }
                .tag(3)

            FeedView()
                .tabItem { Label("Feed", systemImage: "person.2.fill") }
                .tag(4)

            ProfileView()
                .tabItem { Label("Profile", systemImage: "person.fill") }
                .tag(5)
        }
        .tint(Color.kineticsBlue)
        .toolbarBackground(.black, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .onAppear {
            Analytics.logEvent("tab_viewed", parameters: ["tab": "home"])
        }
        .onChange(of: selectedTab) { oldTab, newTab in
            let duration = Date().timeIntervalSince(tabEnteredAt)
            Analytics.logEvent("tab_screen_time", parameters: [
                "tab": tabName(for: oldTab),
                "duration_seconds": Int(duration)
            ])
            Analytics.logEvent("tab_viewed", parameters: [
                "tab": tabName(for: newTab)
            ])
            tabEnteredAt = Date()
            previousTab = newTab
        }
        .onOpenURL { url in
            guard let link = DeepLink(url: url) else { return }
            switch link {
            case .home, .todayStats:
                selectedTab = 0
            case .train:
                selectedTab = 1
            case .track:
                selectedTab = 2
            case .gym:
                selectedTab = 3
            case .feed:
                selectedTab = 4
            case .notifications:
                selectedTab = 0
            }
        }
    }

    // MARK: - Private helpers

    private func tabName(for tag: Int) -> String {
        switch tag {
        case 0: return "home"
        case 1: return "train"
        case 2: return "track"
        case 3: return "gym"
        case 4: return "feed"
        case 5: return "profile"
        default: return "unknown"
        }
    }
}
