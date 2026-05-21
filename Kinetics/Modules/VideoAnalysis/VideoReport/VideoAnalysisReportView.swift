import SwiftUI
import SwiftData
import UIKit

// MARK: - VideoAnalysisReportView

/// The full-screen report presented after a video has been analysed.
///
/// Sections:
///   1. Video player + skeleton overlay (16:9, full-width)
///   2. Session info bar (sport badge, title, date, duration, subject)
///   3. Sport-specific metrics bento grid
///   4. AI coach panel (overview / coaching / drills with section picker)
///   5. Tip timeline (visible when activeSection == .coaching)
///   6. Cloud upload row (when not yet uploaded)
///
/// This view is pushed as a `NavigationLink` destination — it inherits
/// the parent `NavigationStack` and does NOT create its own.
struct VideoAnalysisReportView: View {

    // MARK: - Inputs

    let session: VideoSession
    let userId: String

    // MARK: - Environment

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    // MARK: - State

    @State private var vm: VideoReportViewModel
    @State private var showPaywall = false

    // MARK: - Subscription

    private var subscriptionManager: SubscriptionManager { SubscriptionManager.shared }

    // MARK: - Init

    init(session: VideoSession, userId: String) {
        self.session = session
        self.userId = userId
        self._vm = State(initialValue: VideoReportViewModel(session: session))
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            Color.kineticsBackground.ignoresSafeArea()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    videoSection
                    sessionInfoBar
                        .padding(.top, 12)
                        .padding(.horizontal, 16)
                    metricsGrid
                        .padding(.top, 20)
                        .padding(.horizontal, 16)
                    coachSection
                        .padding(.top, 20)
                        .padding(.horizontal, 16)
                    if vm.activeSection == .coaching,
                       let tips = vm.coachReport?.tips,
                       !tips.isEmpty {
                        tipTimeline(tips: tips)
                            .padding(.top, 16)
                            .padding(.horizontal, 16)
                    }
                    if session.cloudStorageURL.isEmpty {
                        cloudUploadRow
                            .padding(.top, 20)
                            .padding(.horizontal, 16)
                    }
                    Spacer(minLength: 48)
                }
            }
        }
        .navigationTitle(session.title.isEmpty ? "Analysis Report" : session.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.kineticsBackground, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    shareReport()
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .foregroundStyle(Color.kineticsSubtext)
                }
            }
        }
        .onAppear { vm.onAppear(modelContext: modelContext) }
        .onDisappear { vm.cleanup() }
        .sheet(isPresented: $showPaywall) {
            PaywallView(lockedFeature: "AI Coach Report")
        }
    }

    // MARK: - Section 1: Video Player

    private var videoSection: some View {
        GeometryReader { geo in
            let playerHeight = geo.size.width * (9.0 / 16.0)

            ZStack(alignment: .bottom) {
                // Video
                VideoPlayerView(player: vm.playerController.player)
                    .frame(height: playerHeight)
                    .clipped()

                // Skeleton overlay
                if vm.showSkeletonOverlay {
                    SkeletonOverlayView(
                        frames: vm.skeletonFrames,
                        currentTime: vm.playerController.currentTime,
                        sportColor: vm.sport.color,
                        showSubjectLabel: true
                    )
                    .frame(height: playerHeight)
                }

                // Gradient at bottom edge for controls legibility
                LinearGradient(
                    colors: [.clear, .black.opacity(0.72)],
                    startPoint: .center,
                    endPoint: .bottom
                )
                .frame(height: playerHeight * 0.45)

                // Controls overlay
                VStack(spacing: 0) {
                    HStack {
                        // Skeleton toggle pill — top-left
                        Button {
                            withAnimation(.spring(response: 0.22, dampingFraction: 0.75)) {
                                vm.showSkeletonOverlay.toggle()
                            }
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: vm.showSkeletonOverlay
                                      ? "person.and.background.dotted"
                                      : "person.slash")
                                .font(.system(size: 11, weight: .semibold))
                                Text(vm.showSkeletonOverlay ? "Skeleton On" : "Skeleton Off")
                                    .font(.system(size: 11, weight: .semibold))
                            }
                            .foregroundStyle(vm.showSkeletonOverlay
                                             ? vm.sport.color
                                             : Color.kineticsSubtext)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                Capsule()
                                    .fill(Color.black.opacity(0.6))
                                    .overlay(
                                        Capsule().strokeBorder(
                                            vm.showSkeletonOverlay
                                                ? vm.sport.color.opacity(0.45)
                                                : Color.white.opacity(0.1),
                                            lineWidth: 0.75
                                        )
                                    )
                            )
                        }
                        .buttonStyle(.plain)
                        .padding(12)

                        Spacer()

                        // Subject label badge — top-right
                        if !vm.subjectLabel.isEmpty && vm.subjectLabel != "Unknown" {
                            let isYou = vm.subjectLabel == "You"
                            Text(vm.subjectLabel)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(isYou ? Color.kineticsGreen : Color.kineticsAmber)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(
                                    Capsule()
                                        .fill(Color.black.opacity(0.6))
                                        .overlay(
                                            Capsule().strokeBorder(
                                                isYou
                                                    ? Color.kineticsGreen.opacity(0.4)
                                                    : Color.kineticsAmber.opacity(0.4),
                                                lineWidth: 0.75
                                            )
                                        )
                                )
                                .padding(12)
                        }
                    }

                    Spacer()

                    // Play/Pause button — centered
                    Button {
                        withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) {
                            vm.playerController.togglePlayPause()
                        }
                    } label: {
                        ZStack {
                            Circle()
                                .fill(Color.black.opacity(0.55))
                                .frame(width: 56, height: 56)
                            Image(
                                systemName: vm.playerController.isPlaying
                                    ? "pause.fill"
                                    : "play.fill"
                            )
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(.white)
                            .offset(x: vm.playerController.isPlaying ? 0 : 2)
                        }
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    // Progress scrubber bar at the very bottom
                    progressScrubber(totalWidth: geo.size.width, playerHeight: playerHeight)
                        .padding(.bottom, 8)
                }
                .frame(height: playerHeight)
            }
        }
        .aspectRatio(16.0 / 9.0, contentMode: .fit)
    }

    private func progressScrubber(totalWidth: CGFloat, playerHeight: CGFloat) -> some View {
        let progress = vm.playerController.duration > 0
            ? vm.playerController.currentTime / vm.playerController.duration
            : 0

        return GeometryReader { scrubGeo in
            ZStack(alignment: .leading) {
                // Track
                Capsule()
                    .fill(Color.white.opacity(0.2))
                    .frame(height: 2)

                // Fill
                Capsule()
                    .fill(vm.sport.color)
                    .frame(
                        width: max(0, min(scrubGeo.size.width * progress, scrubGeo.size.width)),
                        height: 2
                    )
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle().size(
                CGSize(width: scrubGeo.size.width, height: 20)
            ))
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let ratio = value.location.x / scrubGeo.size.width
                        let seekTo = ratio * vm.playerController.duration
                        vm.playerController.seek(to: seekTo)
                    }
            )
        }
        .frame(height: 20)
        .padding(.horizontal, 16)
    }

    // MARK: - Section 2: Session Info Bar

    private var sessionInfoBar: some View {
        HStack(spacing: 10) {
            // Sport badge pill
            HStack(spacing: 5) {
                Image(systemName: vm.sport.systemImage)
                    .font(.system(size: 11, weight: .bold))
                Text(vm.sport.rawValue)
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(vm.sport.color)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(vm.sport.color.opacity(0.12))
                    .overlay(
                        Capsule().strokeBorder(vm.sport.color.opacity(0.3), lineWidth: 0.75)
                    )
            )

            Spacer()

            // Duration
            if session.durationSeconds > 0 {
                let secs = Int(session.durationSeconds)
                let m = secs / 60
                let s = secs % 60
                HStack(spacing: 4) {
                    Image(systemName: "clock")
                        .font(.system(size: 11))
                    Text(m > 0 ? "\(m)m \(s)s" : "\(s)s")
                        .font(.system(size: 12))
                }
                .foregroundStyle(Color.kineticsSubtext)
            }

            // Date
            HStack(spacing: 4) {
                Image(systemName: "calendar")
                    .font(.system(size: 11))
                Text(session.recordedAt, format: .dateTime.month(.abbreviated).day().year())
                    .font(.system(size: 12))
            }
            .foregroundStyle(Color.kineticsSubtext)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.kineticsDark)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.06), lineWidth: 0.75)
                )
        )
    }

    // MARK: - Section 3: Metrics Grid

    private var metricsGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("METRICS")

            if vm.primaryMetrics.isEmpty {
                noMetricsPlaceholder
            } else {
                let columns = [
                    GridItem(.flexible(), spacing: 10),
                    GridItem(.flexible(), spacing: 10)
                ]

                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(vm.primaryMetrics, id: \.label) { metric in
                        metricCard(
                            label: metric.label,
                            value: metric.value,
                            unit: metric.unit
                        )
                    }
                }
            }
        }
    }

    private func metricCard(label: String, value: String, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(vm.sport.color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)

                if !unit.isEmpty {
                    Text(unit)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(vm.sport.color.opacity(0.65))
                        .padding(.bottom, 2)
                }
            }
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.75))
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.kineticsDark)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(vm.sport.color.opacity(0.04))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(vm.sport.color.opacity(0.25), lineWidth: 0.75)
                )
        )
    }

    private var noMetricsPlaceholder: some View {
        HStack(spacing: 10) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 20, weight: .light))
                .foregroundStyle(Color.kineticsSubtext.opacity(0.5))
            Text("No metrics available for this session.")
                .font(.system(size: 13))
                .foregroundStyle(Color.kineticsSubtext)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.kineticsDark)
        )
    }

    // MARK: - Section 4: AI Coach Panel

    @ViewBuilder
    private var coachSection: some View {
        if vm.hasCoachReport, let report = vm.coachReport {
            coachReportContent(report: report)
        } else {
            coachCallToAction
        }
    }

    private func coachReportContent(report: CoachReport) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionLabel("AI COACH REPORT")

            // Score ring + summary
            HStack(alignment: .top, spacing: 16) {
                scoreRing(score: report.overallScore)

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Overall Score")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.kineticsSubtext)
                        Spacer()
                        Text("\(report.overallScore)/100")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(vm.sport.color)
                    }

                    Text(report.summary)
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.85))
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.kineticsDark)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(vm.sport.color.opacity(0.2), lineWidth: 0.75)
                    )
            )

            // Section picker
            reportSectionPicker

            // Section content
            Group {
                switch vm.activeSection {
                case .overview:
                    overviewContent(report: report)
                case .coaching:
                    coachingContent(report: report)
                case .drills:
                    drillsContent(report: report)
                }
            }
            .animation(
                .spring(response: 0.3, dampingFraction: 0.8),
                value: vm.activeSection
            )
        }
    }

    private func scoreRing(score: Int) -> some View {
        ZStack {
            // Background track
            Circle()
                .stroke(Color.white.opacity(0.08), lineWidth: 5)

            // Fill arc
            Circle()
                .trim(from: 0, to: CGFloat(score) / 100.0)
                .stroke(
                    vm.sport.color,
                    style: StrokeStyle(lineWidth: 5, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            Text("\(score)")
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(vm.sport.color)
        }
        .frame(width: 60, height: 60)
    }

    private var reportSectionPicker: some View {
        HStack(spacing: 0) {
            ForEach(VideoReportViewModel.ReportSection.allCases, id: \.self) { section in
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        vm.activeSection = section
                    }
                } label: {
                    Text(section.rawValue)
                        .font(.system(size: 13, weight: vm.activeSection == section ? .semibold : .regular))
                        .foregroundStyle(vm.activeSection == section ? .black : Color.kineticsSubtext)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background {
                            if vm.activeSection == section {
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .fill(vm.sport.color)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.kineticsDark)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.07), lineWidth: 0.75)
                )
        )
    }

    private func overviewContent(report: CoachReport) -> some View {
        VStack(spacing: 10) {
            if !report.strengths.isEmpty {
                coachListCard(
                    title: "Strengths",
                    items: report.strengths,
                    iconName: "checkmark.circle.fill",
                    itemColor: Color.kineticsGreen
                )
            }
            if !report.improvements.isEmpty {
                coachListCard(
                    title: "Areas to Improve",
                    items: report.improvements,
                    iconName: "arrow.up.right.circle.fill",
                    itemColor: Color.kineticsAmber
                )
            }
        }
    }

    private func coachListCard(
        title: String,
        items: [String],
        iconName: String,
        itemColor: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.kineticsSubtext)
                .kerning(0.5)

            VStack(spacing: 8) {
                ForEach(items, id: \.self) { item in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: iconName)
                            .font(.system(size: 13))
                            .foregroundStyle(itemColor)
                            .frame(width: 18)
                            .padding(.top, 1)
                        Text(item)
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.85))
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.kineticsDark)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(itemColor.opacity(0.15), lineWidth: 0.75)
                )
        )
    }

    private func coachingContent(report: CoachReport) -> some View {
        VStack(spacing: 8) {
            if report.tips.isEmpty {
                emptyCoachingState(message: "No timestamped tips available for this session.")
            } else {
                ForEach(Array(report.tips.enumerated()), id: \.element.id) { index, tip in
                    tipRow(tip: tip, index: index)
                }
            }
        }
    }

    private func tipRow(tip: CoachReport.TimestampedTip, index: Int) -> some View {
        let severityColor = tipSeverityColor(tip.severity)
        let isSelected = vm.selectedTipIndex == index

        return Button {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                vm.selectedTipIndex = isSelected ? nil : index
            }
            vm.seekToTip(tip)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                // Timestamp badge
                VStack(spacing: 4) {
                    Text(formattedTimestamp(tip.timestampSeconds))
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(vm.sport.color)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(vm.sport.color.opacity(0.12))
                        )

                    Circle()
                        .fill(severityColor)
                        .frame(width: 6, height: 6)
                }

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Image(systemName: severityIcon(tip.severity))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(severityColor)

                        Text(tip.category.rawValue.capitalized)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(severityColor)
                            .kerning(0.3)

                        Spacer()
                    }

                    Text(tip.text)
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.88))
                        .fixedSize(horizontal: false, vertical: true)
                        .lineSpacing(2)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? vm.sport.color.opacity(0.08) : Color.kineticsDark)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(
                                isSelected
                                    ? vm.sport.color.opacity(0.4)
                                    : severityColor.opacity(0.15),
                                lineWidth: 0.75
                            )
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private func drillsContent(report: CoachReport) -> some View {
        VStack(spacing: 10) {
            if report.drillRecommendations.isEmpty {
                emptyCoachingState(message: "No drill recommendations available.")
            } else {
                ForEach(report.drillRecommendations) { drill in
                    drillRow(drill: drill)
                }
            }
        }
    }

    private func drillRow(drill: CoachReport.DrillRecommendation) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(vm.sport.color.opacity(0.12))
                    .frame(width: 44, height: 44)
                Image(systemName: "figure.run.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(vm.sport.color)
            }

            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(drill.name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                    Spacer()
                    HStack(spacing: 3) {
                        Image(systemName: "clock")
                            .font(.system(size: 10))
                        Text("\(drill.durationMinutes)m")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(Color.kineticsSubtext)
                }
                Text(drill.reason)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.65))
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(2)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.kineticsDark)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(vm.sport.color.opacity(0.18), lineWidth: 0.75)
                )
        )
    }

    private func emptyCoachingState(message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "info.circle")
                .foregroundStyle(Color.kineticsSubtext.opacity(0.6))
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(Color.kineticsSubtext)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.kineticsDark)
        )
    }

    // MARK: - Coach Call-to-Action (no report yet)

    private var coachCallToAction: some View {
        VStack(spacing: 20) {
            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.kineticsPurple.opacity(0.12))
                        .frame(width: 72, height: 72)
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 32, weight: .light))
                        .foregroundStyle(Color.kineticsPurple)
                }

                VStack(spacing: 6) {
                    Text("Get AI Coach Analysis")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)

                    Text("Claude will analyse your form and provide\npersonalised coaching based on your metrics.")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.kineticsSubtext)
                        .multilineTextAlignment(.center)
                        .lineSpacing(2)
                }
            }

            generateCoachButton
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.kineticsDark)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(Color.kineticsPurple.opacity(0.2), lineWidth: 0.75)
                )
        )
    }

    @ViewBuilder
    private var generateCoachButton: some View {
        if !AICoachService.isAPIKeyConfigured {
            // Show a clear, actionable message instead of a button that will
            // immediately fail with a cryptic error.
            HStack(spacing: 10) {
                Image(systemName: "key.slash")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.kineticsAmber)
                Text("API key not configured — add CLAUDE_API_KEY to enable AI coaching.")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.kineticsAmber.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Color.kineticsAmber.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.kineticsAmber.opacity(0.25), lineWidth: 0.75)
            )
        } else if vm.isGeneratingCoachReport {
            HStack(spacing: 10) {
                ProgressView()
                    .tint(.white)
                    .scaleEffect(0.85)
                Text("Generating report...")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.kineticsPurple.opacity(0.55))
            )
        } else if subscriptionManager.isPremium {
            // Premium path — run the analysis.
            VStack(spacing: 10) {
                Button {
                    Task {
                        await vm.generateCoachReport(userId: userId, modelContext: modelContext)
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "wand.and.stars")
                            .font(.system(size: 16, weight: .semibold))
                        Text("Analyse with AI Coach")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        LinearGradient(
                            colors: [Color.kineticsPurple, Color(hex: "#6D28D9")],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                    )
                }
                .buttonStyle(.plain)

                if let errorMsg = vm.coachReportError {
                    Text(errorMsg)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.kineticsRed)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        } else {
            // Free path — show locked state that opens the paywall.
            Button {
                showPaywall = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.kineticsAmber)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Unlock AI Coach Analysis")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white)
                        Text("Requires Kinetics Pro")
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.45))
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.3))
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.kineticsAmber.opacity(0.08))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Color.kineticsAmber.opacity(0.35), lineWidth: 1)
                        )
                )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Section 5: Tip Timeline

    private func tipTimeline(tips: [CoachReport.TimestampedTip]) -> some View {
        let duration = vm.playerController.duration > 0
            ? vm.playerController.duration
            : max(tips.map(\.timestampSeconds).max() ?? 1, 1)

        return VStack(alignment: .leading, spacing: 10) {
            sectionLabel("TIP TIMELINE")

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    // Track line
                    Capsule()
                        .fill(Color.white.opacity(0.12))
                        .frame(height: 2)
                        .frame(maxWidth: .infinity)

                    // Playhead indicator
                    if vm.playerController.duration > 0 {
                        let playRatio = vm.playerController.currentTime / vm.playerController.duration
                        let playX = max(0, min(playRatio * geo.size.width, geo.size.width))
                        Rectangle()
                            .fill(Color.white.opacity(0.7))
                            .frame(width: 1.5, height: 12)
                            .offset(x: playX - 0.75)
                            .offset(y: -5)
                    }

                    // Tip ticks
                    ForEach(Array(tips.enumerated()), id: \.element.id) { index, tip in
                        let ratio = min(tip.timestampSeconds / duration, 1.0)
                        let xPos = CGFloat(ratio) * geo.size.width
                        let tickColor = tipSeverityColor(tip.severity)

                        Button {
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                                vm.selectedTipIndex = (vm.selectedTipIndex == index) ? nil : index
                            }
                            vm.seekToTip(tip)
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(tickColor)
                                    .frame(
                                        width: vm.selectedTipIndex == index ? 14 : 10,
                                        height: vm.selectedTipIndex == index ? 14 : 10
                                    )

                                if vm.selectedTipIndex == index {
                                    Circle()
                                        .strokeBorder(.white, lineWidth: 1.5)
                                        .frame(width: 14, height: 14)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .offset(
                            x: xPos - (vm.selectedTipIndex == index ? 7 : 5),
                            y: -(vm.selectedTipIndex == index ? 7 : 5)
                        )
                    }
                }
                .frame(height: 2)
                .padding(.top, 10)
            }
            .frame(height: 32)

            // Selected tip preview
            if let selIdx = vm.selectedTipIndex, selIdx < tips.count {
                let tip = tips[selIdx]
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: severityIcon(tip.severity))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(tipSeverityColor(tip.severity))
                        .frame(width: 16)
                    Text(tip.text)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(tipSeverityColor(tips[selIdx].severity).opacity(0.1))
                )
                .transition(.opacity.combined(with: .offset(y: 4)))
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.kineticsDark)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.06), lineWidth: 0.75)
                )
        )
    }

    // MARK: - Section 6: Cloud Upload Row

    private var cloudUploadRow: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: vm.isUploadingToCloud ? "icloud.and.arrow.up.fill" : "icloud.and.arrow.up")
                    .font(.system(size: 20))
                    .foregroundStyle(
                        vm.isUploadingToCloud ? Color.kineticsBlue : Color.kineticsBlue.opacity(0.7)
                    )

                VStack(alignment: .leading, spacing: 3) {
                    Text(vm.isUploadingToCloud ? "Uploading…" : "Upload to Cloud")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.8))

                    if vm.isUploadingToCloud {
                        Text("\(Int(vm.cloudUploadProgress * 100))%")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.kineticsBlue)
                    } else {
                        Text("Access your analysis on all devices")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.kineticsSubtext)
                    }
                }

                Spacer()

                if vm.isUploadingToCloud {
                    ProgressView()
                        .tint(Color.kineticsBlue)
                        .scaleEffect(0.85)
                } else {
                    Button {
                        Task {
                            await vm.uploadToCloud(userId: userId, modelContext: modelContext)
                        }
                    } label: {
                        Text("Upload")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.kineticsBlue)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color.kineticsBlue.opacity(0.12))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .strokeBorder(Color.kineticsBlue.opacity(0.3), lineWidth: 0.75)
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                }
            }

            if vm.isUploadingToCloud {
                ProgressView(value: vm.cloudUploadProgress)
                    .tint(Color.kineticsBlue)
                    .frame(maxWidth: .infinity)
            }

            if let err = vm.cloudUploadError {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.kineticsRed)
                    Text(err)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.kineticsRed)
                    Spacer()
                    Button {
                        vm.cloudUploadError = nil
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Color.kineticsRed.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.kineticsDark)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.kineticsBlue.opacity(0.12), lineWidth: 0.75)
                )
        )
    }

    // MARK: - Shared UI Helpers

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Color.kineticsSubtext)
            .kerning(0.8)
    }

    // MARK: - Tip Display Helpers

    private func tipSeverityColor(
        _ severity: CoachReport.TimestampedTip.TipSeverity
    ) -> Color {
        switch severity {
        case .info:     return Color.kineticsBlue
        case .warning:  return Color.kineticsAmber
        case .critical: return Color.kineticsRed
        }
    }

    private func severityIcon(
        _ severity: CoachReport.TimestampedTip.TipSeverity
    ) -> String {
        switch severity {
        case .info:     return "info.circle.fill"
        case .warning:  return "exclamationmark.triangle.fill"
        case .critical: return "exclamationmark.2.circle.fill"
        }
    }

    private func formattedTimestamp(_ seconds: Double) -> String {
        let total = Int(max(0, seconds))
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }

    // MARK: - Share

    private func shareReport() {
        var items: [Any] = []

        // Include thumbnail if available
        if let data = session.thumbnailData, let img = UIImage(data: data) {
            items.append(img)
        }

        // Sport + title text
        let sportName = vm.sport.rawValue
        let title = session.title.isEmpty
            ? "Kinetics Analysis – \(sportName)"
            : session.title
        items.append(title)

        // Include score if available
        if let score = vm.coachReport?.overallScore {
            items.append("Coach Score: \(score)/100")
        }

        guard !items.isEmpty else { return }

        let vc = UIActivityViewController(activityItems: items, applicationActivities: nil)

        guard
            let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
            let root = scene.windows.first?.rootViewController
        else { return }

        if let popover = vc.popoverPresentationController {
            popover.sourceView = root.view
        }
        root.present(vc, animated: true)
    }
}
