import Foundation
import SwiftData

// MARK: - Exercise

/// Represents a single exercise in the library.
/// `isCustom == false` entries are seeded from the built-in library;
/// `isCustom == true` entries are created by the user.
@Model
final class Exercise {
    var id: String
    var name: String
    var category: String
    var primaryMuscle: String
    var secondaryMuscles: [String]
    var equipment: String
    var instructions: String
    var isCustom: Bool
    var isFavorite: Bool
    var createdAt: Date

    init(
        id: String = UUID().uuidString,
        name: String,
        category: String,
        primaryMuscle: String,
        secondaryMuscles: [String] = [],
        equipment: String,
        instructions: String = "",
        isCustom: Bool = false,
        isFavorite: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.primaryMuscle = primaryMuscle
        self.secondaryMuscles = secondaryMuscles
        self.equipment = equipment
        self.instructions = instructions
        self.isCustom = isCustom
        self.isFavorite = isFavorite
        self.createdAt = createdAt
    }
}

// MARK: - WorkoutSession

/// Top-level container for a single training session.
/// Owns all `WorkoutExerciseEntry` records via a cascade-delete relationship.
@Model
final class WorkoutSession {
    var id: String
    var userId: String
    var startedAt: Date
    var endedAt: Date?
    var notes: String
    var isCompleted: Bool
    @Relationship(deleteRule: .cascade) var entries: [WorkoutExerciseEntry]

    init(
        id: String = UUID().uuidString,
        userId: String,
        startedAt: Date = Date(),
        endedAt: Date? = nil,
        notes: String = "",
        isCompleted: Bool = false,
        entries: [WorkoutExerciseEntry] = []
    ) {
        self.id = id
        self.userId = userId
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.notes = notes
        self.isCompleted = isCompleted
        self.entries = entries
    }
}

// MARK: - WorkoutExerciseEntry

/// A single exercise slot within a `WorkoutSession`.
/// `exerciseName` is denormalised so it can be displayed without a join.
@Model
final class WorkoutExerciseEntry {
    var id: String
    var exerciseId: String
    var exerciseName: String
    var orderIndex: Int
    @Relationship(deleteRule: .cascade) var sets: [WorkoutSet]

    init(
        id: String = UUID().uuidString,
        exerciseId: String,
        exerciseName: String,
        orderIndex: Int,
        sets: [WorkoutSet] = []
    ) {
        self.id = id
        self.exerciseId = exerciseId
        self.exerciseName = exerciseName
        self.orderIndex = orderIndex
        self.sets = sets
    }
}

// MARK: - WorkoutSet

/// An individual set within a `WorkoutExerciseEntry`.
/// `weight` is stored in kilograms; use 0 for bodyweight movements.
/// `rpe` uses the 1-10 Borg scale; 0 means the athlete did not track RPE.
@Model
final class WorkoutSet {
    var id: String
    var setNumber: Int
    var weight: Double
    var reps: Int
    var rpe: Double
    var isCompleted: Bool
    var completedAt: Date?

    init(
        id: String = UUID().uuidString,
        setNumber: Int,
        weight: Double = 0,
        reps: Int = 0,
        rpe: Double = 0,
        isCompleted: Bool = false,
        completedAt: Date? = nil
    ) {
        self.id = id
        self.setNumber = setNumber
        self.weight = weight
        self.reps = reps
        self.rpe = rpe
        self.isCompleted = isCompleted
        self.completedAt = completedAt
    }
}

// MARK: - Routine

/// A saved workout template the athlete can launch at any time.
/// `exerciseIds` and `exerciseNames` are parallel arrays — index N in each
/// array refers to the same exercise slot.
@Model
final class Routine {
    var id: String
    var userId: String
    var name: String
    var routineDescription: String
    var exerciseIds: [String]
    var exerciseNames: [String]
    var createdAt: Date
    var lastUsedAt: Date?

    init(
        id: String = UUID().uuidString,
        userId: String,
        name: String,
        routineDescription: String = "",
        exerciseIds: [String] = [],
        exerciseNames: [String] = [],
        createdAt: Date = Date(),
        lastUsedAt: Date? = nil
    ) {
        self.id = id
        self.userId = userId
        self.name = name
        self.routineDescription = routineDescription
        self.exerciseIds = exerciseIds
        self.exerciseNames = exerciseNames
        self.createdAt = createdAt
        self.lastUsedAt = lastUsedAt
    }
}

// MARK: - PersonalRecord

/// Stores the all-time best weight × reps pair for a given exercise.
/// `exerciseName` is denormalised for fast display without a join.
@Model
final class PersonalRecord {
    var id: String
    var userId: String
    var exerciseId: String
    var exerciseName: String
    var weight: Double
    var reps: Int
    var achievedAt: Date

    init(
        id: String = UUID().uuidString,
        userId: String,
        exerciseId: String,
        exerciseName: String,
        weight: Double,
        reps: Int,
        achievedAt: Date = Date()
    ) {
        self.id = id
        self.userId = userId
        self.exerciseId = exerciseId
        self.exerciseName = exerciseName
        self.weight = weight
        self.reps = reps
        self.achievedAt = achievedAt
    }
}

// MARK: - BodyMeasurement

/// A point-in-time body composition snapshot.
/// Both `weightKg` and `bodyFatPercent` default to 0 — 0 means "not recorded
/// in this entry", not a literal measurement of zero.
@Model
final class BodyMeasurement {
    var id: String
    var userId: String
    var recordedAt: Date
    var weightKg: Double
    var bodyFatPercent: Double
    var notes: String

    init(
        id: String = UUID().uuidString,
        userId: String,
        recordedAt: Date = Date(),
        weightKg: Double = 0,
        bodyFatPercent: Double = 0,
        notes: String = ""
    ) {
        self.id = id
        self.userId = userId
        self.recordedAt = recordedAt
        self.weightKg = weightKg
        self.bodyFatPercent = bodyFatPercent
        self.notes = notes
    }
}

// MARK: - GymMuscleGroup (display helper, not a SwiftData model)

enum GymMuscleGroup: String, CaseIterable, Sendable {
    case chest = "Chest"
    case back = "Back"
    case shoulders = "Shoulders"
    case biceps = "Biceps"
    case triceps = "Triceps"
    case forearms = "Forearms"
    case core = "Core"
    case quadriceps = "Quadriceps"
    case hamstrings = "Hamstrings"
    case glutes = "Glutes"
    case calves = "Calves"
    case fullBody = "Full Body"
}

enum GymEquipment: String, CaseIterable, Sendable {
    case barbell = "Barbell"
    case dumbbell = "Dumbbell"
    case cable = "Cable"
    case machine = "Machine"
    case bodyweight = "Bodyweight"
    case kettlebell = "Kettlebell"
    case other = "Other"
}
