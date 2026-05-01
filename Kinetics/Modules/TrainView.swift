import SwiftUI

// MARK: - TrainView

struct TrainView: View {

    @Environment(AppState.self) private var appState
    @State private var vm = TrainViewModel()

    private var uid: String {
        appState.authManager.currentUser?.uid ?? "preview-user"
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    headerSection
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                        .padding(.bottom, 20)

                    // Today's Focus hero card
                    todaysFocusCard
                        .padding(.horizontal, 16)
                        .padding(.bottom, 20)

                    // Recent sessions quick-launch strip
                    if !vm.recentSports.isEmpty {
                        recentSection
                            .padding(.bottom, 20)
                    }

                    sectionHeader("ALL MODULES")
                        .padding(.horizontal, 20)
                        .padding(.bottom, 12)

                    // Sport module cards
                    VStack(spacing: 12) {
                        ForEach(SportType.allCases, id: \.self) { sport in
                            NavigationLink(value: sport) {
                                TrainModuleCard(sport: sport)
                            }
                            .buttonStyle(ScaleButtonStyle())
                        }

                        // Video Library entry point
                        NavigationLink(destination: VideoLibraryView(userId: uid)) {
                            VideoLibraryTrainCard()
                        }
                        .buttonStyle(ScaleButtonStyle())
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 32)
                }
            }
            .background(Color.kineticsBackground)
            .navigationBarHidden(true)
            .navigationDestination(for: SportType.self) { sport in
                moduleView(for: sport)
            }
            .task {
                await vm.load(userId: uid)
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 5) {
                Text("TRAIN")
                    .font(.system(size: 32, weight: .black))
                    .tracking(6)
                    .foregroundStyle(.white)
                Text(vm.headerSubtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.38))
            }
            Spacer()
        }
    }

    // MARK: - Today's Focus Card

    private var todaysFocusCard: some View {
        let accent = Color.moduleColor(for: vm.focusSport)

        return NavigationLink(value: vm.focusSport) {
            ZStack(alignment: .bottomLeading) {
                // Base
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.kineticsDark)

                // Radial glow top-right (large icon area)
                RadialGradient(
                    colors: [accent.opacity(0.18), .clear],
                    center: .topTrailing,
                    startRadius: 0,
                    endRadius: 160
                )
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

                // Bottom fade
                LinearGradient(
                    colors: [.clear, accent.opacity(0.28)],
                    startPoint: .center,
                    endPoint: .bottom
                )
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

                // Border
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(accent.opacity(0.28), lineWidth: 0.75)

                // Large background icon (decorative)
                Image(systemName: vm.focusSport.systemImage)
                    .font(.system(size: 100, weight: .black))
                    .foregroundStyle(accent.opacity(0.07))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(.top, 8)
                    .padding(.trailing, 12)

                // Content
                VStack(alignment: .leading, spacing: 4) {
                    // "Today's Focus" badge
                    HStack(spacing: 5) {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(accent)
                        Text("TODAY'S FOCUS")
                            .font(.system(size: 9, weight: .bold))
                            .tracking(1.6)
                            .foregroundStyle(accent)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(accent.opacity(0.12))
                    .clipShape(Capsule())
                    .overlay(Capsule().strokeBorder(accent.opacity(0.28), lineWidth: 0.5))

                    Spacer().frame(height: 12)

                    // Module name
                    Text(vm.focusSport.displayName)
                        .font(.system(size: 24, weight: .black))
                        .foregroundStyle(.white)

                    // Tagline
                    Text(vm.focusSport.tagline)
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.50))
                        .padding(.top, 2)

                    Spacer().frame(height: 14)

                    // Start CTA
                    HStack(spacing: 6) {
                        Text("START SESSION")
                            .font(.system(size: 11, weight: .bold))
                            .tracking(1.5)
                        Image(systemName: "arrow.right")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .foregroundStyle(accent)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(accent.opacity(0.14))
                    .clipShape(Capsule())
                    .overlay(Capsule().strokeBorder(accent.opacity(0.30), lineWidth: 0.75))
                }
                .padding(20)
            }
            .frame(height: 200)
        }
        .buttonStyle(ScaleButtonStyle())
    }

    // MARK: - Recent Section

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("RECENTLY USED")
                .padding(.horizontal, 20)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(vm.recentSports, id: \.self) { sport in
                        NavigationLink(value: sport) {
                            RecentSportChip(sport: sport)
                        }
                        .buttonStyle(ScaleButtonStyle())
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    // MARK: - Helpers

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .tracking(2.5)
            .foregroundStyle(.white.opacity(0.38))
    }

    // MARK: - Module Navigation

    @ViewBuilder
    private func moduleView(for sport: SportType) -> some View {
        switch sport {
        case .striking:    StrikingView()
        case .grappling:   GrapplingView()
        case .ironTracker: IronTrackerView()
        case .wallBeta:    WallBetaView()
        }
    }
}

// MARK: - TrainViewModel

@Observable
@MainActor
final class TrainViewModel {

    // MARK: State

    /// The sport to feature as "Today's Focus" — rotates daily.
    var focusSport: SportType = .striking

    /// Up to 3 most recently used sports from session history.
    var recentSports: [SportType] = []

    // MARK: Computed

    var headerSubtitle: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        let day = formatter.string(from: Date())
        return "Good \(timeOfDayGreeting()), it's \(day)"
    }

    // MARK: Load

    func load(userId: String) async {
        // Determine "Today's Focus" by rotating through sports based on day-of-year
        let dayOfYear = Calendar.current.ordinality(of: .day, in: .year, for: Date()) ?? 1
        let allSports = SportType.allCases
        focusSport = allSports[dayOfYear % allSports.count]

        // Load recent sessions to populate the recently-used chip row
        if let sessions = try? await SessionRepository.shared.fetchSessions(for: userId, limit: 10) {
            var seen = Set<SportType>()
            var ordered: [SportType] = []
            for session in sessions {
                if seen.insert(session.sport).inserted {
                    ordered.append(session.sport)
                }
                if ordered.count == 3 { break }
            }
            recentSports = ordered
        }
    }

    // MARK: Private

    private func timeOfDayGreeting() -> String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 0..<12: return "morning"
        case 12..<17: return "afternoon"
        default: return "evening"
        }
    }
}

// MARK: - RecentSportChip

struct RecentSportChip: View {
    let sport: SportType
    private var accent: Color { Color.moduleColor(for: sport) }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: sport.systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(accent)
            Text(sport.displayName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(accent.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(accent.opacity(0.28), lineWidth: 0.75)
        )
    }
}

// MARK: - VideoLibraryTrainCard

struct VideoLibraryTrainCard: View {
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.kineticsPurple.opacity(0.14))
                    .frame(width: 56, height: 56)
                Image(systemName: "video.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(Color.kineticsPurple)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Video Library")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)

                Text("AI-powered biomechanics analysis")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.45))
                    .padding(.bottom, 6)

                Divider()
                    .background(.white.opacity(0.08))
                    .padding(.bottom, 6)

                ForEach([
                    "Auto sport classification",
                    "Frame-by-frame pose analysis",
                    "Progress tracking over time"
                ], id: \.self) { bullet in
                    HStack(spacing: 6) {
                        Circle().fill(Color.kineticsPurple).frame(width: 4, height: 4)
                        Text(bullet)
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.55))
                    }
                }

                HStack(spacing: 4) {
                    Text("OPEN LIBRARY")
                        .font(.system(size: 9, weight: .bold))
                        .tracking(1.8)
                        .foregroundStyle(Color.kineticsPurple)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Color.kineticsPurple)
                }
                .padding(.top, 8)
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .background(Color.kineticsDark)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.kineticsPurple.opacity(0.18), lineWidth: 0.75)
        )
    }
}

// MARK: - TrainModuleCard

struct TrainModuleCard: View {
    let sport: SportType
    private var accent: Color { Color.moduleColor(for: sport) }

    private var bullets: [String] {
        switch sport {
        case .striking:
            return ["Strike velocity in mph", "Kinematic chain score", "Hip-shoulder separation"]
        case .grappling:
            return ["Center of mass tracking", "Kuzushi index 0–100", "Base stability percentage"]
        case .ironTracker:
            return ["Bar path deviation in cm", "Velocity-based training speed", "Bilateral symmetry"]
        case .wallBeta:
            return ["Hip proximity to wall", "Hip sag event detection", "Dyno arc smoothness"]
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            // Icon
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(accent.opacity(0.14))
                    .frame(width: 56, height: 56)
                Image(systemName: sport.systemImage)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(accent)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(sport.displayName)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)

                Text(sport.tagline)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.45))
                    .padding(.bottom, 6)

                Divider()
                    .background(.white.opacity(0.08))
                    .padding(.bottom, 6)

                ForEach(bullets, id: \.self) { bullet in
                    HStack(spacing: 6) {
                        Circle().fill(accent).frame(width: 4, height: 4)
                        Text(bullet)
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.55))
                    }
                }

                HStack(spacing: 4) {
                    Text("START SESSION")
                        .font(.system(size: 9, weight: .bold))
                        .tracking(1.8)
                        .foregroundStyle(accent)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(accent)
                }
                .padding(.top, 8)
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .background(Color.kineticsDark)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(accent.opacity(0.18), lineWidth: 0.75)
        )
    }
}
