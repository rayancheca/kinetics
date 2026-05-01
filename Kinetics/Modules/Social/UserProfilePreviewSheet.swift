import SwiftUI

// MARK: - UserProfilePreviewViewModel

@Observable
@MainActor
final class UserProfilePreviewViewModel {

    var profile: UserProfile?
    var followStatus: FollowStatus = .notFollowing
    var followerCount: Int = 0
    var followingCount: Int = 0
    var postCount: Int = 0
    var recentPosts: [FeedItem] = []
    var isLoading = false
    var errorMessage: String?

    func load(userId: String, currentUserId: String) async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        async let profileFetch = SocialRepository.shared.fetchUserProfile(userId: userId)
        async let statusFetch = SocialRepository.shared.followStatus(currentUserId: currentUserId, targetUserId: userId)
        async let followersFetch = SocialRepository.shared.fetchFollowerCount(userId: userId)
        async let followingFetch = SocialRepository.shared.fetchFollowingCount(userId: userId)
        async let postCountFetch = SocialRepository.shared.fetchUserPostCount(userId: userId)
        async let postsFetch: [FeedItem] = (try? await SocialRepository.shared.fetchUserActivities(userId: userId, limit: 3)) ?? []

        let (fetchedProfile, status, followers, following, posts, recentItems) = await (
            try? profileFetch,
            statusFetch,
            followersFetch,
            followingFetch,
            (try? postCountFetch) ?? 0,
            postsFetch
        )

        profile = fetchedProfile
        followStatus = status
        followerCount = followers
        followingCount = following
        postCount = posts
        recentPosts = recentItems
    }

    func follow(currentUserId: String, currentDisplayName: String) async {
        guard let profile = profile else { return }
        followStatus = .requested
        do {
            try await SocialRepository.shared.follow(
                currentUserId: currentUserId,
                currentDisplayName: currentDisplayName,
                currentUsername: "",
                targetUserId: profile.id,
                targetDisplayName: profile.displayName,
                targetUsername: profile.username,
                isTargetPublic: profile.isPublic
            )
            followStatus = profile.isPublic ? .following : .requested
        } catch {
            followStatus = .notFollowing
        }
    }

    func unfollow(currentUserId: String) async {
        guard let profile = profile else { return }
        followStatus = .notFollowing
        try? await SocialRepository.shared.unfollow(currentUserId: currentUserId, targetUserId: profile.id)
    }
}

// MARK: - UserProfilePreviewSheet

@MainActor
struct UserProfilePreviewSheet: View {

    let userId: String

    @Environment(AppState.self) private var appState
    @State private var viewModel = UserProfilePreviewViewModel()
    @Environment(\.dismiss) private var dismiss

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
            ZStack {
                Color.kineticsBackground.ignoresSafeArea()
                if viewModel.isLoading {
                    loadingView
                } else if let profile = viewModel.profile {
                    profileContent(profile)
                } else {
                    errorView
                }
            }
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
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .task {
            await viewModel.load(userId: userId, currentUserId: currentUserId)
        }
    }

    // MARK: Profile Content

    private func profileContent(_ profile: UserProfile) -> some View {
        ScrollView {
            VStack(spacing: 0) {
                avatarHeader(profile)
                    .padding(.top, 24)
                    .padding(.horizontal, 24)

                statsRow
                    .padding(.top, 20)
                    .padding(.horizontal, 24)

                Divider().background(.white.opacity(0.07))
                    .padding(.top, 20)

                if viewModel.followStatus != .self_ {
                    followButton(profile)
                        .padding(.horizontal, 24)
                        .padding(.top, 16)
                }

                if !viewModel.recentPosts.isEmpty {
                    recentPostsList
                        .padding(.top, 20)
                }

                viewFullProfileButton
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
                    .padding(.bottom, 24)
            }
        }
    }

    // MARK: Avatar Header

    private func avatarHeader(_ profile: UserProfile) -> some View {
        HStack(alignment: .top, spacing: 16) {
            ZStack {
                Circle()
                    .stroke(sportGradient(for: profile.primarySport), lineWidth: 3)
                    .frame(width: 72, height: 72)
                Circle()
                    .fill(LinearGradient(
                        colors: [Color.kineticsPurple, Color.kineticsBlue],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
                    .frame(width: 64, height: 64)
                Text(String(profile.displayName.prefix(1)).uppercased())
                    .font(.system(size: 26, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 5) {
                Text(profile.displayName)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text(profile.username)
                    .font(.system(size: 14))
                    .foregroundStyle(Color.kineticsSubtext)
                if !profile.bio.isEmpty {
                    Text(profile.bio)
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.75))
                        .lineLimit(2)
                        .padding(.top, 2)
                }
                HStack(spacing: 8) {
                    SportBadge(sport: profile.primarySport)
                    Text("Member since \(memberSince(profile.joinedAt))")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.kineticsSubtext)
                }
                .padding(.top, 4)
            }
            Spacer()
        }
    }

    // MARK: Stats Row

    private var statsRow: some View {
        HStack(spacing: 0) {
            statCell(value: "\(viewModel.postCount)", label: "Posts")
            Divider().background(.white.opacity(0.1)).frame(height: 30)
            statCell(value: "\(viewModel.followerCount)", label: "Followers")
            Divider().background(.white.opacity(0.1)).frame(height: 30)
            statCell(value: "\(viewModel.followingCount)", label: "Following")
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(Color(white: 0.08), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.white.opacity(0.07), lineWidth: 1))
    }

    private func statCell(value: String, label: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.kineticsSubtext)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Follow Button

    private func followButton(_ profile: UserProfile) -> some View {
        Button {
            Task {
                if viewModel.followStatus == .following {
                    await viewModel.unfollow(currentUserId: currentUserId)
                } else {
                    await viewModel.follow(currentUserId: currentUserId, currentDisplayName: currentDisplayName)
                }
            }
        } label: {
            HStack(spacing: 8) {
                if viewModel.followStatus == .following {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .bold))
                }
                Text(followButtonLabel)
                    .font(.system(size: 15, weight: .semibold))
            }
            .foregroundStyle(followButtonForeground)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(followButtonBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(followButtonStroke, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var followButtonLabel: String {
        switch viewModel.followStatus {
        case .notFollowing: return "Follow"
        case .requested:    return "Requested"
        case .following:    return "Following"
        case .self_:        return ""
        }
    }

    private var followButtonForeground: Color {
        switch viewModel.followStatus {
        case .notFollowing: return .kineticsBackground
        case .requested:    return Color.kineticsSubtext
        case .following:    return Color.kineticsGreen
        case .self_:        return .clear
        }
    }

    private var followButtonBackground: AnyShapeStyle {
        switch viewModel.followStatus {
        case .notFollowing: return AnyShapeStyle(Color.kineticsBlue)
        default:            return AnyShapeStyle(Color.clear)
        }
    }

    private var followButtonStroke: Color {
        switch viewModel.followStatus {
        case .notFollowing: return .clear
        case .requested:    return Color.kineticsSubtext.opacity(0.35)
        case .following:    return Color.kineticsGreen.opacity(0.45)
        case .self_:        return .clear
        }
    }

    // MARK: Recent Posts

    private var recentPostsList: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Recent Posts")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.kineticsSubtext)
                .padding(.horizontal, 24)
                .padding(.bottom, 10)
            VStack(spacing: 0) {
                ForEach(viewModel.recentPosts) { item in
                    RecentPostRow(item: item)
                        .padding(.horizontal, 24)
                    Divider().background(.white.opacity(0.05)).padding(.horizontal, 24)
                }
            }
        }
    }

    // MARK: View Full Profile Button

    private var viewFullProfileButton: some View {
        Button {
            dismiss()
        } label: {
            HStack(spacing: 6) {
                Text("View Full Profile")
                    .font(.system(size: 14, weight: .semibold))
                Image(systemName: "arrow.right")
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(Color.kineticsBlue)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color.kineticsBlue.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.kineticsBlue.opacity(0.25), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: Loading / Error

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView().tint(Color.kineticsBlue).scaleEffect(1.2)
            Text("Loading profile…")
                .font(.system(size: 14))
                .foregroundStyle(Color.kineticsSubtext)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var errorView: some View {
        VStack(spacing: 14) {
            Image(systemName: "person.slash")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(Color.kineticsSubtext.opacity(0.5))
            Text("Profile not found")
                .font(.system(size: 15))
                .foregroundStyle(Color.kineticsSubtext)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Helpers

    private func sportGradient(for sport: String) -> LinearGradient {
        let colors: [Color] = {
            switch sport {
            case "striking":  return [.kineticsRed, .kineticsOrange]
            case "grappling": return [.kineticsOrange, Color(red: 0.9, green: 0.6, blue: 0)]
            case "iron", "ironTracker", "gym": return [.kineticsBlue, .kineticsPurple]
            case "wall":      return [.kineticsGreen, .kineticsBlue]
            case "run":       return [Color(red: 0.3, green: 0.8, blue: 1.0), .kineticsGreen]
            default:          return [.kineticsPurple, .kineticsBlue]
            }
        }()
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private func memberSince(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM yyyy"
        return formatter.string(from: date)
    }
}

// MARK: - RecentPostRow

private struct RecentPostRow: View {

    let item: FeedItem

    private var timeAgo: String {
        let interval = Date().timeIntervalSince(item.postedAt)
        switch interval {
        case ..<60:               return "Just now"
        case ..<3_600:            return "\(Int(interval / 60))m ago"
        case ..<86_400:           return "\(Int(interval / 3_600))h ago"
        default:                  return "\(Int(interval / 86_400))d ago"
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: postIcon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.kineticsBlue.opacity(0.7))
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(timeAgo)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.kineticsSubtext)
            }
            Spacer()
            HStack(spacing: 4) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.kineticsRed.opacity(0.7))
                Text("\(item.kudosCount)")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.kineticsSubtext)
            }
        }
        .padding(.vertical, 10)
    }

    private var postIcon: String {
        switch item.activityType {
        case "run":      return "figure.run"
        case "striking": return "figure.boxing"
        case "grappling": return "figure.martial.arts"
        case "iron", "ironTracker", "gym": return "dumbbell.fill"
        case "wall":     return "figure.climbing"
        default:         return "bolt.fill"
        }
    }
}
