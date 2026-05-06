import SwiftUI

// MARK: - OnboardingView

/// Forced multi-step walkthrough shown on first launch.
/// Every step requires a deliberate interaction before the Continue button
/// becomes visible — the user cannot skip any step.
///
/// Step ordering mirrors `OnboardingStep`:
///   0 — Welcome
///   1 — Modules (tap a card to flip it)
///   2 — Video Analysis (tap a source icon)
///   3 — AI Coach (tap the example coaching card)
///   4 — Social Feed (tap the kudos button)
///   5 — Done (checkmark animation → Start Training)
@MainActor
struct OnboardingView: View {

    // MARK: - State

    @AppStorage("onboarding_complete") private var isComplete = false

    @State private var currentStep: OnboardingStep = .welcome
    @State private var stepUnlocked = false   // true once the required interaction fires
    @State private var animateIn = false

    // MARK: - Body

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // Ambient gradient glow that shifts with the current step
            stepGlowColor
                .opacity(0.07)
                .blur(radius: 90)
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 0.7), value: currentStep)

            VStack(spacing: 0) {
                // Progress bar at the top
                progressBar
                    .padding(.top, 16)
                    .padding(.horizontal, 24)

                // Main step content
                ZStack {
                    switch currentStep {
                    case .welcome:
                        WelcomeStep(onInteraction: unlock)
                            .transition(stepTransition)
                    case .modules:
                        ModulesStep(onInteraction: unlock)
                            .transition(stepTransition)
                    case .videoAnalysis:
                        VideoAnalysisStep(onInteraction: unlock)
                            .transition(stepTransition)
                    case .aiCoach:
                        AICoachStep(onInteraction: unlock)
                            .transition(stepTransition)
                    case .socialFeed:
                        SocialFeedStep(onInteraction: unlock)
                            .transition(stepTransition)
                    case .done:
                        DoneStep(onFinish: finish)
                            .transition(stepTransition)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .animation(
                    .spring(response: 0.48, dampingFraction: 0.82),
                    value: currentStep
                )

                // CTA — hidden on Done step (that step has its own button)
                if currentStep != .done {
                    ctaButton
                        .padding(.horizontal, 24)
                        .padding(.bottom, 52)
                }
            }
        }
        .onAppear { animateIn = true }
    }

    // MARK: - Progress Bar

    private var progressBar: some View {
        HStack(spacing: 5) {
            ForEach(OnboardingStep.allCases, id: \.rawValue) { step in
                let isPast    = step.rawValue < currentStep.rawValue
                let isCurrent = step == currentStep
                Capsule()
                    .fill(
                        isPast || isCurrent
                            ? Color.kineticsBlue
                            : Color.white.opacity(0.15)
                    )
                    .frame(maxWidth: .infinity)
                    .frame(height: isCurrent ? 4 : 3)
                    .animation(.spring(response: 0.4, dampingFraction: 0.75), value: currentStep)
            }
        }
        .padding(.bottom, 8)
    }

    // MARK: - CTA Button

    private var ctaButton: some View {
        Button { advance() } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        stepUnlocked
                            ? LinearGradient(
                                colors: [Color.kineticsBlue, Color(red: 0, green: 0.55, blue: 0.88)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                              )
                            : LinearGradient(
                                colors: [Color.white.opacity(0.1), Color.white.opacity(0.1)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                              )
                    )
                    .frame(height: 56)

                HStack(spacing: 8) {
                    Text(currentStep == .welcome ? "Let's Go" : "Continue")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(stepUnlocked ? .black : .white.opacity(0.35))

                    if currentStep != .welcome {
                        Image(systemName: "arrow.right")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(stepUnlocked ? .black : .white.opacity(0.35))
                    }
                }
            }
        }
        .disabled(!stepUnlocked)
        .animation(.easeInOut(duration: 0.25), value: stepUnlocked)
    }

    // MARK: - Helpers

    private var stepTransition: AnyTransition {
        .asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal:   .move(edge: .leading).combined(with: .opacity)
        )
    }

    private var stepGlowColor: Color {
        switch currentStep {
        case .welcome:       return Color.kineticsBlue
        case .modules:       return Color.kineticsPurple
        case .videoAnalysis: return Color.kineticsBlue
        case .aiCoach:       return Color.kineticsGreen
        case .socialFeed:    return Color.kineticsPurple
        case .done:          return Color.kineticsBlue
        }
    }

    private func unlock() {
        guard !stepUnlocked else { return }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
            stepUnlocked = true
        }
    }

    private func advance() {
        guard stepUnlocked else { return }
        guard let next = OnboardingStep(rawValue: currentStep.rawValue + 1) else { return }
        withAnimation(.spring(response: 0.48, dampingFraction: 0.82)) {
            currentStep  = next
            stepUnlocked = (next == .welcome)   // welcome is always unlocked
        }
    }

    private func finish() {
        isComplete = true
    }
}

// MARK: - Step 1: Welcome

private struct WelcomeStep: View {

    let onInteraction: () -> Void

    @State private var appeared = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Logo mark — large bold wordmark
            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.kineticsBlue.opacity(0.12))
                        .frame(width: 120, height: 120)
                    Circle()
                        .fill(Color.kineticsBlue.opacity(0.06))
                        .frame(width: 160, height: 160)
                    Image(systemName: "figure.run.circle.fill")
                        .font(.system(size: 68, weight: .semibold))
                        .foregroundStyle(Color.kineticsBlue)
                }
                .scaleEffect(appeared ? 1.0 : 0.6)
                .opacity(appeared ? 1 : 0)
                .animation(.spring(response: 0.65, dampingFraction: 0.6).delay(0.05), value: appeared)

                Text("KINETICS")
                    .font(.system(size: 44, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .tracking(6)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 16)
                    .animation(.spring(response: 0.55, dampingFraction: 0.75).delay(0.18), value: appeared)

                Text("Your AI Sports Performance Coach")
                    .font(.system(size: 17, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.kineticsBlue)
                    .multilineTextAlignment(.center)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 12)
                    .animation(.easeOut(duration: 0.45).delay(0.28), value: appeared)
            }
            .padding(.bottom, 36)

            // Description
            Text("Kinetics uses Apple's Vision Framework to track 19 body joints in real-time — measuring velocity, posture, and kinetic chain efficiency across four elite sport modules. Built-in GPS tracking logs every run, ride, hike, and walk.")
                .font(.system(size: 15, design: .rounded))
                .foregroundStyle(.white.opacity(0.55))
                .multilineTextAlignment(.center)
                .lineSpacing(5)
                .padding(.horizontal, 32)
                .opacity(appeared ? 1 : 0)
                .animation(.easeOut(duration: 0.5).delay(0.38), value: appeared)

            Spacer()
        }
        .onAppear {
            appeared = true
            // Welcome is auto-unlocked — no required tap
            Task {
                try? await Task.sleep(for: .seconds(0.1))
                await MainActor.run { onInteraction() }
            }
        }
    }
}

// MARK: - Step 2: Modules

private struct ModulesStep: View {

    let onInteraction: () -> Void

    @State private var flippedModule: SportType?
    @State private var pulseActive = false

    private let modules: [SportType] = [.striking, .grappling, .ironTracker, .wallBeta]

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 8) {
                Text("FOUR SPORT MODULES")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(3)
                    .foregroundStyle(Color.kineticsPurple)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(Color.kineticsPurple.opacity(0.14))
                    .clipShape(Capsule())

                Text("Tap any card to see what it tracks.")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                if flippedModule == nil {
                    Text("Each module uses a shared Vision engine for real-time biomechanics analysis.")
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.45))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28)
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 20)

            // 2×2 grid
            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)],
                spacing: 14
            ) {
                ForEach(modules, id: \.self) { sport in
                    ModuleFlipCard(
                        sport: sport,
                        isFlipped: flippedModule == sport,
                        pulseActive: pulseActive && flippedModule == nil
                    ) {
                        withAnimation(.spring(response: 0.55, dampingFraction: 0.7)) {
                            flippedModule = sport
                        }
                        onInteraction()
                    }
                }
            }
            .padding(.horizontal, 20)

            Spacer()
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                pulseActive = true
            }
        }
    }
}

// MARK: ModuleFlipCard

private struct ModuleFlipCard: View {
    let sport: SportType
    let isFlipped: Bool
    let pulseActive: Bool
    let onTap: () -> Void

    @State private var rotation: Double = 0

    var body: some View {
        ZStack {
            // Front face
            cardFront
                .opacity(rotation < 90 ? 1 : 0)

            // Back face
            cardBack
                .opacity(rotation >= 90 ? 1 : 0)
                .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
        }
        .rotation3DEffect(.degrees(rotation), axis: (x: 0, y: 1, z: 0))
        .onTapGesture { onTap() }
        .onChange(of: isFlipped) { _, flipped in
            withAnimation(.spring(response: 0.55, dampingFraction: 0.7)) {
                rotation = flipped ? 180 : 0
            }
        }
    }

    // MARK: Front

    private var cardFront: some View {
        let accent = Color(hex: sport.accentColor)
        return VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(accent.opacity(0.14))
                    .frame(width: 52, height: 52)
                Image(systemName: sport.systemImage)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(accent)
            }

            Text(sport.displayName)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)

            Text(sport.tagline)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.5))
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .frame(height: 148)
        .background(Color.kineticsDark)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(
                    accent.opacity(pulseActive ? 0.65 : 0.22),
                    lineWidth: pulseActive ? 1.5 : 1
                )
                .animation(
                    .easeInOut(duration: 1.1).repeatForever(autoreverses: true),
                    value: pulseActive
                )
        )
    }

    // MARK: Back

    private var cardBack: some View {
        let accent = Color(hex: sport.accentColor)
        return VStack(alignment: .leading, spacing: 6) {
            Text("TRACKS")
                .font(.system(size: 9, weight: .black))
                .tracking(2.5)
                .foregroundStyle(accent)
                .padding(.bottom, 2)

            ForEach(sport.keyMetrics, id: \.self) { metric in
                HStack(spacing: 6) {
                    Circle()
                        .fill(accent)
                        .frame(width: 4, height: 4)
                    Text(metric)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 148)
        .background(accent.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(accent.opacity(0.5), lineWidth: 1)
        )
    }
}

// MARK: SportType + Key Metrics (onboarding)

private extension SportType {
    var keyMetrics: [String] {
        switch self {
        case .striking:    return ["Strike velocity (m/s)", "Hip-shoulder separation", "Kinetic chain order", "Reset time"]
        case .grappling:   return ["Centre of mass vs. base", "Kuzushi spine angle", "Hip elevation (BJJ)", "Postural breakdown"]
        case .ironTracker: return ["Bar path trace", "VBT velocity (m/s)", "Bilateral symmetry", "Butt wink detection"]
        case .wallBeta:    return ["Hip-to-wall proximity", "Sag detection", "Dyno trajectory arc", "Time per hold"]
        }
    }
}

// MARK: - Step 3: Video Analysis

private struct VideoAnalysisStep: View {

    let onInteraction: () -> Void

    @State private var tappedSource: String?
    @State private var shimmerOffset: CGFloat = -200

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 28) {
                // Camera icon with shimmer
                ZStack {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(Color.kineticsBlue.opacity(0.1))
                        .frame(width: 120, height: 120)

                    // Shimmer overlay
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [.clear, Color.kineticsBlue.opacity(0.3), .clear],
                                startPoint: .init(x: 0, y: 0.5),
                                endPoint: .init(x: 1, y: 0.5)
                            )
                        )
                        .frame(width: 60, height: 120)
                        .offset(x: shimmerOffset)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))

                    Image(systemName: "video.fill")
                        .font(.system(size: 52, weight: .semibold))
                        .foregroundStyle(Color.kineticsBlue)
                }
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))

                VStack(spacing: 10) {
                    Text("Analyse Any Workout Video")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)

                    Text("Import any workout video — we'll analyse your technique with computer vision.")
                        .font(.system(size: 15))
                        .foregroundStyle(.white.opacity(0.55))
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                        .padding(.horizontal, 24)
                }

                // Source buttons — tap one to unlock Continue
                HStack(spacing: 16) {
                    SourceButton(
                        icon: "camera.fill",
                        label: "Live Session",
                        accent: Color.kineticsBlue,
                        isTapped: tappedSource == "live"
                    ) {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.65)) {
                            tappedSource = "live"
                        }
                        onInteraction()
                    }

                    SourceButton(
                        icon: "photo.on.rectangle.angled",
                        label: "Upload Video",
                        accent: Color.kineticsPurple,
                        isTapped: tappedSource == "upload"
                    ) {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.65)) {
                            tappedSource = "upload"
                        }
                        onInteraction()
                    }
                }
                .padding(.horizontal, 36)
            }

            Spacer()
        }
        .onAppear {
            withAnimation(.linear(duration: 1.6).repeatForever(autoreverses: false)) {
                shimmerOffset = 200
            }
        }
    }
}

private struct SourceButton: View {
    let icon: String
    let label: String
    let accent: Color
    let isTapped: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(isTapped ? accent : accent.opacity(0.14))
                        .frame(width: 60, height: 60)
                        .scaleEffect(isTapped ? 1.08 : 1.0)
                        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isTapped)
                    Image(systemName: icon)
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(isTapped ? .black : accent)
                }

                Text(label)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.75))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(accent.opacity(0.07))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isTapped ? accent : accent.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Step 4: AI Coach

private struct AICoachStep: View {

    let onInteraction: () -> Void

    @State private var isExpanded = false
    @State private var pulseActive = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    Text("AI COACH")
                        .font(.system(size: 11, weight: .bold))
                        .tracking(3)
                        .foregroundStyle(Color.kineticsGreen)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(Color.kineticsGreen.opacity(0.14))
                        .clipShape(Capsule())

                    Text("Personalised Technique Feedback")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)

                    Text("After every session, your AI Coach gives you precision technique feedback. Tap the example report to see more.")
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.5))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }

                // Example coaching card — tap to expand and unlock Continue
                Button {
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.7)) {
                        isExpanded.toggle()
                    }
                    onInteraction()
                } label: {
                    coachCard
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 20)
            }

            Spacer()
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                pulseActive = true
            }
        }
    }

    private var coachCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(Color.kineticsGreen.opacity(0.16))
                        .frame(width: 38, height: 38)
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color.kineticsGreen)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("AI Coach Report")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                    Text("Striking Clinic • Today")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.45))
                }
                Spacer()
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.3))
            }

            // Headline finding — always visible
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.kineticsGreen)
                    .frame(width: 20)
                Text("Your hip-shoulder separation averaged **42°**. Rotating hips first before shoulders increases punch velocity by up to **30%**.")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.8))
                    .fixedSize(horizontal: false, vertical: true)
            }

            if isExpanded {
                Divider().background(.white.opacity(0.07))

                VStack(alignment: .leading, spacing: 10) {
                    CoachFinding(
                        icon: "bolt.fill",
                        color: Color.kineticsBlue,
                        text: "Peak strike velocity: **8.3 m/s** — elite threshold is 10+ m/s. Focus on hip drive."
                    )
                    CoachFinding(
                        icon: "exclamationmark.triangle.fill",
                        color: Color.kineticsAmber,
                        text: "Guard drops on **3 of 12 crosses** — left hand trails behind the hip rotation."
                    )
                    CoachFinding(
                        icon: "checkmark.circle.fill",
                        color: Color.kineticsGreen,
                        text: "Reset time improved **18%** vs. last session. Stance width is consistent."
                    )
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(18)
        .background(Color.kineticsDark)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(
                    Color.kineticsGreen.opacity(pulseActive ? 0.55 : 0.18),
                    lineWidth: 1.5
                )
                .animation(
                    .easeInOut(duration: 1.2).repeatForever(autoreverses: true),
                    value: pulseActive
                )
        )
    }
}

private struct CoachFinding: View {
    let icon: String
    let color: Color
    let text: LocalizedStringKey

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(color)
                .frame(width: 20)
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.72))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Step 5: Social Feed

private struct SocialFeedStep: View {

    let onInteraction: () -> Void

    @State private var kudosBurst = false
    @State private var kudosCount = 12
    @State private var hasTappedKudos = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    Text("COMMUNITY")
                        .font(.system(size: 11, weight: .bold))
                        .tracking(3)
                        .foregroundStyle(Color.kineticsPurple)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(Color.kineticsPurple.opacity(0.14))
                        .clipShape(Capsule())

                    Text("Train With Others")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)

                    Text("Share sessions, give kudos, challenge friends. Tap the thumbs up to give kudos.")
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.5))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28)
                }

                // Mock feed card
                feedCard
                    .padding(.horizontal, 20)
            }

            Spacer()
        }
    }

    private var feedCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Author row
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.kineticsBlue, Color.kineticsPurple],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 40, height: 40)
                    Text("A")
                        .font(.system(size: 16, weight: .black))
                        .foregroundStyle(.black)
                }

                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text("Alex Guerrero")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                        Text("• Striking Clinic")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.kineticsRed.opacity(0.8))
                    }
                    Text("2 hours ago")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.38))
                }
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 12)

            Divider().background(.white.opacity(0.06))

            // Session metrics
            HStack(spacing: 0) {
                FeedMetricTile(label: "VELOCITY", value: "9.1", unit: "m/s")
                Divider().background(.white.opacity(0.08)).frame(height: 36)
                FeedMetricTile(label: "STRIKES", value: "58", unit: "")
                Divider().background(.white.opacity(0.08)).frame(height: 36)
                FeedMetricTile(label: "SYMMETRY", value: "96", unit: "%")
            }
            .padding(.vertical, 14)

            Divider().background(.white.opacity(0.06))

            // Kudos row
            HStack(spacing: 16) {
                // Kudos button with burst
                ZStack {
                    Button {
                        guard !hasTappedKudos else { return }
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.5)) {
                            kudosBurst = true
                            kudosCount += 1
                            hasTappedKudos = true
                        }
                        onInteraction()
                        Task {
                            try? await Task.sleep(for: .seconds(0.5))
                            await MainActor.run {
                                withAnimation(.easeOut(duration: 0.3)) {
                                    kudosBurst = false
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: hasTappedKudos ? "hand.thumbsup.fill" : "hand.thumbsup")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(hasTappedKudos ? Color.kineticsBlue : .white.opacity(0.55))
                                .scaleEffect(kudosBurst ? 1.35 : 1.0)
                                .animation(.spring(response: 0.3, dampingFraction: 0.5), value: kudosBurst)
                            Text("\(kudosCount)")
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundStyle(hasTappedKudos ? Color.kineticsBlue : .white.opacity(0.55))
                                .contentTransition(.numericText())
                        }
                    }
                    .buttonStyle(.plain)

                    // Burst particles
                    if kudosBurst {
                        ForEach(0..<6, id: \.self) { i in
                            Image(systemName: "plus")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(Color.kineticsBlue)
                                .offset(
                                    x: CGFloat.random(in: -28...28),
                                    y: CGFloat.random(in: -28...8)
                                )
                                .opacity(kudosBurst ? 0 : 1)
                                .animation(
                                    .easeOut(duration: 0.45).delay(Double(i) * 0.04),
                                    value: kudosBurst
                                )
                        }
                    }
                }

                HStack(spacing: 6) {
                    Image(systemName: "bubble.left")
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.38))
                    Text("4")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.38))
                }

                Spacer()

                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.38))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
        .background(Color.kineticsDark)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.white.opacity(0.07), lineWidth: 1)
        )
    }
}

private struct FeedMetricTile: View {
    let label: String
    let value: String
    let unit: String

    var body: some View {
        VStack(spacing: 2) {
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 20, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                if !unit.isEmpty {
                    Text(unit)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .tracking(1.5)
                .foregroundStyle(.white.opacity(0.38))
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Step 6: Done

private struct DoneStep: View {

    let onFinish: () -> Void

    @State private var drawProgress: CGFloat = 0
    @State private var circleScale: CGFloat = 0.5
    @State private var circleOpacity: CGFloat = 0
    @State private var textOpacity: CGFloat = 0
    @State private var buttonOpacity: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 32) {
                // Animated checkmark
                ZStack {
                    Circle()
                        .fill(Color.kineticsBlue.opacity(0.1))
                        .frame(width: 130, height: 130)
                        .scaleEffect(circleScale)
                        .opacity(circleOpacity)

                    Circle()
                        .stroke(Color.kineticsBlue.opacity(0.25), lineWidth: 2)
                        .frame(width: 130, height: 130)
                        .scaleEffect(circleScale)
                        .opacity(circleOpacity)

                    // Checkmark drawn via Canvas
                    Canvas { context, size in
                        let w = size.width
                        let h = size.height

                        var path = Path()
                        path.move(to:    CGPoint(x: w * 0.22, y: h * 0.50))
                        path.addLine(to: CGPoint(x: w * 0.42, y: h * 0.72))
                        path.addLine(to: CGPoint(x: w * 0.78, y: h * 0.28))

                        let trimmed = path.trimmedPath(from: 0, to: drawProgress)

                        context.stroke(
                            trimmed,
                            with: .color(Color.kineticsBlue),
                            style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round)
                        )
                    }
                    .frame(width: 80, height: 80)
                    .opacity(circleOpacity)
                }

                VStack(spacing: 10) {
                    Text("You're Ready.")
                        .font(.system(size: 34, weight: .black, design: .rounded))
                        .foregroundStyle(.white)

                    Text("Your AI coach is set up and ready to analyse your movement. Time to train.")
                        .font(.system(size: 15))
                        .foregroundStyle(.white.opacity(0.55))
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                        .padding(.horizontal, 32)
                }
                .opacity(textOpacity)

                // Start Training button
                Button(action: onFinish) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [Color.kineticsBlue, Color(red: 0, green: 0.55, blue: 0.88)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(height: 56)

                        HStack(spacing: 8) {
                            Text("Start Training")
                                .font(.system(size: 17, weight: .bold, design: .rounded))
                                .foregroundStyle(.black)
                            Image(systemName: "arrow.right")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(.black)
                        }
                    }
                }
                .padding(.horizontal, 24)
                .opacity(buttonOpacity)
            }

            Spacer()
        }
        .onAppear { runEntryAnimation() }
    }

    private func runEntryAnimation() {
        withAnimation(.spring(response: 0.55, dampingFraction: 0.65).delay(0.1)) {
            circleScale   = 1.0
            circleOpacity = 1.0
        }
        withAnimation(.linear(duration: 0.55).delay(0.45)) {
            drawProgress = 1.0
        }
        withAnimation(.easeOut(duration: 0.4).delay(0.85)) {
            textOpacity = 1.0
        }
        withAnimation(.easeOut(duration: 0.4).delay(1.1)) {
            buttonOpacity = 1.0
        }
    }
}

// MARK: - Preview

#Preview {
    OnboardingView()
}
