import SwiftUI

// MARK: - DiscoverViewModel

@Observable
@MainActor
final class DiscoverViewModel {

    // MARK: State

    var searchQuery = ""
    var searchResults: [UserProfile] = []
    var isSearching = false
    var searchError: String?

    var topAthletes: [UserProfile] = []
    var trendingWorkouts: [FeedItem] = []
    var suggestedAthletes: [UserProfile] = []

    var isLoadingDiscover = false
    var selectedSport: DiscoverSport?

    // MARK: Follow State Cache

    var followStates: [String: FollowStatus] = [:]

    // MARK: Search Task

    private var searchTask: Task<Void, Never>?

    // MARK: Load Discover

    func loadDiscover(currentUserId: String) async {
        guard !isLoadingDiscover else { return }
        isLoadingDiscover = true
        defer { isLoadingDiscover = false }

        async let athletesFetch = SocialRepository.shared.fetchTopAthletes(limit: 8)
        async let trendingFetch = SocialRepository.shared.fetchTrendingWorkouts(limit: 3)
        async let suggestedFetch = SocialRepository.shared.fetchSuggestedAthletes(currentUserId: currentUserId, limit: 10)

        let (athletes, trending, suggested) = await (
            (try? athletesFetch) ?? [],
            (try? trendingFetch) ?? [],
            (try? suggestedFetch) ?? []
        )

        topAthletes = athletes
        trendingWorkouts = trending
        suggestedAthletes = suggested

        // Pre-load follow states for all users shown
        let allUserIds = (athletes + suggested).map(\.id)
        await loadFollowStates(for: allUserIds, currentUserId: currentUserId)
    }

    // MARK: Search

    func onSearchChanged(currentUserId: String) {
        searchTask?.cancel()
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)

        guard query.count >= 1 else {
            searchResults = []
            searchError = nil
            return
        }

        searchTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000) // 300ms debounce
            guard !Task.isCancelled else { return }

            isSearching = true
            searchError = nil
            defer { isSearching = false }

            do {
                let results = try await SocialRepository.shared.searchUsers(query: query)
                guard !Task.isCancelled else { return }
                searchResults = results

                let ids = results.map(\.id)
                await loadFollowStates(for: ids, currentUserId: currentUserId)
            } catch {
                guard !Task.isCancelled else { return }
                searchError = "Search failed. Check your connection."
                searchResults = []
            }
        }
    }

    // MARK: Follow

    func follow(userId: String, displayName: String, username: String, currentUserId: String, currentDisplayName: String) async {
        followStates[userId] = .requested
        do {
            try await SocialRepository.shared.follow(
                currentUserId: currentUserId,
                currentDisplayName: currentDisplayName,
                currentUsername: "",
                targetUserId: userId,
                targetDisplayName: displayName,
                targetUsername: username,
                isTargetPublic: true
            )
            followStates[userId] = .following
        } catch {
            followStates[userId] = .notFollowing
        }
    }

    func unfollow(userId: String, currentUserId: String) async {
        followStates[userId] = .notFollowing
        try? await SocialRepository.shared.unfollow(currentUserId: currentUserId, targetUserId: userId)
    }

    // MARK: Private

    private func loadFollowStates(for userIds: [String], currentUserId: String) async {
        await withTaskGroup(of: (String, FollowStatus).self) { group in
            for id in userIds {
                group.addTask {
                    let status = await SocialRepository.shared.followStatus(currentUserId: currentUserId, targetUserId: id)
                    return (id, status)
                }
            }
            for await (id, status) in group {
                followStates[id] = status
            }
        }
    }
}

// MARK: - DiscoverSport

enum DiscoverSport: String, CaseIterable {
    case lifting = "Lifting"
    case running = "Running"
    case striking = "Striking"
    case grappling = "Grappling"
    case climbing = "Climbing"

    var icon: String {
        switch self {
        case .lifting:   return "dumbbell.fill"
        case .running:   return "figure.run"
        case .striking:  return "figure.boxing"
        case .grappling: return "figure.martial.arts"
        case .climbing:  return "figure.climbing"
        }
    }

    var activityKey: String {
        switch self {
        case .lifting:   return "iron"
        case .running:   return "run"
        case .striking:  return "striking"
        case .grappling: return "grappling"
        case .climbing:  return "wall"
        }
    }

    var accentColor: Color {
        switch self {
        case .lifting:   return .kineticsBlue
        case .running:   return .kineticsGreen
        case .striking:  return .kineticsRed
        case .grappling: return .kineticsOrange
        case .climbing:  return .kineticsPurple
        }
    }
}

// MARK: - SearchDiscoverView

@MainActor
struct SearchDiscoverView: View {

    @Environment(AppState.self) private var appState
    @State private var viewModel = DiscoverViewModel()
    @Environment(\.dismiss) private var dismiss
    @State private var profilePreviewUserId: String?

    private var currentUserId: String {
        appState.authManager.currentUser?.uid ?? ""
    }

    private var currentDisplayName: String {
        let user = appState.authManager.currentUser
        if user?.isAnonymous == true { return "Athlete" }
        return user?.email?.components(separatedBy: "@").first?.capitalized ?? "Athlete"
    }

    private var isSearchMode: Bool {
        !viewModel.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.kineticsBackground.ignoresSafeArea()
                VStack(spacing: 0) {
                    searchBar
                    Divider().background(.white.opacity(0.07))
                    if isSearchMode {
                        searchResultsList
                    } else {
                        discoverScrollContent
                    }
                }
            }
            .navigationTitle("Discover")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.kineticsBackground, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Color.kineticsBlue)
                        .font(.system(size: 15, weight: .semibold))
                }
            }
            .task {
                await viewModel.loadDiscover(currentUserId: currentUserId)
            }
            .sheet(isPresented: Binding(
                get: { profilePreviewUserId != nil },
                set: { if !$0 { profilePreviewUserId = nil } }
            )) {
                if let userId = profilePreviewUserId {
                    UserProfilePreviewSheet(userId: userId)
                        .environment(appState)
                }
            }
        }
    }

    // MARK: Search Bar

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color.kineticsSubtext)
            TextField("Search athletes...", text: $viewModel.searchQuery)
                .font(.system(size: 16))
                .foregroundStyle(.white)
                .tint(Color.kineticsBlue)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .onChange(of: viewModel.searchQuery) {
                    viewModel.onSearchChanged(currentUserId: currentUserId)
                }
            if !viewModel.searchQuery.isEmpty {
                Button {
                    viewModel.searchQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(Color.kineticsSubtext)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(Color(white: 0.1), in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: Discover Content

    private var discoverScrollContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 28) {
                topAthletesSection
                trendingWorkoutsSection
                bySportSection
                suggestedAthletesSection
            }
            .padding(.bottom, 32)
        }
    }

    // MARK: Top Athletes Section

    private var topAthletesSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader(title: "Top Athletes This Week", icon: "flame.fill", iconColor: .kineticsAmber)
            if viewModel.isLoadingDiscover {
                topAthletesLoadingPlaceholder
            } else if viewModel.topAthletes.isEmpty {
                emptySection(message: "No athletes found")
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(viewModel.topAthletes) { athlete in
                            TopAthleteCard(
                                profile: athlete,
                                followStatus: viewModel.followStates[athlete.id] ?? .notFollowing,
                                onFollow: {
                                    Task {
                                        await viewModel.follow(
                                            userId: athlete.id,
                                            displayName: athlete.displayName,
                                            username: athlete.username,
                                            currentUserId: currentUserId,
                                            currentDisplayName: currentDisplayName
                                        )
                                    }
                                },
                                onTap: { profilePreviewUserId = athlete.id }
                            )
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
        .padding(.top, 20)
    }

    private var topAthletesLoadingPlaceholder: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(0..<5, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color(white: 0.1))
                        .frame(width: 110, height: 140)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    // MARK: Trending Workouts Section

    private var trendingWorkoutsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader(title: "Trending Workouts", icon: "arrow.up.right.circle.fill", iconColor: .kineticsBlue)
            if viewModel.isLoadingDiscover {
                ForEach(0..<3, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(white: 0.1))
                        .frame(height: 72)
                        .padding(.horizontal, 16)
                }
            } else if viewModel.trendingWorkouts.isEmpty {
                emptySection(message: "No trending workouts yet").padding(.horizontal, 16)
            } else {
                VStack(spacing: 10) {
                    ForEach(viewModel.trendingWorkouts) { item in
                        TrendingWorkoutCard(item: item)
                            .padding(.horizontal, 16)
                    }
                }
            }
        }
    }

    // MARK: By Sport Section

    private var bySportSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader(title: "By Sport", icon: "square.grid.2x2.fill", iconColor: .kineticsPurple)
            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())],
                spacing: 10
            ) {
                ForEach(DiscoverSport.allCases, id: \.self) { sport in
                    SportTileButton(sport: sport, isSelected: viewModel.selectedSport == sport) {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            viewModel.selectedSport = viewModel.selectedSport == sport ? nil : sport
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            if let selected = viewModel.selectedSport {
                let filtered = viewModel.trendingWorkouts.filter {
                    $0.activityType == selected.activityKey
                }
                if filtered.isEmpty {
                    Text("No \(selected.rawValue) posts yet")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.kineticsSubtext)
                        .padding(.horizontal, 16)
                } else {
                    VStack(spacing: 10) {
                        ForEach(filtered) { item in
                            TrendingWorkoutCard(item: item)
                                .padding(.horizontal, 16)
                        }
                    }
                }
            }
        }
    }

    // MARK: Suggested Athletes Section

    private var suggestedAthletesSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader(title: "Suggested Athletes", icon: "person.2.fill", iconColor: .kineticsGreen)
            if viewModel.suggestedAthletes.isEmpty && !viewModel.isLoadingDiscover {
                emptySection(message: "No suggestions right now").padding(.horizontal, 16)
            } else {
                VStack(spacing: 0) {
                    ForEach(viewModel.suggestedAthletes) { athlete in
                        UserSearchRow(
                            profile: athlete,
                            followStatus: viewModel.followStates[athlete.id] ?? .notFollowing,
                            onFollow: {
                                Task {
                                    await viewModel.follow(
                                        userId: athlete.id,
                                        displayName: athlete.displayName,
                                        username: athlete.username,
                                        currentUserId: currentUserId,
                                        currentDisplayName: currentDisplayName
                                    )
                                }
                            },
                            onUnfollow: {
                                Task { await viewModel.unfollow(userId: athlete.id, currentUserId: currentUserId) }
                            },
                            onTap: { profilePreviewUserId = athlete.id }
                        )
                        .padding(.horizontal, 16)
                        Divider().background(.white.opacity(0.05)).padding(.horizontal, 16)
                    }
                }
            }
        }
    }

    // MARK: Search Results

    private var searchResultsList: some View {
        Group {
            if viewModel.isSearching {
                VStack {
                    Spacer(minLength: 40)
                    ProgressView().tint(Color.kineticsBlue)
                    Text("Searching…")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.kineticsSubtext)
                        .padding(.top, 8)
                    Spacer()
                }
            } else if let error = viewModel.searchError {
                centeredMessage(error)
            } else if viewModel.searchResults.isEmpty && !viewModel.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                centeredMessage("No athletes found for '\(viewModel.searchQuery)'")
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(viewModel.searchResults) { profile in
                            UserSearchRow(
                                profile: profile,
                                followStatus: viewModel.followStates[profile.id] ?? .notFollowing,
                                onFollow: {
                                    Task {
                                        await viewModel.follow(
                                            userId: profile.id,
                                            displayName: profile.displayName,
                                            username: profile.username,
                                            currentUserId: currentUserId,
                                            currentDisplayName: currentDisplayName
                                        )
                                    }
                                },
                                onUnfollow: {
                                    Task { await viewModel.unfollow(userId: profile.id, currentUserId: currentUserId) }
                                },
                                onTap: { profilePreviewUserId = profile.id }
                            )
                            .padding(.horizontal, 16)
                            Divider().background(.white.opacity(0.05)).padding(.horizontal, 16)
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
        }
    }

    // MARK: Helpers

    private func sectionHeader(title: String, icon: String, iconColor: Color) -> some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(iconColor)
            Text(title)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 16)
    }

    private func emptySection(message: String) -> some View {
        Text(message)
            .font(.system(size: 13))
            .foregroundStyle(Color.kineticsSubtext)
    }

    private func centeredMessage(_ message: String) -> some View {
        VStack {
            Spacer(minLength: 60)
            Image(systemName: "person.slash")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(Color.kineticsSubtext.opacity(0.5))
                .padding(.bottom, 10)
            Text(message)
                .font(.system(size: 14))
                .foregroundStyle(Color.kineticsSubtext)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Spacer()
        }
    }
}

// MARK: - TopAthleteCard

private struct TopAthleteCard: View {

    let profile: UserProfile
    let followStatus: FollowStatus
    let onFollow: () -> Void
    let onTap: () -> Void

    private var emoji: String {
        String(profile.displayName.prefix(1)).uppercased()
    }

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(
                            colors: [Color.kineticsPurple, Color.kineticsBlue],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ))
                        .frame(width: 54, height: 54)
                    Text(emoji)
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }
                VStack(spacing: 2) {
                    Text(profile.displayName)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    SportBadge(sport: profile.primarySport)
                }
                Text("\(profile.totalWorkouts) workouts")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.kineticsSubtext)
                DiscoverFollowButton(status: followStatus, onFollow: onFollow)
                    .frame(maxWidth: .infinity)
            }
            .padding(12)
            .frame(width: 110)
            .background(Color(white: 0.08), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.07), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - TrendingWorkoutCard

private struct TrendingWorkoutCard: View {

    let item: FeedItem

    private var activityIcon: String {
        switch item.activityType {
        case "run":      return "figure.run"
        case "striking": return "figure.boxing"
        case "grappling": return "figure.martial.arts"
        case "iron", "ironTracker", "gym": return "dumbbell.fill"
        case "wall":     return "figure.climbing"
        default:         return "bolt.fill"
        }
    }

    private var accentColor: Color {
        switch item.activityType {
        case "run":      return .kineticsBlue
        case "striking": return .kineticsRed
        case "grappling": return .kineticsOrange
        case "iron", "ironTracker", "gym": return .kineticsBlue
        case "wall":     return .kineticsGreen
        default:         return .kineticsPurple
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(accentColor.opacity(0.15)).frame(width: 40, height: 40)
                Image(systemName: activityIcon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(accentColor)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text("by \(item.displayName)")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.kineticsSubtext)
            }
            Spacer()
            HStack(spacing: 4) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.kineticsRed.opacity(0.8))
                Text("\(item.kudosCount)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.kineticsSubtext)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color(white: 0.08), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.white.opacity(0.06), lineWidth: 1))
    }
}

// MARK: - SportTileButton

private struct SportTileButton: View {

    let sport: DiscoverSport
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(isSelected ? sport.accentColor : sport.accentColor.opacity(0.12))
                        .frame(width: 44, height: 44)
                    Image(systemName: sport.icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(isSelected ? .black : sport.accentColor)
                }
                Text(sport.rawValue)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(isSelected ? .white : Color.kineticsSubtext)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                isSelected
                    ? sport.accentColor.opacity(0.12)
                    : Color(white: 0.08),
                in: RoundedRectangle(cornerRadius: 12)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(isSelected ? sport.accentColor.opacity(0.4) : .white.opacity(0.07), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - UserSearchRow

struct UserSearchRow: View {

    let profile: UserProfile
    let followStatus: FollowStatus
    let onFollow: () -> Void
    let onUnfollow: () -> Void
    var onTap: (() -> Void)? = nil

    var body: some View {
        Button(action: { onTap?() }) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(
                            colors: [Color.kineticsPurple, Color.kineticsBlue],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ))
                        .frame(width: 44, height: 44)
                    Text(String(profile.displayName.prefix(1)).uppercased())
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(profile.displayName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(profile.username)
                        .font(.system(size: 13))
                        .foregroundStyle(Color.kineticsSubtext)
                        .lineLimit(1)
                }
                Spacer()
                SportBadge(sport: profile.primarySport)
                if followStatus != .self_ {
                    DiscoverFollowButton(status: followStatus, onFollow: followStatus == .following ? onUnfollow : onFollow)
                }
            }
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
        .disabled(onTap == nil)
    }
}

// MARK: - DiscoverFollowButton

struct DiscoverFollowButton: View {

    let status: FollowStatus
    let onFollow: () -> Void

    var body: some View {
        Button(action: onFollow) {
            HStack(spacing: 4) {
                if status == .following {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                }
                Text(label)
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(background)
            .clipShape(Capsule())
            .overlay(
                Capsule().strokeBorder(strokeColor, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var label: String {
        switch status {
        case .notFollowing: return "Follow"
        case .requested:    return "Requested"
        case .following:    return "Following"
        case .self_:        return ""
        }
    }

    private var foregroundColor: Color {
        switch status {
        case .notFollowing: return .kineticsBackground
        case .requested:    return Color.kineticsSubtext
        case .following:    return Color.kineticsGreen
        case .self_:        return .clear
        }
    }

    private var background: AnyShapeStyle {
        switch status {
        case .notFollowing: return AnyShapeStyle(Color.kineticsBlue)
        case .requested:    return AnyShapeStyle(Color.clear)
        case .following:    return AnyShapeStyle(Color.clear)
        case .self_:        return AnyShapeStyle(Color.clear)
        }
    }

    private var strokeColor: Color {
        switch status {
        case .notFollowing: return Color.clear
        case .requested:    return Color.kineticsSubtext.opacity(0.4)
        case .following:    return Color.kineticsGreen.opacity(0.5)
        case .self_:        return Color.clear
        }
    }
}

// MARK: - SportBadge

struct SportBadge: View {

    let sport: String

    private var label: String {
        switch sport {
        case "striking":  return "Striking"
        case "grappling": return "Grappling"
        case "iron", "ironTracker", "gym": return "Lifting"
        case "wall":      return "Climbing"
        case "run":       return "Running"
        default:          return sport.capitalized
        }
    }

    private var color: Color {
        switch sport {
        case "striking":  return .kineticsRed
        case "grappling": return .kineticsOrange
        case "iron", "ironTracker", "gym": return .kineticsBlue
        case "wall":      return .kineticsGreen
        case "run":       return Color(red: 0.3, green: 0.8, blue: 1.0)
        default:          return .kineticsPurple
        }
    }

    var body: some View {
        Text(label)
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.12), in: Capsule())
    }
}
