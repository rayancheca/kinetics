import SwiftUI

// MARK: - SessionHistoryRow

/// A single row in the session history list showing key metadata for a completed session.
///
/// Each row displays:
/// - A sport-branded icon tile (module accent color background).
/// - The module name and formatted start date.
/// - The session duration right-aligned in electric blue.
///
/// Designed to be embedded inside a `List` or `LazyVStack` backed by a Firestore
/// or SwiftData query, with `.listRowBackground(Color.kineticsDark)` applied
/// at the list level.
///
/// ```swift
/// List(sessions) { session in
///     SessionHistoryRow(session: session)
///         .listRowBackground(Color.kineticsDark)
/// }
/// ```
struct SessionHistoryRow: View {

    let session: SessionResult

    // MARK: Body

    var body: some View {
        HStack(spacing: 12) {
            moduleIconTile
            sessionInfo
            Spacer()
            durationStack
        }
        .padding(.vertical, 4)
    }

    // MARK: - Subviews

    /// Rounded square tile tinted with the sport module's accent color.
    private var moduleIconTile: some View {
        let accentColor = Color.moduleColor(for: session.sport)

        return ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(accentColor.opacity(0.15))
                .frame(width: 44, height: 44)

            Image(systemName: session.sport.systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(accentColor)
        }
    }

    /// Module name and formatted date, left-aligned.
    private var sessionInfo: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(session.sport.displayName)
                .font(.system(.callout, weight: .semibold))
                .foregroundStyle(Color.white)

            Text(session.formattedDate)
                .font(.system(.caption))
                .foregroundStyle(Color.white.opacity(0.50))
        }
    }

    /// Formatted duration and a "DURATION" label, right-aligned.
    private var durationStack: some View {
        VStack(alignment: .trailing, spacing: 3) {
            Text(session.formattedDuration)
                .font(.system(.callout, design: .rounded, weight: .semibold))
                .foregroundStyle(Color.kineticsBlue)
                .monospacedDigit()

            Text("DURATION")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.40))
                .tracking(1.0)
        }
    }
}
