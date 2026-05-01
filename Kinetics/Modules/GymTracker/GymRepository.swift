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
    /// Populates the library with 60+ canonical exercises on first launch.
    /// Idempotent — returns immediately if 50+ non-custom exercises already exist.
    func seedExerciseLibraryIfNeeded() throws {
        let ctx = try context
        var checkDescriptor = FetchDescriptor<Exercise>(
            predicate: #Predicate { !$0.isCustom }
        )
        checkDescriptor.fetchLimit = 50
        let existing = try ctx.fetch(checkDescriptor)
        guard existing.count < 50 else { return }

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
