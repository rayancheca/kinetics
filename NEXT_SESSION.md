# KINETICS — Master Plan for Session 3+
**Written:** 2026-04-29  
**Purpose:** Complete roadmap for every feature, design decision, and technical spec needed to turn Kinetics from a tech demo into a daily-use app. Read this at the start of every session.

---

## SECTION 1 — HONEST ASSESSMENT: WHAT IS THE APP RIGHT NOW?

### What it actually does today
You point your camera at yourself, a skeleton appears over your body, and some numbers update in real time. When you stop, it saves "session lasted 47 seconds, average velocity 12 mph" to Firebase. That's it.

It doesn't tell you if 12 mph is good or bad. It doesn't tell you what to do differently next time. It doesn't compare this session to your last one. It doesn't explain what "kinematic chain score" even means. There's no onboarding that explains any of this. The activity log is a receipt, not a report.

### What the app SHOULD be
An AI coaching layer on top of your body's movement — the kind of detailed, specific, personalized feedback you'd only get from an elite coach standing next to you. Then, a social layer so your training connects you to others.

The product pitch in one sentence: **"Point your camera at yourself. Get coached."**

### The three biggest problems right now

**Problem 1: There is no "aha moment"**
The first time a user opens this app they see: a grid of 4 cards, a Sign In button, and nothing else. They tap Striking Clinic, a camera opens, dots appear on their body. They don't know if they're doing it right, what the numbers mean, whether this is even working. They close the app and never return.
FIX: Onboarding flow, in-session guidance text, post-session "here's what we found" report.

**Problem 2: The data dies at the session screen**
Every session generates rich data — velocity curves, angle distributions, hold time heatmaps — and all of it gets thrown away except 5 numbers written to Firestore. The user never sees any of it after they close the session view.
FIX: Post-session report screen. Rich activity log drill-down. Progress charts.

**Problem 3: The app doesn't know what sport looks like**
It detects joints but doesn't interpret them in a way a human would understand. "Hip proximity: 0.73" is meaningless. "Your hips were close to the wall 73% of the time — that's solid technique, most beginners score below 50%" is useful.
FIX: Contextualised coaching copy, benchmarks, thresholds that map numbers to human language.

---

## SECTION 2 — THE FULL PRODUCT VISION

### What Kinetics becomes
A three-layer app:

**Layer 1 — AI Movement Coach** (the 4 existing modules, massively improved)
Point camera → real-time skeleton + live metric coaching → post-session detailed report with AI tips → progress tracked over time → personal records celebrated → weekly summary pushed as notification.

**Layer 2 — Strava for all sports** (a full GPS/activity tracking section)
Run, walk, ride, hike with full GPS route, pace, heart rate, elevation, step count, cadence. Post-workout map card shared to feed. Segment leaderboards. Challenges.

**Layer 3 — Social fitness network**
Friend graph, follow system, activity feed, kudos (likes), comments, DMs, challenges. Your training visible to people who care about it.

### Navigation structure (final app)
```
Tab Bar (bottom):
├── Home (dashboard + recent activity)
├── Train (the 4 AI modules + new modules)
├── Track (Strava clone: GPS activities)
├── Feed (social: friends' activities, kudos, comments)
└── Profile (your stats, history, settings, friends)
```

Sidebar (swipe from left on home):
- Your profile
- Settings
- Connected apps (Health, Strava import)
- Privacy controls
- Notifications

---

## SECTION 3 — LOGO AND VISUAL IDENTITY

### Current state
No logo. Generic SF Symbols icons for each module. The app looks like an Xcode template.

### Direction: Option A — "Kinetic Force" (Recommended)
- Mark: A stylized human figure mid-motion, abstracted into 3-4 geometric lines suggesting a body in movement. Think: the Olympics pictogram style but electric and modern.
- Color: The current electric blue (#00C2FF) stays as primary. Add deep midnight black (#080C10) as background, pure white for text, neon green (#39FF14) for live metrics only.
- Wordmark: "KINETICS" in a wide-tracking geometric sans-serif (similar to Neue Haas Grotesk or Inter tight). All caps. Letter-spacing at 0.15em.
- Feel: Apple Fitness+ meets Nike Training Club. Premium, dark, performance-oriented.

### Direction: Option B — "Signal"
- Mark: A sine wave / heartbeat line that morphs into a running figure. Clean, medical + athletic.
- Color: White + electric blue on jet black. No neon green — use amber (#FFB800) for alerts.
- Feel: Whoop meets Strava. Data-driven, precise.

### Direction: Option C — "Neural"
- Mark: A neural network node pattern forming the shape of a head/brain. Hexagonal nodes connected by lines.
- Color: Deep purple (#6B21A8) + electric blue gradient. Gold (#F59E0B) for achievements.
- Feel: Futuristic AI lab meets fitness app.

### HOW TO GET THE LOGO BUILT — Claude Design Workflow

**Step 1: Generate concepts with AI design tools**

Use these exact prompts in Midjourney or DALL-E 3:

```
Prompt A (App Icon):
"iOS app icon for a sports AI coaching app called Kinetics. Dark background #080C10. 
Geometric abstract human figure in motion made of clean vector lines. Electric blue 
#00C2FF glow. Rounded square format. Minimal. No text. Style: Apple Fitness+ meets 
NASA mission patch. Ultra clean, modern, professional."

Prompt B (Wordmark):
"Clean typographic logo for KINETICS sports app. All caps geometric sans-serif 
letterforms. Electric blue #00C2FF on black. Wide letter spacing. A subtle motion 
blur or speed lines on the K only. Vector style, no gradients except on the K."

Prompt C (Alternative mark):
"Abstract logo mark for a real-time motion capture sports coaching app. A human 
silhouette deconstructed into 5-7 geometric lines suggesting movement. Electric blue 
and neon green. Dark background. Clean, modern, scalable to 29px icon size."
```

**Step 2: Use Claude (claude.ai with image upload)**
Upload your 3 best concepts from Midjourney and write:
```
"I need you to help me refine this into a final app icon for iOS. The app is called 
Kinetics — it uses computer vision to coach athletes in real time. 
Current design: [paste image]. Please:
1. Critique what works and what doesn't
2. Suggest specific shape/color changes
3. Describe the exact final version in enough detail that a designer can execute it
4. Write me an SVG code version of a simplified mark based on your critique"
```

**Step 3: Get SVG from Claude and paste into Xcode**
Claude will give you SVG code. Convert it to a PNG using:
```bash
# Install rsvg-convert (brew install librsvg)
rsvg-convert -w 1024 -h 1024 logo.svg -o AppIcon-1024.png
```

Then drag into `Assets.xcassets → AppIcon` in Xcode. Done.

**Step 4: Ask Claude to write the SwiftUI logo view**
```
"Write me a SwiftUI View called KineticsLogoView that renders this logo mark 
programmatically using Canvas and Path. The mark is: [describe what you settled on]. 
It should animate on appear with a draw-on effect using trim()."
```

---

## SECTION 4 — MODULE-BY-MODULE OVERHAUL PLAN

### What every module needs to add

Every module currently has:
- `ModuleView.swift` — camera + overlay + metrics panel
- `ModuleViewModel.swift` — session lifecycle + frame processing
- `ModuleAnalytics.swift` — the math

Every module needs to gain:
- `ModuleOnboardingView.swift` — what is this, how to set up, what to expect
- `ModuleSessionReportView.swift` — post-session breakdown screen
- `ModuleProgressView.swift` — charts, personal records, trend over time
- Rich data model in `SessionResult` — store full metric arrays, not just averages

---

### MODULE 1: STRIKING CLINIC — Full Spec

**What it should tell the user:**

ONBOARDING (show once, can revisit from ⓘ button):
```
"STRIKING CLINIC
How it works: Point the camera so your full body is visible. 
Throw your strikes normally. We track 3 things:

① STRIKE VELOCITY — how fast your fist or foot is moving at impact
   Measured in mph. Elite fighters: 25-35 mph. Beginners: 8-15 mph.

② KINEMATIC CHAIN — are your hips loading before your shoulder fires?
   Score 0-100. Perfect chain: hips rotate first, shoulders follow, arm extends last.
   A score below 60 means your upper body is doing all the work. That costs you power.

③ HIP-SHOULDER SEPARATION — the 'coil' that stores energy before the strike
   Great strikers open 35°+ between hips and shoulders before releasing.
   Below 20°: you're arm-punching. 20-35°: developing. 35°+: elite."
```

IN-SESSION REAL-TIME COACHING (text line below the metrics panel):
- velocity < 10 mph: "Engage your rear foot — push off the ground before rotating"
- kinematic_chain < 50: "Hips first! Rotate your hips before your shoulder moves"
- hip_shoulder_sep < 20°: "Load up — twist further before releasing the strike"
- all metrics good: "Great chain — feel that hip-to-shoulder sequence"

POST-SESSION REPORT (new screen, appears after stopping):
```
━━━━━━━━━━━━━━━━━━━━━━━
YOUR SESSION — STRIKING CLINIC
April 29 · 2:47 total time · 23 strikes detected
━━━━━━━━━━━━━━━━━━━━━━━

⚡ TOP STRIKE VELOCITY
   47.3 mph  ← personal best! (was 41.2 mph)
   Average: 31.4 mph  +8.2 mph vs last session ↑

🔗 KINEMATIC CHAIN SCORE
   74/100  (+6 vs last session)
   Your hips are loading correctly on 68% of strikes

📐 HIP-SHOULDER SEPARATION
   29° average  (Goal: 35°+)
   Best strike: 38° at 0:43

━━ AI COACHING NOTES ━━━━━━━━━━━━━

💡 Focus Area: Your chain breaks down on jabs
   On your crosses, chain score is 81 — excellent.
   On jabs, it drops to 61 — you're initiating with your shoulder.
   Fix: Think "hip-tap" before every jab. Initiate the jab by 
   tapping your lead hip forward first.

💡 Velocity spike at 0:43
   Your fastest strike came immediately after a 4-second pause.
   Pattern: rest → explosive strike. This is your power window.

━━ NEXT SESSION GOAL ━━━━━━━━━━━━━
→ Target: Hip-shoulder separation above 32° average
→ Try: 3 sets of 10 jabs focusing only on hip initiation
```

**Firestore data model additions (SessionResult):**
```
// Add to SessionResult
strikeEvents: [{timestamp: Double, velocity: Double, chainScore: Double, hipSep: Double}]
personalBests: {maxVelocity: Double, maxChainScore: Double, maxHipSep: Double}
sessionNumber: Int  // which session this is for this module
```

---

### MODULE 2: GRAPPLING LAB — Full Spec

**Onboarding copy:**
```
"GRAPPLING LAB
What we measure:

① CENTER OF MASS — where your body weight is concentrated
   The dot on screen is your CoM. It must stay inside your base (feet/knees on floor).
   When CoM exits your base, you're about to be swept or thrown.

② KUZUSHI INDEX — how much control you have over your opponent's balance
   (Measured via YOUR body — a forward-tilted spine with low hips = good kuzushi position)
   Scale: 0-100. Judo throws work best above 70.

③ BASE STABILITY — are your feet/knees creating a solid platform?
   When base is unstable, any attack can take you down.

④ SPINE ANGLE — upright vs. forward-bent
   For throws: lean forward 15-30°. For guard: stay upright.
   For defensive posture: upright with tight elbows."
```

**Post-session report specifics:**
- Heatmap: where was your CoM throughout the session (X/Y grid)
- Base stability: % of time base was stable
- Ground time: % of session you spent on the ground vs standing
- Kuzushi index distribution: bar chart of how often you were in high-kuzushi position

**AI coaching tips for Grappling:**
- kuzushiIndex < 40: "Your base is too wide and upright. Bend your knees, lower your hips, and lean 20° forward to create kuzushi pressure."
- isGroundPosition 80%+ of session: "You spent most of the session on the ground. Work on getting back to your feet — use bridging and hip escape movements."
- hipElevation low in ground: "Your hips are flat. Bridge more aggressively — drive your hips up to create space for escapes."
- centerOfMass exits base frequently: "Your CoM is leaving your base. Widen your stance by 6 inches and keep your weight low."

---

### MODULE 3: IRON TRACKER — Full Spec

**Onboarding copy:**
```
"IRON TRACKER
Set up: Mount your phone horizontally at hip height, 6 feet away, side-on to your lift.
This gives us the clearest view of your bar path.

What we track:

① BAR PATH — the line your barbell travels through the lift
   Perfect squat: vertical bar path directly over mid-foot
   Perfect deadlift: bar scrapes shins, travels vertically
   Any deviation = wasted energy = reduced load capacity

② VELOCITY (VBT) — how fast the bar is moving
   Velocity Based Training uses bar speed to determine effort level:
   > 0.8 m/s = speed/power zone
   0.5-0.8 m/s = hypertrophy zone  
   < 0.5 m/s = max strength zone

③ BILATERAL SYMMETRY — left vs. right arm speed
   100% = perfectly even. Below 90% = one side is dominant.
   Asymmetry above 10% during pressing = injury risk.

④ TECHNIQUE ALERTS
   Butt wink: lumbar rounds at the bottom of a squat → disc pressure
   Knee cave: knees collapse inward → ACL/MCL risk"
```

**Post-session report:**
- Bar path graphic: replay the actual path drawn on a neutral background
- Velocity chart: line graph of velocity over time for each rep
- Symmetry gauge: left vs right as a split bar
- Technique alert log: exact timestamp + what was detected
- Rep-by-rep table: rep number, velocity, symmetry, alerts

---

### MODULE 4: WALL BETA — Full Spec

**Onboarding copy:**
```
"WALL BETA
What we analyze:

① HIP PROXIMITY — how close your hips are to the wall
   This is the single most important technique metric in climbing.
   Close hips = weight on your feet = arms used for balance only.
   Far hips = you're pulling with your arms = pump in 30 seconds.
   Score: 0-1. Below 0.4: your hips are too far. Above 0.7: elite technique.

② SAG DETECTION — when your hips drop and pull you off the wall
   Sag happens when your arms tire and your core disengages.
   We alert you when sag is detected mid-climb.

③ DYNO ARCS — for dynamic movement, we trace your body's flight path
   A good dyno: compact arc, controlled reach, solid catch.
   We overlay the arc so you can see if you're overshooting or under-rotating.

④ HOLD TIME — how long you're static at each position
   Counting rest time per move helps you understand route economy.

Set up: Place phone 6-8 feet back from the wall, landscape, at your hip height."
```

---

## SECTION 5 — NEW SPORT MODULES TO ADD

### Module 5: Sprint Mechanics
**What it does:** Detects acceleration mechanics during sprints. Tracks drive angle (forward lean), arm swing tempo, stride length estimation, and deceleration pattern.
**Who uses it:** Sprinters, soccer/basketball/football players, any speed athlete.
**Camera setup:** Side-on, 20 feet back, landscape orientation.

Key metrics:
- Drive angle: forward lean during acceleration phase (optimal: 45° at 10m, 80° at 30m)
- Arm swing: symmetric or not, tempo in swings/second
- Cadence: estimated steps per second from ankle joint oscillation
- Transition point: when drive phase ends and upright sprint begins

### Module 6: Basketball Shot Form
**What it does:** Analyzes your shooting form — elbow alignment, wrist snap angle, release point, follow-through hold time.
**Camera setup:** Side-on to the basket, 10 feet back.

Key metrics:
- Elbow tuck: is elbow under the ball or flared out?
- Release angle: wrist angle at moment of release (optimal: 55-70°)
- Follow-through: how long the wrist holds follow-through position
- Shot consistency: how similar is each shot's form (standard deviation of key angles)

### Module 7: Golf Swing
**What it does:** X-factor (hip-shoulder separation at top of backswing), spine angle at address vs impact, wrist hinge timing, follow-through balance.
**Camera setup:** Behind the player, face-on, or down-the-line.

Key metrics:
- X-factor at top: hip-shoulder separation in degrees (elite: 45°+)
- Spine tilt at address vs impact
- Head movement: how much head position shifts during swing
- Weight transfer: hip shift timing left-to-right

### Module 8: Tennis Serve
**What it does:** Trophy position detection, shoulder rotation, racket drop depth, contact point height, follow-through direction.
**Camera setup:** Behind the server, landscape.

### Module 9: Yoga/Flexibility
**What it does:** Joint range-of-motion measurement in static poses. Tracks flexibility progress over time — can you reach deeper into warrior pose than you could last month?
**Key value prop:** Progress is invisible in yoga without measurement. We make it visible.

---

## SECTION 6 — STRAVA COMPLETE CLONE SPECIFICATION

This is its own tab called **"TRACK"** in the tab bar.

### Core GPS Activity Recording

**File structure:**
```
Kinetics/Modules/Track/
├── TrackView.swift                 ← tab entry, activity type selection
├── ActiveWorkoutView.swift         ← full-screen during recording
├── WorkoutSummaryView.swift        ← post-workout report
├── WorkoutHistoryView.swift        ← all past GPS activities
├── WorkoutDetailView.swift         ← tapped activity → full detail
├── RouteMapView.swift              ← MapKit route overlay
├── SegmentView.swift               ← leaderboard for known segments
├── TrackViewModel.swift            ← all recording state
├── WorkoutRepository.swift         ← Firestore CRUD
└── TrackAnalytics.swift            ← pace, HR zones, elevation
```

**Activity types:**
- Run (outdoor + treadmill)
- Walk
- Ride (outdoor + indoor)
- Hike
- Swim (no GPS, manual lap entry)
- Ski / Snowboard

**During recording UI (full-screen, similar to Apple Workout app):**
```
━━━━━━━━━━━━━━━━━━━━━━━
[Live map showing route so far]

DISTANCE          PACE            TIME
5.24 km           4:32/km         23:47

HEART RATE     ELEVATION     CADENCE
142 bpm          +84m           172 spm

[Pause] [Stop]
━━━━━━━━━━━━━━━━━━━━━━━
```

Auto-splits: every km/mile, show a notification with split pace.
Auto-pause: when speed drops below 0.5 m/s for 3+ seconds.
Background tracking: `CLLocationManager` with `allowsBackgroundLocationUpdates = true`.

**Post-workout summary:**
```
━━━━━━━━━━━━━━━━━━━━━━━
RUN · April 29, 2026
━━━━━━━━━━━━━━━━━━━━━━━
[Full route map with color-coded pace overlay]

10.2 km     48:32    4:45/km avg
Distance    Time     Avg Pace

Fastest km: km 7 — 4:12/km
Elevation: +147m / -134m
Avg HR: 158 bpm · Max: 181 bpm
Calories: 612 kcal (HealthKit)

HEART RATE ZONES
[Colored bar] Z1 8% Z2 22% Z3 41% Z4 25% Z5 4%

PACE CHART
[Line chart of pace per km, x=km, y=pace]

SPLITS TABLE
km 1: 4:58 · km 2: 4:51 · km 3: 4:47 ...

ACHIEVEMENTS UNLOCKED 🏆
• Longest run ever
• First sub-4:30/km km

━━ SHARE ━━━━━━━━━━━━━━
[Share Card image → Instagram/Messages/AirDrop]
━━━━━━━━━━━━━━━━━━━━━━━
```

### HealthKit Integration

**Required permissions (add to Info.plist):**
```
NSHealthShareUsageDescription: "Kinetics reads your heart rate and step count to enhance workout tracking."
NSHealthUpdateUsageDescription: "Kinetics writes your workouts to Apple Health for tracking."
```

**Data to read from HealthKit:**
- `HKQuantityType.heartRate` — live HR during workout
- `HKQuantityType.stepCount` — step count
- `HKQuantityType.activeEnergyBurned` — calories
- `HKQuantityType.vo2Max` — fitness level

**Data to write to HealthKit:**
- `HKWorkout` — each GPS activity as a workout
- `HKQuantityType.distanceWalkingRunning` — distance

**HealthKit service file:** `Kinetics/Core/Services/HealthKitService.swift`
```swift
actor HealthKitService {
    static let shared = HealthKitService()
    func requestAuthorization() async throws
    func startHeartRateQuery(handler: @escaping (Double) -> Void)
    func stopHeartRateQuery()
    func saveWorkout(_ result: WorkoutResult) async throws
    func fetchStepCount(for date: Date) async throws -> Int
}
```

### Firebase Data Model for Workouts

```
users/{uid}/
  workouts/{workoutId}/
    type: String              // "run", "ride", "walk"
    startedAt: Timestamp
    duration: Double          // seconds
    distance: Double          // meters
    avgPace: Double           // seconds per km
    avgHeartRate: Double
    maxHeartRate: Double
    elevationGain: Double
    calories: Double
    routePolyline: String     // encoded polyline (Google Maps format)
    splits: [{km: Int, pace: Double, heartRate: Double}]
    hrZones: {z1: Double, z2: Double, z3: Double, z4: Double, z5: Double}
    achievements: [String]
    isPublic: Bool
    kudosCount: Int
    commentCount: Int
```

---

## SECTION 7 — SOCIAL NETWORK SPECIFICATION

### User Profile

**Firestore model:**
```
users/{uid}/
  profile/
    displayName: String
    username: String          // @handle
    bio: String
    avatarURL: String         // Firebase Storage
    sports: [String]          // ["mma", "bjj", "powerlifting"]
    followerCount: Int
    followingCount: Int
    activityCount: Int
    isPublic: Bool
    joinedAt: Timestamp
    
  followers/{followerId}     // subcollection of follower UIDs
  following/{followingId}    // subcollection of following UIDs
```

**Profile screen layout:**
```
[Avatar] [Display Name] [@username]
[Bio text]
[Followers] [Following] [Activities]
Sport tags: MMA · BJJ · Powerlifting

[Edit Profile] [Share Profile]

─── RECENT ACTIVITY ───
[Activity cards]
```

### Follow System

**Files needed:**
- `SocialRepository.swift` — follow/unfollow, fetch followers, fetch following
- `UserSearchView.swift` — search users by name or @handle
- `FollowersView.swift` — list of followers/following with follow button

**Firestore operations:**
```
// Follow
users/{currentUID}/following/{targetUID} → {followedAt: Timestamp}
users/{targetUID}/followers/{currentUID} → {followedAt: Timestamp}
// Increment counters with FieldValue.increment(1)

// Feed: fetch all activities from following list
// Denormalized: maintain feed/{uid}/feedItems collection
// Populated via Cloud Function when a user posts
```

### Activity Feed

**Structure:**
- Chronological feed of friends' activities
- Each card shows: avatar, name, sport, headline metric, mini map or icon, kudos count, comment count
- "Kudo" button (heart) — one tap, toggles
- Comment thread (up to 5 visible, tap to expand)
- Share button → share card image

**Feed card types:**
1. GPS run/ride (shows mini map + distance/pace)
2. AI coaching session (shows module name + top metric + achievement)
3. Personal record (special highlight card)
4. Challenge completion
5. Streak milestone (7 days active, 30 days active)

### Kudos System
```
activities/{activityId}/kudos/{uid} → {givenAt: Timestamp}
// Denormalized: activityId.kudosCount incremented via Cloud Function
```

### Direct Messages
**Use Firebase Realtime Database (not Firestore) for DMs — lower latency.**
```
dmThreads/{threadId}/
  participants: [uid1, uid2]
  lastMessage: String
  lastMessageAt: Timestamp
  messages/{messageId}/
    senderId: String
    text: String
    sentAt: Timestamp
    read: Bool
```

**Files:**
- `MessagesListView.swift` — all DM threads
- `MessageThreadView.swift` — individual conversation
- `MessagesViewModel.swift` — Realtime Database listener

### Challenges
Weekly auto-generated challenges:
- "Most km run this week"
- "Highest strike velocity this week"
- "Most grappling sessions this week"

**Firestore:**
```
challenges/{weekId}/
  type: String
  metric: String
  participants/{uid}/
    value: Double
    updatedAt: Timestamp
```

---

## SECTION 8 — RICH ACTIVITY LOG SPECIFICATION

### Current state
`SessionHistoryRow.swift` — shows sport icon, date, duration. Tapping does nothing.

### What it must become

**List item (improved):**
```
[Sport icon color] STRIKING CLINIC
Today · 2:47 · 23 strikes

Top velocity: 47.3 mph  ↑ PB   Chain: 74/100
[Tap for full report →]
```

**Tapped → Session Detail Screen (`SessionDetailView.swift`):**
```
━━━━━━━━━━━━━━━━━━━━━━━
STRIKING CLINIC SESSION
April 29, 2026 · 2:47 duration
━━━━━━━━━━━━━━━━━━━━━━━

HIGHLIGHTS
⚡ Personal Best — Max Velocity 47.3 mph
🔥 7-session streak on Striking Clinic

━━ METRICS ━━━━━━━━━━━━

Average Strike Velocity
31.4 mph
[Bar chart: this session vs last 5 sessions]

Kinematic Chain Score  
74 / 100
[Gauge chart, color coded: red/yellow/green zones]

Hip-Shoulder Separation
29° average
[Progress bar: 0° → 35° goal → 38° max seen]

━━ STRIKE TIMELINE ━━━━

[Scrollable timeline showing each strike detected:
 :12 · 28.4 mph · Chain 71
 :18 · 31.2 mph · Chain 68
 :23 · 47.3 mph · Chain 81 ← best strike
 ...]

━━ AI COACHING ━━━━━━━━

💡 Great session — your kinematic chain is improving.
   Your average chain score went from 68 → 74 over 
   the last 3 sessions.

💡 Your best strike (47.3 mph at 0:23) had a 38° 
   hip-shoulder separation. Your worst strikes averaged 
   only 19°. Focus on loading up before every strike.

💡 Next session: Try 3 sets of 8 rear crosses only.
   Focus purely on hip initiation. Ignore power.

━━ SHARE ━━━━━━━━━━━━━━
[Share button → generates square card image]
━━━━━━━━━━━━━━━━━━━━━━━
```

---

## SECTION 9 — SETTINGS AND USER CONTROL

**`SettingsView.swift` — complete spec:**

```
ACCOUNT
  Edit Profile
  Change Email / Password
  Privacy Settings
    - Who can see my activities (Everyone / Friends / Only Me)
    - Show me in search results: ON/OFF
  Notification Settings
    - Push for kudos: ON/OFF
    - Push for comments: ON/OFF
    - Push for friend requests: ON/OFF
    - Weekly summary: ON/OFF
  Sign Out
  Delete Account

TRAINING
  Default unit system: Metric / Imperial
  Distance unit: km / miles
  Pace format: min/km or min/mile
  Heart rate zones: Auto / Manual (enter max HR)

CONNECTED APPS
  Apple Health: Connected ✓ (Manage)
  Strava: Connect (import past activities)
  
APP
  App icon (let user pick alt icons)
  Haptics: ON/OFF
  Sound effects: ON/OFF
  
ABOUT
  Version 1.0.0
  Privacy Policy
  Terms of Service
  What's New
```

---

## SECTION 10 — BUILD ORDER FOR NEXT SESSIONS

### Session 3 (Priority: Make existing modules useful)
**Spawn agents for each file in parallel:**
1. Agent A: `Onboarding/` folder — `ModuleOnboardingView.swift` for all 4 modules
2. Agent B: `SessionReportView.swift` — post-session report screen (generic, parameterized by sport)
3. Agent C: `SessionDetailView.swift` — rich tapped-session drill-down
4. Agent D: Update `SessionResult.swift` — add strikeEvents array, rich metric storage
5. Agent E: `CoachingEngine.swift` — maps metric values to coaching text strings

**Test gate:** After session 3, a user should be able to: start a session, do some reps, end it, see a meaningful report, and understand what they should do next time.

### Session 4 (Priority: Visual identity + navigation overhaul)
1. Agent A: Logo mark as SwiftUI `Canvas` + `Path` view
2. Agent B: Sidebar (`SidebarView.swift`)
3. Agent C: Tab bar restructure (Home / Train / Track / Feed / Profile)
4. Agent D: `SettingsView.swift` complete
5. Agent E: `ProfileView.swift` skeleton

### Session 5 (Priority: Strava GPS tracking — Track tab)
1. Agent A: `HealthKitService.swift` + permissions
2. Agent B: `TrackViewModel.swift` — CoreLocation integration
3. Agent C: `ActiveWorkoutView.swift` — full-screen recording UI
4. Agent D: `WorkoutSummaryView.swift` — post-workout report
5. Agent E: `RouteMapView.swift` — MapKit with pace color overlay

### Session 6 (Priority: Social graph)
1. Agent A: `SocialRepository.swift` — follow/unfollow/search
2. Agent B: `FeedView.swift` — activity feed with kudos
3. Agent C: `UserProfileView.swift` — public profile
4. Agent D: `ActivityFeedCard.swift` — universal card component
5. Agent E: Cloud Functions setup for feed denormalization

### Session 7 (Priority: New modules)
Spawn one agent per module:
1. Sprint Mechanics
2. Basketball Shot Form
3. Golf Swing

### Session 8 (Priority: DMs + Challenges)
1. Messaging (Firebase Realtime DB)
2. Weekly challenges system
3. Notification service

---

## SECTION 11 — COMPLETE FILE LIST TO CREATE

New files needed (does not include existing files):

```
Kinetics/
├── Core/
│   ├── Services/
│   │   ├── HealthKitService.swift        ← HealthKit actor
│   │   ├── LocationService.swift         ← CoreLocation actor
│   │   ├── NotificationService.swift     ← UNUserNotificationCenter
│   │   └── SocialRepository.swift        ← follow/feed/kudos Firestore ops
│   ├── Coaching/
│   │   ├── CoachingEngine.swift          ← metric → coaching text mapping
│   │   └── AchievementEngine.swift       ← personal records detection
│   └── Models/
│       ├── WorkoutResult.swift           ← GPS workout model
│       ├── UserProfile.swift             ← user profile model
│       ├── Activity.swift                ← feed item model
│       ├── Challenge.swift               ← weekly challenge model
│       └── FeedItem.swift                ← social feed item
│
├── Modules/
│   ├── Onboarding/
│   │   ├── StrikingOnboardingView.swift
│   │   ├── GrapplingOnboardingView.swift
│   │   ├── IronTrackerOnboardingView.swift
│   │   └── WallBetaOnboardingView.swift
│   ├── Reports/
│   │   ├── SessionReportView.swift       ← parameterized post-session report
│   │   ├── SessionDetailView.swift       ← rich activity log detail
│   │   ├── StrikingReportContent.swift   ← sport-specific report sections
│   │   ├── GrapplingReportContent.swift
│   │   ├── IronTrackerReportContent.swift
│   │   └── WallBetaReportContent.swift
│   ├── Sprint/
│   │   ├── SprintView.swift
│   │   ├── SprintViewModel.swift
│   │   └── SprintAnalytics.swift
│   ├── Basketball/
│   │   ├── BasketballView.swift
│   │   ├── BasketballViewModel.swift
│   │   └── BasketballAnalytics.swift
│   └── Golf/
│       ├── GolfView.swift
│       ├── GolfViewModel.swift
│       └── GolfAnalytics.swift
│
├── Track/                                ← Strava clone tab
│   ├── TrackView.swift
│   ├── ActiveWorkoutView.swift
│   ├── WorkoutSummaryView.swift
│   ├── WorkoutHistoryView.swift
│   ├── WorkoutDetailView.swift
│   ├── RouteMapView.swift
│   ├── ElevationChartView.swift
│   ├── PaceChartView.swift
│   ├── HRZoneView.swift
│   ├── SplitsTableView.swift
│   ├── TrackViewModel.swift
│   └── WorkoutRepository.swift
│
├── Social/                               ← Friends, feed, kudos, DMs
│   ├── FeedView.swift
│   ├── FeedViewModel.swift
│   ├── ActivityFeedCard.swift
│   ├── UserProfileView.swift
│   ├── UserSearchView.swift
│   ├── FollowersView.swift
│   ├── MessagesListView.swift
│   ├── MessageThreadView.swift
│   ├── MessagesViewModel.swift
│   ├── KudosButton.swift
│   ├── CommentView.swift
│   └── ShareCardView.swift               ← generates shareable image
│
├── Profile/                              ← User's own profile + stats
│   ├── ProfileView.swift
│   ├── ProfileViewModel.swift
│   ├── EditProfileView.swift
│   ├── ProgressDashboardView.swift
│   ├── PersonalRecordsView.swift
│   └── AchievementsView.swift
│
├── Settings/
│   ├── SettingsView.swift
│   ├── PrivacySettingsView.swift
│   ├── NotificationSettingsView.swift
│   └── ConnectedAppsView.swift
│
└── Shared/
    ├── Components/
    │   ├── KineticsLogoView.swift        ← programmatic logo mark
    │   ├── MetricProgressBar.swift
    │   ├── LineChartView.swift           ← generic reusable chart
    │   ├── RadarChartView.swift          ← sport fitness radar
    │   ├── HeatmapView.swift             ← CoM position heatmap
    │   ├── ShareCardGenerator.swift      ← UIGraphicsImageRenderer share cards
    │   └── OnboardingPageView.swift      ← reusable onboarding component
    └── Navigation/
        ├── RootTabView.swift             ← tab bar controller
        └── SidebarView.swift             ← left drawer
```

---

## SECTION 12 — FIREBASE SETUP CHECKLIST

Before Session 3 starts, make sure Firebase has:

- [ ] **Firestore Security Rules** updated for `users/{uid}/sessions/{id}` path:
```
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /users/{userId}/{document=**} {
      allow read, write: if request.auth != null && request.auth.uid == userId;
    }
    // Public profile reads
    match /users/{userId}/profile {
      allow read: if request.auth != null;
    }
    // Activity feed items (public activities readable by authenticated users)
    match /users/{userId}/workouts/{workoutId} {
      allow read: if request.auth != null && resource.data.isPublic == true;
    }
  }
}
```

- [ ] **Firebase Storage** enabled for avatar images:
  `gs://your-bucket/avatars/{uid}.jpg`

- [ ] **Firestore indexes** (needed for feed queries):
  - `users/{uid}/workouts` — composite: `isPublic ASC, startedAt DESC`
  - `users/{uid}/sessions` — composite: `sport ASC, startedAt DESC`

- [ ] **Firebase Functions** (needed for social feed):
  Set up Cloud Functions to denormalize activity into followers' feeds

- [ ] **Firebase Realtime Database** enabled for DMs

---

## SECTION 13 — HOW TO WORK IN THE NEXT SESSION

### The agent swarm pattern for Session 3
Every session should start with this pattern:

```
1. Read state.md
2. Read NEXT_SESSION.md (this file) — find the current session's tasks
3. Decompose into independent files
4. Launch one agent per file IN PARALLEL using the Task tool
5. Each agent: reads relevant existing files, implements one complete file
6. Collect outputs, verify they compile together
7. Build and test
8. Commit and push
9. Update state.md with what was completed
```

### How many agents to spawn per session
- Minimum: 4 agents running simultaneously
- Target: 6-8 agents for a full session
- Each agent owns exactly ONE file or ONE feature
- Agents that write ViewModels should also write any helper models they need

### Prompt template for a Session 3 agent
```
You are implementing [FileName.swift] for the Kinetics iOS app.

EXISTING CODEBASE CONTEXT:
- Swift 6, SwiftUI, iOS 17+
- @Observable @MainActor for all ViewModels
- Firestore path: users/{uid}/sessions/{id}
- SessionResult model is in Kinetics/Core/Models/SessionResult.swift
- Color palette: .kineticsBackground, .kineticsBlue, .kineticsGreen
- All views use dark background with electric blue accents

YOUR TASK: Implement [specific file] as described in NEXT_SESSION.md Section [X].
Requirements: [paste exact spec from this file]

Read these existing files before starting:
- [list relevant files]

Output: The complete Swift file, production-quality, no TODOs, no placeholder text.
```

---

## SECTION 14 — DESIGN DETAILS FOR CLAUDE CODE SESSION

### Colors to add to `Color+Kinetics.swift`
```swift
// Add these:
static let kineticsAmber = Color(hex: "FFB800")      // achievements, PRs
static let kineticsPurple = Color(hex: "8B5CF6")     // social/feed
static let kineticsRed = Color(hex: "FF3B30")        // alerts
static let kineticsSurface = Color(hex: "141414")    // card backgrounds
static let kineticsSubtext = Color(hex: "8E8E93")    // secondary text
```

### Typography rules
```swift
// Metric values: SF Pro Rounded Bold
Font.system(.largeTitle, design: .rounded, weight: .bold)

// Labels: SF Pro Display Medium  
Font.system(.caption, design: .default, weight: .medium)
  .tracking(1.2)    // wide tracking on all-caps labels
  .textCase(.uppercase)

// Body coaching text: SF Pro Text Regular
Font.system(.body)
```

### Card component spec
Every content card: 
- Background: `Color.kineticsSurface` (not `.black`)
- Corner radius: 16pt
- Padding: 20pt horizontal, 18pt vertical
- No border by default; `0.5pt` border in `Color.white.opacity(0.08)` on hover/selected

### Animation rules
- Session start: camera feed fades in, skeleton overlay draws on with `trim()` animation
- Metric updates: spring animation, 0.3s, `dampingFraction: 0.7`
- Achievement unlock: scale + glow pulse, 0.6s
- Tab switch: standard SwiftUI tab animation (don't override)

---

---

## SECTION 15 — FRONT CAMERA SUPPORT

### Current state
`CameraManager.swift` hard-codes `.back` camera position. The front camera works better for:
- Striking Clinic: self-coaching in a mirror-free gym
- Grappling Lab: solo drilling without a partner to hold the phone
- Wall Beta: mount phone on a wall bracket facing the climber
- All modules: users who don't have someone to hold the phone behind them

### What to build

**1. Add camera position toggle to `CameraManager.swift`**

The key file: `Kinetics/Core/Vision/CameraManager.swift`

Change the `captureDevice` lookup from hardcoded `.back` to a settable property:
```swift
// Add to CameraManager:
var cameraPosition: AVCaptureDevice.Position = .back

// In configureSessionIfNeeded(), replace:
//   AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
// with:
//   AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: cameraPosition)
```

Because `configureSessionIfNeeded()` is guarded by `isConfigured`, switching cameras requires a full session teardown and reconfigure. Add a `switchCamera()` method:
```swift
func switchCamera() async {
    await stopSession()         // stop current session
    isConfigured = false        // reset the guard flag
    cameraPosition = (cameraPosition == .back) ? .front : .back
    configureSessionIfNeeded()  // reconfigure with new position
    startRunningSession()       // restart
}
```

**2. Mirror the preview for front camera**

When using front camera, the `CameraPreviewView` needs to be horizontally mirrored so the user sees themselves as in a mirror (not flipped). In `CameraPreviewView.swift`:
```swift
// In the AVCaptureVideoPreviewLayer setup, add:
previewLayer.connection?.automaticallyAdjustsVideoMirroring = false
previewLayer.connection?.isVideoMirrored = (cameraManager.cameraPosition == .front)
```

**3. Flip Vision coordinate system for front camera**

`VNDetectHumanBodyPoseRequest` returns normalized coordinates in the camera's frame. When using the front camera, the x-axis is flipped relative to what the user sees on screen (because the preview is mirrored but the Vision output is not). 

In `PoseDetectionEngine.swift`, after extracting joint positions, flip the x-coordinate when front camera is active:
```swift
// In processObservation(_:), after getting joint locations:
if isFrontCamera {
    // Flip x: newX = 1.0 - x
    // Apply to every VNRecognizedPoint before wrapping in JointPose
}
```

Pass `isFrontCamera: Bool` as a parameter to `poseEngine.process(buffer, isFrontCamera: cameraPosition == .front)`.

**4. UI toggle button**

Add a camera flip button to every module View — overlay it in the top-right corner of the camera feed (same location as the existing toolbar but as a floating overlay button so it's visible over the live camera):
```swift
// Floating toggle button — shown at top-trailing of the camera preview
Button {
    Task { await cameraManager.switchCamera() }
} label: {
    Image(systemName: "camera.rotate.fill")
        .font(.system(size: 20, weight: .semibold))
        .foregroundStyle(.white)
        .padding(12)
        .background(.ultraThinMaterial)
        .clipShape(Circle())
        .shadow(color: .black.opacity(0.4), radius: 6)
}
.padding(16)
```

**5. Per-module camera position defaults**

Some modules naturally suit one camera over the other. Store the user's last-used position per module in `@AppStorage`:
```swift
@AppStorage("camera_position_striking") var preferFrontForStriking = false
@AppStorage("camera_position_grappling") var preferFrontForGrappling = true  // default front: user is often solo
@AppStorage("camera_position_iron") var preferFrontForIron = false           // side view for iron
@AppStorage("camera_position_wall") var preferFrontForWall = false           // wall-facing camera
```

When a module opens, set `cameraManager.cameraPosition` to the stored preference before calling `startSession()`.

### Files to modify
- `Kinetics/Core/Vision/CameraManager.swift` — add `cameraPosition`, `switchCamera()`
- `Kinetics/Core/Vision/PoseDetectionEngine.swift` — add front-camera x-flip
- `Kinetics/Shared/Components/CameraPreviewView.swift` — mirror layer for front camera
- All 4 module Views — add floating rotate button, load stored camera preference
- All 4 module ViewModels — pass camera position to pose engine

### Build order
1. `CameraManager` changes first (foundation)
2. `PoseDetectionEngine` coordinate flip
3. `CameraPreviewView` mirror fix
4. Module Views (4 files in parallel)

---

*This document is the single source of truth for Kinetics development. Update it when specs change. Never delete sections — append updates below the relevant section.*
