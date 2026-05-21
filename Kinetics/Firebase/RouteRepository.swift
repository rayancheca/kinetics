import Foundation
import FirebaseFirestore
import CoreLocation

// MARK: - RouteRepository

@Observable @MainActor
final class RouteRepository {
    static let shared = RouteRepository()

    var communityRoutes: [KineticsRoute] = []
    var myRoutes: [KineticsRoute] = []

    private let db = Firestore.firestore()

    private init() {}

    // MARK: - Fetch

    /// Fetches public community routes sorted by kudos count.
    /// Note: Geospatial filtering requires a GeoHash index; this implementation
    /// fetches the top 20 public routes globally and can be extended with
    /// Firestore GeoPoint queries when the index is available.
    func fetchCommunityRoutes(
        near coordinate: CLLocationCoordinate2D,
        radiusKM: Double = 10
    ) async {
        do {
            let snapshot = try await db.collection("routes")
                .whereField("isPublic", isEqualTo: true)
                .order(by: "kudosCount", descending: true)
                .limit(to: 20)
                .getDocuments()

            communityRoutes = snapshot.documents.compactMap {
                try? $0.data(as: KineticsRoute.self)
            }
        } catch {
            print("RouteRepository.fetchCommunityRoutes error: \(error)")
        }
    }

    func fetchMyRoutes(uid: String) async {
        do {
            let snapshot = try await db.collection("routes")
                .whereField("creatorUID", isEqualTo: uid)
                .order(by: "createdAt", descending: true)
                .getDocuments()

            myRoutes = snapshot.documents.compactMap {
                try? $0.data(as: KineticsRoute.self)
            }
        } catch {
            print("RouteRepository.fetchMyRoutes error: \(error)")
        }
    }

    // MARK: - Write

    func saveRoute(_ route: KineticsRoute) async throws {
        try db.collection("routes").document(route.id).setData(from: route)
    }

    func kudosRoute(_ routeID: String, uid: String) async {
        do {
            try await db.collection("routes").document(routeID)
                .updateData(["kudosCount": FieldValue.increment(Int64(1))])
        } catch {
            print("RouteRepository.kudosRoute error: \(error)")
        }
    }

    func deleteRoute(_ routeID: String) async throws {
        try await db.collection("routes").document(routeID).delete()
    }
}
