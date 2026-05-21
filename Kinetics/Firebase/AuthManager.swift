import AuthenticationServices
import CryptoKit
import FirebaseAuth
import FirebaseCore
import Foundation
import Observation
import UIKit

// MARK: - AuthManager

/// Manages Firebase Authentication state for the Kinetics app.
///
/// Supports anonymous sign-in for frictionless onboarding and email/password
/// for users who want persistent session history across devices.
///
/// Guards every Firebase call with `isFirebaseReady` so the app runs cleanly
/// against the placeholder `GoogleService-Info.plist` during development.
@Observable
@MainActor
final class AuthManager {

    // MARK: - Published State

    private(set) var currentUser: FirebaseAuth.User?
    var isSignedIn: Bool { currentUser != nil }
    var authError: String?
    var isLoading = false

    // MARK: - Private

    nonisolated(unsafe) private var listenerHandle: AuthStateDidChangeListenerHandle?

    /// Held between the Apple ID request and the ASAuthorizationController delegate callback.
    nonisolated(unsafe) private var currentNonce: String?

    /// Returns `true` only when a real Firebase app has been configured.
    /// When the placeholder plist is active, `FirebaseApp.app()` returns `nil`.
    private var isFirebaseReady: Bool { FirebaseApp.app() != nil }

    // MARK: - Init / Deinit

    init() {
        listenForAuthChanges()
    }

    deinit {
        if let handle = listenerHandle {
            Auth.auth().removeStateDidChangeListener(handle)
        }
    }

    // MARK: - Auth State Listener

    /// Attaches a persistent listener so `currentUser` stays in sync with the
    /// Firebase Auth token. No-ops silently when Firebase is not configured.
    func listenForAuthChanges() {
        guard isFirebaseReady else { return }
        listenerHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor [weak self] in
                withAnimation(.easeInOut(duration: 0.35)) {
                    self?.currentUser = user
                }
            }
        }
    }

    // MARK: - Sign In: Anonymous

    /// Signs in without credentials. Suitable for first-launch sessions before
    /// the user decides to create a full account.
    func signInAnonymously() async throws {
        guard isFirebaseReady else {
            authError = "Firebase is not configured. Replace the placeholder GoogleService-Info.plist with a real one from your Firebase Console."
            return
        }
        isLoading = true
        defer { isLoading = false }
        authError = nil

        let result = try await Auth.auth().signInAnonymously()
        currentUser = result.user
    }

    // MARK: - Sign In: Email / Password

    /// Authenticates an existing account with email and password.
    func signInWithEmail(_ email: String, password: String) async throws {
        guard isFirebaseReady else {
            authError = "Firebase is not configured."
            return
        }
        isLoading = true
        defer { isLoading = false }
        authError = nil

        do {
            let result = try await Auth.auth().signIn(withEmail: email, password: password)
            currentUser = result.user
        } catch {
            authError = error.localizedDescription
            throw error
        }
    }

    // MARK: - Create Account

    /// Creates a new email/password account and signs in immediately.
    func createAccount(email: String, password: String) async throws {
        guard isFirebaseReady else {
            authError = "Firebase is not configured."
            return
        }
        isLoading = true
        defer { isLoading = false }
        authError = nil

        do {
            let result = try await Auth.auth().createUser(withEmail: email, password: password)
            currentUser = result.user
        } catch {
            authError = error.localizedDescription
            throw error
        }
    }

    // MARK: - Sign In: Apple

    /// Authenticates with Sign in with Apple and links the credential to Firebase Auth.
    ///
    /// Internally wraps the delegate-based `ASAuthorizationController` in a
    /// checked-throwing continuation so callers can use `try await`.
    func signInWithApple() async throws {
        guard isFirebaseReady else {
            authError = "Firebase is not configured."
            return
        }
        isLoading = true
        defer { isLoading = false }
        authError = nil

        let nonce = randomNonceString()
        currentNonce = nonce

        let appleIDProvider = ASAuthorizationAppleIDProvider()
        let request = appleIDProvider.createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = sha256(nonce)

        let authorization: ASAuthorization = try await withCheckedThrowingContinuation { continuation in
            let coordinator = AppleSignInCoordinator(continuation: continuation)
            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = coordinator
            controller.presentationContextProvider = coordinator
            // Retain coordinator for the async lifetime of this call.
            coordinator.retain()
            controller.performRequests()
        }

        guard
            let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential,
            let appleIDTokenData = appleIDCredential.identityToken,
            let appleIDToken = String(data: appleIDTokenData, encoding: .utf8),
            let nonce = currentNonce
        else {
            authError = "Unable to read Apple ID token."
            throw AuthError.missingAppleIDToken
        }

        let credential = OAuthProvider.appleCredential(
            withIDToken: appleIDToken,
            rawNonce: nonce,
            fullName: appleIDCredential.fullName
        )

        do {
            let result = try await Auth.auth().signIn(with: credential)
            currentUser = result.user
        } catch {
            authError = error.localizedDescription
            throw error
        }
    }

    // MARK: - Sign In: Apple (credential-based, for use with SignInWithAppleButton)

    /// Completes Apple authentication using the credential delivered by
    /// `SignInWithAppleButton`'s `onCompletion` handler.
    ///
    /// The nonce used when constructing the button request must match `currentNonce`.
    /// Call `prepareAppleSignInRequest(_:)` from the button's `onRequest` closure
    /// first so the nonce is set before this is called.
    func completeAppleSignIn(with authorization: ASAuthorization) async throws {
        guard isFirebaseReady else {
            authError = "Firebase is not configured."
            return
        }
        isLoading = true
        defer { isLoading = false }
        authError = nil

        guard
            let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential,
            let appleIDTokenData = appleIDCredential.identityToken,
            let appleIDToken = String(data: appleIDTokenData, encoding: .utf8),
            let nonce = currentNonce
        else {
            authError = "Unable to read Apple ID token."
            throw AuthError.missingAppleIDToken
        }

        let credential = OAuthProvider.appleCredential(
            withIDToken: appleIDToken,
            rawNonce: nonce,
            fullName: appleIDCredential.fullName
        )

        do {
            let result = try await Auth.auth().signIn(with: credential)
            currentUser = result.user
        } catch {
            authError = error.localizedDescription
            throw error
        }
    }

    /// Configures an `ASAuthorizationAppleIDRequest` and stores the matching
    /// nonce so `completeAppleSignIn(with:)` can verify it.
    /// Call this from `SignInWithAppleButton`'s `onRequest` closure.
    func prepareAppleSignInRequest(_ request: ASAuthorizationAppleIDRequest) {
        let nonce = randomNonceString()
        currentNonce = nonce
        request.requestedScopes = [.fullName, .email]
        request.nonce = sha256(nonce)
    }

    // MARK: - Nonce Helpers

    private func randomNonceString(length: Int = 32) -> String {
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remainingLength = length
        while remainingLength > 0 {
            let randoms: [UInt8] = (0 ..< 16).map { _ in
                var random: UInt8 = 0
                _ = SecRandomCopyBytes(kSecRandomDefault, 1, &random)
                return random
            }
            randoms.forEach { random in
                if remainingLength == 0 { return }
                if random < charset.count {
                    result.append(charset[Int(random)])
                    remainingLength -= 1
                }
            }
        }
        return result
    }

    private func sha256(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hashedData = SHA256.hash(data: inputData)
        return hashedData.compactMap { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Sign Out

    /// Signs out the current user. Clears `currentUser` synchronously.
    func signOut() throws {
        guard isFirebaseReady else { return }
        try Auth.auth().signOut()
        withAnimation(.easeInOut(duration: 0.35)) {
            currentUser = nil
        }
    }
}

// MARK: - AuthError

enum AuthError: Error {
    case missingAppleIDToken
}

// MARK: - AppleSignInCoordinator

/// Bridges `ASAuthorizationController`'s delegate callbacks into a Swift
/// checked-throwing continuation so `signInWithApple()` can be fully async.
///
/// The coordinator retains itself via `retain()` / `release()` to survive the
/// async gap between `performRequests()` and the delegate callback — without
/// leaking if the authorization window is dismissed early.
private final class AppleSignInCoordinator: NSObject,
    ASAuthorizationControllerDelegate,
    ASAuthorizationControllerPresentationContextProviding
{

    private var continuation: CheckedContinuation<ASAuthorization, Error>?
    // Self-retain token so ARC doesn't deallocate us during the async gap.
    private var selfRetain: AppleSignInCoordinator?

    init(continuation: CheckedContinuation<ASAuthorization, Error>) {
        self.continuation = continuation
    }

    /// Call once before `performRequests()` to keep the coordinator alive.
    func retain() { selfRetain = self }

    // MARK: - ASAuthorizationControllerDelegate

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        continuation?.resume(returning: authorization)
        continuation = nil
        selfRetain = nil
    }

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        continuation?.resume(throwing: error)
        continuation = nil
        selfRetain = nil
    }

    // MARK: - ASAuthorizationControllerPresentationContextProviding

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow } ?? UIWindow()
    }
}
