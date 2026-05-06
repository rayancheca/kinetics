import SwiftUI

// MARK: - WatchContentView

struct WatchContentView: View {
    @EnvironmentObject private var session: WatchSessionManager

    var body: some View {
        if session.isSessionActive || session.activeModule != nil {
            WatchActiveSessionView()
        } else {
            WatchQuickStartView()
        }
    }
}

// MARK: - WatchQuickStartView

struct WatchQuickStartView: View {
    @EnvironmentObject private var session: WatchSessionManager

    private let modules: [(name: String, icon: String, color: Color)] = [
        ("Striking", "figure.boxing", .blue),
        ("Grappling", "figure.wrestling", .orange),
        ("Iron", "dumbbell.fill", .green),
        ("Climbing", "mountain.2.fill", .purple),
        ("Track", "figure.run", Color(red: 0, green: 0.76, blue: 1.0))
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text("KINETICS")
                    .font(.system(.headline, design: .rounded, weight: .black))
                    .foregroundStyle(Color(red: 0, green: 0.76, blue: 1.0))
                    .padding(.horizontal, 4)

                ForEach(modules, id: \.name) { module in
                    Button {
                        session.startSession(module: module.name)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: module.icon)
                                .font(.title3)
                                .foregroundStyle(module.color)
                                .frame(width: 28)

                            Text(module.name)
                                .font(.system(.body, design: .rounded, weight: .semibold))

                            Spacer()

                            Image(systemName: "play.fill")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
        }
    }
}
