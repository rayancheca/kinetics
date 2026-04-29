import SwiftUI

// MARK: - UserProfileViewModel

/// Drives `UserProfileView`.
///
/// `load(userId:)` fires both fetches in parallel via `async let` so the profile
/// header and the activity list arrive together rather than in two serial round-trips.
@Observable
@MainActor
final class UserProfileViewModel {

    // MARK: - State

    var profile: UserProfile?
    var activities: [FeedItem] = []
    var isLoading = false
    var errorMessage: String?

    // MARK: - Edit Bio

    var isEditingBio = false
    var editBioText = ""

    // MARK: - Load

    /// Fetches the user profile and their recent public activities in parallel.
    func load(userId: String) async {
        isLoading = true
        errorMessage = nil

        do {
            async let profileFetch = SocialRepository.shared.fetchProfile(userId: userId)
            async let activitiesFetch = SocialRepository.shared.fetchUserActivities(userId: userId)

            let (fetchedProfile, fetchedActivities) = try await (profileFetch, activitiesFetch)
            profile = fetchedProfile
            activities = fetchedActivities
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    // MARK: - Save Bio

    /// Persists the edited bio text back to Firestore.
    ///
    /// Creates a mutated copy of the current profile — never mutates the value
    /// in place — then calls `SocialRepository.updateProfile(_:)`.
    func saveBio(userId: String) async {
        guard var updatedProfile = profile else { return }

        let trimmed = editBioText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != updatedProfile.bio else {
            isEditingBio = false
            return
        }

        updatedProfile.bio = trimmed

        do {
            try await SocialRepository.shared.updateProfile(updatedProfile)
            profile = updatedProfile
            isEditingBio = false
        } catch {
            errorMessage = "Failed to save bio: \(error.localizedDescription)"
        }
    }
}

// MARK: - UserProfileView

/// Displays a user's profile header, aggregate stats, and recent public activities.
///
/// Pass `isCurrentUser: true` when the signed-in user is viewing their own profile
/// to unlock the Edit bio toolbar button.
@MainActor
struct UserProfileView: View {

    // MARK: - Props

    let userId: String
    var isCurrentUser: Bool = false

    // MARK: - Dependencies

    @Environment(AppState.self) private var appState
    @State private var viewModel = UserProfileViewModel()

    // MARK: - Body

    var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: 0) {
                // Profile header
                if let profile = viewModel.profile {
                    let bindable = Bindable(viewModel)
                    ProfileHeaderView(
                        profile: profile,
                        isCurrentUser: isCurrentUser,
                        isEditingBio: bindable.isEditingBio,
                        editBioText: bindable.editBioText,
                        onSave: { await viewModel.saveBio(userId: userId) }
                    )
                } else if viewModel.isLoading {
                    profileHeaderSkeleton
                }

                // Stats row
                if let profile = viewModel.profile {
                    ProfileStatRow(profile: profile)
                        .padding(.horizontal, 16)
                        .padding(.top, 20)
                }

                // Error
                if let message = viewModel.errorMessage {
                    Text(message)
                        .font(.system(size: 13))
                        .foregroundStyle(Color.kineticsRed)
                        .padding(16)
                }

                // Recent activity
                recentActivitySection

                Spacer(minLength: 40)
            }
        }
        .background(Color.kineticsBackground)
        .navigationTitle(viewModel.profile?.displayName ?? "Profile")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.kineticsBackground, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            if isCurrentUser {
                ToolbarItem(placement: .navigationBarTrailing) {
                    editBioButton
                }
            }
        }
        .task { await viewModel.load(userId: userId) }
    }

    // MARK: - Recent Activity Section

    private var recentActivitySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent Activity")
                .font(.system(size: 13, weight: .semibold))
                .tracking(1.4)
                .foregroundStyle(.white.opacity(0.38))
                .padding(.horizontal, 20)
                .padding(.top, 24)

            if viewModel.activities.isEmpty && !viewModel.isLoading {
                Text("No public activity yet")
                    .font(.system(size: 15))
                    .foregroundStyle(Color.kineticsSubtext)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 32)
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(viewModel.activities) { item in
                        MiniActivityCard(item: item)
                            .padding(.horizontal, 16)
                    }
                }
            }
        }
    }

    // MARK: - Skeleton

    private var profileHeaderSkeleton: some View {
        VStack(spacing: 12) {
            Circle()
                .fill(Color.kineticsDark)
                .frame(width: 80, height: 80)
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color.kineticsDark)
                .frame(width: 140, height: 18)
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color.kineticsDark)
                .frame(width: 90, height: 14)
        }
        .padding(.top, 32)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Edit Bio Button

    private var editBioButton: some View {
        Button {
            if let bio = viewModel.profile?.bio {
                viewModel.editBioText = bio
            }
            viewModel.isEditingBio = true
        } label: {
            Text("Edit")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color.kineticsBlue)
        }
    }
}

// MARK: - MiniActivityCard

/// Compact activity card used inside `UserProfileView`'s recent-activity list.
/// Intentionally simpler than the full `FeedItemCardView` — no kudos or comments
/// controls, just title + subtitle + type indicator.
private struct MiniActivityCard: View {

    let item: FeedItem

    var body: some View {
        HStack(spacing: 12) {
            // Activity type icon
            Image(systemName: activityIcon(for: item.activityType))
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(activityColor(for: item.activityType))
                .frame(width: 36, height: 36)
                .background(
                    activityColor(for: item.activityType).opacity(0.12)
                )
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Text(item.subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.kineticsSubtext)
                    .lineLimit(1)
            }

            Spacer()

            Text(item.postedAt.relativeFormatted)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.3))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(Color.kineticsDark)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Helpers

    private func activityIcon(for type: String) -> String {
        switch type {
        case "run":        return "figure.run"
        case "striking":   return "bolt.fill"
        case "grappling":  return "person.2.fill"
        case "iron":       return "dumbbell.fill"
        case "wall":       return "figure.climbing"
        default:           return "flame.fill"
        }
    }

    private func activityColor(for type: String) -> Color {
        switch type {
        case "run":        return Color.kineticsGreen
        case "striking":   return Color.kineticsRed
        case "grappling":  return Color.kineticsOrange
        case "iron":       return Color.kineticsBlue
        case "wall":       return Color.kineticsGreen
        default:           return Color.kineticsPurple
        }
    }
}

// MARK: - ProfileHeaderView

/// Displays the avatar, display name, @username, bio, and — when the owner is
/// viewing their own profile and has tapped Edit — an inline bio editor.
private struct ProfileHeaderView: View {

    let profile: UserProfile
    let isCurrentUser: Bool

    @Binding var isEditingBio: Bool
    @Binding var editBioText: String

    let onSave: () async -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Avatar
            avatarView
                .padding(.top, 32)

            // Display name
            Text(profile.displayName)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white)
                .padding(.top, 12)

            // Username
            Text(profile.username)
                .font(.system(size: 15))
                .foregroundStyle(Color.kineticsSubtext)
                .padding(.top, 2)

            // Bio — static or editable
            if isCurrentUser && isEditingBio {
                editBioField
                    .padding(.top, 10)
                    .padding(.horizontal, 24)
            } else {
                if !profile.bio.isEmpty {
                    Text(profile.bio)
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.6))
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                        .padding(.top, 8)
                        .padding(.horizontal, 32)
                }
            }

            // Bottom padding before stats
            Spacer().frame(height: 20)

            // Thin separator
            Divider()
                .background(.white.opacity(0.07))
        }
    }

    // MARK: - Avatar

    private var avatarView: some View {
        Group {
            if profile.avatarURL.isEmpty {
                // Gradient placeholder — purple-to-blue matches the social accent
                ZStack {
                    LinearGradient(
                        colors: [Color.kineticsPurple, Color.kineticsBlue],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    Text(String(profile.displayName.prefix(1)).uppercased())
                        .font(.system(size: 30, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                }
                .frame(width: 80, height: 80)
                .clipShape(Circle())
            } else {
                AsyncImage(url: URL(string: profile.avatarURL)) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        avatarFallback
                    }
                }
                .frame(width: 80, height: 80)
                .clipShape(Circle())
            }
        }
        .overlay(
            Circle()
                .strokeBorder(.white.opacity(0.08), lineWidth: 1.5)
        )
    }

    private var avatarFallback: some View {
        LinearGradient(
            colors: [Color.kineticsPurple, Color.kineticsBlue],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    // MARK: - Bio Edit Field

    private var editBioField: some View {
        VStack(spacing: 8) {
            TextField("Bio", text: $editBioText, axis: .vertical)
                .font(.system(size: 14))
                .foregroundStyle(.white)
                .tint(Color.kineticsBlue)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color.kineticsDark)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .lineLimit(3, reservesSpace: true)

            HStack(spacing: 10) {
                Button {
                    isEditingBio = false
                } label: {
                    Text("Cancel")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.kineticsSubtext)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(.white.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                }

                Button {
                    Task { await onSave() }
                } label: {
                    Text("Save")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.kineticsDark)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(Color.kineticsBlue)
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
            }
        }
    }
}

// MARK: - ProfileStatRow

/// Three-column stats bar: total workouts / total distance / primary sport.
private struct ProfileStatRow: View {

    let profile: UserProfile

    private var distanceKm: String {
        let km = profile.totalDistanceMeters / 1_000
        if km < 1 {
            return String(format: "%.0fm", profile.totalDistanceMeters)
        }
        return String(format: "%.1f", km)
    }

    var body: some View {
        HStack(spacing: 0) {
            statColumn(
                label: "WORKOUTS",
                value: "\(profile.totalWorkouts)"
            )

            columnDivider

            statColumn(
                label: "DISTANCE",
                value: distanceKm,
                unit: profile.totalDistanceMeters >= 1_000 ? "km" : nil
            )

            columnDivider

            statColumn(
                label: "SPORT",
                value: profile.primarySport.uppercased()
            )
        }
        .padding(.vertical, 16)
        .background(Color.kineticsDark)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: - Column

    private func statColumn(label: String, value: String, unit: String? = nil) -> some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .tracking(1.6)
                .foregroundStyle(.white.opacity(0.38))

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 20, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                if let unit {
                    Text(unit)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.kineticsSubtext)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Divider

    private var columnDivider: some View {
        Rectangle()
            .fill(.white.opacity(0.07))
            .frame(width: 1, height: 36)
    }
}

// MARK: - KudosButton

/// Heart button with animated scale pulse and a running kudos count.
///
/// The `action` closure runs an async operation (Firestore write) — it is
/// called after the haptic animation begins so the UI responds instantly.
struct KudosButton: View {

    let isLiked: Bool
    let count: Int
    let action: () async -> Void

    @State private var isAnimating = false

    var body: some View {
        Button {
            triggerKudos()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: isLiked ? "heart.fill" : "heart")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(isLiked ? Color.kineticsBlue : .white.opacity(0.5))
                    .scaleEffect(isAnimating ? 1.35 : 1.0)

                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(isLiked ? Color.kineticsBlue : .white.opacity(0.5))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(
            .spring(response: 0.3, dampingFraction: 0.5),
            value: isAnimating
        )
    }

    // MARK: - Private

    private func triggerKudos() {
        // Visual pulse
        isAnimating = true
        Task {
            try? await Task.sleep(nanoseconds: 300_000_000) // 300ms
            isAnimating = false
        }
        // Firestore write — runs concurrently with animation
        Task { await action() }
    }
}

// MARK: - CommentSectionView

/// Loads and displays comments for an activity, plus an inline compose field.
///
/// Comments are loaded once via `.task` and appended optimistically on post
/// so the user sees their comment immediately without waiting for a Firestore
/// round-trip confirmation.
struct CommentSectionView: View {

    // MARK: - Props

    let activityId: String
    var currentUserId: String
    var currentDisplayName: String

    // MARK: - State

    @State private var comments: [ActivityComment] = []
    @State private var newCommentText = ""
    @State private var isLoading = false
    @State private var isPosting = false

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // Header
            Text("Comments")
                .font(.system(size: 13, weight: .semibold))
                .tracking(1.4)
                .foregroundStyle(.white.opacity(0.38))
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

            Divider().background(.white.opacity(0.06))

            if isLoading {
                ProgressView()
                    .tint(Color.kineticsBlue)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
            } else if comments.isEmpty {
                Text("Be the first to comment")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.kineticsSubtext)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(comments) { comment in
                        CommentRow(comment: comment)
                        Divider().background(.white.opacity(0.05)).padding(.leading, 58)
                    }
                }
            }

            Divider().background(.white.opacity(0.06))

            // Compose bar
            composeBar
        }
        .background(Color.kineticsDark)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .task {
            await loadComments()
        }
    }

    // MARK: - Compose Bar

    private var composeBar: some View {
        HStack(spacing: 10) {
            // Current user avatar placeholder
            ZStack {
                LinearGradient(
                    colors: [Color.kineticsPurple, Color.kineticsBlue],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Text(String(currentDisplayName.prefix(1)).uppercased())
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 30, height: 30)
            .clipShape(Circle())

            TextField("Add a comment…", text: $newCommentText)
                .font(.system(size: 14))
                .foregroundStyle(.white)
                .tint(Color.kineticsBlue)
                .submitLabel(.send)
                .onSubmit { Task { await postComment() } }

            Button {
                Task { await postComment() }
            } label: {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(
                        newCommentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            ? Color.kineticsSubtext
                            : Color.kineticsBlue
                    )
            }
            .disabled(
                newCommentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isPosting
            )
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    // MARK: - Data

    private func loadComments() async {
        isLoading = true
        do {
            comments = try await SocialRepository.shared.fetchComments(activityId: activityId)
        } catch {
            // Non-fatal — silently leave the list empty.
        }
        isLoading = false
    }

    private func postComment() async {
        let trimmed = newCommentText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isPosting else { return }

        isPosting = true

        let newComment = ActivityComment(
            id: UUID().uuidString,
            userId: currentUserId,
            displayName: currentDisplayName,
            avatarURL: "",
            text: trimmed,
            postedAt: Date()
        )

        // Optimistic append
        comments.append(newComment)
        newCommentText = ""

        do {
            try await SocialRepository.shared.postComment(newComment, activityId: activityId)
        } catch {
            // Roll back optimistic append on failure
            comments.removeAll { $0.id == newComment.id }
            newCommentText = trimmed
        }

        isPosting = false
    }
}

// MARK: - CommentRow

/// Single comment row: 30pt avatar circle + display name + text + relative timestamp.
private struct CommentRow: View {

    let comment: ActivityComment

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // Avatar
            Group {
                if comment.avatarURL.isEmpty {
                    ZStack {
                        LinearGradient(
                            colors: [Color.kineticsPurple.opacity(0.7), Color.kineticsBlue.opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        Text(String(comment.displayName.prefix(1)).uppercased())
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                    }
                } else {
                    AsyncImage(url: URL(string: comment.avatarURL)) { phase in
                        if case .success(let image) = phase {
                            image.resizable().scaledToFill()
                        } else {
                            Color.kineticsMidGray
                        }
                    }
                }
            }
            .frame(width: 30, height: 30)
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(comment.displayName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)

                    Text(comment.postedAt.relativeFormatted)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.3))
                }

                Text(comment.text)
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }
}

// MARK: - Date + relativeFormatted

private extension Date {

    /// Returns a compact relative time string (e.g. "2m", "4h", "3d").
    var relativeFormatted: String {
        let seconds = Int(Date().timeIntervalSince(self))
        switch seconds {
        case ..<60:            return "now"
        case 60..<3_600:       return "\(seconds / 60)m"
        case 3_600..<86_400:   return "\(seconds / 3_600)h"
        case 86_400..<604_800: return "\(seconds / 86_400)d"
        default:
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d"
            return formatter.string(from: self)
        }
    }
}
