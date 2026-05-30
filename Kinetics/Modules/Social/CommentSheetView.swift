import SwiftUI

// MARK: - ReactionType

enum ReactionType: String, CaseIterable, Sendable {
    case strong = "strong"
    case fire = "fire"
    case pr = "pr"
    case beast = "beast"
    case love = "love"

    var emoji: String {
        switch self {
        case .strong: return "💪"
        case .fire:   return "🔥"
        case .pr:     return "🏆"
        case .beast:  return "😤"
        case .love:   return "❤️"
        }
    }

    var label: String {
        switch self {
        case .strong: return "Strong"
        case .fire:   return "Fire"
        case .pr:     return "PR"
        case .beast:  return "Beast"
        case .love:   return "Love"
        }
    }
}

// MARK: - CommentSheetView

struct CommentSheetView: View {

    let item: FeedItem
    let currentUserId: String
    let currentDisplayName: String
    let currentUsername: String

    @Environment(\.dismiss) private var dismiss
    @State private var comments: [ActivityComment] = []
    @State private var isLoading = false
    @State private var isPosting = false
    @State private var draftText = ""
    @FocusState private var textFieldFocused: Bool

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.kineticsBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                sheetHeader
                Divider().background(Color.white.opacity(0.07))
                commentsList
            }

            composeBar
                .background(
                    Color.kineticsDark
                        .ignoresSafeArea(edges: .bottom)
                )
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .task { await loadComments() }
    }

    // MARK: - Header

    private var sheetHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Comments")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text("\(comments.count) comment\(comments.count == 1 ? "" : "s")")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.kineticsSubtext)
            }
            Spacer()
            Button { dismiss() } label: {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.08))
                        .frame(width: 30, height: 30)
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.kineticsSubtext)
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    // MARK: - Comments List

    private var commentsList: some View {
        ScrollView {
            if isLoading {
                ProgressView()
                    .tint(Color.kineticsBlue)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
            } else if comments.isEmpty {
                emptyState
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(comments) { comment in
                        SheetCommentRow(
                            comment: comment,
                            isOwnComment: comment.userId == currentUserId,
                            activityId: item.id,
                            onDelete: {
                                comments.removeAll { $0.id == comment.id }
                            }
                        )
                        Divider()
                            .background(Color.white.opacity(0.05))
                            .padding(.leading, 54)
                    }
                }
                .padding(.bottom, 80)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Text("💬")
                .font(.system(size: 40))
            Text("Be the first to comment")
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(Color.kineticsSubtext)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }

    // MARK: - Compose Bar

    private var composeBar: some View {
        HStack(spacing: 10) {
            ZStack {
                LinearGradient(
                    colors: [Color.kineticsPurple, Color.kineticsBlue],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Text(String(currentDisplayName.prefix(1)).uppercased())
                    .font(.system(size: 13, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
            }
            .frame(width: 32, height: 32)
            .clipShape(Circle())

            TextField("Add a comment...", text: $draftText, axis: .vertical)
                .font(.system(size: 14))
                .foregroundStyle(.white)
                .tint(Color.kineticsBlue)
                .lineLimit(4)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(Color.white.opacity(0.07))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .focused($textFieldFocused)
                .submitLabel(.send)
                .onSubmit { Task { await postComment() } }

            Button {
                Task { await postComment() }
            } label: {
                ZStack {
                    Circle()
                        .fill(sendEnabled ? Color.kineticsBlue : Color.white.opacity(0.07))
                        .frame(width: 34, height: 34)
                    Image(systemName: "arrow.up")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(sendEnabled ? Color.kineticsDark : Color.kineticsSubtext)
                }
            }
            .buttonStyle(.plain)
            .disabled(!sendEnabled)
            .animation(.easeInOut(duration: 0.15), value: sendEnabled)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .overlay(alignment: .top) {
            Divider().background(Color.white.opacity(0.07))
        }
    }

    private var sendEnabled: Bool {
        !draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isPosting
    }

    // MARK: - Actions

    private func loadComments() async {
        isLoading = true
        do {
            comments = try await SocialRepository.shared.fetchComments(activityId: item.id)
        } catch {}
        isLoading = false
    }

    private func postComment() async {
        let trimmed = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isPosting else { return }
        isPosting = true
        let optimistic = ActivityComment(
            id: UUID().uuidString,
            userId: currentUserId,
            displayName: currentDisplayName,
            avatarURL: "",
            text: trimmed,
            postedAt: Date()
        )
        comments.append(optimistic)
        draftText = ""
        textFieldFocused = false
        do {
            try await SocialRepository.shared.postComment(optimistic, activityId: item.id)
        } catch {
            comments.removeAll { $0.id == optimistic.id }
            draftText = trimmed
        }
        isPosting = false
    }
}

// MARK: - SheetCommentRow

private struct SheetCommentRow: View {

    let comment: ActivityComment
    let isOwnComment: Bool
    let activityId: String
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            avatarView
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(comment.displayName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(comment.postedAt.commentTimeAgo)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.kineticsSubtext)
                }
                Text(comment.text)
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contextMenu {
            Button {
                UIPasteboard.general.string = comment.text
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
            Button(role: .destructive) {
                Task {
                    try? await SocialRepository.shared.reportContent(
                        type: "comment",
                        contentId: comment.id,
                        parentId: activityId
                    )
                }
            } label: {
                Label("Report", systemImage: "flag")
            }
            if isOwnComment {
                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
    }

    private var avatarView: some View {
        Group {
            if comment.avatarURL.isEmpty {
                ZStack {
                    LinearGradient(
                        colors: [Color.kineticsPurple.opacity(0.7), Color.kineticsBlue.opacity(0.7)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    Text(String(comment.displayName.prefix(1)).uppercased())
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                }
            } else {
                AsyncImage(url: URL(string: comment.avatarURL)) { phase in
                    if case .success(let img) = phase {
                        img.resizable().scaledToFill()
                    } else {
                        Color.kineticsMidGray
                    }
                }
            }
        }
        .frame(width: 36, height: 36)
        .clipShape(Circle())
    }
}

// MARK: - Date + commentTimeAgo

private extension Date {
    var commentTimeAgo: String {
        let seconds = Int(-timeIntervalSinceNow)
        switch seconds {
        case 0 ..< 60:   return "just now"
        case 60 ..< 3600:  return "\(seconds / 60)m ago"
        case 3600 ..< 86400: return "\(seconds / 3600)h ago"
        default:           return "\(seconds / 86400)d ago"
        }
    }
}

// MARK: - ReactionPickerView

struct ReactionPickerView: View {

    let onSelect: (ReactionType) -> Void

    var body: some View {
        HStack(spacing: 4) {
            ForEach(ReactionType.allCases, id: \.self) { reaction in
                Button {
                    onSelect(reaction)
                } label: {
                    Text(reaction.emoji)
                        .font(.system(size: 26))
                        .padding(8)
                        .contentShape(Rectangle())
                }
                .buttonStyle(ReactionButtonStyle())
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.kineticsDark)
                .shadow(color: .black.opacity(0.45), radius: 12, x: 0, y: 4)
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }
}

// MARK: - ReactionButtonStyle

private struct ReactionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 1.35 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.55), value: configuration.isPressed)
    }
}
