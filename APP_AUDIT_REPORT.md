# KINETICS APP AUDIT — PRE-APP STORE GRADING REPORT

**Date:** 2026-05-04  
**Auditor:** Claude Code (Senior Code Review)  
**Codebase state:** Session 10 complete — 119 Swift files, BUILD SUCCEEDED (simulator)  
**Scope:** Full static analysis of source code, architecture, security posture, and App Store readiness

---

## PERSPECTIVE 1 — VENTURE CAPITALIST

**Grade: 6.5 / 10**

### What Is Impressive

The strategic architecture is genuinely clever. The super-app-to-micro-app pipeline is a defensible go-to-market play — build everything, instrument everything, spin off the winner. That is a smarter approach than launching a single-sport app cold. The use of Apple's own Vision Framework (rather than a third-party ML dependency like MediaPipe) creates a distribution and privacy moat: no SDK vendor risk, no off-device data processing, and no GDPR/CCPA headache around biometric data leaving the device. The breadth of the feature surface — four sport modules, GPS track, social layer, gym tracker, HealthKit integration, video AI analysis, WidgetKit, deep links, StoreKit skeleton — demonstrates that the developer can ship volume at speed.

The Firebase Analytics telemetry wiring is correctly positioned. Every module fires `module_session_started` and `module_session_completed`, which is exactly what you need to run the Phase 2 data exercise. The tab screen-time events give a secondary engagement signal. The foundational instrumentation is correct.

### Critical Concerns

**Retention problem: the social graph is seeded, not organic.** `FeedSeeder.swift` (1,037 lines) populates the activity feed with synthetic data on first load by writing to the global `activity` Firestore collection. A real user's feed will show them fake workouts from fake athletes. When they discover this — and they will — the trust collapse is terminal. You cannot build a social product on fabricated social proof. The seeder is a development convenience that must be stripped before TestFlight.

**User acquisition has no flywheel.** There is no referral mechanism, no invite flow, no share-to-Instagram card for individual sessions. The PR share card (ImageRenderer) exists in the Gym Tracker but is not wired to a share sheet that creates a branded asset attractive enough for social re-posting. The `activityType` string in `FeedItem` drives the icon but produces no outbound virality.

**The AI coach feature has no revenue attachment.** `AICoachService.swift` reads `CLAUDE_API_KEY` from `Info.plist`. That key is not present in `Info.plist` (the plist was audited and the key is absent). Every user who pays for premium and taps "Generate AI Report" will receive a hardcoded template response without knowing the difference. The Claude API costs money per call and there is no mechanism to pass that cost to users — no per-analysis paywall, no token budget enforcement, no usage tracking. If the key is added and users discover AI reports, the cost structure is completely unbounded.

**The monetization skeleton has no muscle.** StoreKit 2 is wired up with product IDs defined, but there is no App Store Connect product configuration, no paywall screen with conversion optimization, no trial mechanic, and no feature-gating. Anonymous users have full access to every feature including the social layer, making the upgrade path invisible.

**Kudos count is a lie on the Firestore document.** `toggleKudos` in `SocialRepository` writes to the `kudos` sub-collection correctly, but never updates `kudosCount` on the parent activity document using `FieldValue.increment`. The count shown on feed cards is whatever was written when the post was created and never changes on the server. On a fresh load, `fetchFeed` decodes `kudosCount` from the stored document — which is always the seeded initial value. The optimistic UI update in `FeedViewModel.toggleKudos` looks correct locally, but refreshing the feed or opening on a second device shows the wrong count.

### What Needs to Work Before Series A

1. Real users posting real sessions to a real feed — no seeded data
2. Conversion event from anonymous → signed-in → paying (currently impossible without proper paywall)
3. At least 60 days of genuine module engagement data from real athletes
4. The AI coach feature either gated properly behind payment or routed through a backend proxy to prevent key extraction

---

## PERSPECTIVE 2 — TIM COOK / APPLE APP STORE REVIEW

**Grade: 5 / 10**

### What Would Get This Rejected

**Microphone permission without functionality.** `Info.plist` declares `NSMicrophoneUsageDescription` ("Kinetics may use the microphone for future audio coaching features"). Apple Guideline 5.1.1 requires that permission strings describe current use, not future use. The phrase "may use" and "future features" is rejection language. Apple will flag this as misleading permission usage.

**Missing `NSPhotoLibraryUsageDescription`.** The app uses `PhotosPickerItem` (via `PhotosPicker`) to import videos from the photo library. `Info.plist` does not contain `NSPhotoLibraryUsageDescription`. On iOS 17 with the new picker, the system picker no longer requires the key for the new-style limited access picker in some flows — but video export via `PhotosPickerItem.loadTransferable` can trigger the broader photo library access path. This needs to be verified and the string added defensively to avoid a review-time rejection.

**Background location justification is borderline.** `Info.plist` declares `UIBackgroundModes: location` and `NSLocationAlwaysAndWhenInUseUsageDescription`. Apple scrutinises background location extremely carefully in App Review since 2022. The usage description ("Kinetics tracks your route in the background so your full workout is recorded even when the screen is off") is accurate and legitimate for a GPS track app, but the review team will expect the app to prominently surface a "stop tracking" control and to not request always-on location unless the user has started a GPS session. If the permission is requested on app launch rather than at GPS track session start, this is a rejection.

**Face scan and biometric data handling needs explicit disclosure.** Session 10 added `FaceProfile` (SwiftData + `VNGenerateImageFeaturePrintRequest` face ID). The Privacy Manifest exists, but the App Store listing and onboarding must explicitly state that face feature data is stored on-device only, never uploaded, and must present this in the App Privacy section of the App Store Connect listing. If this is not prominently disclosed in the UI and listing, it will fail the review for apps that collect or process facial data (Guideline 5.5).

**No App Privacy details configured.** The app collects: email address (auth), biometric data (face feature print, body composition), health data (HealthKit), location data (GPS), user-generated content (feed posts, comments), and usage data (Firebase Analytics). All of these must be declared accurately in App Store Connect under Privacy. Missing or inaccurate declarations result in rejection.

**Anonymous users can post to a public social feed.** Anonymous Firebase Auth is fully wired to the activity collection. A completely unauthenticated user can post content, comment, and interact with the feed. Apple Guideline 1.2 requires that apps with user-generated content have appropriate moderation, reporting tools, and content removal mechanisms. None of these exist. There is no report/block user button anywhere in the social layer.

**The placeholder `GoogleService-Info.plist` will cause a crash on first launch in review.** The plist contains `PLACEHOLDER-REPLACE-WITH-REAL-PLIST` as the API key. `AppState.configureFirebaseIfReady()` has a guard for this, but if the reviewer gets a build where Firebase fails to initialize, any Firestore call will throw and the app may behave erratically during review. App Review requires a fully functional build.

### What Would Get This Featured

The Vision Framework integration is exactly what Apple promotes in WWDC sessions. If the skeleton overlay, real-time pose analysis, and sport detection actually work reliably in a 1-minute demo video for App Review, this is the kind of technically impressive native iOS story that gets featured in "Apps We Love." The dark, clean aesthetic matches Apple's current design sensibility. The WidgetKit integration, HealthKit reads, and StoreKit 2 use of Apple's own frameworks are all editorial favorability signals.

### HIG Compliance Issues

The `navigationBarHidden(true)` in `ProfileView.swift` line 98 is deprecated in iOS 16+ in favour of `.toolbar(.hidden, for: .navigationBar)`. The current call still works but should be migrated. The `UIScreen.main` usage in `FeedView.swift` (line 492) and `ActiveWorkoutView.swift` is deprecated since iOS 16. Both files were identified in the audit. The `ActiveWorkoutView` usage was supposed to be fixed in Session 8 but `FeedView.swift` still contains it at line 492 inside `GeometryReader`.

---

## PERSPECTIVE 3 — SENIOR iOS ENGINEER CODE REVIEW

**Grade: 6 / 10**

### Architecture Quality

The MVVM structure is generally well-executed. `@Observable` + `@MainActor` is used correctly throughout. The actor isolation is consistent — `AICoachService` is an actor, `CameraManager` is described as an actor in state.md. The `@discardableResult` on `toggleKudos` is appropriate. The use of `guard !isLoading else { return }` debouncing in ViewModels is correct.

The repository pattern is sound. `SocialRepository`, `SessionRepository`, `VideoRepository`, and `GymRepository` all abstract Firestore/SwiftData behind clean boundaries. The `isFirebaseReady` guard pattern is clever for development-mode no-ops.

The JSON round-trip encoding strategy for Firestore (`JSONEncoder → JSONSerialization → [String: Any]`) avoids Firestore conformance requirements on model types, which is intentional and reasonable. It does add one layer of serialization risk.

### Specific Bad Patterns Found

**`fatalError` in `ModelContainer` initialization (KineticsApp.swift, line 88).** If SwiftData fails to create its `ModelContainer` — due to a schema migration conflict after an app update, a corrupt database file, or insufficient disk space — the app crashes with no recovery path. For a user who has been using the app for 60 days with gym data, a failed migration means all local data is silently destroyed and the app crashes until the user deletes and reinstalls. This is the most dangerous pattern in the codebase.

```swift
// Current — instant crash on schema migration failure:
fatalError("Failed to create SwiftData ModelContainer: \(error)")

// Should be — migration strategy with user communication:
do {
    let container = try ModelContainer(for: schema, configurations: config)
    return container
} catch {
    // Attempt migration, or present the user with a recovery option
    // before crashing. At minimum, log to Crashlytics before dying.
}
```

**`UIScreen.main` deprecated usage in `FeedView.swift` (line 492).** The `GeometryReader` inside `feedCards` uses `UIScreen.main.bounds.height` to trigger infinite scroll pagination:

```swift
if frame.maxY < UIScreen.main.bounds.height + 200 {
    Task { await viewModel.loadMore() }
}
```

`UIScreen.main` is deprecated since iOS 16. On multi-window iPads and Stage Manager, this returns incorrect dimensions. The fix is to use the geometry proxy's own coordinate space. This was supposedly fixed in Session 8 for other files but `FeedView.swift` still contains it.

**`DispatchQueue.main.async` inside a SwiftUI `GeometryReader` body (FeedView.swift, line 490-494).** Using `DispatchQueue.main.async` inside `body` to trigger state mutations is a view-layer side effect that can cause infinite re-render loops in specific SwiftUI versions. The correct pattern is `.onPreferenceChange` or a dedicated scroll offset tracking approach. The fact that it spawns a `Task` for `loadMore()` inside a render-time callback is also concerning — `loadMore()` has a debounce guard but the infinite render loop risk is real.

**`FeedCards.swift` uses `DispatchQueue.main.asyncAfter` (lines 558, 589) inside a SwiftUI view body.** These are the old completion-handler patterns that the CLAUDE.md spec explicitly prohibits. The spec states "No completion handlers." These should be `Task { try? await Task.sleep(...) }` patterns.

**`VideoLibraryView.swift` is 1,405 lines** — nearly double the project's stated 800-line maximum. `ActiveGymSessionView.swift` is 1,921 lines and `RoutineBuilderView.swift` is 1,878 lines. These violate the codebase's own stated file size limits and are unmaintainable monoliths.

**Kudos count denormalization is broken.** `SocialRepository.toggleKudos` writes to `activity/{id}/kudos/{uid}` sub-collection correctly, but never calls `FieldValue.increment()` on the parent `activity/{id}` document's `kudosCount` field. The count on the document is frozen at seed time. This means every user except the original poster sees stale kudos counts on every pull-to-refresh. The optimistic update in `FeedViewModel` makes it look correct locally but breaks on refresh.

**No request timeout on `AICoachService`'s `URLSession` call (line 130).** The call uses `URLSession.shared.data(for: request)` with no `timeoutInterval` configured. The default `URLSession` timeout is 60 seconds. If the Anthropic API is slow or unreliable, the UI's "Generating report..." spinner will block for up to 60 seconds with no user-visible progress or cancellation option. `URLRequest` should have `timeoutInterval` set and the `Task` should be cancellable.

**`CLAUDE_API_KEY` is read from `Info.plist` but the key is not in `Info.plist`.** `AICoachService` reads `Bundle.main.object(forInfoDictionaryKey: "CLAUDE_API_KEY")`. The actual `Info.plist` was audited — the key is not present. Every single user who taps "Generate AI Report" receives a silent fallback template, not AI output, with no indication that the feature is unconfigured. The UI should explicitly state "AI Coach not configured" rather than presenting template content as though it were real AI output.

**`FeedSeeder.swift` is 1,037 lines of production code** that seeds fake users, fake posts, fake kudos, and fake comments into the live Firestore database. The only guard is a flag document at `_meta/feed_seeded_v3`. If any real user's Firebase project is connected, this code runs once and pollutes the production database with synthetic data on first app launch. There is no environment guard (e.g., `#if DEBUG`).

### Crash Risks, Memory Leaks, Data Loss Risks

**Crash risk (HIGH):** `fatalError` in `ModelContainer` static initializer. Any SwiftData migration failure = instant crash = data loss.

**Data loss risk (HIGH):** There is no explicit SwiftData migration strategy for any model that has changed between sessions. `VideoSession`, `FaceProfile`, `BodyMeasurement`, and `GymModels` have all been added across sessions 7-10. A user who installed the app after Session 6 and updates to Session 10 may hit a schema mismatch that triggers the `fatalError`.

**Memory risk (MEDIUM):** `FeedView` holds a `listenerRegistration: ListenerRegistration?` which is a Firestore real-time snapshot listener. The listener is set via `listenForNewPosts()` and cleaned up with `listenerRegistration?.remove()` before reassignment — this is correct. However, `FeedViewModel` is a `@State` variable on `FeedView`, meaning it lives as long as the view is in the hierarchy. If the tab is kept alive while the user does long sessions, the listener continues to fire indefinitely. This is by design but should be documented.

**Crash risk (MEDIUM):** `VideoReportViewModel.resolvedVideoURL()` returns `nil` silently if the file does not exist. `VideoReportViewModel.onAppear(modelContext:)` calls `playerController.setup(url:)` only if the URL resolves. If the video file was deleted (e.g., iOS purged the Documents directory under storage pressure), the report view loads with no video and no error message. The user sees a blank player with no explanation.

### Firebase Security Rules

No `firestore.rules` file exists anywhere in the repository. The Firestore database is operating with default rules. For a new Firebase project, the default rules after the initial setup period change to "deny all," which means the app would stop working entirely. Before the initial period expires, the default rules are "allow all" — meaning any authenticated or unauthenticated user can read and write any document in the entire database. There is no server-side enforcement that a user can only delete their own posts, only follow/unfollow from their own account, or only update their own profile. The `deleteActivity` client-side check in `SocialRepository` is the only guard — and it can be bypassed by any client that sends raw Firestore calls.

### Zero Test Coverage

There is no test target in the Xcode project. `grep -c "TestTarget\|XCTestCase\|KineticsTests"` returns 0. 119 Swift files, 50,000+ lines of code, zero automated tests. The `BiomechanicsCalculator`, `AICoachService` prompt builder, `SocialRepository` encode/decode round-trip, and `VideoAnalysisEngine` metric calculation are all completely untested. The project spec mandates 80% coverage — the current coverage is 0%.

---

## OVERALL GRADE: 5.5 / 10

Technically ambitious, architecturally mostly sound, dangerously under-tested, and not ready for App Store submission in its current state. The build succeeds. The vision is strong. The blocking issues are real and fixable within two focused sessions.

---

## PRIORITY BUG LIST (Ordered by Severity)

**Bug 1 — FeedSeeder writes synthetic data to live production Firestore**  
Severity: CRITICAL  
File: `Kinetics/Modules/Social/FeedSeeder.swift` — entire file  
Description: `FeedSeeder.shared.seedIfNeeded()` is called every time `FeedView` appears (line 348 of `FeedView.swift`). It writes ~10 fake user profiles, ~20 fake posts, fake kudos, and fake comments to the live `activity` collection. The only guard is a Firestore flag document. On a production Firebase project, this runs once and permanently contaminates the database. Users will see fake athletes in their feed.  
Fix complexity: Easy — wrap entire `seedIfNeeded()` body in `#if DEBUG` or delete the file entirely before production.

**Bug 2 — No Firestore security rules**  
Severity: CRITICAL  
File: No `firestore.rules` file exists  
Description: The Firestore database has no server-side security rules. Any Firebase-authenticated client (or unauthenticated client during the default rules window) can read and write any document. User profiles, session data, feed posts, and kudos records are all publicly writable by any client.  
Fix complexity: Medium — write and deploy rules scoping reads/writes to `request.auth.uid == resource.data.userId`.

**Bug 3 — `fatalError` on SwiftData schema migration failure**  
Severity: CRITICAL  
File: `Kinetics/App/KineticsApp.swift` line 88  
Description: `fatalError("Failed to create SwiftData ModelContainer: \(error)")` — if any of the 10 SwiftData models (Exercise, WorkoutSession, WorkoutExerciseEntry, WorkoutSet, Routine, PersonalRecord, BodyMeasurement, VideoSession, WeeklyPlan, FaceProfile) has a schema change that SwiftData cannot automatically migrate, the app crashes on launch with no recovery. User loses all local data.  
Fix complexity: Medium — add `migrationPlan` or catch the error, log to Crashlytics, and present a recovery UI.

**Bug 4 — Kudos count never updates in Firestore**  
Severity: HIGH  
File: `Kinetics/Modules/Social/SocialRepository.swift` lines 183-210  
Description: `toggleKudos` writes/deletes sub-collection documents but never calls `FieldValue.increment(1)` or `FieldValue.increment(-1)` on the parent `activity` document's `kudosCount` field. The count is frozen at the value set when the post was created (seeded data shows 3-8). Every user on a second device or after any refresh sees the wrong count.  
Fix complexity: Easy — add `try await ref.updateData(["kudosCount": FieldValue.increment(Int64(wasLiked ? -1 : 1))])` after the kudos document write/delete.

**Bug 5 — `UIScreen.main` deprecated in `FeedView.swift`**  
Severity: HIGH  
File: `Kinetics/Modules/Social/FeedView.swift` line 492  
Description: `if frame.maxY < UIScreen.main.bounds.height + 200` uses the deprecated `UIScreen.main` API inside a `GeometryReader` body, combined with `DispatchQueue.main.async`. This is the pattern Session 8 claimed to fix, but `FeedView.swift` was missed. On multi-window setups (iPad Stage Manager) this returns wrong dimensions, causing infinite scroll to never trigger or to trigger incorrectly.  
Fix complexity: Easy — use `geo.frame(in: .global)` and pass screen size via `GeometryReader` in the parent, or use `.onScrollGeometryChange`.

**Bug 6 — `DispatchQueue.main.asyncAfter` in SwiftUI view body (FeedCards.swift)**  
Severity: HIGH  
File: `Kinetics/Modules/Social/FeedCards.swift` lines 558, 589  
Description: The project spec prohibits completion handlers. These two sites use `DispatchQueue.main.asyncAfter` inside `@MainActor` SwiftUI views, which is the old pattern and creates timing-dependent animation state that can misfire on slow devices. Should be `Task { try? await Task.sleep(for: .seconds(N)) }`.  
Fix complexity: Easy — replace both with structured concurrency `Task` sleep patterns.

**Bug 7 — AI Coach silently delivers templates instead of AI output**  
Severity: HIGH  
File: `Kinetics/Core/Services/AICoachService.swift` line 54; `Kinetics/Info.plist`  
Description: `CLAUDE_API_KEY` is read from `Info.plist` but the key is not present in `Info.plist`. Every call to `generateReport` falls through to `templateReport`. The UI shows the report as if it came from AI. Users paying for premium who tap "Generate AI Report" will receive hardcoded templates with no indication the feature is non-functional. The `missingAPIKey` error case exists but is never thrown because the missing key returns `""` rather than `nil`.  
Fix complexity: Medium — either add the key to Info.plist via an `.xcconfig` file (not checked in), or change the guard to throw `missingAPIKey` when empty, and show a proper "AI Coach not configured" state in the UI.

**Bug 8 — Microphone permission declared for non-existent feature**  
Severity: HIGH  
File: `Kinetics/Info.plist` line 45-46  
Description: `NSMicrophoneUsageDescription` says "may use the microphone for future audio coaching features." Apple will reject this. The string must describe the current use. If the feature doesn't exist, remove the permission.  
Fix complexity: Easy — remove the `NSMicrophoneUsageDescription` key from `Info.plist`.

**Bug 9 — No report/block user controls in social layer**  
Severity: HIGH  
File: `Kinetics/Modules/Social/FeedCards.swift`, `FeedView.swift`, `CommentSheetView.swift`  
Description: Apple Guideline 1.2 requires user-generated content apps to have content reporting and blocking mechanisms. There is no "Report post," "Block user," or "Hide content" action anywhere in the social layer. Anonymous users can post without restriction.  
Fix complexity: Medium — add a context menu item "Report Post" on `ActivityFeedCard` that writes to a `reports` collection in Firestore, and implement `blockUser` that adds the target UID to a local block list checked in `filteredItems`.

**Bug 10 — No `NSPhotoLibraryUsageDescription` despite photo library access**  
Severity: HIGH  
File: `Kinetics/Info.plist`  
Description: `VideoLibraryView` uses `PhotosPicker` with `matching: .videos`. On certain video import flows through `PhotosPickerItem.loadTransferable`, the system may request photo library access. The key is absent from `Info.plist`, which can cause a crash or a confusing system permission dialog with no app-provided rationale string.  
Fix complexity: Easy — add `NSPhotoLibraryUsageDescription` to `Info.plist`.

**Bug 11 — SwiftData schema migration has no strategy for 3 sessions of model evolution**  
Severity: HIGH  
File: `Kinetics/App/KineticsApp.swift` lines 71-90  
Description: `VideoSession`, `FaceProfile`, `WeeklyPlan`, and `BodyMeasurement` were all added after the initial schema. Users who installed the app in Sessions 1-6 and update will hit SwiftData schema mismatches. Without a `VersionedSchema` and `MigrationPlan`, SwiftData either silently drops existing stores or crashes. Combined with Bug 3 (`fatalError`), this is a guaranteed data-loss event for any early adopter who updates.  
Fix complexity: Hard — requires defining `VersionedSchema` for each major schema revision and writing lightweight migration paths.

**Bug 12 — `URLSession` has no timeout on Claude API calls**  
Severity: MEDIUM  
File: `Kinetics/Core/Services/AICoachService.swift` line 130  
Description: `URLSession.shared.data(for: request)` uses the default 60-second timeout with no `URLRequest.timeoutInterval` set. If the Anthropic API is slow, the "Generating report..." spinner blocks for up to 60 seconds. The `Task` is not cancellable from the UI. Users have no way to abort the request.  
Fix complexity: Easy — set `request.timeoutInterval = 20` and expose a `Task` handle that can be cancelled from a "Cancel" button in `VideoAnalysisReportView`.

**Bug 13 — `VideoLibraryView.swift` is 1,405 lines (75% over limit)**  
Severity: MEDIUM  
File: `Kinetics/Modules/VideoAnalysis/VideoLibraryView.swift`  
Description: The file contains `VideoLibraryViewModel`, `VideoLibraryView`, `VideoFilterChip`, `VideoThumbnailCard`, `AnalyzingRing`, `VideoDetailView`, `VideoMetricRow`, `VideoProgressView`, and `VideoSport` display extensions — 9 distinct types in one file. The project spec caps files at 800 lines. `ActiveGymSessionView.swift` (1,921 lines) and `RoutineBuilderView.swift` (1,878 lines) also violate this.  
Fix complexity: Medium — extract `VideoDetailView`, `VideoProgressView`, and `VideoMetricRow` into separate files.

**Bug 14 — `commentCount` on activity documents is never updated**  
Severity: MEDIUM  
File: `Kinetics/Modules/Social/SocialRepository.swift` lines 233-247  
Description: `postComment` writes to `activity/{id}/comments/{commentId}` but never increments `commentCount` on the parent document. Feed cards always show the seeded comment count (0 for real user posts). Same root cause as Bug 4 — `FieldValue.increment` not used.  
Fix complexity: Easy — same fix as Bug 4, using `FieldValue.increment(Int64(1))` on `commentCount` after writing the comment.

**Bug 15 — `FeedSeeder.swift` uses `try?` on critical seeding operations**  
Severity: MEDIUM  
File: `Kinetics/Modules/Social/FeedSeeder.swift` lines 27-35  
Description: The seed guard check and the seed flag write both use `try?`, silently discarding errors. If the flag write fails (e.g., no network), the seeder will run again on every subsequent app launch until it succeeds, potentially creating duplicate seed data in the database.  
Fix complexity: Easy — use proper `do/catch` with a local `UserDefaults` flag as a fallback so the seeder does not retry on every cold launch.

**Bug 16 — Zero test coverage across 119 Swift files**  
Severity: MEDIUM  
File: Entire project — no test target exists  
Description: The project spec mandates 80% coverage. Current coverage: 0%. No unit tests for `BiomechanicsCalculator` math, no tests for `SocialRepository` encode/decode round-trip, no tests for `AICoachService` prompt construction or fallback logic, no tests for `FeedViewModel` pagination logic.  
Fix complexity: Hard — requires creating a test target and writing tests. The architecture (protocols, `@Observable` ViewModels, actor-isolated services) is actually testable, but no work has been done.

**Bug 17 — `FaceProfile` biometric data handling has no explicit user consent UI**  
Severity: MEDIUM  
File: `Kinetics/Modules/VideoAnalysis/FaceSetup/FaceSetupView.swift` (referenced in ProfileView)  
Description: `FaceProfile` stores a `VNGenerateImageFeaturePrintRequest` feature print derived from the user's face. This is biometric data under CCPA and EU data protection law. The onboarding flow for face setup must present an explicit consent screen explaining what data is stored, where it is stored (on-device only vs. Firestore), and how to delete it. The current ProfileView shows a "Face Scan Setup" button with no prior consent UI.  
Fix complexity: Medium — add a consent modal before the face scan that explicitly describes the data collected and stored.

**Bug 18 — `navigationBarHidden(true)` deprecated API in ProfileView**  
Severity: LOW  
File: `Kinetics/Shared/ProfileView.swift` line 98  
Description: `.navigationBarHidden(true)` is deprecated in iOS 16 in favour of `.toolbar(.hidden, for: .navigationBar)`. Will generate Xcode deprecation warnings in production builds.  
Fix complexity: Easy — replace with `.toolbar(.hidden, for: .navigationBar)`.

**Bug 19 — `DateFormatter` instantiated on every render in `VideoThumbnailCard`**  
Severity: LOW  
File: `Kinetics/Modules/VideoAnalysis/VideoLibraryView.swift` lines 487-491  
Description: `var dateText: String { let f = DateFormatter(); ... }` creates a new `DateFormatter` on every call to `dateText`. `DateFormatter` initialization is expensive. In a `LazyVGrid` with many thumbnails, this creates measurable scroll jank.  
Fix complexity: Easy — use a `static let` shared formatter or `formatted(date:time:)`.

**Bug 20 — Missing `caption` field in `ComposePostSheet` — posts lose the workout type context**  
Severity: LOW  
File: `Kinetics/Modules/Social/FeedView.swift` lines 950-960  
Description: When a user composes a post from `ComposePostSheet`, the `FeedItem` is constructed with `itemType: .workout`, `activityType: "general"`, and `workoutId: ""` regardless of what the user typed. The activity suggestion chips prepend text to the `caption` field but do not set `activityType`. Feed cards for these posts will always show the generic bolt icon and `"general"` color, even if the user typed "Striking Session." The `activityType` should be inferred from the caption or let the user select it explicitly.  
Fix complexity: Easy — add a sport picker to the compose sheet that sets `activityType` on the constructed `FeedItem`.

---

## FEATURE GAPS FOR APP STORE SUBMISSION

1. **Firestore security rules** — must be deployed before any public-facing build. The database is currently wide open.
2. **Real `GoogleService-Info.plist`** — the placeholder sentinel is detected and Firebase is skipped. The entire app runs in an offline-only degraded mode for any build with the placeholder plist.
3. **Microphone permission removal** — the key must be removed or the feature must be real before submission.
4. **`NSPhotoLibraryUsageDescription`** — required for the video import flow.
5. **Content moderation controls** — report/block must exist before Apple will approve a social UGC app.
6. **App Store Connect product configuration** — the two StoreKit 2 product IDs (`com.rayancheca.kinetics.premium.monthly`, `com.rayancheca.kinetics.premium.annual`) must be created and approved in App Store Connect before the app can be submitted. StoreKit 2 will throw errors in production if the products don't exist.
7. **App Privacy declarations** — all data types collected (biometric, health, location, contact info, user content, usage data) must be accurately declared in the App Store Connect Privacy section.
8. **Real app icon (1024×1024)** — the `AppIcon.appiconset` contains a placeholder. App Store Connect will reject a submission with a missing or placeholder icon.
9. **FaceProfile explicit consent screen** — biometric data collection requires prior informed consent presented in the UI before the data is collected.
10. **FeedSeeder removal or `#if DEBUG` guard** — synthetic data must not write to a production database.
11. **SwiftData migration plan** — required before any update to users who installed earlier sessions.
12. **Privacy manifest accuracy review** — the `PrivacyInfo.xcprivacy` exists but its contents were not audited for completeness against the full list of APIs used (HealthKit, CoreLocation, Vision, AVFoundation, Firebase, UserNotifications all have required reason codes).
13. **Paywall screen** — App Review requires that subscription offers be clearly presented before any purchase. The StoreKit skeleton has no purchase UI.

---

## WHAT IS GENUINELY IMPRESSIVE

**The Vision Framework integration is architecturally correct.** Using `VNDetectHumanBodyPoseRequest` as a shared engine across all four sport modules, with each module's analytics layer doing sport-specific math on the same joint coordinates, is the right design. This is how Apple intends the framework to be used.

**Swift 6 strict concurrency is actually enforced.** The codebase uses `@Observable`, `@MainActor`, `actor`, `async/await`, and `Sendable` throughout. There are zero force unwraps in production code paths (as confirmed by the grep). The `[weak self]` captures are consistent. This is production-quality concurrency hygiene that most AI-generated codebases completely butcher.

**The `isFirebaseReady` sentinel pattern is clever.** Rather than crashing during development when no real Firebase project exists, every repository method guards on `FirebaseApp.app() != nil` and returns empty/no-op. This allows the entire app to run and be developed without a live backend — something most Firebase apps get completely wrong.

**The social layer's optimistic UI for kudos is correctly implemented.** Snapshot-before-update, apply optimistically, roll back on error, with the immutable `updatedItem` helper building new `FeedItem` structs rather than mutating in place. This is the correct pattern from the coding style rules.

**The AI fallback templates are substantive.** The sport-specific fallback reports in `AICoachService` are genuinely well-written coaching content — not lorem ipsum. They cite specific biomechanical concepts (kuzushi timing, butt wink at L4-L5, bar path forward drift, hip-to-wall proximity). When the API key is absent, users still get actionable content. This is thoughtful product design even if the presentation to the user is misleading.

**Session continuity and state management are exemplary.** The `state.md` file is maintained with surgical precision across 10 sessions. The commit history is clean with conventional commit messages. The `CLAUDE.md` spec is comprehensive and has been respected throughout development. This is the kind of documentation discipline that makes a codebase maintainable by someone other than its author.

**The `SocialRepository` encode/decode strategy handles the Firestore nested-array limitation correctly.** The `routeCoordinates: [[Double]]` workaround (serialise to JSON string, store as a string field, deserialise on read) is the right solution for Firestore's limitation on nested arrays. The code is commented and the intent is clear.

---

## Review Summary

| Severity | Count | Status |
|----------|-------|--------|
| CRITICAL | 3     | BLOCK  |
| HIGH     | 9     | WARN   |
| MEDIUM   | 5     | INFO   |
| LOW      | 3     | NOTE   |

**Verdict: BLOCKED — 3 CRITICAL issues must be resolved before any public distribution.**

The three blocking issues are: (1) FeedSeeder contaminating a real production database with synthetic data, (2) zero Firestore security rules leaving all data publicly writable, and (3) the `fatalError` on `ModelContainer` failure which will destroy user data on any schema change. Resolve these three and the remaining HIGH issues, and this app is a credible TestFlight candidate.
