import MapKit
import PhotosUI
import SwiftUI

// MARK: - PostComposerActivity

/// Describes the session data that can be attached to a new post.
/// Pass this when launching the composer from a completed session.
struct PostComposerActivity: Sendable {

    // MARK: Kind

    enum Kind: Sendable {
        case gym(exercises: [ExerciseSummary], totalVolume: Double, durationMinutes: Int)
        case gps(distanceKm: Double, durationSeconds: TimeInterval,
                 avgPaceSecPerKm: Double, coordinates: [[Double]])
        case sport(type: String, metrics: [FeedMetric])
    }

    var kind: Kind
    var sessionTitle: String
}

// MARK: - PostComposerViewModel

@Observable
@MainActor
final class PostComposerViewModel {

    // MARK: State

    var caption: String = ""
    var isPosting = false
    var errorMessage: String?
    var selectedPhotoItem: PhotosPickerItem?
    var selectedImageData: Data?
    var isPublic = true

    // MARK: Derived

    var captionCount: Int { caption.count }
    var captionCountColor: Color {
        switch captionCount {
        case ..<240:   return Color.kineticsSubtext
        case 240..<280: return Color.kineticsAmber
        default:       return Color.kineticsRed
        }
    }
    var canPost: Bool { !isPosting }

    // MARK: Post

    func post(
        activity: PostComposerActivity?,
        userId: String,
        displayName: String,
        username: String
    ) async throws {
        isPosting = true
        defer { isPosting = false }

        var metrics: [FeedMetric] = []
        var exerciseSummaries: [ExerciseSummary]?
        var routeCoordinates: [[Double]]?
        var itemType: FeedItemType = .workout
        var title = caption.isEmpty ? "New Activity" : String(caption.prefix(60))
        var subtitle = ""
        var activityType = "general"

        if let activity {
            switch activity.kind {
            case let .gym(exercises, totalVolume, duration):
                itemType = .gymSession
                activityType = "iron"
                exerciseSummaries = exercises
                title = activity.sessionTitle.isEmpty ? "Gym Session" : activity.sessionTitle
                subtitle = "\(exercises.count) exercises · \(Int(totalVolume))kg volume · \(duration)min"
                metrics = [
                    FeedMetric(label: "VOLUME", value: "\(Int(totalVolume))", unit: "kg"),
                    FeedMetric(label: "EXERCISES", value: "\(exercises.count)", unit: ""),
                    FeedMetric(label: "TIME", value: "\(duration)", unit: "min")
                ]
            case let .gps(distKm, duration, pace, coords):
                itemType = .workout
                activityType = "run"
                routeCoordinates = coords
                let paceMin = Int(pace) / 60
                let paceSec = Int(pace) % 60
                let paceStr = "\(paceMin):\(String(format: "%02d", paceSec))"
                title = activity.sessionTitle.isEmpty
                    ? "Run · \(String(format: "%.1f", distKm)) km"
                    : activity.sessionTitle
                subtitle = "\(formatDuration(duration)) · \(paceStr)/km"
                metrics = [
                    FeedMetric(label: "DIST", value: String(format: "%.1f", distKm), unit: "km"),
                    FeedMetric(label: "TIME", value: formatDuration(duration), unit: ""),
                    FeedMetric(label: "PACE", value: paceStr, unit: "/km")
                ]
            case let .sport(type, sportMetrics):
                activityType = type
                itemType = {
                    switch type {
                    case "striking":  return .strikeSession
                    case "grappling": return .grapplingSession
                    case "wall":      return .wallSession
                    default:          return .workout
                    }
                }()
                title = activity.sessionTitle
                metrics = sportMetrics
            }
        }

        let item = FeedItem(
            userId: userId,
            displayName: displayName,
            username: username,
            avatarURL: "",
            itemType: itemType,
            title: title,
            subtitle: subtitle,
            caption: caption.isEmpty ? nil : caption,
            metrics: metrics,
            exerciseSummaries: exerciseSummaries,
            routeCoordinates: routeCoordinates,
            imageURL: "",
            postedAt: Date(),
            kudosCount: 0,
            commentCount: 0,
            isLikedByCurrentUser: false,
            workoutId: "",
            activityType: activityType
        )

        try await SocialRepository.shared.post(item: item)
    }

    // MARK: Private

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let m = total / 60
        let s = total % 60
        if m >= 60 {
            return "\(m / 60):\(String(format: "%02d", m % 60)):\(String(format: "%02d", s))"
        }
        return "\(m):\(String(format: "%02d", s))"
    }
}

// MARK: - PostComposerView

@MainActor
struct PostComposerView: View {

    // MARK: Init

    /// Pass `activity` when launching from a completed session. Nil for a standalone post.
    let activity: PostComposerActivity?
    let currentUserId: String
    let currentDisplayName: String
    let username: String
    /// Called on successful post with the newly created item so the caller can
    /// prepend it to the feed optimistically.
    let onPost: (FeedItem) -> Void

    @State private var viewModel = PostComposerViewModel()
    @Environment(\.dismiss) private var dismiss

    private let maxCaptionLength = 280

    var body: some View {
        NavigationStack {
            ZStack {
                Color.kineticsBackground.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        authorRow
                        captionEditor
                        if let activity {
                            ActivityPreviewCard(activity: activity)
                        }
                        if let error = viewModel.errorMessage {
                            Text(error)
                                .font(.system(size: 13))
                                .foregroundStyle(Color.kineticsRed)
                                .padding(.horizontal, 20)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 40)
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
                    postButton
                }
            }
        }
    }

    // MARK: Author Row

    private var authorRow: some View {
        HStack(spacing: 12) {
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

            VStack(alignment: .leading, spacing: 2) {
                Text(currentDisplayName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                Text(username.isEmpty ? "@athlete" : username)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.kineticsSubtext)
            }
            Spacer()
        }
    }

    // MARK: Caption Editor

    private var captionEditor: some View {
        ZStack(alignment: .topLeading) {
            if viewModel.caption.isEmpty {
                Text("What's on your mind? Share your session...")
                    .font(.system(size: 16))
                    .foregroundStyle(Color.kineticsSubtext)
                    .padding(.top, 8)
                    .padding(.leading, 4)
                    .allowsHitTesting(false)
            }
            VStack(alignment: .trailing, spacing: 4) {
                TextEditor(text: Binding(
                    get: { viewModel.caption },
                    set: { viewModel.caption = String($0.prefix(maxCaptionLength)) }
                ))
                .font(.system(size: 16))
                .foregroundStyle(.white)
                .tint(Color.kineticsBlue)
                .scrollContentBackground(.hidden)
                .background(Color.clear)
                .frame(minHeight: 100)

                Text("\(viewModel.captionCount)/\(maxCaptionLength)")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(viewModel.captionCountColor)
            }
        }
    }

    // MARK: Post Button

    private var postButton: some View {
        Button {
            Task {
                do {
                    try await viewModel.post(
                        activity: activity,
                        userId: currentUserId,
                        displayName: currentDisplayName,
                        username: username
                    )
                    // Build a preview item to return optimistically.
                    // The real item is already in Firestore; we rebuild a local copy here
                    // so the caller can prepend it without a round-trip fetch.
                    let previewItem = FeedItem(
                        userId: currentUserId,
                        displayName: currentDisplayName,
                        username: username,
                        avatarURL: "",
                        itemType: .workout,
                        title: viewModel.caption.isEmpty ? "New Activity" : String(viewModel.caption.prefix(60)),
                        subtitle: "",
                        caption: viewModel.caption.isEmpty ? nil : viewModel.caption,
                        metrics: [],
                        imageURL: "",
                        postedAt: Date(),
                        kudosCount: 0,
                        commentCount: 0,
                        isLikedByCurrentUser: false,
                        workoutId: "",
                        activityType: "general"
                    )
                    onPost(previewItem)
                    dismiss()
                } catch {
                    viewModel.errorMessage = "Couldn't post. Check your connection and try again."
                }
            }
        } label: {
            if viewModel.isPosting {
                ProgressView().tint(.white).scaleEffect(0.8)
            } else {
                Text("Post")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(viewModel.canPost ? Color.kineticsDark : Color.kineticsSubtext)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 7)
                    .background(viewModel.canPost ? Color.kineticsBlue : Color.kineticsDark)
                    .clipShape(Capsule())
            }
        }
        .disabled(!viewModel.canPost)
    }
}

// MARK: - ActivityPreviewCard

/// Renders attached session data inside the composer so the user can preview
/// what will appear on their post card.
private struct ActivityPreviewCard: View {

    let activity: PostComposerActivity

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(activity.sessionTitle.isEmpty ? "Attached Session" : activity.sessionTitle)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.kineticsBlue)

            switch activity.kind {
            case let .gym(exercises, totalVolume, duration):
                gymPreview(exercises: exercises, totalVolume: totalVolume, duration: duration)
            case let .gps(distKm, durationSecs, pace, coords):
                gpsPreview(distKm: distKm, durationSecs: durationSecs, pace: pace, coords: coords)
            case let .sport(_, metrics):
                sportPreview(metrics: metrics)
            }
        }
        .padding(14)
        .background(Color(white: 0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(Color.kineticsBlue.opacity(0.25), lineWidth: 1))
    }

    // MARK: Gym Preview

    @ViewBuilder
    private func gymPreview(exercises: [ExerciseSummary], totalVolume: Double, duration: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(exercises.prefix(4).enumerated()), id: \.offset) { _, exercise in
                HStack(spacing: 8) {
                    Circle()
                        .fill(Color.kineticsAmber)
                        .frame(width: 6, height: 6)
                    Text(exercise.name)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.88))
                    Spacer()
                    Text("\(exercise.sets)x · \(Int(exercise.topWeightKg))kg")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.kineticsAmber)
                }
            }
            if exercises.count > 4 {
                Text("+ \(exercises.count - 4) more exercises")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.kineticsSubtext)
            }
        }

        Divider().background(Color.white.opacity(0.08))

        HStack(spacing: 0) {
            MetricPill(label: "VOLUME", value: "\(Int(totalVolume))kg")
            MetricPill(label: "EXERCISES", value: "\(exercises.count)")
            MetricPill(label: "TIME", value: "\(duration)min")
        }
    }

    // MARK: GPS Preview

    @ViewBuilder
    private func gpsPreview(distKm: Double, durationSecs: TimeInterval, pace: Double, coords: [[Double]]) -> some View {
        if coords.count >= 2 {
            ComposerRouteMapView(coordinates: coords)
                .frame(height: 160)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }

        let paceMin = Int(pace) / 60
        let paceSec = Int(pace) % 60
        let mins = Int(durationSecs) / 60
        let secs = Int(durationSecs) % 60
        let timeStr = "\(mins):\(String(format: "%02d", secs))"
        let paceStr = "\(paceMin):\(String(format: "%02d", paceSec))"

        HStack(spacing: 0) {
            MetricPill(label: "DIST", value: String(format: "%.1fkm", distKm))
            MetricPill(label: "TIME", value: timeStr)
            MetricPill(label: "PACE", value: "\(paceStr)/km")
        }
    }

    // MARK: Sport Preview

    @ViewBuilder
    private func sportPreview(metrics: [FeedMetric]) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(metrics.prefix(3).enumerated()), id: \.offset) { _, metric in
                MetricPill(label: metric.label, value: metric.value + metric.unit)
            }
        }
    }
}

// MARK: - MetricPill

private struct MetricPill: View {

    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 3) {
            Text(label)
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.kineticsSubtext)
                .tracking(0.6)
            Text(value)
                .font(.system(.subheadline, design: .rounded, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
    }
}

// MARK: - ComposerRouteMapView

/// Route map used inside the composer activity preview — identical logic to the
/// card version but kept private to this file.
private struct ComposerRouteMapView: View {

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
