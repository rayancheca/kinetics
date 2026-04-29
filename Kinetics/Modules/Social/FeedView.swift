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
            errorMessage = error.localizedDescription
        }
    }

    // MARK: Refresh

    /// Pull-to-refresh path. Uses a separate flag so the list stays visible.
    func refresh(currentUserId: String) async {
        isRefreshing = true
        errorMessage = nil
        defer { isRefreshing = false }

        do {
            feedItems = try await SocialRepository.shared.fetchFeed()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: Kudos

    /// Toggles the kudos (like) state for a given item both remotely and locally.
    /// The local update is applied optimistically; a failure surfaces an error message
    /// but does not roll back (server state re-syncs on next refresh).
    func toggleKudos(for item: FeedItem, currentUserId: String) async {
        do {
            try await SocialRepository.shared.toggleKudos(
                activityId: item.id,
                fromUserId: currentUserId
            )
        } catch {
            errorMessage = error.localizedDescription
            return
        }

        // Optimistic local update — find by id and flip the like state.
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
    }

    // MARK: Delete

    /// Deletes an activity both from the remote store and from the local list.
    func delete(item: FeedItem, userId: String) async {
        do {
            try await SocialRepository.shared.deleteActivity(activityId: item.id, userId: userId)
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        feedItems.removeAll { $0.id == item.id }
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

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ZStack {
                Color.kineticsBackground.ignoresSafeArea()

                content
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
            newPostPlaceholder
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
                            // Comment sheet — wired in a future session
                        }
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
        VStack(spacing: 16) {
            ProgressView()
                .tint(Color.kineticsBlue)
                .scaleEffect(1.2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Empty State

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "figure.2.arms.open")
                .font(.system(size: 52, weight: .light))
                .foregroundStyle(Color.kineticsSubtext)

            Text("No activity yet")
                .font(.system(.title3, design: .rounded, weight: .semibold))
                .foregroundStyle(.white)

            Text("Follow athletes to see their sessions here.")
                .font(.subheadline)
                .foregroundStyle(Color.kineticsSubtext)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: New Post Sheet

    private var newPostPlaceholder: some View {
        Text("New Post — coming soon")
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.kineticsBackground)
    }
}

// MARK: - ActivityFeedCard

struct ActivityFeedCard: View {

    let item: FeedItem
    let currentUserId: String
    let onKudos: () async -> Void
    let onComment: () -> Void

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

                    Text("\(item.kudosCount)")
                        .font(.system(.footnote, design: .rounded, weight: .semibold))
                        .foregroundStyle(item.isLikedByCurrentUser ? Color.kineticsBlue : Color.kineticsSubtext)
                        .contentTransition(.numericText())
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

                    Text("\(item.commentCount)")
                        .font(.system(.footnote, design: .rounded, weight: .semibold))
                        .foregroundStyle(Color.kineticsSubtext)
                }
            }
            .buttonStyle(.plain)

            Spacer()
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

            Text(metric.value)
                .font(.system(.subheadline, design: .rounded, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
    }
}
