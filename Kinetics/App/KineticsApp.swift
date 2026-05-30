import AppIntents
import FirebaseAnalytics
import FirebaseCore
import FirebaseCrashlytics
import FirebaseFirestore
import FirebaseMessaging
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

    @UIApplicationDelegateAdaptor(KineticsAppDelegate.self) private var appDelegate

    @State private var appState = AppState()
    @State private var showSplash = true
    @AppStorage("permissions_requested") private var permissionsRequested = false
    @AppStorage("onboarding_complete") private var onboardingComplete = false

    // Notification delegate must be retained for the lifetime of the app.
    private let notificationDelegate = KineticsNotificationDelegate()

    // Configure Firebase in the struct init — this runs before any SwiftUI lifecycle,
    // before @State initialization, and before AppDelegate callbacks. The guard prevents
    // double-configuration if AppState.init() also calls configureFirebaseIfReady().
    init() {
        if FirebaseApp.app() == nil {
            FirebaseApp.configure()
        }
        // CRITICAL: Firestore settings must be applied BEFORE any other Firebase
        // code touches Firestore. AuthManager, FCM token persistence in
        // KineticsAppDelegate, and onAppear initializers can all race ahead of
        // a view-layer settings call. Setting them inline here, immediately
        // after FirebaseApp.configure(), is the only safe place.
        if FirebaseApp.app() != nil {
            let settings = FirestoreSettings()
            settings.cacheSettings = PersistentCacheSettings(
                sizeBytes: NSNumber(value: 100 * 1024 * 1024)
            )
            Firestore.firestore().settings = settings
        }
        // Register App Shortcuts so Siri suggests them and Spotlight indexes them.
        if #available(iOS 17.0, *) {
            KineticsShortcutsProvider.updateAppShortcutParameters()
        }
        // Clean up any stale Live Activities from a previous run.
        if #available(iOS 16.2, *) {
            LiveSessionController.endAllOrphaned()
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
            FaceProfile.self,
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: config)
        } catch {
            // Store is corrupt or schema changed — delete and recreate once.
            print("[Kinetics] SwiftData container failed (\(error)). Attempting store deletion and retry.")
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            if let appSupport {
                let storeFiles = (try? FileManager.default.contentsOfDirectory(at: appSupport, includingPropertiesForKeys: nil)) ?? []
                for file in storeFiles where file.pathExtension == "sqlite"
                    || file.lastPathComponent.hasSuffix(".sqlite-shm")
                    || file.lastPathComponent.hasSuffix(".sqlite-wal") {
                    try? FileManager.default.removeItem(at: file)
                }
            }
            do {
                return try ModelContainer(for: schema, configurations: config)
            } catch {
                // Recovery also failed — fall back to an in-memory store so the app still launches.
                print("[Kinetics] SwiftData retry failed (\(error)). Falling back to in-memory store.")
                let fallbackConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
                // swiftlint:disable:next force_try
                return try! ModelContainer(for: schema, configurations: fallbackConfig)
            }
        }
    }()

    var body: some Scene {
        WindowGroup {
            if showSplash {
                SplashScreenView {
                    showSplash = false
                }
            } else {
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

                    // Kick the FCM auto-init so tokens flow even before the user
                    // explicitly opts into notifications. Token persistence runs
                    // through KineticsAppDelegate.messaging(_:didReceiveRegistrationToken:).
                    if FirebaseApp.app() != nil {
                        Messaging.messaging().isAutoInitEnabled = true
                    }
                }
                .fullScreenCover(isPresented: Binding(
                    get: { !permissionsRequested },
                    set: { _ in }
                )) {
                    PermissionsGateView()
                }
                // Onboarding walkthrough — shown once after permissions are granted.
                .fullScreenCover(isPresented: Binding(
                    get: { permissionsRequested && !onboardingComplete },
                    set: { _ in }
                )) {
                    OnboardingView()
                }
            } // end else
        }
    }
}
