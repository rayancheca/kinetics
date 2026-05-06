import AVFoundation
import SwiftUI

// MARK: - PermissionsGateView

/// Full-screen permissions gate shown exactly once on first launch.
///
/// Each permission is shown as a premium card with icon, title, description,
/// and a benefit callout. After the user taps "Get Started", all three
/// permissions are requested in sequence. Sets `@AppStorage("permissions_requested")`
/// to `true` on completion so the gate is never shown again.
///
/// Threading: `@MainActor` throughout — all service calls bridge back to
/// main via their own isolation.
@MainActor
struct PermissionsGateView: View {

    // MARK: - Persistence Flag

    @AppStorage("permissions_requested") private var permissionsRequested = false

    // MARK: - Local State

    @State private var isRequesting = false
    @State private var currentPage = 0
    @State private var animateIn = false

    private let pages: [PermissionPage] = [
        PermissionPage(
            systemImage: "figure.run.circle.fill",
            tint: Color(red: 0, green: 0.76, blue: 1),
            title: "Welcome to Kinetics",
            headline: "AI Sports Coaching",
            description: "Kinetics uses your camera and device sensors to analyse your movement in real-time and deliver precision coaching.",
            benefit: "Let's set up a few permissions to get started."
        ),
        PermissionPage(
            systemImage: "camera.fill",
            tint: Color(red: 0, green: 0.76, blue: 1),
            title: "Camera",
            headline: "Required for live analysis",
            description: "Kinetics tracks 19 body joints through your camera to measure strike velocity, posture, and biomechanics.",
            benefit: "Without camera access, live coaching is not possible."
        ),
        PermissionPage(
            systemImage: "bell.badge.fill",
            tint: Color(red: 1, green: 0.722, blue: 0),
            title: "Notifications",
            headline: "Streak alerts & reminders",
            description: "Stay consistent with scheduled workout reminders and get notified when you hit a new personal record.",
            benefit: "You can customise or disable these any time in Settings."
        ),
        PermissionPage(
            systemImage: "heart.fill",
            tint: Color(red: 0.224, green: 0.906, blue: 0.439),
            title: "Health",
            headline: "Recovery & performance insights",
            description: "Kinetics reads heart rate and activity data from Apple Health to personalise your recovery recommendations.",
            benefit: "Requires a paid Apple Developer account — gracefully skipped if unavailable."
        ),
    ]

    // MARK: - Body

    var body: some View {
        ZStack {
            // Deep black background
            Color.black.ignoresSafeArea()

            // Ambient glow behind the icon
            pages[currentPage].tint
                .opacity(0.08)
                .blur(radius: 80)
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 0.6), value: currentPage)

            VStack(spacing: 0) {
                Spacer()

                // Card
                permissionCard
                    .padding(.horizontal, 24)
                    .opacity(animateIn ? 1 : 0)
                    .offset(y: animateIn ? 0 : 24)
                    .animation(.spring(duration: 0.55, bounce: 0.2), value: animateIn)
                    .animation(.spring(duration: 0.55, bounce: 0.2), value: currentPage)

                Spacer()

                // Progress dots + CTA
                VStack(spacing: 20) {
                    progressDots

                    ctaButton
                        .padding(.horizontal, 24)
                }
                .padding(.bottom, 52)
            }
        }
        .onAppear {
            withAnimation {
                animateIn = true
            }
        }
    }

    // MARK: - Permission Card

    private var permissionCard: some View {
        let page = pages[currentPage]
        return VStack(spacing: 0) {
            // Icon
            ZStack {
                Circle()
                    .fill(page.tint.opacity(0.14))
                    .frame(width: 100, height: 100)

                Circle()
                    .fill(page.tint.opacity(0.06))
                    .frame(width: 140, height: 140)

                Image(systemName: page.systemImage)
                    .font(.system(size: 48, weight: .semibold))
                    .foregroundStyle(page.tint)
            }
            .padding(.top, 44)
            .padding(.bottom, 28)

            // Title pill
            Text(page.title.uppercased())
                .font(.system(size: 11, weight: .bold))
                .tracking(3)
                .foregroundStyle(page.tint)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(page.tint.opacity(0.14))
                .clipShape(Capsule())
                .padding(.bottom, 14)

            // Headline
            Text(page.headline)
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
                .padding(.bottom, 14)

            // Description
            Text(page.description)
                .font(.system(size: 15, design: .rounded))
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .padding(.horizontal, 20)
                .padding(.bottom, 20)

            // Benefit callout
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(page.tint)
                Text(page.benefit)
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.45))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 32)
        }
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(red: 0.075, green: 0.075, blue: 0.075))
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(page.tint.opacity(0.18), lineWidth: 1)
                )
        )
        .id(currentPage) // Force re-render on page change for transition
        .transition(.asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal: .move(edge: .leading).combined(with: .opacity)
        ))
    }

    // MARK: - Progress Dots

    private var progressDots: some View {
        HStack(spacing: 7) {
            ForEach(0..<pages.count, id: \.self) { index in
                Capsule()
                    .fill(index == currentPage ? pages[currentPage].tint : .white.opacity(0.2))
                    .frame(width: index == currentPage ? 22 : 7, height: 7)
                    .animation(.spring(duration: 0.4, bounce: 0.3), value: currentPage)
            }
        }
    }

    // MARK: - CTA Button

    private var ctaButton: some View {
        let isLastPage = currentPage == pages.count - 1

        return Button {
            if isLastPage {
                Task { await requestAllPermissions() }
            } else {
                withAnimation(.spring(duration: 0.45, bounce: 0.1)) {
                    currentPage += 1
                }
            }
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0, green: 0.76, blue: 1),
                                Color(red: 0, green: 0.55, blue: 0.88),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(height: 56)

                if isRequesting {
                    ProgressView()
                        .tint(.black)
                        .scaleEffect(1.1)
                } else {
                    Text(isLastPage ? "Get Started" : "Continue")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(.black)
                }
            }
        }
        .disabled(isRequesting)
    }

    // MARK: - Actions

    /// Requests Camera → Notifications → HealthKit → Location in sequence.
    /// Sets `permissionsRequested` to `true` regardless of individual
    /// grant/deny outcomes — we never block the app on denied permissions.
    private func requestAllPermissions() async {
        isRequesting = true

        // 1. Camera — must be requested before the live analysis views appear.
        await AVCaptureDevice.requestAccess(for: .video)

        // 2. HealthKit — throws on simulator (no HealthKit); handled gracefully.
        try? await HealthKitService.shared.requestAuthorization()

        // 3. Notifications — @MainActor, returns Bool (we don't block on denial).
        _ = await NotificationService.shared.requestAuthorization()

        // 4. Location — actor-isolated, returns Bool.
        let locationService = LocationService()
        _ = await locationService.requestAuthorization()

        permissionsRequested = true
        isRequesting = false
    }
}

// MARK: - PermissionPage Model

private struct PermissionPage {
    let systemImage: String
    let tint: Color
    let title: String
    let headline: String
    let description: String
    let benefit: String
}

// MARK: - Preview

#Preview {
    PermissionsGateView()
}
