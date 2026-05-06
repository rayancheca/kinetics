# Kinetics — Session 12 Master Plan
**Date:** 2026-05-06
**Status:** IN PROGRESS
**Goal:** Polish everything for App Store submission — gym, social, modules, home, UI

---

## CRITICAL BUGS (fix first)

### BUG-1: Train section module cards not tappable
- `SportBentoCard` has `frame(width: 170, height: 170)` which may not fill grid cell, cutting off touch target
- `ModuleEntrySheet` sheet modifier stacks with `showPerformance` sheet — may conflict on older iOS
- **Fix:** Remove fixed width on SportBentoCard, use `.frame(maxWidth: .infinity)` instead; ensure sheet state is independent

### BUG-2: Session report card auto-dismisses in < 1 second
- The post-session report (e.g., `StrikingSessionReportView`) gets a `.onDisappear` or a `Task.sleep` that fires too fast
- **Fix:** Find the dismiss timer in each module's view/ViewModel and increase to at least 5 seconds or remove the auto-dismiss entirely — user should tap "Done" to dismiss

### BUG-3: AI Coach + Pose detection only works in Grappling Lab
- Vision `VNDetectHumanBodyPoseRequest` works for all 4 modules but the feedback pipeline may only pipe through GrapplingViewModel
- CoachingEngine is initialized and fed observations only in Grappling
- **Fix:** Ensure all 4 module ViewModels call `CoachingEngine.shared.processPose(_:sport:)` on each VNHumanBodyPoseObservation frame; ensure AVSpeechSynthesizer TTS coach voice fires for all 4

### BUG-4: Calendar heatmap starts from beginning (12 weeks ago, all empty)
- `GymWorkoutHistoryView` calendar starts at `today - 83 days` and shows all cells, but UI renders them in order (oldest first) making user scroll to find today
- **Fix:** Reverse the rendering so most recent week appears first (or scroll position defaults to end)

### BUG-5: FAB (+ button) in Routines view is under the profile tab bar
- The FAB sits at the bottom with `.padding(.bottom, 34)` but the tab bar adds ~83pt on iPhone with home indicator
- **Fix:** Add tab bar height to FAB bottom padding (use `.safeAreaInset(edge: .bottom)` pattern)

### BUG-6: Cancel button in workout session is not red / not responding
- The cancel button in `ActiveGymSessionView` has incorrect button style or `.disabled(true)` 
- **Fix:** Make cancel button `.foregroundStyle(.red)`, give it a red background tint, ensure action fires

### BUG-7: Recent Activity in Home is not clickable
- `HomeView` recent activity rows use `Text` only — no `Button` or `NavigationLink` wrapping them
- **Fix:** Wrap each session row in a `NavigationLink` that goes to `GymWorkoutDetailView` or a new `SessionDetailView`

---

## GYM SECTION — COMPLETE OVERHAUL

### GYM-1: Clickable Streak Badge
- Current: Streak shows a number with no interaction
- Want: Tap streak → sheet or navigation to streak detail view showing calendar, longest streak, current streak, best performance days, weekly targets
- **Implement:** `StreakDetailSheet` — full calendar heatmap, stats, motivational copy, milestone progress

### GYM-2: Multiple Splits / Plans Management
- Current: Can only have "My Split" — no way to create multiple named programs
- Want: Manage multiple named splits (e.g. "PPL", "Upper/Lower", "5/3/1 Wendler")
- **Implement:** 
  - `WeeklyPlanListView` already exists but needs a prominent entry point from GymHomeView
  - Add "Manage Plans" button in the active plan card
  - Show all plans with active/inactive status
  - Tap to preview or activate
  - Swipe to delete

### GYM-3: Split Editor — Add Custom Routines
- Current: Split editor lets you pick a day label and select from existing routines only (seeded ones)
- Want: In the split editor, when assigning a day, be able to:
  1. Pick from existing routines
  2. Create a new routine inline without leaving the split editor
  3. Remove assigned routine from a day
- **Implement:** In `WeeklyPlanEditorView`, the day slot picker sheet should show `ExercisePickerView`-style routine picker + a "Create New Routine" option at the bottom that pushes `RoutineBuilderView` modally

### GYM-4: Start Workout — Better Flow
- Current: Start Workout shows a card with routines that you can expand but can't change
- Want: Start Workout should ask:
  1. "Continue with today's split?" (shows today's assigned routine from active plan)
  2. "Choose a different routine" (shows all routines)
  3. "Start blank session" (empty)
  4. "Repeat last workout"
- **Implement:** Replace `startWorkoutSheet` with `StartWorkoutPickerSheet` — a bottom sheet with 4 options, each tappable

### GYM-5: Workout History — Redesigned
- Current: History view shows a flat scrollable list with expandable rows but starts at oldest week
- Want:
  - Most recent workouts first, always
  - Each workout row: swipe right = edit/repeat, swipe left = delete (Gmail style)
  - Tap a workout row → full detail sheet: exercises, sets, reps, weights, duration, volume, PRs achieved, notes
  - Filter pills: All / This Week / This Month / Personal Records
  - Stats header: total sessions, total volume, avg session time, longest streak
  - Calendar heatmap: starts from TODAY scrolling backwards (most recent = right side)
- **Implement:** Rewrite `GymWorkoutHistoryView` with:
  - `List` with `.swipeActions` for delete and repeat
  - `NavigationLink` or `.sheet(item:)` for full detail
  - Reversed calendar rendering

### GYM-6: Workout Detail View — Rich Data
- When tapping a past workout, show:
  - Session name / date / duration / total volume
  - Exercises grouped by muscle group
  - Per exercise: each set with weight × reps, 1RM estimate, PR badge if a PR was achieved
  - Performance vs previous: "↑ 12% volume vs last time"
  - Body fatigue indicator
  - Export/Share button (generates a share card)
- **Implement:** Expand `GymWorkoutDetailView` with these sections

### GYM-7: Exercise Library — 200+ Exercises
- Current: 63 exercises seeded
- Want: Full comprehensive library covering all major gym exercises across all muscle groups and equipment
- Add exercises for: neck, rear delts, serratus, tibialis, adductors, hip flexors, external rotators
- Add Olympic lifts: clean and jerk, snatch variations, push jerk
- Add sport-specific: box jump, broad jump, med ball throws, sled push
- Add stretches/mobility: pigeon pose, couch stretch, world's greatest stretch
- Add cardio machines: row erg, ski erg, assault bike, treadmill, stairmaster
- Total target: 200+ exercises with full instructions
- **Implement:** Expand `seedExerciseLibraryIfNeeded()` in `GymRepository.swift` (reset seed flag with a version number so new exercises get added on update)

### GYM-8: Progress View — 3D + Animations
- Current: Line charts and volume bars (very basic)
- Want:
  - 3D rotating body diagram showing which muscle groups were trained (highlight muscles trained this week in accent colors)
  - Animated progress rings for weekly goals
  - Confetti/burst animation on PR achievement
  - Volume chart with area fill gradient
  - Strength progression per lift (1RM over time)
  - Body composition section (link to measurements from ProfileView)
  - Estimated 1RM calculator card
- **Implement:** Redesign `GymProgressView` with Canvas-based body diagram, SwiftUI Charts with animations, phase animations on appear

### GYM-9: Color Scheme / UI Redesign
- Current: Too much plain dark gray, too uniform
- Want: Premium feel — layered cards, gradient accents, sport color theming
- **Design direction:**
  - Use glassmorphism for card surfaces: `.ultraThinMaterial` instead of flat `kineticsDark`
  - Add subtle grain texture overlay on headers
  - Each muscle group / sport gets its own gradient identity
  - Metric values: large, tabular, SF Pro Rounded Heavy
  - Use radial gradients for hero cards
  - Add micro-animations: number counters animate on appear, rings animate fill, cards scale on tap

---

## SOCIAL FEED — STRAVA POST COMPOSER

### FEED-1: Full Strava-Style Post Composer
Current `PostComposerView` has: text box + sport chip + mood + photo picker (basic)

**Strava features to replicate (full spec):**
1. **Activity header** — auto-populated if coming from a completed workout:
   - Activity type icon + sport name
   - Duration badge
   - Distance / volume badge
   - Date/time
2. **Title field** — bold, large text input (required, auto-suggested from activity type + time of day: "Morning Run", "Evening Lift")
3. **Description field** — multi-line, lighter text, optional
4. **Photos** — up to 10 photos, drag to reorder, pinch to crop, caption per photo
5. **Map preview** — if GPS session exists, shows route map as card (tappable to expand full map)
6. **Workout stats block** — auto-populated cards:
   - Total Volume (kg)
   - Sets Completed
   - PRs Achieved (badge count)
   - Duration
   - Estimated Calories
7. **Tag Athletes** — search bar that searches Firebase users, adds @mention tag
8. **Club/Group** — future feature (show placeholder)
9. **Privacy selector** — Everyone / Followers Only / Private (with icon)
10. **Kudos Preview** — "Share to see who gives you kudos first" teaser
11. **Post button** — prominent, accent colored, with loading state
12. **Discard confirmation** — "Are you sure? Your post will be lost" if navigating back with content

**Implement:** Full rewrite of `PostComposerView` with all above sections, matching Strava's visual hierarchy

### FEED-2: Feed Cards — Clickable Throughout
- Tapping the athlete name/avatar → `UserProfileView`
- Tapping the sport icon → filter feed to that sport
- Tapping the workout stats block → opens full workout detail
- Tapping the map thumbnail → full-screen map
- Tapping the photo → full-screen photo viewer

### FEED-3: Activity Feed (Home Tab)
- Current: "Recent Activity" section in Home shows flat rows
- Want: Mini Strava-style activity strip — horizontal scroll of recent activities from people you follow
- Tap → goes to full FeedView with that activity highlighted

---

## HOME TAB IMPROVEMENTS

### HOME-1: Readiness Card — What Is It?
**What readiness is:** A 0–100 composite score computed from:
- Sleep quality (HealthKit: 0–100 pts based on duration vs 8hr target)
- HRV trend (Heart Rate Variability — higher = better recovery)
- Resting HR vs baseline (lower than baseline = well rested)
- Days since last rest day (training load management)
- Step count (general activity level)
- Missing data defaults to 70 (neutral)

**Make it clickable:** Tap readiness card → `ReadinessDetailSheet` showing:
- Score breakdown (each sub-score with explanation)
- "What this means" natural language interpretation
- Historical readiness chart (7 days)
- Recovery tips based on score (< 50 = rest day recommendation, > 80 = "ready to push hard")

### HOME-2: Community Section → Clickable to Feed
- Current: Shows a static "Community" card
- Want: Tapping it navigates to `FeedView` tab

### HOME-3: Streak → Clickable Detail
- Tap streak badge → `StreakDetailSheet`:
  - Current streak count (large, animated)
  - Longest ever streak
  - "You've trained X days out of the last 30"
  - Weekly training calendar
  - Milestone next unlock

### HOME-4: Badges — Accessible + Profile Integration
- Current: Badges buried in `HomeAchievementsView`, hard to find
- Want:
  - Badges section on ProfileView — show earned badges in a grid
  - Home quick-access: row of 3-4 most recent badges earned
  - Tapping any badge → full achievements sheet
  - Locked badges show grayed out with progress (e.g., "42 / 100 sessions for Century")
  - Earned badge = full color with earned date
  - Badge notification: when a badge is earned mid-session, show a banner

### HOME-5: Next Milestone — Clickable
- The "Next Milestone" component on HomeView should be a `Button` that opens milestone detail
- Show: what the milestone is, current progress, how to earn it faster, what reward it unlocks

### HOME-6: Recent Sessions — Full Detail on Tap
- Each activity in the Recent Activity section on Home should open:
  - Sport/gym sessions → full session detail (metrics, duration, tips AI generated)
  - GPS runs → route map + pace analysis

---

## MODULE IMPROVEMENTS

### MODULE-1: All 4 Modules — Coaching Layer
- **Striking Clinic:** 
  - Track hip rotation speed (degrees/second)
  - Track shoulder rotation (kinetic chain detection)
  - Strike velocity in mph (wrist displacement ÷ frame time)
  - Combo detection: jab-cross-hook sequences
  - Coach voice: "Lead with your hips" / "More hip rotation" / "Good kinetic chain"
  
- **Grappling Lab:**
  - Already mostly working
  - Add: submission attempt detection (triangle, armbar, rear naked choke setups)
  - Add: base width measurement (feet distance)
  - Coach voice: "Protect your neck" / "Drop your hips" / "Good base"

- **Iron Tracker:**
  - Bar path deviation from vertical (the more vertical the better for most lifts)
  - Bilateral asymmetry (left vs right side loading)
  - Rep tempo (eccentric/concentric timing)
  - Form breakdown alerts (butt wink on squat, bar drift on deadlift)
  - Coach voice: "Keep bar over mid-foot" / "Symmetric push"

- **Wall Beta:**
  - Hip-to-wall proximity gauge
  - Dynamic movement detection (dyno arcs)
  - Time-on-hold tracking per position
  - Coach voice: "Hips to wall" / "Trust your feet"

### MODULE-2: Session Report — Persist and Make Accessible
- Session report card must NOT auto-dismiss
- After session ends, save a full `SessionResult` to Firestore
- The report stays on screen until user taps "Done" or "Share to Feed"
- "Share to Feed" pre-populates the Strava-style `PostComposerView` with session data
- Tap "Done" → go back to Train tab
- Recent Activity in Home tapping → show this same report

---

## DESIGN ASSET PROMPTS (AI Generation)

### App Icon (1024×1024) — Midjourney Prompt:
```
Ultra premium iOS app icon, dark background (#0D0D0D). Minimalist glowing human 
figure in motion - abstract geometric lines forming a sprinting/dynamic athlete pose. 
Electric blue gradient glow (#00C2FF) with neon green sparks (#39FF14). The figure 
should feel like pure energy and kinetic motion. No text. Perfect square composition. 
Style: Nike brand meets futuristic HUD. Ultra high detail. Professional App Store icon.
--ar 1:1 --v 6 --quality 2 --style raw
```

### Sport Module Cards — Background Illustrations (4 images):
**Striking (boxing/MMA):**
```
Abstract dark background illustration showing a boxer or martial artist silhouette 
with motion blur and kinetic energy lines in electric blue. Biomechanics-style 
skeleton overlay visible. No text. For an iOS app card background. Dark, moody, 
powerful. Electric blue and white glow. 16:9 crop.
```

**Grappling (BJJ/Judo):**
```
Abstract illustration of two grappling figures in fluid motion, dark background, 
neon green energy lines showing center of mass and leverage vectors. Technical 
biomechanics aesthetic. No text. For an iOS card. Dark and precise.
```

**Iron Tracker (Powerlifting):**
```
Abstract illustration of a barbell being pressed upward by a powerful figure, 
motion lines showing bar path trajectory in bright orange. Technical overlay 
showing angle vectors. Dark background, premium gym aesthetic. No text.
```

**Wall Beta (Climbing):**
```
Abstract illustration of a climber on a rock face reaching for a hold, purple 
and violet energy lines showing body tension and center of mass. Dynamic, flowing 
composition. Dark background. Technical biomechanics feel. No text.
```

### Onboarding Illustrations (6 steps) — Stable Diffusion / DALL-E Prompts:
All should share the style: "Dark background, electric blue neon glow, clean minimalist 
illustration, iOS app aesthetic, no text, white and blue color palette"

Step 1: "Welcome" — Glowing phone showing skeleton overlay on athlete
Step 2: "Modules" — 2x2 grid of sport silhouettes
Step 3: "Video Analysis" — Phone recording athlete with AI analysis overlay
Step 4: "AI Coach" — Abstract neural network connecting to athlete figure
Step 5: "Community" — Connected athlete figures on a social feed
Step 6: "You're Ready" — Single glowing trophy or flame icon

### Logo / Wordmark:
```
SF Pro Rounded Bold, all caps: "KINETICS"
Letter spacing: +8%
Color: Pure white with an electric blue (#00C2FF) dot or spark accent after the K
Size: 40pt on dark background
No additional design elements needed — typography alone is the mark
```

---

## IMPLEMENTATION ORDER

### Phase 1 — Critical Fixes (this session, parallel agents):
1. Train module card tapping
2. Session report auto-dismiss
3. AI coach all 4 modules
4. FAB button overlap

### Phase 2 — Gym Overhaul (this session, parallel agents):
5. Exercise library 200+
6. Start Workout flow redesign
7. Workout history redesign (swipe delete, scroll position)
8. Clickable streak + badges
9. Splits management improvements

### Phase 3 — Social + Home (this session, parallel agents):
10. Strava post composer
11. Readiness card detail
12. Home recent activity clickable
13. Badges on profile

### Phase 4 — Visual Upgrade:
14. Color system upgrade (glassmorphism, gradients)
15. Progress view 3D body + animations
16. Gym module illustrations/icons

---

## COLOR SYSTEM UPGRADE (from flat to premium)

### Current (too flat):
- Background: #0D0D0D
- Surface: #1A1A1A (kineticsDark)
- Blue: #00C2FF

### Upgraded (layered, premium):
- Background layer 0: #080808 (deeper black)
- Surface layer 1: Color(red:0.1, green:0.1, blue:0.12) — very slight cool tint
- Glass surface: .ultraThinMaterial (Apple glass effect)
- Overlay: .regularMaterial for sheets
- Blue stays: #00C2FF — it's distinctive, don't change
- Green changes: #00FF87 (slightly cooler, more modern)
- Add: electric violet #7B2FFF for premium features
- Gold: #F5C842 (richer than current amber)
- Success: #23D160 (brighter green for confirmations)
- Danger: #FF3A5C (punchier red)

### Typography upgrade:
- Hero numbers: `.system(size: 48+, weight: .black, design: .rounded)` — already good
- Add `.monospacedDigit()` to all metric counters (prevents layout jumping)
- Tracking values: section headers at +2.5, body at 0

---

## STRAVA ANALYSIS (for reference)

What Strava's post composer has that we need to clone:
1. Auto-generated activity title (based on sport + time of day)
2. Large title field (editable, bold)
3. Description field (lighter, multi-line)
4. Automatically attached workout stats (not manual — auto from session data)
5. Route map card if GPS was used
6. Photo carousel with crop and reorder
7. Tag athlete (@mention search)
8. Privacy control (who can see this)
9. "Post" as primary CTA — large, colorful button
10. Discard warning if navigating back with content

What Strava has that we can skip for now:
- Clubs / Groups
- Segment challenges (future)
- Equipment tracking (future)
- Perceived exertion (could add as mood picker — already have this)
