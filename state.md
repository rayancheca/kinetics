# Kinetics — Session State

**Last updated:** Session 4 (2026-04-29) — Sections 15, 6, 7, 8 built, compiled, committed, pushed
**Current phase:** Phase 1 — MVP
**Overall progress:** Session 4 in progress. BUILD SUCCEEDED.

---

## Status: SESSION 4 IN PROGRESS — BUILD SUCCEEDED

`** BUILD SUCCEEDED **` on iPhone 17 Pro Simulator.
All changes committed. Latest commit: `97cbac6` (Gym Tracker).

---

## Session 4 — What Was Built

### Section 15 — Front Camera Toggle (COMPLETE ✅)

**Modified files:**
- `CameraManager.swift` — Added `cameraPosition: AVCaptureDevice.Position`, `switchCamera() async` (full session teardown/rebuild), mirror baked into preview layer connection
- `PoseDetectionEngine.swift` — `process(_:isFrontCamera:)` — calls `pose.mirroredHorizontally()` when front camera active
- `JointPose.swift` — `mirroredHorizontally()` maps `x → 1.0 - x` for all joints
- All 4 module ViewModels — `activeCameraManager` weak ref, `isFront` passed to `process()`
- All 4 module Views — `@AppStorage("camera_position_{module}")`, `cameraFlipButton` ZStack layer, calls `switchCamera()` on tap

**Key decisions:**
- Full teardown/rebuild chosen over input swap because `configureSessionIfNeeded()` is guarded by `isConfigured` flag — reset it and call again with new position
- Mirroring lives in `CameraManager.configureSessionIfNeeded()` on the preview layer connection — `CameraPreviewView` gets the new layer pre-mirrored, no changes there
- Grappling defaults to front camera (`@AppStorage("camera_position_grappling") = true`) for solo drilling

**Commit:** `6bb2261`

---

### Section 6 — GPS Track Module (COMPLETE ✅)

**New files:**
- `Kinetics/Core/Services/LocationService.swift` — `actor LocationService: NSObject, CLLocationManagerDelegate`. Filters GPS fixes (accuracy thresholds, age). `AsyncStream<CLLocation>` rebuilt each `startTracking()`. Elevation accumulated with ±0.5m noise threshold.
- `Kinetics/Core/Services/HealthKitService.swift` — `actor HealthKitService { static let shared }`. `HKAnchoredObjectQuery` → `AsyncStream<Double>` for live HR. `saveWorkout()` with energy + distance samples. `withCheckedThrowingContinuation` for `store.add(_:to:completion:)` (no async overload).
- `Kinetics/Core/Models/WorkoutResult.swift` — `WorkoutActivityType` (run/walk/ride/hike/swim/ski), `WorkoutSplit`, `HRZones`, `WorkoutResult` (all `Codable, Identifiable, Sendable, Hashable`).
- `Kinetics/Modules/Track/TrackAnalytics.swift` — Pure functions: `buildSplits`, `computeHRZones`, `segmentPaces`, `detectAchievements`, `formatPace`.
- `Kinetics/Modules/Track/TrackViewModel.swift` — `@Observable @MainActor`. Three child tasks: duration timer, location consumer, HR consumer. Auto-pause (3 consecutive <0.5 m/s samples). Running HR mean O(1). MET-based calorie estimate.
- `Kinetics/Modules/Track/WorkoutRepository.swift` — `@MainActor final class`. Firestore path `users/{uid}/workouts/{id}`. JSON round-trip. `fetchAll` limit 50 ordered by startedAt desc.
- `Kinetics/Modules/Track/TrackView.swift` — Activity picker + gradient START button + today stats.
- `Kinetics/Modules/Track/ActiveWorkoutView.swift` — Full-screen live recording with RouteMapView.
- `Kinetics/Modules/Track/RouteMapView.swift` — `MKMapView` UIViewRepresentable with live polyline + `routeSummary()` factory.
- `Kinetics/Modules/Track/WorkoutSummaryView.swift` — Post-workout report with HRZoneBar, SplitsTable, achievements.
- `Kinetics/Modules/Track/WorkoutHistoryView.swift` — Grouped list ("This Week"/"Last Week"/"Older") with filter pills, swipe-to-delete. `WorkoutHistoryViewModel` co-located.
- `Kinetics/Modules/Track/WorkoutDetailView.swift` — Swift Charts pace BarMark + full metrics.

**project.yml additions:** NSLocationWhenInUseUsageDescription, NSLocationAlwaysAndWhenInUseUsageDescription, NSHealthShareUsageDescription, NSHealthUpdateUsageDescription, UIBackgroundModes: [location].

**Entitlements note:** `Kinetics.entitlements` had HealthKit keys stripped by a post-tool-use hook reformatter. Needs re-adding for device builds (`com.apple.developer.healthkit: true`, `com.apple.developer.healthkit.background-delivery: true`). Simulator builds unaffected.

**Commit:** `000ca72`

---

### Section 14 — Color Token Additions (COMPLETE ✅)

Added to `Color+Kinetics.swift`:
- `kineticsAmber` (#FFB800) — achievements, PRs
- `kineticsPurple` (#8B5CF6) — social/feed
- `kineticsSurface` (#141414) — elevated card backgrounds
- `kineticsSubtext` (#8E8E93) — muted secondary text

**Commit:** `4923693` (part of social commit)

---

### Section 7 — Social Layer (COMPLETE ✅)

**New files:**
- `Kinetics/Modules/Social/SocialModels.swift` — `UserProfile`, `FeedItemType`, `FeedMetric`, `FeedItem` (CodingKeys exclude `isLikedByCurrentUser`), `ActivityComment`. All Codable/Sendable/Hashable with preview factories.
- `Kinetics/Modules/Social/SocialRepository.swift` — `@MainActor final class`. Firestore paths: `users/{uid}`, `activity/{id}`, `activity/{id}/kudos/{uid}`, `activity/{id}/comments/{id}`. JSON round-trip. `postActivity` writes top-level `postedAt` timestamp so Firestore can order by it. `toggleKudos` checks existence of kudos sub-doc.
- `Kinetics/Modules/Social/FeedView.swift` — `FeedViewModel` (`@Observable @MainActor`) + `FeedView` (NavigationStack, refreshable LazyVStack, empty state) + `ActivityFeedCard` (avatar, metrics strip, kudos/comment action row) + `FeedMetricCell`.
- `Kinetics/Modules/Social/UserProfileView.swift` — `UserProfileViewModel` + `UserProfileView` (profile header, stats row, recent activity) + `ProfileHeaderView` (inline bio editor with `Bindable(viewModel)`) + `ProfileStatRow` + `KudosButton` (spring animation) + `CommentSectionView` (optimistic append) + `CommentRow`.

**MainTabView:** Feed tab added at tag 4.

**Key decisions:**
- `FeedItem.isLikedByCurrentUser` excluded from CodingKeys — resolved client-side after fetch
- `Bindable(viewModel)` used for binding extraction from `@State private var viewModel` (not `$viewModel.property` which doesn't compile with `@Observable` + `@State`)
- Duplicate `SocialRepository` generated by an agent in `UserProfileView.swift` was removed — kept only the one in `SocialRepository.swift`
- `fetchFeed(limit:)` signature — no `for:` parameter

**Commit:** `4923693`

---

### Section 8 — Gym Tracker (COMPLETE ✅)

**New files:**
- `Kinetics/Modules/GymTracker/GymModels.swift` — 6 SwiftData `@Model` classes: `Exercise`, `WorkoutSession`, `WorkoutExerciseEntry`, `WorkoutSet`, `Routine`, `PersonalRecord`, `BodyMeasurement`. Plus `GymMuscleGroup` and `GymEquipment` enums.
- `Kinetics/Modules/GymTracker/GymRepository.swift` — `@MainActor final class`. `modelContainer: ModelContainer?` set by App layer. Exercise CRUD (in-memory filter — no `lowercased()` inside `#Predicate`), WorkoutSession CRUD, Set Management, Personal Records (only updates when new weight > stored), 20-exercise seed library, Firestore sync fire-and-forget.
- `Kinetics/Modules/GymTracker/GymHomeView.swift` — `GymHomeViewModel` + `GymHomeView` (Quick Start cards, Recent Sessions, Top Lifts PRs) + `ExerciseLibraryView` (searchable, category filter pills) + `ExerciseRow`.
- `Kinetics/Modules/GymTracker/ActiveGymSessionView.swift` — `ActiveGymSessionViewModel` (timer task, add exercise/set, mark completed) + `ActiveGymSessionView` (header + exercise list + bottom toolbar) + `ExercisePickerView` + `SetRowView` (local state for weight/reps, swipe to delete).

**KineticsApp.swift:** SwiftData `ModelContainer` created at app startup for all 7 model types. `GymRepository.shared.modelContainer` set in `.onAppear`. `.modelContainer()` modifier applied to root view.

**MainTabView:** Gym tab at tag 3 (between Track and Feed). Removed History tab (merged into individual module history screens).

**Key fix:** `fetchSessions` and `fetchPersonalRecords` are synchronous — removed `async let` from `GymHomeViewModel.load()` which was causing Swift 6 Sendable errors for non-Sendable SwiftData model arrays.

**Commit:** `97cbac6`

---

## Architecture Decisions (Session 4)

- `xcodegen generate` needed after every new file added — project.yml glob covers `Kinetics/Modules/**` so all new files in subdirs are auto-picked up
- SwiftData `@Model` classes are not `Sendable` — cannot use `async let` or cross actor boundaries with them
- SwiftData in-memory filter chosen over complex `#Predicate` chains for small datasets (exercise library ~20-300 items)
- `Bindable(viewModel)` is the correct pattern for getting `Binding<T>` from `@State private var viewModel: SomeObservableClass`
- Firebase `SocialRepository` and `WorkoutRepository` both use JSON round-trip (JSONEncoder → Data → JSONSerialization → [String: Any]) — keeps models free of Firestore conformances

---

## What Was Completed Across All Sessions

### Session 1
- Full app scaffold: 4 modules, Firebase, CameraManager, PoseDetectionEngine, TrajectoryTracker

### Session 2
- Firebase plist bundling, camera black screen fix, 5 Swift 6 concurrency errors

### Session 3
- CoachingEngine AI layer, onboarding views (all 4), post-session reports (all 4), tab navigation, settings/profile/history screens

### Session 4
- Section 15: Front camera toggle (all 4 modules + CameraManager + PoseDetectionEngine + JointPose)
- Section 6: GPS Track module (LocationService, HealthKitService, TrackViewModel, WorkoutResult, TrackAnalytics, WorkoutRepository, 6 Track UI files)
- Section 14: Color token additions (amber, purple, surface, subtext)
- Section 7: Social layer (SocialModels, SocialRepository, FeedView, UserProfileView)
- Section 8: Gym Tracker (GymModels SwiftData, GymRepository, GymHomeView, ActiveGymSessionView)

---

## Next Steps — Session 5

Priority order (from NEXT_SESSION.md):
1. **Section 16 — Gym Tracker Part B**: RoutineBuilderView, PersonalRecordView, BodyMeasurementView, GymProgressView (charts), WorkoutTemplates
2. **Section 9 — HealthKit integration depth**: Sync workout stats back from HealthKit, sleep, HRV, VO2 max reads for HomeView dashboard
3. **Section 10 — Notifications**: UNUserNotificationCenter, workout reminders, achievement notifications, streak alerts
4. **Section 11 — Widget extension**: WidgetKit target, today's stats widget, next workout widget
5. **Fix Kinetics.entitlements**: Re-add `com.apple.developer.healthkit: true` and `com.apple.developer.healthkit.background-delivery: true` (stripped by hook)

### Session 5 start prompt:
```
Read state.md first. Session 4 complete — front camera toggle, GPS Track module, social layer, Gym Tracker Part A all built and committed.

Session 5 priorities:
1. Section 16 — Gym Tracker Part B: RoutineBuilderView, PersonalRecordView, GymProgressView with Swift Charts, WorkoutTemplates. Spawn parallel agents.
2. Fix Kinetics.entitlements HealthKit keys.
3. Section 9 — HealthKit depth reads for HomeView dashboard.

Always spawn maximum parallel agents. Commit after every feature. Never delete files.
```

---

## To Run the App

1. Open `Kinetics.xcodeproj` in Xcode
2. Select your iPhone as target device
3. Signing & Capabilities → Team → select your Apple ID
4. Build & Run (⌘R)
5. Trust developer certificate in Settings → General → VPN & Device Management

If new Swift files are added and Xcode can't find them: run `xcodegen generate` in the project root.

## File Count Summary

**Total Swift files:** ~60+
**New in Session 4:** 18 files (front camera mods + Track module + Social module + Gym Tracker)
