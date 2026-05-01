import FirebaseAnalytics
import FirebaseCore
import FirebaseCrashlytics
import FirebaseFirestore
import SwiftData
import SwiftUI
import UserNotifications

// MARK: - KineticsNotificationDelegate

/// Bridges UNUserNotificationCenter taps into the kinetics:// URL scheme so
/// `MainTabView.onOpenURL` can route notification taps without any extra
/// AppDelegate machinery.
///
/// Set as the `UNUserNotificationCenter.current().delegate` in `KineticsApp`.
@MainActor
final class KineticsNotificationDelegate: NSObject, UNUserNotificationCenterDelegate, Sendable {

    /// Present notifications as banners even while the app is in the foreground.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler:
            @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .badge])
    }

    /// When the user taps a notification, extract `kinetics_deeplink` from
    /// `userInfo` and open it via `UIApplication.open(_:)`.  That fires the
    /// `onOpenURL` modifier in `MainTabView` which calls `handleDeepLink`.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        defer { completionHandler() }
        guard
            let rawURL = response.notification.request.content
                .userInfo["kinetics_deeplink"] as? String,
            let url = URL(string: rawURL)
        else { return }

        Task { @MainActor in
            UIApplication.shared.open(url)
        }
    }
}

// MARK: - KineticsApp

@main
struct KineticsApp: App {

    @State private var appState = AppState()
    @AppStorage("permissions_requested") private var permissionsRequested = false

    // Notification delegate must be retained for the lifetime of the app.
    private let notificationDelegate = KineticsNotificationDelegate()

    // Configure Firebase in the struct init — this runs before any SwiftUI lifecycle,
    // before @State initialization, and before AppDelegate callbacks. The guard prevents
    // double-configuration if AppState.init() also calls configureFirebaseIfReady().
    init() {
        if FirebaseApp.app() == nil {
            FirebaseApp.configure()
        }
    }

    private static let modelContainer: ModelContainer = {
        let schema = Schema([
            Exercise.self,
            WorkoutSession.self,
            WorkoutExerciseEntry.self,
            WorkoutSet.self,
            Routine.self,
            PersonalRecord.self,
            BodyMeasurement.self,
            VideoSession.self,
            WeeklyPlan.self,
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            let container = try ModelContainer(for: schema, configurations: config)
            return container
        } catch {
            fatalError("Failed to create SwiftData ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .environment(appState)
                .preferredColorScheme(.dark)
                .modelContainer(Self.modelContainer)
                .onAppear {
                    // Register notification delegate so taps deep-link correctly.
                    UNUserNotificationCenter.current().delegate = notificationDelegate

                    GymRepository.shared.modelContainer = Self.modelContainer
                    VideoRepository.shared.modelContainer = Self.modelContainer
                    Analytics.logEvent("app_session_started", parameters: [
                        "timestamp": Date().timeIntervalSince1970
                    ])
                    // Enable Crashlytics
                    Crashlytics.crashlytics().setCrashlyticsCollectionEnabled(true)
                    // Offline Firestore caching (100 MB on-device persistent cache)
                    if FirebaseApp.app() != nil {
                        let settings = FirestoreSettings()
                        settings.cacheSettings = PersistentCacheSettings(
                            sizeBytes: NSNumber(value: 100 * 1024 * 1024)
                        )
                        Firestore.firestore().settings = settings
                    }
                }
                .fullScreenCover(isPresented: Binding(
                    get: { !permissionsRequested },
                    set: { _ in }
                )) {
                    PermissionsGateView()
                }
        }
    }
}
