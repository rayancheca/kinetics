import Foundation
import AuthenticationServices

// MARK: - StravaError

enum StravaError: Error, LocalizedError {
    case invalidURL
    case noCallback
    case noCode
    case notAuthenticated
    case apiError(String)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "Connect your Strava account to access routes."
        case .apiError(let msg):
            return msg
        default:
            return "Strava connection failed."
        }
    }
}

// MARK: - StravaTokenResponse

struct StravaTokenResponse: Decodable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: Int
    let athlete: StravaAthlete?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresAt = "expires_at"
        case athlete
    }
}

// MARK: - StravaAthlete

struct StravaAthlete: Codable, Sendable {
    let id: Int
    let firstname: String
    let lastname: String
    let profileMedium: String?
    let city: String?
    let country: String?

    enum CodingKeys: String, CodingKey {
        case id, firstname, lastname, city, country
        case profileMedium = "profile_medium"
    }
}

// MARK: - StravaAuthService

@Observable @MainActor
final class StravaAuthService: NSObject {
    static let shared = StravaAuthService()

    var isAuthenticated = false
    var athleteProfile: StravaAthlete?

    // Strava API credentials — sourced from Secrets.xcconfig via Info.plist
    // Never hardcode these values; populate Kinetics/Config/Secrets.xcconfig locally
    private let clientID: String = Bundle.main.infoDictionary?["STRAVA_CLIENT_ID"] as? String ?? ""
    private let clientSecret: String = Bundle.main.infoDictionary?["STRAVA_CLIENT_SECRET"] as? String ?? ""
    private let redirectURI = "kinetics://strava-auth"
    private let scope = "read,activity:read,profile:read_all"

    // MARK: - Keychain Keys

    private enum KeychainKey {
        static let accessToken = "strava_access_token"
        static let refreshToken = "strava_refresh_token"
    }

    // MARK: Token Storage (Keychain)

    private var accessToken: String? {
        get { KeychainHelper.load(for: KeychainKey.accessToken) }
        set {
            if let value = newValue {
                KeychainHelper.save(value, for: KeychainKey.accessToken)
            } else {
                KeychainHelper.delete(for: KeychainKey.accessToken)
            }
        }
    }

    private var refreshToken: String? {
        get { KeychainHelper.load(for: KeychainKey.refreshToken) }
        set {
            if let value = newValue {
                KeychainHelper.save(value, for: KeychainKey.refreshToken)
            } else {
                KeychainHelper.delete(for: KeychainKey.refreshToken)
            }
        }
    }

    private var tokenExpiresAt: Date? {
        get {
            guard let raw = KeychainHelper.load(for: "strava_token_expires"),
                  let ts = Double(raw), ts > 0 else { return nil }
            return Date(timeIntervalSince1970: ts)
        }
        set {
            let ts = newValue?.timeIntervalSince1970 ?? 0
            KeychainHelper.save(String(ts), for: "strava_token_expires")
        }
    }

    private override init() {
        super.init()
        isAuthenticated = accessToken != nil
    }

    // MARK: - Public API

    func authenticate() async throws {
        let encodedScope = scope.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? scope
        let encodedRedirect = redirectURI.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? redirectURI
        let authURLString = "https://www.strava.com/oauth/mobile/authorize"
            + "?client_id=\(clientID)"
            + "&redirect_uri=\(encodedRedirect)"
            + "&response_type=code"
            + "&approval_prompt=auto"
            + "&scope=\(encodedScope)"

        guard let url = URL(string: authURLString) else {
            throw StravaError.invalidURL
        }

        let callbackURL: URL = try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: "kinetics"
            ) { url, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let url else {
                    continuation.resume(throwing: StravaError.noCallback)
                    return
                }
                continuation.resume(returning: url)
            }
            session.prefersEphemeralWebBrowserSession = false
            session.start()
        }

        guard let code = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "code" })?.value
        else {
            throw StravaError.noCode
        }

        try await exchangeCode(code)
    }

    /// Returns a valid access token, refreshing if the current one is within 60 s of expiry.
    func validToken() async throws -> String {
        if let token = accessToken,
           let expiry = tokenExpiresAt,
           expiry > Date().addingTimeInterval(60) {
            return token
        }
        try await refreshAccessToken()
        guard let token = accessToken else {
            throw StravaError.notAuthenticated
        }
        return token
    }

    func disconnect() {
        accessToken = nil
        refreshToken = nil
        tokenExpiresAt = nil
        athleteProfile = nil
        isAuthenticated = false
    }

    // MARK: - Private

    private func exchangeCode(_ code: String) async throws {
        let params: [String: String] = [
            "client_id": clientID,
            "client_secret": clientSecret,
            "code": code,
            "grant_type": "authorization_code"
        ]

        var request = URLRequest(url: URL(string: "https://www.strava.com/oauth/token")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(params)

        let (data, _) = try await URLSession.shared.data(for: request)
        let response = try JSONDecoder().decode(StravaTokenResponse.self, from: data)

        accessToken = response.accessToken
        refreshToken = response.refreshToken
        tokenExpiresAt = Date(timeIntervalSince1970: TimeInterval(response.expiresAt))
        athleteProfile = response.athlete
        isAuthenticated = true
    }

    private func refreshAccessToken() async throws {
        guard let refresh = refreshToken else {
            throw StravaError.notAuthenticated
        }

        let params: [String: String] = [
            "client_id": clientID,
            "client_secret": clientSecret,
            "refresh_token": refresh,
            "grant_type": "refresh_token"
        ]

        var request = URLRequest(url: URL(string: "https://www.strava.com/oauth/token")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(params)

        let (data, _) = try await URLSession.shared.data(for: request)
        let response = try JSONDecoder().decode(StravaTokenResponse.self, from: data)

        accessToken = response.accessToken
        refreshToken = response.refreshToken
        tokenExpiresAt = Date(timeIntervalSince1970: TimeInterval(response.expiresAt))
    }
}
