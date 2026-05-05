import Foundation
import SwiftUI

// MARK: - OnboardingStep

/// Ordered list of every step in the forced walkthrough.
enum OnboardingStep: Int, CaseIterable {
    case welcome        = 0
    case modules        = 1
    case videoAnalysis  = 2
    case aiCoach        = 3
    case socialFeed     = 4
    case done           = 5
}

// MARK: - OnboardingCoordinator

/// Tracks onboarding completion state via `@AppStorage` so it persists across
/// launches. Once `isComplete` flips to `true` the full-screen cover is never
/// shown again. A debug helper lets it be reset from Profile settings.
@Observable
@MainActor
final class OnboardingCoordinator {

    // MARK: - Persistence

    /// Persisted flag. `true` = onboarding has been fully completed once.
    /// Written by `OnboardingView` at the end of Step 6 (Done).
    @ObservationIgnored
    @AppStorage("onboarding_complete") var isComplete: Bool = false

    // MARK: - Debug

    /// Resets the flag so the walkthrough appears on the next launch.
    /// Exposed to `ProfileView` for development testing.
    func resetOnboarding() {
        isComplete = false
    }
}
