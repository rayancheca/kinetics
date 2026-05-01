import SwiftUI

// MARK: - FeedViewModel

@Observable
@MainActor
final class FeedViewModel {

    var feedItems: [FeedItem] = []
    var isLoading = false
    var isRefreshing = false
    var errorMessage: String?
    var showNewPostSheet = false
    var showErrorBanner = false
    var selectedTab: FeedTab = .forYou
    var stories: [StoryModel] = []
    var selectedStory: StoryModel?
    var showStorySheet = false
    var commentItem: FeedItem?
    var showCommentSheet = false
    var kudosFloatingItems: [String: Bool] = [:]

    func load(currentUserId: String) async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            async let feedFetch = SocialRepository.shared.fetchFeed()
            async let storiesFetch = SocialRepository.shared.fetchStories(for: currentUserId)
            let (fetchedFeed, fetchedStories) = try await (feedFetch, storiesFetch)
            feedItems = fetchedFeed
            stories = fetchedStories
        } catch {
            errorMessage = "Couldn't load the feed. Pull to retry."
            showErrorBanner = true
        }
    }

    func refresh(currentUserId: String) async {
        isRefreshing = true
        errorMessage = nil
        showErrorBanner = false
        defer { isRefreshing = false }
        do {
            async let feedFetch = SocialRepository.shared.fetchFeed()
            async let storiesFetch = SocialRepository.shared.fetchStories(for: currentUserId)
            let (fetchedFeed, fetchedStories) = try await (feedFetch, storiesFetch)
            feedItems = fetchedFeed
            stories = fetchedStories
        } catch {
            errorMessage = "Couldn't refresh. Check your connection."
            showErrorBanner = true
        }
    }

    func toggleKudos(for item: FeedItem, currentUserId: String) async {
        guard let index = feedItems.firstIndex(where: { $0.id == item.id }) else { return }
        let current = feedItems[index]
        let wasLiked = current.isLikedByCurrentUser
        feedItems[index] = FeedItem(
            id: current.id, userId: current.userId,
            displayName: current.displayName, username: current.username,
            avatarURL: current.avatarURL, itemType: current.itemType,
            title: current.title, subtitle: current.subtitle,
            metrics: current.metrics, imageURL: current.imageURL,
            postedAt: current.postedAt,
            kudosCount: current.kudosCount + (wasLiked ? -1 : 1),
            commentCount: current.commentCount,
            isLikedByCurrentUser: !wasLiked,
            workoutId: current.workoutId, activityType: current.activityType
        )
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
            errorMessage = "Couldn't update kudos. Try again."
            showErrorBanner = true
        }
    }

    func delete(item: FeedItem, userId: String) async {
        do {
            try await SocialRepository.shared.deleteActivity(activityId: item.id, userId: userId)
        } catch {
            errorMessage = "Couldn't delete post. Try again."
            showErrorBanner = true
            return
        }
        feedItems.removeAll { $0.id == item.id }
    }

    func openComments(for item: FeedItem) {
        commentItem = item
        showCommentSheet = true
    }

    func openStory(_ story: StoryModel) {
        selectedStory = story
        showStorySheet = true
    }
}

// MARK: - FeedTab

enum FeedTab: String, CaseIterable {
    case forYou = "For You"
    case following = "Following"
}

// MARK: - FeedView

@MainActor
struct FeedView: View {

    @Environment(AppState.self) private var appState
    @State private var viewModel = FeedViewModel()
    @State private var navigationPath = NavigationPath()

    private var currentUserId: String {
        appState.authManager.currentUser?.uid ?? ""
    }

    private var currentDisplayName: String {
        let user = appState.authManager.currentUser
        if user?.isAnonymous == true { return "Athlete" }
        return user?.email?.components(separatedBy: "@").first?.capitalized ?? "Athlete"
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
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
                ToolbarItem(placement: .topBarTrailing) {
                    Button { viewModel.showNewPostSheet = true } label: {
                        Image(systemName: "pencil.circle.fill")
                            .font(.title3)
                            .foregroundStyle(Color.kineticsBlue)
                    }
                }
            }
            .task { await viewModel.load(currentUserId: currentUserId) }
        }
        .sheet(isPresented: $viewModel.showNewPostSheet) {
            ComposePostSheet(
                currentUserId: currentUserId,
                currentDisplayName: currentDisplayName
            ) { newItem in
                viewModel.feedItems.insert(newItem, at: 0)
                viewModel.showNewPostSheet = false
            }
        }
        .sheet(isPresented: $viewModel.showCommentSheet) {
            if let item = viewModel.commentItem {
                CommentSheet(item: item, currentUserId: currentUserId, currentDisplayName: currentDisplayName)
            }
        }
        .sheet(isPresented: $viewModel.showStorySheet) {
            if let story = viewModel.selectedStory {
                StoryFullScreenView(story: story)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading && viewModel.feedItems.isEmpty {
            loadingState
        } else if viewModel.feedItems.isEmpty && !viewModel.isLoading {
            emptyStateView
        } else {
            feedList
        }
    }

    private var feedList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                FeedTabBar(selectedTab: $viewModel.selectedTab)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 4)
                StoriesBar(
                    stories: viewModel.stories,
                    currentDisplayName: currentDisplayName,
                    onStoryTap: { viewModel.openStory($0) },
                    onYourStoryTap: { viewModel.showNewPostSheet = true }
                )
                .padding(.vertical, 12)
                LazyVStack(spacing: 12) {
                    ForEach(viewModel.feedItems) { item in
                        ActivityFeedCard(
                            item: item,
                            currentUserId: currentUserId,
                            showFloatingKudos: viewModel.kudosFloatingItems[item.id] == true,
                            onKudos: { await viewModel.toggleKudos(for: item, currentUserId: currentUserId) },
                            onComment: { viewModel.openComments(for: item) },
                            onDelete: item.userId == currentUserId ? {
                                await viewModel.delete(item: item, userId: currentUserId)
                            } : nil
                        )
                        .padding(.horizontal, 16)
                    }
                }
                .padding(.bottom, 24)
            }
        }
        .refreshable { await viewModel.refresh(currentUserId: currentUserId) }
    }

    private var loadingState: some View {
        VStack(spacing: 20) {
            ProgressView().tint(Color.kineticsBlue).scaleEffect(1.4)
            Text("Loading feed...")
                .font(.system(size: 14, design: .rounded))
                .foregroundStyle(Color.kineticsSubtext)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 40)
    }
}

// MARK: - FeedTabBar

private struct FeedTabBar: View {

    @Binding var selectedTab: FeedTab
    @Namespace private var tabNamespace

    var body: some View {
        HStack(spacing: 0) {
            ForEach(FeedTab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) { selectedTab = tab }
                } label: {
                    VStack(spacing: 6) {
                        Text(tab.rawValue)
                            .font(.system(size: 15, weight: selectedTab == tab ? .bold : .regular, design: .rounded))
                            .foregroundStyle(selectedTab == tab ? .white : Color.kineticsSubtext)
                            .animation(.easeInOut(duration: 0.2), value: selectedTab)
                        ZStack {
                            Capsule().fill(Color.clear).frame(height: 3)
                            if selectedTab == tab {
                                Capsule().fill(Color.kineticsBlue).frame(height: 3)
                                    .matchedGeometryEffect(id: "tab_indicator", in: tabNamespace)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
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
                        Image(systemName: "plus").font(.system(size: 10, weight: .bold)).foregroundStyle(.black)
                    }
                    .offset(x: 18, y: 18)
                }
                Text("Your Story")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.kineticsSubtext)
                    .lineLimit(1).frame(width: 62)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - StoryBubble

private struct StoryBubble: View {

    let story: StoryModel
    let onTap: () -> Void

    private var ringColors: [Color] {
        story.seen
            ? [Color.kineticsSubtext.opacity(0.4), Color.kineticsSubtext.opacity(0.2)]
            : [Color.kineticsBlue, Color(red: 0.6, green: 0.2, blue: 0.9)]
    }

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .stroke(LinearGradient(colors: ringColors, startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 2.5)
                        .frame(width: 60, height: 60)
                    Circle().fill(Color.kineticsDark).frame(width: 54, height: 54)
                    Text(story.avatarEmoji).font(.system(size: 24))
                }
                Text(String(story.displayName.prefix(8)))
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(story.seen ? Color.kineticsSubtext : .white)
                    .lineLimit(1).frame(width: 62)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - ErrorBannerView

struct ErrorBannerView: View {

    let message: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 14, weight: .semibold)).foregroundStyle(Color.kineticsAmber)
            Text(message).font(.system(size: 13, weight: .medium)).foregroundStyle(.white).lineLimit(2)
            Spacer(minLength: 0)
            Button { onDismiss() } label: {
                Image(systemName: "xmark").font(.system(size: 11, weight: .bold)).foregroundStyle(.white.opacity(0.5))
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(red: 0.14, green: 0.10, blue: 0.04))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.kineticsAmber.opacity(0.35), lineWidth: 1))
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
                            LinearGradient(colors: [Color.kineticsPurple, Color.kineticsBlue], startPoint: .topLeading, endPoint: .bottomTrailing)
                            Text(String(currentDisplayName.prefix(1)).uppercased())
                                .font(.system(size: 16, weight: .black, design: .rounded)).foregroundStyle(.white)
                        }
                        .frame(width: 44, height: 44).clipShape(Circle())
                        VStack(alignment: .leading, spacing: 6) {
                            Text(currentDisplayName).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                            TextField("What did you train today?", text: $caption, axis: .vertical)
                                .font(.system(size: 16)).foregroundStyle(.white).tint(Color.kineticsBlue).lineLimit(6, reservesSpace: false)
                        }
                    }
                    .padding(20)
                    Divider().background(.white.opacity(0.07))
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(activitySuggestions, id: \.0) { label, icon in
                                Button { if caption.isEmpty { caption = label + " " } } label: {
                                    Label(label, systemImage: icon)
                                        .font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.7))
                                        .padding(.horizontal, 12).padding(.vertical, 7)
                                        .background(.white.opacity(0.07)).clipShape(Capsule())
                                }
                            }
                        }
                        .padding(.horizontal, 20).padding(.vertical, 12)
                    }
                    if let error = errorMessage {
                        Text(error).font(.system(size: 13)).foregroundStyle(Color.kineticsRed).padding(.horizontal, 20)
                    }
                    Spacer()
                }
            }
            .navigationTitle("New Post").navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.kineticsBackground, for: .navigationBar).toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }.foregroundStyle(Color.kineticsSubtext)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { Task { await post() } } label: {
                        if isPosting {
                            ProgressView().tint(.white).scaleEffect(0.8)
                        } else {
                            Text("Post").font(.system(size: 15, weight: .bold))
                                .foregroundStyle(canPost ? Color.kineticsDark : Color.kineticsSubtext)
                                .padding(.horizontal, 16).padding(.vertical, 7)
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
                            Circle().fill(activityColor(item.activityType).opacity(0.15)).frame(width: 40, height: 40)
                            Image(systemName: activityIcon(item.activityType))
                                .font(.system(size: 16, weight: .semibold)).foregroundStyle(activityColor(item.activityType))
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.title).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                            Text("by \(item.displayName)").font(.system(size: 12)).foregroundStyle(Color.kineticsSubtext)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 16).padding(.vertical, 14).background(Color.kineticsDark)
                    Divider().background(.white.opacity(0.07))
                    ScrollView {
                        CommentSectionView(activityId: item.id, currentUserId: currentUserId, currentDisplayName: currentDisplayName)
                            .padding(.horizontal, 16).padding(.vertical, 8)
                    }
                }
            }
            .navigationTitle("Comments").navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.kineticsBackground, for: .navigationBar).toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }.foregroundStyle(Color.kineticsBlue).font(.system(size: 15, weight: .semibold))
                }
            }
        }
    }

    private func activityIcon(_ type: String) -> String {
        switch type {
        case "run": return "figure.run"
        case "striking": return "figure.boxing"
        case "grappling": return "figure.martial.arts"
        case "ironTracker", "gym": return "dumbbell.fill"
        case "wall": return "figure.climbing"
        default: return "bolt.fill"
        }
    }

    private func activityColor(_ type: String) -> Color {
        switch type {
        case "run": return .kineticsBlue
        case "walk": return .kineticsGreen
        case "striking": return .kineticsRed
        case "grappling": return .kineticsOrange
        case "ironTracker", "gym": return .kineticsBlue
        case "wall": return .kineticsGreen
        default: return .kineticsPurple
        }
    }
}
