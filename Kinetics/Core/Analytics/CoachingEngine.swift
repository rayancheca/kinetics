import Foundation

// MARK: - CoachCue

/// A single real-time coaching cue produced by `CoachingEngine.evaluate(metrics:sport:)`.
///
/// Cues are generated from live per-frame metrics, distinct from the post-session
/// `CoachingNote` values which summarise a completed session.
struct CoachCue: Equatable, Sendable {

    // MARK: Priority

    enum Priority: Sendable {
        case info
        case warning
        case critical
    }

    /// The coaching message to display and optionally speak aloud.
    let text: String
    /// Severity level — drives overlay color and TTS pitch/rate.
    let priority: Priority
    /// The metric name that triggered this cue (used for cooldown keying).
    let metric: String?
    /// SF Symbol name for the overlay icon.
    let icon: String
}

// MARK: - LiveCoachingMetrics

/// Type-erased bag of live metric values passed into `CoachingEngine.evaluate`.
///
/// Each sport module populates only the fields it tracks; unused fields stay `nil`.
struct LiveCoachingMetrics: Sendable {

    // MARK: Striking
    var hipShoulderSeparation: Double?    // degrees
    var strikeVelocityMPH: Double?
    var stanceRecoveryTime: Double?       // seconds
    var leftRightBalance: Double?         // 0..1 (0 = fully left, 1 = fully right)
    var isSessionActive: Bool = false

    // MARK: Grappling
    var isBaseStable: Bool?
    var spineAngleDegrees: Double?
    var kuzushiIndex: Double?             // 0..100
    var centerOfMassInBase: Bool?

    // MARK: IronTracker
    var vbtVelocityMs: Double?
    var bilateralSymmetry: Double?        // 0..1 (1.0 = perfect)
    var buttWinkDetected: Bool?
    var autoRepCount: Int?

    // MARK: WallBeta
    var hipProximityScore: Double?        // 0..100
    var sagDetected: Bool?
    var timeUnderTensionAvg: Double?      // seconds
}

// MARK: - CoachingEngine

/// Pure-function namespace that produces both real-time `CoachCue` values and
/// post-session `CoachingNote` values from session data.
///
/// Real-time coaching (live session):
/// ```swift
/// let metrics = LiveCoachingMetrics(hipShoulderSeparation: 18, ...)
/// let cue = CoachingEngine.evaluate(metrics: metrics, sport: .striking, cooldowns: &cooldowns)
/// ```
///
/// Post-session notes:
/// ```swift
/// let notes = CoachingEngine.generateNotes(for: result, previousSessions: history)
/// ```
enum CoachingEngine {

    // MARK: - Cooldown Interval

    /// Minimum seconds between two cues of the same category.
    static let cueCooldownSeconds: TimeInterval = 8.0

    // MARK: - Real-Time Cue Evaluation

    /// Derives a single `CoachCue` from the current live metrics for the given sport.
    ///
    /// Returns `nil` when no condition threshold is exceeded or when the most-relevant
    /// cue category is still within its cooldown window.
    ///
    /// - Parameters:
    ///   - metrics: The latest computed biomechanics values for this frame.
    ///   - sport: The active sport module — selects which rule set to evaluate.
    ///   - cooldowns: Caller-owned dictionary mapping cue-category keys to the last
    ///     time that category fired. Updated in place when a cue is returned.
    /// - Returns: A `CoachCue` if a threshold was exceeded and the cooldown has elapsed,
    ///   otherwise `nil`.
    static func evaluate(
        metrics: LiveCoachingMetrics,
        sport: SportType,
        cooldowns: inout [String: Date]
    ) -> CoachCue? {
        switch sport {
        case .striking:    return strikingCue(metrics: metrics, cooldowns: &cooldowns)
        case .grappling:   return grapplingCue(metrics: metrics, cooldowns: &cooldowns)
        case .ironTracker: return ironTrackerCue(metrics: metrics, cooldowns: &cooldowns)
        case .wallBeta:    return wallBetaCue(metrics: metrics, cooldowns: &cooldowns)
        }
    }

    // MARK: - Private: Striking Cues

    private static func strikingCue(
        metrics: LiveCoachingMetrics,
        cooldowns: inout [String: Date]
    ) -> CoachCue? {
        let sep = metrics.hipShoulderSeparation ?? 0
        let vel = metrics.strikeVelocityMPH ?? 0
        let recovery = metrics.stanceRecoveryTime ?? 0
        let balance = metrics.leftRightBalance ?? 0.5

        // Priority order: critical > warning > info.
        // Each check includes its cooldown key so categories fire independently.

        if balance < 0.4 {
            return fireCue(
                CoachCue(
                    text: "You're over-committed to one side — keep your guard",
                    priority: .warning,
                    metric: "leftRightBalance",
                    icon: "shield.slash"
                ),
                key: "striking_balance",
                cooldowns: &cooldowns
            )
        }

        if recovery > 0.8 {
            return fireCue(
                CoachCue(
                    text: "Reset faster — get back to stance immediately",
                    priority: .warning,
                    metric: "stanceRecoveryTime",
                    icon: "arrow.counterclockwise"
                ),
                key: "striking_recovery",
                cooldowns: &cooldowns
            )
        }

        if sep < 15 {
            return fireCue(
                CoachCue(
                    text: "Rotate your hips FIRST — lead with the core, not the arm",
                    priority: .warning,
                    metric: "hipShoulderSeparation",
                    icon: "rotate.right"
                ),
                key: "striking_sep_low",
                cooldowns: &cooldowns
            )
        }

        if sep > 35 {
            return fireCue(
                CoachCue(
                    text: "Perfect hip rotation — keep that coiling motion",
                    priority: .info,
                    metric: "hipShoulderSeparation",
                    icon: "checkmark.circle"
                ),
                key: "striking_sep_high",
                cooldowns: &cooldowns
            )
        }

        if vel > 12.0 {
            return fireCue(
                CoachCue(
                    text: "Explosive! That's elite-level hand speed",
                    priority: .info,
                    metric: "strikeVelocity",
                    icon: "bolt.fill"
                ),
                key: "striking_vel_high",
                cooldowns: &cooldowns
            )
        }

        if vel < 4.0, vel > 0.1, metrics.isSessionActive {
            return fireCue(
                CoachCue(
                    text: "Drive through the target — commit to the strike",
                    priority: .info,
                    metric: "strikeVelocity",
                    icon: "arrow.up.forward"
                ),
                key: "striking_vel_low",
                cooldowns: &cooldowns
            )
        }

        return nil
    }

    // MARK: - Private: Grappling Cues

    private static func grapplingCue(
        metrics: LiveCoachingMetrics,
        cooldowns: inout [String: Date]
    ) -> CoachCue? {
        let isBaseStable = metrics.isBaseStable ?? true
        let spineAngle = metrics.spineAngleDegrees ?? 0
        let kuzushi = metrics.kuzushiIndex ?? 0
        let comInBase = metrics.centerOfMassInBase ?? true

        if !isBaseStable {
            return fireCue(
                CoachCue(
                    text: "BASE — drop your hips and widen your base NOW",
                    priority: .critical,
                    metric: "isBaseStable",
                    icon: "exclamationmark.triangle.fill"
                ),
                key: "grappling_base",
                cooldowns: &cooldowns
            )
        }

        if !comInBase {
            return fireCue(
                CoachCue(
                    text: "Off balance — realign your center over your feet",
                    priority: .warning,
                    metric: "centerOfMassInBase",
                    icon: "scope"
                ),
                key: "grappling_com",
                cooldowns: &cooldowns
            )
        }

        if spineAngle > 45 {
            return fireCue(
                CoachCue(
                    text: "You're getting broken down — straighten up",
                    priority: .warning,
                    metric: "spineAngle",
                    icon: "arrow.up.to.line"
                ),
                key: "grappling_spine",
                cooldowns: &cooldowns
            )
        }

        if kuzushi > 0.7 * 100 {
            return fireCue(
                CoachCue(
                    text: "Perfect kuzushi — commit to the throw!",
                    priority: .info,
                    metric: "kuzushiIndex",
                    icon: "hand.raised.fill"
                ),
                key: "grappling_kuzushi_high",
                cooldowns: &cooldowns
            )
        }

        return nil
    }

    // MARK: - Private: IronTracker Cues

    private static func ironTrackerCue(
        metrics: LiveCoachingMetrics,
        cooldowns: inout [String: Date]
    ) -> CoachCue? {
        let vbt = metrics.vbtVelocityMs ?? 0
        let symmetry = metrics.bilateralSymmetry ?? 1.0
        let buttWink = metrics.buttWinkDetected ?? false
        let repCount = metrics.autoRepCount ?? 0

        if buttWink {
            return fireCue(
                CoachCue(
                    text: "BUTT WINK — protect your lower back, stop the set",
                    priority: .critical,
                    metric: "buttWink",
                    icon: "exclamationmark.shield.fill"
                ),
                key: "iron_buttwink",
                cooldowns: &cooldowns
            )
        }

        if symmetry < 0.85 {
            return fireCue(
                CoachCue(
                    text: "Left/right imbalance detected — focus on the weak side",
                    priority: .warning,
                    metric: "bilateralSymmetry",
                    icon: "scale.3d"
                ),
                key: "iron_symmetry",
                cooldowns: &cooldowns
            )
        }

        if vbt < 0.2, vbt > 0.01 {
            return fireCue(
                CoachCue(
                    text: "Bar speed dying — reduce weight or you're grinding",
                    priority: .warning,
                    metric: "vbtVelocity",
                    icon: "gauge.low"
                ),
                key: "iron_vbt_low",
                cooldowns: &cooldowns
            )
        }

        if vbt > 0.8 {
            return fireCue(
                CoachCue(
                    text: "Explosive tempo — excellent velocity-based training",
                    priority: .info,
                    metric: "vbtVelocity",
                    icon: "gauge.high"
                ),
                key: "iron_vbt_high",
                cooldowns: &cooldowns
            )
        }

        if repCount == 1 {
            return fireCue(
                CoachCue(
                    text: "Rep 1 — full range of motion",
                    priority: .info,
                    metric: "autoRepCount",
                    icon: "1.circle"
                ),
                key: "iron_rep_first",
                cooldowns: &cooldowns
            )
        }

        if repCount > 0, repCount % 5 == 0 {
            return fireCue(
                CoachCue(
                    text: "That's \(repCount) — keep breathing",
                    priority: .info,
                    metric: "autoRepCount",
                    icon: "checkmark.circle"
                ),
                key: "iron_rep_milestone",
                cooldowns: &cooldowns
            )
        }

        return nil
    }

    // MARK: - Private: WallBeta Cues

    private static func wallBetaCue(
        metrics: LiveCoachingMetrics,
        cooldowns: inout [String: Date]
    ) -> CoachCue? {
        let proximity = metrics.hipProximityScore ?? 50
        let sag = metrics.sagDetected ?? false
        let tut = metrics.timeUnderTensionAvg ?? 0

        if sag {
            return fireCue(
                CoachCue(
                    text: "Sag detected — engage your core and pull your hips up",
                    priority: .warning,
                    metric: "sagDetected",
                    icon: "arrow.down.circle"
                ),
                key: "wall_sag",
                cooldowns: &cooldowns
            )
        }

        if proximity < 30 {
            return fireCue(
                CoachCue(
                    text: "Hips OFF the wall — you're all arms, get your hips in",
                    priority: .warning,
                    metric: "hipProximity",
                    icon: "arrow.up.to.line.compact"
                ),
                key: "wall_proximity_low",
                cooldowns: &cooldowns
            )
        }

        if tut > 5.0 {
            return fireCue(
                CoachCue(
                    text: "Good static hold — controlled movement is the goal",
                    priority: .info,
                    metric: "timeUnderTension",
                    icon: "clock"
                ),
                key: "wall_tut_high",
                cooldowns: &cooldowns
            )
        }

        if proximity > 70 {
            return fireCue(
                CoachCue(
                    text: "Hips close — great technique, trust your feet",
                    priority: .info,
                    metric: "hipProximity",
                    icon: "star.fill"
                ),
                key: "wall_proximity_high",
                cooldowns: &cooldowns
            )
        }

        return nil
    }

    // MARK: - Private: Cooldown Gate

    /// Returns `cue` and stamps `cooldowns[key]` if the cooldown has elapsed.
    /// Returns `nil` if the key fired within the cooldown window.
    private static func fireCue(
        _ cue: CoachCue,
        key: String,
        cooldowns: inout [String: Date]
    ) -> CoachCue? {
        let now = Date()
        if let lastFired = cooldowns[key],
           now.timeIntervalSince(lastFired) < cueCooldownSeconds {
            return nil
        }
        cooldowns[key] = now
        return cue
    }

    // MARK: - Post-Session Note Generation

    /// Generate up to four coaching notes for a completed session.
    ///
    /// Notes are ordered: achievements first, then technique / consistency / strength notes.
    /// An additional trend note is prepended when the athlete shows three consecutive
    /// sessions of improvement on the sport's primary metric.
    ///
    /// - Parameters:
    ///   - result: The just-completed session.
    ///   - previousSessions: Earlier sessions for the same user, any sport. The engine
    ///     filters to the matching sport internally.
    /// - Returns: Up to four `CoachingNote` values ready to persist on the session.
    static func generateNotes(
        for result: SessionResult,
        previousSessions: [SessionResult]
    ) -> [CoachingNote] {
        let sportNotes: [CoachingNote]

        switch result.sport {
        case .striking:    sportNotes = strikingNotes(for: result)
        case .grappling:   sportNotes = grapplingNotes(for: result)
        case .ironTracker: sportNotes = ironTrackerNotes(for: result)
        case .wallBeta:    sportNotes = wallBetaNotes(for: result)
        }

        let trendNote = improvementTrendNote(for: result, previousSessions: previousSessions)

        // Achievements surface first, then all other categories.
        let achievements = sportNotes.filter { $0.category == "achievement" }
        let others = sportNotes.filter { $0.category != "achievement" }

        var ordered: [CoachingNote] = achievements + others
        if let trend = trendNote {
            ordered.insert(trend, at: 0)
        }

        return Array(ordered.prefix(4))
    }

    /// Returns a short goal string to display at the top of the next-session prompt.
    ///
    /// - Parameter result: The most recently completed session.
    /// - Returns: A one-sentence motivational target for the athlete's next workout.
    static func nextSessionGoal(for result: SessionResult) -> String {
        switch result.sport {
        case .striking:    return strikingGoal(for: result)
        case .grappling:   return grapplingGoal(for: result)
        case .ironTracker: return ironTrackerGoal(for: result)
        case .wallBeta:    return wallBetaGoal(for: result)
        }
    }

    // MARK: - Sport-Specific Note Generators

    // MARK: Striking

    private static func strikingNotes(for result: SessionResult) -> [CoachingNote] {
        var notes: [CoachingNote] = []

        // peak_velocity_mph
        if let velocity = result.metrics["peak_velocity_mph"] {
            let formatted = String(format: "%.1f", velocity)
            if velocity > 30 {
                notes.append(CoachingNote(
                    category: "achievement",
                    icon: "bolt.fill",
                    headline: "Elite Velocity",
                    detail: "Your top strike hit \(formatted) mph — that's in the top 20% of athletes. Elite fighters average 28–35 mph.",
                    metricKey: "peak_velocity_mph",
                    metricValue: velocity
                ))
            } else if velocity < 12 {
                notes.append(CoachingNote(
                    category: "technique",
                    icon: "arrow.up.circle",
                    headline: "Build Your Foundation",
                    detail: "Strikes averaged under 12 mph. Focus on rear-leg drive and proper stance width before chasing speed.",
                    metricKey: "peak_velocity_mph",
                    metricValue: velocity
                ))
            }
        }

        // kinematic_score
        if let score = result.metrics["kinematic_score"] {
            if score > 80 {
                notes.append(CoachingNote(
                    category: "achievement",
                    icon: "checkmark.seal.fill",
                    headline: "Perfect Chain",
                    detail: "Kinematic chain scored \(Int(score))/100 — elite energy transfer. Keep this pattern as you increase velocity.",
                    metricKey: "kinematic_score",
                    metricValue: score
                ))
            } else if score < 60 {
                notes.append(CoachingNote(
                    category: "technique",
                    icon: "link",
                    headline: "Hips Before Hands",
                    detail: "Chain score \(Int(score))/100 — upper body is doing most of the work. Drill 'hip-tap jabs': tap your lead hip forward before every strike.",
                    metricKey: "kinematic_score",
                    metricValue: score
                ))
            }
        }

        // hip_shoulder_sep
        if let sep = result.metrics["hip_shoulder_sep"] {
            let formatted = String(format: "%.1f", sep)
            if sep > 32 {
                notes.append(CoachingNote(
                    category: "strength",
                    icon: "flame.fill",
                    headline: "Strong Coil",
                    detail: "Hip-shoulder separation at \(formatted)° — you're storing real rotational energy before each strike.",
                    metricKey: "hip_shoulder_sep",
                    metricValue: sep
                ))
            } else if sep < 20 {
                notes.append(CoachingNote(
                    category: "technique",
                    icon: "rotate.right",
                    headline: "Load Your Coil",
                    detail: "Separation averaged \(formatted)°. Great strikers open 35°+. Drill: hips first, freeze, then shoulders follow.",
                    metricKey: "hip_shoulder_sep",
                    metricValue: sep
                ))
            }
        }

        // strike_count
        if let count = result.metrics["strike_count"] {
            if count > 25 {
                notes.append(CoachingNote(
                    category: "achievement",
                    icon: "figure.martial.arts",
                    headline: "High Volume",
                    detail: "\(Int(count)) strikes — excellent volume for pattern analysis.",
                    metricKey: "strike_count",
                    metricValue: count
                ))
            } else if count < 5 {
                notes.append(CoachingNote(
                    category: "consistency",
                    icon: "timer",
                    headline: "Short Session",
                    detail: "Only \(Int(count)) strikes detected. Aim for 15+ strikes for meaningful data.",
                    metricKey: "strike_count",
                    metricValue: count
                ))
            }
        }

        return notes
    }

    // MARK: Grappling

    private static func grapplingNotes(for result: SessionResult) -> [CoachingNote] {
        var notes: [CoachingNote] = []

        // kuzushi_index
        if let kuzushi = result.metrics["kuzushi_index"] {
            if kuzushi > 75 {
                notes.append(CoachingNote(
                    category: "achievement",
                    icon: "hand.raised.fill",
                    headline: "Strong Kuzushi",
                    detail: "Index \(Int(kuzushi))/100 — dominant control positions. Translates to more successful throw attempts.",
                    metricKey: "kuzushi_index",
                    metricValue: kuzushi
                ))
            }
        }

        // base_stability
        if let stability = result.metrics["base_stability"] {
            if stability < 0.5 {
                notes.append(CoachingNote(
                    category: "technique",
                    icon: "exclamationmark.triangle",
                    headline: "Widen Your Base",
                    detail: "Stability \(Int(stability * 100))% — weight was outside your foot platform frequently. Place feet hip-width+ apart before any engagement.",
                    metricKey: "base_stability",
                    metricValue: stability
                ))
            }
        }

        // postural_breaks
        if let breaks = result.metrics["postural_breaks"] {
            if breaks > 3 {
                notes.append(CoachingNote(
                    category: "technique",
                    icon: "shield.slash",
                    headline: "Protect Your Base",
                    detail: "\(Int(breaks)) postural breaks — each break is a sweep opportunity for your opponent.",
                    metricKey: "postural_breaks",
                    metricValue: breaks
                ))
            }
        }

        // com_control
        if let control = result.metrics["com_control"] {
            if control > 0.8 {
                notes.append(CoachingNote(
                    category: "achievement",
                    icon: "scope",
                    headline: "Excellent CoM Control",
                    detail: "\(Int(control * 100))% — your weight management is disciplined.",
                    metricKey: "com_control",
                    metricValue: control
                ))
            }
        }

        return notes
    }

    // MARK: Iron Tracker

    private static func ironTrackerNotes(for result: SessionResult) -> [CoachingNote] {
        var notes: [CoachingNote] = []

        // bar_path_deviation_cm
        if let deviation = result.metrics["bar_path_deviation_cm"] {
            let formatted = String(format: "%.1f", deviation)
            if deviation < 2 {
                notes.append(CoachingNote(
                    category: "achievement",
                    icon: "arrow.up",
                    headline: "Clean Bar Path",
                    detail: "\(formatted)cm deviation — world-class technique shows <2cm.",
                    metricKey: "bar_path_deviation_cm",
                    metricValue: deviation
                ))
            } else if deviation > 5 {
                notes.append(CoachingNote(
                    category: "technique",
                    icon: "arrow.left.and.right",
                    headline: "Straighten Your Path",
                    detail: "\(formatted)cm off-path. Cue: 'pull the bar into your body' on deadlifts.",
                    metricKey: "bar_path_deviation_cm",
                    metricValue: deviation
                ))
            }
        }

        // vbt_velocity_ms
        if let velocity = result.metrics["vbt_velocity_ms"] {
            if velocity > 0.8 {
                let formatted = String(format: "%.2f", velocity)
                notes.append(CoachingNote(
                    category: "achievement",
                    icon: "gauge.high",
                    headline: "Explosive Output",
                    detail: "Bar velocity \(formatted) m/s — in the power-speed zone.",
                    metricKey: "vbt_velocity_ms",
                    metricValue: velocity
                ))
            }
        }

        // bilateral_symmetry
        if let symmetry = result.metrics["bilateral_symmetry"] {
            if symmetry < 0.85 {
                notes.append(CoachingNote(
                    category: "technique",
                    icon: "scale.3d",
                    headline: "Fix the Imbalance",
                    detail: "\(Int(symmetry * 100))% symmetry — one side leading by 15%+. Use a mirror and slow the movement.",
                    metricKey: "bilateral_symmetry",
                    metricValue: symmetry
                ))
            }
        }

        // butt_wink_angle
        if let winkAngle = result.metrics["butt_wink_angle"] {
            if winkAngle > 15 {
                let formatted = String(format: "%.0f", winkAngle)
                notes.append(CoachingNote(
                    category: "technique",
                    icon: "exclamationmark.shield",
                    headline: "Squat Depth Warning",
                    detail: "\(formatted)° pelvic tilt detected. Reduce depth until hip mobility improves.",
                    metricKey: "butt_wink_angle",
                    metricValue: winkAngle
                ))
            }
        }

        return notes
    }

    // MARK: Wall Beta

    private static func wallBetaNotes(for result: SessionResult) -> [CoachingNote] {
        var notes: [CoachingNote] = []

        // hip_proximity_score
        if let proximity = result.metrics["hip_proximity_score"] {
            if proximity > 0.75 {
                notes.append(CoachingNote(
                    category: "achievement",
                    icon: "star.fill",
                    headline: "Great Hip Position",
                    detail: "\(Int(proximity * 100))% proximity — weight over feet, not arms. The single biggest technique differentiator.",
                    metricKey: "hip_proximity_score",
                    metricValue: proximity
                ))
            } else if proximity < 0.5 {
                notes.append(CoachingNote(
                    category: "technique",
                    icon: "arrow.up.to.line.compact",
                    headline: "Hips to the Wall",
                    detail: "\(Int(proximity * 100))% — hips pulling away. Cue: 'push hips into the rock.'",
                    metricKey: "hip_proximity_score",
                    metricValue: proximity
                ))
            }
        }

        // sag_events
        if let sags = result.metrics["sag_events"] {
            if sags > 2 {
                notes.append(CoachingNote(
                    category: "technique",
                    icon: "arrow.down.circle",
                    headline: "Stop the Sag",
                    detail: "\(Int(sags)) hip sag events — engage core to keep hips elevated between moves.",
                    metricKey: "sag_events",
                    metricValue: sags
                ))
            }
        }

        // dyno_arc_smoothness
        if let smoothness = result.metrics["dyno_arc_smoothness"] {
            if smoothness > 0.8 {
                notes.append(CoachingNote(
                    category: "achievement",
                    icon: "waveform.path",
                    headline: "Smooth Dynamics",
                    detail: "\(Int(smoothness * 100))% smooth — body moving as a unit.",
                    metricKey: "dyno_arc_smoothness",
                    metricValue: smoothness
                ))
            }
        }

        // time_under_tension_avg
        if let tut = result.metrics["time_under_tension_avg"] {
            if tut > 3.0 {
                let formatted = String(format: "%.1f", tut)
                notes.append(CoachingNote(
                    category: "technique",
                    icon: "clock",
                    headline: "Reduce Hang Time",
                    detail: "\(formatted)s average hold time — decisive movement: aim for <2.5s.",
                    metricKey: "time_under_tension_avg",
                    metricValue: tut
                ))
            }
        }

        return notes
    }

    // MARK: - Trend Detection

    /// Returns an "Improving Streak" achievement note when the athlete has beaten their own
    /// score on the sport's primary metric for three consecutive previous sessions.
    private static func improvementTrendNote(
        for result: SessionResult,
        previousSessions: [SessionResult]
    ) -> CoachingNote? {
        let primaryKey = primaryMetricKey(for: result.sport)
        let higherIsBetter = primaryMetricHigherIsBetter(for: result.sport)

        guard let currentValue = result.metrics[primaryKey] else { return nil }

        // Filter and sort — most-recent first.
        let prior = previousSessions
            .filter { $0.sport == result.sport }
            .sorted { $0.startedAt > $1.startedAt }
            .prefix(3)

        guard prior.count >= 3 else { return nil }

        // Collect the three most-recent values for the primary metric.
        let priorValues = prior.compactMap { $0.metrics[primaryKey] }
        guard priorValues.count == 3 else { return nil }

        // The current session must beat all three previous values.
        let beatAll = priorValues.allSatisfy { previous in
            higherIsBetter ? currentValue > previous : currentValue < previous
        }

        guard beatAll else { return nil }

        return CoachingNote(
            category: "achievement",
            icon: "chart.line.uptrend.xyaxis",
            headline: "Improving Streak",
            detail: "3 sessions in a row of improvement on \(primaryKey.replacingOccurrences(of: "_", with: " ")). Keep the momentum.",
            metricKey: primaryKey,
            metricValue: currentValue
        )
    }

    /// The single most representative metric for each sport module.
    private static func primaryMetricKey(for sport: SportType) -> String {
        switch sport {
        case .striking:    "peak_velocity_mph"
        case .grappling:   "kuzushi_index"
        case .ironTracker: "vbt_velocity_ms"
        case .wallBeta:    "hip_proximity_score"
        }
    }

    /// Whether a higher value on the primary metric represents better performance.
    private static func primaryMetricHigherIsBetter(for sport: SportType) -> Bool {
        true
    }

    // MARK: - Next Session Goal Generators

    private static func strikingGoal(for result: SessionResult) -> String {
        if let score = result.metrics["kinematic_score"], score < 70 {
            return "Target kinematic chain above 70"
        }
        if let sep = result.metrics["hip_shoulder_sep"], sep < 32 {
            return "Push hip-shoulder separation above 32° average"
        }
        return "Maintain velocity — try combination strikes"
    }

    private static func grapplingGoal(for result: SessionResult) -> String {
        if let stability = result.metrics["base_stability"], stability < 0.7 {
            return "Hold base stability above 70% for the full session"
        }
        return "Work on transitions from both sides"
    }

    private static func ironTrackerGoal(for result: SessionResult) -> String {
        if let symmetry = result.metrics["bilateral_symmetry"], symmetry < 0.9 {
            return "Close the symmetry gap — slow reps with mirror"
        }
        if let velocity = result.metrics["vbt_velocity_ms"], velocity < 0.8 {
            return "Push bar velocity above 0.8 m/s"
        }
        return "Maintain bar path precision — keep deviation under 2 cm"
    }

    private static func wallBetaGoal(for result: SessionResult) -> String {
        if let proximity = result.metrics["hip_proximity_score"], proximity < 0.65 {
            return "Focus entirely on hip proximity — quality over quantity"
        }
        if let holdTime = result.metrics["time_under_tension_avg"], holdTime > 2.5 {
            return "Work on reducing hold time below 2.5s average"
        }
        return "Push for a clean Dyno — explosive hip drive on the crux move"
    }
}
