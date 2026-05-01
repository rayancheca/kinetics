import SwiftUI

// MARK: - GymSubTab

enum GymSubTab: Int, CaseIterable {
    case log        = 0
    case history    = 1
    case stats      = 2

    var icon: String {
        switch self {
        case .log:     return "dumbbell.fill"
        case .history: return "calendar"
        case .stats:   return "chart.bar.fill"
        }
    }

    var label: String {
        switch self {
        case .log:     return "Log"
        case .history: return "History"
        case .stats:   return "Stats"
        }
    }
}

// MARK: - GymRootView

/// Root container for the Gym tab.
/// Hosts an internal 3-tab nav (Log / History / Stats) rendered as a
/// dark floating pill at the bottom — completely separate from the
/// main app tab bar.
@MainActor
struct GymRootView: View {

    @Environment(AppState.self) private var appState

    @State private var selectedSubTab: GymSubTab = .log

    private var uid: String {
        appState.authManager.currentUser?.uid ?? "preview-user"
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.ignoresSafeArea()

            // MARK: Page content
            tabContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                // Reserve space so content is never hidden behind the pill
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    Color.clear.frame(height: 72)
                }

            // MARK: Floating pill tab bar
            gymTabPill
                .padding(.bottom, 8)
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
    }

    // MARK: - Tab Content

    @ViewBuilder
    private var tabContent: some View {
        switch selectedSubTab {
        case .log:
            GymHomeView()
        case .history:
            GymWorkoutHistoryView(userId: uid)
        case .stats:
            GymProgressView(userId: uid)
        }
    }

    // MARK: - Floating Pill

    private var gymTabPill: some View {
        HStack(spacing: 0) {
            ForEach(GymSubTab.allCases, id: \.rawValue) { tab in
                gymPillButton(for: tab)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(Color(white: 0.1))
                .overlay(
                    Capsule()
                        .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.55), radius: 20, x: 0, y: 8)
        )
        .padding(.horizontal, 48)
        .animation(.spring(response: 0.3, dampingFraction: 0.72), value: selectedSubTab)
    }

    private func gymPillButton(for tab: GymSubTab) -> some View {
        let isSelected = selectedSubTab == tab

        return Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.72)) {
                selectedSubTab = tab
            }
        } label: {
            HStack(spacing: isSelected ? 6 : 0) {
                Image(systemName: tab.icon)
                    .font(.system(size: 16, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? .black : Color.white.opacity(0.45))

                if isSelected {
                    Text(tab.label)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.black)
                        .transition(.opacity.combined(with: .scale(scale: 0.85)))
                }
            }
            .padding(.horizontal, isSelected ? 16 : 14)
            .padding(.vertical, 10)
            .background(
                Capsule()
                    .fill(isSelected ? Color.kineticsBlue : Color.clear)
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
