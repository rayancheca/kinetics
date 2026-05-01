import MapKit
import PhotosUI
import SwiftUI
import UIKit

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

// MARK: - SportChip

enum SportChip: CaseIterable {
    case striking, grappling, iron, run, wall

    var label: String {
        switch self {
        case .striking:  return "🥊 Striking"
        case .grappling: return "🤼 Grappling"
        case .iron:      return "🏋️ Iron"
        case .run:       return "🏃 Run"
        case .wall:      return "🧗 Wall"
        }
    }

    var activityType: String {
        switch self {
        case .striking:  return "striking"
        case .grappling: return "grappling"
        case .iron:      return "iron"
        case .run:       return "run"
        case .wall:      return "wall"
        }
    }

    var color: Color {
        switch self {
        case .striking:  return Color(red: 1.0, green: 0.35, blue: 0.25)
        case .grappling: return Color(red: 0.55, green: 0.35, blue: 1.0)
        case .iron:      return Color.kineticsAmber
        case .run:       return Color.kineticsGreen
        case .wall:      return Color(red: 0.25, green: 0.80, blue: 0.55)
        }
    }
}

// MARK: - PostComposerViewModel

@Observable
@MainActor
final class PostComposerViewModel {

    // MARK: State

    var caption: String = ""
    var isPosting = false
    var postSucceeded = false
    var errorMessage: String?
    var selectedPhotoItem: PhotosPickerItem?
    var selectedImageData: Data?
    var isPublic = true

    /// The activity attached via the card selector. Initially set from `init` argument.
    var selectedActivity: PostComposerActivity?

    /// Sport chip selection used when no workout is attached.
    var selectedSportChip: SportChip?

    // MARK: Derived

    var captionCount: Int { caption.count }
    var captionCountColor: Color {
        switch captionCount {
        case ..<260:    return Color.kineticsSubtext
        case 260..<280: return Color.kineticsRed
        default:        return Color.kineticsRed
        }
    }
    /// Share is enabled when there is something to post — caption or an activity.
    var canPost: Bool {
        !isPosting && (!caption.trimmingCharacters(in: .whitespaces).isEmpty || selectedActivity != nil)
    }

    // MARK: Init

    init(preloadedActivity: PostComposerActivity? = nil) {
        self.selectedActivity = preloadedActivity
    }

    // MARK: Post

    func post(
        userId: String,
        displayName: String,
        username: String
    ) async throws {
        isPosting = true
        defer { isPosting = false }

        let activity = selectedActivity
        var metrics: [FeedMetric] = []
        var exerciseSummaries: [ExerciseSummary]?
        var routeCoordinates: [[Double]]?
        var itemType: FeedItemType = .workout
        var title = caption.isEmpty ? "New Activity" : String(caption.prefix(60))
        var subtitle = ""
        var activityType = selectedSportChip?.activityType ?? "general"

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

    let currentUserId: String
    let currentDisplayName: String
    let username: String
    /// Pre-populated caption template (e.g. from a just-finished workout).
    let initialCaption: String
    /// Pre-populated activity data. Also settable interactively inside the composer.
    let initialActivity: PostComposerActivity?
    /// Called on successful post with the newly created item so the caller can
    /// prepend it to the feed optimistically.
    let onPost: (FeedItem) -> Void

    @State private var viewModel: PostComposerViewModel
    @Environment(\.dismiss) private var dismiss

    private let maxCaptionLength = 280

    init(
        currentUserId: String,
        currentDisplayName: String,
        username: String,
        initialCaption: String = "",
        initialActivity: PostComposerActivity? = nil,
        onPost: @escaping (FeedItem) -> Void
    ) {
        self.currentUserId = currentUserId
        self.currentDisplayName = currentDisplayName
        self.username = username
        self.initialCaption = initialCaption
        self.initialActivity = initialActivity
        self.onPost = onPost
        self._viewModel = State(initialValue: PostComposerViewModel(preloadedActivity: initialActivity))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.kineticsBackground.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        authorRow
                        captionEditor

                        // Activity card selector / preview
                        activitySection

                        // Sport chip row — only when no workout attached
                        if viewModel.selectedActivity == nil {
                            sportChipRow
                        }

                        // Inline error banner
                        if let error = viewModel.errorMessage {
                            HStack(spacing: 10) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 13))
                                    .foregroundStyle(Color.kineticsRed)
                                Text(error)
                                    .font(.system(size: 13))
                                    .foregroundStyle(Color.kineticsRed)
                                Spacer()
                                Button {
                                    viewModel.errorMessage = nil
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(Color.kineticsRed.opacity(0.7))
                                }
                            }
                            .padding(12)
                            .background(Color.kineticsRed.opacity(0.1),
                                        in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(Color.kineticsRed.opacity(0.25), lineWidth: 1)
                            )
                            .padding(.horizontal, 20)
                            .transition(.move(edge: .top).combined(with: .opacity))
                            .animation(.spring(duration: 0.3), value: viewModel.errorMessage != nil)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 40)
                }

                // Posting overlay
                if viewModel.isPosting {
                    postingOverlay
                }

                // Success checkmark overlay
                if viewModel.postSucceeded {
                    successOverlay
                }
            }
            .navigationTitle("New Post")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.kineticsBackground, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .font(.system(size: 16))
                        .foregroundStyle(Color.kineticsBlue)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    shareButton
                }
            }
            .onAppear {
                if !initialCaption.isEmpty && viewModel.caption.isEmpty {
                    viewModel.caption = String(initialCaption.prefix(maxCaptionLength))
                }
            }
        }
        .presentationDetents([.large])
    }

    // MARK: - Author Row

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

    // MARK: - Caption Editor

    private var captionEditor: some View {
        VStack(alignment: .trailing, spacing: 4) {
            ZStack(alignment: .topLeading) {
                if viewModel.caption.isEmpty {
                    Text("What did you crush today? 💪")
                        .font(.system(size: 16))
                        .foregroundStyle(Color.kineticsSubtext)
                        .padding(.top, 8)
                        .padding(.leading, 4)
                        .allowsHitTesting(false)
                }
                TextEditor(text: Binding(
                    get: { viewModel.caption },
                    set: { viewModel.caption = String($0.prefix(maxCaptionLength)) }
                ))
                .font(.system(size: 16))
                .foregroundStyle(.white)
                .tint(Color.kineticsBlue)
                .scrollContentBackground(.hidden)
                .background(Color.clear)
                .frame(minHeight: 120)
            }

            Text("\(viewModel.captionCount)/\(maxCaptionLength)")
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(viewModel.captionCountColor)
                .animation(.easeInOut(duration: 0.15), value: viewModel.captionCountColor)
        }
    }

    // MARK: - Activity Section

    @ViewBuilder
    private var activitySection: some View {
        if let activity = viewModel.selectedActivity {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    HStack(spacing: 6) {
                        Image(systemName: "dumbbell.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.kineticsBlue)
                        Text("ATTACHED WORKOUT")
                            .font(.system(size: 10, weight: .semibold))
                            .tracking(1.0)
                            .foregroundStyle(Color.kineticsBlue)
                    }
                    Spacer()
                    Button {
                        withAnimation(.spring(duration: 0.3)) {
                            viewModel.selectedActivity = nil
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "xmark")
                                .font(.system(size: 10, weight: .bold))
                            Text("Remove")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .foregroundStyle(Color.kineticsSubtext)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.kineticsSubtext.opacity(0.1),
                                    in: Capsule())
                    }
                    .buttonStyle(.plain)
                }

                ActivityPreviewCard(activity: activity)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            .animation(.spring(duration: 0.35), value: viewModel.selectedActivity != nil)
        } else {
            // "Attach Workout" placeholder card
            Button {
                // No-op: workout attach is only via programmatic pre-population.
                // This card serves as a visual cue; real attachment comes from
                // launching the composer from a finished session.
            } label: {
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.kineticsBlue.opacity(0.12))
                            .frame(width: 44, height: 44)
                        Image(systemName: "dumbbell.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(Color.kineticsBlue)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Attach Workout")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                        Text("Finish a session then tap \"Share to Feed\"")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.kineticsSubtext)
                    }
                    Spacer()
                }
                .padding(14)
                .background(Color(white: 0.06),
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.kineticsBlue.opacity(0.18), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Sport Chip Row

    private var sportChipRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SPORT")
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.0)
                .foregroundStyle(Color.kineticsSubtext)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(SportChip.allCases, id: \.activityType) { chip in
                        Button {
                            withAnimation(.spring(duration: 0.22)) {
                                if viewModel.selectedSportChip == chip {
                                    viewModel.selectedSportChip = nil
                                } else {
                                    viewModel.selectedSportChip = chip
                                }
                            }
                        } label: {
                            Text(chip.label)
                                .font(.system(size: 13, weight:
                                    viewModel.selectedSportChip == chip ? .semibold : .regular))
                                .foregroundStyle(
                                    viewModel.selectedSportChip == chip ? .black : Color.kineticsSubtext)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(
                                    Capsule()
                                        .fill(viewModel.selectedSportChip == chip
                                              ? chip.color
                                              : Color(white: 0.1))
                                )
                                .overlay(
                                    Capsule()
                                        .strokeBorder(
                                            viewModel.selectedSportChip == chip
                                                ? Color.clear
                                                : chip.color.opacity(0.25),
                                            lineWidth: 1
                                        )
                                )
                                .animation(.spring(duration: 0.2), value: viewModel.selectedSportChip)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    // MARK: - Share Button

    private var shareButton: some View {
        Button {
            Task {
                do {
                    try await viewModel.post(
                        userId: currentUserId,
                        displayName: currentDisplayName,
                        username: username
                    )
                    // Success haptic + brief overlay, then dismiss
                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.success)
                    withAnimation(.spring(duration: 0.35)) {
                        viewModel.postSucceeded = true
                    }
                    // Build optimistic item
                    let previewItem = buildOptimisticItem()
                    try? await Task.sleep(for: .seconds(0.85))
                    onPost(previewItem)
                    dismiss()
                } catch {
                    viewModel.errorMessage = "Couldn't post. Check your connection and try again."
                }
            }
        } label: {
            if viewModel.isPosting {
                ProgressView().tint(.white).scaleEffect(0.8)
                    .frame(width: 70, height: 32)
            } else {
                Text("Share")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(viewModel.canPost ? Color.kineticsDark : Color.kineticsSubtext)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 7)
                    .background(
                        viewModel.canPost
                            ? Color.kineticsBlue
                            : Color(white: 0.18)
                    )
                    .clipShape(Capsule())
            }
        }
        .disabled(!viewModel.canPost)
        .animation(.easeInOut(duration: 0.15), value: viewModel.canPost)
    }

    // MARK: - Posting Overlay

    private var postingOverlay: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
            VStack(spacing: 14) {
                ProgressView()
                    .tint(Color.kineticsBlue)
                    .scaleEffect(1.3)
                Text("Sharing…")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .padding(28)
            .background(Color(white: 0.1),
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .transition(.opacity)
    }

    // MARK: - Success Overlay

    private var successOverlay: some View {
        ZStack {
            Color.black.opacity(0.45).ignoresSafeArea()
            VStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(Color.kineticsGreen)
                Text("Posted!")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
            }
            .padding(32)
            .background(Color(white: 0.1),
                        in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .transition(.scale(scale: 0.8).combined(with: .opacity))
    }

    // MARK: - Helpers

    private func buildOptimisticItem() -> FeedItem {
        FeedItem(
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
            activityType: viewModel.selectedSportChip?.activityType ?? "general"
        )
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
