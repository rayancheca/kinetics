import SwiftUI

// MARK: - ProfileViewModel

@Observable @MainActor
final class ProfileViewModel {
    var sessions: [SessionResult] = []
    var isLoading = false

    var totalCount: Int { sessions.count }

    var totalHours: Double { sessions.reduce(0) { $0 + $1.duration } / 3600 }

    var favoriteModule: SportType? {
        let counts = Dictionary(grouping: sessions, by: \.sport).mapValues(\.count)
        return counts.max(by: { $0.value < $1.value })?.key
    }

    var longestStreak: Int {
        let cal = Calendar.current
        let days = Set(sessions.map { cal.startOfDay(for: $0.startedAt) }).sorted(by: >)
        var streak = 0
        var current = 0
        var prev: Date? = nil
        for day in days {
            if let p = prev, cal.dateComponents([.day], from: day, to: p).day == 1 {
                current += 1
            } else {
                current = 1
            }
            streak = max(streak, current)
            prev = day
        }
        return streak
    }

    func load(for userId: String) async {
        isLoading = true
        sessions = (try? await SessionRepository.shared.fetchSessions(for: userId, limit: 200)) ?? []
        isLoading = false
    }
}

// MARK: - ProfileView

struct ProfileView: View {
    @Environment(AppState.self) private var appState
    @State private var vm = ProfileViewModel()
    @State private var showSignIn = false
    @State private var confirmSignOut = false
    @AppStorage("preferred_units") private var preferredUnits = "mph"

    private var isAnonymous: Bool { appState.authManager.currentUser?.isAnonymous == true }

    private var displayName: String {
        if isAnonymous { return "Guest User" }
        return appState.authManager.currentUser?.email?
            .components(separatedBy: "@").first?
            .capitalized ?? "Athlete"
    }

    private var initials: String { String(displayName.prefix(1)).uppercased() }

    private var appVersion: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "1.0"
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 24) {
                    avatarSection
                    statsGrid
                    settingsSection
                    Text("Kinetics v\(appVersion)")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.2))
                        .padding(.bottom, 40)
                }
            }
            .background(Color.kineticsBackground)
            .navigationBarHidden(true)
            .sheet(isPresented: $showSignIn) {
                SignInSheet().environment(appState)
            }
            .confirmationDialog("Sign Out", isPresented: $confirmSignOut) {
                Button("Sign Out", role: .destructive) {
                    try? appState.authManager.signOut()
                }
            }
            .task {
                if let uid = appState.authManager.currentUser?.uid {
                    await vm.load(for: uid)
                }
            }
        }
    }

    // MARK: - Subviews

    private var avatarSection: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle().fill(Color.kineticsBlue).frame(width: 72, height: 72)
                Text(initials)
                    .font(.system(size: 28, weight: .black))
                    .foregroundStyle(Color.kineticsDark)
            }
            Text(displayName)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.white)

            if isAnonymous {
                Button { showSignIn = true } label: {
                    Text("Sign in to save progress")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.kineticsBlue)
                }
            } else {
                Text(appState.authManager.currentUser?.email ?? "")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.38))
            }
        }
        .padding(.top, 8)
    }

    private var statsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            StatCard(
                value: "\(vm.totalCount)",
                label: "Total Sessions",
                icon: "figure.run",
                color: .kineticsBlue
            )
            StatCard(
                value: String(format: "%.1fh", vm.totalHours),
                label: "Total Time",
                icon: "clock.fill",
                color: .kineticsGreen
            )
            StatCard(
                value: vm.favoriteModule?.displayName ?? "—",
                label: "Favorite Module",
                icon: "star.fill",
                color: Color(hex: "FFB800")
            )
            StatCard(
                value: "\(vm.longestStreak)d",
                label: "Best Streak",
                icon: "flame.fill",
                color: .kineticsRed
            )
        }
        .padding(.horizontal, 16)
    }

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("SETTINGS")
                .font(.system(size: 10, weight: .semibold))
                .tracking(2.5)
                .foregroundStyle(.white.opacity(0.38))
                .padding(.horizontal, 20)
                .padding(.bottom, 10)

            VStack(spacing: 0) {
                NavigationLink(destination: SubscriptionView()) {
                    HStack {
                        Image(systemName: "star.fill")
                            .font(.system(size: 15))
                            .foregroundStyle(Color.kineticsAmber)
                            .frame(width: 28)
                        Text("Premium")
                            .font(.system(size: 15))
                            .foregroundStyle(.white)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.2))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                }

                Divider().background(.white.opacity(0.06)).padding(.horizontal, 14)

                SettingsRow(icon: "camera.fill", label: "Camera Permissions") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }

                Divider().background(.white.opacity(0.06)).padding(.horizontal, 14)

                NavigationLink(destination: NotificationSettingsView()) {
                    HStack {
                        Image(systemName: "bell.badge.fill")
                            .font(.system(size: 15))
                            .foregroundStyle(Color.kineticsBlue)
                            .frame(width: 28)
                        Text("Notifications")
                            .font(.system(size: 15))
                            .foregroundStyle(.white)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.2))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                }

                Divider().background(.white.opacity(0.06)).padding(.horizontal, 14)

                coachVoiceToggle

                Divider().background(.white.opacity(0.06)).padding(.horizontal, 14)

                unitsPicker

                Divider().background(.white.opacity(0.06)).padding(.horizontal, 14)

                SettingsRow(icon: "info.circle", label: "App Version \(appVersion)") { }

                if !isAnonymous {
                    Divider().background(.white.opacity(0.06)).padding(.horizontal, 14)
                    signOutRow
                }
            }
            .background(Color.kineticsDark)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(.horizontal, 16)
        }
    }

    private var coachVoiceToggle: some View {
        Toggle(isOn: Binding(
            get: { UserDefaults.standard.bool(forKey: "coach_voice_enabled") },
            set: { UserDefaults.standard.set($0, forKey: "coach_voice_enabled") }
        )) {
            Label("Coach Voice", systemImage: "waveform")
                .font(.system(size: 15))
                .foregroundStyle(.white)
        }
        .tint(Color.kineticsBlue)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var unitsPicker: some View {
        HStack {
            Image(systemName: "ruler")
                .font(.system(size: 15))
                .foregroundStyle(Color.kineticsBlue)
                .frame(width: 28)
            Text("Units")
                .font(.system(size: 15))
                .foregroundStyle(.white)
            Spacer()
            Picker("Units", selection: $preferredUnits) {
                Text("mph").tag("mph")
                Text("km/h").tag("kmh")
                Text("m/s").tag("ms")
            }
            .pickerStyle(.segmented)
            .frame(width: 140)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var signOutRow: some View {
        Button { confirmSignOut = true } label: {
            HStack {
                Image(systemName: "rectangle.portrait.and.arrow.right")
                    .font(.system(size: 15))
                    .foregroundStyle(Color.kineticsRed)
                    .frame(width: 28)
                Text("Sign Out")
                    .font(.system(size: 15))
                    .foregroundStyle(Color.kineticsRed)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
    }
}

// MARK: - StatCard

struct StatCard: View {
    let value: String
    let label: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(color)
            Text(value)
                .font(.system(size: 22, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.45))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.kineticsDark)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

// MARK: - SettingsRow

struct SettingsRow: View {
    let icon: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 15))
                    .foregroundStyle(Color.kineticsBlue)
                    .frame(width: 28)
                Text(label)
                    .font(.system(size: 15))
                    .foregroundStyle(.white)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.2))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
    }
}
