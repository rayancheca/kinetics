import AVFoundation
import Foundation

// MARK: - SpeechPriority

/// Controls whether a new utterance may interrupt speech already in progress.
enum SpeechPriority {
    /// Will not interrupt speech that is already playing.
    case normal
    /// Interrupts any in-progress utterance immediately — use for critical form warnings.
    case high
}

// MARK: - CoachVoice

/// Speaks coach feedback aloud using on-device TTS.
///
/// Queues utterances and prevents overlapping speech so the athlete
/// is never bombarded with stacked cues. Gated by the `coach_voice_enabled`
/// UserDefaults key that the user controls from the Profile settings screen.
///
/// Usage:
/// ```swift
/// CoachVoice.shared.speak("Hips first, then shoulders")
/// CoachVoice.shared.speak("Stop — protect your lower back", priority: .high)
/// CoachVoice.shared.speakIfChanged(cue: myCue)
/// CoachVoice.shared.stop()
/// ```
@MainActor
final class CoachVoice {

    // MARK: - Shared Instance

    static let shared = CoachVoice()

    // MARK: - Private

    private let synthesizer = AVSpeechSynthesizer()
    private var lastSpokenText: String = ""

    private var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: "coach_voice_enabled")
    }

    // MARK: - Init

    private init() {}

    // MARK: - Speak

    /// Speaks `text` aloud when coach voice is enabled.
    ///
    /// - Parameters:
    ///   - text: The string to synthesize. Empty strings are silently ignored.
    ///   - priority: `.high` interrupts any ongoing utterance immediately,
    ///     uses a lower pitch (0.95) and slower rate (0.45) for urgency.
    ///     `.normal` (default) is a no-op if the synthesizer is already speaking,
    ///     preventing cue pile-up at 30 fps.
    func speak(_ text: String, priority: SpeechPriority = .normal) {
        guard isEnabled, !text.isEmpty else { return }

        if priority == .high {
            synthesizer.stopSpeaking(at: .immediate)
        } else if synthesizer.isSpeaking {
            // Do not interrupt for normal-priority cues — wait for silence.
            return
        }

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.volume = 0.9
        utterance.preUtteranceDelay = 0.1

        if priority == .high {
            // Critical cues: lower pitch and slower rate to convey urgency.
            utterance.rate = 0.45
            utterance.pitchMultiplier = 0.95
        } else {
            // Info cues: slightly faster and higher for energy.
            utterance.rate = 0.52
            utterance.pitchMultiplier = 1.1
        }

        synthesizer.speak(utterance)
    }

    /// Speaks the cue only if it differs from the last spoken text.
    ///
    /// Handles deduplication so call sites don't need to track the previous value.
    /// Critical cues always interrupt regardless of whether text is identical.
    ///
    /// - Parameter cue: The `CoachCue` to potentially speak.
    func speakIfChanged(cue: CoachCue) {
        guard isEnabled else { return }

        let priority: SpeechPriority = cue.priority == .critical ? .high : .normal

        if cue.priority == .critical {
            // Critical warnings always fire immediately, even if text matches.
            speak(cue.text, priority: .high)
            lastSpokenText = cue.text
        } else if cue.text != lastSpokenText {
            lastSpokenText = cue.text
            speak(cue.text, priority: priority)
        }
    }

    /// Stops any in-progress speech at the next word boundary.
    func stop() {
        synthesizer.stopSpeaking(at: .word)
        lastSpokenText = ""
    }
}

// MARK: - String + Warning Detection

extension String {
    /// Returns `true` if the string contains keywords associated with critical form
    /// warnings or injury risk, which should be spoken at `.high` priority.
    var isHighPriorityCue: Bool {
        let lower = lowercased()
        let keywords = ["danger", "injury", "warning", "stop", "posture break", "brace", "protect"]
        return keywords.contains { lower.contains($0) }
    }
}
