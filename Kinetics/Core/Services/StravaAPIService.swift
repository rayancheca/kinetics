import Foundation
import CoreLocation
import MapKit

// MARK: - StravaRoute

struct StravaRoute: Codable, Identifiable, Sendable {
    let id: Int
    let name: String
    let distance: Double
    let elevationGain: Double
    let type: Int
    let subType: Int
    let estimatedMovingTime: Int

    enum CodingKeys: String, CodingKey {
        case id, name, distance, type
        case elevationGain = "elevation_gain"
        case subType = "sub_type"
        case estimatedMovingTime = "estimated_moving_time"
    }

    var activityTypeName: String { type == 1 ? "Run" : "Ride" }

    var formattedDistance: String {
        String(format: "%.1f km", distance / 1000)
    }

    var formattedTime: String {
        let hours = estimatedMovingTime / 3600
        let minutes = (estimatedMovingTime % 3600) / 60
        return hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
    }
}

// MARK: - StravaSegment

struct StravaSegment: Codable, Identifiable, Sendable {
    let id: Int
    let name: String
    let distance: Double
    let avgGrade: Double
    let maxGrade: Double
    let elevationHigh: Double
    let elevationLow: Double
    let activityType: String
    let effortCount: Int
    let athleteCount: Int

    enum CodingKeys: String, CodingKey {
        case id, name, distance
        case avgGrade = "average_grade"
        case maxGrade = "maximum_grade"
        case elevationHigh = "elevation_high"
        case elevationLow = "elevation_low"
        case activityType = "activity_type"
        case effortCount = "effort_count"
        case athleteCount = "athlete_count"
    }
}

// MARK: - StravaLeaderboard

struct StravaLeaderboard: Codable, Sendable {
    let entryCount: Int
    let entries: [StravaLeaderboardEntry]

    enum CodingKeys: String, CodingKey {
        case entryCount = "entry_count"
        case entries
    }
}

struct StravaLeaderboardEntry: Codable, Sendable {
    let rank: Int
    let athleteName: String
    let elapsedTime: Int

    enum CodingKeys: String, CodingKey {
        case rank
        case athleteName = "athlete_name"
        case elapsedTime = "elapsed_time"
    }
}

// MARK: - StravaAPIService

actor StravaAPIService {
    static let shared = StravaAPIService()

    private let baseURL = "https://www.strava.com/api/v3"

    // MARK: - Public API

    func fetchAthleteRoutes() async throws -> [StravaRoute] {
        let token = try await StravaAuthService.shared.validToken()
        return try await get("/athlete/routes", token: token)
    }

    func fetchStarredSegments(lat: Double, lng: Double) async throws -> [StravaSegment] {
        let token = try await StravaAuthService.shared.validToken()
        return try await get("/segments/starred", token: token)
    }

    func fetchSegmentLeaderboard(segmentID: Int) async throws -> StravaLeaderboard {
        let token = try await StravaAuthService.shared.validToken()
        return try await get("/segments/\(segmentID)/leaderboard", token: token)
    }

    // MARK: - Private

    private func get<T: Decodable & Sendable>(
        _ path: String,
        token: String,
        queryItems: [URLQueryItem] = []
    ) async throws -> T {
        var components = URLComponents(string: baseURL + path)!
        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }

        guard let url = components.url else {
            throw StravaError.invalidURL
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw StravaError.apiError("Strava API returned an error response.")
        }

        return try JSONDecoder().decode(T.self, from: data)
    }
}
