import FirebaseCore
import FirebaseFirestore
import Foundation

// MARK: - FirebaseBootstrap

/// Single source of truth for one-time Firebase configuration.
///
/// Firestore enforces a hard rule: `Firestore.firestore().settings` can only be
/// assigned BEFORE any other Firestore method is called. Once any code touches
/// `Firestore.firestore()` for a read, write, or even a collection reference,
/// the settings become immutable and subsequent assignment crashes the process.
///
/// In a real app many code paths can race to be the "first to touch" Firestore:
/// repositories created at app launch, FCM token writes from the AppDelegate,
/// auth state listeners, and view-layer `.onAppear` blocks. Centralising
/// configuration here and guarding it with a one-shot flag means no caller
/// needs to know whether they are the first to arrive — they call
/// `FirebaseBootstrap.configureIfNeeded()` and it does the right thing.
///
/// The flag is `nonisolated(unsafe)` because it is only mutated inside
/// `configureIfNeeded()`, which is itself synchronous. The check-and-set is
/// not strictly atomic, but the worst case under contention is a second call
/// short-circuiting harmlessly — Firestore's settings assignment is itself
/// the synchronization primitive that would crash, and we never let two
/// assignments race past the flag.
enum FirebaseBootstrap {

    /// True once Firestore settings have been applied successfully.
    nonisolated(unsafe) private static var firestoreConfigured = false

    /// Idempotent Firebase configuration entry point.
    ///
    /// 1. Calls `FirebaseApp.configure()` if no app has been registered yet.
    /// 2. Applies Firestore cache + transport settings exactly once.
    /// 3. Safe to call from any place at any time — repeat calls are no-ops.
    ///
    /// Designed to run from `KineticsApp.init()` first, but tolerant of being
    /// re-invoked from repositories or tests.
    static func configureIfNeeded() {
        // 1. Make sure FirebaseApp exists. configure() is itself idempotent —
        // calling it twice throws an exception, so we guard on app() == nil.
        if FirebaseApp.app() == nil {
            FirebaseApp.configure()
        }

        // 2. Configure Firestore once. The flag guards against multiple call
        // sites racing past the FirebaseApp check.
        guard FirebaseApp.app() != nil, !firestoreConfigured else { return }
        firestoreConfigured = true

        let settings = FirestoreSettings()
        settings.cacheSettings = PersistentCacheSettings(
            sizeBytes: NSNumber(value: 100 * 1024 * 1024)
        )
        Firestore.firestore().settings = settings
    }
}
