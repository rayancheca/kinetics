# Kinetics — AI Biomechanics Coach

A native iOS super-app that uses Apple's Vision Framework to coach athletes in real-time. Point your camera at yourself, and Kinetics tells you what's wrong with your movement — instantly, on-device, no cloud required.

---

## What It Does

Kinetics contains four expert coaching modules, all sharing one Vision engine:

| Module | Sport | Core Metric |
|--------|-------|-------------|
| **Striking Clinic** | MMA / Karate / TKD | Strike velocity (MPH) + kinetic chain score |
| **Grappling Lab** | BJJ / Judo | Center-of-mass stability + kuzushi index |
| **Iron Tracker** | Powerlifting / Weightlifting | Bar path deviation + VBT (m/s) + bilateral symmetry |
| **Wall Beta** | Bouldering / Sport Climbing | Hip proximity score + Dyno arc trace |

The app is intentionally over-featured. Firebase Analytics measures which module drives the most engagement over 60 days. The winner gets spun off as a standalone premium app.

---

## Architecture

```
AVCaptureSession (30fps, 1280×720)
    └── CameraManager (AsyncStream<CMSampleBuffer>)
            ├── PoseDetectionEngine (actor)
            │       └── VNDetectHumanBodyPoseRequest → JointPose (19 joints)
            └── TrajectoryTracker (actor)
                    └── VNDetectTrajectoriesRequest → [TrajectoryPath]

JointPose / TrajectoryPath
    ├── StrikingAnalytics  → StrikingViewModel  → StrikingView
    ├── GrapplingAnalytics → GrapplingViewModel → GrapplingView
    ├── IronTrackerAnalytics → IronTrackerViewModel → IronTrackerView
    └── WallBetaAnalytics  → WallBetaViewModel  → WallBetaView

Firebase Auth   → AuthManager    → AppState
Firebase Firestore → SessionRepository → session history
Firebase Analytics → module_session_started / module_session_completed
```

All Vision work runs on dedicated background queues via `actor` isolation. ViewModels are `@Observable @MainActor`. Views are pure SwiftUI — zero business logic in `body`.

---

## Tech Stack

| Layer | Technology | Why |
|-------|-----------|-----|
| Language | Swift 6 (strict concurrency) | Safe actor/async patterns |
| UI | SwiftUI iOS 17+ | `@Observable`, `NavigationStack` |
| Architecture | MVVM + `@Observable` macro | No `ObservableObject` legacy |
| Computer Vision | Apple Vision Framework | On-device, no latency, no cost |
| Camera | AVFoundation | Direct `AVCaptureSession` → `AsyncStream` |
| Auth / DB | Firebase Auth + Firestore | Cross-device session history |
| Analytics | Firebase Analytics | Module engagement measurement |
| Project Gen | xcodegen 2.45+ | Reproducible `.xcodeproj` from YAML |

**Rejected:** UIKit (SwiftUI covers all requirements), CoreML (Vision Framework already wraps the pose model), ObservableObject (deprecated pattern in Swift 6 context).

---

## How the Vision Pipeline Works

The hardest engineering decision was bridging AVFoundation's delegate callbacks — which fire on a private background queue — into the Swift 6 actor system.

`CameraManager` holds an `AsyncStream<CMSampleBuffer>` created once in `init`. The AVFoundation delegate stores the `AsyncStream.Continuation` as `nonisolated(unsafe)` to permit capture from the Sendable closure. Each frame yielded to the stream is consumed by the active module's ViewModel via `for await buffer in cameraManager.frameStream`.

This means only one ViewModel processes frames at a time (the active module), and the stream survives navigation transitions cleanly — no setup/teardown race conditions.

`PoseDetectionEngine` uses `VNSequenceRequestHandler` (not `VNImageRequestHandler`) so the model can track joints across frames for temporal consistency, significantly reducing the jitter you'd get from per-frame detection.

---

## Sport-Specific Analytics

### Striking Clinic
- Compares hip angular velocity vs. shoulder angular velocity. Hips should fire first.
- Kinematic chain score = `hipVelocity / shoulderVelocity` clamped to [0, 1].
- Strike detection via rising-edge threshold on wrist velocity (>5 mph).

### Grappling Lab
- Center of mass calculated as centroid of `leftHip + rightHip`.
- Base polygon built from `leftAnkle + rightAnkle + leftKnee + rightKnee`.
- Point-in-polygon test determines whether CoM is inside the base (stable).
- Spine vector: `neck` → `root` angle vs. vertical gives kuzushi (postural displacement) index.

### Iron Tracker
- Bar path tracked as `(leftWrist + rightWrist) / 2` midpoint.
- Bar velocity converted from pixel displacement using a real-world calibration assumption (1280px ≈ 2m frame width).
- Bilateral symmetry: percentage difference in left vs. right wrist Y-ascent speed.
- Butt wink: `leftHip`-`root`-`leftKnee` angle < 70° at squat bottom.

### Wall Beta
- Hip proximity score maps distance from the left edge (wall) to 0-100.
- Sag detection: hip Y drops >5% below an established baseline.
- Dyno detection: wrist velocity >8 mph + hips moving upward simultaneously.
- Dyno arc: accumulated wrist path points rendered as a glowing Canvas trail.

---

## Install & Run

### Prerequisites
- Xcode 16.2+
- iOS 17.0+ device (Vision Framework body pose **requires a physical device**)
- [xcodegen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)
- Firebase project (see below)

### Setup

```bash
git clone https://github.com/rayancheca/kinetics.git
cd kinetics
xcodegen generate
open Kinetics.xcodeproj
```

In Xcode:
1. Select your team under **Signing & Capabilities** → **Team**
2. Connect your iPhone and select it as the run destination
3. Press **⌘R** to build and run

> **Firebase:** The placeholder `GoogleService-Info.plist` lets the app build without Firebase. To enable auth and session history, create a Firebase project, add an iOS app with bundle ID `com.rayancheca.kinetics`, download the real `GoogleService-Info.plist`, and replace `Kinetics/Resources/GoogleService-Info.plist`.

### Enable Required Firebase Services

In the Firebase Console for your project:
- Authentication → Sign-in method → Email/Password ✓
- Firestore Database → Create database (production mode)
- Analytics → enabled by default

---

## Project Structure

```
Kinetics/
├── App/           KineticsApp.swift, AppState.swift
├── Core/
│   ├── Vision/    CameraManager, PoseDetectionEngine, TrajectoryTracker
│   ├── Analytics/ BiomechanicsCalculator (shared math)
│   └── Models/    JointPose, TrajectoryPath, SessionResult, SportType
├── Modules/
│   ├── StrikingClinic/
│   ├── GrapplingLab/
│   ├── IronTracker/
│   └── WallBeta/
├── Shared/
│   ├── Components/ CameraPreviewView, PoseOverlayView, MetricsCardView
│   └── Extensions/ Color+Kinetics
├── Firebase/      AuthManager, SessionRepository
├── Home/          HomeView, HomeViewModel
└── Resources/     Assets.xcassets, GoogleService-Info.plist
project.yml        xcodegen spec
```

---

## Roadmap

- [ ] Phase 2: Firebase Analytics data collection (60 days)
- [ ] Phase 3: Spin off highest-engagement module as standalone app with StoreKit 2 subscription
- [ ] Apple Watch companion for heart-rate overlay on session results
- [ ] Rep counting via trajectory detection
- [ ] Coach mode: record + annotate sessions for remote coaching
