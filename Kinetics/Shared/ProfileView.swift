import FirebaseAuth
import FirebaseFirestore
import SwiftData
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
    @Environment(\.modelContext) private var modelContext
    @State private var vm = ProfileViewModel()
    @State private var showSignIn = false
    @State private var confirmSignOut = false
    @State private var showDeleteConfirm = false
    @State private var showFaceSetup = false
    @AppStorage("preferred_units") private var preferredUnits = "mph"
    @AppStorage("coach_voice_enabled") private var coachVoiceEnabled = true
    @AppStorage("onboarding_complete") private var onboardingComplete = true
    @AppStorage("auto_publish_sessions") private var autoPublishSessions = true
    @StateObject private var stravaAuth = StravaAuthService.shared

    // Body composition editing state
    @State private var heightCmText: String = ""
    @State private var ageText: String = ""
    @State private var weightKgText: String = ""
    @State private var skeletalMuscleText: String = ""
    @State private var hasFaceProfile = false
    @State private var badgesVM = AchievementsViewModel()
    @State private var selectedBadge: KineticsAchievementBadge? = nil

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

    private var buildNumber: String {
        (Bundle.main.infoDictionary?["CFBundleVersion"] as? String) ?? "1"
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 28) {
                    avatarSection
                    statsGrid
                    badgesSection
                    athleteSection
                    accountSection
                    preferencesSection
                    subscriptionSection
                    aboutSection
                }
                .padding(.bottom, 48)
            }
            .background(Color.kineticsBackground)
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showSignIn) {
                SignInSheet().environment(appState)
            }
            .confirmationDialog("Sign Out", isPresented: $confirmSignOut) {
                Button("Sign Out", role: .destructive) {
                    try? appState.authManager.signOut()
                }
            } message: {
                Text("You will be signed out of your account.")
            }
            .confirmationDialog(
                "Delete your account?",
                isPresented: $showDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button("Delete Everything", role: .destructive) {
                    Task { await deleteAccount() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This permanently deletes your sessions, progress, and profile. This cannot be undone.")
            }
            .task {
                if let uid = appState.authManager.currentUser?.uid {
                    await vm.load(for: uid)
                    loadBodyComposition(userId: uid)
                    hasFaceProfile = faceProfileExists(userId: uid)
                    await badgesVM.load(userId: uid)
                }
            }
            .sheet(item: $selectedBadge) { badge in
                BadgeDetailSheet(badge: badge)
            }
            .fullScreenCover(isPresented: $showFaceSetup) {
                if let uid = appState.authManager.currentUser?.uid {
                    FaceSetupView(userId: uid)
                        .onDisappear {
                            hasFaceProfile = faceProfileExists(userId: uid)
                        }
                }
            }
        }
    }

    // MARK: - Badges Section

    private var badgesSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("BADGES")
                .font(.system(size: 10, weight: .semibold))
                .tracking(2.5)
                .foregroundStyle(.white.opacity(0.38))
                .padding(.horizontal, 22)
                .padding(.bottom, 8)

            let allBadges = badgesVM.unlockedBadges + badgesVM.lockedBadges
            if allBadges.isEmpty {
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "trophy")
                            .font(.system(size: 28, weight: .thin))
                            .foregroundStyle(Color.kineticsBlue.opacity(0.40))
                        Text("Complete sessions to earn badges")
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.35))
                    }
                    .padding(.vertical, 28)
                    Spacer()
                }
                .background(Color.kineticsDark)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding(.horizontal, 16)
            } else {
                LazyVGrid(
                    columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ],
                    spacing: 10
                ) {
                    ForEach(allBadges) { badge in
                        ProfileBadgeChip(badge: badge) {
                            selectedBadge = badge
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    // MARK: - Athlete Section

    private var athleteSection: some View {
        SettingsGroup(header: "ATHLETE PROFILE") {
            // Face ID row
            Button { showFaceSetup = true } label: {
                HStack(spacing: 12) {
                    settingsIconBox(systemName: "person.crop.circle.fill.badge.checkmark", color: Color.kineticsBlue)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Face Profile")
                            .font(.system(size: 15))
                            .foregroundStyle(.white)
                        Text(hasFaceProfile ? "Scan saved — tap to update" : "Set up for auto-tagging in videos")
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.38))
                    }
                    Spacer()
                    if hasFaceProfile {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(Color.kineticsGreen)
                    } else {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.2))
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }

            SettingsDivider()

            // Height
            HStack(spacing: 12) {
                settingsIconBox(systemName: "ruler.fill", color: Color.kineticsGreen)
                Text("Height (cm)")
                    .font(.system(size: 15))
                    .foregroundStyle(.white)
                Spacer()
                TextField("0", text: $heightCmText)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.kineticsBlue)
                    .multilineTextAlignment(.trailing)
                    .keyboardType(.decimalPad)
                    .frame(width: 64)
                    .onChange(of: heightCmText) { _, _ in saveBodyComposition() }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            SettingsDivider()

            // Age
            HStack(spacing: 12) {
                settingsIconBox(systemName: "calendar", color: Color.kineticsAmber)
                Text("Age")
                    .font(.system(size: 15))
                    .foregroundStyle(.white)
                Spacer()
                TextField("0", text: $ageText)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.kineticsBlue)
                    .multilineTextAlignment(.trailing)
                    .keyboardType(.numberPad)
                    .frame(width: 64)
                    .onChange(of: ageText) { _, _ in saveBodyComposition() }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            SettingsDivider()

            // Weight
            HStack(spacing: 12) {
                settingsIconBox(systemName: "scalemass.fill", color: Color.kineticsPurple)
                Text("Weight (kg)")
                    .font(.system(size: 15))
                    .foregroundStyle(.white)
                Spacer()
                TextField("0", text: $weightKgText)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.kineticsBlue)
                    .multilineTextAlignment(.trailing)
                    .keyboardType(.decimalPad)
                    .frame(width: 64)
                    .onChange(of: weightKgText) { _, _ in saveBodyComposition() }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            SettingsDivider()

            // Skeletal Muscle Mass
            HStack(spacing: 12) {
                settingsIconBox(systemName: "figure.strengthtraining.traditional", color: Color.kineticsRed)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Skeletal Muscle (kg)")
                        .font(.system(size: 15))
                        .foregroundStyle(.white)
                    Text("From InBody or DEXA scan")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.35))
                }
                Spacer()
                TextField("0", text: $skeletalMuscleText)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.kineticsBlue)
                    .multilineTextAlignment(.trailing)
                    .keyboardType(.decimalPad)
                    .frame(width: 64)
                    .onChange(of: skeletalMuscleText) { _, _ in saveBodyComposition() }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
    }

    // MARK: - Body Composition Persistence

    private func loadBodyComposition(userId: String) {
        let descriptor = FetchDescriptor<BodyMeasurement>(
            predicate: #Predicate { $0.userId == userId },
            sortBy: [SortDescriptor(\.recordedAt, order: .reverse)]
        )
        guard let latest = (try? modelContext.fetch(descriptor))?.first else { return }
        if latest.heightCm > 0 { heightCmText = String(format: "%.1f", latest.heightCm) }
        if latest.ageYears > 0 { ageText = "\(latest.ageYears)" }
        if latest.weightKg > 0 { weightKgText = String(format: "%.1f", latest.weightKg) }
        if latest.skeletalMuscleMassKg > 0 { skeletalMuscleText = String(format: "%.1f", latest.skeletalMuscleMassKg) }
    }

    private func saveBodyComposition() {
        guard let userId = appState.authManager.currentUser?.uid else { return }
        let descriptor = FetchDescriptor<BodyMeasurement>(
            predicate: #Predicate { $0.userId == userId },
            sortBy: [SortDescriptor(\.recordedAt, order: .reverse)]
        )
        let entry: BodyMeasurement
        if let existing = (try? modelContext.fetch(descriptor))?.first {
            entry = existing
        } else {
            entry = BodyMeasurement(userId: userId)
            modelContext.insert(entry)
        }
        entry.heightCm = Double(heightCmText) ?? entry.heightCm
        entry.ageYears = Int(ageText) ?? entry.ageYears
        entry.weightKg = Double(weightKgText) ?? entry.weightKg
        entry.skeletalMuscleMassKg = Double(skeletalMuscleText) ?? entry.skeletalMuscleMassKg
        try? modelContext.save()
    }

    private func faceProfileExists(userId: String) -> Bool {
        let descriptor = FetchDescriptor<FaceProfile>(
            predicate: #Predicate { $0.userId == userId }
        )
        return ((try? modelContext.fetch(descriptor))?.isEmpty == false)
    }

    // MARK: - Avatar

    private var avatarSection: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.kineticsBlue, Color.kineticsPurple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 76, height: 76)
                Text(initials)
                    .font(.system(size: 30, weight: .black))
                    .foregroundStyle(.black)
            }
            .padding(.top, 16)

            Text(displayName)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.white)

            if isAnonymous {
                Button { showSignIn = true } label: {
                    Label("Sign in to save progress", systemImage: "person.badge.key.fill")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.kineticsBlue)
                }
            } else {
                Text(appState.authManager.currentUser?.email ?? "")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.38))
            }
        }
    }

    // MARK: - Stats Grid

    private var statsGrid: some View {
        Group {
            if vm.totalCount == 0 && !vm.isLoading {
                VStack(spacing: 16) {
                    Image(systemName: "figure.run.circle")
                        .font(.system(size: 40))
                        .foregroundStyle(Color(red: 0, green: 0.76, blue: 1.0))
                    VStack(spacing: 6) {
                        Text("Your journey starts here")
                            .font(.system(.headline, design: .rounded, weight: .bold))
                            .foregroundStyle(.white)
                        Text("Complete your first session to start tracking your progress.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(24)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal, 16)
            } else {
                LazyVGrid(
                    columns: [GridItem(.flexible()), GridItem(.flexible())],
                    spacing: 12
                ) {
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
        }
    }

    // MARK: - Account Section

    private var accountSection: some View {
        SettingsGroup(header: "ACCOUNT") {
            if isAnonymous {
                SettingsNavRow(
                    icon: "person.badge.plus",
                    iconColor: Color.kineticsBlue,
                    label: "Create Account",
                    detail: "Save progress across devices"
                ) {
                    showSignIn = true
                }
            } else {
                HStack(spacing: 12) {
                    settingsIconBox(systemName: "envelope.fill", color: Color.kineticsBlue)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Email")
                            .font(.system(size: 15))
                            .foregroundStyle(.white)
                        Text(appState.authManager.currentUser?.email ?? "—")
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.38))
                    }
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)

                SettingsDivider()

                Button { confirmSignOut = true } label: {
                    HStack(spacing: 12) {
                        settingsIconBox(systemName: "rectangle.portrait.and.arrow.right", color: Color.kineticsRed)
                        Text("Sign Out")
                            .font(.system(size: 15))
                            .foregroundStyle(Color.kineticsRed)
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                }

                SettingsDivider()

                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    HStack(spacing: 12) {
                        settingsIconBox(systemName: "trash.fill", color: Color.kineticsRed)
                        Text("Delete Account")
                            .font(.system(size: 15))
                            .foregroundStyle(Color.kineticsRed)
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                }
            }
        }
    }

    // MARK: - Delete Account

    private func deleteAccount() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let db = Firestore.firestore()
        try? await db.collection("users").document(uid).delete()
        try? appState.authManager.signOut()
        try? await Auth.auth().currentUser?.delete()
    }

    // MARK: - Preferences Section

    private var preferencesSection: some View {
        SettingsGroup(header: "PREFERENCES") {
            // Coach Voice toggle
            HStack(spacing: 12) {
                settingsIconBox(systemName: "waveform", color: Color.kineticsPurple)
                Toggle(isOn: $coachVoiceEnabled) {
                    Text("Coach Voice")
                        .font(.system(size: 15))
                        .foregroundStyle(.white)
                }
                .tint(Color.kineticsBlue)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            SettingsDivider()

            // Units picker
            HStack(spacing: 12) {
                settingsIconBox(systemName: "ruler", color: Color.kineticsGreen)
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

            SettingsDivider()

            // Notifications
            NavigationLink {
                NotificationSettingsView()
            } label: {
                HStack(spacing: 12) {
                    settingsIconBox(systemName: "bell.badge.fill", color: Color.kineticsAmber)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Notifications")
                            .font(.system(size: 15))
                            .foregroundStyle(.white)
                        Text("Reminders & achievement alerts")
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.38))
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.2))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }

            SettingsDivider()

            // Camera permissions deep-link
            SettingsNavRow(
                icon: "camera.fill",
                iconColor: Color.kineticsBlue,
                label: "Camera Permissions",
                detail: "Manage in Settings"
            ) {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }

            SettingsDivider()

            // Auto-share sessions toggle
            HStack(spacing: 12) {
                settingsIconBox(systemName: "square.and.arrow.up", color: Color.kineticsGreen)
                Toggle(isOn: $autoPublishSessions) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Auto-share sessions")
                            .font(.system(size: 15))
                            .foregroundStyle(.white)
                        Text("Automatically post completed sessions to your feed")
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.38))
                    }
                }
                .tint(Color(red: 0, green: 0.76, blue: 1.0))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            SettingsDivider()

            // Strava connection row
            HStack(spacing: 12) {
                settingsIconBox(systemName: "figure.run", color: Color(red: 0.98, green: 0.38, blue: 0.16))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Strava")
                        .font(.system(size: 15))
                        .foregroundStyle(.white)
                    Text(stravaAuth.isAuthenticated ? "Connected" : "Not connected")
                        .font(.system(size: 12))
                        .foregroundStyle(stravaAuth.isAuthenticated ? Color.kineticsGreen : .secondary)
                }
                Spacer()
                if stravaAuth.isAuthenticated {
                    Button("Disconnect") {
                        stravaAuth.disconnect()
                    }
                    .font(.system(size: 13))
                    .foregroundStyle(.red)
                } else {
                    Button("Connect") {
                        Task { try? await stravaAuth.authenticate() }
                    }
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .foregroundStyle(Color(red: 0.98, green: 0.38, blue: 0.16))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
    }

    // MARK: - Subscription Section

    private var subscriptionSection: some View {
        SettingsGroup(header: "SUBSCRIPTION") {
            NavigationLink {
                SubscriptionView()
            } label: {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.kineticsAmber.opacity(0.18))
                            .frame(width: 34, height: 34)
                        Image(systemName: "crown.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color.kineticsAmber)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text("Go Premium")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.white)
                            Text("PRO")
                                .font(.system(size: 9, weight: .bold))
                                .tracking(1)
                                .foregroundStyle(Color.kineticsDark)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.kineticsAmber)
                                .clipShape(Capsule())
                        }
                        Text("Unlock advanced analytics & remove limits")
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.45))
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.2))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 14)
            }
        }
    }

    // MARK: - About Section

    private var aboutSection: some View {
        SettingsGroup(header: "ABOUT") {
            HStack(spacing: 12) {
                settingsIconBox(systemName: "info.circle.fill", color: Color.kineticsSubtext)
                Text("Version")
                    .font(.system(size: 15))
                    .foregroundStyle(.white)
                Spacer()
                Text("\(appVersion) (\(buildNumber))")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.38))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            #if DEBUG
            SettingsDivider()

            // Debug: seed demo feed data
            Button {
                Task { await FeedSeeder.shared.seed() }
            } label: {
                Text("Seed Demo Data")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.3))
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            SettingsDivider()

            // Debug: reset onboarding walkthrough
            Button {
                onboardingComplete = false
            } label: {
                Text("Reset Onboarding")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.3))
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            #endif
        }
    }

    // MARK: - Icon Box Helper

    private func settingsIconBox(systemName: String, color: Color) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(color.opacity(0.18))
                .frame(width: 34, height: 34)
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(color)
        }
    }
}

// MARK: - SettingsGroup

/// A labelled grouped section matching iOS Settings dark aesthetic.
struct SettingsGroup<Content: View>: View {
    let header: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(header)
                .font(.system(size: 10, weight: .semibold))
                .tracking(2.5)
                .foregroundStyle(.white.opacity(0.38))
                .padding(.horizontal, 22)
                .padding(.bottom, 8)

            VStack(spacing: 0) {
                content()
            }
            .background(Color.kineticsDark)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(.horizontal, 16)
        }
    }
}

// MARK: - SettingsDivider

struct SettingsDivider: View {
    var body: some View {
        Divider()
            .background(.white.opacity(0.06))
            .padding(.horizontal, 14)
    }
}

// MARK: - SettingsNavRow

/// A tappable settings row with icon, label, optional detail subtitle, and chevron.
struct SettingsNavRow: View {
    let icon: String
    let iconColor: Color
    let label: String
    var detail: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(iconColor.opacity(0.18))
                        .frame(width: 34, height: 34)
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(iconColor)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(.system(size: 15))
                        .foregroundStyle(.white)
                    if let detail {
                        Text(detail)
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.38))
                    }
                }
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

// MARK: - SettingsRow (legacy — kept for backward compatibility)

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

// MARK: - ProfileBadgeChip

/// Compact 3-column badge chip used in the Profile badges grid.
/// Earned badges show full color; locked ones are dimmed with a lock overlay.
private struct ProfileBadgeChip: View {

    let badge: KineticsAchievementBadge
    let onTap: () -> Void

    private var accent: Color { Color(hex: badge.accentHex) }

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 6) {
                ZStack(alignment: .bottomTrailing) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(
                                badge.isUnlocked
                                    ? accent.opacity(0.18)
                                    : Color.white.opacity(0.05)
                            )
                            .frame(width: 44, height: 44)
                        Image(systemName: badge.icon)
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(
                                badge.isUnlocked
                                    ? accent
                                    : Color.white.opacity(0.22)
                            )
                            .opacity(badge.isUnlocked ? 1.0 : 0.4)
                    }
                    if !badge.isUnlocked {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white.opacity(0.50))
                            .padding(3)
                            .background(Color.kineticsMidGray)
                            .clipShape(Circle())
                            .offset(x: 4, y: 4)
                    }
                }

                Text(badge.title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(
                        badge.isUnlocked ? .white : Color.white.opacity(0.28)
                    )
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .padding(.horizontal, 6)
            .background(Color.kineticsDark)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(
                        badge.isUnlocked
                            ? accent.opacity(0.28)
                            : Color.white.opacity(0.06),
                        lineWidth: 0.75
                    )
            )
        }
        .buttonStyle(ScaleButtonStyle())
    }
}

// MARK: - BadgeDetailSheet

/// Mini sheet explaining a badge — how it was earned or how to unlock it.
struct BadgeDetailSheet: View {

    let badge: KineticsAchievementBadge
    @Environment(\.dismiss) private var dismiss

    private var accent: Color { Color(hex: badge.accentHex) }

    var body: some View {
        VStack(spacing: 0) {
            // Drag indicator area
            Capsule()
                .fill(.white.opacity(0.18))
                .frame(width: 36, height: 4)
                .padding(.top, 12)
                .padding(.bottom, 24)

            // Badge icon
            ZStack {
                Circle()
                    .fill(
                        badge.isUnlocked
                            ? accent.opacity(0.14)
                            : Color.white.opacity(0.05)
                    )
                    .frame(width: 88, height: 88)
                Image(systemName: badge.icon)
                    .font(.system(size: 38, weight: .semibold))
                    .foregroundStyle(
                        badge.isUnlocked ? accent : Color.white.opacity(0.25)
                    )
                    .opacity(badge.isUnlocked ? 1.0 : 0.5)
                if !badge.isUnlocked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white.opacity(0.55))
                        .frame(width: 88, height: 88, alignment: .bottomTrailing)
                        .offset(x: 4, y: 4)
                }
            }
            .padding(.bottom, 16)

            // Title + status
            Text(badge.title)
                .font(.system(size: 22, weight: .black))
                .foregroundStyle(.white)
                .padding(.bottom, 4)

            Text(badge.isUnlocked ? "EARNED" : "LOCKED")
                .font(.system(size: 10, weight: .bold))
                .tracking(2)
                .foregroundStyle(
                    badge.isUnlocked ? Color.kineticsGreen : Color.white.opacity(0.35)
                )
                .padding(.bottom, 20)

            // Description
            Text(badge.description)
                .font(.system(size: 15))
                .foregroundStyle(.white.opacity(0.65))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 32)
                .padding(.bottom, 28)

            // How to unlock (locked only)
            if !badge.isUnlocked {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(Color.kineticsBlue)
                    Text("Keep training to unlock this badge")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.55))
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(Color.kineticsBlue.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(.horizontal, 24)
                .padding(.bottom, 28)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .background(Color.kineticsBackground)
        .presentationDetents([.height(380)])
        .presentationBackground(Color.kineticsBackground)
        .presentationCornerRadius(24)
    }
}
