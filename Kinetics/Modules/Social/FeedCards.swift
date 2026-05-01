import MapKit
import SwiftUI

// MARK: - ActivityFeedCard

struct ActivityFeedCard: View {

    let item: FeedItem
    let currentUserId: String
    var showFloatingKudos: Bool = false
    let onKudos: () async -> Void
    let onComment: () -> Void
    var onDelete: (() async -> Void)? = nil

    @State private var showDeleteConfirm = false
    @State private var heartScale: CGFloat = 1.0
    @State private var floatOffset: CGFloat = 0
    @State private var floatOpacity: Double = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            sportHeaderBand
            VStack(alignment: .leading, spacing: 14) {
                headerRow
                titleBlock
                metricsRow
                captionBlock
                exerciseList
                routeMap
                Divider().background(Color.white.opacity(0.07))
                actionRow
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 14)
        }
        .background(Color(white: 0.07), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.white.opacity(0.06), lineWidth: 1))
        .overlay(alignment: .bottomLeading) {
            if showFloatingKudos {
                Text("+1")
                    .font(.system(size: 15, weight: .black, design: .rounded))
                    .foregroundStyle(Color.red)
                    .offset(x: 60, y: floatOffset)
                    .opacity(floatOpacity)
                    .onAppear {
                        floatOffset = 0
                        floatOpacity = 1
                        withAnimation(.easeOut(duration: 0.8)) {
                            floatOffset = -50
                            floatOpacity = 0
                        }
                    }
            }
        }
        .contextMenu {
            if onDelete != nil {
                Button(role: .destructive) { showDeleteConfirm = true } label: {
                    Label("Delete Post", systemImage: "trash")
                }
            }
        }
        .confirmationDialog("Delete this post?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { Task { await onDelete?() } }
            Button("Cancel", role: .cancel) {}
        } message: { Text("This can't be undone.") }
    }

    // MARK: Sport Header Band

    private var sportHeaderBand: some View {
        LinearGradient(colors: sportGradientColors(for: item.activityType), startPoint: .leading, endPoint: .trailing)
            .frame(height: 40)
            .clipShape(.rect(topLeadingRadius: 16, bottomLeadingRadius: 0, bottomTrailingRadius: 0, topTrailingRadius: 16))
            .overlay(alignment: .leading) {
                HStack(spacing: 8) {
                    Image(systemName: activityIcon(item.activityType))
                        .font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                    Text(activityLabel(item.activityType))
                        .font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundStyle(.white)
                }
                .padding(.leading, 14)
            }
    }

    // MARK: Header Row

    private var headerRow: some View {
        HStack(spacing: 10) {
            avatarView
            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayName)
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                    .foregroundStyle(.white).lineLimit(1)
                Text("@\(item.username)").font(.caption).foregroundStyle(Color.kineticsSubtext).lineLimit(1)
            }
            Spacer()
            Text(timeAgo(item.postedAt)).font(.caption2).foregroundStyle(Color.kineticsSubtext)
        }
    }

    private var avatarView: some View {
        ZStack {
            if !item.avatarURL.isEmpty, let url = URL(string: item.avatarURL) {
                AsyncImage(url: url) { image in image.resizable().scaledToFill() }
                    placeholder: { defaultAvatar }
                    .frame(width: 40, height: 40).clipShape(Circle())
            } else {
                defaultAvatar
            }
        }
    }

    /// Shows a sport emoji for known demo users; falls back to an initials circle.
    private var defaultAvatar: some View {
        let resolved = resolvedAvatar(for: item.userId, displayName: item.displayName)
        return ZStack {
            Circle()
                .fill(LinearGradient(
                    colors: [Color.kineticsPurple, Color.kineticsBlue.opacity(0.7)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ))
                .frame(width: 40, height: 40)
            if resolved.isEmoji {
                Text(resolved.text).font(.system(size: 20))
            } else {
                Text(resolved.text)
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
    }

    private struct AvatarContent {
        let text: String
        let isEmoji: Bool
    }

    private func resolvedAvatar(for userId: String, displayName: String) -> AvatarContent {
        let emojiMap: [String: String] = [
            "demo_001": "🥊",
            "demo_002": "🏋️",
            "demo_003": "🏃",
            "demo_004": "🧗",
            "demo_005": "🤼",
            "demo_006": "🏋️",
            "demo_007": "🥋",
            "demo_008": "🏃‍♂️",
            "demo_009": "🤼‍♂️",
            "demo_010": "🧗‍♂️",
        ]
        if let emoji = emojiMap[userId] {
            return AvatarContent(text: emoji, isEmoji: true)
        }
        return AvatarContent(text: String(displayName.prefix(1).uppercased()), isEmoji: false)
    }

    // MARK: Title Block

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.title).font(.system(.callout, design: .rounded, weight: .bold)).foregroundStyle(.white).lineLimit(2)
            if !item.subtitle.isEmpty {
                Text(item.subtitle).font(.caption).foregroundStyle(Color.kineticsSubtext).lineLimit(1)
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
                        Divider().frame(height: 28).background(Color.white.opacity(0.1))
                    }
                }
            }
            .padding(.vertical, 10)
            .background(Color.kineticsBackground.opacity(0.6), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    // MARK: Caption Block

    @ViewBuilder
    private var captionBlock: some View {
        if let caption = item.caption, !caption.isEmpty {
            Text(caption)
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.88))
                .lineSpacing(3)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Exercise List

    @ViewBuilder
    private var exerciseList: some View {
        if let summaries = item.exerciseSummaries, !summaries.isEmpty {
            VStack(spacing: 0) {
                ForEach(Array(summaries.prefix(4).enumerated()), id: \.offset) { index, exercise in
                    HStack(spacing: 10) {
                        Circle()
                            .fill(muscleGroupColor(exercise.muscleGroup))
                            .frame(width: 7, height: 7)
                        Text(exercise.name)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.88))
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        Text("\(exercise.sets)x @ \(formattedWeight(exercise.topWeightKg))")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color.kineticsAmber)
                    }
                    .padding(.vertical, 5)
                    .padding(.horizontal, 12)
                    if index < min(summaries.prefix(4).count, 4) - 1 {
                        Divider().background(Color.white.opacity(0.05)).padding(.leading, 29)
                    }
                }
                if summaries.count > 4 {
                    HStack {
                        Spacer()
                        Text("+ \(summaries.count - 4) more")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(Color.kineticsSubtext)
                            .padding(.vertical, 5)
                            .padding(.horizontal, 12)
                    }
                }
            }
            .background(Color(white: 0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 1))
        }
    }

    // MARK: Route Map

    @ViewBuilder
    private var routeMap: some View {
        if let coords = item.routeCoordinates, coords.count >= 2 {
            FeedRouteMapView(coordinates: coords)
                .frame(height: 130)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    // MARK: Action Row

    private var actionRow: some View {
        HStack(spacing: 20) {
            Button {
                let generator = UIImpactFeedbackGenerator(style: .medium)
                generator.impactOccurred()
                withAnimation(.spring(response: 0.25, dampingFraction: 0.4)) { heartScale = 1.4 }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.6)) { heartScale = 1.0 }
                }
                Task { await onKudos() }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: item.isLikedByCurrentUser ? "heart.fill" : "heart")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(item.isLikedByCurrentUser ? Color.red : Color.kineticsSubtext)
                        .scaleEffect(heartScale)
                    if item.kudosCount > 0 {
                        Text("\(item.kudosCount)")
                            .font(.system(.footnote, design: .rounded, weight: .semibold))
                            .foregroundStyle(item.isLikedByCurrentUser ? Color.red : Color.kineticsSubtext)
                            .contentTransition(.numericText())
                    }
                }
            }
            .buttonStyle(.plain)

            Button { onComment() } label: {
                HStack(spacing: 5) {
                    Image(systemName: "bubble.left").font(.system(size: 15, weight: .medium)).foregroundStyle(Color.kineticsSubtext)
                    if item.commentCount > 0 {
                        Text("\(item.commentCount)")
                            .font(.system(.footnote, design: .rounded, weight: .semibold))
                            .foregroundStyle(Color.kineticsSubtext)
                    }
                }
            }
            .buttonStyle(.plain)

            Spacer()

            Button {
                let shareText = "\(item.displayName) on Kinetics: \(item.title)\n\(item.subtitle)"
                let activityVC = UIActivityViewController(
                    activityItems: [shareText],
                    applicationActivities: nil
                )
                if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                   let rootVC = windowScene.windows.first?.rootViewController {
                    var presented = rootVC
                    while let next = presented.presentedViewController { presented = next }
                    presented.present(activityVC, animated: true)
                }
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.kineticsSubtext)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Helpers

    private func sportGradientColors(for type: String) -> [Color] {
        switch type {
        case "striking":           return [Color(hex: "#FF6B35"), Color(hex: "#FF3B30")]
        case "grappling":          return [Color(hex: "#5856D6"), Color(hex: "#9B59B6")]
        case "ironTracker", "gym": return [Color(hex: "#FF9F0A"), Color(hex: "#FFD60A")]
        case "wall":               return [Color(hex: "#00BF96"), Color(hex: "#34C759")]
        default:                   return [Color.kineticsBlue, Color(hex: "#30D158")]
        }
    }

    private func activityLabel(_ type: String) -> String {
        switch type {
        case "striking":           return "Striking Clinic"
        case "grappling":          return "Grappling Lab"
        case "ironTracker", "gym": return "Iron Tracker"
        case "wall":               return "Wall Beta"
        case "run":                return "Run"
        case "ride":               return "Ride"
        default:                   return "Session"
        }
    }

    private func activityIcon(_ type: String) -> String {
        switch type {
        case "run":                return "figure.run"
        case "ride":               return "bicycle"
        case "striking":           return "figure.boxing"
        case "grappling":          return "figure.martial.arts"
        case "ironTracker", "gym": return "dumbbell.fill"
        case "wall":               return "figure.climbing"
        default:                   return "bolt.fill"
        }
    }

    private func muscleGroupColor(_ group: String) -> Color {
        switch group.lowercased() {
        case "chest":           return Color.kineticsBlue
        case "back":            return Color.kineticsPurple
        case "legs", "glutes":  return Color.kineticsGreen
        case "shoulders":       return Color.kineticsAmber
        case "arms", "biceps", "triceps": return Color(hex: "#FF6B35")
        case "core":            return Color.kineticsRed
        default:                return Color.kineticsSubtext
        }
    }

    private func formattedWeight(_ kg: Double) -> String {
        if kg == kg.rounded() {
            return "\(Int(kg))kg"
        }
        return String(format: "%.1fkg", kg)
    }

    private func timeAgo(_ date: Date) -> String {
        let seconds = Int(Date.now.timeIntervalSince(date))
        switch seconds {
        case ..<60:            return "now"
        case 60..<3_600:       return "\(seconds / 60) mins ago"
        case 3_600..<86_400:
            let h = seconds / 3_600
            return h == 1 ? "1 hour ago" : "\(h) hours ago"
        case 86_400..<172_800: return "Yesterday"
        default:               return "\(seconds / 86_400)d ago"
        }
    }
}

// MARK: - FeedRouteMapView

/// A non-interactive satellite map that draws a `MapPolyline` for a GPS route.
/// Coordinates are `[[lat, lng]]` pairs matching the `FeedItem.routeCoordinates` format.
private struct FeedRouteMapView: View {

    let coordinates: [[Double]]

    private var clCoordinates: [CLLocationCoordinate2D] {
        coordinates.compactMap { pair in
            guard pair.count == 2 else { return nil }
            return CLLocationCoordinate2D(latitude: pair[0], longitude: pair[1])
        }
    }

    private var region: MKCoordinateRegion {
        guard !clCoordinates.isEmpty else {
            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 0, longitude: 0),
                span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
            )
        }
        let lats = clCoordinates.map(\.latitude)
        let lngs = clCoordinates.map(\.longitude)
        let minLat = lats.min() ?? 0
        let maxLat = lats.max() ?? 0
        let minLng = lngs.min() ?? 0
        let maxLng = lngs.max() ?? 0
        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLng + maxLng) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta: max((maxLat - minLat) * 1.35, 0.003),
            longitudeDelta: max((maxLng - minLng) * 1.35, 0.003)
        )
        return MKCoordinateRegion(center: center, span: span)
    }

    var body: some View {
        Map(initialPosition: .region(region)) {
            MapPolyline(coordinates: clCoordinates)
                .stroke(Color.kineticsBlue, lineWidth: 3)
        }
        .mapStyle(.imagery(elevation: .realistic))
        .disabled(true)
    }
}

// MARK: - FeedMetricCell

struct FeedMetricCell: View {

    let metric: FeedMetric

    var body: some View {
        VStack(spacing: 3) {
            Text(metric.label.uppercased())
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.kineticsSubtext).tracking(0.6).lineLimit(1)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(metric.value)
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                    .foregroundStyle(.white).lineLimit(1)
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

// MARK: - StoryFullScreenView

struct StoryFullScreenView: View {

    let story: StoryModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            LinearGradient(colors: sportGradient(for: story.sport), startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()
            VStack(spacing: 20) {
                Spacer()
                Text(story.avatarEmoji).font(.system(size: 72))
                VStack(spacing: 8) {
                    Text(story.displayName)
                        .font(.system(size: 26, weight: .bold, design: .rounded)).foregroundStyle(.white)
                    Text(story.sport.capitalized + " Session")
                        .font(.system(size: 16, weight: .medium, design: .rounded)).foregroundStyle(.white.opacity(0.8))
                }
                VStack(spacing: 12) {
                    HStack {
                        Image(systemName: activityIcon(for: story.sport)).font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
                        Text("Recent Session").font(.system(size: 15, weight: .semibold, design: .rounded)).foregroundStyle(.white)
                        Spacer()
                        Text(story.createdAt.relativeFormatted).font(.system(size: 12)).foregroundStyle(.white.opacity(0.7))
                    }
                    Divider().background(.white.opacity(0.2))
                    Text("Training hard, making progress \u{1F4AA}")
                        .font(.system(size: 14)).foregroundStyle(.white.opacity(0.9)).frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(16).background(.white.opacity(0.15)).clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .padding(.horizontal, 32)
                Spacer()
            }
            VStack {
                HStack {
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 28)).foregroundStyle(.white.opacity(0.8))
                    }
                    .padding(.trailing, 20).padding(.top, 20)
                }
                Spacer()
            }
        }
    }

    private func activityIcon(for sport: String) -> String {
        switch sport {
        case "striking":            return "figure.boxing"
        case "grappling":           return "figure.martial.arts"
        case "iron", "ironTracker": return "dumbbell.fill"
        case "wall":                return "figure.climbing"
        case "run":                 return "figure.run"
        default:                    return "bolt.fill"
        }
    }

    private func sportGradient(for sport: String) -> [Color] {
        switch sport {
        case "striking":            return [Color(hex: "#FF6B35"), Color(hex: "#FF3B30")]
        case "grappling":           return [Color(hex: "#5856D6"), Color(hex: "#9B59B6")]
        case "iron", "ironTracker": return [Color(hex: "#FF9F0A"), Color(hex: "#FFD60A")]
        case "wall":                return [Color(hex: "#00BF96"), Color(hex: "#34C759")]
        default:                    return [Color.kineticsBlue, Color(hex: "#30D158")]
        }
    }
}
