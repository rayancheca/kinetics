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
/// CoachVoice.shared.stop()
/// ```
@MainActor
final class CoachVoice {

    // MARK: - Shared Instance

    static let shared = CoachVoice()

    // MARK: - Private

    private let synthesizer = AVSpeechSynthesizer()

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
    ///   - priority: `.high` interrupts any ongoing utterance immediately.
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
        utterance.rate = 0.52           // Slightly faster than default (0.5)
        utterance.pitchMultiplier = 1.1 // Slightly higher for energy
        utterance.volume = 0.9
        utterance.preUtteranceDelay = 0.1

        synthesizer.speak(utterance)
    }

    /// Stops any in-progress speech at the next word boundary.
    func stop() {
        synthesizer.stopSpeaking(at: .word)
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
