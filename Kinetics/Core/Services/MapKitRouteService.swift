import Foundation
@preconcurrency import MapKit
import CoreLocation

// MARK: - MapKitRouteService

actor MapKitRouteService {
    static let shared = MapKitRouteService()

    // MARK: - LoopRoute

    struct LoopRoute: @unchecked Sendable {
        let name: String
        let distance: Double        // metres
        let estimatedMinutes: Int
        let waypoints: [CLLocationCoordinate2D]
        let polyline: MKPolyline
    }

    // MARK: - Public API

    /// Generates up to 3 loop route suggestions centred on `center`.
    ///
    /// Routes are computed with cardinal offsets scaled to approximately
    /// `targetDistanceKM` kilometres and returned sorted by ascending distance.
    func suggestLoops(
        near center: CLLocationCoordinate2D,
        targetDistanceKM: Double
    ) async -> [LoopRoute] {
        let cardinalOffsets = generateCardinalWaypoints(from: center, distanceKM: targetDistanceKM)

        var routes: [LoopRoute] = []
        for (name, waypoints) in cardinalOffsets {
            if let route = buildRoute(name: name, waypoints: waypoints) {
                routes.append(route)
            }
        }

        return routes.sorted { $0.distance < $1.distance }
    }

    // MARK: - Private

    /// Generates three sets of waypoints (North, East, South loops) scaled to `distanceKM`.
    private func generateCardinalWaypoints(
        from center: CLLocationCoordinate2D,
        distanceKM: Double
    ) -> [(String, [CLLocationCoordinate2D])] {
        // 1 degree latitude ≈ 111 km
        let deg = distanceKM / 111.0
        let halfDeg = deg / 2.2

        return [
            ("North Loop", [
                center,
                CLLocationCoordinate2D(
                    latitude: center.latitude + deg * 0.4,
                    longitude: center.longitude - halfDeg * 0.5
                ),
                CLLocationCoordinate2D(
                    latitude: center.latitude + deg * 0.6,
                    longitude: center.longitude
                ),
                CLLocationCoordinate2D(
                    latitude: center.latitude + deg * 0.4,
                    longitude: center.longitude + halfDeg * 0.5
                ),
                center
            ]),
            ("East Loop", [
                center,
                CLLocationCoordinate2D(
                    latitude: center.latitude + halfDeg * 0.5,
                    longitude: center.longitude + deg * 0.4
                ),
                CLLocationCoordinate2D(
                    latitude: center.latitude,
                    longitude: center.longitude + deg * 0.6
                ),
                CLLocationCoordinate2D(
                    latitude: center.latitude - halfDeg * 0.5,
                    longitude: center.longitude + deg * 0.4
                ),
                center
            ]),
            ("South Loop", [
                center,
                CLLocationCoordinate2D(
                    latitude: center.latitude - deg * 0.4,
                    longitude: center.longitude + halfDeg * 0.5
                ),
                CLLocationCoordinate2D(
                    latitude: center.latitude - deg * 0.6,
                    longitude: center.longitude
                ),
                CLLocationCoordinate2D(
                    latitude: center.latitude - deg * 0.4,
                    longitude: center.longitude - halfDeg * 0.5
                ),
                center
            ])
        ]
    }

    /// Builds a `LoopRoute` from a sequence of waypoints by computing straight-line
    /// segment distances. Assumes running pace of 6 min/km for time estimation.
    private func buildRoute(
        name: String,
        waypoints: [CLLocationCoordinate2D]
    ) -> LoopRoute? {
        guard waypoints.count >= 2 else { return nil }

        var totalDistance = 0.0
        for i in 0..<(waypoints.count - 1) {
            let from = CLLocation(
                latitude: waypoints[i].latitude,
                longitude: waypoints[i].longitude
            )
            let to = CLLocation(
                latitude: waypoints[i + 1].latitude,
                longitude: waypoints[i + 1].longitude
            )
            totalDistance += from.distance(from: to)
        }

        let polyline = MKPolyline(coordinates: waypoints, count: waypoints.count)
        // 6 min/km walking/running pace
        let estimatedMinutes = Int((totalDistance / 1000.0) * 6.0)

        return LoopRoute(
            name: name,
            distance: totalDistance,
            estimatedMinutes: estimatedMinutes,
            waypoints: waypoints,
            polyline: polyline
        )
    }
}
