import SwiftUI

struct MainTabView: View {
    @Environment(AppState.self) private var appState
    @State private var selectedTab = 0

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
    }
}
