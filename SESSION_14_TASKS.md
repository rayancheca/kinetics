# Session 14 — Bug Fix & Feature Backlog

Priority: P1 = ship blocker, P2 = major UX, P3 = polish

---

## P1 — Critical Bugs (App Unusable)

- [ ] **No end button on any live session** — Striking, Grappling, IronTracker, WallBeta all lack a way to end the session without force-quitting
- [ ] **Grappling Lab blank screen** — shows card then goes blank, never loads
- [ ] **WallBeta live session error** — crashes on Start
- [ ] **Feed: likes/comments don't persist** — they vanish after you close the sheet (Firebase not saving correctly)
- [ ] **Video upload broken** — clicking a video (40s) in the picker dismisses without uploading; takes you back to library
- [ ] **Video AI sport detection wrong** — jujitsu → wrongly labelled as strike/gym

## P2 — Major UX Gaps

- [ ] **Striking live session: no pause/resume** — need pause, resume, end controls
- [ ] **AI Coach voice never fires** — "Complete first session to unlock" never clears even after many sessions
- [ ] **Feed: post body missing** — shares appear in story circles, not as feed cards with content, name, likes
- [ ] **Gym: swipe-to-delete on recent workouts** — swipe left → delete; swipe right → hide/mute
- [ ] **Gym: plus button hidden behind footer** — can't add new routine
- [ ] **Gym: End vs Cancel button** — End is red, Cancel should match; also why are there two buttons (End + Finish)?
- [ ] **Discover: can't tap user profiles** — Follow works but tapping the row should open their profile
- [ ] **Feed: Share Workout needs real Strava-style data** — not just sport type, include duration, distance, pace, notes

## P3 — Polish & Animation

- [ ] **Splash screen too fast** — animation plays but "KINETICS" text isn't visible long enough; increase hold time
- [ ] **Animations everywhere** — implement entry animations on cards, tabs, session start (inspired by splash screen style)
- [ ] **Profile badges slide-up card** — add lottie/spring animations when badge card appears
- [ ] **Home milestone card** — Grappling Lab "5 sessions to go" needs richer data and better layout
- [ ] **Performance tab rework** — remove 52-week training frequency, replace with meaningful insights
- [ ] **Notifications** — not firing at all; need to verify UNUserNotificationCenter authorization and scheduling
- [ ] **Strava connect button** — broken in Profile → Preferences

---

## Status

| # | Item | Status |
|---|------|--------|
| 1 | No end button on sessions | TODO |
| 2 | Grappling blank screen | TODO |
| 3 | WallBeta start error | TODO |
| 4 | Feed likes/comments persist | TODO |
| 5 | Video upload fix | TODO |
| 6 | Video sport detection | TODO |
| 7 | Striking pause/resume | TODO |
| 8 | AI coach unlock | TODO |
| 9 | Feed post body visible | TODO |
| 10 | Gym swipe delete | TODO |
| 11 | Gym plus button | TODO |
| 12 | Gym End/Cancel buttons | TODO |
| 13 | Discover profile tap | TODO |
| 14 | Share Workout Strava-style | TODO |
| 15 | Splash timing | IN PROGRESS |
| 16 | Animations | TODO |
| 17 | Badge animations | TODO |
| 18 | Home milestone richer | TODO |
| 19 | Performance tab rework | TODO |
| 20 | Notifications | TODO |
| 21 | Strava connect | TODO |
