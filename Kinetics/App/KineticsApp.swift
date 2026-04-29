import SwiftData
import SwiftUI

@main
struct KineticsApp: App {

    @State private var appState = AppState()

    private static let modelContainer: ModelContainer = {
        let schema = Schema([
            Exercise.self,
            WorkoutSession.self,
            WorkoutExerciseEntry.self,
            WorkoutSet.self,
            Routine.self,
            PersonalRecord.self,
            BodyMeasurement.self
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
                }
        }
    }
}
