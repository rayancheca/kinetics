import FirebaseAuth
import FirebaseCore
import Foundation
import Observation

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

    private var listenerHandle: AuthStateDidChangeListenerHandle?

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
                self?.currentUser = user
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

    // MARK: - Sign Out

    /// Signs out the current user. Clears `currentUser` synchronously.
    func signOut() throws {
        guard isFirebaseReady else { return }
        try Auth.auth().signOut()
        currentUser = nil
    }
}
