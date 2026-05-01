import AuthenticationServices
import SwiftUI

// MARK: - HomeView

/// Redesigned Home tab with five distinct sections:
/// 1. Hero greeting header with time-based salutation and streak pill
/// 2. Today's snapshot card (HealthKit stats + weekly progress ring)
/// 3. Quick-launch horizontal module cards
/// 4. AI coaching insights card
/// 5. Recent activity feed
struct HomeView: View {

    // MARK: - Dependencies

    @Environment(AppState.self) private var appState
    @State private var viewModel = HomeViewModel()
    @State private var showSignIn = false
    @State private var confirmSignOut = false

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 24) {
                    heroHeader
                        .padding(.horizontal, 20)
                        .padding(.top, 8)

                    todaySnapshotCard
                        .padding(.horizontal, 16)

                    quickLaunchSection
                        .padding(.horizontal, 16)

                    aiInsightsSection
                        .padding(.horizontal, 16)

                    if appState.authManager.isSignedIn {
                        recentActivitySection
                            .padding(.horizontal, 16)
                    }

                    Spacer(minLength: 32)
                }
            }
            .background(Color.kineticsBackground)
            .navigationDestination(for: SportType.self) { sport in
                moduleView(for: sport)
            }
            .sheet(isPresented: $showSignIn) {
                SignInSheet()
                    .environment(appState)
            }
            .onChange(of: showSignIn) { _, isShowing in
                guard !isShowing, let uid = appState.authManager.currentUser?.uid else { return }
                Task { await viewModel.loadHistory(for: uid) }
            }
            .confirmationDialog("Account", isPresented: $confirmSignOut, titleVisibility: .visible) {
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
            .task {
                await viewModel.signInAnonymouslyIfNeeded(authManager: appState.authManager)
                if let userId = appState.authManager.currentUser?.uid {
                    await viewModel.loadHistory(for: userId)
                }
                await viewModel.loadDashboardStats()
            }
        }
    }

    // MARK: - 1. Hero Header

    private var heroHeader: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text(greetingText)
                    .font(.system(size: 28, weight: .bold, design: .default))
                    .foregroundStyle(.white)

                Text(formattedDate)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(.white.opacity(0.42))
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 8) {
                authPill

                if viewModel.streakDays > 0 {
                    streakPill
                }
            }
        }
    }

    private var greetingText: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let name = displayFirstName
        switch hour {
        case 0..<12:  return "Good morning, \(name) 👋"
        case 12..<17: return "Good afternoon, \(name) 👋"
        default:      return "Good evening, \(name) 👋"
        }
    }

    private var displayFirstName: String {
        guard let user = appState.authManager.currentUser, user.isAnonymous == false else {
            return "Athlete"
        }
        return user.email?
            .components(separatedBy: "@").first?
            .components(separatedBy: ".").first?
            .capitalized ?? "Athlete"
    }

    private var formattedDate: String {
        Date().formatted(.dateTime.weekday(.wide).month(.wide).day())
    }

    private var streakPill: some View {
        HStack(spacing: 5) {
            Image(systemName: "flame.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.kineticsAmber)
            Text("\(viewModel.streakDays) day streak")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.88))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.kineticsAmber.opacity(0.13))
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .strokeBorder(Color.kineticsAmber.opacity(0.30), lineWidth: 0.75)
        )
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
                            color: (isAnonymous ? Color.yellow : Color.kineticsGreen).opacity(0.8),
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

    // MARK: - 2. Today's Snapshot Card

    private var todaySnapshotCard: some View {
        ZStack(alignment: .topLeading) {
            // Gradient background
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.04, green: 0.08, blue: 0.18),
                            Color(red: 0.04, green: 0.04, blue: 0.10)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            // Subtle blue glow top-right
            RadialGradient(
                colors: [Color.kineticsBlue.opacity(0.18), .clear],
                center: .topTrailing,
                startRadius: 0,
                endRadius: 160
            )
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

            // Hairline border
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.kineticsBlue.opacity(0.18), lineWidth: 0.75)

            // Content
            VStack(alignment: .leading, spacing: 16) {
                // Header row
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("TODAY'S SNAPSHOT")
                            .font(.system(size: 10, weight: .semibold))
                            .tracking(2.5)
                            .foregroundStyle(.white.opacity(0.40))

                        Text(todayStatusText)
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(.white)
                    }

                    Spacer()

                    // Weekly progress ring
                    weeklyProgressRing
                }

                // Stats row
                HStack(spacing: 10) {
                    snapshotStatBadge(
                        icon: "figure.walk",
                        color: Color.kineticsBlue,
                        value: viewModel.dashboardStats.steps > 0
                            ? HomeView.formattedSteps(viewModel.dashboardStats.steps) : "--",
                        unit: "steps"
                    )
                    snapshotStatBadge(
                        icon: "flame.fill",
                        color: Color.kineticsAmber,
                        value: viewModel.dashboardStats.activeCalories > 0
                            ? String(Int(viewModel.dashboardStats.activeCalories)) : "--",
                        unit: "kcal"
                    )
                    snapshotStatBadge(
                        icon: "heart.fill",
                        color: Color.kineticsGreen,
                        value: viewModel.dashboardStats.restingHeartRate > 0
                            ? String(Int(viewModel.dashboardStats.restingHeartRate)) : "--",
                        unit: "bpm"
                    )
                }
            }
            .padding(18)
        }
    }

    private var todayStatusText: String {
        guard let last = viewModel.recentSessions.first else { return "Rest Day" }
        let cal = Calendar.current
        if cal.isDateInToday(last.startedAt) {
            return "Active Today · \(last.sport.displayName)"
        }
        return "Rest Day"
    }

    private var weeklySessionCount: Int {
        let cal = Calendar.current
        guard let weekStart = cal.dateInterval(of: .weekOfYear, for: Date())?.start else { return 0 }
        return viewModel.recentSessions.filter { $0.startedAt >= weekStart }.count
    }

    private var weeklyProgressRing: some View {
        let target: Int = 5
        let count = min(weeklySessionCount, target)
        let progress = target > 0 ? Double(count) / Double(target) : 0.0

        return ZStack {
            Circle()
                .stroke(Color.white.opacity(0.08), lineWidth: 5)
                .frame(width: 58, height: 58)

            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    LinearGradient(
                        colors: [Color.kineticsBlue, Color.kineticsGreen],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    style: StrokeStyle(lineWidth: 5, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .frame(width: 58, height: 58)
                .animation(.spring(response: 0.6, dampingFraction: 0.8), value: progress)

            VStack(spacing: 1) {
                Text("\(count)")
                    .font(.system(size: 16, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                Text("/\(target)")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.40))
            }
        }
    }

    private func snapshotStatBadge(icon: String, color: Color, value: String, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(color)

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text(unit)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.white.opacity(0.40))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - 3. Quick Launch Section

    private var quickLaunchSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("QUICK LAUNCH")
                .font(.system(size: 10, weight: .semibold))
                .tracking(2.5)
                .foregroundStyle(.white.opacity(0.38))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(SportType.allCases, id: \.self) { sport in
                        NavigationLink(value: sport) {
                            QuickLaunchCard(
                                sport: sport,
                                lastSession: viewModel.recentSessions.first { $0.sport == sport }
                            )
                        }
                        .buttonStyle(ScaleButtonStyle())
                    }
                }
                .padding(.horizontal, 2)
                .padding(.vertical, 2)
            }
        }
    }

    // MARK: - 4. AI Insights Section

    private var aiInsightsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("AI INSIGHTS")
                .font(.system(size: 10, weight: .semibold))
                .tracking(2.5)
                .foregroundStyle(.white.opacity(0.38))

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(white: 0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(.white.opacity(0.07), lineWidth: 0.5)
                    )

                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 10) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.kineticsPurple.opacity(0.15))
                                .frame(width: 38, height: 38)
                            Image(systemName: "brain.head.profile")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(Color.kineticsPurple)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Coach AI")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.white)
                            Text("Personalized feedback")
                                .font(.system(size: 11))
                                .foregroundStyle(.white.opacity(0.40))
                        }
                    }

                    if viewModel.recentSessions.isEmpty {
                        HStack(spacing: 10) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 14))
                                .foregroundStyle(Color.kineticsPurple.opacity(0.6))
                            Text("Complete your first session to unlock AI insights.")
                                .font(.system(size: 13))
                                .foregroundStyle(.white.opacity(0.50))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    } else {
                        VStack(spacing: 10) {
                            ForEach(aiInsights(from: viewModel.recentSessions), id: \.self) { insight in
                                AIInsightRow(text: insight)
                            }
                        }
                    }
                }
                .padding(16)
            }
        }
    }

    private func aiInsights(from sessions: [SessionResult]) -> [String] {
        var insights: [String] = []

        // Most-used module this week
        let cal = Calendar.current
        let weekStart = cal.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()
        let weekSessions = sessions.filter { $0.startedAt >= weekStart }
        if !weekSessions.isEmpty {
            let counts = Dictionary(grouping: weekSessions, by: \.sport).mapValues(\.count)
            if let top = counts.max(by: { $0.value < $1.value })?.key {
                insights.append("You're most active in \(top.displayName) this week — keep the momentum going.")
            }
        }

        // Metric-based insight from most recent session
        if let latest = sessions.first {
            if let velocity = latest.metrics["strikeVelocityMPH"] {
                insights.append("Latest strike velocity: \(String(format: "%.1f", velocity)) mph — focus on hip rotation for more power.")
            } else if let barDev = latest.metrics["barPathDeviationCM"] {
                insights.append("Bar path deviation was \(String(format: "%.1f", barDev)) cm — aim for a straighter vertical path.")
            } else if let hipProx = latest.metrics["hipToWallProximity"] {
                insights.append("Hip proximity score: \(String(format: "%.0f", hipProx * 100))% — closer hips mean less arm strain on the wall.")
            } else {
                insights.append("Great session on \(latest.sport.displayName) — \(latest.formattedDate).")
            }
        }

        // Consistency nudge
        if sessions.count >= 3 {
            insights.append("You're building a habit — \(sessions.count) sessions logged so far. Consistency compounds.")
        }

        return Array(insights.prefix(3))
    }

    // MARK: - 5. Recent Activity Feed

    private var recentActivitySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("RECENT ACTIVITY")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(2.5)
                    .foregroundStyle(.white.opacity(0.38))

                Spacer()

                if viewModel.isLoadingHistory {
                    ProgressView()
                        .tint(.white.opacity(0.3))
                        .scaleEffect(0.7)
                }
            }

            if viewModel.isLoadingHistory && viewModel.recentSessions.isEmpty {
                activitySkeleton
            } else if !viewModel.isLoadingHistory && viewModel.recentSessions.isEmpty {
                emptyActivityState
            } else {
                activityFeed
            }
        }
    }

    private var activityFeed: some View {
        VStack(spacing: 0) {
            ForEach(viewModel.recentSessions) { session in
                ActivityFeedRow(session: session)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)

                if session.id != viewModel.recentSessions.last?.id {
                    Rectangle()
                        .fill(.white.opacity(0.06))
                        .frame(height: 0.5)
                        .padding(.horizontal, 14)
                }
            }
        }
        .background(Color(white: 0.08))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.white.opacity(0.06), lineWidth: 0.5)
        )
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
        .background(Color(white: 0.08))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var activitySkeleton: some View {
        VStack(spacing: 0) {
            ForEach(0..<3, id: \.self) { _ in
                SkeletonRow()
            }
        }
        .background(Color(white: 0.08))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - Formatting Helpers

    private static func formattedSteps(_ steps: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: steps)) ?? String(steps)
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

// MARK: - QuickLaunchCard

/// Horizontal-scroll sport card for the Quick Launch section.
/// Shows sport gradient, icon, name, and relative time of last session.
private struct QuickLaunchCard: View {

    let sport: SportType
    let lastSession: SessionResult?

    private var accent: Color { Color.moduleColor(for: sport) }

    private var relativeTime: String {
        guard let session = lastSession else { return "Never" }
        let interval = Date().timeIntervalSince(session.startedAt)
        let days = Int(interval / 86400)
        if days == 0 { return "Today" }
        if days == 1 { return "Yesterday" }
        return "\(days) days ago"
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // Base
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.kineticsDark)

            // Ghost icon background
            Image(systemName: sport.systemImage)
                .font(.system(size: 64, weight: .black))
                .foregroundStyle(accent.opacity(0.10))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(.top, 8)
                .padding(.trailing, 8)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            // Bottom gradient
            LinearGradient(
                colors: [.clear, accent.opacity(0.26)],
                startPoint: .top,
                endPoint: .bottom
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            // Border
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(accent.opacity(0.22), lineWidth: 0.75)

            // Text content
            VStack(alignment: .leading, spacing: 4) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(accent.opacity(0.18))
                        .frame(width: 36, height: 36)
                    Image(systemName: sport.systemImage)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(accent)
                }

                Spacer()

                Text(sport.displayName)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Text(relativeTime)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(.white.opacity(0.42))

                Text("Tap to start")
                    .font(.system(size: 9, weight: .medium))
                    .tracking(0.5)
                    .foregroundStyle(accent.opacity(0.7))
                    .padding(.top, 2)
            }
            .padding(12)
        }
        .frame(width: 138, height: 170)
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

// MARK: - AIInsightRow

/// A single coaching insight bullet in the AI Insights card.
private struct AIInsightRow: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(Color.kineticsPurple.opacity(0.55))
                .frame(width: 6, height: 6)
                .padding(.top, 5)

            Text(text)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(.white.opacity(0.78))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - ActivityFeedRow

/// A single row in the Recent Activity feed.
private struct ActivityFeedRow: View {
    let session: SessionResult

    private var accent: Color { Color.moduleColor(for: session.sport) }

    private var topMetricText: String {
        if let velocity = session.metrics["strikeVelocityMPH"] {
            return String(format: "%.1f mph", velocity)
        }
        if let barDev = session.metrics["barPathDeviationCM"] {
            return String(format: "%.1f cm dev", barDev)
        }
        if let hipProx = session.metrics["hipToWallProximity"] {
            return String(format: "%.0f%% prox", hipProx * 100)
        }
        return session.formattedDuration
    }

    var body: some View {
        HStack(spacing: 12) {
            // Sport icon badge
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(accent.opacity(0.14))
                    .frame(width: 40, height: 40)
                Image(systemName: session.sport.systemImage)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(accent)
            }

            // Labels
            VStack(alignment: .leading, spacing: 3) {
                Text(session.sport.displayName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                Text(session.formattedDate)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.40))
            }

            Spacer()

            // Top metric
            Text(topMetricText)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(Color.kineticsGreen)
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
                            .textContentType(isCreatingAccount ? .newPassword : .password)
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
                                Text(isCreatingAccount ? "Create Account" : "Sign In")
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
