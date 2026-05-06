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
    var onAvatarTap: (() -> Void)? = nil
    var onSportTap: (() -> Void)? = nil

    @State private var showDeleteConfirm = false
    @State private var heartScale: CGFloat = 1.0
    @State private var floatOffset: CGFloat = 0
    @State private var floatOpacity: Double = 0
    @State private var burstParticles: [BurstParticle] = []
    @State private var showReactionPicker = false

    private static let shortDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 1. Header row (avatar + name + sport badge)
            cardHeader
            // 2. Sport gradient banner strip
            sportBannerStrip
            // 3. Body content with padding
            VStack(alignment: .leading, spacing: 12) {
                // 3a. Caption
                captionBlock
                // 3b. Attached photo (shown above metrics when present)
                photoBlock
                // 3c. Content block (sport-specific)
                contentBlock
                // 3d. Stats row for gym / run
                statsRow
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 4)
            // 4. Divider + Interaction bar
            Divider()
                .background(Color.white.opacity(0.07))
                .padding(.horizontal, 14)
                .padding(.top, 6)
            interactionBar
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
        }
        .background(Color(white: 0.06), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.white.opacity(0.07), lineWidth: 1)
        )
        .shadow(color: primarySportColor.opacity(item.isLikedByCurrentUser ? 0.22 : 0.10), radius: 12, x: 0, y: 4)
        // Burst particles overlay
        .overlay(alignment: .bottomLeading) {
            ZStack {
                ForEach(burstParticles) { p in
                    Circle()
                        .fill(primarySportColor)
                        .frame(width: p.size, height: p.size)
                        .offset(x: p.x, y: p.y)
                        .opacity(p.opacity)
                        .scaleEffect(p.scale)
                }
            }
            .offset(x: 18, y: -44)
        }
        // Floating "+1" kudos indicator
        .overlay(alignment: .bottomLeading) {
            if showFloatingKudos {
                Text("+1")
                    .font(.system(size: 15, weight: .black, design: .rounded))
                    .foregroundStyle(primarySportColor)
                    .offset(x: 62, y: floatOffset)
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

    // MARK: - Card Header

    private var cardHeader: some View {
        HStack(spacing: 10) {
            avatarView
            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayName)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text("@\(item.username)")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(Color.kineticsSubtext)
                    .lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                if let tap = onSportTap {
                    Button(action: tap) { sportBadgePill }
                        .buttonStyle(.plain)
                } else {
                    sportBadgePill
                }
                Text(relativeTimestamp(item.postedAt))
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(Color.kineticsSubtext)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    // MARK: - Avatar

    private var avatarView: some View {
        let core = ZStack {
            // Sport-color ring
            Circle()
                .strokeBorder(
                    LinearGradient(
                        colors: sportGradientColors(for: item.activityType),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 2
                )
                .frame(width: 44, height: 44)

            if !item.avatarURL.isEmpty, let url = URL(string: item.avatarURL) {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    avatarInitialsView
                }
                .frame(width: 40, height: 40)
                .clipShape(Circle())
            } else {
                avatarInitialsView
            }
        }
        return Group {
            if let tap = onAvatarTap {
                Button(action: tap) { core }
                    .buttonStyle(.plain)
            } else {
                core
            }
        }
    }

    private var avatarInitialsView: some View {
        let resolved = resolvedAvatar(for: item.userId, displayName: item.displayName)
        return ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color.kineticsPurple, Color.kineticsBlue.opacity(0.7)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
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
            "demo_001": "🥊", "demo_002": "🏋️", "demo_003": "🏃",
            "demo_004": "🧗", "demo_005": "🤼", "demo_006": "🏋️",
            "demo_007": "🥋", "demo_008": "🏃‍♂️", "demo_009": "🤼‍♂️",
            "demo_010": "🧗‍♂️",
        ]
        if let emoji = emojiMap[userId] {
            return AvatarContent(text: emoji, isEmoji: true)
        }
        return AvatarContent(text: String(displayName.prefix(1).uppercased()), isEmoji: false)
    }

    // MARK: - Sport Badge Pill

    private var sportBadgePill: some View {
        Text(sportBadgeLabel(item.activityType))
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .tracking(0.8)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                LinearGradient(
                    colors: sportGradientColors(for: item.activityType),
                    startPoint: .leading,
                    endPoint: .trailing
                ),
                in: Capsule()
            )
    }

    // MARK: - Sport Banner Strip

    private var sportBannerStrip: some View {
        LinearGradient(
            colors: sportGradientColors(for: item.activityType),
            startPoint: .leading,
            endPoint: .trailing
        )
        .frame(height: 4)
        .drawingGroup()
    }

    // MARK: - Caption

    @ViewBuilder
    private var captionBlock: some View {
        if let caption = item.caption, !caption.isEmpty {
            Text(caption)
                .font(.system(size: 14, weight: .regular, design: .rounded).italic())
                .foregroundStyle(.white.opacity(0.9))
                .lineSpacing(3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 2)
        }
    }

    // MARK: - Photo Block

    @ViewBuilder
    private var photoBlock: some View {
        if !item.imageURL.isEmpty, let url = URL(string: item.imageURL) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity)
                        .frame(height: 220)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                case .failure:
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(white: 0.09))
                            .frame(maxWidth: .infinity)
                            .frame(height: 220)
                        Image(systemName: "photo")
                            .font(.system(size: 28))
                            .foregroundStyle(Color.kineticsSubtext)
                    }
                case .empty:
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(white: 0.09))
                            .frame(maxWidth: .infinity)
                            .frame(height: 220)
                        ProgressView().tint(Color.kineticsBlue)
                    }
                @unknown default:
                    EmptyView()
                }
            }
        }
    }

    // MARK: - Sport-specific Content Block

    @ViewBuilder
    private var contentBlock: some View {
        switch item.activityType {
        case "run", "ride":
            runContent
        case "ironTracker", "gym":
            gymContent
        default:
            // striking, grappling, wall — big metric tiles
            combatMetricGrid
        }
    }

    // MARK: Run / GPS Content

    private var runContent: some View {
        VStack(spacing: 10) {
            if let coords = item.routeCoordinates, coords.count >= 2 {
                FeedRouteMapView(coordinates: coords)
                    .frame(height: 160)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            if !item.metrics.isEmpty {
                HStack(spacing: 6) {
                    ForEach(item.metrics.prefix(3), id: \.label) { m in
                        metricChip(label: m.label, value: m.value, unit: m.unit)
                    }
                }
            }
        }
    }

    private func metricChip(label: String, value: String, unit: String) -> some View {
        VStack(spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                if !unit.isEmpty {
                    Text(unit)
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.kineticsSubtext)
                }
            }
            Text(label)
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.kineticsSubtext)
                .tracking(0.5)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color(white: 0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: Gym / Iron Content

    @ViewBuilder
    private var gymContent: some View {
        if let summaries = item.exerciseSummaries, !summaries.isEmpty {
            VStack(spacing: 0) {
                ForEach(Array(summaries.prefix(4).enumerated()), id: \.offset) { index, exercise in
                    HStack(spacing: 10) {
                        Circle()
                            .fill(muscleGroupColor(exercise.muscleGroup))
                            .frame(width: 7, height: 7)
                        Text(exercise.name)
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.9))
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        Text("\(exercise.sets)x @ \(formattedWeight(exercise.topWeightKg))")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color.kineticsAmber)
                    }
                    .padding(.vertical, 7)
                    .padding(.horizontal, 12)
                    if index < min(summaries.prefix(4).count, 4) - 1 {
                        Divider()
                            .background(Color.white.opacity(0.05))
                            .padding(.leading, 29)
                    }
                }
                if summaries.count > 4 {
                    HStack {
                        Spacer()
                        Text("+ \(summaries.count - 4) more")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(Color.kineticsSubtext)
                            .padding(.vertical, 6)
                            .padding(.horizontal, 12)
                    }
                }
            }
            .background(Color(white: 0.09), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
            )
        }
    }

    // MARK: Combat / Climbing Metric Grid

    @ViewBuilder
    private var combatMetricGrid: some View {
        let displayMetrics = Array(item.metrics.prefix(4))
        if !displayMetrics.isEmpty {
            let columns = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(displayMetrics, id: \.label) { metric in
                    bigMetricTile(metric: metric)
                }
            }
        }
    }

    private func bigMetricTile(metric: FeedMetric) -> some View {
        VStack(spacing: 4) {
            Text(metric.label.uppercased())
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.kineticsSubtext)
                .tracking(0.8)
                .lineLimit(1)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(metric.value)
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                if !metric.unit.isEmpty {
                    Text(metric.unit)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(primarySportColor.opacity(0.9))
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(
            LinearGradient(
                colors: [Color(white: 0.10), Color(white: 0.08)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(primarySportColor.opacity(0.18), lineWidth: 1)
        )
    }

    // MARK: - Stats Row (gym + run)

    @ViewBuilder
    private var statsRow: some View {
        let displayMetrics = Array(item.metrics.prefix(3))
        switch item.activityType {
        case "ironTracker", "gym":
            if !displayMetrics.isEmpty {
                HStack(spacing: 0) {
                    ForEach(displayMetrics.indices, id: \.self) { index in
                        FeedMetricCell(metric: displayMetrics[index])
                        if index < displayMetrics.count - 1 {
                            Rectangle()
                                .fill(Color.white.opacity(0.10))
                                .frame(width: 1, height: 28)
                        }
                    }
                }
                .padding(.vertical, 6)
                .background(Color.kineticsBackground.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
            }
        default:
            EmptyView()
        }
    }

    // MARK: - Interaction Bar

    private var interactionBar: some View {
        ZStack(alignment: .bottomLeading) {
            HStack(spacing: 22) {
                // Kudos / heart button with long-press reaction picker
                Button {
                    triggerKudosAnimation()
                    Task { await onKudos() }
                } label: {
                    HStack(spacing: 5) {
                        reactionLeadingEmoji
                            .scaleEffect(heartScale)
                        if item.kudosCount > 0 {
                            Text("\(item.kudosCount)")
                                .font(.system(.footnote, design: .rounded, weight: .semibold))
                                .foregroundStyle(item.isLikedByCurrentUser ? Color.kineticsRed : Color.kineticsSubtext)
                                .contentTransition(.numericText())
                        }
                    }
                }
                .buttonStyle(.plain)
                .simultaneousGesture(
                    LongPressGesture(minimumDuration: 0.4)
                        .onEnded { _ in
                            let generator = UIImpactFeedbackGenerator(style: .heavy)
                            generator.impactOccurred()
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.65)) {
                                showReactionPicker = true
                            }
                        }
                )

            // Comment button
            Button { onComment() } label: {
                HStack(spacing: 5) {
                    Image(systemName: "bubble.left")
                        .font(.system(size: 16, weight: .medium))
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
                Image(systemName: "arrow.up.circle")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Color.kineticsSubtext)
            }
            .buttonStyle(.plain)
            } // end HStack
            .contentShape(Rectangle())
            .onTapGesture {
                if showReactionPicker {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                        showReactionPicker = false
                    }
                }
            }

            if showReactionPicker {
                ReactionPickerView { reaction in
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                        showReactionPicker = false
                    }
                    triggerKudosAnimation()
                    Task {
                        try? await SocialRepository.shared.addReaction(
                            reaction.rawValue,
                            to: item.id,
                            userId: currentUserId
                        )
                        await onKudos()
                    }
                }
                .offset(x: 0, y: -52)
                .transition(.scale(scale: 0.7, anchor: .bottomLeading).combined(with: .opacity))
                .zIndex(10)
            }
        } // end ZStack
    }

    // MARK: - Reaction Leading Emoji

    @ViewBuilder
    private var reactionLeadingEmoji: some View {
        let dominantReaction = item.reactions.max(by: { $0.value < $1.value })?.key
        if let type = dominantReaction.flatMap({ ReactionType(rawValue: $0) }), item.isLikedByCurrentUser {
            Text(type.emoji)
                .font(.system(size: 17))
        } else {
            Image(systemName: item.isLikedByCurrentUser ? "heart.fill" : "heart")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(item.isLikedByCurrentUser ? Color.kineticsRed : Color.kineticsSubtext)
        }
    }

    // MARK: - Kudos Animation

    private func triggerKudosAnimation() {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()

        // Spring bounce on the heart icon
        withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
            heartScale = 1.4
        }
        Task {
            try? await Task.sleep(for: .seconds(0.3))
            await MainActor.run {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                    heartScale = 1.0
                }
            }
        }

        // Burst particles: 4 circles that scale out and fade
        burstParticles = (0..<4).map { i in
            let angle = Double(i) / 4.0 * .pi * 2
            return BurstParticle(
                id: UUID(),
                x: cos(angle) * 4,
                y: sin(angle) * 4,
                opacity: 1,
                scale: 1,
                size: CGFloat.random(in: 5...9)
            )
        }
        withAnimation(.easeOut(duration: 0.55)) {
            burstParticles = burstParticles.map { p in
                let angle = atan2(p.y, p.x)
                return BurstParticle(
                    id: p.id,
                    x: cos(angle) * 22,
                    y: sin(angle) * 22,
                    opacity: 0,
                    scale: 0.3,
                    size: p.size
                )
            }
        }
        Task {
            try? await Task.sleep(for: .seconds(0.6))
            await MainActor.run {
                burstParticles = []
            }
        }
    }

    // MARK: - Color + Label Helpers

    private var primarySportColor: Color {
        sportColor(for: item.activityType)
    }

    private func sportColor(for type: String) -> Color {
        switch type.lowercased() {
        case "iron", "irontracker", "gym": return Color.kineticsBlue
        case "run":                         return Color.kineticsGreen
        case "striking":                    return Color(red: 1, green: 0.5, blue: 0.1)
        case "grappling":                   return Color.kineticsPurple
        case "wall":                        return Color(red: 0.1, green: 0.9, blue: 0.8)
        default:                            return Color.kineticsBlue
        }
    }

    private func sportGradientColors(for type: String) -> [Color] {
        switch type.lowercased() {
        case "iron", "irontracker", "gym":  return [Color.kineticsBlue, Color(hex: "#5856D6")]
        case "run":                          return [Color.kineticsGreen, Color(hex: "#00BF96")]
        case "striking":                     return [Color(hex: "#FF8C00"), Color(hex: "#FF3B30")]
        case "grappling":                    return [Color.kineticsPurple, Color(hex: "#D946EF")]
        case "wall":                         return [Color(hex: "#00BF96"), Color.kineticsBlue]
        default:                             return [Color.kineticsBlue, Color.kineticsGreen]
        }
    }

    private func sportBadgeLabel(_ type: String) -> String {
        switch type.lowercased() {
        case "iron", "irontracker", "gym":  return "IRON"
        case "run":                          return "RUN"
        case "ride":                         return "RIDE"
        case "striking":                     return "STRIKING"
        case "grappling":                    return "GRAPPLING"
        case "wall":                         return "WALL"
        default:                             return "SESSION"
        }
    }

    private func muscleGroupColor(_ group: String) -> Color {
        switch group.lowercased() {
        case "chest":                          return Color.kineticsBlue
        case "back":                           return Color.kineticsPurple
        case "legs", "glutes":                 return Color.kineticsGreen
        case "shoulders":                      return Color.kineticsAmber
        case "arms", "biceps", "triceps":      return Color(hex: "#FF6B35")
        case "core":                           return Color.kineticsRed
        default:                               return Color.kineticsSubtext
        }
    }

    private func formattedWeight(_ kg: Double) -> String {
        if kg == kg.rounded() { return "\(Int(kg))kg" }
        return String(format: "%.1fkg", kg)
    }

    private func relativeTimestamp(_ date: Date) -> String {
        let seconds = Int(Date.now.timeIntervalSince(date))
        switch seconds {
        case ..<30:         return "Just now"
        case 30..<3_600:    return "\(seconds / 60)m"
        case 3_600..<86_400:
            let h = seconds / 3_600
            return "\(h)h"
        case 86_400..<172_800: return "Yesterday"
        case 172_800..<604_800:
            return "\(seconds / 86_400)d"
        default:
            return Self.shortDateFormatter.string(from: date)
        }
    }
}

// MARK: - BurstParticle

private struct BurstParticle: Identifiable {
    let id: UUID
    var x: CGFloat
    var y: CGFloat
    var opacity: Double
    var scale: CGFloat
    let size: CGFloat
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

// MARK: - StoryFullScreenView

struct StoryFullScreenView: View {

    let story: StoryModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            LinearGradient(
                colors: sportGradient(for: story.sport),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            VStack(spacing: 20) {
                Spacer()
                Text(story.avatarEmoji).font(.system(size: 72))
                VStack(spacing: 8) {
                    Text(story.displayName)
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text(story.sport.capitalized + " Session")
                        .font(.system(size: 16, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.8))
                }
                VStack(spacing: 12) {
                    HStack {
                        Image(systemName: activityIcon(for: story.sport))
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                        Text("Recent Session")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                        Spacer()
                        Text(story.createdAt.relativeFormatted)
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    Divider().background(.white.opacity(0.2))
                    Text("Training hard, making progress \u{1F4AA}")
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.9))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(16)
                .background(.white.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .padding(.horizontal, 32)
                Spacer()
            }
            VStack {
                HStack {
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    .padding(.trailing, 20)
                    .padding(.top, 20)
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
