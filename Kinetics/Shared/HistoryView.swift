import SwiftUI

// MARK: - HistoryViewModel

@Observable @MainActor
final class HistoryViewModel {
    var sessions: [SessionResult] = []
    var selectedFilter: SportType? = nil
    var isLoading = false

    var filtered: [SessionResult] {
        guard let filter = selectedFilter else { return sessions }
        return sessions.filter { $0.sport == filter }
    }

    var grouped: [(String, [SessionResult])] {
        let cal = Calendar.current
        let dict = Dictionary(grouping: filtered) { session -> String in
            if cal.isDateInToday(session.startedAt)     { return "TODAY" }
            if cal.isDateInYesterday(session.startedAt) { return "YESTERDAY" }
            return session.startedAt.formatted(.dateTime.weekday(.wide).month().day())
        }
        return dict.sorted { a, b in
            (a.value.first?.startedAt ?? .distantPast) > (b.value.first?.startedAt ?? .distantPast)
        }
    }

    func load(for userId: String) async {
        isLoading = true
        sessions = (try? await SessionRepository.shared.fetchSessions(for: userId, limit: 100)) ?? []
        isLoading = false
    }
}

// MARK: - HistoryView

struct HistoryView: View {
    @Environment(AppState.self) private var appState
    @State private var vm = HistoryViewModel()
    @State private var selectedSession: SessionResult? = nil

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    // Header
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("HISTORY")
                                .font(.system(size: 32, weight: .black))
                                .tracking(6)
                                .foregroundStyle(.white)
                            Text("\(vm.sessions.count) sessions recorded")
                                .font(.system(size: 13))
                                .foregroundStyle(.white.opacity(0.38))
                        }
                        Spacer()
                        if vm.isLoading {
                            ProgressView().tint(.white.opacity(0.3))
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 20)

                    // Filter pills
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            FilterPill(
                                label: "All",
                                accent: Color.kineticsBlue,
                                isSelected: vm.selectedFilter == nil
                            ) {
                                vm.selectedFilter = nil
                            }
                            ForEach(SportType.allCases, id: \.self) { sport in
                                FilterPill(
                                    label: sport.displayName,
                                    accent: Color.moduleColor(for: sport),
                                    isSelected: vm.selectedFilter == sport
                                ) {
                                    vm.selectedFilter = (vm.selectedFilter == sport) ? nil : sport
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                    .padding(.bottom, 20)

                    // Grouped list
                    if vm.filtered.isEmpty && !vm.isLoading {
                        VStack(spacing: 8) {
                            Image(systemName: "clock")
                                .font(.system(size: 40, weight: .thin))
                                .foregroundStyle(.white.opacity(0.2))
                            Text("No sessions yet")
                                .font(.system(.subheadline, weight: .medium))
                                .foregroundStyle(.white.opacity(0.35))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 60)
                    } else {
                        LazyVStack(spacing: 20, pinnedViews: .sectionHeaders) {
                            ForEach(vm.grouped, id: \.0) { header, sessions in
                                Section {
                                    VStack(spacing: 0) {
                                        ForEach(sessions) { session in
                                            Button { selectedSession = session } label: {
                                                HistorySessionRow(session: session)
                                                    .padding(.horizontal, 14)
                                                    .padding(.vertical, 8)
                                            }
                                            if session.id != sessions.last?.id {
                                                Divider()
                                                    .background(.white.opacity(0.06))
                                                    .padding(.horizontal, 14)
                                            }
                                        }
                                    }
                                    .background(Color.kineticsDark)
                                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .strokeBorder(.white.opacity(0.06), lineWidth: 0.5)
                                    )
                                    .padding(.horizontal, 16)
                                } header: {
                                    Text(header)
                                        .font(.system(size: 10, weight: .semibold))
                                        .tracking(2.5)
                                        .foregroundStyle(.white.opacity(0.38))
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.horizontal, 20)
                                        .padding(.vertical, 6)
                                        .background(Color.kineticsBackground)
                                }
                            }
                        }
                    }

                    Spacer(minLength: 40)
                }
            }
            .background(Color.kineticsBackground)
            .navigationBarHidden(true)
            .sheet(item: $selectedSession) { session in
                SessionDetailView(session: session)
                    .environment(appState)
            }
            .task {
                if let uid = appState.authManager.currentUser?.uid {
                    await vm.load(for: uid)
                }
            }
        }
    }
}

// MARK: - FilterPill

struct FilterPill: View {
    let label: String
    let accent: Color
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isSelected ? Color.kineticsDark : .white.opacity(0.55))
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(isSelected ? accent : Color(red: 0.12, green: 0.12, blue: 0.12))
                .clipShape(Capsule())
        }
    }
}

// MARK: - HistorySessionRow

struct HistorySessionRow: View {
    let session: SessionResult
    private var accent: Color { Color.moduleColor(for: session.sport) }

    private var topMetric: String {
        switch session.sport {
        case .striking:
            return session.metrics["peak_velocity_mph"].map { String(format: "%.0f mph", $0) } ?? ""
        case .grappling:
            return session.metrics["kuzushi_index"].map { "\(Int($0))/100 kuzushi" } ?? ""
        case .ironTracker:
            return session.metrics["vbt_velocity_ms"].map { String(format: "%.2f m/s", $0) } ?? ""
        case .wallBeta:
            return session.metrics["hip_proximity_score"].map { "\(Int($0 * 100))% proximity" } ?? ""
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(accent.opacity(0.14))
                    .frame(width: 44, height: 44)
                Image(systemName: session.sport.systemImage)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(accent)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(session.sport.displayName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                Text(session.formattedDate)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.4))
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                Text(session.formattedDuration)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white)
                if !topMetric.isEmpty {
                    Text(topMetric)
                        .font(.system(size: 11))
                        .foregroundStyle(accent)
                }
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.2))
        }
    }
}
