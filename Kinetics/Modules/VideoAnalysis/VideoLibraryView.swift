import Charts
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

// MARK: - VideoTransferable

struct VideoTransferable: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { video in
            SentTransferredFile(video.url)
        } importing: { received in
            let copy = FileManager.default.temporaryDirectory
                .appendingPathComponent(received.file.lastPathComponent)
            if FileManager.default.fileExists(atPath: copy.path) {
                try FileManager.default.removeItem(at: copy)
            }
            try FileManager.default.copyItem(at: received.file, to: copy)
            return VideoTransferable(url: copy)
        }
    }
}

// MARK: - VideoLibraryViewModel

@Observable
@MainActor
final class VideoLibraryViewModel {

    // MARK: State

    var sessions: [VideoSession] = []
    var isImporting = false
    var isAnalyzing = false
    var analysisProgress: Double = 0
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
        isAnalyzing = true
        analysisProgress = 0
        defer { isAnalyzing = false }

        do {
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

            analysisProgress = 0.3

            let result = try await VideoAnalysisEngine.shared.analyze(videoURL: url)

            analysisProgress = 0.9

            session.sport = result.sport.rawValue
            session.confidence = result.confidence
            session.durationSeconds = result.durationSeconds
            session.status = VideoAnalysisStatus.complete.rawValue
            session.analyzedAt = Date()

            if let data = try? JSONEncoder().encode(result.metrics),
               let str = String(data: data, encoding: .utf8) {
                session.metricsJSON = str
            }

            if session.title.isEmpty {
                session.title = "\(result.sport.rawValue) Session"
            }

            try VideoRepository.shared.update(session)
            analysisProgress = 1.0

            try? await Task.sleep(for: .milliseconds(300))
            await load()
        } catch {
            errorMessage = error.localizedDescription
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
            ZStack {
                Color.kineticsBackground.ignoresSafeArea()

                VStack(spacing: 0) {
                    // Sport filter chips
                    sportFilterBar

                    // Analysis progress banner
                    if viewModel.isAnalyzing {
                        analysisBanner
                    }

                    if viewModel.filteredSessions.isEmpty && !viewModel.isAnalyzing {
                        emptyState
                    } else {
                        videoGrid
                    }
                }
            }
            .navigationTitle("Video Library")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(Color.kineticsBackground, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showPicker = true
                    } label: {
                        Image(systemName: "plus")
                            .foregroundStyle(Color.kineticsBlue)
                            .fontWeight(.semibold)
                    }
                }
            }
            .task { await viewModel.load() }
            .photosPicker(
                isPresented: $showPicker,
                selection: $selectedItem,
                matching: .videos
            )
            .onChange(of: selectedItem) { _, item in
                guard let item else { return }
                Task {
                    if let transferable = try? await item.loadTransferable(type: VideoTransferable.self) {
                        await viewModel.importVideo(from: transferable.url)
                    } else {
                        viewModel.errorMessage = "Could not load the selected video."
                    }
                    selectedItem = nil
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
                VideoFilterChip(
                    title: "All",
                    isSelected: viewModel.selectedSportFilter == nil
                ) {
                    viewModel.selectedSportFilter = nil
                }

                ForEach(VideoSport.allCases, id: \.self) { sport in
                    VideoFilterChip(
                        title: sport.rawValue,
                        isSelected: viewModel.selectedSportFilter == sport
                    ) {
                        viewModel.selectedSportFilter = sport
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
        VStack(spacing: 6) {
            HStack {
                Image(systemName: "waveform.badge.magnifyingglass")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.kineticsBlue)
                Text("Analyzing video...")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.kineticsBlue)
                Spacer()
                Text("\(Int(viewModel.analysisProgress * 100))%")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.kineticsSubtext)
            }
            ProgressView(value: viewModel.analysisProgress)
                .tint(Color.kineticsBlue)
                .animation(.linear(duration: 0.3), value: viewModel.analysisProgress)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.kineticsBlue.opacity(0.08))
    }

    // MARK: - Video grid

    private var videoGrid: some View {
        let columns = [
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12)
        ]

        return ScrollView(.vertical, showsIndicators: false) {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(viewModel.filteredSessions, id: \.id) { session in
                    NavigationLink(destination: VideoDetailView(session: session)) {
                        VideoThumbnailCard(session: session)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 32)
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "video.slash.fill")
                .font(.system(size: 52, weight: .light))
                .foregroundStyle(Color.kineticsPurple.opacity(0.4))

            Text("No Videos Yet")
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundStyle(.white)

            Text("Import a workout video to get\nAI-powered biomechanics analysis")
                .font(.subheadline)
                .foregroundStyle(Color.kineticsSubtext)
                .multilineTextAlignment(.center)

            Button {
                showPicker = true
            } label: {
                Label("Import Video", systemImage: "photo.on.rectangle.angled")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Color.kineticsBlue, in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.top, 4)

            Spacer()
        }
        .padding(.horizontal, 32)
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
                        .fill(isSelected ? Color.kineticsPurple : Color.kineticsDark)
                )
                .animation(.spring(duration: 0.2), value: isSelected)
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
        if secs < 60 { return "\(secs)s" }
        return "\(secs / 60)m \(secs % 60)s"
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            // Thumbnail
            if let data = session.thumbnailData,
               let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(height: 160)
                    .clipped()
            } else {
                Rectangle()
                    .fill(Color.kineticsDark)
                    .frame(height: 160)
                    .overlay(
                        Image(systemName: session.videoSport.systemImage)
                            .font(.system(size: 28, weight: .light))
                            .foregroundStyle(sportColor.opacity(0.5))
                    )
            }

            // Bottom gradient overlay
            LinearGradient(
                colors: [.clear, .black.opacity(0.72)],
                startPoint: .center,
                endPoint: .bottom
            )
            .frame(height: 80)

            // Bottom labels
            HStack {
                Text(durationText)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
                Spacer()
                Text(session.videoSport.rawValue)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(sportColor)
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 10)

            // Sport badge (top-right)
            VStack {
                HStack {
                    Spacer()
                    ZStack {
                        Circle()
                            .fill(sportColor.opacity(0.2))
                            .frame(width: 28, height: 28)
                        Image(systemName: session.videoSport.systemImage)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(sportColor)
                    }
                    .padding(8)
                }
                Spacer()
            }

            // Analyzing indicator
            if session.analysisStatus == .analyzing {
                ZStack {
                    Color.black.opacity(0.55)
                    VStack(spacing: 6) {
                        ProgressView()
                            .tint(Color.kineticsBlue)
                            .scaleEffect(0.9)
                        Text("Analyzing")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Color.kineticsBlue)
                    }
                }
            }
        }
        .frame(height: 160)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(sportColor.opacity(0.2), lineWidth: 0.75)
        )
    }
}

// MARK: - VideoDetailView

struct VideoDetailView: View {

    @Environment(\.dismiss) private var dismiss
    let session: VideoSession

    @State private var notes: String = ""
    @State private var showDeleteAlert = false

    private var sportColor: Color { session.videoSport.color }

    private var dateText: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .short
        return formatter.string(from: session.recordedAt)
    }

    private var confidenceText: String {
        "\(Int(session.confidence * 100))%"
    }

    var body: some View {
        ZStack {
            Color.kineticsBackground.ignoresSafeArea()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    // Thumbnail header
                    thumbnailHeader

                    VStack(alignment: .leading, spacing: 24) {
                        // Analysis results section
                        analysisSection

                        // Metrics section
                        if !session.metrics.isEmpty {
                            metricsSection
                        }

                        // Notes section
                        notesSection

                        // Filmed date
                        VStack(alignment: .leading, spacing: 4) {
                            sectionLabel("FILMED")
                            Text(dateText)
                                .font(.system(size: 14))
                                .foregroundStyle(.white.opacity(0.8))
                        }

                        // Delete button
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
                                        .fill(Color.red.opacity(0.1))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12)
                                                .strokeBorder(Color.red.opacity(0.3), lineWidth: 1)
                                        )
                                )
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 8)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 24)
                    .padding(.bottom, 40)
                }
            }
        }
        .navigationTitle(session.title.isEmpty ? "Video Analysis" : session.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.kineticsBackground, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .onAppear { notes = session.notes }
        .alert("Delete Video", isPresented: $showDeleteAlert) {
            Button("Delete", role: .destructive) {
                Task {
                    try? VideoRepository.shared.delete(session)
                    dismiss()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently remove the video and its analysis results.")
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
                Rectangle()
                    .fill(Color.kineticsDark)
                    .frame(height: 220)
                    .overlay(
                        Image(systemName: session.videoSport.systemImage)
                            .font(.system(size: 48, weight: .light))
                            .foregroundStyle(sportColor.opacity(0.4))
                    )
            }

            LinearGradient(
                colors: [.clear, Color.kineticsBackground],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 80)
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

                VStack(alignment: .leading, spacing: 4) {
                    Text(session.videoSport.rawValue)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.white)

                    HStack(spacing: 6) {
                        Text("Confidence")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.kineticsSubtext)

                        Text(confidenceText)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(sportColor)
                    }

                    if session.durationSeconds > 0 {
                        let secs = Int(session.durationSeconds)
                        let durText = secs < 60 ? "\(secs)s" : "\(secs / 60)m \(secs % 60)s"
                        Text(durText)
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

    // MARK: - Metrics section

    private var metricsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("METRICS")

            let sortedMetrics = session.metrics.sorted { $0.key < $1.key }
            let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(sortedMetrics, id: \.key) { key, value in
                    MetricPill(key: key, value: value, accentColor: sportColor)
                }
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
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.kineticsDark)
                )
                .lineLimit(3...6)
                .onChange(of: notes) { _, newValue in
                    session.notes = newValue
                    try? VideoRepository.shared.update(session)
                }
        }
    }

    // MARK: - Helpers

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Color.kineticsSubtext)
            .kerning(0.8)
    }
}

// MARK: - MetricPill

private struct MetricPill: View {
    let key: String
    let value: Double
    let accentColor: Color

    private var formattedKey: String {
        key
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }

    private var formattedValue: String {
        if key.hasSuffix("ratio") || key.hasSuffix("symmetry") || key.hasSuffix("confidence") {
            return String(format: "%.0f%%", value * 100)
        }
        if value == value.rounded() && value < 1000 {
            return String(Int(value))
        }
        return String(format: "%.2f", value)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(formattedKey)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color.kineticsSubtext)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Text(formattedValue)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(accentColor)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(accentColor.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(accentColor.opacity(0.15), lineWidth: 0.5)
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
        case .gym:         return "avg_wrist_velocity"
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

    private var formattedMetricKey: String {
        primaryMetricKey
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
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
                // Chart
                VStack(alignment: .leading, spacing: 12) {
                    Text(formattedMetricKey)
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
                                colors: [sportColor.opacity(0.3), sportColor.opacity(0.0)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .interpolationMethod(.catmullRom)
                    }
                    .chartXAxis {
                        AxisMarks(values: .automatic) { value in
                            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                                .foregroundStyle(.white.opacity(0.1))
                            AxisValueLabel(format: .dateTime.month().day())
                                .foregroundStyle(Color.kineticsSubtext)
                        }
                    }
                    .chartYAxis {
                        AxisMarks { value in
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

                // Session count summary
                HStack(spacing: 16) {
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

            Text("Record at least 2 \(sport.rawValue) sessions\nto see progress over time")
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
        guard chartData.count >= 2 else { return nil }
        let first = chartData.first!.value
        let last  = chartData.last!.value
        guard first > 0 else { return nil }
        return ((last - first) / first) * 100
    }

    private func loadSessions() async {
        isLoading = true
        defer { isLoading = false }
        do {
            sessions = try VideoRepository.shared.fetchBySport(userId: userId, sport: sport)
        } catch {
            // Non-critical; empty state handles the UI
        }
    }
}

// MARK: - VideoSport + Color

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
}
