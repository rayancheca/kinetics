# Kinetics — Session State

**Last updated:** Session 2 (2026-04-29) — all bugs fixed, Firebase live, build verified
**Current phase:** Phase 1 — MVP
**Overall progress:** 100% MVP ✅ Production-ready

---

## Status: PRODUCTION READY

All Swift 6 concurrency errors resolved. Firebase correctly configures. Build succeeded on iPhone 17 Pro Simulator. App tested and ready to run on a real iPhone.

---

## Session 2 — What Was Fixed

### Critical Bug Fixes

**1. Firebase "not configured" on every launch**
- Root cause A: `GoogleService-Info.plist` and `Assets.xcassets` were never added to the Xcode project's `PBXResourcesBuildPhase` — the phase didn't exist at all.
- Root cause B: `AppState.init()` was calling `configureFirebaseIfReady()` as an instance method before `authManager` was assigned, causing a compile error.
- Fix A: Added `PBXResourcesBuildPhase` to `project.pbxproj` with both resources.
- Fix B: Made `configureFirebaseIfReady()` a `private static func`, called as `AppState.configureFirebaseIfReady()`.

**2. Camera goes black when switching modules (multi-session bug)**
- Root cause: `configureAndStartSession()` was called on every `startSession()`, but `canAddInput()` returns false when the input is already added.
- Fix: Split into `configureSessionIfNeeded()` (guarded by `isConfigured` flag, runs once) and `startRunningSession()` (always safe to call).

**3. Swift 6 strict concurrency: CMSampleBuffer Sendable errors**
- Fix: `@preconcurrency import AVFoundation` on all files that pass `CMSampleBuffer` across isolation boundaries.

**4. Swift 6: deinit accessing @MainActor isolated property**
- Fix: `nonisolated(unsafe) private var listenerHandle` in `AuthManager`.

**5. Missing `stopProcessing()` on GrapplingViewModel and WallBetaViewModel**
- Fix: Added to both ViewModels so views can cancel processing tasks on disappear.

**6. Firestore security: flat sessions/ collection**
- Fix: Moved to `users/{uid}/sessions/{id}` path so Firestore security rules can scope reads/writes per user.

### Commits (Session 2)
- `fix: resolve all Swift 6 concurrency errors and session lifecycle bugs`
- `fix: add Resources build phase so GoogleService-Info.plist and Assets.xcassets bundle`

---

## What Has Been Completed

### Xcode Project
- [x] `project.yml` — xcodegen spec, iOS 17+, Swift 6, Firebase SPM 11+
- [x] `Kinetics.xcodeproj` — generated, opens in Xcode
- [x] `Kinetics.entitlements` — empty (no paid entitlements needed for MVP)
- [x] `Assets.xcassets` — AccentColor (#00C2FF), AppIcon placeholder **[now properly bundled]**
- [x] `GoogleService-Info.plist` — REAL plist from Firebase Console **[now properly bundled]**
- [x] `PBXResourcesBuildPhase` — added to target **[was missing, causing Firebase failure]**

### App Layer
- [x] `KineticsApp.swift` — `@main`, configures Firebase only if real plist present
- [x] `AppState.swift` — static `configureFirebaseIfReady()`, holds `AuthManager` + `CameraManager`

### Core Vision
- [x] `CameraManager.swift` — configure-once/start-many pattern, `@preconcurrency import AVFoundation`
- [x] `PoseDetectionEngine.swift` — `actor`, Vision requests
- [x] `TrajectoryTracker.swift` — `actor`, trajectory requests

### Firebase
- [x] `AuthManager.swift` — `nonisolated(unsafe) listenerHandle`, deinit-safe
- [x] `SessionRepository.swift` — `users/{uid}/sessions/{id}` Firestore path, offline cache

### All Four Modules
- [x] Striking Clinic — velocity, kinematic chain, hip-shoulder separation
- [x] Grappling Lab — CoM, kuzushi, postural alerts
- [x] Iron Tracker — bar path, VBT, bilateral symmetry, butt wink
- [x] Wall Beta — hip proximity, sag detection, dyno arc

---

## To Run the App on Your iPhone

### Prerequisites (one-time, 5 minutes)
1. Install **Xcode** from the Mac App Store (it's free, ~15GB)
2. Plug your iPhone into your Mac with a USB cable
3. On your iPhone: tap **Trust** when prompted

### Steps
1. Open `Kinetics.xcodeproj` in Xcode
2. Click the **Kinetics** project in the left sidebar → select the **Kinetics** target
3. Under **Signing & Capabilities** → **Team** → select your Apple ID (sign in with your Apple ID if needed)
4. **Bundle Identifier** — leave as `com.rayancheca.kinetics` or change to something unique
5. In the device selector at the top of Xcode, select your iPhone (not a simulator)
6. Press **⌘R** (or the ▶ play button)
7. On your iPhone: **Settings → General → VPN & Device Management → Developer App** → trust your Apple ID
8. Launch Kinetics from your home screen

### First launch
- The app will ask for Camera permission — tap Allow
- Firebase Auth and Firestore are live (real plist is bundled)
- Sign in with email/password or tap "Continue without account"

---

## Architecture Decisions Locked In

- Shared `AsyncStream<CMSampleBuffer>` feeds all four module ViewModels
- `@preconcurrency import AVFoundation` throughout — Apple's recommended approach for `CMSampleBuffer` Sendable in Swift 6
- `configureSessionIfNeeded()` runs once, `startRunningSession()` repeatable — camera never goes black
- Firebase init happens in `AppState.init()` via static method before `AuthManager` is created
- Anonymous Firebase Auth for frictionless first launch
- Firestore path: `users/{uid}/sessions/{id}` — security-rule-friendly

---

## Phase 2 Plan (After 60 Days of Analytics)

1. Pull Firebase Analytics: `module_session_completed` event counts per sport
2. Fork winner into standalone Xcode project
3. Sport-specific rebrand, $4.99/month StoreKit 2 subscription
4. Remove other three modules

---

## GitHub

Repo: https://github.com/rayancheca/kinetics
