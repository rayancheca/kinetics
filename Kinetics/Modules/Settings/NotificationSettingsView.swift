import SwiftUI

// MARK: - NotificationSettingsView

struct NotificationSettingsView: View {

    // MARK: - Persisted State

    @AppStorage("notifications_reminders_enabled")
    private var remindersEnabled = false

    @AppStorage("notifications_reminder_days")
    private var reminderDaysRaw = ""            // comma-separated weekday ints, e.g. "2,4,6"

    @AppStorage("notifications_reminder_hour")
    private var reminderHour = 8

    @AppStorage("notifications_reminder_minute")
    private var reminderMinute = 0

    @AppStorage("notifications_achievements_enabled")
    private var achievementsEnabled = true

    // MARK: - Local UI State

    @State private var permissionGranted: Bool? = nil
    @State private var isSaving = false
    @State private var reminderTime = Date()    // drives the DatePicker; syncs to/from @AppStorage

    // MARK: - Computed Helpers

    /// Weekdays that are currently active as a `Set<Int>` (1 = Sun … 7 = Sat).
    private var selectedDays: Set<Int> {
        Set(
            reminderDaysRaw
                .split(separator: ",")
                .compactMap { Int($0) }
        )
    }

    // MARK: - Body

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 20) {
                remindersSection
                achievementsSection
                testButton
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 20)
        }
        .background(Color.kineticsBackground.ignoresSafeArea())
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbarBackground(Color.kineticsDark, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .task { await syncOnAppear() }
    }

    // MARK: - Reminders Section

    private var remindersSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("WORKOUT REMINDERS")

            VStack(spacing: 0) {
                // Master toggle
                Toggle(isOn: $remindersEnabled) {
                    iconLabel(
                        icon: "bell.badge.fill",
                        color: Color.kineticsBlue,
                        text: "Daily Reminders"
                    )
                }
                .toggleStyle(SwitchToggleStyle(tint: Color.kineticsBlue))
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .onChange(of: remindersEnabled) { _, enabled in
                    Task { await applyReminderChange(enabled: enabled) }
                }

                if remindersEnabled {
                    divider

                    // Day picker
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Repeat")
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.45))
                        dayPickerRow
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)

                    divider

                    // Time picker
                    HStack {
                        iconLabel(
                            icon: "clock.fill",
                            color: Color.kineticsGreen,
                            text: "Time"
                        )
                        Spacer()
                        DatePicker(
                            "",
                            selection: $reminderTime,
                            displayedComponents: .hourAndMinute
                        )
                        .labelsHidden()
                        .colorScheme(.dark)
                        .onChange(of: reminderTime) { _, newTime in
                            let cal = Calendar.current
                            reminderHour   = cal.component(.hour,   from: newTime)
                            reminderMinute = cal.component(.minute, from: newTime)
                            Task { await applyReminderChange(enabled: remindersEnabled) }
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)

                    divider

                    // Apply button
                    Button {
                        Task { await applyReminderChange(enabled: remindersEnabled) }
                    } label: {
                        HStack {
                            Spacer()
                            if isSaving {
                                ProgressView()
                                    .tint(Color.kineticsBlue)
                                    .scaleEffect(0.8)
                                Text("Saving…")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(Color.kineticsBlue)
                            } else {
                                Text("Apply Schedule")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(Color.kineticsBlue)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 12)
                    }
                    .disabled(isSaving)
                }
            }
            .background(Color.kineticsDark)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    // MARK: - Day Picker Row

    private var dayPickerRow: some View {
        HStack(spacing: 6) {
            ForEach(DayButton.allDays) { day in
                Button {
                    toggleDay(day.weekday)
                } label: {
                    Text(day.label)
                        .font(.system(size: 12, weight: .bold))
                        .frame(width: 36, height: 36)
                        .background(
                            selectedDays.contains(day.weekday)
                                ? Color.kineticsBlue
                                : Color.kineticsSubtext.opacity(0.3)
                        )
                        .foregroundStyle(
                            selectedDays.contains(day.weekday)
                                ? Color.kineticsDark
                                : .white.opacity(0.55)
                        )
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Achievements Section

    private var achievementsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("ACHIEVEMENT ALERTS")

            Toggle(isOn: $achievementsEnabled) {
                iconLabel(
                    icon: "trophy.fill",
                    color: Color.kineticsAmber,
                    text: "Achievement Alerts"
                )
            }
            .toggleStyle(SwitchToggleStyle(tint: Color.kineticsBlue))
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color.kineticsDark)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    // MARK: - Test Button

    private var testButton: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("DEBUG")

            Button {
                Task {
                    await NotificationService.shared.scheduleAchievementNotification(
                        title: "Test Notification",
                        body: "You're crushing it!"
                    )
                }
            } label: {
                HStack {
                    Image(systemName: "bell.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(Color.kineticsPurple)
                        .frame(width: 28)
                    Text("Test Notification")
                        .font(.system(size: 15))
                        .foregroundStyle(.white)
                    Spacer()
                    Text("~5s")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.35))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
            .background(Color.kineticsDark)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    // MARK: - Helpers: View Builders

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold))
            .tracking(2.5)
            .foregroundStyle(.white.opacity(0.38))
            .padding(.horizontal, 6)
            .padding(.bottom, 8)
    }

    private func iconLabel(icon: String, color: Color, text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundStyle(color)
                .frame(width: 28)
            Text(text)
                .font(.system(size: 15))
                .foregroundStyle(.white)
        }
    }

    private var divider: some View {
        Divider()
            .background(.white.opacity(0.06))
            .padding(.horizontal, 14)
    }

    // MARK: - Logic

    private func toggleDay(_ weekday: Int) {
        var days = selectedDays
        if days.contains(weekday) {
            days.remove(weekday)
        } else {
            days.insert(weekday)
        }
        reminderDaysRaw = days.sorted().map(String.init).joined(separator: ",")
    }

    private func applyReminderChange(enabled: Bool) async {
        isSaving = true
        defer { isSaving = false }

        guard enabled else {
            await NotificationService.shared.cancelWorkoutReminders(
                identifier: "workout_reminder"
            )
            return
        }

        // Request permission first; schedule only if granted.
        let granted = await NotificationService.shared.requestAuthorization()
        permissionGranted = granted
        guard granted else { return }

        let days = selectedDays.isEmpty ? [2, 4, 6] : Array(selectedDays) // M/W/F default
        await NotificationService.shared.scheduleWorkoutReminder(
            title: "Time to train",
            body: "Open Kinetics and crush today's session.",
            weekdays: days,
            hour: reminderHour,
            minute: reminderMinute,
            identifier: "workout_reminder"
        )
    }

    private func syncOnAppear() async {
        // Reconstruct the Date value the DatePicker binds to from stored hour/minute.
        var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        components.hour   = reminderHour
        components.minute = reminderMinute
        if let date = Calendar.current.date(from: components) {
            reminderTime = date
        }
    }
}

// MARK: - DayButton Model

private struct DayButton: Identifiable {
    let id: Int
    let weekday: Int    // UNCalendarNotificationTrigger weekday: 1 = Sun, 7 = Sat
    let label: String

    static let allDays: [DayButton] = [
        DayButton(id: 1, weekday: 2, label: "M"),
        DayButton(id: 2, weekday: 3, label: "T"),
        DayButton(id: 3, weekday: 4, label: "W"),
        DayButton(id: 4, weekday: 5, label: "T"),
        DayButton(id: 5, weekday: 6, label: "F"),
        DayButton(id: 6, weekday: 7, label: "S"),
        DayButton(id: 7, weekday: 1, label: "S"),
    ]
}
