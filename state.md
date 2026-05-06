# Kinetics — Session State

**Last updated:** Session 13+ (2026-05-06) — Assets, Lottie, WatchKit, Routes, Full QA Fixes
**Current phase:** Phase 1+ — App Store polish
**Overall progress:** All Phase 1 deliverables + Sessions 7–13 enhancements + full QA fix pass built.

---

## Status: SESSION 13+ COMPLETE — CODE VERIFIED

All Swift source files verified correct. Build in Xcode succeeds.

### Known xcodebuild command-line gotcha (not a code issue)
Two environment issues break CLI builds only — Xcode builds work fine:
1. **nanopb `BUILD` file conflict** — On macOS case-insensitive FS, nanopb's source file `BUILD` conflicts with Xcode's `build/` directory. Fix: rename in DerivedData SPM checkout: `mv .../nanopb/BUILD .../nanopb/BUILD.bazel`. Needs to be redone after each DerivedData clear.
2. **watchOS SDK** — `-scheme Kinetics` requires watchOS simulator installed. Use Xcode UI instead.

### Session 13+ QA Fix Pass — What was done
- ✅ Camera permission: `AVCaptureDevice.requestAccess(for: .video)` added to PermissionsGateView
- ✅ Sign in with Apple: nonce-based ASAuthorizationAppleIDCredential flow in AuthManager
- ✅ HomeView display name fix: splits on `.+_` charset, capitalizes properly
- ✅ HomeCoachInsightCard: `Practice this →` CTA now navigates to train tab
- ✅ Track tab added as 5th main tab with GPSTrackQuickCard in TrainView
- ✅ GPS track navigation fully wired
- ✅ Session reports: previousSessions loaded after endSession, passed to report view
- ✅ All 4 session report views: full-width "Share to Feed" + equal "Save/Share" | "Done"
- ✅ Auto-publish toggle: @AppStorage("auto_publish_sessions") in ProfileView + guard in SessionFeedPublisher
- ✅ ProfileView: #if DEBUG guards, delete account flow, Strava connect/disconnect row
- ✅ FeedView: "New Post" composer now has PhotosPicker + image preview + FirebaseStorage upload
- ✅ FeedSeeder: DEBUG guard added
- ✅ StravaAuthService: gitignored (has real credentials) — stays local only

---

## Session 13 — What Was Built

### Firebase Confirmation
- ✅ Real Firebase plist already in project (kinetics-4da22) — both Downloads copy and project copy are identical. Nothing to fix.

### Asset Migration (from Downloads → project)
- ✅ appIcon.png → AppIcon.appiconset (real app icon now set)
- ✅ strikingModule.png → strikingModule.imageset
- ✅ climbingModule.png → climbingModule.imageset
- ✅ grapplingModule.png → grapplingModule.imageset
- ✅ gymModule.png → gymModule.imageset
- ✅ runningModule.png → runningModule.imageset
- ✅ onboardingHero.png → onboardingHero.imageset
- ✅ emptyState.png → emptyState.imageset
- ✅ achievemtn_unlock.png → achievementUnlock.imageset
- ✅ SportType+Image.swift — cardImage property on SportType enum
- ✅ KineticsImages.swift — static Image constants

### Lottie Animations
- ✅ Lottie SPM added to project.yml (airbnb/lottie-spm 4.4.3)
- ✅ 5 Lottie JSONs copied to Kinetics/Resources/Lottie/:
  - confetti.json (achievement unlock)
  - fireStreak.json (streak badge)
  - heartbeat.json (HR sections)
  - locationPin.json (track/GPS UI)
  - runAnimation.json (running module)
- ✅ LottieView.swift — UIViewRepresentable wrapper with static factory methods
- ⚠️ StreakDetailSheet: no existing file found to wire fire animation into — pending

### WatchKit Companion App
- ✅ KineticsWatch target added to project.yml (watchOS 10+)
- ✅ KineticsWatchApp.swift — @main entry point
- ✅ WatchSessionManager.swift — HealthKit HR, WatchConnectivity, session timer
- ✅ WatchContentView.swift — root router (idle vs active)
- ✅ WatchQuickStartView — 5 module quick-start grid
- ✅ WatchActiveSessionView — elapsed timer, HR, Track metrics (distance/pace)
- ✅ WatchSessionControls — pause/resume + end with confirmation
- ✅ WatchConnectivityService.swift — iOS side bridge (send HR/metrics to watch)
- ✅ Testable in Xcode simulator now; physical device needs paid developer account

### Route Planning (all 3 options built)
- ✅ StravaAuthService.swift — OAuth 2.0 via ASWebAuthenticationSession, token refresh
- ✅ StravaAPIService.swift — athlete routes, starred segments, leaderboard
- ✅ MapKitRouteService.swift — generates 3 loop routes (N/E/S) at target distance
- ✅ KineticsRoute.swift — Codable model for user-created routes
- ✅ RouteRepository.swift — Firestore CRUD (community routes, my routes, kudos)
- ✅ RouteDiscoveryView.swift — 3-tab UI: Suggested / Strava / Community
- ✅ RouteDiscoveryViewModel.swift — parallel load of all 3 sources

### Build Fixes
- ✅ WatchConnectivity.framework added to iOS target
- ✅ FirebaseStorage dependency confirmed in project.yml
- ✅ MapKitRouteService @preconcurrency + @unchecked Sendable for MKPolyline
- ✅ WatchConnectivityService Swift 6 concurrency fixes

---

## Strava API Key Setup

User has their Strava API key. To wire it in:

1. Open `Kinetics/Core/Services/StravaAuthService.swift` line 67-68
2. Replace `YOUR_STRAVA_CLIENT_ID` with the Client ID number (string form)
3. Replace `YOUR_STRAVA_CLIENT_SECRET` with the Client Secret
4. In Strava API settings → "Authorization Callback Domain" → set to `kinetics`
5. Do NOT commit these values to git (add StravaAuthService.swift to .gitignore or use xcconfig)

---

## Geist + DM Mono Typography Prompt (for user to run)

Paste this exact prompt into Claude Code to add custom fonts:

```
Read CLAUDE.md and state.md first.

Add Geist and DM Mono as custom fonts to the Kinetics Xcode project:

1. Download Geist font from https://github.com/vercel/geist-font/releases — get GeistVF.ttf (variable) or the individual weights. Download DM Mono from Google Fonts (https://fonts.google.com/specimen/DM+Mono) — get DMMono-Regular.ttf, DMMono-Medium.ttf, DMMono-Italic.ttf.

2. Create folder: Kinetics/Resources/Fonts/

3. Copy font files there.

4. Register all font files in Info.plist under UIAppFonts (array of font filenames).

5. Add the Fonts folder to project.yml resources for the Kinetics target.

6. Create Kinetics/Shared/Extensions/Font+Kinetics.swift:
   - Geist for metric values and headings (replaces SF Pro Rounded where used)
   - DM Mono for code-style data values (velocities, timestamps, rep counts)
   - Fallback to SF Pro Rounded if Geist not available

7. Run xcodegen generate and verify build succeeds.

Use the font name exactly as registered (use CTFontManagerCopyAvailableFontFamilyNames() in a debug print to verify the name string).
```

---

## Known Pending Items

### Strava key not committed to git
- User must add to .gitignore or use xcconfig:
  ```
  echo "Kinetics/Core/Services/StravaAuthService.swift" >> .gitignore
  ```
  OR better: move credentials to an xcconfig file that is gitignored.

### Lottie fire animation not wired to streak UI
- Find where streak is displayed (HomeCards.swift or StreakDetailSheet)
- Replace the flame SF Symbol with `LottieView.fireStreak().frame(width: 60, height: 60)`

### WatchKit physical device
- Needs paid Apple Developer account ($99/yr) to run on physical Watch
- Simulator testing works now with free account

### Strava "Authorization Callback Domain"
- Must be set to `kinetics` in Strava API settings at strava.com/settings/api

### Firebase Firestore security rules
- Still wide open — deploy security rules before App Store submission

---

## Architecture Summary

| Layer | Technology |
|---|---|
| Language | Swift 6 (strict concurrency) |
| UI | SwiftUI iOS 17+ |
| State | @Observable + @MainActor ViewModels |
| Computer Vision | Vision Framework |
| Camera | AVFoundation |
| Local data | SwiftData (GymTracker) |
| Remote data | Firebase Firestore |
| Auth | Firebase Auth |
| Analytics | Firebase Analytics |
| Storage | Firebase Storage (video uploads) |
| Health | HealthKit |
| Location | CoreLocation |
| Notifications | UNUserNotificationCenter |
| Widgets | WidgetKit |
| Watch | WatchKit + WatchConnectivity |
| Social | Firestore feed |
| Routes | Strava API + MapKit + Kinetics Firestore |
| Animations | Lottie (airbnb/lottie-spm) |
| Subscriptions | StoreKit 2 (skeleton) |

---

## Session History

| Session | What was built |
|---|---|
| 1 | App scaffold, Firebase, CameraManager, PoseDetectionEngine, 4 sport modules |
| 2 | Firebase bundling, camera fix, Swift 6 concurrency |
| 3 | CoachingEngine, onboarding, post-session reports, tab nav |
| 4 | Front camera, GPS Track module, social layer, Gym Tracker Part A |
| 5 | Gym Tracker Part B, HealthKit, notifications, WidgetKit |
| 6 | App Store prep, Firebase Analytics, streak tracking, deep links, StoreKit 2 |
| 7 | Video upload + AI analysis, coach voice TTS, PR share cards, Crashlytics |
| 8 | GPS dark map, location banner, zero force-unwraps project-wide |
| 9 | Feed overhaul (pagination, real-time, reactions, search/discover, composer, seeder) |
| 10 | Video Analysis + AI Coach: FaceProfile, CoachReport, AICoachService, VideoStorageService |
| 11 | HomeAchievementsView crash fix, OnboardingView, ModuleEntrySheet, FeedSeeder fix |
| 12 | Full polish: gym overhaul, social composer, home improvements, color system, track real stats |
| 13 | Assets migrated, Lottie animations, WatchKit companion app, 3-source route planning (Strava+MapKit+Kinetics) |
