import MapKit
import SwiftUI

// MARK: - RouteMapView

/// A MapKit map rendered via `UIViewRepresentable` that draws the GPS route
/// as a coloured `MKPolyline` overlay.
///
/// When `followsUser` is `true` the map tracks the runner's current position
/// using `MKUserTrackingMode.follow`. When `false` — e.g. on a summary screen —
/// it fits the entire route inside the visible region.
///
/// Usage (live recording):
/// ```swift
/// RouteMapView(
///     coordinates: viewModel.routeCoordinates,
///     currentLocation: viewModel.routeCoordinates.last,
///     followsUser: true
/// )
/// ```
///
/// Usage (post-workout summary):
/// ```swift
/// RouteMapView.routeSummary(coordinates: result.routeCoordinates)
/// ```
struct RouteMapView: UIViewRepresentable {

    // MARK: - Properties

    /// Ordered waypoints that form the route polyline. Updated as new GPS fixes arrive.
    var coordinates: [CLLocationCoordinate2D]

    /// Current device location used as the region centre when `followsUser` is false.
    /// Pass `nil` when no fix is available yet.
    var currentLocation: CLLocationCoordinate2D?

    /// Colour of the route polyline. Defaults to `#00C2FF` (kineticsBlue).
    var lineColor: UIColor = UIColor(red: 0, green: 0.761, blue: 1.0, alpha: 1.0)

    /// When `true`, the map enters `.follow` tracking mode so the user's position
    /// stays centred as they move. When `false`, the map fits all coordinates into
    /// the visible region (summary mode).
    var followsUser: Bool = true

    // MARK: - Factory

    /// Returns a `RouteMapView` configured for a post-workout summary.
    ///
    /// - The map does not track the user.
    /// - The visible region is fitted to contain all `coordinates`.
    static func routeSummary(coordinates: [CLLocationCoordinate2D]) -> RouteMapView {
        RouteMapView(
            coordinates: coordinates,
            currentLocation: nil,
            followsUser: false
        )
    }

    // MARK: - UIViewRepresentable

    func makeCoordinator() -> Coordinator {
        Coordinator(lineColor: lineColor)
    }

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator

        // Appearance
        mapView.showsUserLocation = true
        mapView.showsCompass = false
        mapView.showsScale = false
        mapView.isPitchEnabled = false
        mapView.isRotateEnabled = false

        // Dark map style: MKStandardMapConfiguration with muted emphasis matches
        // the app's near-black chrome. The kineticsBlue polyline renders well on
        // the dark basemap.
        let darkConfig = MKStandardMapConfiguration(elevationStyle: .flat, emphasisStyle: .muted)
        mapView.preferredConfiguration = darkConfig

        // Start following the user immediately when in live mode
        if followsUser {
            mapView.setUserTrackingMode(.follow, animated: false)
        }

        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        // Update polyline whenever coordinates change
        context.coordinator.updatePolyline(on: mapView, coordinates: coordinates)

        // Tracking mode and region management
        if followsUser {
            if mapView.userTrackingMode != .follow {
                mapView.setUserTrackingMode(.follow, animated: true)
            }
        } else {
            // Summary mode: fit all waypoints in view with comfortable padding
            fitRegion(on: mapView)
        }
    }

    // MARK: - Private Helpers

    /// Fits all `coordinates` into the mapView's visible region, adding padding so
    /// the polyline doesn't hug the edge of the screen.
    private func fitRegion(on mapView: MKMapView) {
        guard coordinates.count >= 2 else {
            // Fall back to current location or a default region when there is no route yet
            if let location = currentLocation {
                let region = MKCoordinateRegion(
                    center: location,
                    latitudinalMeters: 500,
                    longitudinalMeters: 500
                )
                mapView.setRegion(region, animated: false)
            }
            return
        }

        // Build a bounding box around all waypoints
        var minLat = coordinates[0].latitude
        var maxLat = coordinates[0].latitude
        var minLon = coordinates[0].longitude
        var maxLon = coordinates[0].longitude

        for coord in coordinates {
            minLat = min(minLat, coord.latitude)
            maxLat = max(maxLat, coord.latitude)
            minLon = min(minLon, coord.longitude)
            maxLon = max(maxLon, coord.longitude)
        }

        let centerLat = (minLat + maxLat) / 2.0
        let centerLon = (minLon + maxLon) / 2.0
        // Add 40 % padding so the route has breathing room inside the frame
        let spanLat = max((maxLat - minLat) * 1.4, 0.002)
        let spanLon = max((maxLon - minLon) * 1.4, 0.002)

        let region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: centerLat, longitude: centerLon),
            span: MKCoordinateSpan(latitudeDelta: spanLat, longitudeDelta: spanLon)
        )
        mapView.setRegion(region, animated: false)
    }
}

// MARK: - Coordinator

extension RouteMapView {

    /// Implements `MKMapViewDelegate` to render the route polyline with the
    /// configured colour and width.
    final class Coordinator: NSObject, MKMapViewDelegate {

        // MARK: State

        private let lineColor: UIColor
        /// The polyline currently displayed on the map. Held here so we can
        /// remove the old overlay before adding the updated one.
        private var currentPolyline: MKPolyline?

        // MARK: Init

        init(lineColor: UIColor) {
            self.lineColor = lineColor
        }

        // MARK: Polyline Management

        /// Removes the existing polyline overlay and replaces it with one built
        /// from `coordinates`. No-ops when `coordinates` is fewer than 2 points.
        func updatePolyline(on mapView: MKMapView, coordinates: [CLLocationCoordinate2D]) {
            // Remove previous overlay
            if let existing = currentPolyline {
                mapView.removeOverlay(existing)
                currentPolyline = nil
            }

            guard coordinates.count >= 2 else { return }

            let polyline = MKPolyline(coordinates: coordinates, count: coordinates.count)
            mapView.addOverlay(polyline, level: .aboveRoads)
            currentPolyline = polyline
        }

        // MARK: MKMapViewDelegate

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let polyline = overlay as? MKPolyline else {
                return MKOverlayRenderer(overlay: overlay)
            }

            let renderer = MKPolylineRenderer(polyline: polyline)
            renderer.strokeColor = lineColor
            renderer.lineWidth = 4.5
            renderer.lineCap = .round
            renderer.lineJoin = .round
            return renderer
        }
    }
}

