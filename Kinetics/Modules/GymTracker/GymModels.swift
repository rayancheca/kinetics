import Foundation
import SwiftData
import SwiftUI

// MARK: - GymCategory

/// High-level workout category used for filtering the exercise library.
enum GymCategory: String, CaseIterable, Codable, Sendable {
    case strength    = "Strength"
    case cardio      = "Cardio"
    case flexibility = "Flexibility"
    case sports      = "Sports"
    case other       = "Other"
}

// MARK: - GymMuscleGroup (display helper, not a SwiftData model)

enum GymMuscleGroup: String, CaseIterable, Sendable {
    case chest       = "Chest"
    case back        = "Back"
    case shoulders   = "Shoulders"
    case biceps      = "Biceps"
    case triceps     = "Triceps"
    case forearms    = "Forearms"
    case core        = "Core"
    case quadriceps  = "Quadriceps"
    case hamstrings  = "Hamstrings"
    case glutes      = "Glutes"
    case calves      = "Calves"
    case fullBody    = "Full Body"
    case other       = "Other"

    /// Representative accent colour for each muscle group.
    var color: Color {
        switch self {
        case .chest:      return Color(red: 0.25, green: 0.72, blue: 1.00)
        case .back:       return Color(red: 0.22, green: 1.00, blue: 0.69)
        case .shoulders:  return Color(red: 1.00, green: 0.80, blue: 0.20)
        case .biceps:     return Color(red: 0.55, green: 0.35, blue: 1.00)
        case .triceps:    return Color(red: 0.90, green: 0.35, blue: 0.90)
        case .forearms:   return Color(red: 0.60, green: 0.80, blue: 0.40)
        case .core:       return Color(red: 1.00, green: 0.45, blue: 0.20)
        case .quadriceps: return Color(red: 0.20, green: 0.85, blue: 1.00)
        case .hamstrings: return Color(red: 0.95, green: 0.35, blue: 0.45)
        case .glutes:     return Color(red: 1.00, green: 0.55, blue: 0.70)
        case .calves:     return Color(red: 0.40, green: 0.90, blue: 0.70)
        case .fullBody:   return Color.white.opacity(0.7)
        case .other:      return Color(red: 0.55, green: 0.55, blue: 0.60)
        }
    }
}

// MARK: - GymEquipment (display helper, not a SwiftData model)

enum GymEquipment: String, CaseIterable, Sendable {
    case barbell    = "Barbell"
    case dumbbell   = "Dumbbell"
    case cable      = "Cable"
    case machine    = "Machine"
    case bodyweight = "Bodyweight"
    case kettlebell = "Kettlebell"
    case band       = "Band"
    case other      = "Other"

    /// SF Symbol name that best represents each equipment type.
    var systemImage: String {
        switch self {
        case .barbell:    return "dumbbell.fill"
        case .dumbbell:   return "dumbbell"
        case .cable:      return "cable.connector"
        case .machine:    return "gear"
        case .bodyweight: return "figure.strengthtraining.traditional"
        case .kettlebell: return "circle.fill"
        case .band:       return "oval"
        case .other:      return "questionmark.circle"
        }
    }
}

// MARK: - Exercise

/// Represents a single exercise in the library.
/// `isCustom == false` entries are seeded from the built-in library;
/// `isCustom == true` entries are created by the user.
@Model
final class Exercise {
    var id: String
    var name: String
    /// Raw string category — kept for backwards compatibility and Firestore encoding.
    var category: String
    var primaryMuscle: String
    var secondaryMuscles: [String]
    var equipment: String
    var instructions: String
    var isCustom: Bool
    var isFavorite: Bool
    var createdAt: Date
    /// Optional owner — nil means the exercise belongs to the shared library.
    var userId: String?

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
        createdAt: Date = Date(),
        userId: String? = nil
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
        self.userId = userId
    }

    // MARK: - Typed accessors

    /// Typed category derived from the raw `category` string.
    var gymCategory: GymCategory { GymCategory(rawValue: category) ?? .other }

    /// Typed primary muscle group derived from `primaryMuscle`.
    var muscleGroup: GymMuscleGroup { GymMuscleGroup(rawValue: primaryMuscle) ?? .other }

    /// Typed equipment derived from the raw `equipment` string.
    var gymEquipment: GymEquipment { GymEquipment(rawValue: equipment) ?? .other }
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

    // MARK: - Computed helpers

    /// Alias for `endedAt`.
    var completedAt: Date? { endedAt }

    /// Elapsed duration between `startedAt` and `endedAt` (or now if still active).
    var duration: TimeInterval { (endedAt ?? Date()).timeIntervalSince(startedAt) }

    /// Total number of sets across all entries.
    var totalSets: Int { entries.reduce(0) { $0 + $1.sets.count } }

    /// Total training volume in kilograms: sum of (weight x reps) for every completed set.
    var totalVolumeKg: Double {
        entries.reduce(0.0) { entryTotal, entry in
            entryTotal + entry.sets.filter { $0.isCompleted }.reduce(0.0) { setTotal, set in
                setTotal + (set.weight * Double(set.reps))
            }
        }
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

    /// Convenience alias for `orderIndex`.
    var order: Int { orderIndex }
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
    /// Optional per-set note (e.g. "felt easy", "used straps").
    var notes: String

    init(
        id: String = UUID().uuidString,
        setNumber: Int,
        weight: Double = 0,
        reps: Int = 0,
        rpe: Double = 0,
        isCompleted: Bool = false,
        completedAt: Date? = nil,
        notes: String = ""
    ) {
        self.id = id
        self.setNumber = setNumber
        self.weight = weight
        self.reps = reps
        self.rpe = rpe
        self.isCompleted = isCompleted
        self.completedAt = completedAt
        self.notes = notes
    }

    /// Convenience alias -- same as `isCompleted`.
    var completed: Bool { isCompleted }
}

// MARK: - RoutineExercise (typealias for RoutineExerciseSlot)

/// Convenience alias -- `RoutineExercise` is the public-facing name.
typealias RoutineExercise = RoutineExerciseSlot

// MARK: - RoutineExerciseSlot

/// A single exercise slot inside a saved Routine.
/// Stores the target volume the athlete wants to hit: sets, reps, and rest duration.
/// This is a plain Codable struct (not a SwiftData model) and is stored as a
/// JSON-encoded [RoutineExerciseSlot] array on the parent `Routine` object.
struct RoutineExerciseSlot: Codable, Identifiable, Equatable, Sendable {
    var id: String
    var exerciseId: String
    var exerciseName: String
    var primaryMuscle: String
    var orderIndex: Int
    var targetSets: Int
    var targetReps: Int
    /// Rest duration in seconds between sets.
    var restSeconds: Int

    init(
        id: String = UUID().uuidString,
        exerciseId: String,
        exerciseName: String,
        primaryMuscle: String = "",
        orderIndex: Int,
        targetSets: Int = 3,
        targetReps: Int = 10,
        restSeconds: Int = 90
    ) {
        self.id = id
        self.exerciseId = exerciseId
        self.exerciseName = exerciseName
        self.primaryMuscle = primaryMuscle
        self.orderIndex = orderIndex
        self.targetSets = targetSets
        self.targetReps = targetReps
        self.restSeconds = restSeconds
    }
}

// MARK: - Routine

/// A saved workout template the athlete can launch at any time.
/// `exerciseIds` and `exerciseNames` are kept for backwards compatibility.
/// New code should use `slotsData` (JSON-encoded `[RoutineExerciseSlot]`).
@Model
final class Routine {
    var id: String
    var userId: String
    var name: String
    var routineDescription: String
    // Legacy parallel arrays -- still populated so older code does not break.
    var exerciseIds: [String]
    var exerciseNames: [String]
    /// JSON-encoded [RoutineExerciseSlot] -- the authoritative ordered list with targets.
    var slotsData: Data
    /// Days of the week this routine is scheduled (0 = Sunday ... 6 = Saturday).
    var scheduledDays: [Int]
    /// Optional free-text notes visible in the detail view.
    var notes: String
    var createdAt: Date
    var lastUsedAt: Date?

    init(
        id: String = UUID().uuidString,
        userId: String,
        name: String,
        routineDescription: String = "",
        exerciseIds: [String] = [],
        exerciseNames: [String] = [],
        slots: [RoutineExerciseSlot] = [],
        scheduledDays: [Int] = [],
        notes: String = "",
        createdAt: Date = Date(),
        lastUsedAt: Date? = nil
    ) {
        self.id = id
        self.userId = userId
        self.name = name
        self.routineDescription = routineDescription
        self.exerciseIds = exerciseIds
        self.exerciseNames = exerciseNames
        slotsData = (try? JSONEncoder().encode(slots)) ?? Data()
        self.scheduledDays = scheduledDays
        self.notes = notes
        self.createdAt = createdAt
        self.lastUsedAt = lastUsedAt
    }

    // MARK: - Computed helpers

    /// Decoded exercise slots, sorted by `orderIndex`.
    var slots: [RoutineExerciseSlot] {
        get {
            let decoded = (try? JSONDecoder().decode([RoutineExerciseSlot].self, from: slotsData)) ?? []
            return decoded.sorted { $0.orderIndex < $1.orderIndex }
        }
        set {
            slotsData = (try? JSONEncoder().encode(newValue)) ?? Data()
            // Keep legacy parallel arrays in sync.
            let sorted = newValue.sorted { $0.orderIndex < $1.orderIndex }
            exerciseIds = sorted.map(\.exerciseId)
            exerciseNames = sorted.map(\.exerciseName)
        }
    }

    /// Alias for `lastUsedAt`.
    var lastPerformedAt: Date? { lastUsedAt }

    /// Unique primary-muscle groups as raw strings across all exercise slots.
    var muscleGroupStrings: [String] {
        var seen = Set<String>()
        return slots.compactMap { slot -> String? in
            let muscle = slot.primaryMuscle
            guard !muscle.isEmpty, !seen.contains(muscle) else { return nil }
            seen.insert(muscle)
            return muscle
        }
    }

    /// Unique primary-muscle groups as typed `GymMuscleGroup` values across all slots.
    var muscleGroups: [GymMuscleGroup] {
        var seen = Set<GymMuscleGroup>()
        return slots.compactMap { slot -> GymMuscleGroup? in
            let group = GymMuscleGroup(rawValue: slot.primaryMuscle) ?? .other
            guard seen.insert(group).inserted else { return nil }
            return group
        }
    }

    /// Estimated total workout duration in minutes.
    /// Formula: sum over each slot of (targetSets x restSeconds) + (targetSets x 45s avg set time).
    var estimatedMinutes: Int {
        let totalSeconds = slots.reduce(0) { acc, slot in
            let setTime = slot.targetSets * 45
            let restTime = max(0, slot.targetSets - 1) * slot.restSeconds
            return acc + setTime + restTime
        }
        return max(1, Int(ceil(Double(totalSeconds) / 60.0)))
    }
}

// MARK: - PersonalRecord

/// Stores the all-time best weight x reps pair for a given exercise.
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
    /// The previous personal-record weight before this one was set.
    /// Zero means this was the first-ever PR for this exercise.
    var previousWeight: Double

    init(
        id: String = UUID().uuidString,
        userId: String,
        exerciseId: String,
        exerciseName: String,
        weight: Double,
        reps: Int,
        achievedAt: Date = Date(),
        previousWeight: Double = 0
    ) {
        self.id = id
        self.userId = userId
        self.exerciseId = exerciseId
        self.exerciseName = exerciseName
        self.weight = weight
        self.reps = reps
        self.achievedAt = achievedAt
        self.previousWeight = previousWeight
    }
}

// MARK: - BodyMeasurement

/// A point-in-time body composition snapshot.
/// Both `weightKg` and `bodyFatPercent` default to 0 -- 0 means "not recorded
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

    /// Convenience alias for `recordedAt`.
    var date: Date { recordedAt }
}
