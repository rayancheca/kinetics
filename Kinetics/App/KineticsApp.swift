import FirebaseAnalytics
import FirebaseCore
import FirebaseCrashlytics
import FirebaseFirestore
import SwiftData
import SwiftUI

@main
struct KineticsApp: App {

    @State private var appState = AppState()
    @AppStorage("permissions_requested") private var permissionsRequested = false

    init() {
        FirebaseApp.configure()
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
            VideoSession.self
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
