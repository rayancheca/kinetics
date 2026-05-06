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
// Kept for use by FeedView.ComposePostSheet — do not remove.

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

// MARK: - ComposerActivityType

/// Activity types selectable in the sport/activity picker sheet.
enum ComposerActivityType: CaseIterable, Sendable {
    case striking, grappling, iron, run, wall, general

    var label: String {
        switch self {
        case .striking:  return "Boxing / MMA"
        case .grappling: return "Grappling"
        case .iron:      return "Strength Training"
        case .run:       return "Run"
        case .wall:      return "Climbing"
        case .general:   return "General"
        }
    }

    var sfSymbol: String {
        switch self {
        case .striking:  return "bolt.fill"
        case .grappling: return "person.2.fill"
        case .iron:      return "dumbbell.fill"
        case .run:       return "figure.run"
        case .wall:      return "figure.climbing"
        case .general:   return "star.fill"
        }
    }

    var activityKey: String {
        switch self {
        case .striking:  return "striking"
        case .grappling: return "grappling"
        case .iron:      return "iron"
        case .run:       return "run"
        case .wall:      return "wall"
        case .general:   return "general"
        }
    }

    var color: Color {
        switch self {
        case .striking:  return Color.kineticsRed
        case .grappling: return Color.kineticsOrange
        case .iron:      return Color.kineticsBlue
        case .run:       return Color.kineticsGreen
        case .wall:      return Color(red: 0.25, green: 0.80, blue: 0.55)
        case .general:   return Color.kineticsPurple
        }
    }

    /// Maps a raw activityType string (from `PostComposerActivity`) back to this enum.
    static func from(activityKey key: String) -> ComposerActivityType {
        switch key {
        case "striking":  return .striking
        case "grappling": return .grappling
        case "iron", "ironTracker", "gym": return .iron
        case "run":       return .run
        case "wall":      return .wall
        default:          return .general
        }
    }
}

// MARK: - ComposerPrivacy

enum ComposerPrivacy: String, CaseIterable, Sendable {
    case everyone        = "Everyone"
    case followersOnly   = "Followers Only"
    case onlyMe          = "Only Me"

    var sfSymbol: String {
        switch self {
        case .everyone:      return "globe"
        case .followersOnly: return "person.2.fill"
        case .onlyMe:        return "lock.fill"
        }
    }
}

// MARK: - ComposerMood

enum ComposerMood: String, CaseIterable, Sendable {
    case exhausted = "😴"
    case strong    = "💪"
    case fire      = "🔥"
    case grind     = "😤"
    case champion  = "🏆"
}

// MARK: - PostComposerViewModel

@Observable
@MainActor
final class PostComposerViewModel {

    // MARK: Text

    var title: String = ""
    var descriptionText: String = ""

    // MARK: Activity

    var selectedActivityType: ComposerActivityType = .general
    var activityDate: Date = Date()
    var preloadedActivity: PostComposerActivity?

    // MARK: Photos

    var selectedPhotoItems: [PhotosPickerItem] = []
    var selectedImageDatas: [Data] = []

    // MARK: Mood & Privacy

    var selectedMood: ComposerMood?
    var privacy: ComposerPrivacy = .everyone

    // MARK: Tags (stub — wired to Firebase later)

    var taggedUsernames: [String] = []
    var showTagSheet: Bool = false
    var tagSearchText: String = ""

    // MARK: Posting state

    var isPosting: Bool = false
    var postSucceeded: Bool = false
    var errorMessage: String?
    var showDiscardAlert: Bool = false
    var showActivityPicker: Bool = false
    var showPrivacyPicker: Bool = false

    // MARK: Derived

    var canPost: Bool {
        !isPosting && !title.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// True if the user has entered any content worth warning about on discard.
    var hasContent: Bool {
        !title.isEmpty || !descriptionText.isEmpty || !selectedImageDatas.isEmpty
    }

    // MARK: Init

    init(
        prefilledSession: SessionResult? = nil,
        prefilledGymSession: WorkoutSession? = nil,
        preloadedActivity: PostComposerActivity? = nil
    ) {
        self.preloadedActivity = preloadedActivity

        if let session = prefilledSession {
            selectedActivityType = ComposerActivityType.from(activityKey: session.sport.rawValue)
            activityDate = session.startedAt
            title = autoTitle(for: selectedActivityType, at: session.startedAt)
        } else if let gym = prefilledGymSession {
            selectedActivityType = .iron
            activityDate = gym.startedAt
            title = autoTitle(for: .iron, at: gym.startedAt)
        } else if let activity = preloadedActivity {
            switch activity.kind {
            case .gym: selectedActivityType = .iron
            case .gps: selectedActivityType = .run
            case let .sport(type, _): selectedActivityType = .from(activityKey: type)
            }
            if !activity.sessionTitle.isEmpty {
                title = activity.sessionTitle
            } else {
                title = autoTitle(for: selectedActivityType, at: activityDate)
            }
        } else {
            title = autoTitle(for: .general, at: Date())
        }
    }

    // MARK: Auto-title

    func autoTitle(for type: ComposerActivityType, at date: Date) -> String {
        let hour = Calendar.current.component(.hour, from: date)
        let prefix: String
        switch hour {
        case 5..<12:  prefix = "Morning"
        case 12..<18: prefix = "Afternoon"
        case 18..<23: prefix = "Evening"
        default:      prefix = "Late Night"
        }
        return "\(prefix) \(type.label)"
    }

    // MARK: Photo loading

    func loadPhotoData(from item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self) else { return }
        selectedImageDatas.append(data)
    }

    func removePhoto(at index: Int) {
        guard selectedImageDatas.indices.contains(index) else { return }
        selectedImageDatas.remove(at: index)
    }

    // MARK: Post

    func post(
        userId: String,
        displayName: String,
        username: String
    ) async throws {
        isPosting = true
        defer { isPosting = false }

        // Upload photos first (best-effort; errors are swallowed so a failed
        // image upload does not block the post).
        var uploadedImageURL = ""
        let postId = UUID().uuidString
        if let firstData = selectedImageDatas.first {
            uploadedImageURL = (try? await SocialRepository.shared.uploadPostImage(firstData, postId: postId, index: 0)) ?? ""
        }

        // Build metrics and exercise summaries from the preloaded activity.
        var metrics: [FeedMetric] = []
        var exerciseSummaries: [ExerciseSummary]?
        var routeCoordinates: [[Double]]?
        var itemType: FeedItemType = .workout
        var subtitle = ""

        if let activity = preloadedActivity {
            switch activity.kind {
            case let .gym(exercises, totalVolume, duration):
                itemType = .gymSession
                exerciseSummaries = exercises
                subtitle = "\(exercises.count) exercises · \(Int(totalVolume))kg · \(duration)min"
                metrics = [
                    FeedMetric(label: "VOLUME", value: "\(Int(totalVolume))", unit: "kg"),
                    FeedMetric(label: "EXERCISES", value: "\(exercises.count)", unit: ""),
                    FeedMetric(label: "TIME", value: "\(duration)", unit: "min")
                ]
            case let .gps(distKm, duration, pace, coords):
                itemType = .workout
                routeCoordinates = coords
                let paceStr = formatPace(pace)
                subtitle = "\(formatDuration(duration)) · \(paceStr)/km"
                metrics = [
                    FeedMetric(label: "DIST", value: String(format: "%.1f", distKm), unit: "km"),
                    FeedMetric(label: "TIME", value: formatDuration(duration), unit: ""),
                    FeedMetric(label: "PACE", value: paceStr, unit: "/km")
                ]
            case let .sport(type, sportMetrics):
                itemType = {
                    switch type {
                    case "striking":  return FeedItemType.strikeSession
                    case "grappling": return FeedItemType.grapplingSession
                    case "wall":      return FeedItemType.wallSession
                    default:          return FeedItemType.workout
                    }
                }()
                metrics = sportMetrics
            }
        } else {
            // No preloaded activity; use the selected type to choose item type.
            switch selectedActivityType {
            case .striking:  itemType = .strikeSession
            case .grappling: itemType = .grapplingSession
            case .wall:      itemType = .wallSession
            case .iron:      itemType = .gymSession
            default:         itemType = .workout
            }
        }

        let item = FeedItem(
            id: postId,
            userId: userId,
            displayName: displayName,
            username: username,
            avatarURL: "",
            itemType: itemType,
            title: title,
            subtitle: subtitle,
            caption: descriptionText.isEmpty ? nil : descriptionText,
            metrics: metrics,
            exerciseSummaries: exerciseSummaries,
            routeCoordinates: routeCoordinates,
            imageURL: uploadedImageURL,
            postedAt: activityDate,
            kudosCount: 0,
            commentCount: 0,
            isLikedByCurrentUser: false,
            workoutId: "",
            activityType: selectedActivityType.activityKey
        )

        try await SocialRepository.shared.post(item: item)
    }

    // MARK: Private helpers

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let m = total / 60
        let s = total % 60
        if m >= 60 {
            return "\(m / 60):\(String(format: "%02d", m % 60)):\(String(format: "%02d", s))"
        }
        return "\(m):\(String(format: "%02d", s))"
    }

    private func formatPace(_ secPerKm: Double) -> String {
        let m = Int(secPerKm) / 60
        let s = Int(secPerKm) % 60
        return "\(m):\(String(format: "%02d", s))"
    }
}

// MARK: - PostComposerView

@MainActor
struct PostComposerView: View {

    // MARK: Init params

    let currentUserId: String
    let currentDisplayName: String
    let username: String
    let initialCaption: String
    let initialActivity: PostComposerActivity?
    let onPost: (FeedItem) -> Void

    @State private var viewModel: PostComposerViewModel
    @Environment(\.dismiss) private var dismiss

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
        self._viewModel = State(
            initialValue: PostComposerViewModel(preloadedActivity: initialActivity)
        )
    }

    // MARK: Body

    var body: some View {
        NavigationStack {
            ZStack {
                Color.kineticsBackground.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 0) {
                        activityTypeHeaderRow
                        sectionDivider

                        titleField
                        sectionDivider

                        descriptionField
                        sectionDivider

                        if viewModel.preloadedActivity != nil {
                            statsBlock
                            sectionDivider
                        }

                        photoSection
                        sectionDivider

                        moodRow
                        sectionDivider

                        privacyRow
                        sectionDivider

                        tagRow
                        sectionDivider

                        if let error = viewModel.errorMessage {
                            errorBanner(error)
                                .padding(.horizontal, 16)
                                .padding(.top, 16)
                        }

                        postButton
                            .padding(.horizontal, 16)
                            .padding(.top, 20)
                            .padding(.bottom, 40)
                    }
                }

                if viewModel.isPosting { postingOverlay }
                if viewModel.postSucceeded { successOverlay }
            }
            .navigationTitle("New Activity")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.kineticsBackground, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        if viewModel.hasContent {
                            viewModel.showDiscardAlert = true
                        } else {
                            dismiss()
                        }
                    }
                    .font(.system(size: 16))
                    .foregroundStyle(Color.kineticsRed)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    navPostButton
                }
            }
            .confirmationDialog("Discard Post?", isPresented: $viewModel.showDiscardAlert) {
                Button("Discard", role: .destructive) { dismiss() }
                Button("Keep Editing", role: .cancel) {}
            }
            // Activity type picker sheet
            .sheet(isPresented: $viewModel.showActivityPicker) {
                activityPickerSheet
            }
            // Tag athletes sheet (stub)
            .sheet(isPresented: $viewModel.showTagSheet) {
                tagAthletesSheet
            }
            .onAppear {
                if !initialCaption.isEmpty && viewModel.descriptionText.isEmpty {
                    viewModel.descriptionText = initialCaption
                }
            }
        }
        .presentationDetents([.large])
    }

    // MARK: - Activity Type Header Row

    private var activityTypeHeaderRow: some View {
        Button {
            viewModel.showActivityPicker = true
        } label: {
            HStack(spacing: 14) {
                // Sport icon circle
                ZStack {
                    Circle()
                        .fill(viewModel.selectedActivityType.color)
                        .frame(width: 44, height: 44)
                    Image(systemName: viewModel.selectedActivityType.sfSymbol)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.black)
                }

                // Activity name + date/time
                VStack(alignment: .leading, spacing: 3) {
                    Text(viewModel.selectedActivityType.label)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                    Text(viewModel.activityDate, style: .date) + Text(" at ") + Text(viewModel.activityDate, style: .time)
                }
                .font(.system(size: 12))
                .foregroundStyle(Color.kineticsSubtext)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.kineticsSubtext.opacity(0.5))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Title Field

    private var titleField: some View {
        TextField(
            viewModel.autoTitle(for: viewModel.selectedActivityType, at: viewModel.activityDate),
            text: $viewModel.title,
            prompt: Text(
                viewModel.autoTitle(for: viewModel.selectedActivityType, at: viewModel.activityDate)
            )
            .foregroundStyle(Color.kineticsSubtext)
        )
        .font(.system(size: 20, weight: .semibold, design: .rounded))
        .foregroundStyle(.white)
        .tint(Color.kineticsBlue)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    // MARK: - Description Field

    private var descriptionField: some View {
        ZStack(alignment: .topLeading) {
            if viewModel.descriptionText.isEmpty {
                Text("How did it feel? Add a note…")
                    .font(.system(size: 15))
                    .foregroundStyle(Color.kineticsSubtext)
                    .padding(.top, 14)
                    .padding(.leading, 20)
                    .allowsHitTesting(false)
            }
            TextEditor(text: $viewModel.descriptionText)
                .font(.system(size: 15))
                .foregroundStyle(.white)
                .tint(Color.kineticsBlue)
                .scrollContentBackground(.hidden)
                .background(Color.clear)
                .frame(minHeight: 60)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
        }
    }

    // MARK: - Stats Block

    @ViewBuilder
    private var statsBlock: some View {
        if let activity = viewModel.preloadedActivity {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    switch activity.kind {
                    case let .gym(exercises, totalVolume, duration):
                        statChip(value: formatVolume(totalVolume), label: "Volume")
                        statChip(value: "\(duration) min", label: "Duration")
                        statChip(value: "\(exercises.reduce(0) { $0 + $1.sets })", label: "Sets")
                        statChip(value: "\(exercises.count)", label: "Exercises")
                        let prs = exercises.filter { $0.topWeightKg > 0 }.count
                        if prs > 0 {
                            statChip(value: "\(prs) PRs", label: "Personal Bests", isGold: true)
                        }

                    case let .gps(distKm, duration, pace, _):
                        statChip(value: String(format: "%.1f km", distKm), label: "Distance")
                        statChip(value: formatDurationMin(duration), label: "Duration")
                        statChip(value: formatPaceStr(pace), label: "Avg Pace")

                    case let .sport(_, metrics):
                        ForEach(Array(metrics.prefix(5).enumerated()), id: \.offset) { _, metric in
                            statChip(value: metric.value + metric.unit, label: metric.label)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
        }
    }

    private func statChip(value: String, label: String, isGold: Bool = false) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(isGold ? Color.kineticsAmber : .white)
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color.kineticsSubtext)
                .textCase(.uppercase)
                .tracking(0.5)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(isGold ? Color.kineticsAmber.opacity(0.35) : Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    // MARK: - Photo Section

    private var photoSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            if viewModel.selectedImageDatas.isEmpty {
                PhotosPicker(
                    selection: Binding(
                        get: { viewModel.selectedPhotoItems },
                        set: { items in
                            viewModel.selectedPhotoItems = items
                            Task {
                                for item in items {
                                    await viewModel.loadPhotoData(from: item)
                                }
                            }
                        }
                    ),
                    maxSelectionCount: 10,
                    matching: .images
                ) {
                    HStack(spacing: 12) {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(Color.kineticsBlue)
                            .frame(width: 28, height: 28)
                        Text("Add Photos")
                            .font(.system(size: 15))
                            .foregroundStyle(.white)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.kineticsSubtext.opacity(0.5))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                }
                .buttonStyle(.plain)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(Array(viewModel.selectedImageDatas.enumerated()), id: \.offset) { index, data in
                            if let uiImage = UIImage(data: data) {
                                Image(uiImage: uiImage)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 80, height: 80)
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    .contextMenu {
                                        Button(role: .destructive) {
                                            withAnimation(.spring(duration: 0.25)) {
                                                viewModel.removePhoto(at: index)
                                            }
                                        } label: {
                                            Label("Remove Photo", systemImage: "trash")
                                        }
                                    }
                            }
                        }

                        if viewModel.selectedImageDatas.count < 10 {
                            PhotosPicker(
                                selection: Binding(
                                    get: { viewModel.selectedPhotoItems },
                                    set: { items in
                                        viewModel.selectedPhotoItems = items
                                        Task {
                                            for item in items {
                                                await viewModel.loadPhotoData(from: item)
                                            }
                                        }
                                    }
                                ),
                                maxSelectionCount: 10 - viewModel.selectedImageDatas.count,
                                matching: .images
                            ) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(Color.white.opacity(0.07))
                                        .frame(width: 80, height: 80)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                                        )
                                    Image(systemName: "plus")
                                        .font(.system(size: 22, weight: .medium))
                                        .foregroundStyle(Color.kineticsSubtext)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                }
            }
        }
    }

    // MARK: - Mood Row

    private var moodRow: some View {
        HStack(spacing: 12) {
            Text("Mood")
                .font(.system(size: 15))
                .foregroundStyle(.white)
            Spacer()
            HStack(spacing: 8) {
                ForEach(ComposerMood.allCases, id: \.rawValue) { mood in
                    Button {
                        withAnimation(.spring(duration: 0.2)) {
                            viewModel.selectedMood = viewModel.selectedMood == mood ? nil : mood
                        }
                    } label: {
                        Text(mood.rawValue)
                            .font(.system(size: 22))
                            .padding(6)
                            .background(
                                viewModel.selectedMood == mood
                                    ? Color.kineticsBlue.opacity(0.18)
                                    : Color.clear
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .strokeBorder(
                                        viewModel.selectedMood == mood
                                            ? Color.kineticsBlue.opacity(0.6)
                                            : Color.clear,
                                        lineWidth: 1.5
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Privacy Row

    private var privacyRow: some View {
        Button {
            viewModel.showPrivacyPicker = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: viewModel.privacy.sfSymbol)
                    .font(.system(size: 15))
                    .foregroundStyle(Color.kineticsSubtext)
                    .frame(width: 24)
                Text("Who can see this?")
                    .font(.system(size: 15))
                    .foregroundStyle(.white)
                Spacer()
                Text(viewModel.privacy.rawValue)
                    .font(.system(size: 14))
                    .foregroundStyle(Color.kineticsSubtext)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.kineticsSubtext.opacity(0.5))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .buttonStyle(.plain)
        .confirmationDialog("Who can see this?", isPresented: $viewModel.showPrivacyPicker, titleVisibility: .visible) {
            ForEach(ComposerPrivacy.allCases, id: \.rawValue) { option in
                Button(option.rawValue) {
                    withAnimation { viewModel.privacy = option }
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: - Tag Row

    private var tagRow: some View {
        Button {
            viewModel.showTagSheet = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "person.badge.plus")
                    .font(.system(size: 15))
                    .foregroundStyle(Color.kineticsSubtext)
                    .frame(width: 24)

                if viewModel.taggedUsernames.isEmpty {
                    Text("+ Tag Athletes")
                        .font(.system(size: 15))
                        .foregroundStyle(Color.kineticsBlue)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(viewModel.taggedUsernames, id: \.self) { handle in
                                Text(handle)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(Color.kineticsBlue)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.kineticsBlue.opacity(0.12), in: Capsule())
                            }
                        }
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.kineticsSubtext.opacity(0.5))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Post Button (bottom)

    private var postButton: some View {
        Button {
            triggerPost()
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(viewModel.canPost ? Color.kineticsBlue : Color(white: 0.16))

                if viewModel.isPosting {
                    ProgressView()
                        .tint(.white)
                } else {
                    Text("Share Activity")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(viewModel.canPost ? Color.black : Color.kineticsSubtext)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
        }
        .disabled(!viewModel.canPost)
        .animation(.easeInOut(duration: 0.15), value: viewModel.canPost)
    }

    // MARK: - Nav Post Button (toolbar)

    private var navPostButton: some View {
        Button {
            triggerPost()
        } label: {
            if viewModel.isPosting {
                ProgressView().tint(.white).scaleEffect(0.8)
                    .frame(width: 70, height: 32)
            } else {
                Text("Post")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(viewModel.canPost ? Color.black : Color.kineticsSubtext)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 7)
                    .background(
                        viewModel.canPost ? Color.kineticsBlue : Color(white: 0.18)
                    )
                    .clipShape(Capsule())
            }
        }
        .disabled(!viewModel.canPost)
        .animation(.easeInOut(duration: 0.15), value: viewModel.canPost)
    }

    // MARK: - Overlays

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

    // MARK: - Activity Picker Sheet

    private var activityPickerSheet: some View {
        NavigationStack {
            ZStack {
                Color.kineticsBackground.ignoresSafeArea()
                List {
                    ForEach(ComposerActivityType.allCases, id: \.activityKey) { type in
                        Button {
                            viewModel.selectedActivityType = type
                            // Regenerate title only if it still matches an auto-title pattern.
                            viewModel.title = viewModel.autoTitle(for: type, at: viewModel.activityDate)
                            viewModel.showActivityPicker = false
                        } label: {
                            HStack(spacing: 14) {
                                ZStack {
                                    Circle()
                                        .fill(type.color)
                                        .frame(width: 36, height: 36)
                                    Image(systemName: type.sfSymbol)
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundStyle(.black)
                                }
                                Text(type.label)
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundStyle(.white)
                                Spacer()
                                if viewModel.selectedActivityType.activityKey == type.activityKey {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(Color.kineticsBlue)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(Color(white: 0.08))
                    }
                }
                .scrollContentBackground(.hidden)
                .background(Color.kineticsBackground)
            }
            .navigationTitle("Activity Type")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.kineticsBackground, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { viewModel.showActivityPicker = false }
                        .foregroundStyle(Color.kineticsBlue)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Tag Athletes Sheet (stub)

    private var tagAthletesSheet: some View {
        NavigationStack {
            ZStack {
                Color.kineticsBackground.ignoresSafeArea()
                VStack(spacing: 0) {
                    // Search field
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(Color.kineticsSubtext)
                        TextField("Search athletes…", text: $viewModel.tagSearchText)
                            .foregroundStyle(.white)
                            .tint(Color.kineticsBlue)
                    }
                    .padding(12)
                    .background(Color(white: 0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .padding(16)

                    // Stub user list
                    List {
                        ForEach(stubAthleteHandles(matching: viewModel.tagSearchText), id: \.self) { handle in
                            Button {
                                if !viewModel.taggedUsernames.contains(handle) {
                                    viewModel.taggedUsernames.append(handle)
                                }
                                viewModel.showTagSheet = false
                            } label: {
                                HStack(spacing: 12) {
                                    ZStack {
                                        Circle()
                                            .fill(Color.kineticsPurple.opacity(0.25))
                                            .frame(width: 38, height: 38)
                                        Text(String(handle.prefix(1)).uppercased())
                                            .font(.system(size: 14, weight: .bold))
                                            .foregroundStyle(Color.kineticsPurple)
                                    }
                                    Text(handle)
                                        .font(.system(size: 15))
                                        .foregroundStyle(.white)
                                    Spacer()
                                    if viewModel.taggedUsernames.contains(handle) {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(Color.kineticsBlue)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                            .buttonStyle(.plain)
                            .listRowBackground(Color(white: 0.08))
                        }
                    }
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle("Tag Athletes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.kineticsBackground, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { viewModel.showTagSheet = false }
                        .foregroundStyle(Color.kineticsBlue)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Helpers

    private var sectionDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.06))
            .frame(maxWidth: .infinity)
            .frame(height: 1)
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 13))
                .foregroundStyle(Color.kineticsRed)
            Text(message)
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
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private func triggerPost() {
        Task {
            do {
                try await viewModel.post(
                    userId: currentUserId,
                    displayName: currentDisplayName,
                    username: username
                )
                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.success)
                withAnimation(.spring(duration: 0.35)) {
                    viewModel.postSucceeded = true
                }
                let previewItem = buildOptimisticItem()
                try? await Task.sleep(for: .seconds(0.85))
                onPost(previewItem)
                dismiss()
            } catch {
                viewModel.errorMessage = "Couldn't post. Check your connection and try again."
            }
        }
    }

    private func buildOptimisticItem() -> FeedItem {
        FeedItem(
            userId: currentUserId,
            displayName: currentDisplayName,
            username: username,
            avatarURL: "",
            itemType: .workout,
            title: viewModel.title.isEmpty ? "New Activity" : viewModel.title,
            subtitle: "",
            caption: viewModel.descriptionText.isEmpty ? nil : viewModel.descriptionText,
            metrics: [],
            imageURL: "",
            postedAt: viewModel.activityDate,
            kudosCount: 0,
            commentCount: 0,
            isLikedByCurrentUser: false,
            workoutId: "",
            activityType: viewModel.selectedActivityType.activityKey
        )
    }

    private func formatVolume(_ kg: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        return (formatter.string(from: NSNumber(value: Int(kg))) ?? "\(Int(kg))") + " kg"
    }

    private func formatDurationMin(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let m = total / 60
        let s = total % 60
        return "\(m):\(String(format: "%02d", s))"
    }

    private func formatPaceStr(_ secPerKm: Double) -> String {
        let m = Int(secPerKm) / 60
        let s = Int(secPerKm) % 60
        return "\(m):\(String(format: "%02d", s))"
    }

    private func stubAthleteHandles(matching query: String) -> [String] {
        let all = ["@alexguerrero", "@jordankim", "@samtorres", "@caseylee", "@mike_mma", "@bjjqueen"]
        guard !query.isEmpty else { return all }
        return all.filter { $0.localizedCaseInsensitiveContains(query) }
    }
}

// MARK: - ComposerRouteMapView

/// Route map used inside an activity preview — kept private to this file.
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
