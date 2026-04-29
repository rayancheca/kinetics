import FirebaseAnalytics
import FirebaseCore
import FirebaseFirestore
import Foundation
import SwiftData

// MARK: - GymRepositoryError

enum GymRepositoryError: LocalizedError {
    case noContainer
    case notFound
    case saveFailed(Error)

    var errorDescription: String? {
        switch self {
        case .noContainer:
            "GymRepository has no ModelContainer. Set GymRepository.shared.modelContainer before calling data methods."
        case .notFound:
            "The requested record was not found in the local store."
        case .saveFailed(let underlying):
            "SwiftData save failed: \(underlying.localizedDescription)"
        }
    }
}

// MARK: - GymRepository

/// Local-first data layer for the Gym Tracker module.
///
/// SwiftData is the source of truth for all reads and writes. Firestore is used
/// as a fire-and-forget sync target — failures there never surface as errors to
/// the caller because local data is always available offline.
///
/// **Setup (called once from KineticsApp.swift):**
/// ```swift
/// GymRepository.shared.modelContainer = container
/// ```
@MainActor
final class GymRepository {

    // MARK: - Singleton

    static let shared = GymRepository()

    // MARK: - Container

    /// Set by the App layer after creating the shared `ModelContainer`.
    var modelContainer: ModelContainer?

    // MARK: - Private init

    private init() {}

    // MARK: - Private helpers

    /// Vends a fresh `ModelContext` backed by the installed container.
    /// Throws `GymRepositoryError.noContainer` when called before setup.
    private var context: ModelContext {
        get throws {
            guard let container = modelContainer else {
                throw GymRepositoryError.noContainer
            }
            return ModelContext(container)
        }
    }

    /// `true` only when a real Firebase app has been initialised.
    private var isFirebaseReady: Bool { FirebaseApp.app() != nil }

    // MARK: - Save helper

    private func saveContext(_ ctx: ModelContext) throws {
        do {
            try ctx.save()
        } catch {
            throw GymRepositoryError.saveFailed(error)
        }
    }
}

// MARK: - Exercise CRUD

extension GymRepository {

    /// Inserts or updates an `Exercise` in the local store.
    func saveExercise(_ exercise: Exercise) throws {
        let ctx = try context
        ctx.insert(exercise)
        try saveContext(ctx)
    }

    /// Returns exercises matching an optional free-text filter and/or category.
    ///
    /// - Parameters:
    ///   - filter: Case-insensitive substring matched against `name`. Pass `nil` to skip.
    ///   - category: Exact match against `category`. Pass `nil` to skip.
    func fetchExercises(filter: String? = nil, category: String? = nil) throws -> [Exercise] {
        let ctx = try context
        let descriptor = FetchDescriptor<Exercise>(
            sortBy: [SortDescriptor(\.name, order: .forward)]
        )
        var results = try ctx.fetch(descriptor)
        if let filter, !filter.isEmpty {
            let lower = filter.lowercased()
            results = results.filter { $0.name.lowercased().contains(lower) }
        }
        if let category, !category.isEmpty {
            results = results.filter { $0.category == category }
        }
        return results
    }

    /// Removes an exercise from the local store.
    func deleteExercise(_ exercise: Exercise) throws {
        let ctx = try context
        ctx.delete(exercise)
        try saveContext(ctx)
    }

    /// Flips `isFavorite` for the exercise identified by `exerciseId`.
    func toggleFavorite(exerciseId: String) throws {
        let ctx = try context
        let descriptor = FetchDescriptor<Exercise>(
            predicate: #Predicate { $0.id == exerciseId }
        )
        guard let exercise = try ctx.fetch(descriptor).first else {
            throw GymRepositoryError.notFound
        }
        exercise.isFavorite.toggle()
        try saveContext(ctx)
    }
}

// MARK: - WorkoutSession CRUD

extension GymRepository {

    /// Creates and persists a new in-progress `WorkoutSession` for the given user.
    func createSession(userId: String) throws -> WorkoutSession {
        let ctx = try context
        let session = WorkoutSession(userId: userId)
        ctx.insert(session)
        try saveContext(ctx)
        return session
    }

    /// Returns the most recent `limit` sessions for `userId`, newest first.
    func fetchSessions(userId: String, limit: Int = 20) throws -> [WorkoutSession] {
        let ctx = try context
        var descriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate { $0.userId == userId },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        return try ctx.fetch(descriptor)
    }

    /// Persists any in-memory changes to `session`.
    func saveSession(_ session: WorkoutSession) throws {
        let ctx = try context
        ctx.insert(session)
        try saveContext(ctx)
    }

    /// Removes a session and all its child entries and sets (cascade delete).
    func deleteSession(_ session: WorkoutSession) throws {
        let ctx = try context
        ctx.delete(session)
        try saveContext(ctx)
    }

    /// Marks a session complete, stamps `endedAt`, and kicks off a background
    /// Firestore sync. The sync failure does not propagate to the caller.
    func completeSession(_ session: WorkoutSession) throws {
        let ctx = try context
        session.isCompleted = true
        session.endedAt = Date()
        ctx.insert(session)
        try saveContext(ctx)

        // Fire-and-forget — local data is already persisted at this point.
        Task { await syncSessionToFirestore(session, userId: session.userId) }
    }
}

// MARK: - Set Management

extension GymRepository {

    /// Appends a new `WorkoutSet` to `entry` and returns it.
    func addSet(to entry: WorkoutExerciseEntry, weight: Double, reps: Int) throws -> WorkoutSet {
        let ctx = try context
        let setNumber = entry.sets.count + 1
        let newSet = WorkoutSet(
            setNumber: setNumber,
            weight: weight,
            reps: reps
        )
        ctx.insert(newSet)
        entry.sets.append(newSet)
        try saveContext(ctx)
        return newSet
    }

    /// Updates the weight, reps, and RPE on an existing set.
    func updateSet(_ set: WorkoutSet, weight: Double, reps: Int, rpe: Double) throws {
        let ctx = try context
        set.weight = weight
        set.reps = reps
        set.rpe = rpe
        ctx.insert(set)
        try saveContext(ctx)
    }

    /// Removes a set from the store. The caller is responsible for removing it
    /// from `WorkoutExerciseEntry.sets` if the entry is still in memory.
    func deleteSet(_ set: WorkoutSet) throws {
        let ctx = try context
        ctx.delete(set)
        try saveContext(ctx)
    }

    /// Stamps `completedAt` and flips `isCompleted` on the given set.
    func markSetCompleted(_ set: WorkoutSet) throws {
        let ctx = try context
        set.isCompleted = true
        set.completedAt = Date()
        ctx.insert(set)
        try saveContext(ctx)
    }
}

// MARK: - Personal Records

extension GymRepository {

    /// Returns all personal records belonging to `userId`.
    func fetchPersonalRecords(userId: String) throws -> [PersonalRecord] {
        let ctx = try context
        let descriptor = FetchDescriptor<PersonalRecord>(
            predicate: #Predicate { $0.userId == userId },
            sortBy: [SortDescriptor(\.achievedAt, order: .reverse)]
        )
        return try ctx.fetch(descriptor)
    }

    /// Creates or updates a PR for `exerciseId`.
    ///
    /// The record is only updated when `weight` exceeds the stored value, so
    /// calling this after every completed set is safe — it self-regulates.
    func updatePersonalRecord(
        userId: String,
        exerciseId: String,
        exerciseName: String,
        weight: Double,
        reps: Int
    ) throws {
        let ctx = try context
        let descriptor = FetchDescriptor<PersonalRecord>(
            predicate: #Predicate {
                $0.userId == userId && $0.exerciseId == exerciseId
            }
        )
        let existing = try ctx.fetch(descriptor).first

        if let existing {
            guard weight > existing.weight else { return }
            existing.weight = weight
            existing.reps = reps
            existing.achievedAt = Date()
            ctx.insert(existing)
        } else {
            let pr = PersonalRecord(
                userId: userId,
                exerciseId: exerciseId,
                exerciseName: exerciseName,
                weight: weight,
                reps: reps
            )
            ctx.insert(pr)
        }

        try saveContext(ctx)
    }
}

// MARK: - Exercise Seeding

extension GymRepository {

    /// Populates the library with ~20 canonical exercises on first launch.
    /// Idempotent — returns immediately if any non-custom exercise already exists.
    func seedExerciseLibraryIfNeeded() throws {
        let ctx = try context
        var checkDescriptor = FetchDescriptor<Exercise>(
            predicate: #Predicate { !$0.isCustom }
        )
        checkDescriptor.fetchLimit = 1
        let existing = try ctx.fetch(checkDescriptor)
        guard existing.isEmpty else { return }

        let seeds: [Exercise] = [
            Exercise(
                name: "Barbell Back Squat",
                category: "Strength",
                primaryMuscle: "Quadriceps",
                secondaryMuscles: ["Glutes", "Hamstrings", "Core"],
                equipment: "Barbell",
                instructions: "Bar on upper traps, feet shoulder-width. Brace core, drive knees out, descend until hip crease passes knee. Drive through mid-foot to stand."
            ),
            Exercise(
                name: "Barbell Bench Press",
                category: "Strength",
                primaryMuscle: "Chest",
                secondaryMuscles: ["Triceps", "Shoulders"],
                equipment: "Barbell",
                instructions: "Retract scapulae, slight arch. Lower bar to lower chest under control. Drive through the bar, squeeze chest at lockout."
            ),
            Exercise(
                name: "Deadlift",
                category: "Strength",
                primaryMuscle: "Hamstrings",
                secondaryMuscles: ["Glutes", "Back", "Core"],
                equipment: "Barbell",
                instructions: "Bar over mid-foot, hip-width stance. Hinge to grip, lats engaged. Push the floor away, keep bar against shins. Lock hips and knees simultaneously at the top."
            ),
            Exercise(
                name: "Overhead Press",
                category: "Strength",
                primaryMuscle: "Shoulders",
                secondaryMuscles: ["Triceps", "Core"],
                equipment: "Barbell",
                instructions: "Bar on front deltoids, elbows just in front. Press overhead, push head through at lockout. Lower under control to collarbone."
            ),
            Exercise(
                name: "Barbell Row",
                category: "Strength",
                primaryMuscle: "Back",
                secondaryMuscles: ["Biceps", "Rear Delts"],
                equipment: "Barbell",
                instructions: "Hip hinge until torso is nearly parallel. Pull bar to lower sternum, drive elbows back. Lower under control — do not let momentum bounce the weight."
            ),
            Exercise(
                name: "Dumbbell Curl",
                category: "Strength",
                primaryMuscle: "Biceps",
                secondaryMuscles: ["Forearms"],
                equipment: "Dumbbell",
                instructions: "Supinate wrist as you curl. Full extension at the bottom, squeeze at the top. Avoid swinging the torso."
            ),
            Exercise(
                name: "Tricep Pushdown",
                category: "Strength",
                primaryMuscle: "Triceps",
                secondaryMuscles: [],
                equipment: "Cable",
                instructions: "Elbows pinned at sides, slight forward lean. Push the bar to full extension. Squeeze triceps hard at the bottom before controlled return."
            ),
            Exercise(
                name: "Lat Pulldown",
                category: "Strength",
                primaryMuscle: "Back",
                secondaryMuscles: ["Biceps"],
                equipment: "Cable",
                instructions: "Overhand grip slightly wider than shoulders. Lean back slightly, pull bar to upper chest. Initiate with lats, not arms."
            ),
            Exercise(
                name: "Leg Press",
                category: "Strength",
                primaryMuscle: "Quadriceps",
                secondaryMuscles: ["Glutes", "Hamstrings"],
                equipment: "Machine",
                instructions: "Feet shoulder-width, high on platform for more glute recruitment. Descend until knees are at 90°. Do not lock knees at the top."
            ),
            Exercise(
                name: "Push-up",
                category: "Strength",
                primaryMuscle: "Chest",
                secondaryMuscles: ["Triceps", "Core"],
                equipment: "Bodyweight",
                instructions: "Hands slightly wider than shoulders. Maintain a rigid plank. Lower until chest grazes the floor, then press to full lockout."
            ),
            Exercise(
                name: "Pull-up",
                category: "Strength",
                primaryMuscle: "Back",
                secondaryMuscles: ["Biceps"],
                equipment: "Bodyweight",
                instructions: "Dead hang start, overhand grip. Drive elbows to hips to initiate. Chin clears the bar at the top. Full extension on every rep."
            ),
            Exercise(
                name: "Dip",
                category: "Strength",
                primaryMuscle: "Triceps",
                secondaryMuscles: ["Chest", "Shoulders"],
                equipment: "Bodyweight",
                instructions: "Upright torso targets triceps; forward lean shifts emphasis to chest. Lower until shoulder is at elbow height. Press to full lockout."
            ),
            Exercise(
                name: "Plank",
                category: "Strength",
                primaryMuscle: "Core",
                secondaryMuscles: ["Shoulders"],
                equipment: "Bodyweight",
                instructions: "Forearms on floor, elbows under shoulders. Neutral spine — no sagging hips or raised glutes. Breathe steadily and brace as if taking a punch."
            ),
            Exercise(
                name: "Romanian Deadlift",
                category: "Strength",
                primaryMuscle: "Hamstrings",
                secondaryMuscles: ["Glutes", "Core"],
                equipment: "Barbell",
                instructions: "Start standing, soft knee bend. Push hips back and hinge forward, bar tracking legs. Lower until a deep stretch in the hamstrings, then drive hips forward to stand."
            ),
            Exercise(
                name: "Bulgarian Split Squat",
                category: "Strength",
                primaryMuscle: "Quadriceps",
                secondaryMuscles: ["Glutes", "Hamstrings"],
                equipment: "Dumbbell",
                instructions: "Rear foot elevated on bench, front foot two long strides forward. Descend until front knee is at 90°. Drive through the front heel to stand."
            ),
            Exercise(
                name: "Incline Dumbbell Press",
                category: "Strength",
                primaryMuscle: "Chest",
                secondaryMuscles: ["Shoulders", "Triceps"],
                equipment: "Dumbbell",
                instructions: "Bench at 30-45°. Press from beside the upper chest to full lockout overhead. Lower dumbbells to chest line — avoid flaring elbows excessively."
            ),
            Exercise(
                name: "Face Pull",
                category: "Strength",
                primaryMuscle: "Rear Delts",
                secondaryMuscles: ["Rotator Cuff", "Trapezius"],
                equipment: "Cable",
                instructions: "Cable set above head height, rope attachment. Pull handles to eye level, elbows flaring wide. External-rotate wrists so knuckles face the ceiling at the end."
            ),
            Exercise(
                name: "Goblet Squat",
                category: "Strength",
                primaryMuscle: "Quadriceps",
                secondaryMuscles: ["Glutes", "Core"],
                equipment: "Kettlebell",
                instructions: "Hold the bell at chest height by the horns. Feet shoulder-width, toes slightly out. Sit between the knees, keeping elbows inside thighs. Drive through heels to stand."
            ),
            Exercise(
                name: "Hip Thrust",
                category: "Strength",
                primaryMuscle: "Glutes",
                secondaryMuscles: ["Hamstrings", "Core"],
                equipment: "Barbell",
                instructions: "Upper back on bench, bar across hips over a pad. Plant feet flat, drive hips to full extension. Squeeze glutes hard at the top — do not hyperextend the lumbar."
            ),
            Exercise(
                name: "Clean and Jerk",
                category: "Olympic",
                primaryMuscle: "Full Body",
                secondaryMuscles: ["Quadriceps", "Glutes", "Shoulders", "Core"],
                equipment: "Barbell",
                instructions: "First pull: bar from floor to knees staying over the bar. Second pull: explosive hip extension and high pull. Catch in a front squat rack position. Stand, then split or power jerk overhead to full lockout."
            )
        ]

        for exercise in seeds {
            ctx.insert(exercise)
        }
        try saveContext(ctx)
    }
}

// MARK: - Firebase Sync

private extension GymRepository {

    /// Encodes a completed `WorkoutSession` and writes it to Firestore under
    /// `users/{userId}/gymSessions/{session.id}`.
    ///
    /// This method is fire-and-forget. All errors are swallowed so that a
    /// Firestore failure never blocks the local-first UX.
    func syncSessionToFirestore(_ session: WorkoutSession, userId: String) async {
        guard isFirebaseReady else { return }

        let db = Firestore.firestore()

        // Encode entries to a plain Sendable structure before crossing
        // the isolation boundary into the async Firebase call.
        let entriesData: [[String: Any]] = session.entries.map { entry in
            let setsData: [[String: Any]] = entry.sets.map { set in
                var setDict: [String: Any] = [
                    "id": set.id,
                    "setNumber": set.setNumber,
                    "weight": set.weight,
                    "reps": set.reps,
                    "rpe": set.rpe,
                    "isCompleted": set.isCompleted
                ]
                if let completedAt = set.completedAt {
                    setDict["completedAt"] = completedAt.timeIntervalSince1970 * 1_000
                }
                return setDict
            }
            return [
                "id": entry.id,
                "exerciseId": entry.exerciseId,
                "exerciseName": entry.exerciseName,
                "orderIndex": entry.orderIndex,
                "sets": setsData
            ]
        }

        var payload: [String: Any] = [
            "id": session.id,
            "userId": userId,
            "startedAt": session.startedAt.timeIntervalSince1970 * 1_000,
            "notes": session.notes,
            "isCompleted": session.isCompleted,
            "entries": entriesData
        ]

        if let endedAt = session.endedAt {
            payload["endedAt"] = endedAt.timeIntervalSince1970 * 1_000
        }

        do {
            try await db
                .collection("users")
                .document(userId)
                .collection("gymSessions")
                .document(session.id)
                .setData(payload)

            let durationSeconds: Double
            if let endedAt = session.endedAt {
                durationSeconds = endedAt.timeIntervalSince(session.startedAt)
            } else {
                durationSeconds = 0
            }

            Analytics.logEvent("gym_session_completed", parameters: [
                "session_id": session.id as NSString,
                "user_id": userId as NSString,
                "exercise_count": session.entries.count as NSNumber,
                "duration_seconds": durationSeconds as NSNumber
            ])
        } catch {
            // Intentionally silent — Firestore is a secondary sync target.
            // SwiftData is already persisted locally before this runs.
        }
    }
}
