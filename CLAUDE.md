# KINETICS — AI Sports Performance Coach
**Project:** Native iOS SwiftUI app with real-time computer vision biomechanics analysis
**Owner:** Rayan Karim-Checa (`rayancheca`)
**Location:** `/Users/rayankarimcheca/Desktop/ClaudeProjects/projects/kinetics/`
**State file:** `state.md` — read it at the start of every session before doing anything else

---

## AGENT SWARM MANDATE — NON-NEGOTIABLE

**You must spawn the maximum number of parallel sub-agents for every single task.** No task is too small to parallelize. This is the core operating principle of this project.

When you receive any instruction:
1. **Decompose first.** Break it into the smallest independent units of work.
2. **Spawn agents simultaneously.** Each unit runs concurrently with the others using the Task tool.
3. **Synthesize last.** Collect all agent outputs and merge into a single coherent result.

**Examples of mandatory parallelization:**
- Building 4 sport modules → 4 agents, each owning one module completely, running simultaneously
- Writing a ViewModel + Repository + Model → 3 agents in parallel, not sequential
- Setting up Firebase + Vision Framework + UI layer → 3 agents at once
- Code review pass → spawn one agent per file, all running concurrently
- Writing tests → one agent per ViewModel/module, all parallel

**Never do work sequentially that could be done in parallel. If you catch yourself working on one thing at a time, stop and respawn as parallel agents.**

The goal is a perfect, production-quality app — parallelism is how we get there fast without cutting corners.

---

## Project Vision

**Kinetics** is a native iOS biomechanics coaching app that uses Apple's Vision Framework to analyze athlete movement in real-time. It is an all-in-one "super-app" containing four expert sport modules. After launch, Firebase Analytics will identify the highest-engagement module, which then gets spun off as a standalone premium app.

**Super-app → Micro-app pipeline:**
Instagram started as Burbn (a bloated multi-feature app) and found its winning feature. Kinetics does the same: build everything, measure everything, spin off the winner.

---

## Tech Stack

| Layer | Technology |
|---|---|
| Language | Swift 6 |
| UI | SwiftUI (iOS 17+) |
| Architecture | MVVM with `@Observable` macro |
| Computer Vision | Apple Vision Framework (`VNDetectHumanBodyPoseRequest`, `VNDetectTrajectoriesRequest`) |
| Camera | AVFoundation (`AVCaptureSession`) |
| Analytics | Firebase Analytics |
| Auth | Firebase Auth |
| Database | Firebase Firestore |
| Local cache | SwiftData |
| Navigation | `NavigationStack` + `navigationDestination(for:)` |
| Concurrency | async/await, `@MainActor`, `withTaskGroup` |
| Target | iOS 17+, iPhone (portrait + landscape) |

**No UIKit. No completion handlers. No `@Published`/`ObservableObject`. No `NavigationView`.**

---

## Architecture Rules

### MVVM — Strict Enforcement
- Views are dumb. Zero business logic in `body`.
- All state and logic lives in `@Observable` ViewModels marked `@MainActor`.
- Repository layer abstracts all data access behind protocols.
- One ViewModel per screen. Pass via `.environment()` or init injection.

### File Structure
```
Kinetics/
├── App/
│   ├── KineticsApp.swift
│   └── AppState.swift
├── Core/
│   ├── Vision/
│   │   ├── PoseDetectionEngine.swift      ← VNDetectHumanBodyPoseRequest
│   │   ├── TrajectoryTracker.swift        ← VNDetectTrajectoriesRequest
│   │   └── CameraManager.swift            ← AVCaptureSession wrapper
│   ├── Analytics/
│   │   └── BiomechanicsCalculator.swift   ← Shared math (velocity, angles, CoG)
│   └── Models/
│       ├── JointPose.swift
│       ├── TrajectoryPath.swift
│       └── SessionResult.swift
├── Modules/
│   ├── StrikingClinic/
│   │   ├── StrikingView.swift
│   │   ├── StrikingViewModel.swift
│   │   └── StrikingAnalytics.swift
│   ├── GrapplingLab/
│   │   ├── GrapplingView.swift
│   │   ├── GrapplingViewModel.swift
│   │   └── GrapplingAnalytics.swift
│   ├── IronTracker/
│   │   ├── IronTrackerView.swift
│   │   ├── IronTrackerViewModel.swift
│   │   └── IronTrackerAnalytics.swift
│   └── WallBeta/
│       ├── WallBetaView.swift
│       ├── WallBetaViewModel.swift
│       └── WallBetaAnalytics.swift
├── Shared/
│   ├── Components/
│   │   ├── CameraPreviewView.swift
│   │   ├── PoseOverlayView.swift          ← 19-joint skeleton overlay
│   │   ├── MetricsCardView.swift
│   │   └── SessionHistoryRow.swift
│   └── Extensions/
│       └── Color+Kinetics.swift
├── Firebase/
│   ├── AuthManager.swift
│   └── SessionRepository.swift
└── Resources/
    ├── Assets.xcassets
    └── GoogleService-Info.plist
```

### Core Vision Engine — The Shared Backend

All four modules feed from the SAME Vision engine. The engine outputs raw `VNHumanBodyPoseObservation` joint coordinates. Each module's `Analytics` layer transforms those coordinates with sport-specific math.

```
AVCaptureSession
    → CameraManager (frame buffer)
        → PoseDetectionEngine (VNDetectHumanBodyPoseRequest → 19 joints)
        → TrajectoryTracker (VNDetectTrajectoriesRequest → movement arcs)
            → Module-specific Analytics (strike velocity / CoG / bar path / etc.)
                → ViewModel (publishes to View)
```

---

## The Four Modules — Detailed Specs

### 1. Striking Clinic (MMA / Karate / Taekwondo)
**Core concept:** Kinetic chaining — energy transfers from floor → hips → shoulders → fist/foot.

**What to track:**
- Joint firing sequence: hips must rotate before shoulders for max power
- Hip-to-shoulder separation angle (measures coiling and uncoiling)
- Strike velocity in mph/fps (calculated via joint displacement ÷ frame rate delta)
- Stance width recovery time (how fast the athlete resets to base after a strike)

**Key Vision nodes:** `leftHip`, `rightHip`, `leftShoulder`, `rightShoulder`, `leftWrist`, `rightWrist`, `leftAnkle`, `rightAnkle`

**UI output:** Live skeleton overlay + real-time velocity badge + post-session breakdown card showing the hip-to-shoulder separation graph per strike.

---

### 2. Grappling Lab (BJJ / Judo)
**Core concept:** Leverage and base over velocity. Limb tangling means we track structure, not speed.

**What to track:**
- Center of mass relative to base (feet/knees on the floor)
- Judo-specific: "Kuzushi" — opponent's spine angle relative to floor before throw execution
- BJJ-specific: hip elevation angles for triangles and armbars
- Postural breakdown alerts (when center of mass exits the base polygon)

**Key Vision nodes:** `root` (hips), `leftKnee`, `rightKnee`, `leftAnkle`, `rightAnkle`, `neck`, `nose` (for head/spine line)

**UI output:** Center-of-mass dot projected on floor plane + spine angle indicator + postural alert banner.

---

### 3. Iron Tracker (Powerlifting / Olympic Weightlifting)
**Core concept:** Form breakdown = injury. Bar path deviation and postural collapse are the two killers.

**What to track:**
- Bar path trace (glowing line overlay tracking the barbell/wrists over the full lift)
- Bar velocity for Velocity-Based Training (VBT) — displayed in m/s
- "Butt wink" detection: lumbar spine vs. pelvis angle at the bottom of a squat
- Bilateral symmetry: compare left vs. right wrist ascent speed during pressing movements
- Detect if one arm leads on bench press (asymmetric loading = injury risk)

**Camera orientation:** Horizontal / landscape. The app locks to landscape for this module and instructs the user to mount the phone on a tripod at hip height.

**Key Vision nodes:** `leftWrist`, `rightWrist`, `leftHip`, `rightHip`, `leftShoulder`, `rightShoulder`, `leftKnee`, `rightKnee`

**UI output:** Bar path line rendered in bright accent color over video feed + real-time VBT speed badge + symmetry gauge (left vs. right %).

---

### 4. Wall Beta (Bouldering / Sport Climbing)
**Core concept:** Hip proximity to wall = weight on feet, not arms. Technique over strength.

**What to track:**
- Hip-to-wall proximity (closer hips = better technique)
- "Sag" detection — when the climber's hips drop and pull them off the wall
- Dynamic movement (Dyno) trajectory arc — maps the full body arc during explosive moves
- Time-under-tension per hold (how long the athlete is stationary at each position)
- Center-of-mass tracking — flag moments when weight shifts off the foothold causing a slip

**Key Vision nodes:** `leftHip`, `rightHip`, `root`, `leftFoot`, `rightFoot`, `leftWrist`, `rightWrist`

**UI output:** Hip proximity gauge + CoM dot overlay + Dyno arc trace in a replay overlay + time-per-hold heatmap after session.

---

## Build Phases

### Phase 1 — MVP (Current)
Build the single SwiftUI super-app with all four modules. The Vision backend is shared. Module selection via a beautiful tabbed home screen.

**Deliverables:**
- [ ] Xcode project scaffolded with full folder structure above
- [ ] `CameraManager` (AVFoundation, live preview, frame buffer output)
- [ ] `PoseDetectionEngine` (VNDetectHumanBodyPoseRequest, 30fps processing)
- [ ] `TrajectoryTracker` (VNDetectTrajectoriesRequest)
- [ ] `BiomechanicsCalculator` (velocity formula, angle calculation, CoG projection)
- [ ] `PoseOverlayView` (19-joint skeleton drawn over camera feed)
- [ ] All four module Views + ViewModels with real analytics
- [ ] Tab-based home with module cards
- [ ] Session history (stored in Firestore)
- [ ] Firebase Auth (sign in with Apple)
- [ ] Firebase Analytics events per module (for Phase 2 data collection)

### Phase 2 — Telemetry
Firebase Analytics tracks:
- `module_session_started` (which module, duration)
- `module_session_completed` (metrics achieved, sport)
- Screen time per module tab

Analyze after 60 days. Pick the winner.

### Phase 3 — Spin-Off
Extract the winning module. New Xcode project. Sport-specific branding, UI reskin, $4.99/month subscription via StoreKit 2. Remove all other modules.

---

## UI / Design Principles

- Dark background (`Color.black` / very dark gray `#0D0D0D`)
- Accent color: electric blue `#00C2FF` for overlays and active states
- Secondary accent: neon green `#39FF14` for real-time metrics badges
- SF Pro Rounded for metric values. SF Pro Display for headings.
- Camera feed takes 100% of the screen. All overlays are semi-transparent layers on top.
- Metrics cards appear at the bottom in a `safeAreaInset` panel — never block the feed.
- Skeleton overlay uses colored joints (active joints highlighted in accent color)
- Minimal chrome — the athlete should see themselves, not the app UI.

---

## Code Quality Standards

- Zero force unwraps (`!`) in production paths
- Every Vision request error must surface to the user
- All AVCaptureSession work on a dedicated background queue
- All ViewModel updates on `@MainActor`
- `[weak self]` in every closure that captures a class
- Firestore listeners removed in `deinit`
- `guard let` over nested `if let` everywhere
- Lines under 100 characters
- `// MARK: -` sections in every class with 3+ methods

---

## Session Continuity

- At the start of every session: read `state.md`
- At the end of every session: update `state.md` with exactly what was completed, what's next, and any blockers
- Never re-do completed work. Never skip the state check.
- If `state.md` is missing, create it before doing anything else.