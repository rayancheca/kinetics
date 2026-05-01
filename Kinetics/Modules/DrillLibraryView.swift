import SwiftUI

// MARK: - DrillDifficulty

enum DrillDifficulty: String, CaseIterable, Identifiable {
    case beginner     = "Beginner"
    case intermediate = "Intermediate"
    case advanced     = "Advanced"

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .beginner:     return .kineticsGreen
        case .intermediate: return .kineticsAmber
        case .advanced:     return .kineticsRed
        }
    }
}

// MARK: - Drill

struct Drill: Identifiable, Equatable {
    let id: UUID
    let sport: SportType
    let name: String
    let summary: String
    let difficulty: DrillDifficulty
    let focusArea: String
    let durationMinutes: Int
    let keyPoints: [String]
    let metric: String
}

// MARK: - DrillLibrary

enum DrillLibrary {

    // MARK: All Drills

    static let all: [Drill] = striking + grappling + ironTracker + wallBeta

    // MARK: Striking

    private static let striking: [Drill] = [
        Drill(
            id: UUID(),
            sport: .striking,
            name: "Hip Fire Isolation",
            summary: "Isolate hip rotation to generate power from the ground up.",
            difficulty: .beginner,
            focusArea: "Hip rotation",
            durationMinutes: 5,
            keyPoints: [
                "Plant rear foot, drive heel into floor",
                "Initiate all rotation from hip — not shoulder",
                "Keep hands up throughout"
            ],
            metric: "Watch hip-shoulder separation angle on each rep"
        ),
        Drill(
            id: UUID(),
            sport: .striking,
            name: "Kinetic Chain Shadow",
            summary: "Shadow box at 50% power focusing on sequential joint firing.",
            difficulty: .intermediate,
            focusArea: "Full-body coordination",
            durationMinutes: 8,
            keyPoints: [
                "Floor → hips → shoulders → fist in sequence",
                "Pause between punches to feel the chain",
                "Film from the side to check shoulder lag"
            ],
            metric: "Use Striking module to verify hip leads shoulder by 0.1–0.15s"
        ),
        Drill(
            id: UUID(),
            sport: .striking,
            name: "Wall Touch Speed Drill",
            summary: "Touch a wall target with maximum velocity, not power.",
            difficulty: .intermediate,
            focusArea: "Strike velocity",
            durationMinutes: 6,
            keyPoints: [
                "Stay relaxed until the last 30% of extension",
                "Snap the wrist at contact",
                "Reset stance in under 0.3s"
            ],
            metric: "Aim for velocity above 18mph on each touch"
        ),
        Drill(
            id: UUID(),
            sport: .striking,
            name: "Stance Recovery Pyramid",
            summary: "Practice returning to base stance at increasing speeds.",
            difficulty: .beginner,
            focusArea: "Recovery speed",
            durationMinutes: 4,
            keyPoints: [
                "Strike — reset — immediately strike again",
                "Width should match shoulder width on reset",
                "Time your resets with a 0.5s metronome"
            ],
            metric: "Track stance width recovery time in Striking module"
        ),
        Drill(
            id: UUID(),
            sport: .striking,
            name: "High Guard Rotation",
            summary: "Maintain shoulder guard while firing full hip rotation.",
            difficulty: .advanced,
            focusArea: "Defense-offense transition",
            durationMinutes: 10,
            keyPoints: [
                "Non-striking shoulder must stay above chin line",
                "Lead shoulder dips only on the strike side",
                "Film from front to verify guard integrity"
            ],
            metric: "Shoulder separation > 45° while guard stays above 60°"
        ),
        Drill(
            id: UUID(),
            sport: .striking,
            name: "Reaction Strike Ladder",
            summary: "Strike on audio cue, increasing frequency each round.",
            difficulty: .advanced,
            focusArea: "Reaction time + velocity",
            durationMinutes: 12,
            keyPoints: [
                "One strike per beep, no anticipation",
                "Maintain form at high frequency",
                "Drop to 70% speed when form breaks"
            ],
            metric: "Measure average velocity consistency across all strikes"
        )
    ]

    // MARK: Grappling

    private static let grappling: [Drill] = [
        Drill(
            id: UUID(),
            sport: .grappling,
            name: "Base Squat Hold",
            summary: "Hold a wide sumo squat at various hip heights to build base awareness.",
            difficulty: .beginner,
            focusArea: "Base stability",
            durationMinutes: 3,
            keyPoints: [
                "Hips lower than knees = compromised base",
                "Weight must stay centered over feet",
                "If pushed, sink rather than step"
            ],
            metric: "CoM stays within 10cm of base polygon center"
        ),
        Drill(
            id: UUID(),
            sport: .grappling,
            name: "Kuzushi Entry Drill",
            summary: "Practice breaking uke's balance before committing to a throw.",
            difficulty: .intermediate,
            focusArea: "Off-balancing",
            durationMinutes: 7,
            keyPoints: [
                "Pull in the direction of easiest movement",
                "Feel the weight shift before initiating kake",
                "Do not rush — kuzushi precedes throw by 0.3–0.5s"
            ],
            metric: "Spine angle deviation > 15° before throw entry"
        ),
        Drill(
            id: UUID(),
            sport: .grappling,
            name: "Hip Bridge Series",
            summary: "Ground bridging to develop explosive hip elevation for sweeps.",
            difficulty: .beginner,
            focusArea: "Hip elevation",
            durationMinutes: 5,
            keyPoints: [
                "Drive from shoulder blades and heels simultaneously",
                "Peak height at full hip extension",
                "Explode up — slow the descent"
            ],
            metric: "Track hip elevation angle with Grappling module"
        ),
        Drill(
            id: UUID(),
            sport: .grappling,
            name: "Turtle Break Circuit",
            summary: "Practice extracting hooks and breaking turtle from multiple angles.",
            difficulty: .intermediate,
            focusArea: "Positional control",
            durationMinutes: 8,
            keyPoints: [
                "Control the head — body follows",
                "Use your hip as a lever not your arms",
                "Set grips before committing to direction"
            ],
            metric: "CoM projection stays over base through entire sequence"
        ),
        Drill(
            id: UUID(),
            sport: .grappling,
            name: "Uchi-Mata Entry Flow",
            summary: "Chain kuzushi into uchi-mata in a continuous flow drill.",
            difficulty: .advanced,
            focusArea: "Throw mechanics",
            durationMinutes: 10,
            keyPoints: [
                "Off-balance before ANY footwork",
                "Driving leg sweeps on the way up, not down",
                "Maintain upright posture throughout the entry"
            ],
            metric: "Spine stays within 10° of vertical through kuzushi"
        ),
        Drill(
            id: UUID(),
            sport: .grappling,
            name: "Postural Reset Under Pressure",
            summary: "Partner applies progressive pressure while you restore upright posture.",
            difficulty: .advanced,
            focusArea: "Posture recovery",
            durationMinutes: 6,
            keyPoints: [
                "Reset from hips up, not from shoulders",
                "Use stiff arm to create frames before posturing",
                "Breathe out on each reset attempt"
            ],
            metric: "Postural alert rate drops below 2 per minute"
        )
    ]

    // MARK: Iron Tracker

    private static let ironTracker: [Drill] = [
        Drill(
            id: UUID(),
            sport: .ironTracker,
            name: "Bar Path Visualization",
            summary: "Trace the ideal bar path in the air with a PVC pipe before loading.",
            difficulty: .beginner,
            focusArea: "Bar path",
            durationMinutes: 4,
            keyPoints: [
                "Squat: bar should track over mid-foot",
                "Deadlift: vertical path from floor to lockout",
                "Bench: slight arc from chest to lockout"
            ],
            metric: "Bar path deviation under 3cm from ideal line"
        ),
        Drill(
            id: UUID(),
            sport: .ironTracker,
            name: "Tempo Squat (3-1-1)",
            summary: "3 second descent, 1 second pause at bottom, 1 second ascent.",
            difficulty: .beginner,
            focusArea: "Movement quality",
            durationMinutes: 8,
            keyPoints: [
                "Maintain braced core throughout pause",
                "No knees caving on the ascent",
                "Drive through full foot, not just heel"
            ],
            metric: "Bar velocity stays > 0.2m/s at bottom of lift"
        ),
        Drill(
            id: UUID(),
            sport: .ironTracker,
            name: "Butt Wink Correction",
            summary: "Identify and correct posterior pelvic tilt at squat depth.",
            difficulty: .intermediate,
            focusArea: "Lumbar positioning",
            durationMinutes: 6,
            keyPoints: [
                "Use box behind to stop at depth threshold",
                "Check with side camera — neutral spine at depth",
                "Adjust stance width until tilt disappears"
            ],
            metric: "Lumbar-pelvis angle change < 10° from standing to depth"
        ),
        Drill(
            id: UUID(),
            sport: .ironTracker,
            name: "Bilateral Symmetry Press",
            summary: "Single-arm dumbbell press on a bench to isolate and equalise each side.",
            difficulty: .intermediate,
            focusArea: "Symmetry",
            durationMinutes: 7,
            keyPoints: [
                "Match ROM on both sides — film from in front",
                "Weaker side leads the set",
                "Stop set when deviation exceeds 15°"
            ],
            metric: "Left-right wrist ascent speed within 5% of each other"
        ),
        Drill(
            id: UUID(),
            sport: .ironTracker,
            name: "VBT Cluster Set",
            summary: "Perform cluster sets (3+3+3) with 15s rest, targeting velocity zone.",
            difficulty: .advanced,
            focusArea: "Velocity-based training",
            durationMinutes: 15,
            keyPoints: [
                "Mean velocity target: 0.4–0.6m/s for strength zone",
                "Drop weight if velocity drops below 0.3m/s",
                "Rest until velocity is fully recovered"
            ],
            metric: "Mean concentric velocity per rep logged in Iron Tracker"
        ),
        Drill(
            id: UUID(),
            sport: .ironTracker,
            name: "Deadlift Bar Contact Drill",
            summary: "Drag the bar up the shins maintaining full contact from floor to lockout.",
            difficulty: .advanced,
            focusArea: "Bar path + leg drive",
            durationMinutes: 10,
            keyPoints: [
                "Bar stays within 1cm of leg surface throughout",
                "Over-the-knee: hips drive forward to complete",
                "Shins must be vertical at bar break from floor"
            ],
            metric: "Bar path vertical deviation under 2cm on each rep"
        )
    ]

    // MARK: Wall Beta

    private static let wallBeta: [Drill] = [
        Drill(
            id: UUID(),
            sport: .wallBeta,
            name: "Hip Drop Awareness",
            summary: "On an easy juggy route, focus on keeping hips as close to wall as possible.",
            difficulty: .beginner,
            focusArea: "Hip proximity",
            durationMinutes: 5,
            keyPoints: [
                "Hips within 20cm of wall = weight on feet",
                "Sag = arms bear load = pump",
                "Turn hips to wall on feet-only sequences"
            ],
            metric: "Hip proximity score above 70% throughout route"
        ),
        Drill(
            id: UUID(),
            sport: .wallBeta,
            name: "Flag Practice Sequence",
            summary: "Practice inside and outside flag positions on a vertical wall.",
            difficulty: .beginner,
            focusArea: "Body tension",
            durationMinutes: 6,
            keyPoints: [
                "Flag leg extends in line with hip, not below",
                "Maintain tension — a limp flag does nothing",
                "Feel which hand bears more load when flagging"
            ],
            metric: "CoM stays projected over active foothold during flag"
        ),
        Drill(
            id: UUID(),
            sport: .wallBeta,
            name: "Smearing Session",
            summary: "Dedicate a session to slabs or volumes using only smears.",
            difficulty: .intermediate,
            focusArea: "Footwork",
            durationMinutes: 8,
            keyPoints: [
                "More rubber = more friction — press full sole",
                "Keep weight over smearing foot",
                "Move slowly — speed reduces smear friction"
            ],
            metric: "Track time-on-hold to measure weight distribution"
        ),
        Drill(
            id: UUID(),
            sport: .wallBeta,
            name: "Dyno Preparation Drill",
            summary: "Practice loading and launching from low dynos (matched start, jump 30cm up).",
            difficulty: .intermediate,
            focusArea: "Dynamic movement",
            durationMinutes: 10,
            keyPoints: [
                "Compress fully — hips drop before launch",
                "Target hand reaches at peak trajectory, not on the way up",
                "Both hands match before leaving the start hold"
            ],
            metric: "Dyno arc smoothness score tracked by Wall Beta module"
        ),
        Drill(
            id: UUID(),
            sport: .wallBeta,
            name: "Roof Hip Drive",
            summary: "On a 30–45° overhang, practice driving hips toward the wall on each move.",
            difficulty: .advanced,
            focusArea: "Overhang technique",
            durationMinutes: 12,
            keyPoints: [
                "One hip high — one hip low on each reach",
                "Hip drive must happen before hand leaves hold",
                "Squeeze core: prevent full-body sag between moves"
            ],
            metric: "Hip sag events drop to zero per sequence"
        ),
        Drill(
            id: UUID(),
            sport: .wallBeta,
            name: "Silent Feet Protocol",
            summary: "Climb a route making zero noise with your feet. Any scrape = restart.",
            difficulty: .advanced,
            focusArea: "Precision footwork",
            durationMinutes: 10,
            keyPoints: [
                "Look at each foothold until weight is committed",
                "Place heel first, then roll to rubber toe box",
                "Feet set position = hand reach position"
            ],
            metric: "Time-under-tension per hold increases as precision improves"
        )
    ]
}

// MARK: - DrillLibraryView

struct DrillLibraryView: View {

    @Environment(\.dismiss) private var dismiss
    @State private var vm = DrillLibraryViewModel()

    // MARK: Body

    var body: some View {
        NavigationStack {
            ZStack {
                Color.kineticsBackground.ignoresSafeArea()

                VStack(spacing: 0) {
                    headerBar
                    sportSelectorBar
                    difficultyFilterBar
                    searchBar
                    drillList
                }
            }
        }
    }

    // MARK: Header Bar

    private var headerBar: some View {
        HStack {
            Text("DRILL LIBRARY")
                .font(.system(size: 20, weight: .black))
                .tracking(4)
                .foregroundStyle(.white)

            Spacer()

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.kineticsSubtext)
                    .frame(width: 32, height: 32)
                    .background(Color.kineticsMidGray)
                    .clipShape(Circle())
            }
            .buttonStyle(ScaleButtonStyle())
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 16)
    }

    // MARK: Sport Selector Bar

    private var sportSelectorBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(SportType.allCases, id: \.self) { sport in
                    sportPill(sport)
                }

                favoritesPill
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
        }
        .padding(.bottom, 12)
    }

    private func sportPill(_ sport: SportType) -> some View {
        let isSelected = vm.selectedSport == sport && !vm.showingFavorites
        let accent = Color.moduleColor(for: sport)

        return Button {
            vm.showingFavorites = false
            vm.selectedSport = sport
        } label: {
            HStack(spacing: 6) {
                Image(systemName: sport.systemImage)
                    .font(.system(size: 12, weight: .semibold))
                Text(sport.displayName)
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(isSelected ? .black : .white)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(isSelected ? accent : Color.kineticsMidGray)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(
                        isSelected ? Color.clear : accent.opacity(0.25),
                        lineWidth: 0.75
                    )
            )
        }
        .buttonStyle(ScaleButtonStyle())
    }

    private var favoritesPill: some View {
        Button {
            vm.showingFavorites = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: vm.showingFavorites ? "heart.fill" : "heart")
                    .font(.system(size: 12, weight: .semibold))
                Text("Favorites")
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(vm.showingFavorites ? .black : .white)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(vm.showingFavorites ? Color.kineticsRed : Color.kineticsMidGray)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(
                        vm.showingFavorites ? Color.clear : Color.kineticsRed.opacity(0.25),
                        lineWidth: 0.75
                    )
            )
        }
        .buttonStyle(ScaleButtonStyle())
    }

    // MARK: Difficulty Filter Bar

    private var difficultyFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                difficultyChip(nil, label: "All")

                ForEach(DrillDifficulty.allCases) { difficulty in
                    difficultyChip(difficulty, label: difficulty.rawValue)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 2)
        }
        .padding(.bottom, 12)
    }

    private func difficultyChip(_ difficulty: DrillDifficulty?, label: String) -> some View {
        let isSelected = vm.selectedDifficulty == difficulty
        let chipColor: Color = difficulty?.color ?? .white

        return Button {
            vm.selectedDifficulty = difficulty
        } label: {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isSelected ? .black : chipColor)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? chipColor : chipColor.opacity(0.12))
                .clipShape(Capsule())
        }
        .buttonStyle(ScaleButtonStyle())
    }

    // MARK: Search Bar

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color.kineticsSubtext)

            ZStack(alignment: .leading) {
                if vm.searchText.isEmpty {
                    Text("Search drills or focus areas…")
                        .foregroundStyle(Color.kineticsSubtext)
                        .font(.system(size: 15))
                }
                TextField("", text: $vm.searchText)
                    .font(.system(size: 15))
                    .foregroundStyle(.white)
            }

            if !vm.searchText.isEmpty {
                Button {
                    vm.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(Color.kineticsSubtext)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(Color.kineticsMidGray)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal, 16)
        .padding(.bottom, 14)
    }

    // MARK: Drill List

    private var drillList: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: 12) {
                let drills = vm.filteredDrills
                if drills.isEmpty {
                    emptyState
                        .padding(.top, 60)
                } else {
                    ForEach(drills) { drill in
                        DrillCard(
                            drill: drill,
                            isFavorited: vm.isFavorited(drill),
                            onFavorite: { vm.toggleFavorite(drill) }
                        )
                        .padding(.horizontal, 16)
                    }
                }
            }
            .padding(.bottom, 40)
        }
    }

    // MARK: Empty State

    private var emptyState: some View {
        let iconName: String = vm.showingFavorites
            ? "heart.slash"
            : vm.selectedSport.systemImage

        return VStack(spacing: 16) {
            Image(systemName: iconName)
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(Color.kineticsSubtext)

            VStack(spacing: 6) {
                Text(vm.showingFavorites ? "No favorites yet" : "No drills match")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)

                Text(
                    vm.showingFavorites
                        ? "Tap the heart on any drill to save it here."
                        : "Try adjusting your filters or search query."
                )
                .font(.system(size: 13))
                .foregroundStyle(Color.kineticsSubtext)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            }
        }
    }
}

// MARK: - DrillCard

struct DrillCard: View {

    let drill: Drill
    let isFavorited: Bool
    let onFavorite: () -> Void

    @State private var isExpanded = false

    private var accent: Color { Color.moduleColor(for: drill.sport) }

    // MARK: Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerRow
                .padding(.top, 14)
                .padding(.horizontal, 14)

            focusLabel
                .padding(.horizontal, 14)
                .padding(.top, 6)

            summaryText
                .padding(.horizontal, 14)
                .padding(.top, 5)
                .padding(.bottom, 14)

            if isExpanded {
                Divider()
                    .background(Color.kineticsMidGray)

                expandedContent
                    .padding(.horizontal, 14)
                    .padding(.vertical, 14)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(Color.kineticsDark)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(accent)
                .frame(width: 3)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.72)) {
                isExpanded.toggle()
            }
        }
    }

    // MARK: Header Row

    private var headerRow: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 6) {
                Text(drill.name)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 6) {
                    difficultyBadge
                    durationBadge
                }
            }

            Spacer()

            HStack(spacing: 10) {
                favoriteButton
                chevronIcon
            }
            .padding(.top, 2)
        }
    }

    private var difficultyBadge: some View {
        Text(drill.difficulty.rawValue)
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.5)
            .foregroundStyle(drill.difficulty.color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(drill.difficulty.color.opacity(0.12))
            .clipShape(Capsule())
    }

    private var durationBadge: some View {
        HStack(spacing: 3) {
            Image(systemName: "clock")
                .font(.system(size: 9, weight: .semibold))
            Text("\(drill.durationMinutes) min")
                .font(.system(size: 10, weight: .medium))
        }
        .foregroundStyle(Color.kineticsSubtext)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Color.kineticsMidGray)
        .clipShape(Capsule())
    }

    private var favoriteButton: some View {
        Button(action: onFavorite) {
            Image(systemName: isFavorited ? "heart.fill" : "heart")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(isFavorited ? Color.kineticsRed : Color.kineticsSubtext)
        }
        .buttonStyle(ScaleButtonStyle())
    }

    private var chevronIcon: some View {
        Image(systemName: "chevron.down")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Color.kineticsSubtext)
            .rotationEffect(.degrees(isExpanded ? 180 : 0))
            .animation(.spring(response: 0.32, dampingFraction: 0.72), value: isExpanded)
    }

    // MARK: Focus Label

    private var focusLabel: some View {
        Text(drill.focusArea.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .tracking(1.5)
            .foregroundStyle(accent)
    }

    // MARK: Summary

    private var summaryText: some View {
        Text(drill.summary)
            .font(.system(size: 13))
            .foregroundStyle(.white.opacity(0.55))
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Expanded Content

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            keyPointsSection
            metricTip
        }
    }

    private var keyPointsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("KEY POINTS")
                .font(.system(size: 9, weight: .semibold))
                .tracking(2)
                .foregroundStyle(Color.kineticsSubtext)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(drill.keyPoints, id: \.self) { point in
                    HStack(alignment: .top, spacing: 8) {
                        Circle()
                            .fill(accent)
                            .frame(width: 5, height: 5)
                            .padding(.top, 5)

                        Text(point)
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.85))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private var metricTip: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(accent)
                .padding(.top, 1)

            Text(drill.metric)
                .font(.system(size: 12).italic())
                .foregroundStyle(accent.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(accent.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(accent.opacity(0.2), lineWidth: 0.75)
        )
    }
}

// MARK: - DrillLibraryViewModel

@Observable
@MainActor
final class DrillLibraryViewModel {

    // MARK: State

    var selectedSport: SportType = .striking
    var selectedDifficulty: DrillDifficulty? = nil
    var searchText: String = ""
    var showingFavorites: Bool = false
    var favoritedIds: Set<UUID> = []

    private let favoritesKey = "drill_favorites"

    // MARK: Init

    init() {
        loadFavorites()
    }

    // MARK: Computed

    var filteredDrills: [Drill] {
        let pool: [Drill]
        if showingFavorites {
            pool = DrillLibrary.all.filter { favoritedIds.contains($0.id) }
        } else {
            pool = DrillLibrary.all.filter { $0.sport == selectedSport }
        }

        return pool
            .filter { selectedDifficulty == nil || $0.difficulty == selectedDifficulty }
            .filter {
                guard !searchText.isEmpty else { return true }
                return $0.name.localizedCaseInsensitiveContains(searchText)
                    || $0.focusArea.localizedCaseInsensitiveContains(searchText)
            }
    }

    // MARK: Favorites

    func toggleFavorite(_ drill: Drill) {
        if favoritedIds.contains(drill.id) {
            favoritedIds.remove(drill.id)
        } else {
            favoritedIds.insert(drill.id)
        }
        persistFavorites()
    }

    func isFavorited(_ drill: Drill) -> Bool {
        favoritedIds.contains(drill.id)
    }

    // MARK: Persistence

    private func persistFavorites() {
        let joined = favoritedIds
            .map(\.uuidString)
            .joined(separator: ",")
        UserDefaults.standard.set(joined, forKey: favoritesKey)
    }

    private func loadFavorites() {
        guard let stored = UserDefaults.standard.string(forKey: favoritesKey),
              !stored.isEmpty else { return }
        let ids = stored
            .split(separator: ",")
            .compactMap { UUID(uuidString: String($0)) }
        favoritedIds = Set(ids)
    }
}
