# Kinetics — Session State

**Last updated:** Session 3 (2026-04-29) — Session 3 features built, compiled, committed, pushed
**Current phase:** Phase 1 — MVP
**Overall progress:** Session 3 complete ✅ Build succeeded.

---

## Status: SESSION 3 COMPLETE — BUILD SUCCEEDED

`** BUILD SUCCEEDED **` on iPhone 17 Pro Simulator.
All 27 changed files committed and pushed to https://github.com/rayancheca/kinetics

---

## Session 3 — What Was Built

### New Files (15 new, 12 modified)

**Coaching Intelligence:**
- `Kinetics/Core/Analytics/CoachingEngine.swift` — AI coaching notes from metric thresholds for all 4 sports. `generateNotes(for:previousSessions:)` returns up to 4 notes (achievements first). `nextSessionGoal(for:)` returns one-line goal string.
- `Kinetics/Core/Models/SessionResult.swift` — Added `CoachingNote` struct + 3 new fields: `coachingNotes: [CoachingNote]`, `sessionNumber: Int`, `personalBests: [String: Double]`. All default to empty/1 so old Firestore docs decode fine.

**Onboarding (4 new files):**
- `StrikingOnboardingView.swift` — red accent, velocity/chain/separation metric explainers
- `GrapplingOnboardingView.swift` — orange accent, CoM/kuzushi/base stability
- `IronTrackerOnboardingView.swift` — blue accent, bar path/VBT/symmetry, landscape warning
- `WallBetaOnboardingView.swift` — green accent, hip proximity/sag/dyno arc
- `Shared/Components/OnboardingMetricRow.swift` — shared `OnboardingMetricRow` + `OnboardingCameraSetup` components

**Post-Session Reports (4 new files):**
- `StrikingSessionReportView.swift` — peak velocity (PB badge), chain score, hip-sep with goal bar
- `GrapplingSessionReportView.swift` — kuzushi, base stability, postural breaks, CoM row
- `IronTrackerSessionReportView.swift` — bar deviation (color-coded), VBT zone, symmetry, butt wink warning, bar path Canvas
- `WallBetaSessionReportView.swift` — hip proximity, sag count, hold time, dyno arc section
- Shared `CoachingNoteCard` + `reportCard()` defined in Striking file, used by all 4 (same target)

**Navigation:**
- `MainTabView.swift` — 4 tabs: Home / Train / History / Profile
- `TrainView.swift` — full-width module cards with bullet analytics previews
- `HistoryView.swift` — sessions grouped by day, sport filter pills, `HistoryViewModel`
- `SessionDetailView.swift` — all metrics mapped to human labels, delete button
- `ProfileView.swift` — avatar, stats grid (total, time, favorite, streak), units picker, settings

**ViewModel additions (all 4 modified):**
- `coachingCue: String` — live coaching text from current frame
- `formattedDuration: String` — M:SS
- `lastCompletedSession: SessionResult?` — triggers report presentation

**View additions (all 4 modified):**
- First-launch onboarding sheet + ⓘ toolbar button to revisit
- Live red pulse dot while recording
- Coaching cue text below metrics panel
- `.fullScreenCover` presenting report when session ends

**Other:**
- `SessionRepository.swift` — added `deleteSession(id:userId:)`
- `KineticsApp.swift` — `HomeView()` → `MainTabView()`
- `project.pbxproj` — regenerated via `xcodegen generate` to register all new files

---

## Architecture Decisions

- `@AppStorage` in `@Observable` classes is illegal in Swift 6 — moved to the View struct (`ProfileView`)
- `CoachingNoteCard` and `reportCard()` defined once in `StrikingSessionReportView.swift`, visible to all 4 report views (same Xcode target)
- xcodegen used to regenerate project file rather than manually editing `.pbxproj` — run `xcodegen generate` whenever new Swift files are added

---

## What Was Completed Across All Sessions

### Session 1
- Full app scaffold: 4 modules, Firebase, CameraManager, PoseDetectionEngine, TrajectoryTracker

### Session 2
- Firebase plist bundling (missing PBXResourcesBuildPhase)
- Camera black screen (configure-once pattern)
- 5 Swift 6 concurrency errors

### Session 3 (this session)
- CoachingEngine AI layer
- Onboarding views (all 4 modules)
- Post-session report screens (all 4 modules)
- Tab navigation (Home/Train/History/Profile)
- Settings, Profile, History, SessionDetail views
- ViewModel coaching cue + live pulse + report trigger

---

## Next Session — Session 4

**Read NEXT_SESSION.md Section 15 first.**

Priority order:
1. **Front camera toggle** (Section 15) — `CameraManager.switchCamera()`, preview mirroring, Vision x-flip, floating rotate button on all 4 module Views
2. **Strava GPS tracking** (Section 6) — CoreLocation, HealthKit, MapKit, Swift Charts, pace/HR/elevation
3. **Social feed** (Section 7) — follow graph, activity feed, kudos, comments

### Prompt to use at start of Session 4:
```
Read state.md and NEXT_SESSION.md before doing anything.

Session 3 is complete — coaching engine, onboarding, report screens, tab navigation all built and committed.

Session 4 priorities:
1. Front camera toggle — read Section 15 of NEXT_SESSION.md for complete spec. Modify CameraManager.swift (add switchCamera()), PoseDetectionEngine.swift (x-flip for front camera), CameraPreviewView.swift (mirror preview layer), and all 4 module Views (floating rotate button, @AppStorage camera preference). Run 4 parallel agents.
2. After front camera is committed, start Section 6 (Strava GPS tracking). Decompose into parallel agents.

Always spawn maximum parallel agents. Commit after every feature. Push after every commit. Never delete files.
```

---

## To Run the App

1. Open `Kinetics.xcodeproj` in Xcode
2. Select your iPhone as target device
3. Signing & Capabilities → Team → select your Apple ID
4. Press ⌘R
5. Trust the developer certificate in Settings → General → VPN & Device Management

If new Swift files are added and Xcode can't find them: run `xcodegen generate` in the project root.
