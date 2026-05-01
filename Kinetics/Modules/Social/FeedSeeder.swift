import FirebaseCore
import FirebaseFirestore
import Foundation

// MARK: - FeedSeeder

/// Seeds Firestore with realistic demo athlete profiles and feed posts.
/// Only auto-seeds once — checks for a "seeded" flag document before writing.
/// The `seed()` method can be called directly to force a re-seed from the debug button.
@MainActor
final class FeedSeeder {

    // MARK: Singleton

    static let shared = FeedSeeder()

    // MARK: Private

    private var db: Firestore { Firestore.firestore() }

    private init() {}

    // MARK: - Public API

    /// Checks the `_meta/feed_seeded_v3` flag and seeds only if absent.
    /// Uses v3 to force a fresh seed that includes comments, follows, and kudos.
    func seedIfNeeded() async {
        guard FirebaseApp.app() != nil else { return }
        let flagDoc = try? await db.collection("_meta").document("feed_seeded_v3").getDocument()
        if flagDoc?.exists == true { return }
        await seed()
        try? await db.collection("_meta").document("feed_seeded_v3")
            .setData(["seededAt": Date().timeIntervalSince1970])
    }

    /// Unconditionally writes all demo users, posts, follows, comments, and kudos to Firestore.
    func seed() async {
        guard FirebaseApp.app() != nil else { return }
        await seedUsers()
        await seedPosts()
        await seedFollows()
        await seedComments()
        await seedKudos()
    }

    // MARK: - Demo User Data

    private struct DemoUser {
        let id: String
        let name: String
        let username: String
        let bio: String
        let sport: String
        let emoji: String
    }

    private let demoUsers: [DemoUser] = [
        DemoUser(id: "demo_001", name: "Alex Rivera",    username: "@alex_r",    bio: "MMA fighter • BJJ purple belt • 3x regional champ",               sport: "striking",  emoji: "🥊"),
        DemoUser(id: "demo_002", name: "Jordan Kim",     username: "@jkim_lifts", bio: "Powerlifter • USAPL • 500kg total • chasing 600",                  sport: "iron",      emoji: "🏋️"),
        DemoUser(id: "demo_003", name: "Sam Torres",     username: "@samtorres", bio: "Trail runner • ultramarathon • 100 mile finisher",                  sport: "run",       emoji: "🏃"),
        DemoUser(id: "demo_004", name: "Casey Nguyen",   username: "@casey_wall", bio: "Pro climber • V9 boulderer • 5.13c sport",                          sport: "wall",      emoji: "🧗"),
        DemoUser(id: "demo_005", name: "Morgan Davies",  username: "@morg_fit",  bio: "Crossfit athlete • BJJ blue belt • weekend warrior",                 sport: "grappling", emoji: "🤼"),
        DemoUser(id: "demo_006", name: "Riley Chen",     username: "@rileyfit",  bio: "Olympic weightlifter • snatch 90kg • clean & jerk 115kg",            sport: "iron",      emoji: "🏋️"),
        DemoUser(id: "demo_007", name: "Taylor Brooks",  username: "@tbrooks",   bio: "Muay Thai fighter • personal trainer • 8 years striking",            sport: "striking",  emoji: "🥋"),
        DemoUser(id: "demo_008", name: "Drew Martinez",  username: "@drewruns",  bio: "5K specialist • 17:32 PR • training for Boston",                     sport: "run",       emoji: "🏃‍♂️"),
        DemoUser(id: "demo_009", name: "Quinn Anderson", username: "@quinn_bjj", bio: "BJJ brown belt • judo black belt • competition mode",                sport: "grappling", emoji: "🤼‍♂️"),
        DemoUser(id: "demo_010", name: "Blake Foster",   username: "@bfoster",   bio: "Rock climber • gym rat • bouldering V7 project",                     sport: "wall",      emoji: "🧗‍♂️"),
    ]

    // MARK: - Seed Users

    private func seedUsers() async {
        let now = Date()
        for user in demoUsers {
            let profile = UserProfile(
                id: user.id,
                displayName: user.name,
                username: user.username,
                bio: user.bio,
                avatarURL: "",
                primarySport: user.sport,
                totalWorkouts: Int.random(in: 45...210),
                totalDistanceMeters: Double.random(in: 80_000...650_000),
                joinedAt: Date(timeIntervalSinceNow: -Double.random(in: 86_400 * 30...86_400 * 365)),
                isPublic: true
            )
            await writeUser(profile)
        }
        _ = now // suppress unused warning
    }

    // MARK: - Seed Posts

    private func seedPosts() async {
        let day: Double = 86_400
        var posts: [FeedItem] = []

        // MARK: Gym / Iron posts — Jordan Kim (demo_002)

        posts.append(FeedItem(
            id: "demo_post_001",
            userId: "demo_002",
            displayName: "Jordan Kim",
            username: "@jkim_lifts",
            avatarURL: "",
            itemType: .gymSession,
            title: "Bench Day 🔥 New PR Hit",
            subtitle: "Bench Press 5×5 @ 120kg • Incline DB 4×10",
            caption: "Felt strong today. Took an extra rest day this week and it paid off. 120kg felt smooth.",
            metrics: [
                FeedMetric(label: "TOP SET", value: "120", unit: "kg"),
                FeedMetric(label: "VOLUME", value: "3,200", unit: "kg"),
                FeedMetric(label: "SETS", value: "12", unit: "")
            ],
            exerciseSummaries: [
                ExerciseSummary(name: "Bench Press",  sets: 5, topWeightKg: 120, totalReps: 25, muscleGroup: "Chest"),
                ExerciseSummary(name: "Incline DB",   sets: 4, topWeightKg: 35,  totalReps: 40, muscleGroup: "Chest"),
                ExerciseSummary(name: "Cable Fly",    sets: 3, topWeightKg: 15,  totalReps: 45, muscleGroup: "Chest"),
            ],
            imageURL: "",
            postedAt: Date(timeIntervalSinceNow: -0.3 * day),
            kudosCount: 31,
            commentCount: 7,
            isLikedByCurrentUser: false,
            workoutId: "",
            activityType: "iron"
        ))

        posts.append(FeedItem(
            id: "demo_post_002",
            userId: "demo_002",
            displayName: "Jordan Kim",
            username: "@jkim_lifts",
            avatarURL: "",
            itemType: .gymSession,
            title: "Deadlift Day • 180kg × 5",
            subtitle: "Felt smooth. RDL superset after.",
            caption: "180kg × 5 felt better than expected. Grip held without straps. Happy with this.",
            metrics: [
                FeedMetric(label: "TOP SET", value: "180", unit: "kg"),
                FeedMetric(label: "VOLUME", value: "4,100", unit: "kg"),
                FeedMetric(label: "SETS", value: "8", unit: "")
            ],
            exerciseSummaries: [
                ExerciseSummary(name: "Deadlift",         sets: 5, topWeightKg: 180, totalReps: 25, muscleGroup: "Back"),
                ExerciseSummary(name: "RDL",              sets: 3, topWeightKg: 100, totalReps: 30, muscleGroup: "Hamstrings"),
                ExerciseSummary(name: "Back Extension",   sets: 3, topWeightKg: 0,   totalReps: 45, muscleGroup: "Lower Back"),
            ],
            imageURL: "",
            postedAt: Date(timeIntervalSinceNow: -1.8 * day),
            kudosCount: 24,
            commentCount: 4,
            isLikedByCurrentUser: false,
            workoutId: "",
            activityType: "iron"
        ))

        // MARK: Olympic lifting — Riley Chen (demo_006)

        posts.append(FeedItem(
            id: "demo_post_003",
            userId: "demo_006",
            displayName: "Riley Chen",
            username: "@rileyfit",
            avatarURL: "",
            itemType: .gymSession,
            title: "Olympic Lifts • Snatch Technique",
            subtitle: "Snatch 8×2 @ 75kg • C&J 5×2 @ 95kg",
            caption: "Bar speed is coming together. Coach said hip snap timing is finally clicking. Front squat afterwards to build the catch position.",
            metrics: [
                FeedMetric(label: "SNATCH", value: "75", unit: "kg"),
                FeedMetric(label: "C&J", value: "95", unit: "kg"),
                FeedMetric(label: "SETS", value: "13", unit: "")
            ],
            exerciseSummaries: [
                ExerciseSummary(name: "Snatch",        sets: 8, topWeightKg: 75,  totalReps: 16, muscleGroup: "Full Body"),
                ExerciseSummary(name: "Clean & Jerk",  sets: 5, topWeightKg: 95,  totalReps: 10, muscleGroup: "Full Body"),
                ExerciseSummary(name: "Front Squat",   sets: 4, topWeightKg: 110, totalReps: 12, muscleGroup: "Legs"),
            ],
            imageURL: "",
            postedAt: Date(timeIntervalSinceNow: -2.4 * day),
            kudosCount: 47,
            commentCount: 12,
            isLikedByCurrentUser: false,
            workoutId: "",
            activityType: "iron"
        ))

        // MARK: Running posts — Sam Torres (demo_003)

        let centralParkLoop: [[Double]] = [
            [40.7851, -73.9683], [40.7862, -73.9650], [40.7878, -73.9620],
            [40.7901, -73.9600], [40.7920, -73.9588], [40.7938, -73.9595],
            [40.7955, -73.9615], [40.7963, -73.9640], [40.7958, -73.9670],
            [40.7944, -73.9695], [40.7922, -73.9712], [40.7898, -73.9710],
            [40.7875, -73.9700], [40.7858, -73.9690], [40.7851, -73.9683]
        ]

        posts.append(FeedItem(
            id: "demo_post_004",
            userId: "demo_003",
            displayName: "Sam Torres",
            username: "@samtorres",
            avatarURL: "",
            itemType: .workout,
            title: "Morning 10k • Tempo Pace",
            subtitle: "10.0 km • 43:20 • 4:20/km",
            caption: "Legs feeling heavy but pushed through. Summer base building 🌞 Consistent week incoming.",
            metrics: [
                FeedMetric(label: "PACE", value: "4:20", unit: "/km"),
                FeedMetric(label: "DIST", value: "10.0", unit: "km"),
                FeedMetric(label: "TIME", value: "43:20", unit: "")
            ],
            routeCoordinates: centralParkLoop,
            imageURL: "",
            postedAt: Date(timeIntervalSinceNow: -0.6 * day),
            kudosCount: 18,
            commentCount: 3,
            isLikedByCurrentUser: false,
            workoutId: "workout_demo_001",
            activityType: "run"
        ))

        posts.append(FeedItem(
            id: "demo_post_005",
            userId: "demo_003",
            displayName: "Sam Torres",
            username: "@samtorres",
            avatarURL: "",
            itemType: .workout,
            title: "Easy Recovery Jog",
            subtitle: "5.5 km • 30:10 • 5:29/km",
            caption: "Active recovery day. Shakeout run after yesterday's tempo. Body needed it.",
            metrics: [
                FeedMetric(label: "PACE", value: "5:29", unit: "/km"),
                FeedMetric(label: "DIST", value: "5.5", unit: "km"),
                FeedMetric(label: "TIME", value: "30:10", unit: "")
            ],
            routeCoordinates: Array(centralParkLoop.prefix(8)),
            imageURL: "",
            postedAt: Date(timeIntervalSinceNow: -2.1 * day),
            kudosCount: 9,
            commentCount: 1,
            isLikedByCurrentUser: false,
            workoutId: "workout_demo_002",
            activityType: "run"
        ))

        // MARK: Running — Drew Martinez (demo_008)

        let trackCoords: [[Double]] = [
            [40.7128, -74.0060], [40.7135, -74.0048], [40.7142, -74.0038],
            [40.7148, -74.0032], [40.7140, -74.0025], [40.7130, -74.0030],
            [40.7122, -74.0042], [40.7120, -74.0055], [40.7128, -74.0060]
        ]

        posts.append(FeedItem(
            id: "demo_post_006",
            userId: "demo_008",
            displayName: "Drew Martinez",
            username: "@drewruns",
            avatarURL: "",
            itemType: .workout,
            title: "Speed Intervals • 8×400m",
            subtitle: "6.2 km • 28:45 • 4:38/km avg",
            caption: "Hard one today. Splits were 1:48, 1:46, 1:47, 1:45, 1:47, 1:44, 1:46, 1:43. Last two were the best. Progress.",
            metrics: [
                FeedMetric(label: "PACE", value: "4:38", unit: "/km"),
                FeedMetric(label: "DIST", value: "6.2", unit: "km"),
                FeedMetric(label: "REPS", value: "8×400", unit: "m")
            ],
            routeCoordinates: trackCoords,
            imageURL: "",
            postedAt: Date(timeIntervalSinceNow: -1.3 * day),
            kudosCount: 22,
            commentCount: 5,
            isLikedByCurrentUser: false,
            workoutId: "workout_demo_003",
            activityType: "run"
        ))

        posts.append(FeedItem(
            id: "demo_post_007",
            userId: "demo_008",
            displayName: "Drew Martinez",
            username: "@drewruns",
            avatarURL: "",
            itemType: .workout,
            title: "Long Run • 18k Easy",
            subtitle: "18.0 km • 1:42:30 • 5:41/km",
            caption: "Weekly long run done. Aerobic base building for Boston qualifier. Heart rate nice and low throughout.",
            metrics: [
                FeedMetric(label: "PACE", value: "5:41", unit: "/km"),
                FeedMetric(label: "DIST", value: "18.0", unit: "km"),
                FeedMetric(label: "TIME", value: "1:42:30", unit: "")
            ],
            routeCoordinates: centralParkLoop + centralParkLoop.reversed(),
            imageURL: "",
            postedAt: Date(timeIntervalSinceNow: -3.5 * day),
            kudosCount: 35,
            commentCount: 8,
            isLikedByCurrentUser: false,
            workoutId: "workout_demo_004",
            activityType: "run"
        ))

        // MARK: Striking posts — Alex Rivera (demo_001)

        posts.append(FeedItem(
            id: "demo_post_008",
            userId: "demo_001",
            displayName: "Alex Rivera",
            username: "@alex_r",
            avatarURL: "",
            itemType: .strikeSession,
            title: "Sparring Session • Combo Flows",
            subtitle: "Avg velocity 9.2 m/s • 87 strikes • 94% guard recovery",
            caption: "Coach says my jab timing is dialing in. Finally. Hip rotation on the cross is translating into real power.",
            metrics: [
                FeedMetric(label: "VELOCITY", value: "9.2", unit: "m/s"),
                FeedMetric(label: "STRIKES", value: "87", unit: ""),
                FeedMetric(label: "GUARD", value: "94", unit: "%")
            ],
            imageURL: "",
            postedAt: Date(timeIntervalSinceNow: -0.8 * day),
            kudosCount: 41,
            commentCount: 9,
            isLikedByCurrentUser: false,
            workoutId: "",
            activityType: "striking"
        ))

        posts.append(FeedItem(
            id: "demo_post_009",
            userId: "demo_001",
            displayName: "Alex Rivera",
            username: "@alex_r",
            avatarURL: "",
            itemType: .strikeSession,
            title: "Pad Work • 3×5 Rounds Speed",
            subtitle: "Avg velocity 8.7 m/s • 124 strikes",
            caption: "Speed focus today, not power. Light on the feet, hands fast. Recovery between rounds was solid.",
            metrics: [
                FeedMetric(label: "VELOCITY", value: "8.7", unit: "m/s"),
                FeedMetric(label: "STRIKES", value: "124", unit: ""),
                FeedMetric(label: "ROUNDS", value: "15", unit: "")
            ],
            imageURL: "",
            postedAt: Date(timeIntervalSinceNow: -3.0 * day),
            kudosCount: 28,
            commentCount: 4,
            isLikedByCurrentUser: false,
            workoutId: "",
            activityType: "striking"
        ))

        // MARK: Striking — Taylor Brooks (demo_007)

        posts.append(FeedItem(
            id: "demo_post_010",
            userId: "demo_007",
            displayName: "Taylor Brooks",
            username: "@tbrooks",
            avatarURL: "",
            itemType: .strikeSession,
            title: "Muay Thai Clinch Work • 6 Rounds",
            subtitle: "Avg velocity 7.8 m/s • Knee strikes 32",
            caption: "Clinch game improving every week. Elbow accuracy is the next thing to tighten up.",
            metrics: [
                FeedMetric(label: "VELOCITY", value: "7.8", unit: "m/s"),
                FeedMetric(label: "KNEES", value: "32", unit: ""),
                FeedMetric(label: "ELBOWS", value: "18", unit: "")
            ],
            imageURL: "",
            postedAt: Date(timeIntervalSinceNow: -1.5 * day),
            kudosCount: 19,
            commentCount: 2,
            isLikedByCurrentUser: false,
            workoutId: "",
            activityType: "striking"
        ))

        posts.append(FeedItem(
            id: "demo_post_011",
            userId: "demo_007",
            displayName: "Taylor Brooks",
            username: "@tbrooks",
            avatarURL: "",
            itemType: .strikeSession,
            title: "Heavy Bag Power Session",
            subtitle: "Peak velocity 11.4 m/s • 58 strikes",
            caption: "Max power day. Not about volume today, just loading up and finding the ceiling. New peak velocity PR 💥",
            metrics: [
                FeedMetric(label: "PEAK VEL", value: "11.4", unit: "m/s"),
                FeedMetric(label: "STRIKES", value: "58", unit: ""),
                FeedMetric(label: "SYM", value: "89", unit: "%")
            ],
            imageURL: "",
            postedAt: Date(timeIntervalSinceNow: -5.2 * day),
            kudosCount: 33,
            commentCount: 6,
            isLikedByCurrentUser: false,
            workoutId: "",
            activityType: "striking"
        ))

        // MARK: Grappling posts — Morgan Davies (demo_005)

        posts.append(FeedItem(
            id: "demo_post_012",
            userId: "demo_005",
            displayName: "Morgan Davies",
            username: "@morg_fit",
            avatarURL: "",
            itemType: .grapplingSession,
            title: "BJJ Open Mat • Single Leg Drills",
            subtitle: "12 takedowns • Kuzushi 78% • Base stability 91%",
            caption: "Drilled single legs for 45 min. Tournament in 3 weeks. Feeling ready. The kuzushi analysis is insane — I can see exactly where I'm off-balance.",
            metrics: [
                FeedMetric(label: "TAKEDOWNS", value: "12", unit: ""),
                FeedMetric(label: "KUZUSHI", value: "78", unit: "%"),
                FeedMetric(label: "BASE", value: "91", unit: "%")
            ],
            imageURL: "",
            postedAt: Date(timeIntervalSinceNow: -0.9 * day),
            kudosCount: 14,
            commentCount: 3,
            isLikedByCurrentUser: false,
            workoutId: "",
            activityType: "grappling"
        ))

        posts.append(FeedItem(
            id: "demo_post_013",
            userId: "demo_005",
            displayName: "Morgan Davies",
            username: "@morg_fit",
            avatarURL: "",
            itemType: .grapplingSession,
            title: "Competition Prep • Sharp Today",
            subtitle: "8 throws • 92% technique score",
            caption: "Felt crisp. Hip timing on the seoi nage is clicking. Three weeks out and this is the best I've felt.",
            metrics: [
                FeedMetric(label: "THROWS", value: "8", unit: ""),
                FeedMetric(label: "TECHNIQUE", value: "92", unit: "%"),
                FeedMetric(label: "BASE", value: "88", unit: "%")
            ],
            imageURL: "",
            postedAt: Date(timeIntervalSinceNow: -4.1 * day),
            kudosCount: 21,
            commentCount: 5,
            isLikedByCurrentUser: false,
            workoutId: "",
            activityType: "grappling"
        ))

        // MARK: Grappling — Quinn Anderson (demo_009)

        posts.append(FeedItem(
            id: "demo_post_014",
            userId: "demo_009",
            displayName: "Quinn Anderson",
            username: "@quinn_bjj",
            avatarURL: "",
            itemType: .grapplingSession,
            title: "Guard Passing Drills • Torreando",
            subtitle: "18 passes • Hip stability 87%",
            caption: "Focused on torreando and leg drag for 90 min. Hip position on the finish needs work but the entry is sharp.",
            metrics: [
                FeedMetric(label: "PASSES", value: "18", unit: ""),
                FeedMetric(label: "HIP STA", value: "87", unit: "%"),
                FeedMetric(label: "SPEED", value: "2.1", unit: "m/s")
            ],
            imageURL: "",
            postedAt: Date(timeIntervalSinceNow: -2.8 * day),
            kudosCount: 16,
            commentCount: 4,
            isLikedByCurrentUser: false,
            workoutId: "",
            activityType: "grappling"
        ))

        posts.append(FeedItem(
            id: "demo_post_015",
            userId: "demo_009",
            displayName: "Quinn Anderson",
            username: "@quinn_bjj",
            avatarURL: "",
            itemType: .grapplingSession,
            title: "Judo Throws • Uchi Mata Focus",
            subtitle: "14 throws • Kuzushi 84% • Entry speed 2.4 m/s",
            caption: "Black belt training. Uchi mata catch timing is the detail that wins matches. Drilling it 500 reps until it's automatic.",
            metrics: [
                FeedMetric(label: "THROWS", value: "14", unit: ""),
                FeedMetric(label: "KUZUSHI", value: "84", unit: "%"),
                FeedMetric(label: "ENTRY", value: "2.4", unit: "m/s")
            ],
            imageURL: "",
            postedAt: Date(timeIntervalSinceNow: -6.0 * day),
            kudosCount: 38,
            commentCount: 11,
            isLikedByCurrentUser: false,
            workoutId: "",
            activityType: "grappling"
        ))

        // MARK: Wall / Climbing posts — Casey Nguyen (demo_004)

        posts.append(FeedItem(
            id: "demo_post_016",
            userId: "demo_004",
            displayName: "Casey Nguyen",
            username: "@casey_wall",
            avatarURL: "",
            itemType: .wallSession,
            title: "SENT the V9 Project!! 6 Sessions",
            subtitle: "Hip proximity 82% • Avg hold time 18s",
            caption: "Finally sent it. Six sessions of work. The beta was a drop knee on the crux — hips flagging out meant the reach was totally different. Kinetics showed the moment I nailed the hip position.",
            metrics: [
                FeedMetric(label: "HIP PROX", value: "82", unit: "%"),
                FeedMetric(label: "HOLD TIME", value: "18", unit: "s"),
                FeedMetric(label: "GRADE", value: "V9", unit: "")
            ],
            imageURL: "",
            postedAt: Date(timeIntervalSinceNow: -0.4 * day),
            kudosCount: 47,
            commentCount: 12,
            isLikedByCurrentUser: false,
            workoutId: "",
            activityType: "wall"
        ))

        posts.append(FeedItem(
            id: "demo_post_017",
            userId: "demo_004",
            displayName: "Casey Nguyen",
            username: "@casey_wall",
            avatarURL: "",
            itemType: .wallSession,
            title: "Overhang Session • Fingers Pumped 🧗",
            subtitle: "14 problems • V6 avg grade",
            caption: "Volume day on the overhang wall. Forearms are destroyed. That's the point. CoM tracking showed how bad my sag is on the steep stuff — working on it.",
            metrics: [
                FeedMetric(label: "PROBLEMS", value: "14", unit: ""),
                FeedMetric(label: "AVG GRADE", value: "V6", unit: ""),
                FeedMetric(label: "HIP PROX", value: "74", unit: "%")
            ],
            imageURL: "",
            postedAt: Date(timeIntervalSinceNow: -3.7 * day),
            kudosCount: 26,
            commentCount: 6,
            isLikedByCurrentUser: false,
            workoutId: "",
            activityType: "wall"
        ))

        // MARK: Wall — Blake Foster (demo_010)

        posts.append(FeedItem(
            id: "demo_post_018",
            userId: "demo_010",
            displayName: "Blake Foster",
            username: "@bfoster",
            avatarURL: "",
            itemType: .wallSession,
            title: "Project Work • V7 Dyno Problem",
            subtitle: "Hip proximity 71% • Dyno arc 1.8m",
            caption: "Getting closer on the dyno. Finally held the lip on the third attempt. Hip timing during the jump is everything — this app is showing me exactly when I'm leaving too early.",
            metrics: [
                FeedMetric(label: "HIP PROX", value: "71", unit: "%"),
                FeedMetric(label: "DYNO ARC", value: "1.8", unit: "m"),
                FeedMetric(label: "GRADE", value: "V7", unit: "")
            ],
            imageURL: "",
            postedAt: Date(timeIntervalSinceNow: -1.6 * day),
            kudosCount: 13,
            commentCount: 2,
            isLikedByCurrentUser: false,
            workoutId: "",
            activityType: "wall"
        ))

        posts.append(FeedItem(
            id: "demo_post_019",
            userId: "demo_010",
            displayName: "Blake Foster",
            username: "@bfoster",
            avatarURL: "",
            itemType: .wallSession,
            title: "Slab Technique Day",
            subtitle: "Hip proximity 91% • 9 problems",
            caption: "Slab is humbling. No power, all balance. Hip proximity went through the roof because you have to stay on the wall differently. Good mental session.",
            metrics: [
                FeedMetric(label: "HIP PROX", value: "91", unit: "%"),
                FeedMetric(label: "PROBLEMS", value: "9", unit: ""),
                FeedMetric(label: "HOLD TIME", value: "22", unit: "s")
            ],
            imageURL: "",
            postedAt: Date(timeIntervalSinceNow: -4.9 * day),
            kudosCount: 17,
            commentCount: 3,
            isLikedByCurrentUser: false,
            workoutId: "",
            activityType: "wall"
        ))

        // MARK: Additional mixed posts to reach 25

        posts.append(FeedItem(
            id: "demo_post_020",
            userId: "demo_006",
            displayName: "Riley Chen",
            username: "@rileyfit",
            avatarURL: "",
            itemType: .gymSession,
            title: "Back Squat Cycle • Week 3",
            subtitle: "Squat 5×3 @ 130kg • Paused 3×3 @ 100kg",
            caption: "Squatting more now than I ever have. Knee tracking is improving and the Kinetics symmetry gauge keeps me honest.",
            metrics: [
                FeedMetric(label: "TOP SET", value: "130", unit: "kg"),
                FeedMetric(label: "SYMMETRY", value: "96", unit: "%"),
                FeedMetric(label: "SETS", value: "8", unit: "")
            ],
            exerciseSummaries: [
                ExerciseSummary(name: "Back Squat",   sets: 5, topWeightKg: 130, totalReps: 15, muscleGroup: "Legs"),
                ExerciseSummary(name: "Paused Squat", sets: 3, topWeightKg: 100, totalReps: 9,  muscleGroup: "Legs"),
            ],
            imageURL: "",
            postedAt: Date(timeIntervalSinceNow: -5.5 * day),
            kudosCount: 29,
            commentCount: 7,
            isLikedByCurrentUser: false,
            workoutId: "",
            activityType: "iron"
        ))

        posts.append(FeedItem(
            id: "demo_post_021",
            userId: "demo_003",
            displayName: "Sam Torres",
            username: "@samtorres",
            avatarURL: "",
            itemType: .workout,
            title: "Trail Run • Morning Hills",
            subtitle: "12.3 km • 1:08:45 • 5:35/km",
            caption: "Finally got back to the hills. 380m elevation today. Quads on fire but the views were worth it. Trail season is back.",
            metrics: [
                FeedMetric(label: "PACE", value: "5:35", unit: "/km"),
                FeedMetric(label: "DIST", value: "12.3", unit: "km"),
                FeedMetric(label: "ELEV", value: "380", unit: "m")
            ],
            imageURL: "",
            postedAt: Date(timeIntervalSinceNow: -6.2 * day),
            kudosCount: 42,
            commentCount: 9,
            isLikedByCurrentUser: false,
            workoutId: "workout_demo_005",
            activityType: "run"
        ))

        posts.append(FeedItem(
            id: "demo_post_022",
            userId: "demo_001",
            displayName: "Alex Rivera",
            username: "@alex_r",
            avatarURL: "",
            itemType: .strikeSession,
            title: "Shadow Boxing • Flow State",
            subtitle: "Avg velocity 6.4 m/s • 210 strikes",
            caption: "No pressure today, just moving. 210 strikes tracked in shadow work. Sometimes you have to drill the combinations slow to make them fast.",
            metrics: [
                FeedMetric(label: "VELOCITY", value: "6.4", unit: "m/s"),
                FeedMetric(label: "STRIKES", value: "210", unit: ""),
                FeedMetric(label: "SYM", value: "91", unit: "%")
            ],
            imageURL: "",
            postedAt: Date(timeIntervalSinceNow: -6.8 * day),
            kudosCount: 11,
            commentCount: 1,
            isLikedByCurrentUser: false,
            workoutId: "",
            activityType: "striking"
        ))

        posts.append(FeedItem(
            id: "demo_post_023",
            userId: "demo_009",
            displayName: "Quinn Anderson",
            username: "@quinn_bjj",
            avatarURL: "",
            itemType: .grapplingSession,
            title: "Live Drilling • 90 Min Mat Time",
            subtitle: "22 sweeps • Base stability 85%",
            caption: "Consecutive days on the mat. Body is adapting. This week's theme is sweep defense — holding position under pressure.",
            metrics: [
                FeedMetric(label: "SWEEPS", value: "22", unit: ""),
                FeedMetric(label: "BASE", value: "85", unit: "%"),
                FeedMetric(label: "TIME", value: "90", unit: "min")
            ],
            imageURL: "",
            postedAt: Date(timeIntervalSinceNow: -5.8 * day),
            kudosCount: 8,
            commentCount: 0,
            isLikedByCurrentUser: false,
            workoutId: "",
            activityType: "grappling"
        ))

        posts.append(FeedItem(
            id: "demo_post_024",
            userId: "demo_004",
            displayName: "Casey Nguyen",
            username: "@casey_wall",
            avatarURL: "",
            itemType: .wallSession,
            title: "Moonboard • Benchmark Problems",
            subtitle: "6 benchmarks topped • Hip proximity 79%",
            caption: "Moonboard session today. Benchmark problems are humbling but nothing beats them for finger strength development. Getting there.",
            metrics: [
                FeedMetric(label: "TOPPED", value: "6", unit: ""),
                FeedMetric(label: "HIP PROX", value: "79", unit: "%"),
                FeedMetric(label: "GRADE", value: "B6C", unit: "")
            ],
            imageURL: "",
            postedAt: Date(timeIntervalSinceNow: -6.5 * day),
            kudosCount: 23,
            commentCount: 4,
            isLikedByCurrentUser: false,
            workoutId: "",
            activityType: "wall"
        ))

        posts.append(FeedItem(
            id: "demo_post_025",
            userId: "demo_008",
            displayName: "Drew Martinez",
            username: "@drewruns",
            avatarURL: "",
            itemType: .workout,
            title: "Fartlek • 45 Min Unstructured",
            subtitle: "9.8 km • 45:10 • 4:36/km avg",
            caption: "Fartlek day — no watch, just feel. Pushed on the uphill sections and floated the flats. Brain off, legs on.",
            metrics: [
                FeedMetric(label: "PACE", value: "4:36", unit: "/km"),
                FeedMetric(label: "DIST", value: "9.8", unit: "km"),
                FeedMetric(label: "TIME", value: "45:10", unit: "")
            ],
            routeCoordinates: Array(centralParkLoop.suffix(10)),
            imageURL: "",
            postedAt: Date(timeIntervalSinceNow: -4.7 * day),
            kudosCount: 15,
            commentCount: 2,
            isLikedByCurrentUser: false,
            workoutId: "workout_demo_006",
            activityType: "run"
        ))

        // Write all posts concurrently
        await withTaskGroup(of: Void.self) { group in
            for post in posts {
                group.addTask { await self.writeFeedItem(post) }
            }
        }
    }

    // MARK: - Seed Follows

    private func seedFollows() async {
        // Maps each follower to the list of users they follow.
        let followGraph: [String: [String]] = [
            "demo_001": ["demo_002", "demo_003", "demo_005", "demo_007"],
            "demo_002": ["demo_001", "demo_006", "demo_004"],
            "demo_003": ["demo_001", "demo_004", "demo_005", "demo_008"],
            "demo_004": ["demo_003", "demo_001", "demo_009"],
            "demo_005": ["demo_001", "demo_002", "demo_006", "demo_007"],
            "demo_006": ["demo_002", "demo_005", "demo_010"],
            "demo_007": ["demo_001", "demo_003", "demo_005"],
            "demo_008": ["demo_003", "demo_004", "demo_009"],
            "demo_009": ["demo_004", "demo_008", "demo_010"],
            "demo_010": ["demo_001", "demo_002", "demo_005"],
        ]

        let now = Date().timeIntervalSince1970

        for (followerId, followingIds) in followGraph {
            for followingId in followingIds {
                await writeFollow(
                    followerId: followerId,
                    followingId: followingId,
                    createdAt: now
                )
            }
        }
    }

    private func writeFollow(followerId: String, followingId: String, createdAt: Double) async {
        let docId = "\(followerId)_\(followingId)"
        let data: [String: Any] = [
            "followerId": followerId,
            "followingId": followingId,
            "status": "accepted",
            "createdAt": createdAt,
        ]
        try? await db.collection("follows")
            .document(docId)
            .setData(data)
    }

    // MARK: - Seed Comments

    private func seedComments() async {
        // Comment pool keyed by activity type, used to pick realistic text.
        let ironComments = [
            "Bro that lift is filthy 🔥",
            "What program are you running?",
            "Goals 💪",
            "That's insane volume for one session",
            "How long did this take you?",
            "Numbers don't lie. Solid work.",
            "That top set looks smooth",
            "What's the diet looking like rn?",
            "When's the next comp?",
        ]
        let strikingComments = [
            "Those combos looked clean",
            "Hip rotation on that cross was 🔑",
            "When's the fight?",
            "Flow state right there",
            "Velocity numbers are insane 😤",
            "That guard recovery is elite",
            "Footwork is next level",
            "Chin down, hands up 💪",
        ]
        let grapplingComments = [
            "That kuzushi score is crazy",
            "How's comp prep going?",
            "Base looks rock solid",
            "Drilling or live rounds?",
            "Those hip entries are clean",
            "Your timing is getting sharper every week",
            "Tournament when?",
            "Entry speed is 🔥",
        ]
        let wallComments = [
            "V9 is next 👀",
            "How long did that project take?",
            "That footwork is insane",
            "Hip proximity numbers are great",
            "Send it!!! 🧗",
            "Beta looks dialled in",
            "That dyno arc is massive",
            "Slab always humbles everyone lol",
        ]
        let runComments = [
            "Marathon pace? 😤",
            "What GPS watch are you using?",
            "Splits look great!",
            "Aerobic base looking strong",
            "That's some serious mileage",
            "Recovery run goals 🏃",
            "Hills are no joke, respect",
            "Intervals looking sharp",
        ]

        // Lookup helper: user id → (displayName, username)
        let userInfo: [String: (String, String)] = [
            "demo_001": ("Alex Rivera",    "@alex_r"),
            "demo_002": ("Jordan Kim",     "@jkim_lifts"),
            "demo_003": ("Sam Torres",     "@samtorres"),
            "demo_004": ("Casey Nguyen",   "@casey_wall"),
            "demo_005": ("Morgan Davies",  "@morg_fit"),
            "demo_006": ("Riley Chen",     "@rileyfit"),
            "demo_007": ("Taylor Brooks",  "@tbrooks"),
            "demo_008": ("Drew Martinez",  "@drewruns"),
            "demo_009": ("Quinn Anderson", "@quinn_bjj"),
            "demo_010": ("Blake Foster",   "@bfoster"),
        ]

        // First 15 posts — (postId, authorId, activityType)
        let targetPosts: [(String, String, String)] = [
            ("demo_post_001", "demo_002", "iron"),
            ("demo_post_002", "demo_002", "iron"),
            ("demo_post_003", "demo_006", "iron"),
            ("demo_post_004", "demo_003", "run"),
            ("demo_post_005", "demo_003", "run"),
            ("demo_post_006", "demo_008", "run"),
            ("demo_post_007", "demo_008", "run"),
            ("demo_post_008", "demo_001", "striking"),
            ("demo_post_009", "demo_001", "striking"),
            ("demo_post_010", "demo_007", "striking"),
            ("demo_post_011", "demo_007", "striking"),
            ("demo_post_012", "demo_005", "grappling"),
            ("demo_post_013", "demo_005", "grappling"),
            ("demo_post_014", "demo_009", "grappling"),
            ("demo_post_015", "demo_009", "grappling"),
        ]

        let allUserIds = Array(userInfo.keys)

        for (postId, authorId, activityType) in targetPosts {
            // Pick comment pool by type
            let pool: [String]
            switch activityType {
            case "iron":       pool = ironComments
            case "striking":   pool = strikingComments
            case "grappling":  pool = grapplingComments
            case "wall":       pool = wallComments
            default:           pool = runComments
            }

            // Pick 2-4 commenters that are not the post author, no duplicates
            let candidates = allUserIds.filter { $0 != authorId }.shuffled()
            let commentCount = 2 + (candidates.hashValue % 3 < 2 ? candidates.hashValue % 3 : 2) // 2–4
            let commenters = Array(candidates.prefix(max(2, min(4, candidates.count))))
            let commentTexts = pool.shuffled()

            var count = 0
            for (index, commenterId) in commenters.enumerated() {
                guard let commenterInfo = userInfo[commenterId] else { continue }
                let commentId = UUID().uuidString
                let offsetSeconds = Double(index + 1) * 1_800 // 30-min gaps
                let ts = Date(timeIntervalSinceNow: -86_400 + offsetSeconds).timeIntervalSince1970 * 1_000
                let text = commentTexts[index % commentTexts.count]

                let commentData: [String: Any] = [
                    "data": [
                        "id": commentId,
                        "activityId": postId,
                        "userId": commenterId,
                        "displayName": commenterInfo.0,
                        "username": commenterInfo.1,
                        "text": text,
                        "createdAt": ts,
                    ] as [String: Any],
                ]

                try? await db.collection("comments")
                    .document(postId)
                    .collection("entries")
                    .document(commentId)
                    .setData(commentData)
                count += 1
            }

            // Update commentCount on the post document
            if count > 0 {
                try? await db.collection("activity")
                    .document(postId)
                    .updateData(["data.commentCount": count])
            }
        }
    }

    // MARK: - Seed Kudos

    private func seedKudos() async {
        // All 25 posts — (postId, authorId) pairs
        let allPosts: [(String, String)] = [
            ("demo_post_001", "demo_002"), ("demo_post_002", "demo_002"),
            ("demo_post_003", "demo_006"), ("demo_post_004", "demo_003"),
            ("demo_post_005", "demo_003"), ("demo_post_006", "demo_008"),
            ("demo_post_007", "demo_008"), ("demo_post_008", "demo_001"),
            ("demo_post_009", "demo_001"), ("demo_post_010", "demo_007"),
            ("demo_post_011", "demo_007"), ("demo_post_012", "demo_005"),
            ("demo_post_013", "demo_005"), ("demo_post_014", "demo_009"),
            ("demo_post_015", "demo_009"), ("demo_post_016", "demo_004"),
            ("demo_post_017", "demo_004"), ("demo_post_018", "demo_010"),
            ("demo_post_019", "demo_010"), ("demo_post_020", "demo_006"),
            ("demo_post_021", "demo_003"), ("demo_post_022", "demo_001"),
            ("demo_post_023", "demo_009"), ("demo_post_024", "demo_004"),
            ("demo_post_025", "demo_008"),
        ]

        let allUserIds = [
            "demo_001", "demo_002", "demo_003", "demo_004", "demo_005",
            "demo_006", "demo_007", "demo_008", "demo_009", "demo_010",
        ]

        for (postId, authorId) in allPosts {
            let candidates = allUserIds.filter { $0 != authorId }.shuffled()
            // 3–8 kudos per post
            let kudosCountSeed = abs(postId.hashValue) % 6
            let kudosCount = 3 + kudosCountSeed  // 3 to 8
            let likers = Array(candidates.prefix(kudosCount))
            let now = Date().timeIntervalSince1970

            for likerId in likers {
                await writeKudo(postId: postId, userId: likerId, likedAt: now)
            }

            // Update kudosCount on the post document
            try? await db.collection("activity")
                .document(postId)
                .updateData(["data.kudosCount": likers.count])
        }
    }

    private func writeKudo(postId: String, userId: String, likedAt: Double) async {
        try? await db.collection("kudos")
            .document(postId)
            .collection("likes")
            .document(userId)
            .setData(["likedAt": likedAt])
    }

    // MARK: - Private Write Helpers

    private func writeFeedItem(_ item: FeedItem) async {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        guard let data = try? encoder.encode(item),
              var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return }
        // Firestore rejects nested arrays ([[Double]]). Serialize routeCoordinates as JSON string.
        if let coords = json["routeCoordinates"],
           let coordData = try? JSONSerialization.data(withJSONObject: coords) {
            json["routeCoordinates"] = String(data: coordData, encoding: .utf8)
        }
        try? await db.collection("activity")
            .document(item.id)
            .setData([
                "data": json,
                "postedAt": item.postedAt.timeIntervalSince1970 * 1_000
            ])
    }

    private func writeUser(_ profile: UserProfile) async {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        guard let data = try? encoder.encode(profile),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return }
        try? await db.collection("users")
            .document(profile.id)
            .setData(["data": json])
    }
}
