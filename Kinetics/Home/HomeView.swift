import AuthenticationServices
import PhotosUI
import SwiftUI

// MARK: - HomeView

/// Redesigned Home tab — seven sections:
/// 1. Hero greeting header with notification bell + auth pill
/// 2. Streak badge (full-width pill, tappable → achievements)
/// 3. Readiness card (HomeReadinessCard)
/// 4. Quick-launch horizontal scroll (HomeQuickLaunchCard)
/// 5. AI coach insight card (HomeCoachInsightCard)
/// 6. Recent activity feed (HomeActivityRow, authenticated only)
/// 7. Next milestone + social preview (authenticated only)
struct HomeView: View {

    // MARK: - Dependencies

    @Environment(AppState.self) private var appState
    @State private var viewModel = HomeViewModel()
    @State private var showSignIn = false
    @State private var confirmSignOut = false
    @State private var showAchievements = false
    @State private var showNotifications = false
    @State private var showReadinessDetail = false
    @State private var showStreakDetail = false

    // Module entry sheet state
    @State private var pendingModule: SportType? = nil
    @State private var showModuleEntrySheet = false

    // Programmatic navigation path for NavigationStack
    @State private var navPath = NavigationPath()

    // Video import state
    @State private var showVideoPicker = false
    @State private var selectedVideoItem: PhotosPickerItem? = nil
    @State private var navigateToVideoLibrary = false

    // MARK: - Body

    var body: some View {
        NavigationStack(path: $navPath) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    // 1. Hero header
                    heroHeader
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                        .padding(.bottom, 4)

                    // 2. Streak badge
                    if viewModel.streakDays > 0 {
                        Button { showStreakDetail = true } label: {
                            streakBadge
                        }
                        .buttonStyle(ScaleButtonStyle())
                        .padding(.horizontal, 20)
                        .padding(.bottom, 16)
                    } else {
                        Color.clear
                            .frame(height: 0)
                            .padding(.bottom, 16)
                    }

                    // 3. Readiness card
                    HomeReadinessCard(vm: viewModel) {
                        showReadinessDetail = true
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 20)

                    // 4. Quick launch
                    quickLaunchSection
                        .padding(.bottom, 20)

                    // 5. AI coach card
                    HomeCoachInsightCard(insight: viewModel.coachInsight)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 20)

                    // 6. Recent activity (authenticated only)
                    if appState.authManager.isSignedIn {
                        recentActivitySection
                            .padding(.horizontal, 16)
                            .padding(.bottom, 20)
                    }

                    // 7. Next milestone (authenticated only)
                    if let milestone = viewModel.nextMilestone {
                        HomeMilestoneCard(milestone: milestone)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 20)
                    }

                    // 8. Social preview (authenticated only)
                    if appState.authManager.isSignedIn {
                        HomeSocialPreviewCard {
                            withAnimation(.easeInOut(duration: 0.18)) {
                                appState.selectedTab = .feed
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 32)
                    }

                    Spacer(minLength: 32)
                }
            }
            .background(Color.kineticsBackground)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: SportType.self) { sport in
                moduleView(for: sport)
            }
            .navigationDestination(isPresented: $navigateToVideoLibrary) {
                VideoLibraryView(userId: uid)
            }
            .sheet(isPresented: $showModuleEntrySheet) {
                if let module = pendingModule {
                    ModuleEntrySheet(
                        sport: module,
                        onLiveSession: {
                            showModuleEntrySheet = false
                            Task {
                                try? await Task.sleep(for: .seconds(0.35))
                                await MainActor.run { navPath.append(module) }
                            }
                        },
                        onAnalyzeVideo: {
                            showModuleEntrySheet = false
                            showVideoPicker = true
                        }
                    )
                    .presentationDetents([.height(260)])
                    .presentationBackground(Color.kineticsDark)
                    .presentationCornerRadius(24)
                }
            }
            .photosPicker(
                isPresented: $showVideoPicker,
                selection: $selectedVideoItem,
                matching: .videos,
                photoLibrary: .shared()
            )
            .onChange(of: selectedVideoItem) { _, item in
                guard item != nil else { return }
                selectedVideoItem = nil
                navigateToVideoLibrary = true
            }
            .sheet(isPresented: $showSignIn) {
                SignInSheet()
                    .environment(appState)
            }
            .sheet(isPresented: $showAchievements) {
                HomeAchievementsView()
                    .environment(appState)
            }
            .sheet(isPresented: $showNotifications) {
                HomeNotificationsView()
                    .environment(appState)
            }
            .sheet(isPresented: $showReadinessDetail) {
                ReadinessDetailSheet(vm: viewModel)
            }
            .sheet(isPresented: $showStreakDetail) {
                HomeStreakDetailSheet(
                    streakDays: viewModel.streakDays,
                    recentSessions: viewModel.recentSessions
                )
            }
            .confirmationDialog(
                "Account",
                isPresented: $confirmSignOut,
                titleVisibility: .visible
            ) {
                Button("Sign Out", role: .destructive) {
                    Task {
                        try? appState.authManager.signOut()
                        if let uid = appState.authManager.currentUser?.uid {
                            await viewModel.refreshSessionHistory(for: uid)
                        } else {
                            viewModel.recentSessions = []
                        }
                    }
                }
                Button("Cancel", role: .cancel) {}
            }
            .onChange(of: showSignIn) { _, isShowing in
                guard !isShowing,
                      let uid = appState.authManager.currentUser?.uid
                else { return }
                Task { await viewModel.loadHistory(for: uid) }
            }
            .task {
                await viewModel.signInAnonymouslyIfNeeded(
                    authManager: appState.authManager
                )
                if let userId = appState.authManager.currentUser?.uid {
                    await viewModel.loadHistory(for: userId)
                }
                await viewModel.loadDashboardStats()
            }
        }
    }

    // MARK: - Section 1: Hero Header

    private var heroHeader: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(greetingText)
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(.white)

                Text(formattedDate)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.white.opacity(0.42))
            }

            Spacer()

            HStack(spacing: 8) {
                // Notification bell
                Button { showNotifications = true } label: {
                    Image(systemName: "bell")
                        .font(.system(size: 20))
                        .foregroundStyle(.white.opacity(0.55))
                        .frame(width: 36, height: 36)
                        .background(Color.kineticsDark)
                        .clipShape(Circle())
                }

                authPill
            }
        }
    }

    // MARK: - Streak Badge

    private var streakBadge: some View {
        HStack(spacing: 8) {
            Image(systemName: "flame.fill")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Color.kineticsAmber)

            Text("\(viewModel.streakDays) day streak")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.30))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .background(
            LinearGradient(
                colors: [
                    Color.kineticsAmber.opacity(0.18),
                    Color.kineticsAmber.opacity(0.08)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.kineticsAmber.opacity(0.28), lineWidth: 0.75)
        )
    }

    // MARK: - Section 3: Quick Launch

    private var quickLaunchSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("QUICK LAUNCH")
                .padding(.horizontal, 20)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(SportType.allCases, id: \.self) { sport in
                        Button {
                            pendingModule = sport
                            showModuleEntrySheet = true
                        } label: {
                            HomeQuickLaunchCard(
                                sport: sport,
                                lastSession: viewModel.recentSessions
                                    .first { $0.sport == sport },
                                bestMetricValue: viewModel
                                    .bestMetric(for: sport)?.value,
                                bestMetricLabel: viewModel
                                    .bestMetric(for: sport)?.label,
                                trend: viewModel.trend(for: sport)
                            )
                        }
                        .buttonStyle(ScaleButtonStyle())
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    // MARK: - Section 5: Recent Activity

    private var recentActivitySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                sectionHeader("RECENT ACTIVITY")

                Spacer()

                if viewModel.prCountThisWeek > 0 {
                    Text("\(viewModel.prCountThisWeek) PR this week")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.kineticsAmber)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.kineticsAmber.opacity(0.12))
                        .clipShape(Capsule())
                }
            }

            if viewModel.isLoadingHistory && viewModel.recentSessions.isEmpty {
                activitySkeleton
            } else if viewModel.recentSessions.isEmpty {
                emptyActivityState
            } else {
                VStack(spacing: 0) {
                    ForEach(viewModel.recentSessions.prefix(5)) { session in
                        HomeActivityRow(
                            session: session,
                            isPR: viewModel.isPersonalRecord(session)
                        )
                        Divider()
                            .opacity(0.08)
                            .padding(.horizontal, 14)
                    }

                    // View all footer
                    NavigationLink(destination: HistoryView()) {
                        HStack {
                            Text(
                                "View all \(viewModel.recentSessions.count) sessions"
                            )
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Color.kineticsBlue)

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Color.kineticsBlue.opacity(0.6))
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                    }
                }
                .background(Color.kineticsDark)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(.white.opacity(0.07), lineWidth: 0.5)
                )
            }
        }
    }

    private var activitySkeleton: some View {
        VStack(spacing: 0) {
            ForEach(0 ..< 3, id: \.self) { _ in
                SkeletonRow()
            }
        }
        .background(Color.kineticsDark)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var emptyActivityState: some View {
        VStack(spacing: 10) {
            Image(systemName: "figure.run.circle")
                .font(.system(size: 34, weight: .thin))
                .foregroundStyle(Color.kineticsBlue.opacity(0.45))
            Text("No sessions yet")
                .font(.system(.subheadline, weight: .medium))
                .foregroundStyle(.white.opacity(0.35))
            Text("Pick a module above to start your first session.")
                .font(.system(.caption))
                .foregroundStyle(.white.opacity(0.25))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .background(Color.kineticsDark)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - Helper Views

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .tracking(2.5)
            .foregroundStyle(Color.kineticsSubtext)
    }

    private var authPill: some View {
        Button {
            let user = appState.authManager.currentUser
            if appState.authManager.isSignedIn && user?.isAnonymous == false {
                confirmSignOut = true
            } else {
                showSignIn = true
            }
        } label: {
            if appState.authManager.isSignedIn {
                let isAnonymous = appState.authManager.currentUser?.isAnonymous == true
                HStack(spacing: 6) {
                    Circle()
                        .fill(isAnonymous ? Color.yellow : Color.kineticsGreen)
                        .frame(width: 6, height: 6)
                        .shadow(
                            color: (isAnonymous
                                ? Color.yellow
                                : Color.kineticsGreen).opacity(0.8),
                            radius: 4
                        )
                    Text(isAnonymous ? "Guest" : "Online")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.55))
                }
                .padding(.horizontal, 13)
                .padding(.vertical, 7)
                .background(Color.kineticsMidGray)
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .strokeBorder(.white.opacity(0.07), lineWidth: 0.5)
                )
            } else {
                Text("Sign In")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.kineticsBlue)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 7)
                    .background(Color.kineticsBlue.opacity(0.12))
                    .clipShape(Capsule())
                    .overlay(
                        Capsule()
                            .strokeBorder(Color.kineticsBlue.opacity(0.35), lineWidth: 0.5)
                    )
            }
        }
    }

    // MARK: - Computed Properties

    private var uid: String {
        appState.authManager.currentUser?.uid ?? "preview-user"
    }

    private var greetingText: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let name = displayFirstName
        switch hour {
        case 0 ..< 12:  return "Good morning, \(name) 👋"
        case 12 ..< 17: return "Good afternoon, \(name) 👋"
        default:        return "Good evening, \(name) 👋"
        }
    }

    private var formattedDate: String {
        Date().formatted(.dateTime.weekday(.wide).month(.wide).day())
    }

    private var displayFirstName: String {
        guard let user = appState.authManager.currentUser,
              user.isAnonymous == false
        else { return "Athlete" }
        return user.email?
            .components(separatedBy: "@").first?
            .components(separatedBy: ".").first?
            .capitalized ?? "Athlete"
    }

    // MARK: - Module Navigation

    @ViewBuilder
    private func moduleView(for sport: SportType) -> some View {
        switch sport {
        case .striking:
            StrikingView()
        case .grappling:
            GrapplingView()
        case .ironTracker:
            IronTrackerView()
        case .wallBeta:
            WallBetaView()
        }
    }
}

// MARK: - ModuleCard

/// A tall card representing one sport module. Used inside the 2×2 home grid.
///
/// Visual layers (back to front):
/// 1. Dark card background (`kineticsDark`).
/// 2. Large ghosted SF Symbol top-right for sport identity at a glance.
/// 3. Radial glow anchored to the top-leading corner.
/// 4. Vertical gradient from clear → accent at the bottom for depth.
/// 5. Hairline border at accent opacity.
/// 6. Content column (icon badge, sport name, tagline, START CTA).
struct ModuleCard: View {

    let sport: SportType

    private var accent: Color { Color.moduleColor(for: sport) }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // MARK: Base surface
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.kineticsDark)

            // MARK: Large ghost icon — sport identity at a glance
            Image(systemName: sport.systemImage)
                .font(.system(size: 78, weight: .black))
                .foregroundStyle(accent.opacity(0.09))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(.top, 10)
                .padding(.trailing, 8)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

            // MARK: Radial glow (top-leading)
            RadialGradient(
                colors: [accent.opacity(0.14), .clear],
                center: .topLeading,
                startRadius: 0,
                endRadius: 110
            )
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

            // MARK: Bottom depth gradient
            LinearGradient(
                colors: [.clear, accent.opacity(0.22)],
                startPoint: .center,
                endPoint: .bottom
            )
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

            // MARK: Hairline border
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(accent.opacity(0.25), lineWidth: 0.75)

            // MARK: Content
            VStack(alignment: .leading, spacing: 0) {
                // Compact icon badge
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(accent.opacity(0.15))
                        .frame(width: 44, height: 44)

                    Image(systemName: sport.systemImage)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(accent)
                }

                Spacer()

                // Module name
                Text(sport.displayName)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                // Tagline
                Text(sport.tagline)
                    .font(.system(size: 10.5, weight: .regular))
                    .foregroundStyle(.white.opacity(0.42))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 3)

                // START CTA
                HStack(spacing: 4) {
                    Text("START")
                        .font(.system(size: 9, weight: .bold))
                        .tracking(1.8)
                        .foregroundStyle(accent)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(accent)
                }
                .padding(.top, 9)
            }
            .padding(14)
        }
        .frame(minHeight: 185)
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

// MARK: - ScaleButtonStyle

/// Spring-animated press effect for module cards.
struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(
                .spring(response: 0.28, dampingFraction: 0.65),
                value: configuration.isPressed
            )
    }
}

// MARK: - SkeletonRow

/// A muted placeholder row shown while session history is loading.
private struct SkeletonRow: View {
    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.white.opacity(0.07))
                .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(.white.opacity(0.07))
                    .frame(width: 100, height: 11)

                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(.white.opacity(0.05))
                    .frame(width: 72, height: 9)
            }

            Spacer()

            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(.white.opacity(0.07))
                .frame(width: 50, height: 11)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

// MARK: - HomeStreakDetailSheet

/// Compact sheet showing the current streak, 30-day frequency, and next badge milestone.
struct HomeStreakDetailSheet: View {

    let streakDays: Int
    let recentSessions: [SessionResult]

    @Environment(\.dismiss) private var dismiss

    private var trainedLast30Days: Int {
        let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        return recentSessions.filter { $0.startedAt >= cutoff }.count
    }

    /// Days remaining until next streak milestone: 7, 14, 30, 60, 100.
    private var nextMilestone: (target: Int, remaining: Int)? {
        let milestones = [7, 14, 30, 60, 100]
        guard let next = milestones.first(where: { $0 > streakDays }) else { return nil }
        return (next, next - streakDays)
    }

    private var badgeNameFor: (Int) -> String {{ days in
        switch days {
        case 7:   return "Week Warrior"
        case 14:  return "Iron Streak"
        case 30:  return "Month Grind"
        case 60:  return "Two-Month Titan"
        default:  return "Century Streak"
        }
    }}

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("YOUR STREAK")
                        .font(.system(size: 13, weight: .bold))
                        .tracking(3)
                        .foregroundStyle(.white.opacity(0.40))
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.55))
                            .frame(width: 32, height: 32)
                            .background(Color.kineticsMidGray)
                            .clipShape(Circle())
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 28)

                // Big flame + number
                VStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(Color.kineticsAmber.opacity(0.12))
                            .frame(width: 100, height: 100)
                        Image(systemName: "flame.fill")
                            .font(.system(size: 44, weight: .bold))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [Color.kineticsAmber, Color.kineticsRed],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                    }
                    Text("\(streakDays)")
                        .font(.system(size: 72, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                    Text(streakDays == 1 ? "day streak" : "day streak")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.45))
                }
                .padding(.bottom, 32)

                // Stats pills
                HStack(spacing: 12) {
                    streakStat(
                        value: "\(trainedLast30Days)",
                        label: "sessions\nlast 30 days"
                    )
                    if let milestone = nextMilestone {
                        streakStat(
                            value: "\(milestone.remaining)",
                            label: "days to\n\(badgeNameFor(milestone.target))"
                        )
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)

                // Milestone hint
                if let milestone = nextMilestone {
                    HStack(spacing: 10) {
                        Image(systemName: "lock.open.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.kineticsAmber)
                        Text(
                            "\(milestone.remaining) more \(milestone.remaining == 1 ? "day" : "days") " +
                            "to unlock **\(badgeNameFor(milestone.target))** badge"
                        )
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.65))
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                    .background(Color.kineticsAmber.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Color.kineticsAmber.opacity(0.20), lineWidth: 0.5)
                    )
                    .padding(.horizontal, 24)
                }

                Spacer()
            }
            .toolbar(.hidden, for: .navigationBar)
            .background(Color.kineticsBackground)
        }
        .presentationDetents([.height(500)])
        .presentationBackground(Color.kineticsBackground)
        .presentationCornerRadius(24)
        .presentationDragIndicator(.visible)
    }

    private func streakStat(value: String, label: String) -> some View {
        VStack(spacing: 6) {
            Text(value)
                .font(.system(size: 32, weight: .black, design: .rounded))
                .foregroundStyle(.white)
            Text(label)
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(.white.opacity(0.45))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .background(Color.kineticsDark)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.white.opacity(0.07), lineWidth: 0.5)
        )
    }
}

// MARK: - SignInSheet

/// Modal sheet for email/password sign-in and account creation.
///
/// The sheet is presented from `HomeView` when the auth pill is tapped.
/// It uses the existing `AuthManager` methods on `AppState` — no extra
/// auth logic lives here.
struct SignInSheet: View {

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var email = ""
    @State private var password = ""
    @State private var isCreatingAccount = false

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    // MARK: Heading
                    VStack(alignment: .leading, spacing: 6) {
                        Text(isCreatingAccount ? "Create Account" : "Welcome Back")
                            .font(.system(size: 26, weight: .bold))
                            .foregroundStyle(.white)

                        Text(
                            isCreatingAccount
                                ? "Save your sessions and track progress over time."
                                : "Sign in to access your session history."
                        )
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.45))
                    }
                    .padding(.bottom, 28)

                    // MARK: Fields
                    VStack(spacing: 10) {
                        TextField("Email", text: $email)
                            .textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .textFieldStyle(KineticsTextFieldStyle())

                        SecureField("Password", text: $password)
                            .textContentType(
                                isCreatingAccount ? .newPassword : .password
                            )
                            .textFieldStyle(KineticsTextFieldStyle())
                    }
                    .padding(.bottom, 16)

                    // MARK: Error
                    if let error = appState.authManager.authError {
                        Text(error)
                            .font(.system(size: 13))
                            .foregroundStyle(Color.kineticsRed)
                            .padding(.bottom, 12)
                    }

                    // MARK: Primary Action
                    Button {
                        Task {
                            if isCreatingAccount {
                                try? await appState.authManager.createAccount(
                                    email: email,
                                    password: password
                                )
                            } else {
                                try? await appState.authManager.signInWithEmail(
                                    email,
                                    password: password
                                )
                            }
                            if appState.authManager.isSignedIn { dismiss() }
                        }
                    } label: {
                        Group {
                            if appState.authManager.isLoading {
                                ProgressView()
                                    .tint(Color.kineticsDark)
                            } else {
                                Text(
                                    isCreatingAccount
                                        ? "Create Account"
                                        : "Sign In"
                                )
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(Color.kineticsDark)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(Color.kineticsBlue)
                        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                    }
                    .disabled(
                        email.trimmingCharacters(in: .whitespaces).isEmpty
                            || password.isEmpty
                            || appState.authManager.isLoading
                    )
                    .padding(.bottom, 12)

                    // MARK: Divider
                    HStack(spacing: 10) {
                        Rectangle()
                            .fill(.white.opacity(0.10))
                            .frame(height: 0.5)
                        Text("or")
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.30))
                        Rectangle()
                            .fill(.white.opacity(0.10))
                            .frame(height: 0.5)
                    }
                    .padding(.bottom, 12)

                    // MARK: Sign in with Apple
                    SignInWithAppleButton(.signIn) { request in
                        request.requestedScopes = [.fullName, .email]
                    } onCompletion: { _ in
                        // Handled inside AuthManager.signInWithApple()
                    }
                    .signInWithAppleButtonStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                    .onTapGesture {
                        Task {
                            try? await appState.authManager.signInWithApple()
                            if appState.authManager.isSignedIn { dismiss() }
                        }
                    }
                    .padding(.bottom, 12)

                    // MARK: Anonymous Continue
                    Button {
                        Task {
                            try? await appState.authManager.signInAnonymously()
                            dismiss()
                        }
                    } label: {
                        Text("Continue without account")
                            .font(.system(size: 14))
                            .foregroundStyle(.white.opacity(0.40))
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                    }
                    .padding(.bottom, 4)

                    // MARK: Toggle Mode
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isCreatingAccount.toggle()
                        }
                    } label: {
                        Text(
                            isCreatingAccount
                                ? "Already have an account? Sign In"
                                : "Don't have an account? Create one"
                        )
                        .font(.system(size: 13))
                        .foregroundStyle(Color.kineticsBlue)
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
            }
            .background(Color.kineticsBackground)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.kineticsBlue)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(Color.kineticsBackground)
        .presentationCornerRadius(20)
    }
}

// MARK: - KineticsTextFieldStyle

/// Dark-surface text field used in the sign-in sheet.
struct KineticsTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(Color.kineticsMidGray)
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(.white.opacity(0.08), lineWidth: 0.5)
            )
    }
}

// MARK: - Preview

#Preview {
    HomeView()
        .environment(AppState.preview)
}
