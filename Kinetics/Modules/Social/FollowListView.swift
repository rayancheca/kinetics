import SwiftUI

// MARK: - FollowListMode

enum FollowListMode: Sendable {
    case followers
    case following

    var title: String {
        switch self {
        case .followers: return "Followers"
        case .following: return "Following"
        }
    }
}

// MARK: - FollowListViewModel

@Observable
@MainActor
final class FollowListViewModel {

    var relationships: [FollowRelationship] = []
    var filteredRelationships: [FollowRelationship] = []
    var searchText = "" {
        didSet { applyFilter() }
    }
    var isLoading = false
    var errorMessage: String?

    // MARK: - Load

    func load(mode: FollowListMode, userId: String) async {
        isLoading = true
        errorMessage = nil
        do {
            switch mode {
            case .followers:
                relationships = try await SocialRepository.shared.fetchFollowers(userId: userId)
            case .following:
                relationships = try await SocialRepository.shared.fetchFollowing(userId: userId)
            }
            applyFilter()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    // MARK: - Filter

    private func applyFilter() {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if query.isEmpty {
            filteredRelationships = relationships
        } else {
            filteredRelationships = relationships.filter {
                $0.displayName.lowercased().contains(query) ||
                $0.username.lowercased().contains(query)
            }
        }
    }

    // MARK: - Unfollow

    func unfollow(currentUserId: String, targetUserId: String) async {
        do {
            try await SocialRepository.shared.unfollow(
                currentUserId: currentUserId,
                targetUserId: targetUserId
            )
            relationships.removeAll { $0.userId == targetUserId }
            applyFilter()
        } catch {
            errorMessage = "Failed to unfollow: \(error.localizedDescription)"
        }
    }
}

// MARK: - FollowListView

struct FollowListView: View {

    let mode: FollowListMode
    let userId: String
    let currentUserId: String
    let currentDisplayName: String
    let currentUsername: String

    @State private var viewModel = FollowListViewModel()
    @Environment(AppState.self) private var appState

    var body: some View {
        NavigationStack {
            ZStack {
                Color.kineticsBackground.ignoresSafeArea()

                VStack(spacing: 0) {
                    searchBar.padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 4)

                    if viewModel.isLoading {
                        Spacer()
                        ProgressView().tint(Color.kineticsBlue)
                        Spacer()
                    } else if viewModel.filteredRelationships.isEmpty {
                        emptyState
                    } else {
                        ScrollView(showsIndicators: false) {
                            LazyVStack(spacing: 0) {
                                ForEach(viewModel.filteredRelationships) { relationship in
                                    FollowUserRow(
                                        relationship: relationship,
                                        mode: mode,
                                        currentUserId: currentUserId,
                                        currentDisplayName: currentDisplayName,
                                        currentUsername: currentUsername,
                                        onUnfollow: { targetId in
                                            await viewModel.unfollow(
                                                currentUserId: currentUserId,
                                                targetUserId: targetId
                                            )
                                        }
                                    )
                                    Divider()
                                        .background(Color.white.opacity(0.06))
                                        .padding(.leading, 74)
                                }
                            }
                            .padding(.top, 4)
                        }
                    }
                }
            }
            .navigationTitle(mode.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.kineticsBackground, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .task { await viewModel.load(mode: mode, userId: userId) }
        }
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        let bindable = Bindable(viewModel)
        return HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.kineticsSubtext)
            TextField("Search by name or username", text: bindable.searchText)
                .font(.system(size: 14))
                .foregroundStyle(.white)
                .tint(Color.kineticsBlue)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            if !viewModel.searchText.isEmpty {
                Button { viewModel.searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.kineticsSubtext)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(Color.kineticsDark)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 14) {
            Spacer()
            ZStack {
                Circle()
                    .fill(Color.kineticsDark)
                    .frame(width: 64, height: 64)
                Image(systemName: mode == .followers ? "person.2" : "person.badge.plus")
                    .font(.system(size: 26, weight: .light))
                    .foregroundStyle(Color.kineticsSubtext)
            }
            VStack(spacing: 4) {
                Text("No \(mode.title.lowercased()) yet")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
                Text(mode == .followers
                     ? "When someone follows you, they'll appear here."
                     : "Accounts you follow will appear here.")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.kineticsSubtext)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            Spacer()
        }
    }
}

// MARK: - FollowUserRow

private struct FollowUserRow: View {

    let relationship: FollowRelationship
    let mode: FollowListMode
    let currentUserId: String
    let currentDisplayName: String
    let currentUsername: String
    let onUnfollow: (String) async -> Void

    @State private var showUnfollowConfirm = false

    private var sportEmoji: String {
        switch relationship.primarySport {
        case "striking":                    return "🥊"
        case "grappling":                   return "🤼"
        case "ironTracker", "iron", "gym":  return "🏋️"
        case "wall":                        return "🧗"
        case "run":                         return "🏃"
        default:                            return "⚡️"
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            // Avatar
            avatarCircle

            // Info
            VStack(alignment: .leading, spacing: 3) {
                Text(relationship.displayName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(relationship.username.hasPrefix("@")
                         ? relationship.username
                         : "@\(relationship.username)")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.kineticsSubtext)
                    if !relationship.primarySport.isEmpty {
                        sportBadge
                    }
                }
            }

            Spacer(minLength: 0)

            // Action button
            if mode == .following {
                followingButton
            } else {
                // In followers list: show Follow Back if current user isn't already following them
                FollowButton(
                    currentUserId: currentUserId,
                    targetUserId: relationship.userId,
                    targetDisplayName: relationship.displayName,
                    targetUsername: relationship.username,
                    isTargetPublic: true
                )
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .confirmationDialog(
            "Unfollow \(relationship.displayName)?",
            isPresented: $showUnfollowConfirm,
            titleVisibility: .visible
        ) {
            Button("Unfollow", role: .destructive) {
                Task { await onUnfollow(relationship.userId) }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var avatarCircle: some View {
        ZStack {
            Circle()
                .fill(LinearGradient(
                    colors: [Color.kineticsPurple.opacity(0.7), Color.kineticsBlue.opacity(0.7)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
                .frame(width: 46, height: 46)
            if relationship.avatarURL.isEmpty {
                Text(relationship.displayName.prefix(1).uppercased())
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            } else {
                AsyncImage(url: URL(string: relationship.avatarURL)) { phase in
                    if case .success(let image) = phase {
                        image.resizable().scaledToFill().clipShape(Circle())
                    } else {
                        Text(relationship.displayName.prefix(1).uppercased())
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: 46, height: 46)
                .clipShape(Circle())
            }
        }
    }

    private var sportBadge: some View {
        Text(sportEmoji)
            .font(.system(size: 11))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Color.kineticsDark)
            .clipShape(Capsule())
    }

    private var followingButton: some View {
        Button { showUnfollowConfirm = true } label: {
            Text("Following")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.7))
                .padding(.horizontal, 16).padding(.vertical, 7)
                .background(Color(white: 0.15))
                .clipShape(Capsule())
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}
