# Kinetics — Session State

**Last updated:** Session 1 (COMPLETE — full MVP built and pushed to GitHub)
**Current phase:** Phase 1 — MVP
**Overall progress:** 100% MVP ✅

---

## Status: COMPLETE (Phase 1)

All 30 Swift source files written. Xcode project generated via xcodegen. Pushed to GitHub.
The app builds and is ready to run on a real iPhone as soon as the developer team is set in Xcode.

---

## What Has Been Completed

### Xcode Project
- [x] `project.yml` — xcodegen spec, iOS 17+, Swift 6, Firebase SPM 11+
- [x] `Kinetics.xcodeproj` — generated, opens in Xcode
- [x] `Kinetics.entitlements` — empty (no paid entitlements needed for MVP)
- [x] `Assets.xcassets` — AccentColor (#00C2FF), AppIcon placeholder
- [x] `GoogleService-Info.plist` — placeholder (replace with real plist to enable Firebase)

### App Layer
- [x] `KineticsApp.swift` — `@main`, configures Firebase only if real plist present
- [x] `AppState.swift` — `@Observable @MainActor`, holds `AuthManager` + `CameraManager`

### Core Vision
- [x] `CameraManager.swift` — `AVCaptureSession`, back camera, 1280×720, 30fps, `AsyncStream<CMSampleBuffer>`
- [x] `PoseDetectionEngine.swift` — `actor`, `VNDetectHumanBodyPoseRequest`, `VNSequenceRequestHandler`
- [x] `TrajectoryTracker.swift` — `actor`, `VNDetectTrajectoriesRequest`

### Core Models
- [x] `JointPose.swift` — 19-joint struct from `VNHumanBodyPoseObservation`
- [x] `TrajectoryPath.swift` — arc struct from `VNTrajectoryObservation`
- [x] `SessionResult.swift` + `SportType` enum (4 cases, Codable, Identifiable)
- [x] `BiomechanicsCalculator.swift` — velocity (mph + m/s), angles, CoM, symmetry, point-in-polygon

### Shared Components
- [x] `CameraPreviewView.swift` — `UIViewRepresentable` wrapping `AVCaptureVideoPreviewLayer`
- [x] `PoseOverlayView.swift` — Canvas skeleton (19 joints + bones), Y-axis flip
- [x] `MetricsCardView.swift` — `MetricBadge`, `MetricRow`, `StatusBadge`, `.ultraThinMaterial`
- [x] `SessionHistoryRow.swift` — sport-branded icon + formatted date/duration

### Color System
- [x] `Color+Kinetics.swift` — kineticsBackground, kineticsBlue, kineticsGreen, kineticsDark, kineticsMidGray, kineticsRed, kineticsOrange, `moduleColor(for:)`

### Firebase
- [x] `AuthManager.swift` — anonymous + email/password + account creation, `@Observable @MainActor`
- [x] `SessionRepository.swift` — save/fetch `SessionResult` to Firestore, Analytics events

### Home
- [x] `HomeView.swift` — NavigationStack, 2×2 grid, `ModuleCard`, `ScaleButtonStyle`, `SignInSheet`, `KineticsTextFieldStyle`, `SkeletonRow`
- [x] `HomeViewModel.swift` — loads 5 recent sessions, handles anonymous sign-in

### Striking Clinic
- [x] `StrikingAnalytics.swift` — strike velocity MPH, hip-shoulder separation, kinematic chain score
- [x] `StrikingViewModel.swift` — processes frameStream, tracks strike count
- [x] `StrikingView.swift` — full-screen camera, red flash on strike, metrics panel

### Grappling Lab
- [x] `GrapplingAnalytics.swift` — CoM, base polygon, point-in-polygon, kuzushi index, spine angle
- [x] `GrapplingViewModel.swift` — stability score averaging
- [x] `GrapplingView.swift` — orange CoM dot overlay, postural alert banner

### Iron Tracker
- [x] `IronTrackerAnalytics.swift` — bar path, VBT m/s, bilateral symmetry, butt wink, knee cave
- [x] `IronTrackerViewModel.swift` — barPath history array, viewSize binding for m/s calibration
- [x] `IronTrackerView.swift` — landscape gate, bar path Canvas glow, alert badges

### Wall Beta
- [x] `WallBetaAnalytics.swift` — hip proximity score, sag detection, dyno detection, hold timing
- [x] `WallBetaViewModel.swift` — hipYBaseline, holdStartTime, dynoPath accumulation
- [x] `WallBetaView.swift` — proximity gauge, dyno arc Canvas, phase badge

---

## To Run the App

1. Open `Kinetics.xcodeproj` in Xcode 16+
2. Signing & Capabilities → select your Apple ID team
3. Connect iPhone → trust device
4. ⌘R to build and run

**To enable Firebase:**
- Create a Firebase project with iOS app (bundle ID: `com.rayancheca.kinetics`)
- Enable Email/Password auth and Firestore
- Download `GoogleService-Info.plist` → drop into `Kinetics/Resources/`
- Re-run xcodegen if needed, then rebuild

---

## Architecture Decisions Locked In

- Shared `AsyncStream<CMSampleBuffer>` feeds all four module ViewModels — one stream, sequential consumers
- `nonisolated(unsafe)` on `session` and `frameContinuation` to bridge AVFoundation delegate (background queue) into async stream
- `VNSequenceRequestHandler` for temporal joint consistency across frames
- `VNDetectTrajectoriesRequest(frameAnalysisSpacing: .zero, trajectoryLength: 10)` — every frame, 10-frame buffer
- Anonymous Firebase Auth on first launch so session history works before user creates account
- Placeholder `GoogleService-Info.plist` with sentinel API_KEY so app compiles and runs without real Firebase

---

## Phase 2 Plan (After 60 Days of Analytics)

1. Pull Firebase Analytics: which module has highest `module_session_completed` event count
2. Fork winner into standalone Xcode project
3. Sport-specific rebrand, $4.99/month StoreKit 2 subscription
4. Remove other three modules

---

## GitHub

Repo: https://github.com/rayancheca/kinetics
