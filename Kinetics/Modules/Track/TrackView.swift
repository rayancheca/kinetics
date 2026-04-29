import SwiftUI

// MARK: - TrackView

/// Tab entry point for the GPS workout tracking module.
///
/// Displays an activity type picker and a full-width START button when no
/// workout is active. Navigates to `ActiveWorkoutView` when recording begins.
/// A history shortcut in the top-right links to `WorkoutHistoryView`.
///
/// This view owns the `TrackViewModel` via `@State` so the instance is tied
/// to the tab's lifetime — not the NavigationStack — allowing the header
/// stats to survive back-navigation from the active workout screen.
struct TrackView: View {

    // MARK: - State

    @State private var viewModel = TrackViewModel()
    @State private var isNavigatingToWorkout = false
    @State private var isStarting = false

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                Color.kineticsBackground.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        headerSection
                        activityPickerSection
                        startButton
                        todayStatsSection
                        Spacer(minLength: 32)
                    }
                }
            }
            .navigationBarHidden(true)
            .navigationDestination(isPresented: $isNavigatingToWorkout) {
                ActiveWorkoutView(viewModel: viewModel)
            }
            .task {
                await viewModel.requestPermissions()
            }
            .fullScreenCover(isPresented: $viewModel.showSummary) {
                if let result = viewModel.lastCompletedWorkout {
                    WorkoutSummaryView(workout: result)
                }
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("TRACK")
                    .font(.system(size: 34, weight: .black))
                    .tracking(6)
                    .foregroundStyle(.white)
                Text(headerSubtitle)
                    .font(.system(size: 12, weight: .medium))
                    .tracking(0.8)
                    .foregroundStyle(.white.opacity(0.35))
            }

            Spacer()

            NavigationLink(destination: WorkoutHistoryView()) {
                HStack(spacing: 5) {
                    Text("History")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.kineticsBlue)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.kineticsBlue.opacity(0.8))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.kineticsBlue.opacity(0.12), in: Capsule())
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 56)
        .padding(.bottom, 28)
    }

    private var headerSubtitle: String {
        let name = viewModel.selectedActivityType.displayName.uppercased()
        return "READY TO \(name)"
    }

    // MARK: - Activity Picker

    private var activityPickerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ACTIVITY")
                .font(.system(size: 10, weight: .bold))
                .tracking(2.5)
                .foregroundStyle(.white.opacity(0.38))
                .padding(.horizontal, 20)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(WorkoutActivityType.allCases, id: \.self) { type in
                        ActivityPill(
                            type: type,
                            isSelected: viewModel.selectedActivityType == type
                        ) {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                viewModel.selectedActivityType = type
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 4)
            }
        }
        .padding(.bottom, 32)
    }

    // MARK: - Start Button

    private var startButton: some View {
        Button {
            guard !isStarting else { return }
            isStarting = true
            Task {
                await viewModel.startWorkout()
                isNavigatingToWorkout = true
                isStarting = false
            }
        } label: {
            ZStack {
                // Gradient background
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(hex: viewModel.selectedActivityType.accentColorHex),
                                Color(hex: viewModel.selectedActivityType.accentColorHex).opacity(0.75)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(height: 72)
                    // Subtle glow underneath the button
                    .shadow(
                        color: Color(hex: viewModel.selectedActivityType.accentColorHex).opacity(0.45),
                        radius: 18,
                        y: 6
                    )

                if isStarting {
                    HStack(spacing: 12) {
                        ProgressView()
                            .tint(Color.kineticsDark)
                            .scaleEffect(0.85)
                        Text("Starting…")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.kineticsDark)
                    }
                } else {
                    HStack(spacing: 12) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 16, weight: .black))
                            .foregroundStyle(Color.kineticsDark)

                        Text("START \(viewModel.selectedActivityType.displayName.uppercased())")
                            .font(.system(size: 18, weight: .black, design: .rounded))
                            .tracking(1.2)
                            .foregroundStyle(Color.kineticsDark)
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 36)
        .disabled(isStarting)
        .animation(.easeInOut(duration: 0.2), value: viewModel.selectedActivityType)
    }

    // MARK: - Today's Stats

    private var todayStatsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("TODAY")
                .font(.system(size: 10, weight: .bold))
                .tracking(2.5)
                .foregroundStyle(.white.opacity(0.38))
                .padding(.horizontal, 20)

            HStack(spacing: 12) {
                TodayStatCard(value: "2", label: "Workouts", icon: "bolt.fill", color: Color.kineticsBlue)
                TodayStatCard(value: "8.3 km", label: "Distance", icon: "location.fill", color: Color.kineticsGreen)
                TodayStatCard(value: "42:17", label: "Time", icon: "timer", color: Color.kineticsOrange)
            }
            .padding(.horizontal, 20)
        }
    }
}

// MARK: - ActivityPill

private struct ActivityPill: View {

    let type: WorkoutActivityType
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 7) {
                Image(systemName: type.systemImage)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.kineticsDark : Color(hex: type.accentColorHex))

                Text(type.displayName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.kineticsDark : .white)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background {
                Capsule()
                    .fill(
                        isSelected
                            ? Color(hex: type.accentColorHex)
                            : Color.white.opacity(0.07)
                    )
                    .overlay {
                        if !isSelected {
                            Capsule()
                                .strokeBorder(
                                    Color(hex: type.accentColorHex).opacity(0.25),
                                    lineWidth: 1
                                )
                        }
                    }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - TodayStatCard

private struct TodayStatCard: View {

    let value: String
    let label: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(color)
                .padding(8)
                .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 9, style: .continuous))

            Spacer()

            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.42))
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
        .background(Color(red: 0.08, green: 0.08, blue: 0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
        }
    }
}
