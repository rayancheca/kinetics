import SwiftUI

// MARK: - HomeNotification

struct HomeNotification: Identifiable {
    let id: UUID
    let title: String
    let body: String
    let icon: String
    let iconColor: Color
    let timestamp: String
    let type: NotifType

    enum NotifType { case achievement, reminder, coach, social }
}

// MARK: - HomeNotificationsView

struct HomeNotificationsView: View {

    @Environment(\.dismiss) private var dismiss

    // MARK: Sample Data

    private let notifications: [HomeNotification] = [
        HomeNotification(
            id: UUID(),
            title: "7-day streak unlocked!",
            body: "You've maintained 7 consecutive days of training. Badge added to your profile.",
            icon: "bolt.fill",
            iconColor: .kineticsAmber,
            timestamp: "Just now",
            type: .achievement
        ),
        HomeNotification(
            id: UUID(),
            title: "Strike velocity tip",
            body: "Focus on hip engagement before shoulder rotation for maximum power transfer.",
            icon: "brain.head.profile",
            iconColor: .kineticsPurple,
            timestamp: "1h ago",
            type: .coach
        ),
        HomeNotification(
            id: UUID(),
            title: "Time to train",
            body: "You haven't trained Grappling Lab in 3 days. Don't lose your momentum.",
            icon: "figure.run",
            iconColor: .kineticsBlue,
            timestamp: "2h ago",
            type: .reminder
        ),
        HomeNotification(
            id: UUID(),
            title: "3 kudos on your last session",
            body: "Marcus R., Ines K. and 1 other reacted to your Iron Tracker session.",
            icon: "heart.fill",
            iconColor: .kineticsRed,
            timestamp: "4h ago",
            type: .social
        ),
        HomeNotification(
            id: UUID(),
            title: "Weekly goal progress",
            body: "You're at 3/5 sessions this week — 2 more to hit your goal.",
            icon: "calendar.badge.checkmark",
            iconColor: .kineticsGreen,
            timestamp: "Yesterday",
            type: .reminder
        ),
        HomeNotification(
            id: UUID(),
            title: "Recovery insight",
            body: "Taking a rest day after yesterday's session supports adaptation. Light mobility work is ideal.",
            icon: "waveform.path.ecg",
            iconColor: .kineticsBlue,
            timestamp: "Yesterday",
            type: .coach
        ),
    ]

    // MARK: Body

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    headerRow
                    notificationList
                    Spacer(minLength: 40)
                }
            }
            .background(Color.kineticsBackground)
            .navigationBarHidden(true)
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(Color.kineticsBackground)
        .presentationCornerRadius(24)
        .presentationDragIndicator(.visible)
    }

    // MARK: - Header Row

    private var headerRow: some View {
        HStack(alignment: .center, spacing: 12) {
            Text("NOTIFICATIONS")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white)

            Spacer()

            Button {
                // No-op — placeholder for future clear-all action
            } label: {
                Text("Clear All")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.kineticsBlue)
            }

            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.55))
                    .frame(width: 28, height: 28)
                    .background(Color.kineticsMidGray)
                    .clipShape(Circle())
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 20)
    }

    // MARK: - Notification List

    private var notificationList: some View {
        VStack(spacing: 0) {
            ForEach(Array(notifications.enumerated()), id: \.element.id) { index, notif in
                NotificationRow(notification: notif)

                if index < notifications.count - 1 {
                    Divider()
                        .background(Color.white.opacity(0.06))
                        .padding(.horizontal, 20)
                }
            }
        }
    }
}

// MARK: - NotificationRow

private struct NotificationRow: View {
    let notification: HomeNotification

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            // Icon badge
            ZStack {
                Circle()
                    .fill(notification.iconColor.opacity(0.14))
                    .frame(width: 42, height: 42)

                Image(systemName: notification.icon)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(notification.iconColor)
            }

            // Text content
            VStack(alignment: .leading, spacing: 3) {
                Text(notification.title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Text(notification.body)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(.white.opacity(0.60))
                    .fixedSize(horizontal: false, vertical: true)
                    .lineLimit(3)

                Text(notification.timestamp)
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(.white.opacity(0.35))
                    .padding(.top, 2)
            }

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }
}

// MARK: - Preview

#Preview {
    HomeNotificationsView()
}
