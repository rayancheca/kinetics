import FirebaseAnalytics
import SwiftUI

// MARK: - KineticsTab

/// Enumeration of the five root tabs.
enum KineticsTab: Int, CaseIterable {
    case home   = 0
    case train  = 1
    case gym    = 2
    case feed   = 3
    case profile = 4

    var label: String {
        switch self {
        case .home:    return "Home"
        case .train:   return "Train"
        case .gym:     return "Gym"
        case .feed:    return "Feed"
        case .profile: return "Profile"
        }
    }

    /// SF Symbol used when the tab is NOT selected.
    var outlineIcon: String {
        switch self {
        case .home:    return "house"
        case .train:   return "figure.run"
        case .gym:     return "dumbbell"
        case .feed:    return "person.2"
        case .profile: return "person"
        }
    }

    /// SF Symbol used when the tab IS selected (fill variant where available).
    var fillIcon: String {
        switch self {
        case .home:    return "house.fill"
        case .train:   return "figure.run"        // no fill variant — same icon
        case .gym:     return "dumbbell.fill"
        case .feed:    return "person.2.fill"
        case .profile: return "person.fill"
        }
    }
}

// MARK: - MainTabView

struct MainTabView: View {

    @Environment(AppState.self) private var appState
    @State private var tabEnteredAt: Date = .init()

    private var selectedTab: KineticsTab { appState.selectedTab }

    var body: some View {
        ZStack(alignment: .bottom) {
            // MARK: Tab content — switch with cross-fade
            Group {
                switch selectedTab {
                case .home:    HomeView()
                case .train:   TrainView()
                case .gym:     GymRootView()
                case .feed:    FeedView()
                case .profile: ProfileView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // Leave room at the bottom for the custom tab bar
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Color.clear.frame(height: tabBarHeight)
            }

            // MARK: Custom tab bar
            customTabBar
        }
        .ignoresSafeArea(.keyboard)
        // Deep link routing
        .onOpenURL { url in
            guard let link = DeepLink(url: url) else { return }
            handleDeepLink(link)
        }
        // Analytics: track time spent on each tab
        .onChange(of: selectedTab) { oldTab, newTab in
            let duration = Date().timeIntervalSince(tabEnteredAt)
            Analytics.logEvent("tab_screen_time", parameters: [
                "tab": oldTab.label.lowercased(),
                "duration_seconds": Int(duration)
            ])
            Analytics.logEvent("tab_viewed", parameters: [
                "tab": newTab.label.lowercased()
            ])
            tabEnteredAt = .init()
        }
        .onAppear {
            Analytics.logEvent("tab_viewed", parameters: ["tab": "home"])
        }
    }

    // MARK: - Tab Bar

    private var tabBarHeight: CGFloat { 56 }

    private var customTabBar: some View {
        VStack(spacing: 0) {
            // Hairline separator
            Rectangle()
                .fill(.white.opacity(0.08))
                .frame(height: 0.5)

            HStack(spacing: 0) {
                ForEach(KineticsTab.allCases, id: \.rawValue) { tab in
                    tabBarButton(for: tab)
                }
            }
            .frame(height: tabBarHeight)
            .background(
                // Layered dark + blur so the bar blends with the camera feed
                ZStack {
                    Color.black
                    Color.black.opacity(0.85)
                }
            )
        }
        .background(Color.black)
    }

    private func tabBarButton(for tab: KineticsTab) -> some View {
        let isSelected = selectedTab == tab

        return Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                appState.selectedTab = tab
            }
        } label: {
            VStack(spacing: 3) {
                Image(systemName: isSelected ? tab.fillIcon : tab.outlineIcon)
                    .font(.system(size: 20, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Color.kineticsBlue : Color.white.opacity(0.45))
                    .scaleEffect(isSelected ? 1.08 : 1.0)
                    .animation(.spring(response: 0.3, dampingFraction: 0.65), value: isSelected)

                Text(tab.label)
                    .font(.system(size: 9.5, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Color.kineticsBlue : Color.white.opacity(0.38))
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Deep Link Handler

    private func handleDeepLink(_ link: DeepLink) {
        withAnimation(.easeInOut(duration: 0.18)) {
            switch link {
            case .home, .todayStats, .notifications, .history:
                appState.selectedTab = .home
            case .train:
                appState.selectedTab = .train
            case .gym, .gymPRs:
                appState.selectedTab = .gym
            case .feed:
                appState.selectedTab = .feed
            case .profile:
                appState.selectedTab = .profile
            case .track:
                // Track module is accessible via Train tab
                appState.selectedTab = .train
            }
        }
    }
}
