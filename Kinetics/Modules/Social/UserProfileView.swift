import Charts
import SwiftUI

// MARK: - ProfileTab

enum ProfileTab: String, CaseIterable {
    case posts = "Posts"
    case stats = "Stats"
}

// MARK: - AchievementBadge

struct AchievementBadge: Identifiable, Sendable {
    let id: String
    let icon: String
    let label: String
    let earned: Bool
}

// MARK: - UserProfileViewModel

@Observable
@MainActor
final class UserProfileViewModel {

    var profile: UserProfile?
    var activities: [FeedItem] = []
    var isLoading = false
    var errorMessage: String?
    var selectedTab: ProfileTab = .posts
    var isEditingBio = false
    var editBioText = ""

    var badges: [AchievementBadge] {
        let count = profile?.totalWorkouts ?? 0
        return [
            AchievementBadge(id: "first",   icon: "\u{1F525}", label: "First Workout", earned: count >= 1),
            AchievementBadge(id: "ten",     icon: "\u{1F4AA}", label: "10 Workouts",   earned: count >= 10),
            AchievementBadge(id: "pr",      icon: "\u{1F3C6}", label: "First PR",      earned: count >= 1),
            AchievementBadge(id: "streak7", icon: "\u{26A1}",  label: "7-Day Streak",  earned: count >= 7),
            AchievementBadge(id: "fifty",   icon: "\u{1F3AF}", label: "50 Workouts",   earned: count >= 50)
        ]
    }

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

    func saveBio(userId: String) async {
        guard var updatedProfile = profile else { return }
        let trimmed = editBioText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != updatedProfile.bio else { isEditingBio = false; return }
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

@MainActor
struct UserProfileView: View {

    let userId: String
    var isCurrentUser: Bool = false

    @Environment(AppState.self) private var appState
    @State private var viewModel = UserProfileViewModel()

    var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: 0) {
                if let profile = viewModel.profile {
                    ProfileBannerHeader(
                        profile: profile,
                        isCurrentUser: isCurrentUser,
                        onEditTap: {
                            viewModel.editBioText = profile.bio
                            viewModel.isEditingBio = true
                        }
                    )
                } else if viewModel.isLoading {
                    profileHeaderSkeleton
                }

                if let profile = viewModel.profile {
                    ProfileStatsStrip(profile: profile)
                        .padding(.horizontal, 16).padding(.top, 20)
                }

                if viewModel.profile != nil {
                    achievementSection.padding(.top, 20)
                }

                if let message = viewModel.errorMessage {
                    ErrorBannerView(message: message) { viewModel.errorMessage = nil }
                        .padding(.horizontal, 16).padding(.top, 8).transition(.opacity)
                }

                if viewModel.isEditingBio {
                    let bindable = Bindable(viewModel)
                    BioEditOverlay(
                        editBioText: bindable.editBioText,
                        isEditing: bindable.isEditingBio,
                        onSave: { await viewModel.saveBio(userId: userId) }
                    )
                    .padding(.horizontal, 16).padding(.top, 12)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                if viewModel.profile != nil {
                    ProfileTabSelector(selectedTab: $viewModel.selectedTab)
                        .padding(.horizontal, 16).padding(.top, 24)
                    tabContent.padding(.top, 16)
                }

                Spacer(minLength: 40)
            }
        }
        .background(Color.kineticsBackground)
        .navigationTitle(viewModel.profile?.displayName ?? "Profile")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.kineticsBackground, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task { await viewModel.load(userId: userId) }
    }

    private var achievementSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("ACHIEVEMENTS")
                .font(.system(size: 10, weight: .semibold)).tracking(2.0)
                .foregroundStyle(.white.opacity(0.38)).padding(.horizontal, 20)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(viewModel.badges) { badge in BadgePill(badge: badge) }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    @ViewBuilder
    private var tabContent: some View {
        switch viewModel.selectedTab {
        case .posts:  postsTab
        case .stats:  statsTab
        }
    }

    private var postsTab: some View {
        Group {
            if viewModel.isLoading {
                ProgressView().tint(Color.kineticsBlue).frame(maxWidth: .infinity).padding(.vertical, 40)
            } else if viewModel.activities.isEmpty {
                emptyActivityState
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(viewModel.activities) { item in
                        CompactActivityCard(item: item).padding(.horizontal, 16)
                    }
                }
            }
        }
    }

    private var statsTab: some View {
        VStack(spacing: 20) {
            if let profile = viewModel.profile {
                TrainingFrequencyChart(workoutCount: profile.totalWorkouts).padding(.horizontal, 16)
                VolumeOverTimeChart(workoutCount: profile.totalWorkouts).padding(.horizontal, 16)
                TopSportsChart(activities: viewModel.activities).padding(.horizontal, 16)
            }
        }
        .padding(.bottom, 20)
    }

    private var emptyActivityState: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle().fill(Color.kineticsDark).frame(width: 64, height: 64)
                Image(systemName: "figure.run.circle").font(.system(size: 28, weight: .light)).foregroundStyle(Color.kineticsSubtext)
            }
            VStack(spacing: 4) {
                Text("No public activity yet").font(.system(size: 15, weight: .semibold)).foregroundStyle(.white.opacity(0.7))
                Text("Completed sessions will appear here.").font(.system(size: 13)).foregroundStyle(Color.kineticsSubtext).multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity).padding(.vertical, 40).padding(.horizontal, 16)
    }

    private var profileHeaderSkeleton: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Color.kineticsDark).frame(height: 140)
            VStack(spacing: 10) {
                Circle().fill(Color.kineticsMidGray).frame(width: 64, height: 64).offset(y: -32)
                RoundedRectangle(cornerRadius: 4).fill(Color.kineticsDark).frame(width: 140, height: 18)
                RoundedRectangle(cornerRadius: 4).fill(Color.kineticsDark).frame(width: 200, height: 13)
            }
            .padding(.top, -32).padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity).redacted(reason: .placeholder)
    }
}

// MARK: - ProfileBannerHeader

private struct ProfileBannerHeader: View {

    let profile: UserProfile
    let isCurrentUser: Bool
    let onEditTap: () -> Void

    private var bannerGradient: [Color] { sportBannerGradient(for: profile.primarySport) }

    var body: some View {
        ZStack(alignment: .bottom) {
            LinearGradient(colors: bannerGradient, startPoint: .topLeading, endPoint: .bottomTrailing)
                .frame(height: 140)
                .overlay(alignment: .topTrailing) {
                    if isCurrentUser {
                        Button(action: onEditTap) {
                            Image(systemName: "pencil.circle.fill")
                                .font(.system(size: 24)).foregroundStyle(.white.opacity(0.9)).padding(14)
                        }
                    }
                }
            ZStack {
                Circle().fill(Color.kineticsDark).frame(width: 64, height: 64)
                    .overlay(Circle().strokeBorder(.white.opacity(0.15), lineWidth: 2))
                if profile.avatarURL.isEmpty {
                    Text(String(profile.displayName.prefix(1)).uppercased())
                        .font(.system(size: 26, weight: .black, design: .rounded)).foregroundStyle(.white)
                } else {
                    AsyncImage(url: URL(string: profile.avatarURL)) { phase in
                        if case .success(let image) = phase { image.resizable().scaledToFill().clipShape(Circle()) }
                        else { Text(String(profile.displayName.prefix(1)).uppercased())
                            .font(.system(size: 26, weight: .black, design: .rounded)).foregroundStyle(.white) }
                    }
                }
            }
            .offset(y: 32)
        }
        .padding(.bottom, 42)

        VStack(spacing: 4) {
            Text(profile.displayName).font(.system(size: 22, weight: .bold, design: .rounded)).foregroundStyle(.white)
            if !profile.bio.isEmpty {
                Text(profile.bio).font(.system(size: 13)).foregroundStyle(Color.kineticsSubtext)
                    .multilineTextAlignment(.center).lineSpacing(2).padding(.horizontal, 32)
            }
            Text("Joined \(profile.joinedAt.monthYear)").font(.system(size: 11)).foregroundStyle(.white.opacity(0.35)).padding(.top, 2)
        }
        .padding(.horizontal, 20).padding(.bottom, 8).frame(maxWidth: .infinity)
    }

    private func sportBannerGradient(for sport: String) -> [Color] {
        switch sport {
        case "striking":                    return [Color(hex: "#FF6B35"), Color(hex: "#FF3B30")]
        case "grappling":                   return [Color(hex: "#5856D6"), Color(hex: "#9B59B6")]
        case "ironTracker", "iron", "gym":  return [Color(hex: "#FF9F0A"), Color(hex: "#CC7A00")]
        case "wall":                        return [Color(hex: "#00BF96"), Color(hex: "#34C759")]
        case "run":                         return [Color.kineticsBlue, Color(hex: "#30D158")]
        default:                            return [Color.kineticsBlue, Color(hex: "#5856D6")]
        }
    }
}

// MARK: - ProfileStatsStrip

private struct ProfileStatsStrip: View {

    let profile: UserProfile

    private var volumeFormatted: String {
        let km = profile.totalDistanceMeters / 1_000
        if km >= 1 { return String(format: "%.1f", km) }
        return String(format: "%.0f", profile.totalDistanceMeters) + "m"
    }

    var body: some View {
        HStack(spacing: 0) {
            statColumn(label: "Sessions", value: "\(profile.totalWorkouts)")
            columnDivider
            statColumn(label: "Volume", value: volumeFormatted, unit: profile.totalDistanceMeters >= 1_000 ? "km" : nil)
            columnDivider
            statColumn(label: "Streak", value: "7", unit: "d")
            columnDivider
            statColumn(label: "PRs", value: "\(profile.totalWorkouts / 5)")
        }
        .padding(.vertical, 16)
        .background(Color.kineticsDark)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func statColumn(label: String, value: String, unit: String? = nil) -> some View {
        VStack(spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.7)
                if let unit { Text(unit).font(.system(size: 11, weight: .medium)).foregroundStyle(Color.kineticsSubtext) }
            }
            Text(label).font(.system(size: 10, weight: .medium)).foregroundStyle(Color.kineticsSubtext)
        }
        .frame(maxWidth: .infinity)
    }

    private var columnDivider: some View {
        Rectangle().fill(.white.opacity(0.07)).frame(width: 1, height: 36)
    }
}

// MARK: - BadgePill

private struct BadgePill: View {

    let badge: AchievementBadge

    var body: some View {
        HStack(spacing: 6) {
            if badge.earned {
                Text(badge.icon).font(.system(size: 14))
                Text(badge.label).font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundStyle(.white)
            } else {
                Image(systemName: "lock.fill").font(.system(size: 11)).foregroundStyle(.white.opacity(0.4))
                Text(badge.label).font(.system(size: 12, weight: .medium, design: .rounded)).foregroundStyle(.white.opacity(0.4))
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(badge.earned ? Color.kineticsBlue.opacity(0.18) : Color(white: 0.12))
        .clipShape(Capsule())
        .overlay(Capsule().strokeBorder(badge.earned ? Color.kineticsBlue.opacity(0.4) : Color.white.opacity(0.06), lineWidth: 1))
    }
}

// MARK: - ProfileTabSelector

private struct ProfileTabSelector: View {

    @Binding var selectedTab: ProfileTab

    var body: some View {
        HStack(spacing: 0) {
            ForEach(ProfileTab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { selectedTab = tab }
                } label: {
                    Text(tab.rawValue)
                        .font(.system(size: 14, weight: selectedTab == tab ? .bold : .regular, design: .rounded))
                        .foregroundStyle(selectedTab == tab ? .white : Color.kineticsSubtext)
                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                        .background(selectedTab == tab ? Color.kineticsDark : Color.clear)
                }
                .buttonStyle(.plain)
            }
        }
        .background(Color(white: 0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

// MARK: - BioEditOverlay

private struct BioEditOverlay: View {

    @Binding var editBioText: String
    @Binding var isEditing: Bool
    let onSave: () async -> Void

    var body: some View {
        VStack(spacing: 10) {
            TextField("Bio", text: $editBioText, axis: .vertical)
                .font(.system(size: 14)).foregroundStyle(.white).tint(Color.kineticsBlue)
                .padding(.horizontal, 12).padding(.vertical, 10)
                .background(Color.kineticsDark)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .lineLimit(3, reservesSpace: true)
            HStack(spacing: 10) {
                Button { isEditing = false } label: {
                    Text("Cancel").font(.system(size: 14, weight: .medium)).foregroundStyle(Color.kineticsSubtext)
                        .frame(maxWidth: .infinity).padding(.vertical, 9)
                        .background(.white.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
                Button { Task { await onSave() } } label: {
                    Text("Save").font(.system(size: 14, weight: .semibold)).foregroundStyle(Color.kineticsDark)
                        .frame(maxWidth: .infinity).padding(.vertical, 9)
                        .background(Color.kineticsBlue)
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
            }
        }
    }
}

// MARK: - CompactActivityCard

private struct CompactActivityCard: View {

    let item: FeedItem

    private var sportColors: [Color] {
        switch item.activityType {
        case "striking":           return [Color(hex: "#FF6B35"), Color(hex: "#FF3B30")]
        case "grappling":          return [Color(hex: "#5856D6"), Color(hex: "#9B59B6")]
        case "ironTracker", "gym": return [Color(hex: "#FF9F0A"), Color(hex: "#FFD60A")]
        case "wall":               return [Color(hex: "#00BF96"), Color(hex: "#34C759")]
        default:                   return [Color.kineticsBlue, Color(hex: "#30D158")]
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            LinearGradient(colors: sportColors, startPoint: .top, endPoint: .bottom).frame(width: 4)
                .clipShape(.rect(topLeadingRadius: 12, bottomLeadingRadius: 12, bottomTrailingRadius: 0, topTrailingRadius: 0))
            HStack(spacing: 12) {
                Image(systemName: activityIcon(for: item.activityType))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(sportColors.first ?? Color.kineticsBlue)
                    .frame(width: 32, height: 32)
                    .background((sportColors.first ?? Color.kineticsBlue).opacity(0.12)).clipShape(Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                    Text(activityLabel(for: item.activityType)).font(.system(size: 11)).foregroundStyle(Color.kineticsSubtext)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text(item.postedAt.relativeFormatted).font(.system(size: 11)).foregroundStyle(.white.opacity(0.3))
                    if let firstMetric = item.metrics.first {
                        Text("\(firstMetric.value) \(firstMetric.unit)")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(sportColors.first ?? Color.kineticsBlue)
                    }
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 11)
        }
        .background(Color.kineticsDark).clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func activityIcon(for type: String) -> String {
        switch type {
        case "run":                        return "figure.run"
        case "striking":                   return "figure.boxing"
        case "grappling":                  return "figure.martial.arts"
        case "ironTracker", "iron", "gym": return "dumbbell.fill"
        case "wall":                       return "figure.climbing"
        default:                           return "flame.fill"
        }
    }

    private func activityLabel(for type: String) -> String {
        switch type {
        case "run":                        return "Run"
        case "striking":                   return "Striking Clinic"
        case "grappling":                  return "Grappling Lab"
        case "ironTracker", "iron", "gym": return "Iron Tracker"
        case "wall":                       return "Wall Beta"
        default:                           return "Session"
        }
    }
}

// MARK: - KudosButton

struct KudosButton: View {

    let isLiked: Bool
    let count: Int
    let action: () async -> Void

    @State private var isAnimating = false

    var body: some View {
        Button { triggerKudos() } label: {
            HStack(spacing: 5) {
                Image(systemName: isLiked ? "heart.fill" : "heart")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(isLiked ? Color.red : .white.opacity(0.5))
                    .scaleEffect(isAnimating ? 1.35 : 1.0)
                if count > 0 {
                    Text("\(count)").font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(isLiked ? Color.red : .white.opacity(0.5))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.3, dampingFraction: 0.5), value: isAnimating)
    }

    private func triggerKudos() {
        isAnimating = true
        Task { try? await Task.sleep(nanoseconds: 300_000_000); isAnimating = false }
        Task { await action() }
    }
}

// MARK: - CommentSectionView

struct CommentSectionView: View {

    let activityId: String
    var currentUserId: String
    var currentDisplayName: String

    @State private var comments: [ActivityComment] = []
    @State private var newCommentText = ""
    @State private var isLoading = false
    @State private var isPosting = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Comments").font(.system(size: 13, weight: .semibold)).tracking(1.4)
                .foregroundStyle(.white.opacity(0.38)).padding(.horizontal, 16).padding(.vertical, 12)
            Divider().background(.white.opacity(0.06))
            if isLoading {
                ProgressView().tint(Color.kineticsBlue).frame(maxWidth: .infinity).padding(.vertical, 20)
            } else if comments.isEmpty {
                Text("Be the first to comment").font(.system(size: 14)).foregroundStyle(Color.kineticsSubtext)
                    .frame(maxWidth: .infinity).padding(.vertical, 20)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(comments) { comment in
                        CommentRow(comment: comment)
                        Divider().background(.white.opacity(0.05)).padding(.leading, 58)
                    }
                }
            }
            Divider().background(.white.opacity(0.06))
            composeBar
        }
        .background(Color.kineticsDark)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .task { await loadComments() }
    }

    private var composeBar: some View {
        HStack(spacing: 10) {
            ZStack {
                LinearGradient(colors: [Color.kineticsPurple, Color.kineticsBlue], startPoint: .topLeading, endPoint: .bottomTrailing)
                Text(String(currentDisplayName.prefix(1)).uppercased()).font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
            }
            .frame(width: 30, height: 30).clipShape(Circle())
            TextField("Add a comment...", text: $newCommentText)
                .font(.system(size: 14)).foregroundStyle(.white).tint(Color.kineticsBlue)
                .submitLabel(.send).onSubmit { Task { await postComment() } }
            Button { Task { await postComment() } } label: {
                Image(systemName: "paperplane.fill").font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(newCommentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.kineticsSubtext : Color.kineticsBlue)
            }
            .disabled(newCommentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isPosting).buttonStyle(.plain)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
    }

    private func loadComments() async {
        isLoading = true
        do { comments = try await SocialRepository.shared.fetchComments(activityId: activityId) } catch {}
        isLoading = false
    }

    private func postComment() async {
        let trimmed = newCommentText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isPosting else { return }
        isPosting = true
        let newComment = ActivityComment(id: UUID().uuidString, userId: currentUserId, displayName: currentDisplayName, avatarURL: "", text: trimmed, postedAt: Date())
        comments.append(newComment)
        newCommentText = ""
        do { try await SocialRepository.shared.postComment(newComment, activityId: activityId) }
        catch { comments.removeAll { $0.id == newComment.id }; newCommentText = trimmed }
        isPosting = false
    }
}

// MARK: - CommentRow

private struct CommentRow: View {

    let comment: ActivityComment

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Group {
                if comment.avatarURL.isEmpty {
                    ZStack {
                        LinearGradient(colors: [Color.kineticsPurple.opacity(0.7), Color.kineticsBlue.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing)
                        Text(String(comment.displayName.prefix(1)).uppercased()).font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
                    }
                } else {
                    AsyncImage(url: URL(string: comment.avatarURL)) { phase in
                        if case .success(let image) = phase { image.resizable().scaledToFill() }
                        else { Color.kineticsMidGray }
                    }
                }
            }
            .frame(width: 30, height: 30).clipShape(Circle())
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(comment.displayName).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                    Text(comment.postedAt.relativeFormatted).font(.system(size: 11)).foregroundStyle(.white.opacity(0.3))
                }
                Text(comment.text).font(.system(size: 14)).foregroundStyle(.white.opacity(0.85))
                    .lineSpacing(2).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
    }
}

// MARK: - Date Extensions

extension Date {

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

    var monthYear: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM yyyy"
        return formatter.string(from: self)
    }
}
