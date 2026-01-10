//
//  FocusHintsView.swift
//  TasksApp
//
//  SwiftUI view explaining Focus mode and Time Sensitive notifications
//

import SwiftUI

// MARK: - Focus Hints View

/// Educates users about iOS Focus mode and Time Sensitive notifications
struct FocusHintsView: View {

    @Environment(\.dismiss) private var dismiss
    @StateObject private var scheduler = NotificationScheduler.shared
    @ObservedObject private var preferences = RedBeaconPreferences.shared

    @State private var showingSettingsAlert = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: RemindersKit.Spacing.xxl) {
                    // Header illustration
                    headerSection

                    // Main explanation
                    explanationSection

                    // Steps to enable
                    stepsSection

                    // Important note
                    importantNoteSection

                    // Settings button
                    settingsButtonSection

                    Spacer(minLength: RemindersKit.Spacing.xxxl)
                }
                .padding(RemindersKit.Spacing.lg)
            }
            .background(RemindersColors.background)
            .navigationTitle("Focus & Notifications")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .font(RemindersTypography.button)
                    .foregroundColor(RemindersColors.accentBlue)
                }
            }
        }
        .alert("Open Settings", isPresented: $showingSettingsAlert) {
            Button("Open Settings") {
                scheduler.openNotificationSettings()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will open the Settings app where you can configure notification and Focus preferences for this app.")
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        VStack(spacing: RemindersKit.Spacing.md) {
            ZStack {
                // Background glow
                Circle()
                    .fill(RemindersColors.accentRed.opacity(0.15))
                    .frame(width: 120, height: 120)

                // Bell icon
                Image(systemName: "bell.badge.fill")
                    .font(.system(size: 48, weight: .medium))
                    .foregroundStyle(
                        RemindersColors.accentRed,
                        RemindersColors.accentOrange
                    )
            }

            Text("Time Sensitive Notifications")
                .font(RemindersTypography.title2)
                .foregroundColor(RemindersColors.textPrimary)
                .multilineTextAlignment(.center)

            if scheduler.isTimeSensitiveAuthorized {
                HStack(spacing: RemindersKit.Spacing.xs) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(RemindersColors.accentGreen)
                    Text("Enabled for this app")
                        .font(RemindersTypography.subheadline)
                        .foregroundColor(RemindersColors.accentGreen)
                }
            }
        }
    }

    // MARK: - Explanation Section

    private var explanationSection: some View {
        VStack(alignment: .leading, spacing: RemindersKit.Spacing.md) {
            Text("What are Time Sensitive notifications?")
                .font(RemindersTypography.headline)
                .foregroundColor(RemindersColors.textPrimary)

            Text("Time Sensitive is an iOS notification priority level. These notifications may break through some Focus modes if you allow it in your iOS Settings.")
                .font(RemindersTypography.body)
                .foregroundColor(RemindersColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Text("When you enable Red Beacon for a task, escalating reminders will use Time Sensitive priority to help ensure you see them.")
                .font(RemindersTypography.body)
                .foregroundColor(RemindersColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(RemindersKit.Spacing.lg)
        .background(RemindersColors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: RemindersKit.Radius.lg))
    }

    // MARK: - Steps Section

    private var stepsSection: some View {
        VStack(alignment: .leading, spacing: RemindersKit.Spacing.md) {
            Text("To allow Time Sensitive through Focus:")
                .font(RemindersTypography.headline)
                .foregroundColor(RemindersColors.textPrimary)

            VStack(alignment: .leading, spacing: RemindersKit.Spacing.lg) {
                stepRow(
                    number: 1,
                    title: "Open Settings",
                    description: "Go to Settings on your device"
                )

                stepRow(
                    number: 2,
                    title: "Select Focus",
                    description: "Tap on Focus to see your Focus modes"
                )

                stepRow(
                    number: 3,
                    title: "Choose a Focus mode",
                    description: "Select the Focus mode you want to configure (e.g., Do Not Disturb)"
                )

                stepRow(
                    number: 4,
                    title: "Allow Time Sensitive",
                    description: "Under \"Allowed Notifications\", enable Time Sensitive Notifications"
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(RemindersKit.Spacing.lg)
        .background(RemindersColors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: RemindersKit.Radius.lg))
    }

    private func stepRow(number: Int, title: String, description: String) -> some View {
        HStack(alignment: .top, spacing: RemindersKit.Spacing.md) {
            // Step number badge
            Text("\(number)")
                .font(RemindersTypography.footnoteBold)
                .foregroundColor(.white)
                .frame(width: 24, height: 24)
                .background(RemindersColors.accentBlue)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: RemindersKit.Spacing.xxs) {
                Text(title)
                    .font(RemindersTypography.bodyBold)
                    .foregroundColor(RemindersColors.textPrimary)

                Text(description)
                    .font(RemindersTypography.subheadline)
                    .foregroundColor(RemindersColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Important Note Section

    private var importantNoteSection: some View {
        HStack(alignment: .top, spacing: RemindersKit.Spacing.md) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 20))
                .foregroundColor(RemindersColors.accentBlue)

            VStack(alignment: .leading, spacing: RemindersKit.Spacing.xs) {
                Text("Important")
                    .font(RemindersTypography.bodyBold)
                    .foregroundColor(RemindersColors.textPrimary)

                Text("Time Sensitive notifications may break through some Focus modes if you allow it in iOS Settings. However, this is not guaranteed for all Focus configurations. You control which apps can deliver Time Sensitive notifications in Settings.")
                    .font(RemindersTypography.subheadline)
                    .foregroundColor(RemindersColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(RemindersKit.Spacing.lg)
        .background(RemindersColors.accentBlue.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: RemindersKit.Radius.lg))
    }

    // MARK: - Settings Button Section

    private var settingsButtonSection: some View {
        VStack(spacing: RemindersKit.Spacing.md) {
            Button {
                showingSettingsAlert = true
            } label: {
                HStack {
                    Image(systemName: "gear")
                    Text("Open App Settings")
                }
                .font(RemindersTypography.button)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(RemindersKit.Spacing.lg)
                .background(RemindersColors.accentBlue)
                .clipShape(RoundedRectangle(cornerRadius: RemindersKit.Radius.button))
            }

            // Toggle for showing hints
            Toggle(isOn: $preferences.showFocusHints) {
                Text("Show Focus hints in app")
                    .font(RemindersTypography.subheadline)
                    .foregroundColor(RemindersColors.textSecondary)
            }
            .tint(RemindersColors.accentBlue)
        }
    }
}

// MARK: - Compact Focus Hint Banner

/// A compact banner for inline Focus mode hints
struct FocusHintBanner: View {

    let onTapLearnMore: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: RemindersKit.Spacing.md) {
            Image(systemName: "moon.fill")
                .font(.system(size: 16))
                .foregroundColor(RemindersColors.accentPurple)

            VStack(alignment: .leading, spacing: RemindersKit.Spacing.xxxs) {
                Text("Focus Mode Active?")
                    .font(RemindersTypography.footnoteBold)
                    .foregroundColor(RemindersColors.textPrimary)

                Text("Time Sensitive may break through if enabled in Settings")
                    .font(RemindersTypography.caption1)
                    .foregroundColor(RemindersColors.textSecondary)
            }

            Spacer()

            Button {
                onTapLearnMore()
            } label: {
                Text("Learn")
                    .font(RemindersTypography.caption1Bold)
                    .foregroundColor(RemindersColors.accentBlue)
            }

            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(RemindersColors.textTertiary)
            }
        }
        .padding(RemindersKit.Spacing.md)
        .background(RemindersColors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: RemindersKit.Radius.md))
    }
}

// MARK: - Time Sensitive Status View

/// Shows the current Time Sensitive notification status
struct TimeSensitiveStatusView: View {

    @StateObject private var scheduler = NotificationScheduler.shared
    @State private var showingFocusHints = false

    var body: some View {
        Button {
            showingFocusHints = true
        } label: {
            HStack(spacing: RemindersKit.Spacing.sm) {
                Image(systemName: statusIcon)
                    .font(.system(size: 14))
                    .foregroundColor(statusColor)

                Text(statusText)
                    .font(RemindersTypography.footnote)
                    .foregroundColor(RemindersColors.textSecondary)

                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(RemindersColors.textTertiary)
            }
        }
        .sheet(isPresented: $showingFocusHints) {
            FocusHintsView()
        }
    }

    private var statusIcon: String {
        if scheduler.isTimeSensitiveAuthorized {
            return "bell.badge.fill"
        } else if scheduler.isAuthorized {
            return "bell.fill"
        } else {
            return "bell.slash"
        }
    }

    private var statusColor: Color {
        if scheduler.isTimeSensitiveAuthorized {
            return RemindersColors.accentGreen
        } else if scheduler.isAuthorized {
            return RemindersColors.accentOrange
        } else {
            return RemindersColors.textTertiary
        }
    }

    private var statusText: String {
        if scheduler.isTimeSensitiveAuthorized {
            return "Time Sensitive enabled"
        } else if scheduler.isAuthorized {
            return "Notifications enabled"
        } else {
            return "Notifications disabled"
        }
    }
}

// MARK: - Red Beacon Settings Row

/// Settings row for configuring Red Beacon escalation
struct RedBeaconSettingsRow: View {

    @ObservedObject private var preferences = RedBeaconPreferences.shared
    @State private var showingPresetPicker = false
    @State private var showingFocusHints = false

    var body: some View {
        VStack(alignment: .leading, spacing: RemindersKit.Spacing.md) {
            // Main toggle
            Toggle(isOn: $preferences.isEnabled) {
                HStack(spacing: RemindersKit.Spacing.md) {
                    Image(systemName: "bell.badge.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(
                            RemindersColors.accentRed,
                            RemindersColors.accentOrange
                        )
                        .frame(width: 28)

                    VStack(alignment: .leading, spacing: RemindersKit.Spacing.xxxs) {
                        Text("Red Beacon Reminders")
                            .font(RemindersTypography.body)
                            .foregroundColor(RemindersColors.textPrimary)

                        Text("Escalating notifications for important tasks")
                            .font(RemindersTypography.caption1)
                            .foregroundColor(RemindersColors.textSecondary)
                    }
                }
            }
            .tint(RemindersColors.accentRed)

            if preferences.isEnabled {
                Divider()
                    .background(RemindersColors.separator)

                // Escalation preset picker
                Button {
                    showingPresetPicker = true
                } label: {
                    HStack {
                        Image(systemName: preferences.escalationPreset.iconName)
                            .font(.system(size: 16))
                            .foregroundColor(RemindersColors.accentBlue)
                            .frame(width: 28)

                        Text("Escalation Level")
                            .font(RemindersTypography.body)
                            .foregroundColor(RemindersColors.textPrimary)

                        Spacer()

                        Text(preferences.escalationPreset.displayName)
                            .font(RemindersTypography.body)
                            .foregroundColor(RemindersColors.textSecondary)

                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(RemindersColors.textTertiary)
                    }
                }

                Divider()
                    .background(RemindersColors.separator)

                // Time Sensitive toggle
                Toggle(isOn: $preferences.useTimeSensitive) {
                    HStack(spacing: RemindersKit.Spacing.md) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundColor(RemindersColors.accentOrange)
                            .frame(width: 28)

                        Text("Use Time Sensitive")
                            .font(RemindersTypography.body)
                            .foregroundColor(RemindersColors.textPrimary)
                    }
                }
                .tint(RemindersColors.accentOrange)

                // Focus hints link
                Button {
                    showingFocusHints = true
                } label: {
                    HStack {
                        Image(systemName: "questionmark.circle")
                            .font(.system(size: 16))
                            .foregroundColor(RemindersColors.accentBlue)
                            .frame(width: 28)

                        Text("About Focus & Time Sensitive")
                            .font(RemindersTypography.subheadline)
                            .foregroundColor(RemindersColors.accentBlue)
                    }
                }
            }
        }
        .padding(RemindersKit.Spacing.lg)
        .background(RemindersColors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: RemindersKit.Radius.lg))
        .sheet(isPresented: $showingPresetPicker) {
            EscalationPresetPicker(selection: $preferences.escalationPreset)
                .presentationDetents([.medium])
        }
        .sheet(isPresented: $showingFocusHints) {
            FocusHintsView()
        }
    }
}

// MARK: - Escalation Preset Picker

struct EscalationPresetPicker: View {

    @Binding var selection: EscalationPreset
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(EscalationPreset.allCases) { preset in
                    Button {
                        selection = preset
                        dismiss()
                    } label: {
                        HStack(spacing: RemindersKit.Spacing.md) {
                            Image(systemName: preset.iconName)
                                .font(.system(size: 20))
                                .foregroundColor(presetColor(for: preset))
                                .frame(width: 28)

                            VStack(alignment: .leading, spacing: RemindersKit.Spacing.xxxs) {
                                Text(preset.displayName)
                                    .font(RemindersTypography.body)
                                    .foregroundColor(RemindersColors.textPrimary)

                                Text(preset.description)
                                    .font(RemindersTypography.caption1)
                                    .foregroundColor(RemindersColors.textSecondary)
                            }

                            Spacer()

                            if preset == selection {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(RemindersColors.accentBlue)
                            }
                        }
                    }
                    .listRowBackground(RemindersColors.backgroundSecondary)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(RemindersColors.background)
            .navigationTitle("Escalation Level")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .font(RemindersTypography.button)
                    .foregroundColor(RemindersColors.accentBlue)
                }
            }
        }
    }

    private func presetColor(for preset: EscalationPreset) -> Color {
        switch preset {
        case .none: return RemindersColors.textSecondary
        case .light: return RemindersColors.accentBlue
        case .moderate: return RemindersColors.accentOrange
        case .aggressive: return RemindersColors.accentRed
        }
    }
}

// MARK: - Preview

#Preview("Focus Hints") {
    FocusHintsView()
}

#Preview("Focus Hint Banner") {
    VStack(spacing: 16) {
        FocusHintBanner(
            onTapLearnMore: {},
            onDismiss: {}
        )

        TimeSensitiveStatusView()

        Spacer()
    }
    .padding()
    .background(RemindersColors.background)
}

#Preview("Red Beacon Settings") {
    ScrollView {
        VStack(spacing: 16) {
            RedBeaconSettingsRow()
        }
        .padding()
    }
    .background(RemindersColors.background)
}

#Preview("Escalation Picker") {
    EscalationPresetPicker(selection: .constant(.moderate))
}
