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
        session.isCompleted = true
        session.endedAt = Date()
        // Use the session's own ModelContext so the save reaches the same store
        // that owns the object. Creating a new context and calling ctx.insert(session)
        // on an already-tracked object silently fails in SwiftData.
        if let ctx = session.modelContext {
            try saveContext(ctx)
        } else {
            let ctx = try context
            ctx.insert(session)
            try saveContext(ctx)
        }

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

    // swiftlint:disable function_body_length
    /// Populates the library with 200+ canonical exercises.
    /// Uses a version key so updated exercise lists are seeded for all users on upgrade.
    func seedExerciseLibraryIfNeeded() throws {
        let versionKey = "gym.exerciseLibraryV2"
        guard !UserDefaults.standard.bool(forKey: versionKey) else { return }
        UserDefaults.standard.set(true, forKey: versionKey)

        let ctx = try context

        let seeds: [Exercise] = [
            // Chest
            Exercise(name: "Bench Press", category: "Strength", primaryMuscle: "Chest", secondaryMuscles: ["Triceps", "Shoulders"], equipment: "Barbell", instructions: "Retract your scapulae and create a slight arch. Lower the bar under control to your lower pec line, elbows at roughly 75 degrees. Press explosively and squeeze the chest at lockout. Avoid flaring elbows past 90 degrees."),
            Exercise(name: "Incline Bench Press", category: "Strength", primaryMuscle: "Chest", secondaryMuscles: ["Shoulders", "Triceps"], equipment: "Barbell", instructions: "Set the bench to 30-45 degrees. Grip slightly wider than shoulder-width. Lower bar to your upper chest just below the collarbone. Press in a slight arc back toward lockout. Keep arch and scapular retraction throughout."),
            Exercise(name: "Decline Bench Press", category: "Strength", primaryMuscle: "Chest", secondaryMuscles: ["Triceps"], equipment: "Barbell", instructions: "Set decline to 15-30 degrees and secure feet. Grip just wider than shoulder-width. Lower the bar to your lower chest in a controlled arc. Press back to lockout. Maximally loads the sternal head of the pec."),
            Exercise(name: "Dumbbell Fly", category: "Strength", primaryMuscle: "Chest", secondaryMuscles: ["Shoulders"], equipment: "Dumbbell", instructions: "Lie flat with dumbbells pressed above chest, palms facing each other. Maintain a soft elbow bend throughout. Lower in a wide arc until elbows are level with the bench. Squeeze pecs to bring dumbbells back together."),
            Exercise(name: "Cable Crossover", category: "Strength", primaryMuscle: "Chest", secondaryMuscles: ["Shoulders"], equipment: "Cable", instructions: "Set cables to shoulder height with D-ring handles. Step forward into a split stance. With a slight elbow bend, arc your hands down and together in front of your hips. Squeeze at peak contraction. Control the return."),
            Exercise(name: "Push-Up", category: "Strength", primaryMuscle: "Chest", secondaryMuscles: ["Triceps", "Shoulders", "Core"], equipment: "Bodyweight", instructions: "Plant hands slightly wider than shoulder-width, fingers forward. Keep a straight line from head to heels. Lower your chest to within an inch of the floor with elbows at 45-75 degrees. Push back to full extension and protract your scapulae at the top."),
            Exercise(name: "Chest Dip", category: "Strength", primaryMuscle: "Chest", secondaryMuscles: ["Triceps", "Shoulders"], equipment: "Bodyweight", instructions: "Use parallel bars with grip slightly wider than shoulder-width. Lean torso forward at 15-30 degrees to emphasise chest over triceps. Lower until upper arms are parallel to the floor. Press back to full extension."),
            Exercise(name: "Pec Deck", category: "Strength", primaryMuscle: "Chest", secondaryMuscles: [], equipment: "Machine", instructions: "Adjust seat so handles are at chest height. Sit with back flat against pad. Arc both arms together in front of your chest, squeezing pecs hard at peak contraction. Control the return."),
            Exercise(name: "Incline Dumbbell Press", category: "Strength", primaryMuscle: "Chest", secondaryMuscles: ["Shoulders", "Triceps"], equipment: "Dumbbell", instructions: "Set bench to 30-45 degrees. Press dumbbells from beside your upper chest to full lockout overhead. Lower back to chest level slowly, feeling the upper pec stretch. Keep wrists stacked over elbows throughout."),
            // Back
            Exercise(name: "Pull-Up", category: "Strength", primaryMuscle: "Back", secondaryMuscles: ["Biceps"], equipment: "Bodyweight", instructions: "Start from a dead hang with an overhand grip slightly wider than shoulder-width. Engage core and squeeze lats before pulling. Drive elbows down toward hips. Chin clears the bar at the top. Lower to full extension on every rep."),
            Exercise(name: "Lat Pulldown", category: "Strength", primaryMuscle: "Back", secondaryMuscles: ["Biceps"], equipment: "Cable", instructions: "Overhand grip slightly wider than shoulder-width, knees secured. Lean back slightly. Initiate by depressing scapulae, then pull the bar to your upper chest. Pause and squeeze lats. Arms are just hooks; do not pull primarily with biceps."),
            Exercise(name: "Bent-Over Barbell Row", category: "Strength", primaryMuscle: "Back", secondaryMuscles: ["Biceps"], equipment: "Barbell", instructions: "Hip hinge until torso is nearly parallel to the floor. Pull bar to lower sternum, driving elbows back. Hold for a beat at the top. Brace core to prevent lower back rounding. Avoid jerking with hips."),
            Exercise(name: "Seated Cable Row", category: "Strength", primaryMuscle: "Back", secondaryMuscles: ["Biceps"], equipment: "Cable", instructions: "Sit with a slight forward lean. Pull handle to your lower sternum, driving elbows behind your body and squeezing shoulder blades at peak contraction. Sit upright at the end of the pull. Control the extension."),
            Exercise(name: "T-Bar Row", category: "Strength", primaryMuscle: "Back", secondaryMuscles: ["Biceps"], equipment: "Barbell", instructions: "Straddle a landmine-anchored barbell. Hip hinge to 45 degrees and grip the handle. Row to your sternum with a neutral grip, driving elbows back. Squeeze lats and rhomboids hard at the top."),
            Exercise(name: "Deadlift", category: "Strength", primaryMuscle: "Back", secondaryMuscles: ["Hamstrings", "Glutes", "Core"], equipment: "Barbell", instructions: "Bar over mid-foot, hip-width stance, shins to the bar. Hinge to grip with lats engaged and chest proud. Brace hard. Push the floor away keeping the bar dragging up your shins. Lock out hips and knees simultaneously. Lower by hinging first then bending knees."),
            Exercise(name: "Face Pull", category: "Strength", primaryMuscle: "Shoulders", secondaryMuscles: ["Back"], equipment: "Cable", instructions: "Set cable above head height with a rope attachment. Pull rope to eye level with elbows flaring wide and high. Externally rotate wrists at the end so knuckles face the ceiling. This activates rear delts and rotator cuff fully. Control the return."),
            Exercise(name: "Good Morning", category: "Strength", primaryMuscle: "Hamstrings", secondaryMuscles: ["Back", "Glutes"], equipment: "Barbell", instructions: "Place the bar on upper traps and brace your core. Push hips back while hinging at the waist, keeping a neutral spine. Lower torso until nearly parallel to the floor. Drive hips forward to return to standing. Keep a slight knee bend throughout."),
            // Shoulders
            Exercise(name: "Overhead Press", category: "Strength", primaryMuscle: "Shoulders", secondaryMuscles: ["Triceps", "Core"], equipment: "Barbell", instructions: "Bar on front deltoids, elbows just in front of the bar. Brace and squeeze glutes. Press overhead, pushing head through the window at lockout. Bar travels in a slight arc over the crown of your head. Lower under control to the clavicle."),
            Exercise(name: "Arnold Press", category: "Strength", primaryMuscle: "Shoulders", secondaryMuscles: ["Triceps"], equipment: "Dumbbell", instructions: "Start with palms facing your face and elbows at shoulder height. As you press overhead rotate palms outward so they face forward at the top. Reverse on the way down. The rotation recruits all three heads of the deltoid. Move with control."),
            Exercise(name: "Lateral Raise", category: "Strength", primaryMuscle: "Shoulders", secondaryMuscles: [], equipment: "Dumbbell", instructions: "Stand tall with a slight forward lean. Raise dumbbells to shoulder height with a slight elbow bend, leading with your elbows. Lower under control. Avoid shrugging or using momentum. Slow, controlled reps maximise medial delt activation."),
            Exercise(name: "Front Raise", category: "Strength", primaryMuscle: "Shoulders", secondaryMuscles: [], equipment: "Dumbbell", instructions: "Stand with dumbbells at your thighs. With a slight elbow bend, raise one or both arms to shoulder height in front of you. Lower slowly. Avoid leaning back or swinging. Alternate arms to allow the working side to fully contract."),
            Exercise(name: "Reverse Fly", category: "Strength", primaryMuscle: "Shoulders", secondaryMuscles: ["Back"], equipment: "Dumbbell", instructions: "Hip hinge with torso nearly parallel, or use an incline bench. With a slight elbow bend, arc dumbbells upward and out to your sides until arms are parallel to the floor. Squeeze rear delts at the top. Avoid shrugging traps."),
            Exercise(name: "Upright Row", category: "Strength", primaryMuscle: "Shoulders", secondaryMuscles: ["Back"], equipment: "Barbell", instructions: "Grip the bar slightly narrower than shoulder-width. Pull upward, leading with elbows which travel higher than wrists. Stop when elbows are at chin height. Use a wider grip to reduce shoulder impingement risk."),
            Exercise(name: "Shrug", category: "Strength", primaryMuscle: "Back", secondaryMuscles: [], equipment: "Barbell", instructions: "Hold barbell or dumbbells at arm's length. Elevate shoulders straight up toward ears as high as possible. Hold at the peak for one second. Lower slowly to a full depression. Do not roll your shoulders; pure elevation and depression only."),
            // Biceps
            Exercise(name: "Barbell Curl", category: "Strength", primaryMuscle: "Biceps", secondaryMuscles: ["Forearms"], equipment: "Barbell", instructions: "Stand with underhand grip just wider than hip-width. Curl from full extension to full contraction, keeping upper arms pinned to sides. Squeeze hard at the top. Lower slowly for the eccentric. If you need to swing the weight is too heavy."),
            Exercise(name: "Dumbbell Curl", category: "Strength", primaryMuscle: "Biceps", secondaryMuscles: ["Forearms"], equipment: "Dumbbell", instructions: "Hold dumbbells at sides with palms forward. Curl from full extension, supinating wrist as you lift. Squeeze at the top. Lower under control. Can be done alternating or simultaneously. Keep core tight and upper body still."),
            Exercise(name: "Hammer Curl", category: "Strength", primaryMuscle: "Biceps", secondaryMuscles: ["Forearms"], equipment: "Dumbbell", instructions: "Hold dumbbells with a neutral grip, palms facing each other. Curl to shoulder height without rotating wrist. Heavily loads the brachialis and brachioradialis. Lower fully before next rep. Can be done alternating or simultaneously."),
            Exercise(name: "Incline Dumbbell Curl", category: "Strength", primaryMuscle: "Biceps", secondaryMuscles: [], equipment: "Dumbbell", instructions: "Set bench to 45-60 degrees and sit back so arms hang behind torso, pre-stretching the bicep long head. Curl from full extension, supinating at the top. Use lighter weight than standing curls. Lower slowly for maximum tension."),
            Exercise(name: "Concentration Curl", category: "Strength", primaryMuscle: "Biceps", secondaryMuscles: [], equipment: "Dumbbell", instructions: "Sit on a bench with your elbow braced against the inside of your thigh. Curl from full extension to peak contraction and squeeze hard. Lower slowly to a full stretch. The braced position eliminates cheating entirely."),
            Exercise(name: "Cable Curl", category: "Strength", primaryMuscle: "Biceps", secondaryMuscles: ["Forearms"], equipment: "Cable", instructions: "Attach a straight or EZ-bar to a low cable pulley. Stand facing the machine and curl, keeping upper arms stationary. Cables maintain constant tension through the full range of motion. Control the return slowly."),
            // Triceps
            Exercise(name: "Skull Crusher", category: "Strength", primaryMuscle: "Triceps", secondaryMuscles: [], equipment: "Barbell", instructions: "Lie flat with an EZ-bar locked out above your chest. Keeping upper arms vertical, lower the bar toward your forehead by bending elbows. Press back to lockout. Keep upper arm angle critical and do not let them drift."),
            Exercise(name: "Tricep Dip", category: "Strength", primaryMuscle: "Triceps", secondaryMuscles: ["Chest", "Shoulders"], equipment: "Bodyweight", instructions: "Use parallel bars and keep torso upright to emphasise triceps. Lower until upper arms are parallel to the floor. Press back to full extension. Unlike chest dips keep a more upright torso and elbows closer to body."),
            Exercise(name: "Overhead Tricep Extension", category: "Strength", primaryMuscle: "Triceps", secondaryMuscles: [], equipment: "Dumbbell", instructions: "Hold one dumbbell with both hands overhead. Lower it behind your head by bending elbows, keeping upper arms close to ears. Press back to full extension and squeeze. The overhead position stretches the long head maximally."),
            Exercise(name: "Cable Pushdown", category: "Strength", primaryMuscle: "Triceps", secondaryMuscles: [], equipment: "Cable", instructions: "Attach bar or rope to a high pulley. Elbows pinned at sides with slight forward lean. Push down to full extension and squeeze hard at bottom. Control the return until forearms are at roughly 90 degrees."),
            Exercise(name: "Close-Grip Bench Press", category: "Strength", primaryMuscle: "Triceps", secondaryMuscles: ["Chest"], equipment: "Barbell", instructions: "Grip the bar slightly inside shoulder-width. Lower to your lower chest, keeping elbows tucked close to torso. Press back to lockout focusing on pushing triceps into the bar. Avoid a grip too narrow as this strains wrists."),
            Exercise(name: "Tricep Kickback", category: "Strength", primaryMuscle: "Triceps", secondaryMuscles: [], equipment: "Dumbbell", instructions: "Hip hinge with your upper arm parallel to the floor and elbow bent at 90 degrees. Extend forearm back until arm is fully straight. Squeeze the tricep hard. Lower to 90 degrees and repeat. Keep upper arm completely still."),
            // Legs
            Exercise(name: "Squat", category: "Strength", primaryMuscle: "Quadriceps", secondaryMuscles: ["Glutes", "Hamstrings", "Core"], equipment: "Barbell", instructions: "Bar on upper traps, feet shoulder-width with toes slightly flared. Brace hard, drive knees out over toes, descend until hip crease passes knee. Drive through mid-foot to stand, pushing knees outward the entire way up."),
            Exercise(name: "Front Squat", category: "Strength", primaryMuscle: "Quadriceps", secondaryMuscles: ["Core", "Shoulders"], equipment: "Barbell", instructions: "Bar rests across front deltoids with elbows high to create a shelf. Keep an extremely upright torso throughout. Descend to full depth, driving knees out. Front squats demand more core and upper back strength than back squats."),
            Exercise(name: "Leg Press", category: "Strength", primaryMuscle: "Quadriceps", secondaryMuscles: ["Glutes", "Hamstrings"], equipment: "Machine", instructions: "Feet shoulder-width on platform, toes slightly out. Descend until knees are at 90 degrees. Do not let lower back peel off the seat. Drive through mid-foot to near-lockout. Higher foot placement shifts emphasis to glutes."),
            Exercise(name: "Lunge", category: "Strength", primaryMuscle: "Quadriceps", secondaryMuscles: ["Glutes", "Hamstrings", "Core"], equipment: "Dumbbell", instructions: "Step forward into a long stride. Lower back knee toward floor until front shin is vertical. Drive through front heel to return to standing. Keep chest up throughout. Ensure stride is long enough so front knee does not drift past the toe."),
            Exercise(name: "Romanian Deadlift", category: "Strength", primaryMuscle: "Hamstrings", secondaryMuscles: ["Glutes", "Core"], equipment: "Barbell", instructions: "Start standing with barbell at hips. Maintain soft knee bend, push hips back, and hinge forward tracking bar down your thighs. Lower until a deep stretch through hamstrings, typically mid-shin. Drive hips forward to stand. Back stays neutral throughout."),
            Exercise(name: "Leg Curl", category: "Strength", primaryMuscle: "Hamstrings", secondaryMuscles: [], equipment: "Machine", instructions: "Lie face down with pad just above heels. Curl heels toward glutes under control. Squeeze at peak contraction and lower slowly. Avoid lifting hips off the pad. Pointed toes slightly increase hamstring activation."),
            Exercise(name: "Leg Extension", category: "Strength", primaryMuscle: "Quadriceps", secondaryMuscles: [], equipment: "Machine", instructions: "Sit with pad resting on shins just above feet. Extend legs to near lockout, squeezing quads at top. Lower under control and do not let weight stack crash. Avoid locking knees under heavy load. Use as isolation, not primary movement."),
            Exercise(name: "Calf Raise", category: "Strength", primaryMuscle: "Calves", secondaryMuscles: [], equipment: "Machine", instructions: "Place balls of feet on edge of platform with heels hanging off. Rise onto toes as high as possible. Pause at peak to eliminate stretch reflex. Lower slowly to a full stretch. Full range of motion every rep is critical for calf development."),
            Exercise(name: "Hip Thrust", category: "Strength", primaryMuscle: "Glutes", secondaryMuscles: ["Hamstrings", "Core"], equipment: "Barbell", instructions: "Rest upper back on bench with padded bar across hips. Plant feet flat roughly under knees. Drive hips upward until body forms a straight line from knees to shoulders. Squeeze glutes maximally at the top. Lower to just above floor and repeat."),
            Exercise(name: "Bulgarian Split Squat", category: "Strength", primaryMuscle: "Quadriceps", secondaryMuscles: ["Glutes", "Hamstrings"], equipment: "Dumbbell", instructions: "Rear foot elevated on a bench behind you. Hold dumbbells at sides. Descend until rear knee nearly touches the floor, keeping torso upright. Drive through front heel to return. Foot placement determines emphasis: further forward targets glutes, closer forward targets quads."),
            // Core
            Exercise(name: "Plank", category: "Strength", primaryMuscle: "Core", secondaryMuscles: ["Shoulders"], equipment: "Bodyweight", instructions: "Forearms on floor with elbows directly under shoulders. Create a straight line from head to heels. Actively brace your core, squeeze glutes, and breathe steadily. Avoid letting hips sag or pike. Add difficulty with a weight vest or elevated feet."),
            Exercise(name: "Crunch", category: "Strength", primaryMuscle: "Core", secondaryMuscles: [], equipment: "Bodyweight", instructions: "Lie on back with knees bent. Fingertips lightly behind ears, do not pull neck. Curl shoulders off floor by contracting abs, bringing ribcage toward hips. Do not reach for knees. Pause at top and lower with control. Exhale during the crunch."),
            Exercise(name: "Hanging Leg Raise", category: "Strength", primaryMuscle: "Core", secondaryMuscles: [], equipment: "Bodyweight", instructions: "Hang from a pull-up bar in a dead hang. Brace core and raise legs until parallel to the floor or higher. Avoid swinging; control both the raise and lowering phase. Bend knees to reduce difficulty. Keep legs straight to increase it."),
            Exercise(name: "Cable Crunch", category: "Strength", primaryMuscle: "Core", secondaryMuscles: [], equipment: "Cable", instructions: "Kneel below high pulley with rope attachment. Grasp rope on either side of face. Crunch elbows toward knees by flexing the spine; hips stay stationary. This is a spinal flexion movement, not a hip flexion. Hold at the bottom contraction."),
            Exercise(name: "Russian Twist", category: "Strength", primaryMuscle: "Core", secondaryMuscles: [], equipment: "Bodyweight", instructions: "Sit on floor with knees bent at 90 degrees, feet elevated slightly. Lean back about 45 degrees. Rotate torso side to side, touching the floor beside each hip. Hold a weight plate or medicine ball to add resistance. Keep lower back neutral."),
            Exercise(name: "Ab Wheel Rollout", category: "Strength", primaryMuscle: "Core", secondaryMuscles: ["Shoulders", "Back"], equipment: "Other", instructions: "Kneel on floor and grip the ab wheel handles. Brace core hard before starting. Roll forward slowly, keeping hips low and lower back from sagging. Extend as far as possible while maintaining the rigid brace. Pull yourself back with abs, not arms."),
            // Full Body / Olympic / Conditioning
            Exercise(name: "Power Clean", category: "Strength", primaryMuscle: "Full Body", secondaryMuscles: ["Quadriceps", "Glutes", "Back", "Shoulders"], equipment: "Barbell", instructions: "Start with bar over mid-foot, grip just outside legs. First pull: push the floor keeping bar close. At mid-thigh, explode with hips via triple extension. Shrug aggressively, then pull yourself under and catch in a front rack position. Stand to full extension to complete."),
            Exercise(name: "Kettlebell Swing", category: "Strength", primaryMuscle: "Glutes", secondaryMuscles: ["Hamstrings", "Core", "Back"], equipment: "Kettlebell", instructions: "Hike kettlebell back between legs in a hip hinge, not a squat. Snap hips forward aggressively to drive the bell to shoulder height. Power comes from hip extension, not from lifting with arms. Let the bell float at shoulder height. Control the hike back for next rep."),
            Exercise(name: "Battle Ropes", category: "Cardio", primaryMuscle: "Full Body", secondaryMuscles: ["Shoulders", "Core"], equipment: "Other", instructions: "Hold one end of each rope with a neutral grip, standing a few feet from the anchor. Alternate arms creating large waves, or slam both simultaneously. Use your entire body; hips and legs drive the power through core to arms. Work in 20-30 second intervals."),
            Exercise(name: "Farmer's Walk", category: "Strength", primaryMuscle: "Full Body", secondaryMuscles: ["Core", "Forearms", "Back"], equipment: "Dumbbell", instructions: "Pick up heavy dumbbells or kettlebells in each hand. Stand tall with chest up, shoulders packed down and back. Walk with deliberate controlled steps. Brace core the entire distance. Focus on grip strength and upright posture. One of the best core stability movements available."),
            Exercise(name: "Lateral Lunge", category: "Strength", primaryMuscle: "Quadriceps", secondaryMuscles: ["Glutes", "Hamstrings"], equipment: "Bodyweight", instructions: "Stand with feet together. Step one foot wide to the side, pushing hips back as you bend the stepping knee. Keep the opposite leg straight. Push off the bent-knee leg to return. Lateral lunges target the inner thigh and load the hip through a different plane of motion."),

            // MARK: - Chest (additional)
            Exercise(name: "Dumbbell Pullover", category: "Strength", primaryMuscle: "Chest", secondaryMuscles: ["Back", "Triceps"], equipment: "Dumbbell", instructions: "Lie across a flat bench with only your upper back supported. Hold one dumbbell with both hands above your chest, arms nearly straight. Lower the dumbbell in an arc behind your head until you feel a deep stretch across the chest and lats. Pull back over your chest in the same arc. Keep a slight elbow bend throughout."),
            Exercise(name: "Svend Press", category: "Strength", primaryMuscle: "Chest", secondaryMuscles: ["Shoulders"], equipment: "Other", instructions: "Hold two weight plates pressed together between both palms at chest height. Press arms straight out in front of you while squeezing the plates together maximally. The continuous inward squeeze creates intense pec activation throughout. Return slowly to chest. A small amount of weight goes a long way."),
            Exercise(name: "Landmine Press", category: "Strength", primaryMuscle: "Chest", secondaryMuscles: ["Shoulders", "Triceps", "Core"], equipment: "Barbell", instructions: "Anchor one end of a barbell in a landmine base or corner. Grip the free end with one or both hands at chest height. Press the bar forward and upward in an arc until your arm is nearly straight. The arc mimics a natural pressing motion and is joint-friendly. Lower under control back to chest."),
            Exercise(name: "Hex Press", category: "Strength", primaryMuscle: "Chest", secondaryMuscles: ["Triceps"], equipment: "Dumbbell", instructions: "Lie flat on a bench and press two dumbbells together, touching throughout the entire movement. Keep them pressed tightly against each other as you lower to your chest and press back up. The constant adduction force recruits the inner pec fibres intensely. Use moderate weight and full control."),

            // MARK: - Back (additional)
            Exercise(name: "Single Arm Dumbbell Row", category: "Strength", primaryMuscle: "Back", secondaryMuscles: ["Biceps"], equipment: "Dumbbell", instructions: "Place one knee and same-side hand on a bench. Hold a dumbbell in the opposite hand hanging at arm's length. Row the dumbbell to your hip, driving the elbow up and back. Feel the lat contract at the top. Lower to a full stretch before the next rep. Keep your torso parallel to the floor."),
            Exercise(name: "Pendlay Row", category: "Strength", primaryMuscle: "Back", secondaryMuscles: ["Biceps", "Core"], equipment: "Barbell", instructions: "Set up like a bent-over row but let the bar rest on the floor each rep. Torso must be nearly horizontal. Explosively row the bar to your lower sternum, then lower it back to the floor under control. The dead stop eliminates momentum and demands a powerful hip-to-back drive each rep."),
            Exercise(name: "Meadows Row", category: "Strength", primaryMuscle: "Back", secondaryMuscles: ["Biceps", "Forearms"], equipment: "Barbell", instructions: "Stand perpendicular to a landmine-anchored barbell. Hinge forward and grip the sleeve end with one hand. Row the bar to your hip, leading with a high elbow in a slight outward arc that hits the upper lat differently than standard rows. Brace your core and keep the torso stable throughout."),
            Exercise(name: "Chest-Supported Row", category: "Strength", primaryMuscle: "Back", secondaryMuscles: ["Biceps"], equipment: "Dumbbell", instructions: "Set an incline bench to 30-45 degrees. Lie chest-down with dumbbells hanging below. Row both dumbbells toward your hips simultaneously, squeezing shoulder blades together at the top. The chest support eliminates lower back fatigue and momentum, making this a pure upper-back builder."),
            Exercise(name: "Seal Row", category: "Strength", primaryMuscle: "Back", secondaryMuscles: ["Biceps"], equipment: "Barbell", instructions: "Set up a barbell on a raised platform and lie face-down on a bench positioned above it. Grip the bar at shoulder-width and row to your chest with a strict, fully supported torso. The bench support creates a pure horizontal pull with zero hip or lower back involvement."),
            Exercise(name: "Cable Straight Arm Pulldown", category: "Strength", primaryMuscle: "Back", secondaryMuscles: ["Core"], equipment: "Cable", instructions: "Stand facing a high cable with a straight bar or rope. Arms extended overhead. Keeping arms nearly straight, pull the bar down to your thighs by extending at the shoulder joint — no elbow bending. Squeeze the lats hard at the bottom. This is a lat isolation movement that mimics the lat pulldown finishing position."),
            Exercise(name: "Rack Pull", category: "Strength", primaryMuscle: "Back", secondaryMuscles: ["Glutes", "Hamstrings", "Core"], equipment: "Barbell", instructions: "Set the safety pins in a rack at knee height or just above. Pull from this shortened range with a standard deadlift setup. The reduced range of motion allows heavier loads and emphasises the lockout portion. Brace your core maximally and drive hips forward to lock out. Great for upper back and trap overload."),
            Exercise(name: "Deficit Deadlift", category: "Strength", primaryMuscle: "Back", secondaryMuscles: ["Hamstrings", "Glutes", "Core"], equipment: "Barbell", instructions: "Stand on a 1-4 inch platform with the bar on the floor. Setup as a standard deadlift but the increased range of motion demands greater leg drive from the floor. This builds starting strength and improves hip mobility. Pull through the full range maintaining a neutral spine."),
            Exercise(name: "Sumo Deadlift", category: "Strength", primaryMuscle: "Back", secondaryMuscles: ["Glutes", "Quadriceps", "Hamstrings"], equipment: "Barbell", instructions: "Take a wide stance with toes pointed out 30-45 degrees. Grip inside your legs and push knees outward into your arms. The more upright torso angle places greater demand on the quads and hips. Drive the floor away to break the bar off the ground, then drive hips through at lockout."),
            Exercise(name: "Trap Bar Deadlift", category: "Strength", primaryMuscle: "Back", secondaryMuscles: ["Quadriceps", "Glutes", "Hamstrings"], equipment: "Other", instructions: "Step inside the hex bar with feet hip-width. Hinge down and grip the handles. Drive through your feet with a more squat-like pattern than a straight bar deadlift. The neutral grip and load alignment make this joint-friendly and ideal for athletes or beginners. Lockout with hips and knees simultaneously."),
            Exercise(name: "Band Pull-Apart", category: "Strength", primaryMuscle: "Shoulders", secondaryMuscles: ["Back"], equipment: "Band", instructions: "Hold a resistance band with both hands in front of you at shoulder height, arms straight. Pull the band apart by driving your hands out to your sides, squeezing shoulder blades together and contracting rear delts. Control the return. An excellent warm-up, posture corrector, and shoulder health exercise."),

            // MARK: - Shoulders (additional)
            Exercise(name: "Pike Push-Up", category: "Strength", primaryMuscle: "Shoulders", secondaryMuscles: ["Triceps", "Core"], equipment: "Bodyweight", instructions: "Start in a downward dog position with hips high. Lower your head toward the floor between your hands by bending elbows outward. Press back up to the starting position. The inverted angle shifts load from the chest to the front and lateral deltoids. Elevate your feet to increase difficulty."),
            Exercise(name: "Handstand Push-Up", category: "Strength", primaryMuscle: "Shoulders", secondaryMuscles: ["Triceps", "Core"], equipment: "Bodyweight", instructions: "Kick into a handstand against a wall, hands shoulder-width, a few inches from the wall. Lower your head toward the floor by bending elbows while maintaining a braced body position. Press back to full lockout. Build strength progressively from pike push-ups before attempting this. Wall support is essential until balance is developed."),
            Exercise(name: "Bradford Press", category: "Strength", primaryMuscle: "Shoulders", secondaryMuscles: ["Triceps"], equipment: "Barbell", instructions: "Start with the bar at the front of your shoulders. Press just enough to clear your head and swing it behind to the back of your neck, then press forward again. This continuous motion alternates front and back press, creating massive time under tension for all deltoid heads. Use light weight and smooth motion."),
            Exercise(name: "Cuban Press", category: "Strength", primaryMuscle: "Shoulders", secondaryMuscles: ["Back"], equipment: "Dumbbell", instructions: "Start with dumbbells hanging at your sides. Perform an upright row to chin height, then externally rotate your forearms so they point upward, then press overhead. Reverse the motion on the way down. The external rotation strengthens the rotator cuff and rear delts in the scapular plane — an excellent shoulder health movement."),
            Exercise(name: "Scott Press", category: "Strength", primaryMuscle: "Shoulders", secondaryMuscles: ["Triceps"], equipment: "Dumbbell", instructions: "Hold dumbbells with palms facing forward, elbows bent to 90 degrees at shoulder height, like a goalpost. Press overhead while rotating palms inward so they face each other at the top. Lower back to the goalpost position. The rotation engages all three deltoid heads and the rotator cuff through a full range of motion."),
            Exercise(name: "Klokov Press", category: "Strength", primaryMuscle: "Shoulders", secondaryMuscles: ["Back", "Triceps"], equipment: "Barbell", instructions: "Use a wide snatch grip. Press the bar overhead from behind the neck. The wide grip and behind-neck position fully externally rotates the shoulder joint, loading the lateral and rear delts through an extreme range. Start very light to build mobility and stability before adding load. Not appropriate with poor shoulder mobility."),
            Exercise(name: "Dumbbell Y-Raise", category: "Strength", primaryMuscle: "Shoulders", secondaryMuscles: ["Back"], equipment: "Dumbbell", instructions: "Lie face-down on an incline bench set to 30-45 degrees, or stand in a hip hinge. With thumbs up, raise both arms at 45 degrees from your torso to form a Y shape at the top. Targets the lower and mid trapezius and rear deltoid. Use very light weight with a two-second pause at the top."),
            Exercise(name: "Dumbbell W-Raise", category: "Strength", primaryMuscle: "Shoulders", secondaryMuscles: ["Back"], equipment: "Dumbbell", instructions: "Lie face-down on an incline bench. Start with elbows at 90 degrees and upper arms parallel to the floor forming a W shape. Externally rotate by driving fists toward the ceiling while keeping upper arms horizontal. Hold for a count at peak external rotation. Directly targets the infraspinatus and teres minor for rotator cuff health."),
            Exercise(name: "Battle Rope Alternating Wave", category: "Cardio", primaryMuscle: "Shoulders", secondaryMuscles: ["Core", "Full Body"], equipment: "Other", instructions: "Stand in an athletic stance with knees slightly bent, holding one end of a battle rope in each hand. Alternate raising and lowering each arm to create continuous waves down the rope. Drive power from your legs and hips through your core to your arms. Work in 20-40 second intervals with full power output."),

            // MARK: - Biceps (additional)
            Exercise(name: "Preacher Curl", category: "Strength", primaryMuscle: "Biceps", secondaryMuscles: ["Forearms"], equipment: "Barbell", instructions: "Rest the backs of your upper arms on the angled pad of a preacher bench. Curl from near-full extension to peak contraction. The pad eliminates momentum and places maximum tension on the lower biceps and brachialis. Lower very slowly to a full stretch — the eccentric on a preacher is extremely effective."),
            Exercise(name: "Zottman Curl", category: "Strength", primaryMuscle: "Biceps", secondaryMuscles: ["Forearms"], equipment: "Dumbbell", instructions: "Curl dumbbells with a supinated grip to the top. At peak contraction, pronate your wrists to an overhand grip and lower slowly under full control. The supinated ascent loads the biceps; the pronated descent loads the brachioradialis and forearms eccentrically. Both directions are equally slow and deliberate."),
            Exercise(name: "Cross Body Curl", category: "Strength", primaryMuscle: "Biceps", secondaryMuscles: ["Forearms"], equipment: "Dumbbell", instructions: "Hold a dumbbell at your side and curl it across your body toward the opposite shoulder, rather than straight up. This angle shifts the line of pull to better recruit the brachialis and brachioradialis alongside the biceps. Alternate arms and keep the upper arm stationary throughout."),
            Exercise(name: "Drag Curl", category: "Strength", primaryMuscle: "Biceps", secondaryMuscles: [], equipment: "Barbell", instructions: "Start with a barbell in the standard curl position. As you curl, instead of arcing the bar forward, drag it up your torso by moving your elbows back behind your body. The bar stays in contact or near your body the entire way. This keeps the bicep under more tension at longer muscle lengths and reduces front delt involvement."),
            Exercise(name: "21s", category: "Strength", primaryMuscle: "Biceps", secondaryMuscles: ["Forearms"], equipment: "Barbell", instructions: "Perform 7 half-reps from the bottom to the halfway point, then 7 half-reps from halfway to the top, then 7 full-range reps without rest. The metabolic stress and constant tension create a significant pump. Use about 60% of your normal curl weight. Control every portion — this is not a speed exercise."),
            Exercise(name: "Spider Curl", category: "Strength", primaryMuscle: "Biceps", secondaryMuscles: [], equipment: "Dumbbell", instructions: "Lie face-down on an incline bench set to 45-60 degrees. Arms hang straight down perpendicular to the floor. Curl dumbbells up toward your shoulders without moving your upper arms. The incline position stretches the biceps at full extension and eliminates momentum completely. Lower slowly for maximum tension."),

            // MARK: - Triceps (additional)
            Exercise(name: "Diamond Push-Up", category: "Strength", primaryMuscle: "Triceps", secondaryMuscles: ["Chest"], equipment: "Bodyweight", instructions: "Form a diamond shape with your thumbs and forefingers and place hands on the floor under your chest. Lower your chest to your hands with elbows tracking back rather than flaring. Press back to full extension and squeeze triceps at the top. This is a significant step up from regular push-ups in tricep demand."),
            Exercise(name: "Tate Press", category: "Strength", primaryMuscle: "Triceps", secondaryMuscles: [], equipment: "Dumbbell", instructions: "Lie flat with dumbbells held directly over your chest, palms facing each other. Lower the dumbbells by bending only at the elbows, allowing them to rotate outward and come toward your pecs. Your elbows flare out wide. Press back to the top by straightening the elbows. Closely related to a skull crusher but with a different elbow path."),
            Exercise(name: "JM Press", category: "Strength", primaryMuscle: "Triceps", secondaryMuscles: ["Chest"], equipment: "Barbell", instructions: "Lie flat with a close-to-shoulder-width grip. Lower the bar toward your chin and throat by bending elbows and allowing them to flare slightly. The bar touches or comes very close to your neck, not your chest. This is a hybrid of a close-grip bench and skull crusher invented by powerlifter JM Blakely. Start light to learn the movement."),
            Exercise(name: "Tricep Pushdown (V-Bar)", category: "Strength", primaryMuscle: "Triceps", secondaryMuscles: [], equipment: "Cable", instructions: "Attach a V-bar to a high cable pulley. Stand close to the stack and grip the bar with a neutral grip. Pin upper arms to your sides. Push down to full lockout, squeezing triceps hard at the bottom. The V-bar position places the wrists in a natural neutral angle that many find more comfortable than a straight bar."),
            Exercise(name: "Bench Dip", category: "Strength", primaryMuscle: "Triceps", secondaryMuscles: ["Shoulders"], equipment: "Bodyweight", instructions: "Sit on the edge of a bench with hands gripping the edge beside your hips. Slide your body forward off the bench. Lower yourself by bending elbows to 90 degrees, keeping back close to the bench. Press back to full arm extension. Add weight on your lap to progress. Avoid letting shoulders roll forward."),

            // MARK: - Legs (additional)
            Exercise(name: "Hack Squat", category: "Strength", primaryMuscle: "Quadriceps", secondaryMuscles: ["Glutes", "Hamstrings"], equipment: "Machine", instructions: "Load the hack squat machine and position shoulders under pads. Keep feet shoulder-width on the platform. Descend until thighs are parallel or below, then drive through the platform to return. The fixed path allows greater quad focus than a free squat. Adjust foot position for glute emphasis."),
            Exercise(name: "Goblet Squat", category: "Strength", primaryMuscle: "Quadriceps", secondaryMuscles: ["Glutes", "Core"], equipment: "Kettlebell", instructions: "Hold a kettlebell or dumbbell vertically at chest height with both hands cupped under the top. Keep elbows pointing down. Descend into a deep squat while keeping the chest up and knees tracking over toes. The front-loaded weight acts as a counterbalance allowing a very upright torso. Drive through the floor to stand."),
            Exercise(name: "Zercher Squat", category: "Strength", primaryMuscle: "Quadriceps", secondaryMuscles: ["Glutes", "Core", "Back"], equipment: "Barbell", instructions: "Cradle the barbell in the crook of your elbows, forearms parallel to the floor. The unusual loading demands an extremely upright torso and strong core stabilisation. Descend to a full squat, driving knees out over toes. The Zercher forces total body tension throughout. Use a pad around the bar for comfort."),
            Exercise(name: "Box Squat", category: "Strength", primaryMuscle: "Quadriceps", secondaryMuscles: ["Glutes", "Hamstrings"], equipment: "Barbell", instructions: "Set a box or bench behind you at roughly parallel height. Squat down and sit gently on the box, pausing briefly to eliminate momentum. Lean slightly forward and drive through mid-foot to stand. Box squats build strength at the sticking point and reinforce proper bar path. Do not relax or bounce off the box."),
            Exercise(name: "Pause Squat", category: "Strength", primaryMuscle: "Quadriceps", secondaryMuscles: ["Glutes", "Core"], equipment: "Barbell", instructions: "Perform a standard back squat and pause at the bottom for 2-3 full seconds before ascending. The pause eliminates the stretch-shortening reflex, demanding that strength be generated from a dead stop. This builds starting strength and positional awareness at the bottom. Reduce load by 15-20% compared to regular squat."),
            Exercise(name: "Belt Squat", category: "Strength", primaryMuscle: "Quadriceps", secondaryMuscles: ["Glutes", "Hamstrings"], equipment: "Other", instructions: "Attach a loading belt around your hips and stand on two elevated platforms with the weight hanging below you. Squat through a full range of motion with zero spinal loading. The belt squat is ideal when back or shoulder injury prevents barbell squatting. Allows very high volume and frequency without spinal fatigue."),
            Exercise(name: "Wall Sit", category: "Strength", primaryMuscle: "Quadriceps", secondaryMuscles: ["Glutes", "Calves"], equipment: "Bodyweight", instructions: "Stand with your back flat against a wall. Slide down until thighs are parallel to the floor and hold the position. Feet are hip-width, knees directly above ankles. Build time under tension gradually — start with 30 seconds and progress. Add a weight plate on your thighs for loading."),
            Exercise(name: "Sissy Squat", category: "Strength", primaryMuscle: "Quadriceps", secondaryMuscles: [], equipment: "Bodyweight", instructions: "Hold a support with one hand and stand with feet hip-width. Lean back while bending at the knees, letting your heels rise and your torso track backward — like a reverse fold. Lower until your knees nearly touch the floor. Drive back through the knees to stand. This extreme quad stretch and contraction hits the rectus femoris in a way few exercises can."),
            Exercise(name: "Nordic Curl", category: "Strength", primaryMuscle: "Hamstrings", secondaryMuscles: ["Glutes"], equipment: "Bodyweight", instructions: "Kneel on a pad with feet anchored under something solid. Slowly lower your torso toward the floor with control, using your hamstrings to resist. Lower as far as possible under control — most beginners need to catch themselves with their hands before the floor. Pull yourself back with your hamstrings. One of the most potent hamstring eccentric exercises."),
            Exercise(name: "Glute Ham Raise", category: "Strength", primaryMuscle: "Hamstrings", secondaryMuscles: ["Glutes", "Calves"], equipment: "Machine", instructions: "Position yourself on a GHR machine with feet secured and knees on the pad. Lower your torso toward the floor by extending the knee while maintaining a neutral spine. Use your hamstrings to curl back up. This movement combines a leg curl and a back extension simultaneously, making it uniquely demanding for the entire posterior chain."),
            Exercise(name: "Stiff-Leg Deadlift", category: "Strength", primaryMuscle: "Hamstrings", secondaryMuscles: ["Glutes", "Core"], equipment: "Barbell", instructions: "Similar to the Romanian deadlift but with the legs kept straighter throughout. Lower the bar down the front of your legs, hinging at the hip. A slight knee bend is still fine but maintain it consistently. Lower until a significant hamstring stretch is felt. Drive hips forward to return. Greater hamstring lengthening than RDL."),
            Exercise(name: "Single-Leg Deadlift", category: "Strength", primaryMuscle: "Hamstrings", secondaryMuscles: ["Glutes", "Core"], equipment: "Dumbbell", instructions: "Hold a dumbbell in one hand (or two). Stand on the opposite leg. Hinge forward, extending the free leg back as your torso lowers. Lower until a hamstring stretch is felt, then drive the hip of the standing leg forward to return. Demands high single-leg stability and glute control. Move slowly and deliberately."),
            Exercise(name: "Reverse Lunge", category: "Strength", primaryMuscle: "Quadriceps", secondaryMuscles: ["Glutes", "Hamstrings"], equipment: "Dumbbell", instructions: "Stand tall and step backward into a lunge. Lower the back knee toward the floor until the front thigh is parallel. Drive through the front heel to return the rear foot forward. Reverse lunges place less knee shear than forward lunges and are generally better tolerated with knee pain. Great for quad and glute development."),
            Exercise(name: "Step-Up", category: "Strength", primaryMuscle: "Quadriceps", secondaryMuscles: ["Glutes", "Hamstrings"], equipment: "Dumbbell", instructions: "Hold dumbbells at your sides and step one foot onto a box or bench. Drive through the elevated heel to step up and bring the other foot up. Step back down with control. Height of the box determines difficulty — higher means more glute; lower means more quad. Add load progressively."),
            Exercise(name: "Box Jump", category: "Strength", primaryMuscle: "Quadriceps", secondaryMuscles: ["Glutes", "Calves", "Full Body"], equipment: "Bodyweight", instructions: "Stand in front of a plyometric box. Dip into a quarter squat with an arm swing, then jump explosively and land softly on the box in a partial squat. Step down rather than jumping down to protect your joints. Focus on landing mechanics — knees track toes and absorb force quietly. Progress box height gradually."),
            Exercise(name: "Broad Jump", category: "Sports", primaryMuscle: "Full Body", secondaryMuscles: ["Quadriceps", "Glutes", "Calves"], equipment: "Bodyweight", instructions: "Stand with feet hip-width. Swing arms back in a quarter squat, then launch forward as far as possible with an explosive full-body extension. Land with soft knees absorbing the impact through ankles, knees, and hips. Horizontal power output tests and develops athletic explosiveness. Land balanced and stick the landing before resetting."),
            Exercise(name: "Jump Squat", category: "Sports", primaryMuscle: "Quadriceps", secondaryMuscles: ["Glutes", "Calves", "Full Body"], equipment: "Bodyweight", instructions: "Squat to roughly parallel, then explode upward as powerfully as possible. Reach arms overhead and extend fully through ankles, knees, and hips. Land softly, absorbing impact through your joints and immediately descend into the next squat. This develops explosive lower body power and reactive strength. Add a barbell or vest to load."),
            Exercise(name: "Sled Push", category: "Cardio", primaryMuscle: "Full Body", secondaryMuscles: ["Quadriceps", "Glutes", "Core"], equipment: "Other", instructions: "Grip the uprights of a loaded sled at a low or high position. Lean into the sled at a 45-degree angle and drive it forward with aggressive leg drives. Keep a neutral spine and tight core throughout. Drive hard with every step. Work in 20-30 meter efforts with full recovery between sets."),
            Exercise(name: "Sled Pull", category: "Cardio", primaryMuscle: "Full Body", secondaryMuscles: ["Hamstrings", "Glutes", "Back"], equipment: "Other", instructions: "Attach a rope or strap to a loaded sled and hold it facing the sled. Walk backward pulling the sled toward you. Alternatively face away from the sled and drag it by walking forward. The pulling direction changes which muscle groups are dominant. A potent low-impact conditioning tool."),
            Exercise(name: "Leg Press High Foot", category: "Strength", primaryMuscle: "Glutes", secondaryMuscles: ["Hamstrings", "Quadriceps"], equipment: "Machine", instructions: "Place feet high on the leg press platform, shoulder-width or wider. This shifts emphasis from quads (low foot) to glutes and hamstrings. Lower the sled until knees are around 90 degrees. Press through heels to near lockout. Do not lock knees fully. Adjust foot width and angle to target different muscles."),
            Exercise(name: "Sumo Squat", category: "Strength", primaryMuscle: "Glutes", secondaryMuscles: ["Quadriceps", "Hamstrings"], equipment: "Dumbbell", instructions: "Take a very wide stance with toes pointed out 45 degrees. Hold a dumbbell or kettlebell vertically at your centre. Descend keeping knees tracking over toes, torso upright. Drive through heels to stand, squeezing glutes at the top. The wide sumo stance dramatically increases inner thigh and glute recruitment compared to a standard squat."),
            Exercise(name: "Landmine Squat", category: "Strength", primaryMuscle: "Quadriceps", secondaryMuscles: ["Glutes", "Core", "Shoulders"], equipment: "Barbell", instructions: "Grip the free end of a landmine barbell at chest height in a goblet position or with both hands. The arc of the landmine guides the bar path. Squat to full depth maintaining an upright torso. The landmine allows a more vertical torso than a straight barbell and is good for those with mobility limitations."),

            // MARK: - Glutes (additional)
            Exercise(name: "Cable Kickback", category: "Strength", primaryMuscle: "Glutes", secondaryMuscles: [], equipment: "Cable", instructions: "Attach an ankle cuff to a low cable pulley. Face the machine and hold onto the support. Kick the cuffed leg straight back, squeezing the glute at peak extension. Avoid arching the lower back excessively. Lower with control. The cable provides constant tension through the full range of motion."),
            Exercise(name: "Donkey Kick", category: "Strength", primaryMuscle: "Glutes", secondaryMuscles: [], equipment: "Bodyweight", instructions: "Start on hands and knees, wrists under shoulders, knees under hips. Keeping the knee bent at 90 degrees, drive one foot toward the ceiling by squeezing the glute and lifting the thigh to parallel. Pause at the top. Lower with control. Avoid rotating the hips or arching the lower back during the movement."),
            Exercise(name: "Fire Hydrant", category: "Strength", primaryMuscle: "Glutes", secondaryMuscles: [], equipment: "Bodyweight", instructions: "Start on all fours. Keeping the knee bent, lift one leg out to the side as high as possible — mimicking a dog at a fire hydrant. Squeeze the glute at the top and lower with control. Targets the gluteus medius specifically, which is critical for hip stability and knee health during athletic movements."),
            Exercise(name: "Clamshell", category: "Strength", primaryMuscle: "Glutes", secondaryMuscles: [], equipment: "Band", instructions: "Lie on your side with hips stacked, knees bent at about 45 degrees. With a resistance band just above the knees, rotate the top knee upward like a clamshell opening without letting the pelvis rotate. Lower with control. This targets the gluteus medius and external rotators that are essential for knee stability."),
            Exercise(name: "Single-Leg Hip Thrust", category: "Strength", primaryMuscle: "Glutes", secondaryMuscles: ["Hamstrings", "Core"], equipment: "Bodyweight", instructions: "Set up as a regular hip thrust with upper back on a bench. Extend one leg out straight. Drive through the planted heel to thrust the hips upward until the body forms a straight line from knee to shoulder. Squeeze the glute maximally at the top. Single-leg loading significantly increases glute demand and identifies imbalances."),
            Exercise(name: "Frog Pump", category: "Strength", primaryMuscle: "Glutes", secondaryMuscles: [], equipment: "Bodyweight", instructions: "Lie on your back with the soles of your feet pressed together and knees falling out to the sides. Drive your hips toward the ceiling by squeezing your glutes. The hip-externally-rotated position places a unique demand on the posterior glute fibres. Perform 20-30 reps with a strong squeeze at the top."),
            Exercise(name: "Resistance Band Walk", category: "Strength", primaryMuscle: "Glutes", secondaryMuscles: ["Quadriceps"], equipment: "Band", instructions: "Place a resistance band just above the knees or ankles. Assume a slight squat position and step laterally maintaining tension in the band throughout. Keep your hips low and torso upright. Do not let knees cave inward. Walk a set number of steps in each direction. This activates the gluteus medius and minimus for hip stability."),
            Exercise(name: "Cable Pull-Through", category: "Strength", primaryMuscle: "Glutes", secondaryMuscles: ["Hamstrings", "Core"], equipment: "Cable", instructions: "Stand facing away from a low cable pulley and reach between your legs to grip the rope handle. Hinge forward at the hip, letting the rope pull your hands back between your legs. Drive your hips forward explosively to stand tall, squeezing glutes at lockout. This is essentially a cable-assisted kettlebell swing pattern."),
            Exercise(name: "Reverse Hyper", category: "Strength", primaryMuscle: "Glutes", secondaryMuscles: ["Hamstrings", "Back"], equipment: "Machine", instructions: "Lie face-down on a reverse hyper machine with your hips at the edge and legs hanging. Swing the legs upward by extending the hips, loading the glutes and erectors. Lower under control. The reverse hyper also tractions the lumbar spine on the way down, making it valuable for lower back recovery and posterior chain conditioning."),

            // MARK: - Calves (additional)
            Exercise(name: "Seated Calf Raise", category: "Strength", primaryMuscle: "Calves", secondaryMuscles: [], equipment: "Machine", instructions: "Sit on a seated calf raise machine with the pad just above your knees. Place the balls of your feet on the platform. Lower heels to a full stretch, then rise as high as possible on your toes. The seated position bends the knee, which shortens the gastrocnemius and places the load primarily on the soleus — critical for complete calf development."),
            Exercise(name: "Donkey Calf Raise", category: "Strength", primaryMuscle: "Calves", secondaryMuscles: [], equipment: "Machine", instructions: "Bend at the waist with torso parallel to the floor and place balls of feet on a platform. Load weight across the hips via a machine or a training partner sitting on your back. Raise and lower through the full ankle range of motion. The hip-hinged position stretches the calf beyond what a standing raise allows."),
            Exercise(name: "Single-Leg Calf Raise", category: "Strength", primaryMuscle: "Calves", secondaryMuscles: [], equipment: "Bodyweight", instructions: "Stand on one foot with the ball of the foot on a step edge. Hold a support lightly for balance only. Lower the heel below step level for a full stretch, then rise to maximum height. The increased loading over a two-legged raise quickly builds calf strength and corrects side-to-side asymmetries. Use bodyweight first, then hold a dumbbell."),
            Exercise(name: "Tibialis Raise", category: "Strength", primaryMuscle: "Calves", secondaryMuscles: [], equipment: "Bodyweight", instructions: "Stand with heels on a low platform or against a wall. Dorsiflex your feet — pulling toes up as high as possible — then lower slowly. This trains the tibialis anterior, the muscle on the shin, which is critical for knee health, ankle stability, and preventing shin splints. Often neglected in standard calf training."),

            // MARK: - Core (additional)
            Exercise(name: "Dead Bug", category: "Strength", primaryMuscle: "Core", secondaryMuscles: [], equipment: "Bodyweight", instructions: "Lie on your back with arms straight up and knees bent to 90 degrees directly above hips. Press your lower back firmly into the floor. Simultaneously lower one arm overhead and extend the opposite leg out, keeping the lower back pinned. Return and alternate. The challenge is maintaining spinal position while moving limbs."),
            Exercise(name: "Bird Dog", category: "Strength", primaryMuscle: "Core", secondaryMuscles: ["Back", "Glutes"], equipment: "Bodyweight", instructions: "Start on all fours with wrists under shoulders and knees under hips. Brace your core. Simultaneously extend one arm forward and the opposite leg back until both are parallel to the floor. Hold for two counts. Return and alternate. Resist any rotation or hip drop. A foundational movement for spinal stability and anti-rotation strength."),
            Exercise(name: "Pallof Press", category: "Strength", primaryMuscle: "Core", secondaryMuscles: ["Shoulders"], equipment: "Cable", instructions: "Stand sideways to a cable machine at shoulder height with a D-handle. Hold the handle at your chest. Press it straight out in front of you, resisting the rotational pull. Hold for a beat, then return. The core must fight rotation throughout — this is an anti-rotation exercise, not a pressing one. Keep hips square throughout."),
            Exercise(name: "Landmine Rotation", category: "Strength", primaryMuscle: "Core", secondaryMuscles: ["Shoulders", "Back"], equipment: "Barbell", instructions: "Grip the free end of a landmine barbell with both hands extended in front of you. Arc the bar from one hip to the other in a smooth controlled motion, pivoting your feet and rotating through the thoracic spine. The landmine constrains the arc and loads the obliques and rotational core muscles through a full range."),
            Exercise(name: "Dragon Flag", category: "Strength", primaryMuscle: "Core", secondaryMuscles: ["Back", "Shoulders"], equipment: "Bodyweight", instructions: "Lie on a bench and grip the bench behind your head. Raise your legs and hips until your body forms a straight line from shoulders to toes, supported only on your upper back. Lower your entire body as a rigid unit toward horizontal as slowly as possible. This is an advanced movement — build to it progressively through leg raises and L-sits."),
            Exercise(name: "Hollow Body Hold", category: "Strength", primaryMuscle: "Core", secondaryMuscles: [], equipment: "Bodyweight", instructions: "Lie on your back. Press your lower back into the floor and raise both arms overhead and legs slightly off the floor. Your body forms a slight hollow or dish shape. Breathe steadily while maintaining maximum intra-abdominal pressure. This trains the anterior core in a long lever position. Start with knees bent to reduce difficulty."),
            Exercise(name: "L-Sit", category: "Strength", primaryMuscle: "Core", secondaryMuscles: ["Triceps", "Shoulders"], equipment: "Bodyweight", instructions: "Grip parallel bars or push-up handles with arms straight. Press into the bars to depress your scapulae. Raise both legs straight out in front of you parallel to the floor, forming an L shape. Hold the position with active scapular depression. Build toward this from tuck L-sits with bent knees. Requires both core and tricep strength."),
            Exercise(name: "GHD Sit-Up", category: "Strength", primaryMuscle: "Core", secondaryMuscles: ["Quadriceps"], equipment: "Machine", instructions: "Sit on a GHD machine with feet secured under the pads. Lower your torso down below horizontal into a full hip extension with arms overhead. Sit back up by flexing at the hips and pulling with hip flexors and abs. The extended range of motion means the abs and hip flexors work through greater length than any standard sit-up. Use caution: DOMS from GHD sit-ups can be extremely severe."),
            Exercise(name: "Weighted Decline Sit-Up", category: "Strength", primaryMuscle: "Core", secondaryMuscles: [], equipment: "Other", instructions: "Set a decline bench at 30-45 degrees and secure your feet. Hold a weight plate on your chest or behind your head. Curl up through the full range of motion, leading with your chest toward your knees. Lower under control. The decline angle increases the range of motion compared to a flat sit-up, and adding load provides progressive overload."),
            Exercise(name: "Bicycle Crunch", category: "Strength", primaryMuscle: "Core", secondaryMuscles: [], equipment: "Bodyweight", instructions: "Lie on your back with hands lightly behind your head. Simultaneously bring one knee toward your chest while rotating the opposite elbow to meet it. Extend the other leg fully. Alternate in a cycling motion. Slow and deliberate reps with full rotation maximise oblique engagement. Avoid pulling on the neck."),
            Exercise(name: "Windmill", category: "Strength", primaryMuscle: "Core", secondaryMuscles: ["Shoulders", "Glutes"], equipment: "Kettlebell", instructions: "Press a kettlebell overhead in one hand and lock it out. With feet at 45 degrees, push your hip toward the weighted side and lean laterally, lowering the free hand down the opposite leg toward the floor. Keep the overhead arm locked straight and eyes on the kettlebell throughout. The movement challenges lateral core stability and shoulder endurance."),
            Exercise(name: "Suitcase Carry", category: "Strength", primaryMuscle: "Core", secondaryMuscles: ["Forearms", "Back"], equipment: "Dumbbell", instructions: "Hold a heavy dumbbell or kettlebell in one hand at your side. Walk a set distance or time while resisting the tendency to lean toward the weight. The core, particularly the obliques on the opposite side, must work maximally to maintain an upright posture. Asymmetric loading makes this one of the best anti-lateral-flexion exercises."),
            Exercise(name: "Overhead Carry", category: "Strength", primaryMuscle: "Core", secondaryMuscles: ["Shoulders", "Triceps"], equipment: "Dumbbell", instructions: "Press a dumbbell or kettlebell overhead and lock the arm out. Walk forward for distance or time while maintaining the overhead position. The core works to prevent lateral flexion and rotation while the shoulder girdle stabilises the locked-out load. Use unilateral loading for the greatest anti-lateral-flexion demand."),
            Exercise(name: "Copenhagen Plank", category: "Strength", primaryMuscle: "Core", secondaryMuscles: ["Glutes"], equipment: "Bodyweight", instructions: "Lie on your side with your top foot resting on a bench. Your body is supported by the bench and your bottom forearm. Raise your hips off the floor forming a straight line from head to feet. The top inner thigh and the lateral core do the work. Hold the position. More advanced than a standard side plank due to the adductor demand."),

            // MARK: - Forearms (additional)
            Exercise(name: "Wrist Curl", category: "Strength", primaryMuscle: "Forearms", secondaryMuscles: [], equipment: "Barbell", instructions: "Sit on a bench and rest your forearms along your thighs with wrists hanging off the edge. Hold a barbell with an underhand grip. Lower the bar by extending the wrists fully, then curl upward by flexing the wrists. Slow, controlled reps across the full range of motion build the wrist flexors and forearm mass."),
            Exercise(name: "Reverse Wrist Curl", category: "Strength", primaryMuscle: "Forearms", secondaryMuscles: [], equipment: "Barbell", instructions: "As a wrist curl but with an overhand grip, training the wrist extensors. Rest forearms on your thighs with wrists hanging over the edge. Lower the bar by flexing the wrists, then extend upward. The wrist extensors are typically weaker than flexors — balanced training helps prevent tennis elbow and improves grip strength."),
            Exercise(name: "Reverse Curl", category: "Strength", primaryMuscle: "Forearms", secondaryMuscles: ["Biceps"], equipment: "Barbell", instructions: "Perform a standard barbell curl but with a pronated, overhand grip. The palms-down position shifts the primary load to the brachioradialis and wrist extensors, with the biceps as a secondary contributor. Lower fully and control the eccentric. Use approximately 40% less weight than your standard curl."),
            Exercise(name: "Fat Gripz Curl", category: "Strength", primaryMuscle: "Forearms", secondaryMuscles: ["Biceps"], equipment: "Dumbbell", instructions: "Attach Fat Gripz or thick grip implements to dumbbells. Perform regular curls with the substantially thicker grip. The increased diameter recruits far more forearm musculature to maintain the grip and drastically limits the weight you can lift, providing targeted forearm overload with minimal extra work."),
            Exercise(name: "Plate Pinch", category: "Strength", primaryMuscle: "Forearms", secondaryMuscles: [], equipment: "Other", instructions: "Pinch one or two weight plates between your thumb and fingers and hold them at your side for time. Start with a single 10kg or 25lb plate. Progress to heavier plates or holding for longer. This directly trains the thumb and finger strength that transfers to all pulling and gripping movements."),
            Exercise(name: "Towel Pull-Up", category: "Strength", primaryMuscle: "Forearms", secondaryMuscles: ["Back", "Biceps"], equipment: "Bodyweight", instructions: "Drape two gym towels over a pull-up bar and grip one in each hand. Perform pull-ups while holding the towels. The unstable, thick cylindrical grip demands extreme forearm and hand activation to maintain contact. This is advanced — ensure the towels are secure before loading. Build up by using the towel grip on a lat pulldown first."),

            // MARK: - Olympic / Athletic
            Exercise(name: "Hang Clean", category: "Strength", primaryMuscle: "Full Body", secondaryMuscles: ["Quadriceps", "Glutes", "Back", "Shoulders"], equipment: "Barbell", instructions: "Start with the bar at the hang position — at mid-thigh. Hinge slightly and then explosively extend hips, knees, and ankles simultaneously. Shrug hard and pull yourself under the bar into a front rack position with elbows high. Stand to full extension. The hang position removes the first pull complexity, making this a great entry point for the clean."),
            Exercise(name: "Clean and Jerk", category: "Strength", primaryMuscle: "Full Body", secondaryMuscles: ["Quadriceps", "Glutes", "Shoulders", "Triceps"], equipment: "Barbell", instructions: "Clean the bar to the front rack position. From there, dip the hips and knees slightly and drive the bar overhead with an explosive full-body extension. Receive the bar in a split jerk or push jerk position. Recover feet and stand to full lockout. The clean and jerk demands co-ordination of the entire kinetic chain."),
            Exercise(name: "Snatch", category: "Strength", primaryMuscle: "Full Body", secondaryMuscles: ["Quadriceps", "Glutes", "Back", "Shoulders"], equipment: "Barbell", instructions: "Use a wide snatch grip. Pull the bar from the floor keeping it close, then at mid-thigh explosively extend the entire body and pull yourself under the bar into an overhead squat position with arms locked. Stand to complete the lift. The most technical lift in weightlifting — work with a coach and begin with a dowel."),
            Exercise(name: "Hang Snatch", category: "Strength", primaryMuscle: "Full Body", secondaryMuscles: ["Quadriceps", "Glutes", "Shoulders"], equipment: "Barbell", instructions: "Start with a wide snatch grip, bar at mid-thigh hang position. Generate a powerful hip extension to drive the bar upward, then rapidly pull under it into an overhead squat or power position with arms locked. Recover to standing. The hang starting position simplifies the first pull and helps develop explosive power."),
            Exercise(name: "Power Snatch", category: "Strength", primaryMuscle: "Full Body", secondaryMuscles: ["Quadriceps", "Glutes", "Shoulders", "Back"], equipment: "Barbell", instructions: "Perform a snatch but catch the bar in a high power position with hips above parallel rather than a full overhead squat. The power snatch develops explosive hip and pull power without requiring extreme overhead squat mobility. It is also useful for training bar height and developing the pull for those learning the full snatch."),
            Exercise(name: "Push Press", category: "Strength", primaryMuscle: "Shoulders", secondaryMuscles: ["Triceps", "Quadriceps", "Core"], equipment: "Barbell", instructions: "Bar on front deltoids. Dip the hips and knees slightly — a quarter squat — then drive up explosively, using leg power to initiate the bar's momentum. Press overhead finishing with full arm lockout. The leg drive allows you to use 20-30% more weight than a strict overhead press."),
            Exercise(name: "Push Jerk", category: "Strength", primaryMuscle: "Shoulders", secondaryMuscles: ["Triceps", "Quadriceps", "Core"], equipment: "Barbell", instructions: "Start with the bar on front deltoids. Dip and drive as with the push press, but instead of pressing the bar while standing, drop under the bar by re-bending the knees into a partial squat as the arms lock out overhead. Recover by standing to full extension. This allows heavier loads than a push press."),
            Exercise(name: "Split Jerk", category: "Strength", primaryMuscle: "Shoulders", secondaryMuscles: ["Triceps", "Full Body"], equipment: "Barbell", instructions: "Dip and drive from a front rack position. At the moment of maximum upward momentum, split your feet front-to-back — one foot forward, one back — dropping your centre of mass under the bar as arms lock out. Recover by stepping the front foot back first, then the rear foot. The split jerk is the technique of choice for maximal overhead loads."),
            Exercise(name: "Clean Pull", category: "Strength", primaryMuscle: "Full Body", secondaryMuscles: ["Quadriceps", "Glutes", "Back"], equipment: "Barbell", instructions: "Perform the first and second pull of a power clean — from the floor through triple extension and aggressive shrug — but do not pull under the bar or catch it. The bar should rise to at least hip height. This drills the pulling mechanics and overloads the extension and shrug with more weight than a full clean."),
            Exercise(name: "Snatch Pull", category: "Strength", primaryMuscle: "Full Body", secondaryMuscles: ["Back", "Glutes", "Quadriceps"], equipment: "Barbell", instructions: "Using a wide snatch grip, perform the pull from the floor through triple extension and shrug without pulling under the bar. The wide grip trains the snatch-specific bar path and develops the pull mechanics. Load can exceed your full snatch significantly. Finish tall with a powerful shrug and slight elbow bend."),

            // MARK: - Cardio (additional)
            Exercise(name: "Rowing Machine", category: "Cardio", primaryMuscle: "Full Body", secondaryMuscles: ["Back", "Quadriceps", "Core"], equipment: "Machine", instructions: "At the catch, arms are straight, shins vertical, body leaning slightly forward. Drive through the legs first, then swing the body back, then pull the handle to your lower sternum. Return: arms away, body forward, then bend the knees. Maintain a 60% legs, 20% back, 20% arms power split for efficiency."),
            Exercise(name: "Ski Erg", category: "Cardio", primaryMuscle: "Full Body", secondaryMuscles: ["Shoulders", "Core", "Back"], equipment: "Machine", instructions: "Stand facing the Ski Erg. Drive the handles down from overhead by hinging at the hips and engaging the lats and core. Follow through until hands are at hip level. Return handles overhead and immediately begin the next stroke. Excellent for upper-body dominant conditioning. Work in 30-second intervals or fixed calorie pieces."),
            Exercise(name: "Assault Bike", category: "Cardio", primaryMuscle: "Full Body", secondaryMuscles: ["Quadriceps", "Glutes", "Shoulders"], equipment: "Machine", instructions: "Sit on the fan bike with feet on the pedals and hands on the arm levers. Drive through the pedals while simultaneously pushing and pulling the handles. The fan provides air resistance — the harder you work, the more resistance generated. Excellent for maximal effort intervals or aerobic base building."),
            Exercise(name: "Treadmill Intervals", category: "Cardio", primaryMuscle: "Full Body", secondaryMuscles: ["Quadriceps", "Calves", "Glutes"], equipment: "Machine", instructions: "Warm up at a comfortable pace. Sprint at a challenging speed for 20-30 seconds, then recover at a walking pace for 60-90 seconds. Repeat for the prescribed number of intervals. High-intensity treadmill intervals develop VO2max, improve lactate threshold, and burn significantly more calories than steady-state."),
            Exercise(name: "Stairmaster", category: "Cardio", primaryMuscle: "Glutes", secondaryMuscles: ["Quadriceps", "Calves", "Core"], equipment: "Machine", instructions: "Step onto the rotating stair machine and set a steady challenging pace. Drive through the full step without skipping steps or leaning heavily on the rails — the rails are for balance only. The continuous climbing motion provides high caloric burn with low knee impact. Excellent for glute and cardiovascular conditioning."),
            Exercise(name: "Jump Rope", category: "Cardio", primaryMuscle: "Full Body", secondaryMuscles: ["Calves", "Shoulders", "Core"], equipment: "Other", instructions: "Jump with feet together on the balls of your feet, keeping hops small and efficient. Rotate the rope with wrist action, not full arm swings. Build rhythm before adding speed or double-unders. Jump rope is one of the most calorie-efficient cardio tools available and develops coordination, timing, and calf strength."),
            Exercise(name: "Box Step-Up Cardio", category: "Cardio", primaryMuscle: "Glutes", secondaryMuscles: ["Quadriceps", "Calves"], equipment: "Bodyweight", instructions: "Step onto a box or bench and back down in a continuous, rhythmic pattern. Alternate the leading leg. Maintain an upright posture and drive through the heel of the elevated foot. The elevation and pace can be varied to control intensity. Lower impact than running while still providing cardiovascular and glute stimulus."),
            Exercise(name: "Burpee", category: "Cardio", primaryMuscle: "Full Body", secondaryMuscles: ["Chest", "Shoulders", "Core", "Quadriceps"], equipment: "Bodyweight", instructions: "From standing, place hands on the floor and jump feet back to a plank. Perform a push-up. Jump feet back to your hands and explosively jump straight up with arms overhead. The burpee is a total-body conditioning drill that elevates heart rate rapidly. Maintain consistent mechanics even as fatigue builds."),
            Exercise(name: "Mountain Climber", category: "Cardio", primaryMuscle: "Core", secondaryMuscles: ["Shoulders", "Quadriceps", "Full Body"], equipment: "Bodyweight", instructions: "Start in a push-up position. Drive one knee toward your chest and then explosively switch, bringing the other knee in as the first goes back. Alternate rapidly while maintaining a flat back and engaged core. Avoid letting the hips pike or sag. Mountain climbers combine core stability with cardiovascular conditioning."),
            Exercise(name: "Sprint Intervals", category: "Cardio", primaryMuscle: "Full Body", secondaryMuscles: ["Quadriceps", "Glutes", "Calves", "Hamstrings"], equipment: "Bodyweight", instructions: "Accelerate to maximum speed over 20-40 metres, focusing on powerful knee drive and arm swing. Walk or jog back to the start for full recovery. Each sprint should be at maximal effort. Sprint intervals are one of the most effective methods to improve speed, power, and cardiovascular capacity simultaneously."),

            // MARK: - Flexibility / Mobility
            Exercise(name: "Couch Stretch", category: "Flexibility", primaryMuscle: "Quadriceps", secondaryMuscles: ["Core"], equipment: "Bodyweight", instructions: "Kneel near a wall and place one shin up the wall behind you with toes touching the wall. The other foot is flat on the floor in a lunge position. Sit tall and engage your glutes to push the hip toward the floor. Hold 1-2 minutes per side. This is considered one of the most effective hip flexor stretches and is essential for those who sit for long periods."),
            Exercise(name: "Pigeon Pose", category: "Flexibility", primaryMuscle: "Glutes", secondaryMuscles: ["Core"], equipment: "Bodyweight", instructions: "From a push-up position, bring one knee forward and place it behind the same-side wrist, foot pointing toward the opposite wrist. Extend the back leg straight. Lower your hips toward the floor and hold. The target is the piriformis and external hip rotators. Hold for 90-120 seconds per side to allow the nervous system to release."),
            Exercise(name: "World's Greatest Stretch", category: "Flexibility", primaryMuscle: "Full Body", secondaryMuscles: ["Quadriceps", "Hamstrings", "Back", "Shoulders"], equipment: "Bodyweight", instructions: "Step into a deep lunge. Place the same-side hand inside your front foot. Rotate the other arm and trunk upward, reaching the free arm toward the ceiling. Then straighten the front leg for a hamstring stretch. This single movement addresses hip flexors, groin, thoracic rotation, and hamstrings in sequence."),
            Exercise(name: "90/90 Hip Stretch", category: "Flexibility", primaryMuscle: "Glutes", secondaryMuscles: ["Core"], equipment: "Bodyweight", instructions: "Sit on the floor with both hips in a 90-degree position: one leg in front, one to the side. Both knees form 90-degree angles. Sit upright and hold, feeling the stretch in the external rotators of the front hip and the internal rotators of the back hip. Transition between front and back leg slowly to develop dynamic hip mobility."),
            Exercise(name: "Cat-Cow", category: "Flexibility", primaryMuscle: "Back", secondaryMuscles: ["Core"], equipment: "Bodyweight", instructions: "Start on all fours with a neutral spine. Inhale and drop your belly toward the floor while lifting your head and tailbone — cow. Exhale and round your spine toward the ceiling, tucking the head and pelvis — cat. Move through the full range smoothly with each breath. This mobilises every spinal segment and is an excellent warm-up or cool-down."),
            Exercise(name: "Thoracic Extension on Foam Roller", category: "Flexibility", primaryMuscle: "Back", secondaryMuscles: [], equipment: "Other", instructions: "Place a foam roller perpendicular to your spine at upper-back level. Support your head with your hands and gently extend backward over the roller. Move it up or down to target different thoracic segments. Spend 30-60 seconds per level. This counteracts the forward flexion posture of sitting and improves overhead mobility significantly."),
            Exercise(name: "Doorway Chest Stretch", category: "Flexibility", primaryMuscle: "Chest", secondaryMuscles: ["Shoulders"], equipment: "Bodyweight", instructions: "Place forearms vertically on both sides of a doorframe, elbows at shoulder height. Step one foot forward and gently lean your body through the doorway until you feel a stretch across the chest and front of the shoulders. Hold 30-60 seconds. Adjust elbow height to target different fibres: lower elbows for upper pec, higher for lower pec."),
            Exercise(name: "Doorway Shoulder Stretch", category: "Flexibility", primaryMuscle: "Shoulders", secondaryMuscles: ["Chest"], equipment: "Bodyweight", instructions: "Stand in a doorway and place one arm against the frame at shoulder height. Gently rotate your body away from the arm until you feel a stretch through the front deltoid and pec. Hold 30 seconds. Adjust the arm angle — higher for anterior deltoid, at shoulder height for pec, lower for the chest lower fibres."),
            Exercise(name: "Child's Pose", category: "Flexibility", primaryMuscle: "Back", secondaryMuscles: ["Shoulders", "Glutes"], equipment: "Bodyweight", instructions: "Kneel and sit back toward your heels. Extend arms forward on the floor and lower your torso. Breathe deeply, using each exhale to relax further. Walk hands to one side to stretch the lat on the opposite side. An excellent recovery pose that decompresses the lumbar spine and stretches the lats, triceps, and glutes."),
            Exercise(name: "Downward Dog", category: "Flexibility", primaryMuscle: "Hamstrings", secondaryMuscles: ["Calves", "Shoulders", "Back"], equipment: "Bodyweight", instructions: "Start on all fours. Lift hips toward the ceiling, forming an inverted V. Press through the palms and try to straighten the legs, driving heels toward the floor. Pedal one foot at a time to dynamically stretch the calves. The position stretches the entire posterior chain and loads the shoulder girdle. Hold 30-60 seconds."),
            Exercise(name: "Supine Hamstring Stretch", category: "Flexibility", primaryMuscle: "Hamstrings", secondaryMuscles: [], equipment: "Bodyweight", instructions: "Lie on your back and raise one leg. Clasp behind the thigh or use a strap around the foot. Gently straighten the knee as much as flexibility allows and hold. Avoid rounding the lower back. Hold 30-60 seconds per side. This isolated supine position allows the most controlled and comfortable hamstring stretching."),
            Exercise(name: "Standing Quad Stretch", category: "Flexibility", primaryMuscle: "Quadriceps", secondaryMuscles: [], equipment: "Bodyweight", instructions: "Stand on one leg and pull the opposite foot toward your glutes, holding the ankle. Keep knees together and stand tall — do not lean forward. Squeeze the glute of the stretching leg to increase the hip flexor component. Hold 30 seconds per side. Use a wall for balance if needed."),
            Exercise(name: "Figure-4 Stretch", category: "Flexibility", primaryMuscle: "Glutes", secondaryMuscles: [], equipment: "Bodyweight", instructions: "Lie on your back with knees bent. Cross one ankle over the opposite knee, forming a figure-4. Either hold this position or pull the bottom leg toward your chest to intensify the stretch. This targets the piriformis and external hip rotators. Hold 60-90 seconds per side for maximum benefit."),
            Exercise(name: "Sleeper Stretch", category: "Flexibility", primaryMuscle: "Shoulders", secondaryMuscles: [], equipment: "Bodyweight", instructions: "Lie on your side on the stretching shoulder with elbow bent to 90 degrees, palm facing up. Use the other hand to gently press the top hand toward the floor, internally rotating the shoulder. Hold 30-45 seconds. This stretches the posterior shoulder capsule and improves internal rotation — essential for athletes with shoulder impingement or tight throwing shoulders."),

            // MARK: - Sports-Specific
            Exercise(name: "Plyometric Push-Up", category: "Sports", primaryMuscle: "Chest", secondaryMuscles: ["Triceps", "Shoulders", "Core"], equipment: "Bodyweight", instructions: "Perform a push-up but explode upward with enough power that your hands leave the floor. Land with soft elbows and immediately descend into the next rep. The brief airborne phase demands maximal rate of force development. Start on an elevated surface to reduce difficulty. Focus on quality explosive reps rather than volume."),
            Exercise(name: "Clap Push-Up", category: "Sports", primaryMuscle: "Chest", secondaryMuscles: ["Triceps", "Shoulders"], equipment: "Bodyweight", instructions: "Perform an explosive push-up. As your hands leave the floor clap them together, then separate and land with soft elbows. The clap adds a co-ordination challenge to the plyometric push-up. This trains upper-body explosive power and reactive strength. Ensure surfaces are non-slip."),
            Exercise(name: "Depth Jump", category: "Sports", primaryMuscle: "Full Body", secondaryMuscles: ["Quadriceps", "Glutes", "Calves"], equipment: "Bodyweight", instructions: "Step off a box and immediately upon landing — not after — jump as high as possible. The goal is to minimise ground contact time. Landing initiates the reactive jump. This is the most potent plyometric exercise for developing reactive strength. Start with a low box height of 20-30 cm and progress conservatively."),
            Exercise(name: "Reactive Box Jump", category: "Sports", primaryMuscle: "Full Body", secondaryMuscles: ["Quadriceps", "Glutes"], equipment: "Bodyweight", instructions: "Jump onto a box, step down quickly, then immediately rebound into the next jump onto the box. The focus is on minimising time between jumps and training the stretch-shortening cycle at high velocity. Maintain an athletic landing position and aggressive arm drive. Used in advanced plyometric training."),
            Exercise(name: "Med Ball Slam", category: "Sports", primaryMuscle: "Core", secondaryMuscles: ["Shoulders", "Back", "Full Body"], equipment: "Other", instructions: "Raise a medicine ball overhead with both hands, extending your entire body. Slam it into the floor as hard as possible by contracting your entire anterior chain. Catch or retrieve the ball and immediately repeat. The slam trains rotational and anti-extension power simultaneously. Use a non-bounce slam ball to avoid rebound injuries."),
            Exercise(name: "Med Ball Chest Pass", category: "Sports", primaryMuscle: "Chest", secondaryMuscles: ["Shoulders", "Triceps", "Core"], equipment: "Other", instructions: "Stand facing a wall or partner holding a medicine ball at your chest. Explosively push the ball away from your chest in a throwing motion, extending the arms fully. Catch the rebound and immediately reload into the next throw. Trains horizontal pushing power and reactive upper-body strength. Use a wall-ball weight appropriate for your level."),
            Exercise(name: "Med Ball Rotational Throw", category: "Sports", primaryMuscle: "Core", secondaryMuscles: ["Shoulders", "Back", "Full Body"], equipment: "Other", instructions: "Stand sideways to a solid wall. Hold a medicine ball at hip level on the far side. Rotate your hips explosively and throw the ball into the wall, catching the rebound. The power comes from rotating the hips before the trunk before the arms. Train both sides equally. Excellent for sport-specific rotational power."),
            Exercise(name: "Sandbag Carry", category: "Sports", primaryMuscle: "Full Body", secondaryMuscles: ["Core", "Back", "Forearms"], equipment: "Other", instructions: "Bear hug or shoulder a heavy sandbag and walk for distance or time. The shifting, unstable load of a sandbag demands constant core stabilisation and whole-body tension. Different carrying positions — bear hug, shoulder, zercher — challenge the body differently. One of the best general strength and conditioning implements for real-world performance."),
            Exercise(name: "Tire Flip", category: "Sports", primaryMuscle: "Full Body", secondaryMuscles: ["Back", "Quadriceps", "Glutes", "Shoulders"], equipment: "Other", instructions: "Stand facing a large tire. Squat down and grip underneath the tire with palms facing up. Drive the tire upward with your legs, transitioning to pushing it forward as it rises. When high enough, push it over with both hands. The tire flip is a total-body loaded movement that develops explosive hip and pushing power."),
            Exercise(name: "Atlas Stone", category: "Sports", primaryMuscle: "Full Body", secondaryMuscles: ["Back", "Glutes", "Core"], equipment: "Other", instructions: "Straddle the stone and squat down, wrapping your arms around it. Deadlift the stone to your lap, then create a shelf with your forearms. Continue to drive hips forward while using your body as a ramp to load the stone onto a platform or over a bar. A strongman staple that requires full body co-ordination and brute strength."),
        ]

        for exercise in seeds {
            ctx.insert(exercise)
        }
        try saveContext(ctx)
    }
    // swiftlint:enable function_body_length
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

    /// Creates a new `WorkoutSession` pre-populated with the same exercises
    /// (and their last-used weights as targets) from a previous session.
    /// This is the "Repeat Workout" action.
    func repeatSession(_ previous: WorkoutSession, userId: String) throws -> WorkoutSession {
        let ctx = try context
        let session = WorkoutSession(userId: userId)
        ctx.insert(session)

        let sortedEntries = previous.entries.sorted { $0.orderIndex < $1.orderIndex }
        for (index, entry) in sortedEntries.enumerated() {
            let newEntry = WorkoutExerciseEntry(
                exerciseId: entry.exerciseId,
                exerciseName: entry.exerciseName,
                orderIndex: index
            )
            ctx.insert(newEntry)

            // Seed the same number of sets as last time, using last session's weights/reps as targets.
            let sortedSets = entry.sets.sorted { $0.setNumber < $1.setNumber }
            for (setIndex, previousSet) in sortedSets.enumerated() {
                let newSet = WorkoutSet(
                    setNumber: setIndex + 1,
                    weight: previousSet.weight,
                    reps: previousSet.reps > 0 ? previousSet.reps : 10
                )
                ctx.insert(newSet)
                newEntry.sets.append(newSet)
            }
            // If original had no sets, seed one blank set.
            if sortedSets.isEmpty {
                let blankSet = WorkoutSet(setNumber: 1)
                ctx.insert(blankSet)
                newEntry.sets.append(blankSet)
            }
            session.entries.append(newEntry)
        }

        try saveContext(ctx)
        return session
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

// MARK: - Routine Seeding

extension GymRepository {

    /// Seeds 5 test routines for `userId` on first run.
    /// Idempotent — returns immediately if any routine already exists for this user.
    func seedTestRoutinesIfNeeded(userId: String) throws {
        let ctx = try context
        var checkDescriptor = FetchDescriptor<Routine>(
            predicate: #Predicate { $0.userId == userId }
        )
        checkDescriptor.fetchLimit = 1
        let existing = try ctx.fetch(checkDescriptor)
        guard existing.isEmpty else { return }

        // Convenience slot builder
        func slot(
            name: String,
            muscle: String,
            order: Int,
            sets: Int,
            reps: Int,
            compound: Bool
        ) -> RoutineExerciseSlot {
            RoutineExerciseSlot(
                exerciseId: name.lowercased().replacingOccurrences(of: " ", with: "_"),
                exerciseName: name,
                primaryMuscle: muscle,
                orderIndex: order,
                targetSets: sets,
                targetReps: reps,
                restSeconds: compound ? 120 : 60
            )
        }

        let desc = "Test routine — editable"

        // Routine 1: Push Day A
        let pushDayASlots: [RoutineExerciseSlot] = [
            slot(name: "Bench Press",            muscle: "Chest",     order: 0, sets: 4, reps: 8,  compound: true),
            slot(name: "Incline Dumbbell Press", muscle: "Chest",     order: 1, sets: 3, reps: 10, compound: true),
            slot(name: "Overhead Press",         muscle: "Shoulders", order: 2, sets: 3, reps: 8,  compound: true),
            slot(name: "Lateral Raises",         muscle: "Shoulders", order: 3, sets: 4, reps: 15, compound: false),
            slot(name: "Tricep Pushdown",        muscle: "Triceps",   order: 4, sets: 3, reps: 12, compound: false),
        ]
        let pushDayA = Routine(
            userId: userId,
            name: "Push Day A",
            routineDescription: desc,
            exerciseIds: pushDayASlots.map(\.exerciseId),
            exerciseNames: pushDayASlots.map(\.exerciseName),
            slots: pushDayASlots,
            scheduledDays: [],
            notes: nil
        )
        ctx.insert(pushDayA)

        // Routine 2: Pull Day B
        let pullDayBSlots: [RoutineExerciseSlot] = [
            slot(name: "Deadlift",       muscle: "Back",      order: 0, sets: 4, reps: 5,  compound: true),
            slot(name: "Pull-Ups",       muscle: "Back",      order: 1, sets: 3, reps: 8,  compound: true),
            slot(name: "Barbell Row",    muscle: "Back",      order: 2, sets: 3, reps: 10, compound: true),
            slot(name: "Face Pulls",     muscle: "Shoulders", order: 3, sets: 3, reps: 15, compound: false),
            slot(name: "Barbell Curl",   muscle: "Biceps",    order: 4, sets: 3, reps: 10, compound: false),
        ]
        let pullDayB = Routine(
            userId: userId,
            name: "Pull Day B",
            routineDescription: desc,
            exerciseIds: pullDayBSlots.map(\.exerciseId),
            exerciseNames: pullDayBSlots.map(\.exerciseName),
            slots: pullDayBSlots,
            scheduledDays: [],
            notes: nil
        )
        ctx.insert(pullDayB)

        // Routine 3: Leg Day C
        let legDayCSlots: [RoutineExerciseSlot] = [
            slot(name: "Squat",              muscle: "Quadriceps", order: 0, sets: 4, reps: 6,  compound: true),
            slot(name: "Romanian Deadlift",  muscle: "Hamstrings", order: 1, sets: 3, reps: 10, compound: true),
            slot(name: "Leg Press",          muscle: "Quadriceps", order: 2, sets: 3, reps: 12, compound: true),
            slot(name: "Leg Curl",           muscle: "Hamstrings", order: 3, sets: 4, reps: 12, compound: false),
            slot(name: "Calf Raises",        muscle: "Calves",     order: 4, sets: 4, reps: 20, compound: false),
        ]
        let legDayC = Routine(
            userId: userId,
            name: "Leg Day C",
            routineDescription: desc,
            exerciseIds: legDayCSlots.map(\.exerciseId),
            exerciseNames: legDayCSlots.map(\.exerciseName),
            slots: legDayCSlots,
            scheduledDays: [],
            notes: nil
        )
        ctx.insert(legDayC)

        // Routine 4: Upper Power
        let upperPowerSlots: [RoutineExerciseSlot] = [
            slot(name: "Bench Press",    muscle: "Chest",     order: 0, sets: 5, reps: 5, compound: true),
            slot(name: "Pull-Ups",       muscle: "Back",      order: 1, sets: 5, reps: 5, compound: true),
            slot(name: "Overhead Press", muscle: "Shoulders", order: 2, sets: 5, reps: 5, compound: true),
            slot(name: "Barbell Row",    muscle: "Back",      order: 3, sets: 4, reps: 6, compound: true),
        ]
        let upperPower = Routine(
            userId: userId,
            name: "Upper Power",
            routineDescription: desc,
            exerciseIds: upperPowerSlots.map(\.exerciseId),
            exerciseNames: upperPowerSlots.map(\.exerciseName),
            slots: upperPowerSlots,
            scheduledDays: [],
            notes: nil
        )
        ctx.insert(upperPower)

        // Routine 5: Full Body
        let fullBodySlots: [RoutineExerciseSlot] = [
            slot(name: "Squat",          muscle: "Quadriceps", order: 0, sets: 3, reps: 8, compound: true),
            slot(name: "Bench Press",    muscle: "Chest",      order: 1, sets: 3, reps: 8, compound: true),
            slot(name: "Deadlift",       muscle: "Back",       order: 2, sets: 3, reps: 5, compound: true),
            slot(name: "Pull-Ups",       muscle: "Back",       order: 3, sets: 3, reps: 8, compound: true),
            slot(name: "Overhead Press", muscle: "Shoulders",  order: 4, sets: 3, reps: 8, compound: true),
        ]
        let fullBody = Routine(
            userId: userId,
            name: "Full Body",
            routineDescription: desc,
            exerciseIds: fullBodySlots.map(\.exerciseId),
            exerciseNames: fullBodySlots.map(\.exerciseName),
            slots: fullBodySlots,
            scheduledDays: [],
            notes: nil
        )
        ctx.insert(fullBody)

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
