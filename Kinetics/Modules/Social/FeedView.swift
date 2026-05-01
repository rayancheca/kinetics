import SwiftUI

// MARK: - FeedViewModel

@Observable
@MainActor
final class FeedViewModel {

    // MARK: State

    var feedItems: [FeedItem] = []
    var isLoading = false
    var isRefreshing = false
    var errorMessage: String?
    var showNewPostSheet = false
    var showErrorBanner = false

    // MARK: Selected item for comment sheet

    var commentItem: FeedItem?
    var showCommentSheet = false

    // MARK: Load

    /// Initial load. Shows the full-screen skeleton while the first fetch is in flight.
    func load(currentUserId: String) async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            feedItems = try await SocialRepository.shared.fetchFeed()
        } catch {
            errorMessage = "Couldn't load the feed. Pull to retry."
            showErrorBanner = true
        }
    }

    // MARK: Refresh

    /// Pull-to-refresh path. Uses a separate flag so the list stays visible.
    func refresh(currentUserId: String) async {
        isRefreshing = true
        errorMessage = nil
        showErrorBanner = false
        defer { isRefreshing = false }

        do {
            feedItems = try await SocialRepository.shared.fetchFeed()
        } catch {
            errorMessage = "Couldn't refresh. Check your connection."
            showErrorBanner = true
        }
    }

    // MARK: Kudos

    /// Toggles the kudos (like) state for a given item both remotely and locally.
    /// The local update is applied optimistically; a failure surfaces an error banner
    /// but does not roll back (server state re-syncs on next refresh).
    func toggleKudos(for item: FeedItem, currentUserId: String) async {
        // Optimistic local update first for instant feedback.
        guard let index = feedItems.firstIndex(where: { $0.id == item.id }) else { return }
        let current = feedItems[index]
        let wasLiked = current.isLikedByCurrentUser
        feedItems[index] = FeedItem(
            id: current.id,
            userId: current.userId,
            displayName: current.displayName,
            username: current.username,
            avatarURL: current.avatarURL,
            itemType: current.itemType,
            title: current.title,
            subtitle: current.subtitle,
            metrics: current.metrics,
            imageURL: current.imageURL,
            postedAt: current.postedAt,
            kudosCount: current.kudosCount + (wasLiked ? -1 : 1),
            commentCount: current.commentCount,
            isLikedByCurrentUser: !wasLiked,
            workoutId: current.workoutId,
            activityType: current.activityType
        )

        do {
            try await SocialRepository.shared.toggleKudos(
                activityId: item.id,
                fromUserId: currentUserId
            )
        } catch {
            // Roll back on failure.
            feedItems[index] = current
            errorMessage = "Couldn't update kudos. Try again."
            showErrorBanner = true
        }
    }

    // MARK: Delete

    /// Deletes an activity both from the remote store and from the local list.
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

    // MARK: Comments

    func openComments(for item: FeedItem) {
        commentItem = item
        showCommentSheet = true
    }
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
        return user?.email?
            .components(separatedBy: "@").first?
            .capitalized ?? "Athlete"
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ZStack(alignment: .top) {
                Color.kineticsBackground.ignoresSafeArea()

                content

                // Error banner overlay
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
                    Button {
                        viewModel.showNewPostSheet = true
                    } label: {
                        Image(systemName: "pencil.circle.fill")
                            .font(.title3)
                            .foregroundStyle(Color.kineticsBlue)
                    }
                }
            }
            .task {
                await viewModel.load(currentUserId: currentUserId)
            }
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
                CommentSheet(
                    item: item,
                    currentUserId: currentUserId,
                    currentDisplayName: currentDisplayName
                )
            }
        }
    }

    // MARK: Content Switch

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

    // MARK: Feed List

    private var feedList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(viewModel.feedItems) { item in
                    ActivityFeedCard(
                        item: item,
                        currentUserId: currentUserId,
                        onKudos: {
                            await viewModel.toggleKudos(for: item, currentUserId: currentUserId)
                        },
                        onComment: {
                            viewModel.openComments(for: item)
                        },
                        onDelete: item.userId == currentUserId ? {
                            await viewModel.delete(item: item, userId: currentUserId)
                        } : nil
                    )
                    .padding(.horizontal, 16)
                }
            }
            .padding(.vertical, 12)
        }
        .refreshable {
            await viewModel.refresh(currentUserId: currentUserId)
        }
    }

    // MARK: Loading State

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

    // MARK: Empty State

    private var emptyStateView: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.kineticsPurple.opacity(0.18), Color.kineticsBlue.opacity(0.12)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 88, height: 88)
                Image(systemName: "person.2.fill")
                    .font(.system(size: 34, weight: .medium))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.kineticsPurple, Color.kineticsBlue],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }

            VStack(spacing: 6) {
                Text("Your feed is empty")
                    .font(.system(size: 20))
                    .fontWeight(.bold)
                    .fontDesign(.rounded)
                    .foregroundStyle(.white)

                Text("Be the first to share a session\nand inspire your training crew.")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.kineticsSubtext)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }

            Button {
                viewModel.showNewPostSheet = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 15, weight: .semibold))
                    Text("Share a Session")
                        .font(.system(size: 15, weight: .semibold))
                }
                .foregroundStyle(Color.kineticsDark)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(Color.kineticsBlue)
                .clipShape(Capsule())
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 40)
    }
}

// MARK: - ActivityFeedCard

struct ActivityFeedCard: View {

    let item: FeedItem
    let currentUserId: String
    let onKudos: () async -> Void
    let onComment: () -> Void
    /// Non-nil only when the current user owns this post — shows a delete option.
    var onDelete: (() async -> Void)? = nil

    @State private var showDeleteConfirm = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            headerRow
            titleBlock
            metricsRow
            Divider()
                .background(Color.white.opacity(0.07))
            actionRow
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color.kineticsDark, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
        )
        .contextMenu {
            if onDelete != nil {
                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    Label("Delete Post", systemImage: "trash")
                }
            }
        }
        .confirmationDialog("Delete this post?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                Task { await onDelete?() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This can't be undone.")
        }
    }

    // MARK: Header Row

    private var headerRow: some View {
        HStack(spacing: 10) {
            avatarView

            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayName)
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Text("@\(item.username)")
                    .font(.caption)
                    .foregroundStyle(Color.kineticsSubtext)
                    .lineLimit(1)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Image(systemName: activityIcon(item.activityType))
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(activityColor(item.activityType))

                Text(timeAgo(item.postedAt))
                    .font(.caption2)
                    .foregroundStyle(Color.kineticsSubtext)
            }
        }
    }

    // MARK: Avatar

    private var avatarView: some View {
        ZStack {
            if !item.avatarURL.isEmpty, let url = URL(string: item.avatarURL) {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    purpleGradientAvatar
                }
                .frame(width: 40, height: 40)
                .clipShape(Circle())
            } else {
                purpleGradientAvatar
            }
        }
    }

    private var purpleGradientAvatar: some View {
        Circle()
            .fill(
                LinearGradient(
                    colors: [Color.kineticsPurple, Color.kineticsBlue.opacity(0.7)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: 40, height: 40)
            .overlay(
                Text(item.displayName.prefix(1).uppercased())
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                    .foregroundStyle(.white)
            )
    }

    // MARK: Title Block

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.title)
                .font(.system(.callout, design: .rounded, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(2)

            if !item.subtitle.isEmpty {
                Text(item.subtitle)
                    .font(.caption)
                    .foregroundStyle(Color.kineticsSubtext)
                    .lineLimit(1)
            }
        }
    }

    // MARK: Metrics Row

    @ViewBuilder
    private var metricsRow: some View {
        let displayMetrics = Array(item.metrics.prefix(3))
        if !displayMetrics.isEmpty {
            HStack(spacing: 0) {
                ForEach(displayMetrics.indices, id: \.self) { index in
                    FeedMetricCell(metric: displayMetrics[index])

                    if index < displayMetrics.count - 1 {
                        Divider()
                            .frame(height: 28)
                            .background(Color.white.opacity(0.1))
                    }
                }
            }
            .padding(.vertical, 10)
            .background(Color.kineticsBackground.opacity(0.6), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    // MARK: Action Row

    private var actionRow: some View {
        HStack(spacing: 20) {
            // Kudos button
            Button {
                Task { await onKudos() }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: item.isLikedByCurrentUser ? "heart.fill" : "heart")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(item.isLikedByCurrentUser ? Color.kineticsBlue : Color.kineticsSubtext)
                        .symbolEffect(.bounce, value: item.isLikedByCurrentUser)

                    if item.kudosCount > 0 {
                        Text("\(item.kudosCount)")
                            .font(.system(.footnote, design: .rounded, weight: .semibold))
                            .foregroundStyle(item.isLikedByCurrentUser ? Color.kineticsBlue : Color.kineticsSubtext)
                            .contentTransition(.numericText())
                    }
                }
            }
            .buttonStyle(.plain)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: item.isLikedByCurrentUser)

            // Comment button
            Button {
                onComment()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "bubble.left")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Color.kineticsSubtext)

                    if item.commentCount > 0 {
                        Text("\(item.commentCount)")
                            .font(.system(.footnote, design: .rounded, weight: .semibold))
                            .foregroundStyle(Color.kineticsSubtext)
                    }
                }
            }
            .buttonStyle(.plain)

            Spacer()

            // Share button
            Button {
                // Share sheet — future: generate a share card
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.kineticsSubtext)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Helpers

    private func activityColor(_ type: String) -> Color {
        switch type {
        case "run":                     return .kineticsBlue
        case "walk":                    return .kineticsGreen
        case "ride":                    return .kineticsOrange
        case "striking":               return .kineticsRed
        case "grappling":              return .kineticsOrange
        case "ironTracker", "gym":     return .kineticsBlue
        case "wall":                   return .kineticsGreen
        default:                        return .kineticsPurple
        }
    }

    private func activityIcon(_ type: String) -> String {
        switch type {
        case "run":                     return "figure.run"
        case "walk":                    return "figure.walk"
        case "ride":                    return "bicycle"
        case "striking":               return "figure.boxing"
        case "grappling":              return "figure.martial.arts"
        case "ironTracker", "gym":     return "dumbbell.fill"
        case "wall":                   return "figure.climbing"
        default:                        return "bolt.fill"
        }
    }

    /// Returns a compact relative-time string: "2m", "1h", "3d", "2w".
    private func timeAgo(_ date: Date) -> String {
        let seconds = Int(Date.now.timeIntervalSince(date))
        switch seconds {
        case ..<60:
            return "now"
        case 60 ..< 3_600:
            return "\(seconds / 60)m"
        case 3_600 ..< 86_400:
            return "\(seconds / 3_600)h"
        case 86_400 ..< 604_800:
            return "\(seconds / 86_400)d"
        default:
            return "\(seconds / 604_800)w"
        }
    }
}

// MARK: - FeedMetricCell

private struct FeedMetricCell: View {

    let metric: FeedMetric

    var body: some View {
        VStack(spacing: 3) {
            Text(metric.label.uppercased())
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.kineticsSubtext)
                .tracking(0.6)
                .lineLimit(1)

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(metric.value)
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                if !metric.unit.isEmpty {
                    Text(metric.unit)
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.kineticsSubtext)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
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

/// Sheet for posting a short-form activity update. Users write a caption; a
/// text-only FeedItem is created and posted to Firestore immediately.
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
                    // Compose area
                    HStack(alignment: .top, spacing: 12) {
                        // Author avatar
                        ZStack {
                            LinearGradient(
                                colors: [Color.kineticsPurple, Color.kineticsBlue],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
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

                            TextField(
                                "What did you train today?",
                                text: $caption,
                                axis: .vertical
                            )
                            .font(.system(size: 16))
                            .foregroundStyle(.white)
                            .tint(Color.kineticsBlue)
                            .lineLimit(6, reservesSpace: false)
                        }
                    }
                    .padding(20)

                    Divider().background(.white.opacity(0.07))

                    // Activity type hint
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(activitySuggestions, id: \.0) { label, icon in
                                Button {
                                    if caption.isEmpty {
                                        caption = label + " "
                                    }
                                } label: {
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
                    Button {
                        Task { await post() }
                    } label: {
                        if isPosting {
                            ProgressView()
                                .tint(.white)
                                .scaleEffect(0.8)
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

    // MARK: Private

    private let activitySuggestions: [(String, String)] = [
        ("Morning Run", "figure.run"),
        ("Striking Session", "figure.boxing"),
        ("Grappling Lab", "figure.martial.arts"),
        ("Iron Tracker", "dumbbell.fill"),
        ("Wall Beta", "figure.climbing"),
        ("Gym Session", "flame.fill")
    ]

    private func post() async {
        let trimmed = caption.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        isPosting = true
        errorMessage = nil

        let item = FeedItem(
            id: UUID().uuidString,
            userId: currentUserId,
            displayName: currentDisplayName,
            username: "",
            avatarURL: "",
            itemType: .workout,
            title: trimmed,
            subtitle: "",
            metrics: [],
            imageURL: "",
            postedAt: Date(),
            kudosCount: 0,
            commentCount: 0,
            isLikedByCurrentUser: false,
            workoutId: "",
            activityType: "general"
        )

        do {
            try await SocialRepository.shared.postActivity(item)
            onPost(item)
        } catch {
            errorMessage = "Couldn't post. Check your connection and try again."
        }

        isPosting = false
    }
}

// MARK: - CommentSheet

/// Modal sheet that loads and displays comments for a single feed item.
struct CommentSheet: View {

    let item: FeedItem
    let currentUserId: String
    let currentDisplayName: String

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.kineticsBackground.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // Activity summary header
                        HStack(spacing: 10) {
                            Image(systemName: activityIcon(item.activityType))
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(activityColor(item.activityType))
                                .frame(width: 32, height: 32)
                                .background(activityColor(item.activityType).opacity(0.12))
                                .clipShape(Circle())

                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                                Text("by \(item.displayName)")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Color.kineticsSubtext)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 16)

                        Divider().background(.white.opacity(0.07)).padding(.horizontal, 16)

                        // Comment section
                        CommentSectionView(
                            activityId: item.id,
                            currentUserId: currentUserId,
                            currentDisplayName: currentDisplayName
                        )
                        .padding(.horizontal, 16)
                        .padding(.bottom, 20)
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
        case "run":                   return "figure.run"
        case "walk":                  return "figure.walk"
        case "ride":                  return "bicycle"
        case "striking":              return "figure.boxing"
        case "grappling":             return "figure.martial.arts"
        case "ironTracker", "gym":    return "dumbbell.fill"
        case "wall":                  return "figure.climbing"
        default:                      return "bolt.fill"
        }
    }

    private func activityColor(_ type: String) -> Color {
        switch type {
        case "run":                   return .kineticsBlue
        case "walk":                  return .kineticsGreen
        case "ride":                  return .kineticsOrange
        case "striking":              return .kineticsRed
        case "grappling":             return .kineticsOrange
        case "ironTracker", "gym":    return .kineticsBlue
        case "wall":                  return .kineticsGreen
        default:                      return .kineticsPurple
        }
    }
}
