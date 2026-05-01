import FirebaseFirestore
import SwiftUI
import UIKit

// MARK: - FeedFilter

enum FeedFilter: String, CaseIterable, Sendable {
    case forYou = "For You"
    case following = "Following"
    case trending = "Trending"

    var icon: String {
        switch self {
        case .forYou:     return "sparkles"
        case .following:  return "person.2"
        case .trending:   return "chart.line.uptrend.xyaxis"
        }
    }
}

// MARK: - FeedViewModel

@Observable
@MainActor
final class FeedViewModel {

    // MARK: - Feed state

    var feedItems: [FeedItem] = []
    var isLoading = false
    var isRefreshing = false
    var isLoadingMore = false
    var hasMore = true
    var errorMessage: String?
    var showErrorBanner = false

    // MARK: - Tab / filter

    var selectedFilter: FeedFilter = .forYou

    // MARK: - Trending

    var trendingItems: [FeedItem] = []

    // MARK: - Following filter

    private var followingIds: Set<String> = []

    var filteredItems: [FeedItem] {
        switch selectedFilter {
        case .forYou:
            return feedItems
        case .following:
            guard !followingIds.isEmpty else { return [] }
            return feedItems.filter { followingIds.contains($0.userId) }
        case .trending:
            return trendingItems
        }
    }

    var isFollowingEmpty: Bool {
        selectedFilter == .following && followingIds.isEmpty
    }

    // MARK: - New posts banner

    var newPostsAvailable = false
    var newPostsCount = 0
    private var pendingNewPosts: [FeedItem] = []
    private var listenerRegistration: ListenerRegistration?

    // MARK: - UI state

    var showNewPostSheet = false
    var showErrorBannerValue = false
    var stories: [StoryModel] = []
    var selectedStory: StoryModel?
    var showStorySheet = false
    var commentItem: FeedItem?
    var showCommentSheet = false
    var kudosFloatingItems: [String: Bool] = [:]
    var scrollToTopTrigger = false

    // MARK: - Pagination cursor

    /// `postedAt` timestamp (ms) of the oldest item in `feedItems`.
    private var oldestPostedAtMs: Double? {
        feedItems.last.map { $0.postedAt.timeIntervalSince1970 * 1_000 }
    }

    // MARK: - Load

    func load(currentUserId: String) async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            async let feedFetch    = SocialRepository.shared.fetchFeed(after: nil, limit: 15)
            async let storiesFetch = SocialRepository.shared.fetchStories(for: currentUserId)
            async let followFetch  = SocialRepository.shared.fetchFollowingIds(for: currentUserId)
            let (fetchedFeed, fetchedStories, followedIds) = try await (feedFetch, storiesFetch, followFetch)
            feedItems      = fetchedFeed
            stories        = fetchedStories
            followingIds   = Set(followedIds)
            trendingItems  = fetchedFeed.sorted { $0.kudosCount > $1.kudosCount }
            hasMore        = fetchedFeed.count >= 15
            listenForNewPosts()
        } catch {
            errorMessage   = "Couldn't load the feed. Pull to retry."
            showErrorBanner = true
        }
    }

    // MARK: - Refresh

    func refresh(currentUserId: String) async {
        isRefreshing      = true
        errorMessage      = nil
        showErrorBanner   = false
        newPostsAvailable = false
        newPostsCount     = 0
        pendingNewPosts   = []
        defer { isRefreshing = false }
        do {
            // Haptic
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()

            async let feedFetch    = SocialRepository.shared.fetchFeed(after: nil, limit: 15)
            async let storiesFetch = SocialRepository.shared.fetchStories(for: currentUserId)
            async let followFetch  = SocialRepository.shared.fetchFollowingIds(for: currentUserId)
            let (fetchedFeed, fetchedStories, followedIds) = try await (feedFetch, storiesFetch, followFetch)
            feedItems     = fetchedFeed
            stories       = fetchedStories
            followingIds  = Set(followedIds)
            trendingItems = fetchedFeed.sorted { $0.kudosCount > $1.kudosCount }
            hasMore       = fetchedFeed.count >= 15
        } catch {
            errorMessage   = "Couldn't refresh. Check your connection."
            showErrorBanner = true
        }
    }

    // MARK: - Pagination

    func loadMore() async {
        guard !isLoadingMore, hasMore, !isLoading else { return }
        guard let cursor = oldestPostedAtMs else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let older = try await SocialRepository.shared.fetchFeed(after: cursor, limit: 15)
            let existingIds = Set(feedItems.map(\.id))
            let newItems = older.filter { !existingIds.contains($0.id) }
            feedItems.append(contentsOf: newItems)
            // Merge into trending
            let merged = feedItems
            trendingItems = merged.sorted { $0.kudosCount > $1.kudosCount }
            hasMore = older.count >= 15
        } catch {
            // Silent failure — existing items remain visible
        }
    }

    // MARK: - Realtime listener

    func listenForNewPosts() {
        listenerRegistration?.remove()
        guard let latestMs = feedItems.first.map({ $0.postedAt.timeIntervalSince1970 * 1_000 }) else { return }

        listenerRegistration = Firestore.firestore()
            .collection("activity")
            .order(by: "postedAt", descending: true)
            .limit(to: 1)
            .addSnapshotListener { [weak self] snapshot, _ in
                guard let self else { return }
                guard let docs = snapshot?.documents, let doc = docs.first else { return }
                guard let wrapper = doc.data()["data"] as? [String: Any],
                      let ms = wrapper["postedAt"] as? Double,
                      ms > latestMs else { return }
                // A new post has arrived that is newer than our current feed head.
                // We do a lightweight re-fetch to get the actual item.
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if let items = try? await SocialRepository.shared.fetchFeed(after: nil, limit: 5) {
                        let existingIds = Set(self.feedItems.map(\.id))
                        let brand = items.filter { !existingIds.contains($0.id) }
                        if !brand.isEmpty {
                            self.pendingNewPosts  = brand + self.pendingNewPosts
                            self.newPostsCount    = self.pendingNewPosts.count
                            self.newPostsAvailable = true
                        }
                    }
                }
            }
    }

    /// Insert pending new posts at the top of the feed and scroll to top.
    func insertNewPosts() {
        guard !pendingNewPosts.isEmpty else { return }
        feedItems.insert(contentsOf: pendingNewPosts, at: 0)
        trendingItems = feedItems.sorted { $0.kudosCount > $1.kudosCount }
        pendingNewPosts   = []
        newPostsCount     = 0
        newPostsAvailable = false
        scrollToTopTrigger.toggle()
    }

    // MARK: - Kudos

    func toggleKudos(for item: FeedItem, currentUserId: String) async {
        guard let index = feedItems.firstIndex(where: { $0.id == item.id }) else { return }
        let current  = feedItems[index]
        let wasLiked = current.isLikedByCurrentUser
        feedItems[index] = updatedItem(current, kudosDelta: wasLiked ? -1 : 1, liked: !wasLiked)
        if !wasLiked {
            kudosFloatingItems[item.id] = true
            Task {
                try? await Task.sleep(nanoseconds: 800_000_000)
                kudosFloatingItems[item.id] = nil
            }
        }
        do {
            try await SocialRepository.shared.toggleKudos(activityId: item.id, fromUserId: currentUserId)
        } catch {
            feedItems[index] = current
            errorMessage   = "Couldn't update kudos. Try again."
            showErrorBanner = true
        }
    }

    // MARK: - Delete

    func delete(item: FeedItem, userId: String) async {
        do {
            try await SocialRepository.shared.deleteActivity(activityId: item.id, userId: userId)
        } catch {
            errorMessage   = "Couldn't delete post. Try again."
            showErrorBanner = true
            return
        }
        feedItems.removeAll { $0.id == item.id }
        trendingItems.removeAll { $0.id == item.id }
    }

    // MARK: - Sheets

    func openComments(for item: FeedItem) {
        commentItem      = item
        showCommentSheet = true
    }

    func openStory(_ story: StoryModel) {
        selectedStory = story
        showStorySheet = true
    }

    // MARK: - Private helpers

    private func updatedItem(_ item: FeedItem, kudosDelta: Int, liked: Bool) -> FeedItem {
        FeedItem(
            id: item.id, userId: item.userId,
            displayName: item.displayName, username: item.username,
            avatarURL: item.avatarURL, itemType: item.itemType,
            title: item.title, subtitle: item.subtitle,
            caption: item.caption, metrics: item.metrics,
            exerciseSummaries: item.exerciseSummaries,
            routeCoordinates: item.routeCoordinates,
            imageURL: item.imageURL, postedAt: item.postedAt,
            kudosCount: item.kudosCount + kudosDelta,
            commentCount: item.commentCount,
            isLikedByCurrentUser: liked,
            workoutId: item.workoutId,
            activityType: item.activityType
        )
    }
}

// MARK: - FeedView

@MainActor
struct FeedView: View {

    @Environment(AppState.self) private var appState
    @State private var viewModel = FeedViewModel()
    @State private var scrollProxy: ScrollViewProxy?
    @State private var showDiscover = false
    @State private var profilePreviewUserId: String?

    private var currentUserId: String {
        appState.authManager.currentUser?.uid ?? ""
    }

    private var currentDisplayName: String {
        let user = appState.authManager.currentUser
        if user?.isAnonymous == true { return "Athlete" }
        return user?.email?.components(separatedBy: "@").first?.capitalized ?? "Athlete"
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                Color.kineticsBackground.ignoresSafeArea()
                content
                if viewModel.showErrorBanner, let msg = viewModel.errorMessage {
                    ErrorBannerView(message: msg) {
                        withAnimation { viewModel.showErrorBanner = false }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(10)
                }
            }
            .navigationTitle("Feed")
            .toolbarBackground(Color.kineticsBackground, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showDiscover = true
                    } label: {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(Color.kineticsBlue)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        viewModel.showNewPostSheet = true
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "plus")
                                .font(.system(size: 11, weight: .bold))
                            Text("Share Workout")
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                        }
                        .foregroundStyle(Color.kineticsDark)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Color.kineticsBlue)
                        .clipShape(Capsule())
                    }
                }
            }
            .task {
                await FeedSeeder.shared.seedIfNeeded()
                await viewModel.load(currentUserId: currentUserId)
            }
            .onChange(of: viewModel.scrollToTopTrigger) { _, _ in
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    scrollProxy?.scrollTo("feed_top", anchor: .top)
                }
            }
        }
        .sheet(isPresented: $viewModel.showNewPostSheet) {
            ComposePostSheet(
                currentUserId: currentUserId,
                currentDisplayName: currentDisplayName
            ) { newItem in
                viewModel.feedItems.insert(newItem, at: 0)
                viewModel.trendingItems = viewModel.feedItems.sorted { $0.kudosCount > $1.kudosCount }
                viewModel.showNewPostSheet = false
            }
        }
        .sheet(isPresented: $viewModel.showCommentSheet) {
            if let item = viewModel.commentItem {
                CommentSheetView(
                    item: item,
                    currentUserId: currentUserId,
                    currentDisplayName: currentDisplayName,
                    currentUsername: ""
                )
            }
        }
        .sheet(isPresented: $viewModel.showStorySheet) {
            if let story = viewModel.selectedStory {
                StoryFullScreenView(story: story)
            }
        }
        .sheet(isPresented: $showDiscover) {
            SearchDiscoverView()
                .environment(appState)
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

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading && viewModel.feedItems.isEmpty {
            loadingState
        } else {
            feedList
        }
    }

    // MARK: - Feed list

    private var feedList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    // Scroll anchor
                    Color.clear.frame(height: 0).id("feed_top")

                    // Tab bar
                    FeedFilterTabBar(selectedFilter: $viewModel.selectedFilter)
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .padding(.bottom, 6)

                    // Stories bar
                    StoriesBar(
                        stories: viewModel.stories,
                        currentDisplayName: currentDisplayName,
                        onStoryTap: { viewModel.openStory($0) },
                        onYourStoryTap: { viewModel.showNewPostSheet = true }
                    )
                    .padding(.bottom, 4)

                    // New posts banner
                    if viewModel.newPostsAvailable {
                        NewPostsBanner(count: viewModel.newPostsCount) {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                viewModel.insertNewPosts()
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    // Feed cards or empty state
                    if viewModel.isFollowingEmpty {
                        followingEmptyState
                            .padding(.top, 40)
                    } else if viewModel.filteredItems.isEmpty && !viewModel.isLoading {
                        emptyStateView
                            .padding(.top, 40)
                    } else {
                        feedCards
                    }
                }
                .padding(.bottom, 24)
            }
            .refreshable {
                await viewModel.refresh(currentUserId: currentUserId)
            }
            .onAppear {
                scrollProxy = proxy
            }
        }
    }

    // MARK: - Feed cards

    private var feedCards: some View {
        LazyVStack(spacing: 12) {
            ForEach(viewModel.filteredItems) { item in
                ActivityFeedCard(
                    item: item,
                    currentUserId: currentUserId,
                    showFloatingKudos: viewModel.kudosFloatingItems[item.id] == true,
                    onKudos: { await viewModel.toggleKudos(for: item, currentUserId: currentUserId) },
                    onComment: { viewModel.openComments(for: item) },
                    onDelete: item.userId == currentUserId ? {
                        await viewModel.delete(item: item, userId: currentUserId)
                    } : nil,
                    onAvatarTap: {
                        profilePreviewUserId = item.userId
                    }
                )
                .padding(.horizontal, 16)
            }

            // Infinite scroll trigger — fires when last card comes near the bottom
            if !viewModel.filteredItems.isEmpty {
                GeometryReader { geo -> Color in
                    let frame = geo.frame(in: .global)
                    DispatchQueue.main.async {
                        if frame.maxY < UIScreen.main.bounds.height + 200 {
                            Task { await viewModel.loadMore() }
                        }
                    }
                    return Color.clear
                }
                .frame(height: 1)
            }

            // Load more spinner
            if viewModel.isLoadingMore {
                HStack {
                    ProgressView()
                        .tint(Color.kineticsBlue)
                        .scaleEffect(0.9)
                    Text("Loading more…")
                        .font(.system(size: 13, design: .rounded))
                        .foregroundStyle(Color.kineticsSubtext)
                }
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity)
            } else if !viewModel.hasMore && !viewModel.filteredItems.isEmpty {
                Text("You're all caught up 🎯")
                    .font(.system(size: 13, design: .rounded))
                    .foregroundStyle(Color.kineticsSubtext)
                    .padding(.vertical, 20)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - Loading state

    private var loadingState: some View {
        VStack(spacing: 20) {
            ProgressView()
                .tint(Color.kineticsBlue)
                .scaleEffect(1.4)
            Text("Loading feed…")
                .font(.system(size: 14, design: .rounded))
                .foregroundStyle(Color.kineticsSubtext)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Empty state — generic

    private var emptyStateView: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(LinearGradient(
                        colors: [Color.kineticsPurple.opacity(0.18), Color.kineticsBlue.opacity(0.12)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
                    .frame(width: 100, height: 100)
                Image(systemName: "person.2.wave.2")
                    .font(.system(size: 38, weight: .medium))
                    .foregroundStyle(LinearGradient(
                        colors: [Color.kineticsBlue, Color.kineticsPurple],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
            }
            VStack(spacing: 8) {
                Text("No activity yet")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text("Complete a session to share your first performance")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.kineticsSubtext)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }
            Button { viewModel.showNewPostSheet = true } label: {
                HStack(spacing: 8) {
                    Text("Start Training").font(.system(size: 15, weight: .semibold))
                    Image(systemName: "arrow.right").font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(Color.kineticsDark)
                .padding(.horizontal, 24)
                .padding(.vertical, 13)
                .background(Color.kineticsBlue)
                .clipShape(Capsule())
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 40)
    }

    // MARK: - Empty state — following tab

    private var followingEmptyState: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(Color.kineticsDark)
                    .frame(width: 88, height: 88)
                Image(systemName: "person.2.slash")
                    .font(.system(size: 32, weight: .medium))
                    .foregroundStyle(Color.kineticsSubtext)
            }
            VStack(spacing: 8) {
                Text("No one here yet")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text("Follow some athletes to see their workouts here")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.kineticsSubtext)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }
            Button {
                viewModel.selectedFilter = .forYou
            } label: {
                Text("Discover Athletes")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.kineticsDark)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 13)
                    .background(Color.kineticsBlue)
                    .clipShape(Capsule())
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 40)
    }
}

// MARK: - FeedFilterTabBar

private struct FeedFilterTabBar: View {

    @Binding var selectedFilter: FeedFilter
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 4) {
            ForEach(FeedFilter.allCases, id: \.self) { tab in
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        selectedFilter = tab
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 12, weight: .semibold))
                        Text(tab.rawValue)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                    }
                    .foregroundStyle(selectedFilter == tab ? Color.kineticsDark : Color.kineticsSubtext)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background {
                        if selectedFilter == tab {
                            Capsule()
                                .fill(.white)
                                .matchedGeometryEffect(id: "pill", in: ns)
                        } else {
                            Capsule()
                                .fill(Color.kineticsDark)
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .animation(.easeInOut(duration: 0.15), value: selectedFilter)
            }
        }
        .padding(4)
        .background(Color(white: 0.1).clipShape(Capsule()))
    }
}

// MARK: - NewPostsBanner

private struct NewPostsBanner: View {

    let count: Int
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 12, weight: .bold))
                Text(count == 1 ? "1 new post" : "\(count) new posts")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(.black)
            .padding(.horizontal, 18)
            .padding(.vertical, 9)
            .background(Color.kineticsBlue)
            .clipShape(Capsule())
            .shadow(color: Color.kineticsBlue.opacity(0.45), radius: 12, x: 0, y: 4)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - StoriesBar

private struct StoriesBar: View {

    let stories: [StoryModel]
    let currentDisplayName: String
    let onStoryTap: (StoryModel) -> Void
    let onYourStoryTap: () -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                YourStoryBubble(displayName: currentDisplayName, onTap: onYourStoryTap)
                ForEach(stories) { story in
                    StoryBubble(story: story, onTap: { onStoryTap(story) })
                }
            }
            .padding(.horizontal, 16)
        }
    }
}

// MARK: - YourStoryBubble

private struct YourStoryBubble: View {

    let displayName: String
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 6) {
                ZStack {
                    Circle().fill(Color.kineticsDark).frame(width: 56, height: 56)
                    Text(String(displayName.prefix(1)).uppercased())
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    ZStack {
                        Circle().fill(Color.kineticsBlue).frame(width: 18, height: 18)
                        Image(systemName: "plus")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.black)
                    }
                    .offset(x: 18, y: 18)
                }
                Text("Your Story")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.kineticsSubtext)
                    .lineLimit(1)
                    .frame(width: 62)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - StoryBubble

private struct StoryBubble: View {

    let story: StoryModel
    let onTap: () -> Void

    /// Ring color based on sport type — seen stories go gray.
    private var ringGradient: LinearGradient {
        if story.seen {
            return LinearGradient(
                colors: [Color.kineticsSubtext.opacity(0.4), Color.kineticsSubtext.opacity(0.2)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        }
        let (a, b) = sportRingColors(story.sport)
        return LinearGradient(colors: [a, b], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .stroke(ringGradient, lineWidth: 2.5)
                        .frame(width: 60, height: 60)
                    Circle()
                        .fill(Color.kineticsDark)
                        .frame(width: 54, height: 54)
                    Text(story.avatarEmoji).font(.system(size: 24))
                }
                Text(String(story.displayName.prefix(8)))
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(story.seen ? Color.kineticsSubtext : .white)
                    .lineLimit(1)
                    .frame(width: 62)
            }
        }
        .buttonStyle(.plain)
    }

    private func sportRingColors(_ sport: String) -> (Color, Color) {
        switch sport {
        case "iron", "ironTracker", "gym": return (.kineticsBlue, Color(red: 0.0, green: 0.45, blue: 0.85))
        case "run":        return (.kineticsGreen, Color(red: 0.0, green: 0.7, blue: 0.4))
        case "striking":   return (.kineticsRed, .kineticsOrange)
        case "grappling":  return (.kineticsPurple, Color(red: 0.8, green: 0.3, blue: 0.9))
        case "wall":       return (.kineticsGreen, .kineticsBlue)
        default:           return (.kineticsBlue, .kineticsPurple)
        }
    }
}

// MARK: - ErrorBannerView

struct ErrorBannerView: View {

    let message: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.kineticsAmber)
            Text(message)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(2)
            Spacer(minLength: 0)
            Button { onDismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(red: 0.14, green: 0.10, blue: 0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.kineticsAmber.opacity(0.35), lineWidth: 1)
                )
        )
    }
}

// MARK: - ComposePostSheet

struct ComposePostSheet: View {

    let currentUserId: String
    let currentDisplayName: String
    let onPost: (FeedItem) -> Void

    @State private var caption = ""
    @State private var isPosting = false
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss

    private var canPost: Bool {
        !caption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isPosting
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.kineticsBackground.ignoresSafeArea()
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .top, spacing: 12) {
                        ZStack {
                            LinearGradient(
                                colors: [Color.kineticsPurple, Color.kineticsBlue],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            )
                            Text(String(currentDisplayName.prefix(1)).uppercased())
                                .font(.system(size: 16, weight: .black, design: .rounded))
                                .foregroundStyle(.white)
                        }
                        .frame(width: 44, height: 44)
                        .clipShape(Circle())
                        VStack(alignment: .leading, spacing: 6) {
                            Text(currentDisplayName)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.white)
                            TextField("What did you train today?", text: $caption, axis: .vertical)
                                .font(.system(size: 16))
                                .foregroundStyle(.white)
                                .tint(Color.kineticsBlue)
                                .lineLimit(6, reservesSpace: false)
                        }
                    }
                    .padding(20)
                    Divider().background(.white.opacity(0.07))
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(activitySuggestions, id: \.0) { label, icon in
                                Button { if caption.isEmpty { caption = label + " " } } label: {
                                    Label(label, systemImage: icon)
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(.white.opacity(0.7))
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 7)
                                        .background(.white.opacity(0.07))
                                        .clipShape(Capsule())
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                    }
                    if let error = errorMessage {
                        Text(error)
                            .font(.system(size: 13))
                            .foregroundStyle(Color.kineticsRed)
                            .padding(.horizontal, 20)
                    }
                    Spacer()
                }
            }
            .navigationTitle("New Post")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.kineticsBackground, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.kineticsSubtext)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { Task { await post() } } label: {
                        if isPosting {
                            ProgressView().tint(.white).scaleEffect(0.8)
                        } else {
                            Text("Post")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(canPost ? Color.kineticsDark : Color.kineticsSubtext)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 7)
                                .background(canPost ? Color.kineticsBlue : Color.kineticsDark)
                                .clipShape(Capsule())
                        }
                    }
                    .disabled(!canPost)
                }
            }
        }
    }

    private let activitySuggestions: [(String, String)] = [
        ("Morning Run", "figure.run"), ("Striking Session", "figure.boxing"),
        ("Grappling Lab", "figure.martial.arts"), ("Iron Tracker", "dumbbell.fill"),
        ("Wall Beta", "figure.climbing"), ("Gym Session", "flame.fill")
    ]

    private func post() async {
        let trimmed = caption.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isPosting = true
        errorMessage = nil
        let item = FeedItem(
            id: UUID().uuidString, userId: currentUserId, displayName: currentDisplayName,
            username: "", avatarURL: "", itemType: .workout, title: trimmed, subtitle: "",
            metrics: [], imageURL: "", postedAt: Date(), kudosCount: 0, commentCount: 0,
            isLikedByCurrentUser: false, workoutId: "", activityType: "general"
        )
        do { try await SocialRepository.shared.postActivity(item); onPost(item) }
        catch { errorMessage = "Couldn't post. Check your connection and try again." }
        isPosting = false
    }
}

// MARK: - CommentSheet

struct CommentSheet: View {

    let item: FeedItem
    let currentUserId: String
    let currentDisplayName: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.kineticsBackground.ignoresSafeArea()
                VStack(spacing: 0) {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(activityColor(item.activityType).opacity(0.15))
                                .frame(width: 40, height: 40)
                            Image(systemName: activityIcon(item.activityType))
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(activityColor(item.activityType))
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
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(Color.kineticsDark)
                    Divider().background(.white.opacity(0.07))
                    ScrollView {
                        CommentSectionView(
                            activityId: item.id,
                            currentUserId: currentUserId,
                            currentDisplayName: currentDisplayName
                        )
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                    }
                }
            }
            .navigationTitle("Comments")
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
        }
    }

    private func activityIcon(_ type: String) -> String {
        switch type {
        case "run":                       return "figure.run"
        case "striking":                  return "figure.boxing"
        case "grappling":                 return "figure.martial.arts"
        case "ironTracker", "gym":        return "dumbbell.fill"
        case "wall":                      return "figure.climbing"
        default:                          return "bolt.fill"
        }
    }

    private func activityColor(_ type: String) -> Color {
        switch type {
        case "run":                       return .kineticsBlue
        case "walk":                      return .kineticsGreen
        case "striking":                  return .kineticsRed
        case "grappling":                 return .kineticsOrange
        case "ironTracker", "gym":        return .kineticsBlue
        case "wall":                      return .kineticsGreen
        default:                          return .kineticsPurple
        }
    }
}
