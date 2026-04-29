import SwiftUI

// MARK: - HomeView

/// The root screen of Kinetics. Presents the four sport module cards, the
/// KINETICS wordmark, auth state, and a recent sessions list.
///
/// Navigation is handled by a `NavigationStack` with a typed
/// `navigationDestination(for: SportType.self)` so each `ModuleCard` is a
/// plain `NavigationLink(value:)` with zero routing logic in the view.
struct HomeView: View {

    // MARK: - Dependencies

    @Environment(AppState.self) private var appState
    @State private var viewModel = HomeViewModel()
    @State private var showSignIn = false
    @State private var confirmSignOut = false

    // MARK: - Grid Layout

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    headerSection
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                        .padding(.bottom, 28)

                    moduleGrid
                        .padding(.horizontal, 16)

                    if appState.authManager.isSignedIn {
                        recentSessionsSection
                            .padding(.top, 32)
                            .padding(.horizontal, 16)
                    }

                    Spacer(minLength: 40)
                }
            }
            .background(Color.kineticsBackground)
            .navigationDestination(for: SportType.self) { sport in
                moduleView(for: sport)
            }
            .sheet(isPresented: $showSignIn) {
                SignInSheet()
                    .environment(appState)
            }
            .onChange(of: showSignIn) { _, isShowing in
                guard !isShowing, let uid = appState.authManager.currentUser?.uid else { return }
                Task { await viewModel.loadHistory(for: uid) }
            }
            .confirmationDialog("Account", isPresented: $confirmSignOut, titleVisibility: .visible) {
                Button("Sign Out", role: .destructive) {
                    Task {
                        try? appState.authManager.signOut()
                        if let uid = appState.authManager.currentUser?.uid {
                            await viewModel.refreshSessionHistory(for: uid)
                        } else {
                            viewModel.recentSessions = []
                        }
                    }
                }
                Button("Cancel", role: .cancel) {}
            }
            .task {
                await viewModel.signInAnonymouslyIfNeeded(authManager: appState.authManager)
                if let userId = appState.authManager.currentUser?.uid {
                    await viewModel.loadHistory(for: userId)
                }
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 5) {
                Text("KINETICS")
                    .font(.system(size: 34, weight: .black, design: .default))
                    .tracking(8)
                    .foregroundStyle(.white)

                Text("AI Biomechanics Coach")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.white.opacity(0.38))
                    .tracking(0.5)
            }

            Spacer(minLength: 12)

            authPill
                .padding(.top, 5)
        }
    }

    // MARK: - Auth Pill

    private var authPill: some View {
        Button {
            let user = appState.authManager.currentUser
            if appState.authManager.isSignedIn && user?.isAnonymous == false {
                confirmSignOut = true
            } else {
                showSignIn = true
            }
        } label: {
            if appState.authManager.isSignedIn {
                let isAnonymous = appState.authManager.currentUser?.isAnonymous == true
                HStack(spacing: 6) {
                    Circle()
                        .fill(isAnonymous ? Color.yellow : Color.kineticsGreen)
                        .frame(width: 6, height: 6)
                        .shadow(
                            color: (isAnonymous ? Color.yellow : Color.kineticsGreen).opacity(0.8),
                            radius: 4
                        )

                    Text(isAnonymous ? "Guest" : "Online")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.55))
                }
                .padding(.horizontal, 13)
                .padding(.vertical, 7)
                .background(Color.kineticsMidGray)
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .strokeBorder(.white.opacity(0.07), lineWidth: 0.5)
                )
            } else {
                Text("Sign In")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.kineticsBlue)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 7)
                    .background(Color.kineticsBlue.opacity(0.12))
                    .clipShape(Capsule())
                    .overlay(
                        Capsule()
                            .strokeBorder(Color.kineticsBlue.opacity(0.35), lineWidth: 0.5)
                    )
            }
        }
    }

    // MARK: - Module Grid

    private var moduleGrid: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(SportType.allCases, id: \.self) { sport in
                NavigationLink(value: sport) {
                    ModuleCard(sport: sport)
                }
                .buttonStyle(ScaleButtonStyle())
            }
        }
    }

    // MARK: - Recent Sessions

    private var recentSessionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("RECENT SESSIONS")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(2.5)
                    .foregroundStyle(.white.opacity(0.38))

                Spacer()

                if viewModel.isLoadingHistory {
                    ProgressView()
                        .tint(.white.opacity(0.3))
                        .scaleEffect(0.7)
                }
            }

            if viewModel.isLoadingHistory && viewModel.recentSessions.isEmpty {
                sessionHistorySkeleton
            } else if !viewModel.isLoadingHistory && viewModel.recentSessions.isEmpty {
                emptySessionsState
            } else {
                sessionHistoryList
            }
        }
    }

    private var sessionHistoryList: some View {
        VStack(spacing: 0) {
            ForEach(viewModel.recentSessions) { session in
                SessionHistoryRow(session: session)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)

                if session.id != viewModel.recentSessions.last?.id {
                    Rectangle()
                        .fill(.white.opacity(0.06))
                        .frame(height: 0.5)
                        .padding(.horizontal, 14)
                }
            }
        }
        .padding(.vertical, 6)
        .background(Color.kineticsDark)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.white.opacity(0.06), lineWidth: 0.5)
        )
    }

    /// Empty state shown when the user is signed in but has no recorded sessions.
    private var emptySessionsState: some View {
        VStack(spacing: 8) {
            Image(systemName: "figure.run.circle")
                .font(.system(size: 32, weight: .thin))
                .foregroundStyle(Color(red: 0, green: 0.76, blue: 1).opacity(0.5))
            Text("No sessions yet")
                .font(.system(.subheadline, weight: .medium))
                .foregroundStyle(.white.opacity(0.35))
            Text("Start a module above to record your first session.")
                .font(.system(.caption))
                .foregroundStyle(.white.opacity(0.25))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(Color(red: 0.075, green: 0.075, blue: 0.075))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    /// Placeholder shimmer rows shown while history is loading.
    private var sessionHistorySkeleton: some View {
        VStack(spacing: 0) {
            ForEach(0..<3, id: \.self) { _ in
                SkeletonRow()
            }
        }
        .padding(.vertical, 6)
        .background(Color.kineticsDark)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: - Module Navigation

    @ViewBuilder
    private func moduleView(for sport: SportType) -> some View {
        switch sport {
        case .striking:
            StrikingView()
        case .grappling:
            GrapplingView()
        case .ironTracker:
            IronTrackerView()
        case .wallBeta:
            WallBetaView()
        }
    }
}

// MARK: - ModuleCard

/// A tall card representing one sport module. Used inside the 2×2 home grid.
///
/// Visual layers (back to front):
/// 1. Dark card background (`kineticsDark`).
/// 2. Subtle radial glow behind the icon.
/// 3. Vertical gradient from clear → accent at bottom for depth.
/// 4. Hairline border at accent opacity.
/// 5. Content column (icon, name, tagline, start prompt).
struct ModuleCard: View {

    let sport: SportType

    private var accent: Color { Color.moduleColor(for: sport) }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // MARK: Base surface
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.kineticsDark)

            // MARK: Icon glow (radial, top-left anchored)
            RadialGradient(
                colors: [accent.opacity(0.12), .clear],
                center: .topLeading,
                startRadius: 0,
                endRadius: 100
            )
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

            // MARK: Bottom depth gradient
            LinearGradient(
                colors: [.clear, accent.opacity(0.20)],
                startPoint: .top,
                endPoint: .bottom
            )
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

            // MARK: Hairline border
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(accent.opacity(0.22), lineWidth: 0.75)

            // MARK: Content
            VStack(alignment: .leading, spacing: 0) {
                // Icon with a tight tinted backing square
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(accent.opacity(0.14))
                        .frame(width: 50, height: 50)

                    Image(systemName: sport.systemImage)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(accent)
                }

                Spacer()

                // Module name
                Text(sport.displayName)
                    .font(.system(size: 16, weight: .bold, design: .default))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                // Tagline
                Text(sport.tagline)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(.white.opacity(0.42))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)

                // Start prompt
                HStack(spacing: 4) {
                    Text("START")
                        .font(.system(size: 9, weight: .bold))
                        .tracking(1.8)
                        .foregroundStyle(accent)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(accent)
                }
                .padding(.top, 10)
            }
            .padding(16)
        }
        .frame(minHeight: 180)
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

// MARK: - ScaleButtonStyle

/// Spring-animated press effect for module cards.
struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(
                .spring(response: 0.28, dampingFraction: 0.65),
                value: configuration.isPressed
            )
    }
}

// MARK: - SkeletonRow

/// A muted placeholder row shown while session history is loading.
private struct SkeletonRow: View {
    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.white.opacity(0.07))
                .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(.white.opacity(0.07))
                    .frame(width: 100, height: 11)

                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(.white.opacity(0.05))
                    .frame(width: 72, height: 9)
            }

            Spacer()

            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(.white.opacity(0.07))
                .frame(width: 36, height: 11)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

// MARK: - SignInSheet

/// Modal sheet for email/password sign-in and account creation.
///
/// The sheet is presented from `HomeView` when the auth pill is tapped.
/// It uses the existing `AuthManager` methods on `AppState` — no extra
/// auth logic lives here.
struct SignInSheet: View {

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var email = ""
    @State private var password = ""
    @State private var isCreatingAccount = false

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    // MARK: Heading
                    VStack(alignment: .leading, spacing: 6) {
                        Text(isCreatingAccount ? "Create Account" : "Welcome Back")
                            .font(.system(size: 26, weight: .bold))
                            .foregroundStyle(.white)

                        Text(
                            isCreatingAccount
                                ? "Save your sessions and track progress over time."
                                : "Sign in to access your session history."
                        )
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.45))
                    }
                    .padding(.bottom, 28)

                    // MARK: Fields
                    VStack(spacing: 10) {
                        TextField("Email", text: $email)
                            .textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .textFieldStyle(KineticsTextFieldStyle())

                        SecureField("Password", text: $password)
                            .textContentType(isCreatingAccount ? .newPassword : .password)
                            .textFieldStyle(KineticsTextFieldStyle())
                    }
                    .padding(.bottom, 16)

                    // MARK: Error
                    if let error = appState.authManager.authError {
                        Text(error)
                            .font(.system(size: 13))
                            .foregroundStyle(Color.kineticsRed)
                            .padding(.bottom, 12)
                    }

                    // MARK: Primary Action
                    Button {
                        Task {
                            if isCreatingAccount {
                                try? await appState.authManager.createAccount(
                                    email: email,
                                    password: password
                                )
                            } else {
                                try? await appState.authManager.signInWithEmail(
                                    email,
                                    password: password
                                )
                            }
                            if appState.authManager.isSignedIn { dismiss() }
                        }
                    } label: {
                        Group {
                            if appState.authManager.isLoading {
                                ProgressView()
                                    .tint(Color.kineticsDark)
                            } else {
                                Text(isCreatingAccount ? "Create Account" : "Sign In")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(Color.kineticsDark)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(Color.kineticsBlue)
                        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                    }
                    .disabled(
                        email.trimmingCharacters(in: .whitespaces).isEmpty
                            || password.isEmpty
                            || appState.authManager.isLoading
                    )
                    .padding(.bottom, 12)

                    // MARK: Anonymous Continue
                    Button {
                        Task {
                            try? await appState.authManager.signInAnonymously()
                            dismiss()
                        }
                    } label: {
                        Text("Continue without account")
                            .font(.system(size: 14))
                            .foregroundStyle(.white.opacity(0.40))
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                    }
                    .padding(.bottom, 4)

                    // MARK: Toggle Mode
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isCreatingAccount.toggle()
                        }
                    } label: {
                        Text(
                            isCreatingAccount
                                ? "Already have an account? Sign In"
                                : "Don't have an account? Create one"
                        )
                        .font(.system(size: 13))
                        .foregroundStyle(Color.kineticsBlue)
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
            }
            .background(Color.kineticsBackground)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.kineticsBlue)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(Color.kineticsBackground)
        .presentationCornerRadius(20)
    }
}

// MARK: - KineticsTextFieldStyle

/// Dark-surface text field used in the sign-in sheet.
struct KineticsTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(Color.kineticsMidGray)
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(.white.opacity(0.08), lineWidth: 0.5)
            )
    }
}

// MARK: - Preview

#Preview {
    HomeView()
        .environment(AppState.preview)
}
