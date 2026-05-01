import SwiftUI

// MARK: - FollowButton

/// A smart follow/unfollow button that adapts its label and style to the current
/// follow status between the signed-in user and a target profile.
///
/// The component loads the initial status via a `.task` modifier and keeps local
/// state optimistically up-to-date after each action.
struct FollowButton: View {

    let currentUserId: String
    let targetUserId: String
    let targetDisplayName: String
    let targetUsername: String
    /// Pass `true` for public profiles; `false` triggers a follow-request flow.
    var isTargetPublic: Bool = true

    @State private var status: FollowStatus = .notFollowing
    @State private var isLoading = false
    @State private var showUnfollowConfirm = false

    var body: some View {
        Button(action: handleTap) {
            HStack(spacing: 6) {
                if isLoading {
                    ProgressView()
                        .tint(progressTintColor)
                        .scaleEffect(0.7)
                        .frame(width: 12, height: 12)
                }
                Text(buttonLabel)
                    .font(.system(size: 14, weight: .semibold))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 9)
            .background(buttonBackground)
            .foregroundStyle(buttonForeground)
            .clipShape(Capsule())
            .overlay(
                Capsule().strokeBorder(
                    status == .following || status == .requested
                        ? Color.white.opacity(0.2)
                        : Color.clear,
                    lineWidth: 1
                )
            )
        }
        .buttonStyle(.plain)
        .disabled(isLoading || status == .self_)
        .task { await loadStatus() }
        .confirmationDialog(
            "Unfollow \(targetDisplayName)?",
            isPresented: $showUnfollowConfirm,
            titleVisibility: .visible
        ) {
            Button("Unfollow", role: .destructive) {
                Task { await performUnfollow() }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: - Label & Style

    private var buttonLabel: String {
        switch status {
        case .notFollowing: return "Follow"
        case .requested:    return "Requested"
        case .following:    return "Following"
        case .self_:        return "Edit Profile"
        }
    }

    private var buttonBackground: Color {
        switch status {
        case .notFollowing: return Color.kineticsBlue
        case .requested:    return Color(white: 0.18)
        case .following:    return Color(white: 0.18)
        case .self_:        return Color.kineticsDark
        }
    }

    private var buttonForeground: Color {
        switch status {
        case .notFollowing: return .white
        case .requested:    return .white.opacity(0.7)
        case .following:    return .white.opacity(0.7)
        case .self_:        return Color.kineticsSubtext
        }
    }

    private var progressTintColor: Color {
        status == .notFollowing ? .white : Color.kineticsSubtext
    }

    // MARK: - Actions

    private func handleTap() {
        switch status {
        case .notFollowing:  Task { await performFollow() }
        case .requested:     Task { await performCancelRequest() }
        case .following:     showUnfollowConfirm = true
        case .self_:         break
        }
    }

    private func loadStatus() async {
        status = await SocialRepository.shared.followStatus(
            currentUserId: currentUserId,
            targetUserId: targetUserId
        )
    }

    private func performFollow() async {
        isLoading = true
        let optimisticStatus: FollowStatus = isTargetPublic ? .following : .requested
        status = optimisticStatus
        do {
            try await SocialRepository.shared.follow(
                currentUserId: currentUserId,
                currentDisplayName: "",
                currentUsername: "",
                targetUserId: targetUserId,
                targetDisplayName: targetDisplayName,
                targetUsername: targetUsername,
                isTargetPublic: isTargetPublic
            )
        } catch {
            // Roll back optimistic update on failure.
            status = .notFollowing
        }
        isLoading = false
    }

    private func performUnfollow() async {
        isLoading = true
        status = .notFollowing
        do {
            try await SocialRepository.shared.unfollow(
                currentUserId: currentUserId,
                targetUserId: targetUserId
            )
        } catch {
            status = .following
        }
        isLoading = false
    }

    private func performCancelRequest() async {
        isLoading = true
        status = .notFollowing
        do {
            try await SocialRepository.shared.cancelFollowRequest(
                currentUserId: currentUserId,
                targetUserId: targetUserId
            )
        } catch {
            status = .requested
        }
        isLoading = false
    }
}
