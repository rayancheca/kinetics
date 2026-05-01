# Kinetics — Session State

**Last updated:** Session 8 (2026-05-01) — GPS Track audit, HistoryView, crash hardening
**Current phase:** Phase 1+ — Post-MVP improvements ✅ DONE
**Overall progress:** All Phase 1 deliverables + Session 7–8 enhancements built, committed, pushed. BUILD SUCCEEDED.

---

## Status: PHASE 1+ ENHANCEMENTS COMPLETE — BUILD SUCCEEDED

`** BUILD SUCCEEDED **` on iPhone 17 Pro Simulator.
Latest commit: `9673e35`
Total Swift files: 80 (main app) + 1 (widget extension)

---

## Phase 1 Deliverables — Final Status

| Deliverable | Status | Commit |
|---|---|---|
| Xcode project scaffolded | ✅ | Session 1 |
| CameraManager (AVFoundation) | ✅ | Session 1 |
| PoseDetectionEngine (Vision 30fps) | ✅ | Session 1 |
| TrajectoryTracker | ✅ | Session 1 |
| BiomechanicsCalculator | ✅ | Session 1 |
| PoseOverlayView (19-joint skeleton) | ✅ | Session 1 |
| All 4 module Views + ViewModels | ✅ | Session 1-3 |
| CoachingEngine AI layer | ✅ | Session 3 |
| Tab-based home + module cards | ✅ | Session 3 |
| Post-session reports (all 4) | ✅ | Session 3 |
| Onboarding views (all 4) | ✅ | Session 3 |
| Front camera toggle (all 4) | ✅ | `6bb2261` |
| GPS Track module (full) | ✅ | `000ca72` |
| Social layer (Feed + Profile) | ✅ | `4923693` |
| Gym Tracker Part A | ✅ | `97cbac6` |
| Gym Tracker Part B (Routines, PRs, Charts) | ✅ | `45ec378` |
| Session history (Firestore) | ✅ | Session 1 |
| Firebase Auth (anonymous + Apple + email) | ✅ | `d7c025d` |
| Firebase Analytics per module | ✅ | `6924cb6` |
| HealthKit dashboard reads | ✅ | `e9a5fe8` |
| Notifications (reminders + achievements) | ✅ | `e9a5fe8` |
| WidgetKit extension (2 widgets) | ✅ | `b076237` |
| Privacy manifest | ✅ | `bb503d4` |
| Launch screen config | ✅ | `bb503d4` |
| Permissions gate (first launch) | ✅ | `6924cb6` |
| Streak tracking + widget data | ✅ | `50311d4` |
| Deep links (kinetics:// scheme) | ✅ | `50311d4` |
| Tab screen-time analytics | ✅ | `d7c025d` |
| Session → social feed auto-post | ✅ | `809c9f6` |
| StoreKit 2 subscription skeleton | ✅ | `809c9f6` |
| **Session 7 Enhancements** | | |
| Fix entitlements (free team compat) | ✅ | `79c4271` |
| Widget UserDefaults fallback fix | ✅ | `79c4271` |
| Video upload + AI analysis feature | ✅ | `539c5ef` |
| Coach voice TTS (AVSpeechSynthesizer) | ✅ | `95b89f1` |
| PR share card (ImageRenderer) | ✅ | `95b89f1` |
| Firebase Crashlytics integration | ✅ | `95b89f1` |
| Firestore offline persistence (100MB) | ✅ | `95b89f1` |
| Auto rep counting (IronTracker) | ✅ | `95b89f1` |
| Injury risk detection (5 flag types) | ✅ | `95b89f1` |
| **Session 8 Hardening** | | |
| GPS Track: dark map (MKStandardMapConfiguration) | ✅ | `9673e35` |
| GPS Track: location permission denied banner | ✅ | `9673e35` |
| GPS Track: deprecate UIScreen.main → UIWindowScene | ✅ | `9673e35` |
| HistoryView: improved empty state w/ correct copy | ✅ | `9673e35` |
| VideoLibraryView: fix force-unwrap crash in computeTrend | ✅ | `9673e35` |
| Global: zero force-unwraps / force-casts / force-tries in production paths | ✅ | `9673e35` |

---

## Known Issues (require manual fix for device builds)

### Entitlements — Free Personal Team
Both `.entitlements` files are intentionally stripped to `<dict/>` for free personal team compatibility. HealthKit, App Groups, and Sign in with Apple require a paid $99/year Apple Developer account.

**When you get a paid account, manually re-add in Xcode Signing & Capabilities:**

**Kinetics target:**
- HealthKit capability
- App Groups: `group.com.rayancheca.kinetics`
- Sign in with Apple

**KineticsWidget target:**
- App Groups: `group.com.rayancheca.kinetics`

Until then: HealthKit returns empty data (graceful degradation), widgets show zeros (UserDefaults.standard fallback), Sign in with Apple falls back to anonymous auth.

### App Store Connect setup required before shipping
- Register product IDs for StoreKit subscriptions:
  - `com.rayancheca.kinetics.premium.monthly`
  - `com.rayancheca.kinetics.premium.annual`
- Replace placeholder `GoogleService-Info.plist` with real Firebase project
- Add real app icon (1024×1024) to `AppIcon.appiconset`
- Add real launch logo to `LaunchLogo.imageset`

---

## Architecture Summary

| Layer | Technology |
|---|---|
| Language | Swift 6 (strict concurrency) |
| UI | SwiftUI iOS 17+ |
| State | @Observable + @MainActor ViewModels |
| Computer Vision | Vision Framework (VNDetectHumanBodyPoseRequest + VNDetectTrajectoriesRequest) |
| Camera | AVFoundation (CameraManager actor) |
| Local data | SwiftData (GymTracker: Exercise, WorkoutSession, Set, Routine, PersonalRecord, BodyMeasurement) |
| Remote data | Firebase Firestore (JSON round-trip) |
| Auth | Firebase Auth (anonymous + Sign in with Apple + email/password) |
| Analytics | Firebase Analytics (module events + tab screen-time) |
| Health | HealthKit (workouts, HR, HRV, VO2 max, steps, sleep) |
| Location | CoreLocation (GPS track module) |
| Notifications | UNUserNotificationCenter (reminders + achievements) |
| Widgets | WidgetKit (TodayStats + NextWorkout, AppGroup data bridge) |
| Deep links | kinetics:// URL scheme + DeepLinkRouter |
| Subscriptions | StoreKit 2 (skeleton, Phase 3 ready) |
| Social | Firestore feed (posts, kudos, comments) |
| Navigation | NavigationStack + navigationDestination |

---

## Session History

| Session | What was built |
|---|---|
| 1 | App scaffold, Firebase, CameraManager, PoseDetectionEngine, TrajectoryTracker, 4 sport modules |
| 2 | Firebase plist bundling, camera fix, Swift 6 concurrency fixes |
| 3 | CoachingEngine, onboarding views, post-session reports, tab nav, settings/profile/history |
| 4 | Front camera toggle, GPS Track module, color tokens, social layer, Gym Tracker Part A |
| 5 | Gym Tracker Part B, HealthKit dashboard, notifications, WidgetKit extension |
| 6 | App Store prep, permissions gate, Firebase Analytics depth, Sign in with Apple, streak tracking, deep links, tab analytics, session→feed pipeline, StoreKit 2 skeleton |
| 7 | Entitlements fix (free team), widget fallback, video upload + AI analysis, coach voice TTS, PR share cards, Crashlytics, offline Firestore, auto rep counting, injury risk detection |

---

## Next Steps — Phase 2 (Telemetry + Data Collection)

1. Ship to TestFlight with real Firebase project (replace GoogleService-Info.plist)
2. Monitor Firebase Analytics for `module_session_started` and `tab_screen_time` events
3. After 60 days: identify highest-engagement module from Firestore data
4. Proceed to Phase 3 (spin-off)

## Next Steps — Phase 3 (Spin-Off)

1. Fork the repo
2. Extract winning module only
3. Create new Xcode project with sport-specific branding
4. Activate StoreKit subscriptions in App Store Connect (product IDs already defined)
5. Submit to App Store

---

## To Run the App

1. Open `Kinetics.xcodeproj` in Xcode
2. Select iPhone target
3. Signing & Capabilities → Team → your Apple ID
4. Manually re-add capabilities (hook strips entitlements): HealthKit, App Groups, Sign in with Apple
5. Build & Run (⌘R)

To run widget: select `KineticsWidget` scheme, build to same device.
