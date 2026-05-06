import Foundation
import CoreLocation
import Combine

// MARK: - RouteDiscoveryViewModel

@MainActor
final class RouteDiscoveryViewModel: ObservableObject {
    @Published var mapKitRoutes: [MapKitRouteService.LoopRoute] = []
    @Published var stravaRoutes: [StravaRoute] = []
    @Published var communityRoutes: [KineticsRoute] = []
    @Published var isLoading = false

    @Published var targetDistance: Double = 5.0 {
        didSet {
            Task { await reloadMapKitRoutes() }
        }
    }

    // MARK: - Private

    /// Dedicated location service instance for route discovery.
    /// A one-shot location request is used; tracking is not started.
    private let locationService = LocationService()
    private var userLocation: CLLocationCoordinate2D?

    // MARK: - Public API

    func loadAll() async {
        isLoading = true
        defer { isLoading = false }

        // Resolve user location once before spawning parallel work.
        await resolveUserLocation()

        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.reloadMapKitRoutes() }
            group.addTask { await self.loadStravaRoutes() }
            group.addTask { await self.loadCommunityRoutes() }
        }
    }

    func reloadMapKitRoutes() async {
        guard let loc = userLocation else { return }
        mapKitRoutes = await MapKitRouteService.shared.suggestLoops(
            near: loc,
            targetDistanceKM: targetDistance
        )
    }

    func loadStravaRoutes() async {
        guard await StravaAuthService.shared.isAuthenticated else { return }
        do {
            stravaRoutes = try await StravaAPIService.shared.fetchAthleteRoutes()
        } catch {
            print("RouteDiscoveryViewModel: Strava routes error — \(error)")
        }
    }

    func loadCommunityRoutes() async {
        let coordinate = userLocation ?? CLLocationCoordinate2D(latitude: 0, longitude: 0)
        await RouteRepository.shared.fetchCommunityRoutes(near: coordinate)
        communityRoutes = RouteRepository.shared.communityRoutes
    }

    // MARK: - Private

    /// Requests location authorization and waits for the first valid fix.
    /// Falls back gracefully if permission is denied.
    private func resolveUserLocation() async {
        let granted = await locationService.requestAuthorization()
        guard granted else { return }

        // Start tracking briefly to capture the first location fix.
        await locationService.startTracking()
        defer { Task { await self.locationService.stopTracking() } }

        // Wait up to 5 seconds for a valid location.
        let stream = await locationService.locationStream
        let deadline = Date().addingTimeInterval(5)
        for await location in stream {
            userLocation = location.coordinate
            break // single fix is sufficient
        }
        _ = deadline // suppress unused warning
    }
}
