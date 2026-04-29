# Kinetics — Session State

**Last updated:** Session 6 (2026-04-29) — Section 12 App Store prep built, compiled, committed, pushed
**Current phase:** Phase 1 — MVP
**Overall progress:** Session 6 in progress. BUILD SUCCEEDED.

---

## Status: SESSION 6 — Section 12 COMPLETE

`** BUILD SUCCEEDED **` on iPhone 17 Pro Simulator.
All changes committed and pushed. Latest commit: `bb503d4` (Section 12 App Store prep).

---

## Session 5 — What Was Built

### Gym Tracker Part B — Section 16 (COMPLETE ✅)

**Files created in previous context (committed `45ec378`):**
- `Kinetics/Modules/GymTracker/RoutineBuilderView.swift` — RoutineListView (@Query), RoutineBuilderView (drag reorder, exercise picker), ExercisePickerSheet
- `Kinetics/Modules/GymTracker/PersonalRecordsView.swift` — PersonalRecordsView (@Query, searchable), BodyMeasurementView (stat cards + history + swipe-delete), AddMeasurementSheet, MeasurementStatCard
- `Kinetics/Modules/GymTracker/GymProgressView.swift` — GymProgressView (segmented Picker + TabView.page): Overview tab with VolumeChartView (BarMark), Strength tab with StrengthChartView (LineMark + PointMark), Body tab with BodyWeightChartView (AreaMark)
- `Kinetics/Modules/GymTracker/GymHomeView.swift` — updated with navigationDestination routing to Part B views

**Key fix:** MeasurementStatCard renamed from StatCard to avoid redeclaration with ProfileView.swift's StatCard.

---

### Entitlements Hook Issue (KNOWN — workaround needed for device builds)

The project has a post-tool-use hook that strips entitlements files back to `<dict/>` whenever `xcodegen generate` runs. This means:
- `Kinetics/Kinetics.entitlements` — HealthKit keys and AppGroup get stripped each run
- `KineticsWidget/KineticsWidget.entitlements` — AppGroup gets stripped each run

**Impact:** Simulator builds unaffected. Device builds need manual re-addition in Xcode Signing & Capabilities tab:
- Main app: HealthKit capability + App Groups (`group.com.rayancheca.kinetics`)
- Widget extension: App Groups (`group.com.rayancheca.kinetics`)

---

### Section 9 — HealthKit Dashboard Reads (COMPLETE ✅)

**Commit:** `e9a5fe8`

**Modified files:**
- `Kinetics/Core/Services/HealthKitService.swift` — Added:
  - `HealthKitDashboardStats` struct (Sendable): `restingHeartRate`, `hrv`, `vo2Max`, `activeCalories`, `steps`, `sleepSeconds` + `.empty` static
  - `fetchDashboardStats() async -> HealthKitDashboardStats` — sequential awaits (not async let — NSPredicate is not Sendable)
  - `todayPredicate()` — returns today's `HKQuery.predicateForSamples`
  - `fetchLatestQuantitySample(type:unit:predicate:)` — HKSampleQuery wrapped in withCheckedContinuation
  - `fetchCumulativeSum(type:unit:predicate:)` — HKStatisticsQuery with .cumulativeSum
  - `fetchSleepDuration()` — sums asleepUnspecified/Core/Deep/REM samples from last 24h
  - Expanded `requestAuthorization` read types: restingHeartRate, HRV SDNN, sleepAnalysis

- `Kinetics/Home/HomeViewModel.swift` — Added `dashboardStats: HealthKitDashboardStats = .empty`, `loadDashboardStats()` method
- `Kinetics/Home/HomeView.swift` — Added `healthStatsCard` + `StatPill` with 6 metrics: Steps(blue)/Calories(amber)/Sleep(purple)/RHR(green)/HRV(blue)/VO2(green)

**Key fix:** `async let` cannot be used with `NSPredicate` (not Sendable) across actor isolation. Changed `fetchDashboardStats` to sequential `await` calls instead.

---

### Section 10 — Notifications (COMPLETE ✅)

**Commit:** `e9a5fe8`

**New files:**
- `Kinetics/Core/Services/NotificationService.swift` — `@MainActor final class NotificationService { static let shared }`:
  - `requestAuthorization() async -> Bool` — UNUserNotificationCenter.requestAuthorization wrapped in withCheckedContinuation
  - `scheduleWorkoutReminder(title:body:weekdays:hour:minute:identifier:) async` — per-weekday UNCalendarNotificationTrigger (repeating)
  - `scheduleAchievementNotification(title:body:) async` — 5s UNTimeIntervalNotificationTrigger one-shot
  - `cancelWorkoutReminders(identifier:) async` — removes pending requests with weekday suffix
  - `pendingCount() async -> Int`

- `Kinetics/Modules/Settings/NotificationSettingsView.swift` — Full settings UI:
  - Workout Reminders toggle (@AppStorage) → day picker (M-T-W-T-F-S-S circular buttons) + DatePicker + Apply button
  - Achievement Alerts toggle (@AppStorage)
  - Test Notification button (fires 5s notification)

**Modified files:**
- `Kinetics/Shared/ProfileView.swift` — NavigationLink to NotificationSettingsView added
- `project.yml` — NSUserNotificationUsageDescription added to Info.plist

---

### Section 11 — WidgetKit Extension (COMPLETE ✅)

**Commit:** `b076237`

**New files:**
- `KineticsWidget/KineticsWidget.swift` — full widget implementation:
  - `KineticsEntry` — TimelineEntry with steps/calories/workoutMinutes/nextWorkout/streakDays
  - `KineticsProvider` — 30-minute refresh, reads from AppGroup UserDefaults
  - `TodayStatsWidget` — `.systemSmall` + `.systemMedium`, shows steps/calories/workout minutes
  - `NextWorkoutWidget` — `.systemSmall`, shows next scheduled workout string
  - `KineticsWidgetBundle` — @main WidgetBundle
  - `TodayStatsView`, `NextWorkoutView`, `StatRow` — widget UI components
- `KineticsWidget/KineticsWidget.entitlements` — AppGroup (hook strips to `<dict/>` — needs manual fix for device)
- `Kinetics/Core/Services/WidgetDataStore.swift` — `@MainActor final class WidgetDataStore { static let shared }`:
  - `updateTodayStats(steps:calories:workoutMinutes:)` — writes to AppGroup + reloads TodayStats timeline
  - `updateNextWorkout(_:)` — writes next workout string + reloads NextWorkout timeline
  - `updateStreak(_:)` — writes streak days + reloads all timelines

**Modified files:**
- `Kinetics/Home/HomeViewModel.swift` — calls `WidgetDataStore.shared.updateTodayStats()` after `fetchDashboardStats()`
- `project.yml` — `KineticsWidget` target added (type: app-extension) + embedded in Kinetics dependencies

---

## Architecture Decisions (Session 5)

- `NSPredicate` is not `Sendable` in Swift 6 — cannot use `async let` when passing predicates across actor boundaries. Solution: compute predicate once, then await sequentially
- WidgetKit `@main` must be in a separate target — cannot be in the same module as the main app
- AppGroup UserDefaults (`group.com.rayancheca.kinetics`) is the data bridge between main app and widget
- `WidgetCenter.shared.reloadTimelines(ofKind:)` must be called after writing data to AppGroup so widgets refresh immediately
- `NotificationService` is `@MainActor` (not actor) because UNUserNotificationCenter callbacks are main-thread-friendly and we need @AppStorage access

---

## Session 6 — What Was Built

### Section 12 — App Store Prep (COMPLETE ✅)

**Commit:** `bb503d4`

**New files:**
- `Kinetics/Resources/PrivacyInfo.xcprivacy` — Apple-required privacy manifest: `NSPrivacyTracking = false`, no tracking domains, declares Health + Location data (app functionality, not linked, not tracking), UserDefaults access reason CA92.1, FileTimestamp access reason C617.1
- `Kinetics/Resources/Assets.xcassets/LaunchBackground.colorset/Contents.json` — universal sRGB color `#0D0D0D` (matches app dark background)
- `Kinetics/Resources/Assets.xcassets/LaunchLogo.imageset/Contents.json` — 1x/2x/3x placeholder (no image files; drop real logo PNG here when available)

**Modified files:**
- `project.yml` — `UILaunchScreen` updated from `{}` to `UIColorName: LaunchBackground` + `UIImageName: LaunchLogo`; `PrivacyInfo.xcprivacy` added to Kinetics target resources
- `AppIcon.appiconset/Contents.json` — already had correct universal 1024x1024 config, no changes needed

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
- Section 8: Gym Tracker Part A (GymModels SwiftData, GymRepository, GymHomeView, ActiveGymSessionView)

### Session 5
- Section 16: Gym Tracker Part B (RoutineBuilderView, PersonalRecordsView, BodyMeasurementView, GymProgressView with Swift Charts)
- Section 9: HealthKit dashboard depth reads (RHR, HRV, VO2 max, active calories, steps, sleep)
- Section 10: Notifications (NotificationService, NotificationSettingsView, ProfileView integration)
- Section 11: WidgetKit extension (TodayStatsWidget, NextWorkoutWidget, WidgetDataStore)

---

## Next Steps — Session 6 (remaining)

Priority order:
1. **Section 13 — Onboarding polish**: HealthKit permission request on first launch, notification permission on onboarding completion
2. **Fix entitlements hook**: The post-tool-use hook strips entitlements. Options:
   - Disable the XML formatter hook for `.entitlements` files
   - Manually re-add capabilities in Xcode GUI (HealthKit + App Groups)
3. **Firebase Analytics depth**: Add `module_session_started`, `module_session_completed` events to all 4 sport modules
4. **Deep link support**: Universal links and widget tap → navigate to relevant screen
5. **Drop real app icon**: Add 1024x1024 PNG to `AppIcon.appiconset/` and 1x/2x/3x PNGs to `LaunchLogo.imageset/`

---

## To Run the App

1. Open `Kinetics.xcodeproj` in Xcode
2. Select your iPhone as target device
3. Signing & Capabilities → Team → select your Apple ID
4. For device builds: manually add HealthKit + App Groups capabilities (hook strips entitlements)
5. Build & Run (⌘R)
6. Trust developer certificate in Settings → General → VPN & Device Management

If new Swift files are added and Xcode can't find them: run `xcodegen generate` in the project root.

## File Count Summary

**Total Swift files:** ~75+
**New in Session 5:** 7 files (RoutineBuilderView, PersonalRecordsView, GymProgressView, NotificationService, NotificationSettingsView, WidgetDataStore, KineticsWidget)
