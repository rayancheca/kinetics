# Firebase Deploy — Kinetics

Project ID: `kinetics-4da22`

## Prerequisites

```bash
npm install -g firebase-tools
firebase login
```

## Select the project

```bash
firebase use kinetics-4da22
```

## Deploy security rules

```bash
firebase deploy --only firestore:rules
```

## Deploy composite indexes

```bash
firebase deploy --only firestore:indexes
```

## Deploy both at once

```bash
firebase deploy --only firestore
```

## Verify rules are live

Open the Firebase Console → Firestore → Rules tab and confirm the timestamp matches.

## Re-seed demo data (DEBUG only)

The `_meta/feed_seeded_v3` flag document blocks automatic re-seeding.
To force a fresh seed:

1. Delete `_meta/feed_seeded_v3` in the Firebase Console (Firestore → _meta collection).
2. Launch the app with the `SEED_DATA=1` environment variable set in the Xcode scheme.
3. The app calls `FeedSeeder.shared.seedIfNeeded()` at launch and will write fresh data.

Client writes to `_meta` are blocked by the security rules. Only delete the flag
via the Firebase Console or a server-side Admin SDK script.
