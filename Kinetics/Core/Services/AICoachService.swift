import Foundation

// MARK: - BodyCompositionContext

/// Optional biometric context that enriches the AI prompt with athlete body data.
struct BodyCompositionContext: Sendable {
    let weightKg: Double
    let heightCm: Double
    let bodyFatPercent: Double
    let ageYears: Int
    let skeletalMuscleMassKg: Double
}

// MARK: - AICoachError

/// Errors that `AICoachService` can produce during report generation.
enum AICoachError: Error, Sendable {
    case missingAPIKey
    case networkError(Error)
    case invalidResponse
    case parsingFailed(String)
}

// MARK: - AICoachService

/// Sends biomechanics session data to the Claude API and returns a structured
/// `CoachReport`. Falls back to sport-specific templated coaching when the API
/// key is absent so the UI always has something to display.
///
/// Isolated as an `actor` because it performs async network I/O and caches
/// the resolved API key — no external locking required.
actor AICoachService {

    // MARK: - Shared Instance

    static let shared = AICoachService()

    // MARK: - Private Constants

    private let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    private let anthropicVersion = "2023-06-01"
    private let model = "claude-sonnet-4-6"
    private let maxTokens = 2048

    // MARK: - Init

    private init() {}

    // MARK: - API Key Status

    /// Returns `true` when a non-empty, non-placeholder Claude API key is
    /// present in `Info.plist`. Use this from the UI to show or hide the
    /// "AI coaching unavailable" banner without making a network call.
    nonisolated static var isAPIKeyConfigured: Bool {
        guard let key = Bundle.main.object(forInfoDictionaryKey: "CLAUDE_API_KEY") as? String,
              !key.isEmpty,
              key != "YOUR_API_KEY_HERE" else { return false }
        return true
    }

    // MARK: - API Key Resolution

    /// Reads the Claude API key from `Info.plist` at the `CLAUDE_API_KEY` key.
    /// Returns an empty string (not `nil`) so callers can do a simple `isEmpty` check.
    private var apiKey: String {
        Bundle.main.object(forInfoDictionaryKey: "CLAUDE_API_KEY") as? String ?? ""
    }

    // MARK: - Main Entry Point

    /// Generates a `CoachReport` for the given session.
    ///
    /// When the API key is empty or missing, throws `AICoachError.missingAPIKey`
    /// so the UI can show a clear, actionable message instead of template output.
    /// Network and parsing errors are surfaced as thrown `AICoachError` values.
    ///
    /// - Parameters:
    ///   - sport: Module identifier — e.g. `"striking"`, `"grappling"`,
    ///     `"ironTracker"`, `"wallBeta"`, `"gym"`, `"track"`.
    ///   - metrics: Sport-specific numeric metrics keyed by human-readable label.
    ///   - bodyContext: Optional biometric data for the athlete.
    ///   - sessionCount: Total completed sessions (used to calibrate advice level).
    ///   - subjectLabel: `"You"` for the primary athlete or `"Person 2"` etc.
    ///   - videoDurationSeconds: Runtime of the analysed video clip.
    ///   - keyObservations: Brief human-readable statements from the Vision engine.
    /// - Returns: A fully-populated `CoachReport`.
    /// - Throws: `AICoachError.missingAPIKey` when no valid key is configured.
    func generateReport(
        sport: String,
        metrics: [String: Double],
        bodyContext: BodyCompositionContext?,
        sessionCount: Int,
        subjectLabel: String,
        videoDurationSeconds: Double,
        keyObservations: [String]
    ) async throws -> CoachReport {
        let key = apiKey
        guard !key.isEmpty, key != "YOUR_API_KEY_HERE" else {
            throw AICoachError.missingAPIKey
        }

        let prompt = buildPrompt(
            sport: sport,
            metrics: metrics,
            bodyContext: bodyContext,
            sessionCount: sessionCount,
            subjectLabel: subjectLabel,
            videoDurationSeconds: videoDurationSeconds,
            keyObservations: keyObservations
        )

        let jsonText = try await callClaudeAPI(prompt: prompt, apiKey: key)
        guard let report = parseReport(from: jsonText) else {
            throw AICoachError.parsingFailed(jsonText)
        }
        return report
    }

    // MARK: - Claude API Call

    private func callClaudeAPI(prompt: String, apiKey: String) async throws -> String {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 25
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(anthropicVersion, forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")

        let body: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "messages": [
                ["role": "user", "content": prompt]
            ]
        ]

        guard let bodyData = try? JSONSerialization.data(withJSONObject: body) else {
            throw AICoachError.invalidResponse
        }
        request.httpBody = bodyData

        let data: Data
        do {
            let (responseData, _) = try await URLSession.shared.data(for: request)
            data = responseData
        } catch {
            throw AICoachError.networkError(error)
        }

        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let content = json["content"] as? [[String: Any]],
            let firstBlock = content.first,
            let text = firstBlock["text"] as? String
        else {
            throw AICoachError.invalidResponse
        }

        return text
    }

    // MARK: - Parsing

    private func parseReport(from jsonText: String) -> CoachReport? {
        // Strip markdown fences Claude occasionally wraps around the JSON.
        let stripped = jsonText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard
            let data = stripped.data(using: .utf8),
            let rawDict = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        return buildReport(from: rawDict)
    }

    /// Assembles a `CoachReport` from a loosely-typed dictionary, providing safe
    /// fallbacks for every field so a partially-complete Claude response still
    /// yields a usable report rather than a nil.
    private func buildReport(from dict: [String: Any]) -> CoachReport? {
        let summary = dict["summary"] as? String ?? ""
        let score = dict["overallScore"] as? Int ?? 60
        let strengths = dict["strengths"] as? [String] ?? []
        let improvements = dict["improvements"] as? [String] ?? []

        let tips: [CoachReport.TimestampedTip] = (dict["tips"] as? [[String: Any]] ?? [])
            .compactMap { tipDict in
                guard let id = tipDict["id"] as? String,
                      let text = tipDict["text"] as? String else { return nil }
                let ts = tipDict["timestampSeconds"] as? Double ?? 0.0
                let cat = CoachReport.TimestampedTip.TipCategory(
                    rawValue: tipDict["category"] as? String ?? ""
                ) ?? .technique
                let sev = CoachReport.TimestampedTip.TipSeverity(
                    rawValue: tipDict["severity"] as? String ?? ""
                ) ?? .info
                return CoachReport.TimestampedTip(
                    id: id,
                    timestampSeconds: ts,
                    category: cat,
                    severity: sev,
                    text: text
                )
            }

        let drills: [CoachReport.DrillRecommendation] = (
            dict["drillRecommendations"] as? [[String: Any]] ?? []
        ).compactMap { d in
            guard let id = d["id"] as? String,
                  let name = d["name"] as? String else { return nil }
            return CoachReport.DrillRecommendation(
                id: id,
                name: name,
                reason: d["reason"] as? String ?? "",
                sport: d["sport"] as? String ?? "",
                durationMinutes: d["durationMinutes"] as? Int ?? 10
            )
        }

        return CoachReport(
            summary: summary,
            overallScore: max(0, min(100, score)),
            tips: tips,
            strengths: strengths,
            improvements: improvements,
            drillRecommendations: drills,
            generatedAt: Date()
        )
    }

    // MARK: - Prompt Builder

    private func buildPrompt(
        sport: String,
        metrics: [String: Double],
        bodyContext: BodyCompositionContext?,
        sessionCount: Int,
        subjectLabel: String,
        videoDurationSeconds: Double,
        keyObservations: [String]
    ) -> String {
        var parts: [String] = []

        parts.append("""
        You are an elite sports performance coach inside the Kinetics app — a professional \
        biomechanics analysis platform. Your task is to analyse the session data below and \
        return structured, actionable coaching feedback.
        """)

        parts.append("Sport module: \(sport)")
        parts.append("Subject: \(subjectLabel)")
        let expLabel = experienceLabel(sessionCount)
        parts.append("Session number: \(sessionCount) (experience level: \(expLabel))")
        parts.append("Video duration: \(String(format: "%.1f", videoDurationSeconds))s")

        if !metrics.isEmpty {
            let metricsLines = metrics
                .sorted { $0.key < $1.key }
                .map { "  • \($0.key): \(formattedMetric($0.value))" }
                .joined(separator: "\n")
            parts.append("Metrics:\n\(metricsLines)")
        }

        if let bc = bodyContext {
            parts.append("""
            Athlete body composition:
              • Age: \(bc.ageYears) yrs
              • Height: \(String(format: "%.0f", bc.heightCm)) cm
              • Weight: \(String(format: "%.1f", bc.weightKg)) kg
              • Body fat: \(String(format: "%.1f", bc.bodyFatPercent))%
              • Skeletal muscle mass: \(String(format: "%.1f", bc.skeletalMuscleMassKg)) kg
            """)
        }

        if !keyObservations.isEmpty {
            let obs = keyObservations.map { "  • \($0)" }.joined(separator: "\n")
            parts.append("Key observations from video analysis:\n\(obs)")
        }

        parts.append("""
        Return ONLY a JSON object matching this exact schema — no additional text, \
        no markdown code fences:

        {
          "summary": "2-3 sentence overall assessment",
          "overallScore": 75,
          "tips": [
            {
              "id": "tip-1",
              "timestampSeconds": 12.5,
              "category": "form",
              "severity": "warning",
              "text": "Your elbow flares at the peak of the press — keep it at 45 degrees \
        to the torso."
            }
          ],
          "strengths": ["Hip drive is explosive", "Good stance width"],
          "improvements": ["Elbow alignment on press", "Breathing pattern"],
          "drillRecommendations": [
            {
              "id": "drill-1",
              "name": "Banded Hip Hinge",
              "reason": "Reinforce neutral spine at the bottom",
              "sport": "ironTracker",
              "durationMinutes": 10
            }
          ]
        }

        Valid category values: form, power, technique, safety, breathing, positioning
        Valid severity values: info, warning, critical
        Do not include any text outside of the JSON object.
        """)

        return parts.joined(separator: "\n\n")
    }

    // MARK: - Prompt Helpers

    private func experienceLabel(_ sessionCount: Int) -> String {
        switch sessionCount {
        case 0...3: return "beginner"
        case 4...15: return "developing"
        case 16...40: return "intermediate"
        case 41...100: return "advanced"
        default: return "elite"
        }
    }

    private func formattedMetric(_ value: Double) -> String {
        if value == value.rounded() { return String(Int(value)) }
        return String(format: "%.2f", value)
    }

    // MARK: - Fallback Templates

    /// Returns a sport-specific templated `CoachReport` used when no API key
    /// is configured. Every sport returns substantive, non-empty content.
    private func templateReport(sport: String, metrics: [String: Double]) -> CoachReport {
        switch sport {
        case "striking":
            return strikingTemplate(metrics: metrics)
        case "grappling":
            return grapplingTemplate(metrics: metrics)
        case "ironTracker":
            return ironTrackerTemplate(metrics: metrics)
        case "wallBeta":
            return wallBetaTemplate(metrics: metrics)
        case "gym":
            return gymTemplate(metrics: metrics)
        case "track":
            return trackTemplate(metrics: metrics)
        default:
            return genericTemplate(sport: sport, metrics: metrics)
        }
    }

    private func strikingTemplate(metrics: [String: Double]) -> CoachReport {
        CoachReport(
            summary: """
            Your kinetic chain shows solid lower-body engagement. Focus on leading hip \
            rotation before shoulder turn to maximise power transfer — your hips and \
            shoulders are currently rotating almost simultaneously.
            """,
            overallScore: 62,
            tips: [
                .init(
                    id: "tip-1",
                    timestampSeconds: 0.0,
                    category: .form,
                    severity: .warning,
                    text: "Initiate strikes from the hip, not the shoulder. " +
                        "Hip-to-shoulder separation should reach at least 35°."
                ),
                .init(
                    id: "tip-2",
                    timestampSeconds: 0.0,
                    category: .power,
                    severity: .info,
                    text: "Drive off the rear foot — your heel is lifting too early, " +
                        "bleeding rotational force before the strike lands."
                ),
                .init(
                    id: "tip-3",
                    timestampSeconds: 0.0,
                    category: .technique,
                    severity: .info,
                    text: "Return to stance immediately after each strike. " +
                        "Faster reset means you are defensively sound and ready to combination."
                )
            ],
            strengths: [
                "Consistent guard position between strikes",
                "Good head movement timing during combinations"
            ],
            improvements: [
                "Hip-to-shoulder separation angle",
                "Rear heel contact during power shots",
                "Post-strike stance recovery speed"
            ],
            drillRecommendations: [
                .init(
                    id: "drill-1",
                    name: "Hip-Shadow Shadowboxing",
                    reason: "Exaggerate hip rotation before shoulder engagement " +
                        "to build the neuromuscular pattern.",
                    sport: "striking",
                    durationMinutes: 8
                ),
                .init(
                    id: "drill-2",
                    name: "Wall-Touch Jab",
                    reason: "Snap back to guard instantly — trains reflexive " +
                        "return without conscious thought.",
                    sport: "striking",
                    durationMinutes: 5
                )
            ],
            generatedAt: Date()
        )
    }

    private func grapplingTemplate(metrics: [String: Double]) -> CoachReport {
        CoachReport(
            summary: """
            Your base structure is your strongest asset — centre of mass stays low and \
            centred. Work on breaking the opponent's posture (kuzushi) earlier in your \
            entry sequence before committing to the throw or takedown.
            """,
            overallScore: 65,
            tips: [
                .init(
                    id: "tip-1",
                    timestampSeconds: 0.0,
                    category: .technique,
                    severity: .warning,
                    text: "Execute kuzushi — off-balance the opponent — before stepping " +
                        "into the throw. Entering upright telegraphs the attempt."
                ),
                .init(
                    id: "tip-2",
                    timestampSeconds: 0.0,
                    category: .positioning,
                    severity: .info,
                    text: "Keep hips below the opponent's centre of mass during " +
                        "clinch entries to generate upward lift."
                ),
                .init(
                    id: "tip-3",
                    timestampSeconds: 0.0,
                    category: .safety,
                    severity: .info,
                    text: "After a failed submission attempt, immediately reset base — " +
                        "do not flatten out while searching for the next attack."
                )
            ],
            strengths: [
                "Low, stable base during scrambles",
                "Effective weight distribution on top"
            ],
            improvements: [
                "Kuzushi timing before throw entry",
                "Hip elevation angle for guard submissions",
                "Spine posture during standing clinch"
            ],
            drillRecommendations: [
                .init(
                    id: "drill-1",
                    name: "Kuzushi Entry Reps",
                    reason: "Practise breaking balance in three directions before " +
                        "committing to any throw entry.",
                    sport: "grappling",
                    durationMinutes: 10
                ),
                .init(
                    id: "drill-2",
                    name: "Hip Escape Flow Drill",
                    reason: "Build automatic base recovery after failed " +
                        "submission attempts.",
                    sport: "grappling",
                    durationMinutes: 7
                )
            ],
            generatedAt: Date()
        )
    }

    private func ironTrackerTemplate(metrics: [String: Double]) -> CoachReport {
        CoachReport(
            summary: """
            Bar path deviation is the primary issue — the bar drifts forward on the \
            concentric phase, increasing shear load on your lower back. Bilateral \
            symmetry is good. Prioritise lat engagement at the start of each pull.
            """,
            overallScore: 60,
            tips: [
                .init(
                    id: "tip-1",
                    timestampSeconds: 0.0,
                    category: .form,
                    severity: .warning,
                    text: "Keep the bar in contact with the body throughout the pull. " +
                        "Forward drift past 3 cm increases lumbar shear significantly."
                ),
                .init(
                    id: "tip-2",
                    timestampSeconds: 0.0,
                    category: .safety,
                    severity: .critical,
                    text: "Lumbar flexion detected at the bottom of the squat (butt wink). " +
                        "Reduce depth until hip mobility improves to protect L4–L5."
                ),
                .init(
                    id: "tip-3",
                    timestampSeconds: 0.0,
                    category: .technique,
                    severity: .info,
                    text: "On the press, your left wrist is leading by ~0.08 s. " +
                        "Cue yourself to push evenly — unilateral loading compounds over sets."
                )
            ],
            strengths: [
                "Consistent descent speed — good eccentric control",
                "Strong lockout position"
            ],
            improvements: [
                "Bar path — reduce forward drift on concentric",
                "Lumbar position at squat depth",
                "Bilateral press symmetry"
            ],
            drillRecommendations: [
                .init(
                    id: "drill-1",
                    name: "Banded Hip Hinge",
                    reason: "Reinforce neutral spine and posterior chain engagement " +
                        "at the bottom of the lift.",
                    sport: "ironTracker",
                    durationMinutes: 10
                ),
                .init(
                    id: "drill-2",
                    name: "Wall Squat Hip Mobility",
                    reason: "Improve hip flexion range to eliminate lumbar " +
                        "flexion at depth.",
                    sport: "ironTracker",
                    durationMinutes: 8
                )
            ],
            generatedAt: Date()
        )
    }

    private func wallBetaTemplate(metrics: [String: Double]) -> CoachReport {
        CoachReport(
            summary: """
            Hip proximity to the wall is below optimal — your centre of mass is pulling \
            you off the holds on overhang sections. Focus on flagging and hip turnout \
            to keep weight over your feet and reduce arm strain.
            """,
            overallScore: 58,
            tips: [
                .init(
                    id: "tip-1",
                    timestampSeconds: 0.0,
                    category: .technique,
                    severity: .warning,
                    text: "Drop your hip to the wall during traverse moves. " +
                        "Hip-to-wall distance should stay under 20 cm on slab and vert."
                ),
                .init(
                    id: "tip-2",
                    timestampSeconds: 0.0,
                    category: .positioning,
                    severity: .warning,
                    text: "Sag detected mid-route — your hips drooped below shoulder " +
                        "height, transferring load to arms. Keep hips high and flagged."
                ),
                .init(
                    id: "tip-3",
                    timestampSeconds: 0.0,
                    category: .breathing,
                    severity: .info,
                    text: "Breathe on the rest positions. Tension is visible in your " +
                        "shoulders — exhale fully on static stances."
                )
            ],
            strengths: [
                "Smooth dyno timing — good trajectory arc",
                "Efficient footwork on straight sections"
            ],
            improvements: [
                "Hip-to-wall proximity on overhang",
                "Centre-of-mass elevation — reduce hip sag",
                "Breathing and tension release on rest holds"
            ],
            drillRecommendations: [
                .init(
                    id: "drill-1",
                    name: "Hip-to-Wall Flag Drill",
                    reason: "Practise keeping hips touching the wall surface on " +
                        "a low-angle slab to build the motor pattern.",
                    sport: "wallBeta",
                    durationMinutes: 12
                ),
                .init(
                    id: "drill-2",
                    name: "Silent Feet Traversal",
                    reason: "Precise footwork reduces body sway that causes " +
                        "hip drop on overhang.",
                    sport: "wallBeta",
                    durationMinutes: 10
                )
            ],
            generatedAt: Date()
        )
    }

    private func gymTemplate(metrics: [String: Double]) -> CoachReport {
        CoachReport(
            summary: """
            Overall session quality is solid. Tempo consistency is your main variable — \
            controlling the eccentric phase more deliberately will drive greater muscle \
            stimulus and reduce injury risk on compound movements.
            """,
            overallScore: 63,
            tips: [
                .init(
                    id: "tip-1",
                    timestampSeconds: 0.0,
                    category: .technique,
                    severity: .warning,
                    text: "Eccentric phase is too fast on most sets — aim for " +
                        "a 3-second lowering to maximise time under tension."
                ),
                .init(
                    id: "tip-2",
                    timestampSeconds: 0.0,
                    category: .breathing,
                    severity: .info,
                    text: "Exhale on exertion, inhale on return. " +
                        "Breath-holding during heavy lifts spikes intrathoracic pressure."
                ),
                .init(
                    id: "tip-3",
                    timestampSeconds: 0.0,
                    category: .form,
                    severity: .info,
                    text: "Maintain a neutral wrist during pressing movements — " +
                        "excessive dorsiflexion transfers stress to the wrist joint."
                )
            ],
            strengths: [
                "Consistent rep depth across all sets",
                "Good rest period discipline"
            ],
            improvements: [
                "Eccentric tempo control",
                "Breathing pattern on heavy compound lifts",
                "Wrist alignment on pressing"
            ],
            drillRecommendations: [
                .init(
                    id: "drill-1",
                    name: "Tempo Bodyweight Squat (3-1-3)",
                    reason: "Build the proprioceptive habit of a controlled " +
                        "eccentric before adding load.",
                    sport: "gym",
                    durationMinutes: 8
                )
            ],
            generatedAt: Date()
        )
    }

    private func trackTemplate(metrics: [String: Double]) -> CoachReport {
        CoachReport(
            summary: """
            Stride mechanics are efficient at sub-maximal pace. At top speed, \
            ground contact time extends — focus on quick, reactive foot strike \
            rather than a pushing action to improve your speed ceiling.
            """,
            overallScore: 67,
            tips: [
                .init(
                    id: "tip-1",
                    timestampSeconds: 0.0,
                    category: .technique,
                    severity: .warning,
                    text: "Ground contact time at max velocity is above threshold — " +
                        "think 'paw back' rather than 'push down' for elastic energy return."
                ),
                .init(
                    id: "tip-2",
                    timestampSeconds: 0.0,
                    category: .form,
                    severity: .info,
                    text: "Arm swing crosses body midline slightly. " +
                        "Drive elbows back parallel to direction of travel — no crossover."
                ),
                .init(
                    id: "tip-3",
                    timestampSeconds: 0.0,
                    category: .breathing,
                    severity: .info,
                    text: "Breathe rhythmically — every 2 strides on shorter reps, " +
                        "every 3-4 on tempo runs. Irregular breathing wastes energy."
                )
            ],
            strengths: [
                "Consistent stride length at aerobic pace",
                "Good forward lean angle at race pace"
            ],
            improvements: [
                "Ground contact time at maximum velocity",
                "Arm swing alignment",
                "Breathing cadence during intense efforts"
            ],
            drillRecommendations: [
                .init(
                    id: "drill-1",
                    name: "A-Skip Drill",
                    reason: "Reinforce high knee drive and quick ground contact " +
                        "as a neuromuscular cue for sprint mechanics.",
                    sport: "track",
                    durationMinutes: 6
                ),
                .init(
                    id: "drill-2",
                    name: "Straight-Arm Bounding",
                    reason: "Isolates the foot strike pattern and builds elastic " +
                        "energy return through the Achilles.",
                    sport: "track",
                    durationMinutes: 8
                )
            ],
            generatedAt: Date()
        )
    }

    private func genericTemplate(sport: String, metrics: [String: Double]) -> CoachReport {
        CoachReport(
            summary: """
            Session data recorded. Connect your Claude API key in Settings to \
            receive personalised AI coaching for \(sport). In the meantime, focus \
            on consistency, controlled movement, and progressive overload.
            """,
            overallScore: 60,
            tips: [
                .init(
                    id: "tip-1",
                    timestampSeconds: 0.0,
                    category: .form,
                    severity: .info,
                    text: "Film multiple angles to capture full-body mechanics. " +
                        "A side profile is most informative for most sports."
                ),
                .init(
                    id: "tip-2",
                    timestampSeconds: 0.0,
                    category: .technique,
                    severity: .info,
                    text: "Log session frequency and perceived effort alongside " +
                        "the metrics Kinetics tracks to build a clearer progress picture."
                )
            ],
            strengths: [
                "Session completed and data captured",
                "Consistent use of Kinetics tracking"
            ],
            improvements: [
                "Add Claude API key for personalised AI coaching",
                "Film from a stable, unobstructed angle"
            ],
            drillRecommendations: [
                .init(
                    id: "drill-1",
                    name: "Sport-Specific Mobility Warm-Up",
                    reason: "5–10 min of dynamic mobility primes the joints for " +
                        "better range of motion during analysis sessions.",
                    sport: sport,
                    durationMinutes: 8
                )
            ],
            generatedAt: Date()
        )
    }
}
