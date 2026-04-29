import SwiftUI

// MARK: - PermissionsGateView

/// Full-screen permissions gate shown exactly once on first launch.
///
/// Presents three permission rows (Health, Notifications, Location) with
/// clear rationale for each, then requests all three in sequence when the
/// user taps "Continue". Sets `@AppStorage("permissions_requested")` to
/// `true` on completion so the gate is never shown again.
///
/// Threading: `@MainActor` throughout — all service calls bridge back to
/// main via their own isolation (`NotificationService` is `@MainActor`;
/// `HealthKitService` and `LocationService` are actors whose `await` calls
/// resume cleanly on `@MainActor`).
@MainActor
struct PermissionsGateView: View {

    // MARK: - Persistence Flag

    @AppStorage("permissions_requested") private var permissionsRequested = false

    // MARK: - Local State

    @State private var isRequesting = false

    // MARK: - Body

    var body: some View {
        ZStack {
            Color.kineticsBackground
                .ignoresSafeArea()

            VStack(spacing: 0) {

                // ── Header ────────────────────────────────────────────────
                VStack(spacing: 12) {
                    Image(systemName: "figure.run.circle.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(Color.kineticsBlue)
                        .padding(.top, 60)

                    Text("Before We Begin")
                        .font(.system(.largeTitle, design: .rounded, weight: .bold))
                        .foregroundStyle(.white)

                    Text("Kinetics needs a few permissions to deliver\naccurate coaching and progress tracking.")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(Color.kineticsSubtext)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
                .padding(.bottom, 48)

                // ── Permission Rows ───────────────────────────────────────
                VStack(spacing: 0) {
                    PermissionRow(
                        systemImage: "heart.fill",
                        tint: Color.kineticsGreen,
                        title: "Health",
                        subtitle: "Read heart rate, sleep, and activity data to personalise your recovery and performance insights."
                    )

                    Divider()
                        .background(Color.kineticsMidGray)
                        .padding(.leading, 68)

                    PermissionRow(
                        systemImage: "bell.fill",
                        tint: Color.kineticsAmber,
                        title: "Notifications",
                        subtitle: "Receive workout reminders and achievement alerts so you never miss a training session."
                    )

                    Divider()
                        .background(Color.kineticsMidGray)
                        .padding(.leading, 68)

                    PermissionRow(
                        systemImage: "location.fill",
                        tint: Color.kineticsBlue,
                        title: "Location",
                        subtitle: "Track outdoor runs, rides, and hikes with GPS route mapping and elevation data."
                    )
                }
                .background(Color.kineticsDark)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .padding(.horizontal, 20)

                Spacer()

                // ── Continue Button ───────────────────────────────────────
                Button {
                    Task { await requestAllPermissions() }
                } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.kineticsBlue)
                            .frame(height: 54)

                        if isRequesting {
                            ProgressView()
                                .tint(.black)
                        } else {
                            Text("Continue")
                                .font(.system(.body, design: .rounded, weight: .semibold))
                                .foregroundStyle(.black)
                        }
                    }
                }
                .disabled(isRequesting)
                .padding(.horizontal, 20)
                .padding(.bottom, 48)
            }
        }
    }

    // MARK: - Actions

    /// Requests Health → Notifications → Location in sequence.
    /// Sets `permissionsRequested` to `true` regardless of individual
    /// grant/deny outcomes — we never block the app on denied permissions.
    private func requestAllPermissions() async {
        isRequesting = true

        // 1. HealthKit — actor-isolated; throws on simulator (no HealthKit).
        try? await HealthKitService.shared.requestAuthorization()

        // 2. Notifications — @MainActor, returns Bool (we don't block on denial).
        _ = await NotificationService.shared.requestAuthorization()

        // 3. Location — actor-isolated, returns Bool.
        let locationService = LocationService()
        _ = await locationService.requestAuthorization()

        permissionsRequested = true
        isRequesting = false
    }
}

// MARK: - PermissionRow

/// A single permission explanation row used inside `PermissionsGateView`.
private struct PermissionRow: View {

    let systemImage: String
    let tint: Color
    let title: String
    let subtitle: String

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(tint.opacity(0.15))
                    .frame(width: 44, height: 44)

                Image(systemName: systemImage)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(tint)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(.body, design: .rounded, weight: .semibold))
                    .foregroundStyle(.white)

                Text(subtitle)
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(Color.kineticsSubtext)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
    }
}

// MARK: - Preview

#Preview {
    PermissionsGateView()
}
