import Foundation
import CoreLocation
import FirebaseFirestore

// MARK: - KineticsRoute

struct KineticsRoute: Identifiable, Codable, Sendable {
    var id: String = UUID().uuidString
    var name: String
    var description: String
    var creatorUID: String
    var creatorDisplayName: String
    var activityType: String
    var distance: Double       // metres
    var elevationGain: Double  // metres
    var polylineEncoded: String
    var waypoints: [RouteWaypoint]
    var createdAt: Date
    var isPublic: Bool
    var kudosCount: Int
    var tags: [String]

    var formattedDistance: String {
        String(format: "%.1f km", distance / 1000)
    }

    // MARK: - RouteWaypoint

    struct RouteWaypoint: Codable, Sendable {
        let lat: Double
        let lng: Double

        var coordinate: CLLocationCoordinate2D {
            CLLocationCoordinate2D(latitude: lat, longitude: lng)
        }
    }
}
