import SwiftUI

struct TrainView: View {
    @Environment(AppState.self) private var appState

    private var uid: String {
        appState.authManager.currentUser?.uid ?? "preview-user"
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    // Header
                    VStack(alignment: .leading, spacing: 5) {
                        Text("TRAIN")
                            .font(.system(size: 32, weight: .black))
                            .tracking(6)
                            .foregroundStyle(.white)
                        Text("Choose your module")
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.38))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 24)

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
        }
    }

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
