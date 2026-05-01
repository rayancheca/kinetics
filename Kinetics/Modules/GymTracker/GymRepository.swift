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

        var didSetNewRecord = false

        if let existing {
            guard weight > existing.weight else { return }
            let oldWeight = existing.weight
            existing.previousWeight = oldWeight
            existing.weight = weight
            existing.reps = reps
            existing.achievedAt = Date()
            ctx.insert(existing)
            didSetNewRecord = true
        } else {
            let pr = PersonalRecord(
                userId: userId,
                exerciseId: exerciseId,
                exerciseName: exerciseName,
                weight: weight,
                reps: reps,
                previousWeight: 0
            )
            ctx.insert(pr)
            didSetNewRecord = true
        }

        try saveContext(ctx)

        // Fire achievement notification on main actor without blocking the save.
        if didSetNewRecord {
            let name = exerciseName
            Task { @MainActor in
                await NotificationService.shared.checkPersonalRecordAchievement(
                    exerciseName: name
                )
            }
        }
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

        // Exact 20-exercise canonical library matching the product spec.
        let seeds: [Exercise] = [
            Exercise(
                name: "Bench Press",
                category: "Strength",
                primaryMuscle: "Chest",
                secondaryMuscles: ["Triceps", "Shoulders"],
                equipment: "Barbell",
                instructions: "Retract scapulae, slight arch. Lower bar to lower chest under control. Drive through the bar, squeeze chest at lockout."
            ),
            Exercise(
                name: "Squat",
                category: "Strength",
                primaryMuscle: "Quadriceps",
                secondaryMuscles: ["Glutes", "Hamstrings", "Core"],
                equipment: "Barbell",
                instructions: "Bar on upper traps, feet shoulder-width. Brace core, drive knees out, descend until hip crease passes knee. Drive through mid-foot to stand."
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
                name: "Pull-up",
                category: "Strength",
                primaryMuscle: "Back",
                secondaryMuscles: ["Biceps"],
                equipment: "Bodyweight",
                instructions: "Dead hang start, overhand grip. Drive elbows to hips to initiate. Chin clears the bar at the top. Full extension on every rep."
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
                secondaryMuscles: ["Biceps"],
                equipment: "Barbell",
                instructions: "Hip hinge until torso is nearly parallel. Pull bar to lower sternum, drive elbows back. Lower under control."
            ),
            Exercise(
                name: "Incline Dumbbell Press",
                category: "Strength",
                primaryMuscle: "Chest",
                secondaryMuscles: ["Shoulders", "Triceps"],
                equipment: "Dumbbell",
                instructions: "Bench at 30-45 degrees. Press from beside the upper chest to full lockout overhead. Lower dumbbells to chest line."
            ),
            Exercise(
                name: "Leg Press",
                category: "Strength",
                primaryMuscle: "Quadriceps",
                secondaryMuscles: ["Glutes", "Hamstrings"],
                equipment: "Machine",
                instructions: "Feet shoulder-width, high on platform. Descend until knees are at 90 degrees. Do not lock knees at the top."
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
                name: "Lat Pulldown",
                category: "Strength",
                primaryMuscle: "Back",
                secondaryMuscles: ["Biceps"],
                equipment: "Cable",
                instructions: "Overhand grip slightly wider than shoulders. Lean back slightly, pull bar to upper chest. Initiate with lats, not arms."
            ),
            Exercise(
                name: "Cable Fly",
                category: "Strength",
                primaryMuscle: "Chest",
                secondaryMuscles: ["Shoulders"],
                equipment: "Cable",
                instructions: "Set cables at shoulder height with D-ring handles. Keep a slight elbow bend, arc hands together in front of chest. Control the return."
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
                name: "Bicep Curl",
                category: "Strength",
                primaryMuscle: "Biceps",
                secondaryMuscles: ["Forearms"],
                equipment: "Dumbbell",
                instructions: "Supinate wrist as you curl. Full extension at the bottom, squeeze at the top. Avoid swinging the torso."
            ),
            Exercise(
                name: "Lunges",
                category: "Strength",
                primaryMuscle: "Quadriceps",
                secondaryMuscles: ["Glutes", "Hamstrings", "Core"],
                equipment: "Dumbbell",
                instructions: "Step forward into a long stride. Lower back knee toward the floor, keep front shin vertical. Drive through the front heel to return."
            ),
            Exercise(
                name: "Hip Thrust",
                category: "Strength",
                primaryMuscle: "Glutes",
                secondaryMuscles: ["Hamstrings", "Core"],
                equipment: "Barbell",
                instructions: "Upper back on bench, bar across hips over a pad. Plant feet flat, drive hips to full extension. Squeeze glutes hard at the top."
            ),
            Exercise(
                name: "Plank",
                category: "Strength",
                primaryMuscle: "Core",
                secondaryMuscles: ["Shoulders"],
                equipment: "Bodyweight",
                instructions: "Forearms on floor, elbows under shoulders. Neutral spine. Breathe steadily and brace."
            ),
            Exercise(
                name: "Face Pull",
                category: "Strength",
                primaryMuscle: "Shoulders",
                secondaryMuscles: ["Biceps", "Trapezius"],
                equipment: "Cable",
                instructions: "Cable set above head height, rope attachment. Pull handles to eye level, elbows flaring wide. External-rotate wrists so knuckles face the ceiling."
            ),
            Exercise(
                name: "Lateral Raise",
                category: "Strength",
                primaryMuscle: "Shoulders",
                secondaryMuscles: [],
                equipment: "Dumbbell",
                instructions: "Stand tall, slight forward lean. Raise dumbbells to shoulder height with a slight elbow bend. Lower under control. Avoid shrugging."
            ),
            Exercise(
                name: "Calf Raise",
                category: "Strength",
                primaryMuscle: "Calves",
                secondaryMuscles: [],
                equipment: "Machine",
                instructions: "Rise onto the balls of your feet as high as possible. Pause at the top, then lower to a full stretch. Full range of motion on every rep."
            ),
            Exercise(
                name: "Russian Twist",
                category: "Strength",
                primaryMuscle: "Core",
                secondaryMuscles: [],
                equipment: "Bodyweight",
                instructions: "Sit on the floor with knees bent, lean back slightly. Rotate the torso side to side, touching the floor beside each hip."
            )
        ]

        for exercise in seeds {
            ctx.insert(exercise)
        }
        try saveContext(ctx)
    }
}

// MARK: - Streak Calculation

extension GymRepository {

    /// Returns the current consecutive-day workout streak for `userId`.
    ///
    /// Walks backward from today, checking whether at least one completed
    /// `WorkoutSession` exists for each calendar day. Stops at the first gap
    /// and returns the count of consecutive days found.
    func calculateStreak(userId: String) throws -> Int {
        let sessions = try fetchSessions(userId: userId, limit: 500)
        let completedSessions = sessions.filter { $0.isCompleted }
        guard !completedSessions.isEmpty else { return 0 }

        let calendar = Calendar.current
        // Build a Set of day start dates for O(1) lookup.
        let sessionDays: Set<Date> = Set(
            completedSessions.map { calendar.startOfDay(for: $0.startedAt) }
        )

        var streak = 0
        var dayToCheck = calendar.startOfDay(for: Date())

        while sessionDays.contains(dayToCheck) {
            streak += 1
            guard let previousDay = calendar.date(byAdding: .day, value: -1, to: dayToCheck) else { break }
            dayToCheck = previousDay
        }

        return streak
    }
}

// MARK: - Routine CRUD

extension GymRepository {

    /// Saves a new or updated `Routine` to the local store.
    func saveRoutine(_ routine: Routine) throws {
        let ctx = try context
        ctx.insert(routine)
        try saveContext(ctx)
    }

    /// Returns all routines belonging to `userId`, newest first.
    func fetchRoutines(userId: String) throws -> [Routine] {
        let ctx = try context
        let descriptor = FetchDescriptor<Routine>(
            predicate: #Predicate { $0.userId == userId },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        return try ctx.fetch(descriptor)
    }

    /// Removes a routine from the store.
    func deleteRoutine(_ routine: Routine) throws {
        let ctx = try context
        ctx.delete(routine)
        try saveContext(ctx)
    }

    /// Creates a duplicate of `routine` with a new id and " (Copy)" appended to the name.
    @discardableResult
    func duplicateRoutine(_ routine: Routine) throws -> Routine {
        let copy = Routine(
            userId: routine.userId,
            name: "\(routine.name) (Copy)",
            routineDescription: routine.routineDescription,
            exerciseIds: routine.exerciseIds,
            exerciseNames: routine.exerciseNames,
            slots: routine.slots.enumerated().map { index, slot in
                RoutineExerciseSlot(
                    exerciseId: slot.exerciseId,
                    exerciseName: slot.exerciseName,
                    primaryMuscle: slot.primaryMuscle,
                    orderIndex: index,
                    targetSets: slot.targetSets,
                    targetReps: slot.targetReps,
                    restSeconds: slot.restSeconds
                )
            },
            scheduledDays: routine.scheduledDays,
            notes: routine.notes
        )
        let ctx = try context
        ctx.insert(copy)
        try saveContext(ctx)
        return copy
    }

    /// Stamps `lastUsedAt` on the routine and returns a pre-populated `WorkoutSession`
    /// with one `WorkoutExerciseEntry` per exercise slot (each seeded with blank sets
    /// equal to `slot.targetSets`).
    func startSession(from routine: Routine, userId: String) throws -> WorkoutSession {
        let ctx = try context

        // Stamp last-used date on the routine.
        routine.lastUsedAt = Date()
        ctx.insert(routine)

        let session = WorkoutSession(userId: userId)
        ctx.insert(session)

        let sortedSlots = routine.slots
        for (index, slot) in sortedSlots.enumerated() {
            let entry = WorkoutExerciseEntry(
                exerciseId: slot.exerciseId,
                exerciseName: slot.exerciseName,
                orderIndex: index
            )
            ctx.insert(entry)
            for setNumber in 1...max(1, slot.targetSets) {
                let workoutSet = WorkoutSet(
                    setNumber: setNumber,
                    reps: slot.targetReps
                )
                ctx.insert(workoutSet)
                entry.sets.append(workoutSet)
            }
            session.entries.append(entry)
        }

        try saveContext(ctx)
        return session
    }
}

// MARK: - Async API (caller-friendly wrappers)

/// `async` overloads that mirror the synchronous CRUD layer.
/// These use the same underlying SwiftData context and never propagate
/// non-fatal errors to callers (they return empty collections instead).
extension GymRepository {

    // MARK: Session

    /// Saves or upserts a workout session. Throws on persistence failure.
    func saveWorkoutSession(_ session: WorkoutSession) async throws {
        try saveSession(session)
    }

    /// Returns all completed and in-progress sessions for a user, newest first.
    func fetchWorkoutSessions(userId: String) async -> [WorkoutSession] {
        (try? fetchSessions(userId: userId, limit: 1_000)) ?? []
    }

    /// Returns the `limit` most-recent sessions for a user.
    func fetchRecentSessions(userId: String, limit: Int) async -> [WorkoutSession] {
        (try? fetchSessions(userId: userId, limit: limit)) ?? []
    }

    // MARK: Exercise

    /// Saves an exercise. Throws on persistence failure.
    func saveExercise(_ exercise: Exercise, userId: String) async throws {
        exercise.userId = userId
        try saveExercise(exercise)
    }

    /// Returns all exercises visible to a user (shared library + user's custom ones).
    func fetchExercises(userId: String) async -> [Exercise] {
        guard let ctx = try? context else { return [] }
        let descriptor = FetchDescriptor<Exercise>(
            sortBy: [SortDescriptor(\.name, order: .forward)]
        )
        let all = (try? ctx.fetch(descriptor)) ?? []
        return all.filter { $0.userId == nil || $0.userId == userId }
    }

    /// Returns a single exercise by id, or `nil` when not found.
    func fetchExercise(id: String) async -> Exercise? {
        guard let ctx = try? context else { return nil }
        let descriptor = FetchDescriptor<Exercise>(
            predicate: #Predicate { $0.id == id }
        )
        return (try? ctx.fetch(descriptor))?.first
    }

    /// Deletes a single exercise. Throws on persistence failure.
    func deleteExercise(_ exercise: Exercise) async throws {
        try _deleteExerciseSync(exercise)
    }

    // MARK: Routine

    /// Inserts or updates a routine. Throws on persistence failure.
    func saveRoutine(_ routine: Routine) async throws {
        try _saveRoutineSync(routine)
    }

    /// Returns all routines for a user, most recently created first.
    func fetchRoutines(userId: String) async -> [Routine] {
        (try? _fetchRoutinesSync(userId: userId)) ?? []
    }

    /// Deletes a routine. Throws on persistence failure.
    func deleteRoutine(_ routine: Routine) async throws {
        try _deleteRoutineSync(routine)
    }

    // MARK: Personal Records

    /// Creates or updates a PR. Parameter order matches the public spec.
    /// Only raises the record when `weight` exceeds the stored value.
    /// `previousWeight` is captured and stored automatically by the underlying sync method.
    func updatePersonalRecord(
        exerciseId: String,
        exerciseName: String,
        weight: Double,
        reps: Int,
        userId: String
    ) async {
        try? updatePersonalRecord(
            userId: userId,
            exerciseId: exerciseId,
            exerciseName: exerciseName,
            weight: weight,
            reps: reps
        )
    }

    /// Returns all PRs for a user. Never throws — returns empty on error.
    /// Async overload — delegates to the synchronous `fetchPersonalRecords` implementation.
    func fetchPersonalRecords(userId: String) async -> [PersonalRecord] {
        (try? _fetchPersonalRecordsSync(userId: userId)) ?? []
    }

    /// Returns the PR for a specific exercise, or `nil` when none exists.
    func fetchPersonalRecord(exerciseId: String, userId: String) async -> PersonalRecord? {
        guard let ctx = try? context else { return nil }
        let descriptor = FetchDescriptor<PersonalRecord>(
            predicate: #Predicate { $0.exerciseId == exerciseId && $0.userId == userId }
        )
        return (try? ctx.fetch(descriptor))?.first
    }

    // MARK: Body Measurements

    /// Saves a body measurement. Throws on persistence failure.
    func saveBodyMeasurement(_ measurement: BodyMeasurement) async throws {
        let ctx = try context
        ctx.insert(measurement)
        try saveContext(ctx)
    }

    /// Returns all body measurements for a user, most recent first.
    func fetchBodyMeasurements(userId: String) async -> [BodyMeasurement] {
        guard let ctx = try? context else { return [] }
        let descriptor = FetchDescriptor<BodyMeasurement>(
            predicate: #Predicate { $0.userId == userId },
            sortBy: [SortDescriptor(\.recordedAt, order: .reverse)]
        )
        return (try? ctx.fetch(descriptor)) ?? []
    }

    // MARK: Derived Stats

    /// Number of completed workout sessions in the last 7 calendar days.
    func weeklyWorkoutCount(userId: String) async -> Int {
        guard let ctx = try? context else { return 0 }
        let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        let descriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate { $0.userId == userId && $0.isCompleted && $0.startedAt >= cutoff }
        )
        return (try? ctx.fetch(descriptor))?.count ?? 0
    }

    /// Total training volume in kg lifted during the current calendar month.
    func monthlyVolume(userId: String) async -> Double {
        guard let ctx = try? context else { return 0 }
        let calendar = Calendar.current
        let startOfMonth = calendar.date(
            from: calendar.dateComponents([.year, .month], from: Date())
        ) ?? Date()
        let descriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate { $0.userId == userId && $0.isCompleted && $0.startedAt >= startOfMonth }
        )
        let sessions = (try? ctx.fetch(descriptor)) ?? []
        return sessions.reduce(0.0) { total, session in
            total + session.totalVolumeKg
        }
    }

    /// Number of consecutive calendar days ending today that contain at least one completed session.
    func currentStreak(userId: String) async -> Int {
        (try? calculateStreak(userId: userId)) ?? 0
    }
}

// MARK: - Private sync trampolines
// These private methods exist solely so the async overloads above can call the
// synchronous CRUD implementations without triggering Swift's "prefer async
// overload" resolution and causing infinite recursion.

private extension GymRepository {

    func _deleteExerciseSync(_ exercise: Exercise) throws {
        let ctx = try context
        ctx.delete(exercise)
        try saveContext(ctx)
    }

    func _saveRoutineSync(_ routine: Routine) throws {
        let ctx = try context
        ctx.insert(routine)
        try saveContext(ctx)
    }

    func _fetchRoutinesSync(userId: String) throws -> [Routine] {
        let ctx = try context
        let descriptor = FetchDescriptor<Routine>(
            predicate: #Predicate { $0.userId == userId },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        return try ctx.fetch(descriptor)
    }

    func _deleteRoutineSync(_ routine: Routine) throws {
        let ctx = try context
        ctx.delete(routine)
        try saveContext(ctx)
    }

    func _fetchPersonalRecordsSync(userId: String) throws -> [PersonalRecord] {
        let ctx = try context
        let descriptor = FetchDescriptor<PersonalRecord>(
            predicate: #Predicate { $0.userId == userId },
            sortBy: [SortDescriptor(\.achievedAt, order: .reverse)]
        )
        return try ctx.fetch(descriptor)
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
