import Charts
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

// MARK: - VideoTransferable

struct VideoTransferable: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { video in
            SentTransferredFile(video.url)
        } importing: { received in
            let copy = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString + "_" + received.file.lastPathComponent)
            if FileManager.default.fileExists(atPath: copy.path) {
                try FileManager.default.removeItem(at: copy)
            }
            try FileManager.default.copyItem(at: received.file, to: copy)
            return VideoTransferable(url: copy)
        }
    }
}

// MARK: - ImportPhase

enum ImportPhase: Equatable {
    case idle
    case importing
    case analyzing
    case classifying
    case complete
    case failed(String)

    var label: String {
        switch self {
        case .idle:             return ""
        case .importing:        return "Importing video..."
        case .analyzing:        return "Analyzing movement..."
        case .classifying:      return "Classifying sport..."
        case .complete:         return "Analysis complete"
        case .failed(let msg):  return msg
        }
    }

    var progress: Double {
        switch self {
        case .idle:         return 0
        case .importing:    return 0.15
        case .analyzing:    return 0.55
        case .classifying:  return 0.85
        case .complete:     return 1.0
        case .failed:       return 0
        }
    }

    var isActive: Bool {
        switch self {
        case .idle, .failed:    return false
        default:                return true
        }
    }

    var isComplete: Bool {
        if case .complete = self { return true }
        return false
    }
}

// MARK: - VideoLibraryViewModel

@Observable
@MainActor
final class VideoLibraryViewModel {

    // MARK: State

    var sessions: [VideoSession] = []
    var importPhase: ImportPhase = .idle
    var selectedSportFilter: VideoSport? = nil
    var errorMessage: String? = nil
    var userId: String

    // MARK: Init

    init(userId: String) {
        self.userId = userId
    }

    // MARK: - Load

    func load() async {
        do {
            sessions = try VideoRepository.shared.fetchAll(userId: userId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Import

    func importVideo(from url: URL) async {
        importPhase = .importing
        defer {
            Task { @MainActor in
                if self.importPhase.isComplete {
                    try? await Task.sleep(for: .seconds(1.5))
                    withAnimation(.easeOut(duration: 0.4)) {
                        self.importPhase = .idle
                    }
                }
            }
        }

        do {
            // Phase 1: Copy video to documents
            let localPath = try VideoRepository.shared.copyVideoToDocuments(from: url)
            let thumbData = await VideoRepository.shared.generateThumbnail(from: url)

            let session = VideoSession(
                userId: userId,
                localVideoPath: localPath,
                thumbnailData: thumbData
            )
            session.status = VideoAnalysisStatus.analyzing.rawValue
            try VideoRepository.shared.save(session)
            sessions.insert(session, at: 0)

            // Phase 2: Vision analysis
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                importPhase = .analyzing
            }

            let result: VideoAnalysisResult
            do {
                result = try await VideoAnalysisEngine.shared.analyze(videoURL: url)
            } catch AnalysisError.emptyVideo {
                session.sport = VideoSport.unknown.rawValue
                session.confidence = 0
                session.status = VideoAnalysisStatus.failed.rawValue
                session.title = "Unknown Sport"
                try? VideoRepository.shared.update(session)
                await load()
                withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                    importPhase = .failed("No movement detected")
                }
                try? await Task.sleep(for: .seconds(2))
                withAnimation { importPhase = .idle }
                return
            }

            // Phase 3: Classify
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                importPhase = .classifying
            }

            session.sport = result.sport.rawValue
            session.confidence = result.confidence
            session.durationSeconds = result.durationSeconds
            session.status = VideoAnalysisStatus.complete.rawValue
            session.analyzedAt = Date()

            if let data = try? JSONEncoder().encode(result.metrics),
               let str = String(data: data, encoding: .utf8) {
                session.metricsJSON = str
            }

            session.subjectLabel = result.subjectLabel

            if let data = try? JSONEncoder().encode(result.skeletonFrames),
               let str = String(data: data, encoding: .utf8) {
                session.skeletonFramesJSON = str
            }

            if session.title.isEmpty {
                let formatter = DateFormatter()
                formatter.dateFormat = "MMM d"
                session.title = "\(result.sport.rawValue) – \(formatter.string(from: Date()))"
            }

            try VideoRepository.shared.update(session)

            withAnimation(.spring(response: 0.4, dampingFraction: 0.9)) {
                importPhase = .complete
            }

            await load()

        } catch {
            withAnimation {
                importPhase = .failed(error.localizedDescription)
            }
            try? await Task.sleep(for: .seconds(2.5))
            withAnimation { importPhase = .idle }
        }
    }

    // MARK: - Delete

    func delete(_ session: VideoSession) async {
        do {
            try VideoRepository.shared.delete(session)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Filtered sessions

    var filteredSessions: [VideoSession] {
        guard let filter = selectedSportFilter else { return sessions }
        return sessions.filter { $0.videoSport == filter }
    }
}

// MARK: - VideoLibraryView

struct VideoLibraryView: View {

    let userId: String

    @State private var viewModel: VideoLibraryViewModel
    @State private var showPicker = false
    @State private var selectedItem: PhotosPickerItem?

    init(userId: String) {
        self.userId = userId
        self._viewModel = State(initialValue: VideoLibraryViewModel(userId: userId))
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                Color.kineticsBackground.ignoresSafeArea()

                VStack(spacing: 0) {
                    sportFilterBar

                    if viewModel.importPhase.isActive || viewModel.importPhase.isComplete {
                        analysisBanner
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    if viewModel.filteredSessions.isEmpty && !viewModel.importPhase.isActive {
                        emptyState
                    } else {
                        videoGrid
                    }
                }
            }
            .navigationTitle("VIDEO LIBRARY")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.kineticsBackground, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showPicker = true
                    } label: {
                        Image(systemName: "video.badge.plus")
                            .foregroundStyle(Color.kineticsPurple)
                            .fontWeight(.semibold)
                            .font(.system(size: 18))
                    }
                    .disabled(viewModel.importPhase.isActive)
                }
            }
            .task { await viewModel.load() }
            .photosPicker(
                isPresented: $showPicker,
                selection: $selectedItem,
                matching: .videos,
                photoLibrary: .shared()
            )
            .onChange(of: selectedItem) { _, item in
                guard let item else { return }
                Task { @MainActor in
                    do {
                        if let transferable = try await item.loadTransferable(type: VideoTransferable.self) {
                            selectedItem = nil
                            await viewModel.importVideo(from: transferable.url)
                        } else {
                            selectedItem = nil
                            viewModel.errorMessage = "Could not load the selected video. Please try again."
                        }
                    } catch {
                        selectedItem = nil
                        viewModel.errorMessage = "Failed to import video: \(error.localizedDescription)"
                    }
                }
            }
            .alert("Error", isPresented: .init(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { viewModel.errorMessage = nil }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
        }
    }

    // MARK: - Sport filter bar

    private var sportFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                VideoFilterChip(title: "All", isSelected: viewModel.selectedSportFilter == nil) {
                    withAnimation(.spring(duration: 0.22)) { viewModel.selectedSportFilter = nil }
                }
                ForEach(VideoSport.allCases.filter { $0 != .unknown }, id: \.self) { sport in
                    VideoFilterChip(
                        title: sport.filterLabel,
                        isSelected: viewModel.selectedSportFilter == sport
                    ) {
                        withAnimation(.spring(duration: 0.22)) {
                            viewModel.selectedSportFilter = sport
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Color.kineticsBackground)
    }

    // MARK: - Analysis progress banner

    private var analysisBanner: some View {
        let isComplete = viewModel.importPhase.isComplete
        let isFailed: Bool = {
            if case .failed = viewModel.importPhase { return true }
            return false
        }()

        let bannerColor: Color = isFailed ? Color.kineticsRed : (isComplete ? Color.kineticsGreen : Color.kineticsBlue)
        let bgColor: Color = bannerColor.opacity(0.10)

        return VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: isComplete ? "checkmark.circle.fill" : (isFailed ? "exclamationmark.triangle.fill" : "waveform.badge.magnifyingglass"))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(bannerColor)

                Text(viewModel.importPhase.label)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(bannerColor)
                    .animation(.easeInOut(duration: 0.25), value: viewModel.importPhase.label)

                Spacer()

                if !isComplete && !isFailed {
                    Text("\(Int(viewModel.importPhase.progress * 100))%")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.kineticsSubtext)
                        .contentTransition(.numericText())
                        .animation(.spring(duration: 0.4), value: viewModel.importPhase.progress)
                }
            }

            if !isComplete && !isFailed {
                ProgressView(value: viewModel.importPhase.progress)
                    .tint(bannerColor)
                    .animation(.spring(response: 0.6, dampingFraction: 0.8), value: viewModel.importPhase.progress)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(bgColor)
    }

    // MARK: - Video grid

    private var videoGrid: some View {
        let columns = [
            GridItem(.flexible(), spacing: 10),
            GridItem(.flexible(), spacing: 10)
        ]

        return ScrollView(.vertical, showsIndicators: false) {
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(viewModel.filteredSessions, id: \.id) { session in
                    NavigationLink(destination: VideoAnalysisReportView(session: session, userId: userId)) {
                        VideoThumbnailCard(session: session)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 4)
            .padding(.bottom, 32)
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "video.badge.plus")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(Color.kineticsPurple.opacity(0.5))

            VStack(spacing: 8) {
                Text("No videos yet")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)

                Text("Import your first workout video to get\nAI form analysis")
                    .font(.subheadline)
                    .foregroundStyle(Color.kineticsSubtext)
                    .multilineTextAlignment(.center)
            }

            Button {
                showPicker = true
            } label: {
                Label("Import Video", systemImage: "photo.on.rectangle.angled")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.kineticsPurple, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 32)
            .padding(.top, 4)

            Spacer()
        }
        .padding(.horizontal, 24)
    }
}

// MARK: - VideoFilterChip

private struct VideoFilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? .black : Color.kineticsSubtext)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(
                    Capsule()
                        .fill(isSelected ? Color.kineticsPurple : Color.clear)
                )
                .overlay(
                    Capsule()
                        .strokeBorder(
                            isSelected ? Color.clear : Color.kineticsSubtext.opacity(0.35),
                            lineWidth: 1
                        )
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - VideoThumbnailCard

private struct VideoThumbnailCard: View {

    let session: VideoSession

    private var sportColor: Color { session.videoSport.color }

    private var durationText: String {
        let secs = Int(session.durationSeconds)
        guard secs > 0 else { return "" }
        let m = secs / 60
        let s = secs % 60
        return m > 0 ? "\(m):\(String(format: "%02d", s))" : "0:\(String(format: "%02d", s))"
    }

    private var dateText: String {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f.string(from: session.recordedAt)
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                // Thumbnail or gradient fallback
                thumbnailContent(size: geo.size)

                // Bottom gradient overlay
                LinearGradient(
                    colors: [.clear, .black.opacity(0.78)],
                    startPoint: .center,
                    endPoint: .bottom
                )

                // Bottom label: title + date
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.title.isEmpty ? session.videoSport.rawValue : session.title)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    Text(dateText)
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.6))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 9)
                .padding(.bottom, 9)

                // Sport badge — top-left pill
                VStack {
                    HStack {
                        HStack(spacing: 4) {
                            Image(systemName: session.videoSport.systemImage)
                                .font(.system(size: 9, weight: .bold))
                            Text(session.videoSport.shortLabel)
                                .font(.system(size: 9, weight: .semibold))
                        }
                        .foregroundStyle(sportColor)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(Color.black.opacity(0.55))
                                .overlay(Capsule().strokeBorder(sportColor.opacity(0.4), lineWidth: 0.75))
                        )
                        .padding(8)
                        Spacer()

                        // Duration badge — top-right
                        if !durationText.isEmpty {
                            Text(durationText)
                                .font(.system(size: 10, weight: .medium, design: .rounded))
                                .foregroundStyle(.white.opacity(0.9))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 4)
                                .background(
                                    Capsule().fill(Color.black.opacity(0.55))
                                )
                                .padding(8)
                        }
                    }
                    Spacer()
                }

                // Analyzing overlay
                if session.analysisStatus == .analyzing {
                    ZStack {
                        Color.black.opacity(0.6)
                        VStack(spacing: 8) {
                            AnalyzingRing()
                            Text("Analyzing")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(Color.kineticsBlue)
                        }
                    }
                }
            }
        }
        .aspectRatio(9 / 16, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 0.75)
        )
    }

    @ViewBuilder
    private func thumbnailContent(size: CGSize) -> some View {
        if let data = session.thumbnailData, let uiImage = UIImage(data: data) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                .frame(width: size.width, height: size.height)
                .clipped()
        } else {
            ZStack {
                LinearGradient(
                    colors: [sportColor.opacity(0.16), Color.kineticsDark],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Image(systemName: session.videoSport.systemImage)
                    .font(.system(size: 30, weight: .light))
                    .foregroundStyle(sportColor.opacity(0.5))
            }
        }
    }
}

// MARK: - AnalyzingRing

private struct AnalyzingRing: View {
    @State private var rotation: Double = 0

    var body: some View {
        Circle()
            .trim(from: 0.1, to: 0.9)
            .stroke(Color.kineticsBlue, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
            .frame(width: 28, height: 28)
            .rotationEffect(.degrees(rotation))
            .onAppear {
                withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) {
                    rotation = 360
                }
            }
    }
}

// MARK: - VideoDetailView

struct VideoDetailView: View {

    @Environment(\.dismiss) private var dismiss
    let session: VideoSession
    let userId: String

    @State private var notes: String = ""
    @State private var showDeleteAlert = false
    @State private var progressSessions: [VideoSession] = []

    private var sportColor: Color { session.videoSport.color }

    private var dateText: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .short
        return formatter.string(from: session.recordedAt)
    }

    private var confidenceText: String { "\(Int(session.confidence * 100))%" }

    var body: some View {
        ZStack {
            Color.kineticsBackground.ignoresSafeArea()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    thumbnailHeader

                    VStack(alignment: .leading, spacing: 24) {
                        analysisSection

                        if session.analysisStatus == .failed || session.metrics.isEmpty {
                            noMovementState
                        } else {
                            metricsSection
                        }

                        if progressSessions.count >= 2 {
                            inlineProgressSection
                        }

                        notesSection

                        VStack(alignment: .leading, spacing: 4) {
                            sectionLabel("FILMED")
                            Text(dateText)
                                .font(.system(size: 14))
                                .foregroundStyle(.white.opacity(0.8))
                        }

                        actionButtons
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 24)
                    .padding(.bottom, 48)
                }
            }
        }
        .navigationTitle(session.title.isEmpty ? "Video Analysis" : session.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.kineticsBackground, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    shareVideo()
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .foregroundStyle(Color.kineticsSubtext)
                }
            }
        }
        .onAppear {
            notes = session.notes
            loadProgressSessions()
        }
        .confirmationDialog(
            "Delete Video?",
            isPresented: $showDeleteAlert,
            titleVisibility: .visible
        ) {
            Button("Delete Video", role: .destructive) {
                Task {
                    try? VideoRepository.shared.delete(session)
                    dismiss()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently removes the video and its analysis.")
        }
    }

    // MARK: - Thumbnail header

    private var thumbnailHeader: some View {
        ZStack(alignment: .bottom) {
            if let data = session.thumbnailData, let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(height: 220)
                    .clipped()
            } else {
                ZStack {
                    LinearGradient(
                        colors: [sportColor.opacity(0.22), Color.kineticsDark],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .frame(height: 220)
                    Image(systemName: session.videoSport.systemImage)
                        .font(.system(size: 56, weight: .light))
                        .foregroundStyle(sportColor.opacity(0.5))
                }
            }

            LinearGradient(
                colors: [.clear, Color.kineticsBackground],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 90)
        }
        .frame(height: 220)
    }

    // MARK: - Analysis section

    private var analysisSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("ANALYSIS RESULTS")

            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(sportColor.opacity(0.15))
                        .frame(width: 60, height: 60)
                    Image(systemName: session.videoSport.systemImage)
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(sportColor)
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text(session.videoSport.rawValue)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.white)

                    if session.confidence > 0 {
                        HStack(spacing: 6) {
                            Text("Confidence")
                                .font(.system(size: 13))
                                .foregroundStyle(Color.kineticsSubtext)
                            Text(confidenceText)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(sportColor)
                        }
                    }

                    if session.durationSeconds > 0 {
                        let secs = Int(session.durationSeconds)
                        let m = secs / 60
                        let s = secs % 60
                        Text(m > 0 ? "\(m)m \(s)s" : "\(s)s")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.kineticsSubtext)
                    }
                }

                Spacer()
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.kineticsDark)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(sportColor.opacity(0.2), lineWidth: 0.75)
                    )
            )
        }
    }

    // MARK: - No movement state

    private var noMovementState: some View {
        VStack(spacing: 10) {
            Image(systemName: "person.slash")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(Color.kineticsSubtext.opacity(0.6))
            Text("No movement detected")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.kineticsSubtext)
            Text("The Vision framework could not detect a person in enough frames to generate metrics.")
                .font(.system(size: 12))
                .foregroundStyle(Color.kineticsSubtext.opacity(0.7))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.kineticsDark)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(Color.white.opacity(0.06), lineWidth: 0.75)
                )
        )
    }

    // MARK: - Metrics section

    private var metricsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("METRICS")

            VStack(spacing: 8) {
                ForEach(sortedMetricRows, id: \.key) { row in
                    VideoMetricRow(key: row.key, value: row.value, accentColor: sportColor)
                }
            }
        }
    }

    private var sortedMetricRows: [(key: String, value: Double)] {
        let priorityOrder: [String] = [
            "max_wrist_velocity",
            "avg_wrist_velocity",
            "bilateral_symmetry",
            "avg_hip_shoulder_separation",
            "max_hip_shoulder_separation",
            "arms_above_head_ratio",
            "avg_hip_height",
            "min_hip_height",
            "pose_detection_ratio"
        ]
        let metrics = session.metrics
        var result: [(key: String, value: Double)] = []
        for key in priorityOrder {
            if let val = metrics[key] {
                result.append((key: key, value: val))
            }
        }
        // Append any keys not in the priority list
        for (key, val) in metrics where !priorityOrder.contains(key) {
            result.append((key: key, value: val))
        }
        return result
    }

    // MARK: - Inline progress chart

    private var inlineProgressSection: some View {
        let sport = session.videoSport
        let primaryKey = primaryMetricKey(for: sport)
        let chartData: [(date: Date, value: Double)] = progressSessions.compactMap { s in
            guard let val = s.metrics[primaryKey], val > 0 else { return nil }
            return (date: s.recordedAt, value: val)
        }.sorted { $0.date < $1.date }

        let metricDisplay = VideoMetricRow.displayForKey(primaryKey)

        return VStack(alignment: .leading, spacing: 12) {
            sectionLabel("PROGRESS")

            if chartData.count >= 2 {
                VStack(alignment: .leading, spacing: 10) {
                    Text(metricDisplay.label)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.kineticsSubtext)

                    Chart(chartData, id: \.date) { point in
                        LineMark(
                            x: .value("Date", point.date),
                            y: .value("Value", point.value)
                        )
                        .foregroundStyle(sportColor)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                        .interpolationMethod(.catmullRom)

                        PointMark(
                            x: .value("Date", point.date),
                            y: .value("Value", point.value)
                        )
                        .foregroundStyle(sportColor)
                        .symbolSize(35)

                        AreaMark(
                            x: .value("Date", point.date),
                            y: .value("Value", point.value)
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: [sportColor.opacity(0.25), .clear],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .interpolationMethod(.catmullRom)
                    }
                    .chartXAxis {
                        AxisMarks(values: .automatic) { _ in
                            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                                .foregroundStyle(.white.opacity(0.08))
                            AxisValueLabel(format: .dateTime.month().day())
                                .foregroundStyle(Color.kineticsSubtext)
                        }
                    }
                    .chartYAxis {
                        AxisMarks { _ in
                            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                                .foregroundStyle(.white.opacity(0.08))
                            AxisValueLabel()
                                .foregroundStyle(Color.kineticsSubtext)
                        }
                    }
                    .frame(height: 160)
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.kineticsDark)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .strokeBorder(Color.white.opacity(0.06), lineWidth: 0.75)
                        )
                )
            }
        }
    }

    // MARK: - Notes section

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("NOTES")

            TextField("Add session notes...", text: $notes, axis: .vertical)
                .font(.system(size: 14))
                .foregroundStyle(.white)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.kineticsDark)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(Color.white.opacity(0.06), lineWidth: 0.75)
                        )
                )
                .lineLimit(3...6)
                .onChange(of: notes) { _, newValue in
                    session.notes = newValue
                    try? VideoRepository.shared.update(session)
                }
        }
    }

    // MARK: - Action buttons

    private var actionButtons: some View {
        Button(role: .destructive) {
            showDeleteAlert = true
        } label: {
            Label("Delete Video", systemImage: "trash")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.red.opacity(0.08))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(Color.red.opacity(0.25), lineWidth: 1)
                        )
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Color.kineticsSubtext)
            .kerning(0.8)
    }

    private func loadProgressSessions() {
        guard let sessions = try? VideoRepository.shared.fetchBySport(
            userId: userId,
            sport: session.videoSport
        ) else { return }
        progressSessions = sessions
    }

    private func primaryMetricKey(for sport: VideoSport) -> String {
        switch sport {
        case .striking:    return "max_wrist_velocity"
        case .grappling:   return "avg_hip_height"
        case .ironTracker: return "bilateral_symmetry"
        case .wallBeta:    return "arms_above_head_ratio"
        case .gym:         return "bilateral_symmetry"
        case .track:       return "avg_wrist_velocity"
        case .unknown:     return "avg_wrist_velocity"
        }
    }

    private func shareVideo() {
        var items: [Any] = []
        if let data = session.thumbnailData, let img = UIImage(data: data) {
            items.append(img)
        }
        items.append("Kinetics Analysis — \(session.videoSport.rawValue)")

        guard !items.isEmpty else { return }
        let vc = UIActivityViewController(activityItems: items, applicationActivities: nil)
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let root = scene.windows.first?.rootViewController else { return }
        if let popover = vc.popoverPresentationController {
            popover.sourceView = root.view
        }
        root.present(vc, animated: true)
    }
}

// MARK: - VideoMetricRow

struct VideoMetricRow: View {
    let key: String
    let value: Double
    let accentColor: Color

    // MARK: - Display metadata

    struct MetricDisplay {
        let label: String
        let icon: String
        let unit: String
        let isRatio: Bool

        init(label: String, icon: String, unit: String, isRatio: Bool = false) {
            self.label = label
            self.icon = icon
            self.unit = unit
            self.isRatio = isRatio
        }
    }

    static func displayForKey(_ key: String) -> MetricDisplay {
        metricDisplayMap[key] ?? MetricDisplay(
            label: key.replacingOccurrences(of: "_", with: " ").capitalized,
            icon: "chart.bar.fill",
            unit: ""
        )
    }

    private static let metricDisplayMap: [String: MetricDisplay] = [
        "avg_wrist_velocity":           MetricDisplay(label: "Avg. Wrist Speed",    icon: "bolt.fill",                          unit: "m/s"),
        "max_wrist_velocity":           MetricDisplay(label: "Peak Wrist Speed",    icon: "bolt.circle.fill",                   unit: "m/s"),
        "avg_hip_height":               MetricDisplay(label: "Avg. Hip Height",     icon: "figure.stand",                       unit: "", isRatio: false),
        "min_hip_height":               MetricDisplay(label: "Min. Hip Height",     icon: "arrow.down.to.line",                 unit: ""),
        "arms_above_head_ratio":        MetricDisplay(label: "Arms Raised",         icon: "arrow.up.circle.fill",               unit: "%", isRatio: true),
        "bilateral_symmetry":           MetricDisplay(label: "Bilateral Symmetry",  icon: "arrow.left.and.right",               unit: "%", isRatio: true),
        "avg_hip_shoulder_separation":  MetricDisplay(label: "Avg. Hip Separation", icon: "rotate.3d",                          unit: "°"),
        "max_hip_shoulder_separation":  MetricDisplay(label: "Peak Hip Separation", icon: "rotate.3d.fill",                     unit: "°"),
        "pose_detection_ratio":         MetricDisplay(label: "Pose Coverage",       icon: "person.crop.circle.badge.checkmark", unit: "%", isRatio: true),
    ]

    private var display: MetricDisplay { Self.displayForKey(key) }

    private var formattedValue: String {
        if display.isRatio {
            return String(format: "%.0f", value * 100)
        }
        switch display.unit {
        case "°":   return String(format: "%.1f", value)
        case "m/s": return String(format: "%.2f", value)
        default:
            if value == value.rounded() && value < 10_000 {
                return String(Int(value))
            }
            return String(format: "%.2f", value)
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: display.icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(accentColor)
                .frame(width: 22)

            Text(display.label)
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.85))

            Spacer()

            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(formattedValue)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(accentColor)

                if !display.unit.isEmpty {
                    Text(display.unit)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(accentColor.opacity(0.6))
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(accentColor.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(accentColor.opacity(0.12), lineWidth: 0.5)
                )
        )
    }
}

// MARK: - VideoProgressView

struct VideoProgressView: View {

    let userId: String
    let sport: VideoSport

    @State private var sessions: [VideoSession] = []
    @State private var isLoading = false

    private var primaryMetricKey: String {
        switch sport {
        case .striking:    return "max_wrist_velocity"
        case .grappling:   return "avg_hip_height"
        case .ironTracker: return "bilateral_symmetry"
        case .wallBeta:    return "arms_above_head_ratio"
        case .gym:         return "bilateral_symmetry"
        case .track:       return "avg_wrist_velocity"
        case .unknown:     return "avg_wrist_velocity"
        }
    }

    private var sportColor: Color { sport.color }

    private var chartData: [(date: Date, value: Double)] {
        sessions.compactMap { session in
            guard let value = session.metrics[primaryMetricKey], value > 0 else { return nil }
            return (date: session.recordedAt, value: value)
        }
        .sorted { $0.date < $1.date }
    }

    private var metricDisplay: VideoMetricRow.MetricDisplay {
        VideoMetricRow.displayForKey(primaryMetricKey)
    }

    var body: some View {
        ZStack {
            Color.kineticsBackground.ignoresSafeArea()

            if isLoading {
                ProgressView()
                    .tint(Color.kineticsBlue)
            } else if chartData.count < 2 {
                emptyState
            } else {
                progressContent
            }
        }
        .navigationTitle("\(sport.rawValue) Progress")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.kineticsBackground, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task { await loadSessions() }
    }

    // MARK: - Progress content

    private var progressContent: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(metricDisplay.label)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.kineticsSubtext)
                        .textCase(.uppercase)
                        .kerning(0.8)

                    Chart(chartData, id: \.date) { point in
                        LineMark(
                            x: .value("Date", point.date),
                            y: .value("Value", point.value)
                        )
                        .foregroundStyle(sportColor)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                        .interpolationMethod(.catmullRom)

                        PointMark(
                            x: .value("Date", point.date),
                            y: .value("Value", point.value)
                        )
                        .foregroundStyle(sportColor)
                        .symbolSize(40)

                        AreaMark(
                            x: .value("Date", point.date),
                            y: .value("Value", point.value)
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: [sportColor.opacity(0.3), .clear],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .interpolationMethod(.catmullRom)
                    }
                    .chartXAxis {
                        AxisMarks(values: .automatic) { _ in
                            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                                .foregroundStyle(.white.opacity(0.1))
                            AxisValueLabel(format: .dateTime.month().day())
                                .foregroundStyle(Color.kineticsSubtext)
                        }
                    }
                    .chartYAxis {
                        AxisMarks { _ in
                            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                                .foregroundStyle(.white.opacity(0.1))
                            AxisValueLabel()
                                .foregroundStyle(Color.kineticsSubtext)
                        }
                    }
                    .frame(height: 220)
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.kineticsDark)
                )

                HStack(spacing: 12) {
                    statCard(
                        label: "Sessions",
                        value: "\(chartData.count)",
                        icon: "video.fill",
                        color: sportColor
                    )

                    if let best = chartData.max(by: { $0.value < $1.value }) {
                        statCard(
                            label: "Best",
                            value: String(format: "%.2f", best.value),
                            icon: "trophy.fill",
                            color: Color.kineticsAmber
                        )
                    }

                    if let trend = computeTrend() {
                        statCard(
                            label: "Trend",
                            value: trend > 0 ? "+\(String(format: "%.1f", trend))%" : "\(String(format: "%.1f", trend))%",
                            icon: trend > 0 ? "arrow.up.right" : "arrow.down.right",
                            color: trend > 0 ? Color.kineticsGreen : Color.red
                        )
                    }
                }
            }
            .padding(16)
            .padding(.bottom, 32)
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(sportColor.opacity(0.4))

            Text("Not Enough Data")
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundStyle(.white)

            Text("Record at least 2 \(sport.rawValue) sessions\nto see your progress over time")
                .font(.subheadline)
                .foregroundStyle(Color.kineticsSubtext)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 32)
    }

    // MARK: - Helpers

    private func statCard(label: String, value: String, icon: String, color: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(color)
            Text(value)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(Color.kineticsSubtext)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.kineticsDark)
        )
    }

    private func computeTrend() -> Double? {
        guard chartData.count >= 2,
              let first = chartData.first,
              let last = chartData.last,
              first.value > 0
        else { return nil }
        return ((last.value - first.value) / first.value) * 100
    }

    private func loadSessions() async {
        isLoading = true
        defer { isLoading = false }
        sessions = (try? VideoRepository.shared.fetchBySport(userId: userId, sport: sport)) ?? []
    }
}

// MARK: - VideoSport + Display helpers

extension VideoSport {

    var color: Color {
        switch self {
        case .striking:    return Color.kineticsAmber
        case .grappling:   return Color.kineticsPurple
        case .ironTracker: return Color.kineticsBlue
        case .wallBeta:    return Color.kineticsGreen
        case .gym:         return Color.kineticsGreen
        case .track:       return Color.kineticsBlue
        case .unknown:     return Color.kineticsSubtext
        }
    }

    /// Short label for filter chips and badges.
    var filterLabel: String {
        switch self {
        case .striking:    return "Striking"
        case .grappling:   return "Grappling"
        case .ironTracker: return "Iron"
        case .wallBeta:    return "Climbing"
        case .gym:         return "Gym"
        case .track:       return "Track"
        case .unknown:     return "Other"
        }
    }

    /// Very short label for thumbnail overlays.
    var shortLabel: String {
        switch self {
        case .striking:    return "Strike"
        case .grappling:   return "Grapple"
        case .ironTracker: return "Iron"
        case .wallBeta:    return "Climb"
        case .gym:         return "Gym"
        case .track:       return "Track"
        case .unknown:     return "?"
        }
    }
}
