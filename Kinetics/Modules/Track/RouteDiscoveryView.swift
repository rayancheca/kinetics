import SwiftUI
import MapKit

// MARK: - RouteDiscoveryView

struct RouteDiscoveryView: View {
    @StateObject private var viewModel = RouteDiscoveryViewModel()
    @State private var selectedTab: RouteTab = .mapkit

    enum RouteTab: String, CaseIterable {
        case mapkit = "Suggested"
        case strava = "Strava"
        case community = "Community"
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Route Source", selection: $selectedTab) {
                ForEach(RouteTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            switch selectedTab {
            case .mapkit:
                MapKitRoutesSection(viewModel: viewModel)
            case .strava:
                StravaRoutesSection(viewModel: viewModel)
            case .community:
                CommunityRoutesSection(viewModel: viewModel)
            }
        }
        .navigationTitle("Discover Routes")
        .navigationBarTitleDisplayMode(.large)
        .task { await viewModel.loadAll() }
    }
}

// MARK: - MapKitRoutesSection

struct MapKitRoutesSection: View {
    @ObservedObject var viewModel: RouteDiscoveryViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                HStack {
                    Text("Loop routes near you")
                        .font(.system(.subheadline, design: .rounded, weight: .medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Menu {
                        ForEach([3.0, 5.0, 8.0, 10.0, 15.0], id: \.self) { km in
                            Button("\(Int(km)) km") {
                                viewModel.targetDistance = km
                            }
                        }
                    } label: {
                        Label("\(Int(viewModel.targetDistance)) km", systemImage: "slider.horizontal.3")
                            .font(.system(.caption, design: .rounded, weight: .semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.kineticsBlue.opacity(0.15), in: Capsule())
                            .foregroundStyle(Color.kineticsBlue)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)

                if viewModel.isLoading && viewModel.mapKitRoutes.isEmpty {
                    ProgressView()
                        .padding(.top, 40)
                } else if viewModel.mapKitRoutes.isEmpty {
                    ContentUnavailableView(
                        "Generating routes…",
                        systemImage: "map",
                        description: Text("Allow location access to suggest loop routes")
                    )
                    .padding(.top, 40)
                } else {
                    ForEach(viewModel.mapKitRoutes, id: \.name) { route in
                        RouteCard(
                            name: route.name,
                            distance: String(format: "%.1f km", route.distance / 1000),
                            duration: "\(route.estimatedMinutes) min",
                            badge: "MapKit",
                            badgeColor: .blue,
                            icon: "map.fill"
                        )
                    }
                }
            }
            .padding(.top, 4)
        }
    }
}

// MARK: - StravaRoutesSection

struct StravaRoutesSection: View {
    @ObservedObject var viewModel: RouteDiscoveryViewModel
    @ObservedObject private var strava = StravaAuthService.shared

    var body: some View {
        if strava.isAuthenticated {
            authenticatedView
        } else {
            connectView
        }
    }

    // MARK: Authenticated state

    private var authenticatedView: some View {
        ScrollView {
            VStack(spacing: 12) {
                if let athlete = strava.athleteProfile {
                    athleteHeader(athlete)
                }

                if viewModel.stravaRoutes.isEmpty {
                    ContentUnavailableView(
                        "No routes yet",
                        systemImage: "figure.run",
                        description: Text("Create routes in Strava to see them here")
                    )
                    .padding(.top, 20)
                } else {
                    ForEach(viewModel.stravaRoutes) { route in
                        RouteCard(
                            name: route.name,
                            distance: route.formattedDistance,
                            duration: route.formattedTime,
                            badge: route.activityTypeName,
                            badgeColor: route.activityTypeName == "Run" ? .kineticsGreen : .kineticsBlue,
                            icon: route.activityTypeName == "Run" ? "figure.run" : "bicycle"
                        )
                    }
                }
            }
            .padding(.top, 4)
        }
    }

    private func athleteHeader(_ athlete: StravaAthlete) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "person.circle.fill")
                .font(.title2)
                .foregroundStyle(Color(red: 0.98, green: 0.38, blue: 0.16))
            VStack(alignment: .leading, spacing: 2) {
                Text("\(athlete.firstname) \(athlete.lastname)")
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                Text(athlete.city ?? "Strava Connected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Disconnect") {
                strava.disconnect()
            }
            .font(.caption)
            .foregroundStyle(.red)
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16)
    }

    // MARK: Unauthenticated state

    private var connectView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "figure.run")
                .font(.system(size: 48))
                .foregroundStyle(Color(red: 0.98, green: 0.38, blue: 0.16))

            VStack(spacing: 8) {
                Text("Connect Strava")
                    .font(.system(.title2, design: .rounded, weight: .bold))
                Text("Access your Strava routes, starred segments, and leaderboards directly in Kinetics")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button {
                Task { try? await strava.authenticate() }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "figure.run")
                    Text("Connect with Strava")
                        .font(.system(.body, design: .rounded, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color(red: 0.98, green: 0.38, blue: 0.16))
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .padding(.horizontal, 32)

            Spacer()
        }
        .padding(.horizontal, 24)
    }
}

// MARK: - CommunityRoutesSection

struct CommunityRoutesSection: View {
    @ObservedObject var viewModel: RouteDiscoveryViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                if viewModel.communityRoutes.isEmpty {
                    ContentUnavailableView(
                        "No community routes yet",
                        systemImage: "person.3",
                        description: Text("Be the first to share a route with the Kinetics community")
                    )
                    .padding(.top, 40)
                } else {
                    ForEach(viewModel.communityRoutes) { route in
                        CommunityRouteCard(route: route) {
                            Task {
                                // TODO: Replace with actual authenticated user UID
                                await RouteRepository.shared.kudosRoute(route.id, uid: "currentUID")
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
        }
    }
}

// MARK: - RouteCard

struct RouteCard: View {
    let name: String
    let distance: String
    let duration: String
    let badge: String
    let badgeColor: Color
    let icon: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(badgeColor)
                .frame(width: 42, height: 42)
                .background(badgeColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 4) {
                Text(name)
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .lineLimit(1)
                HStack(spacing: 8) {
                    Label(distance, systemImage: "ruler")
                    Label(duration, systemImage: "clock")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            Text(badge)
                .font(.system(.caption2, design: .rounded, weight: .bold))
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(badgeColor.opacity(0.15), in: Capsule())
                .foregroundStyle(badgeColor)
        }
        .padding()
        .background(Color(hex: "141414"), in: RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, 16)
    }
}

// MARK: - CommunityRouteCard

struct CommunityRouteCard: View {
    let route: KineticsRoute
    let onKudos: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(route.name)
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                Spacer()
                Text(route.formattedDistance)
                    .font(.system(.caption, design: .rounded, weight: .bold))
                    .foregroundStyle(Color.kineticsBlue)
            }

            Text("by \(route.creatorDisplayName)")
                .font(.caption)
                .foregroundStyle(.secondary)

            if !route.tags.isEmpty {
                HStack(spacing: 6) {
                    ForEach(route.tags.prefix(3), id: \.self) { tag in
                        Text(tag)
                            .font(.system(.caption2, design: .rounded))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.ultraThinMaterial, in: Capsule())
                    }
                }
            }

            HStack {
                Button(action: onKudos) {
                    Label("\(route.kudosCount)", systemImage: "heart")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)

                Spacer()

                Button("Use Route") {}
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .foregroundStyle(Color.kineticsBlue)
            }
        }
        .padding()
        .background(Color(hex: "141414"), in: RoundedRectangle(cornerRadius: 14))
    }
}
