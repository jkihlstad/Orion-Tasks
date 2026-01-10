//
//  CalendarSyncSettingsView.swift
//  TasksApp
//
//  Settings UI for calendar sync configuration
//  Provides controls for sync toggle, calendar selection, and status display
//

import EventKit
import SwiftUI

// MARK: - Calendar Sync Settings View

/// Main settings view for calendar synchronization
struct CalendarSyncSettingsView: View {

    // MARK: - Properties

    @ObservedObject var calendarManager: CalendarSyncManager
    @State private var showingDeleteConfirmation = false
    @State private var showingDisconnectConfirmation = false

    // MARK: - Body

    var body: some View {
        List {
            // Permission banner if needed
            if !calendarManager.isAuthorized {
                Section {
                    EventKitPermissionBanner(calendarManager: calendarManager)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
            }

            // Main sync toggle section
            syncToggleSection

            // Status section
            if calendarManager.isSyncEnabled {
                statusSection
            }

            // App calendar section
            if calendarManager.isAuthorized && calendarManager.isSyncEnabled {
                appCalendarSection
            }

            // Import calendars section
            if calendarManager.isAuthorized && calendarManager.isSyncEnabled {
                importCalendarsSection
            }

            // Actions section
            if calendarManager.isAuthorized && calendarManager.isSyncEnabled {
                actionsSection
            }

            // Info section
            infoSection
        }
        .remindersGroupedStyle()
        .navigationTitle("Calendar Sync")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Remove All Synced Events?", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Remove", role: .destructive) {
                Task {
                    try? await calendarManager.removeAllSyncedEvents()
                }
            }
        } message: {
            Text("This will remove all calendar events created by this app. Your tasks will not be affected.")
        }
        .alert("Disconnect Calendar?", isPresented: $showingDisconnectConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Disconnect", role: .destructive) {
                Task {
                    await calendarManager.disconnect()
                }
            }
        } message: {
            Text("This will disable calendar sync and remove all sync data. Your tasks and calendar events will remain unchanged.")
        }
        .onAppear {
            calendarManager.checkAuthorizationStatus()
        }
    }

    // MARK: - Sync Toggle Section

    private var syncToggleSection: some View {
        Section {
            Toggle(isOn: $calendarManager.isSyncEnabled) {
                HStack(spacing: RemindersKit.Spacing.md) {
                    ZStack {
                        RoundedRectangle(cornerRadius: RemindersKit.Radius.listIcon)
                            .fill(RemindersColors.accentBlue)
                            .frame(width: 30, height: 30)

                        Image(systemName: "calendar")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                    }

                    VStack(alignment: .leading, spacing: RemindersKit.Spacing.xxxs) {
                        Text("Calendar Sync")
                            .font(RemindersTypography.body)
                            .foregroundColor(RemindersColors.textPrimary)

                        Text("Sync tasks with your calendar")
                            .font(RemindersTypography.caption1)
                            .foregroundColor(RemindersColors.textSecondary)
                    }
                }
            }
            .toggleStyle(SwitchToggleStyle(tint: RemindersColors.accentBlue))
            .disabled(!calendarManager.isAuthorized)
            .remindersListRow()
        } header: {
            Text("Synchronization")
                .font(RemindersTypography.sectionHeaderUppercase)
                .foregroundColor(RemindersColors.textSecondary)
                .textCase(.uppercase)
        } footer: {
            if !calendarManager.isAuthorized {
                Text("Enable calendar access to use this feature.")
                    .font(RemindersTypography.caption1)
                    .foregroundColor(RemindersColors.textTertiary)
            }
        }
    }

    // MARK: - Status Section

    private var statusSection: some View {
        Section {
            HStack {
                Text("Status")
                    .font(RemindersTypography.body)
                    .foregroundColor(RemindersColors.textPrimary)

                Spacer()

                HStack(spacing: RemindersKit.Spacing.xs) {
                    statusIndicator
                    Text(calendarManager.syncStatus.displayText)
                        .font(RemindersTypography.subheadline)
                        .foregroundColor(statusColor)
                }
            }
            .remindersListRow()

            if let error = calendarManager.lastError {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(RemindersColors.accentOrange)

                    Text(error.localizedDescription)
                        .font(RemindersTypography.caption1)
                        .foregroundColor(RemindersColors.textSecondary)
                }
                .remindersListRow()
            }
        } header: {
            Text("Sync Status")
                .font(RemindersTypography.sectionHeaderUppercase)
                .foregroundColor(RemindersColors.textSecondary)
                .textCase(.uppercase)
        }
    }

    private var statusIndicator: some View {
        Group {
            switch calendarManager.syncStatus {
            case .syncing:
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: RemindersColors.accentBlue))
                    .scaleEffect(0.7)

            case .completed:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(RemindersColors.accentGreen)

            case .failed:
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundColor(RemindersColors.accentRed)

            case .disabled:
                Image(systemName: "pause.circle.fill")
                    .foregroundColor(RemindersColors.textSecondary)

            case .idle:
                Image(systemName: "circle.fill")
                    .foregroundColor(RemindersColors.textTertiary)
                    .font(.system(size: 8))
            }
        }
    }

    private var statusColor: Color {
        switch calendarManager.syncStatus {
        case .syncing:
            return RemindersColors.accentBlue
        case .completed:
            return RemindersColors.accentGreen
        case .failed:
            return RemindersColors.accentRed
        case .disabled:
            return RemindersColors.textSecondary
        case .idle:
            return RemindersColors.textSecondary
        }
    }

    // MARK: - App Calendar Section

    private var appCalendarSection: some View {
        Section {
            if let calendar = calendarManager.appCalendar {
                HStack {
                    Circle()
                        .fill(calendar.swiftUIColor)
                        .frame(width: 14, height: 14)

                    VStack(alignment: .leading, spacing: RemindersKit.Spacing.xxxs) {
                        Text(calendar.title)
                            .font(RemindersTypography.body)
                            .foregroundColor(RemindersColors.textPrimary)

                        Text("Tasks with \"Mirror to Calendar\" appear here")
                            .font(RemindersTypography.caption1)
                            .foregroundColor(RemindersColors.textSecondary)
                    }

                    Spacer()

                    Image(systemName: "checkmark")
                        .foregroundColor(RemindersColors.accentBlue)
                        .font(.system(size: 14, weight: .semibold))
                }
                .remindersListRow()
            } else {
                Button {
                    Task {
                        await calendarManager.findOrCreateAppCalendar()
                    }
                } label: {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(RemindersColors.accentBlue)

                        Text("Create App Calendar")
                            .font(RemindersTypography.body)
                            .foregroundColor(RemindersColors.accentBlue)
                    }
                }
                .remindersListRow()
            }
        } header: {
            Text("Linked Calendar")
                .font(RemindersTypography.sectionHeaderUppercase)
                .foregroundColor(RemindersColors.textSecondary)
                .textCase(.uppercase)
        } footer: {
            Text("A dedicated calendar is created to store events from your tasks.")
                .font(RemindersTypography.caption1)
                .foregroundColor(RemindersColors.textTertiary)
        }
    }

    // MARK: - Import Calendars Section

    private var importCalendarsSection: some View {
        Section {
            ForEach(importableCalendars, id: \.calendarIdentifier) { calendar in
                CalendarSelectionRow(
                    calendar: calendar,
                    isSelected: calendarManager.selectedCalendarIdentifiers.contains(calendar.calendarIdentifier),
                    onToggle: { toggleCalendarSelection(calendar) }
                )
                .remindersListRow()
            }

            if importableCalendars.isEmpty {
                HStack {
                    Image(systemName: "calendar.badge.exclamationmark")
                        .foregroundColor(RemindersColors.textTertiary)

                    Text("No calendars available")
                        .font(RemindersTypography.body)
                        .foregroundColor(RemindersColors.textSecondary)
                }
                .remindersListRow()
            }
        } header: {
            Text("Import Events From")
                .font(RemindersTypography.sectionHeaderUppercase)
                .foregroundColor(RemindersColors.textSecondary)
                .textCase(.uppercase)
        } footer: {
            Text("Select calendars to import events as tasks. Events from these calendars will be converted to tasks automatically.")
                .font(RemindersTypography.caption1)
                .foregroundColor(RemindersColors.textTertiary)
        }
    }

    private var importableCalendars: [EKCalendar] {
        // Exclude the app calendar from import options
        calendarManager.availableCalendars.filter { calendar in
            calendar.calendarIdentifier != calendarManager.appCalendar?.calendarIdentifier
        }
    }

    private func toggleCalendarSelection(_ calendar: EKCalendar) {
        if calendarManager.selectedCalendarIdentifiers.contains(calendar.calendarIdentifier) {
            calendarManager.selectedCalendarIdentifiers.remove(calendar.calendarIdentifier)
        } else {
            calendarManager.selectedCalendarIdentifiers.insert(calendar.calendarIdentifier)
        }
    }

    // MARK: - Actions Section

    private var actionsSection: some View {
        Section {
            // Sync Now Button
            Button {
                Task {
                    await calendarManager.performSync()
                }
            } label: {
                HStack {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .foregroundColor(RemindersColors.accentBlue)

                    Text("Sync Now")
                        .font(RemindersTypography.body)
                        .foregroundColor(RemindersColors.accentBlue)

                    Spacer()

                    if case .syncing = calendarManager.syncStatus {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: RemindersColors.accentBlue))
                            .scaleEffect(0.8)
                    }
                }
            }
            .disabled(calendarManager.syncStatus == .syncing)
            .remindersListRow()

            // Remove Events Button
            Button {
                showingDeleteConfirmation = true
            } label: {
                HStack {
                    Image(systemName: "trash")
                        .foregroundColor(RemindersColors.accentRed)

                    Text("Remove All Synced Events")
                        .font(RemindersTypography.body)
                        .foregroundColor(RemindersColors.accentRed)
                }
            }
            .remindersListRow()

            // Disconnect Button
            Button {
                showingDisconnectConfirmation = true
            } label: {
                HStack {
                    Image(systemName: "link.badge.plus")
                        .rotationEffect(.degrees(45))
                        .foregroundColor(RemindersColors.accentRed)

                    Text("Disconnect Calendar Sync")
                        .font(RemindersTypography.body)
                        .foregroundColor(RemindersColors.accentRed)
                }
            }
            .remindersListRow()
        } header: {
            Text("Actions")
                .font(RemindersTypography.sectionHeaderUppercase)
                .foregroundColor(RemindersColors.textSecondary)
                .textCase(.uppercase)
        }
    }

    // MARK: - Info Section

    private var infoSection: some View {
        Section {
            VStack(alignment: .leading, spacing: RemindersKit.Spacing.md) {
                InfoRow(
                    icon: "arrow.triangle.2.circlepath",
                    title: "Two-way Sync",
                    description: "Changes sync both directions between tasks and calendar events."
                )

                InfoRow(
                    icon: "shield.fill",
                    title: "Loop Prevention",
                    description: "The app automatically prevents duplicate entries when syncing."
                )

                InfoRow(
                    icon: "calendar.badge.plus",
                    title: "Mirror to Calendar",
                    description: "Enable on individual tasks to show them as calendar events."
                )
            }
            .padding(.vertical, RemindersKit.Spacing.sm)
            .remindersListRow()
        } header: {
            Text("How It Works")
                .font(RemindersTypography.sectionHeaderUppercase)
                .foregroundColor(RemindersColors.textSecondary)
                .textCase(.uppercase)
        }
    }
}

// MARK: - Calendar Selection Row

private struct CalendarSelectionRow: View {
    let calendar: EKCalendar
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: RemindersKit.Spacing.md) {
                Circle()
                    .fill(calendar.swiftUIColor)
                    .frame(width: 14, height: 14)

                VStack(alignment: .leading, spacing: RemindersKit.Spacing.xxxs) {
                    Text(calendar.title)
                        .font(RemindersTypography.body)
                        .foregroundColor(RemindersColors.textPrimary)

                    if let source = calendar.source?.title {
                        Text(source)
                            .font(RemindersTypography.caption1)
                            .foregroundColor(RemindersColors.textTertiary)
                    }
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundColor(RemindersColors.accentBlue)
                        .font(.system(size: 14, weight: .semibold))
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Info Row

private struct InfoRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: RemindersKit.Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(RemindersColors.accentBlue)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: RemindersKit.Spacing.xxxs) {
                Text(title)
                    .font(RemindersTypography.subheadlineBold)
                    .foregroundColor(RemindersColors.textPrimary)

                Text(description)
                    .font(RemindersTypography.caption1)
                    .foregroundColor(RemindersColors.textSecondary)
            }
        }
    }
}

// MARK: - Calendar Sync Settings Row

/// A compact row for use in the main settings list
struct CalendarSyncSettingsRow: View {

    @ObservedObject var calendarManager: CalendarSyncManager

    var body: some View {
        HStack(spacing: RemindersKit.Spacing.md) {
            ZStack {
                RoundedRectangle(cornerRadius: RemindersKit.Radius.listIcon)
                    .fill(RemindersColors.accentBlue)
                    .frame(width: 30, height: 30)

                Image(systemName: "calendar")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
            }

            VStack(alignment: .leading, spacing: RemindersKit.Spacing.xxxs) {
                Text("Calendar Sync")
                    .font(RemindersTypography.body)
                    .foregroundColor(RemindersColors.textPrimary)

                Text(statusText)
                    .font(RemindersTypography.caption1)
                    .foregroundColor(statusColor)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(RemindersColors.textTertiary)
        }
    }

    private var statusText: String {
        if !calendarManager.isAuthorized {
            return "Not configured"
        } else if calendarManager.isSyncEnabled {
            return "Enabled"
        } else {
            return "Disabled"
        }
    }

    private var statusColor: Color {
        if !calendarManager.isAuthorized {
            return RemindersColors.textTertiary
        } else if calendarManager.isSyncEnabled {
            return RemindersColors.accentGreen
        } else {
            return RemindersColors.textSecondary
        }
    }
}

// MARK: - Preview

#Preview("Calendar Sync Settings") {
    NavigationStack {
        CalendarSyncSettingsView(calendarManager: CalendarSyncManager())
    }
    .preferredColorScheme(.dark)
}

#Preview("Settings Row") {
    List {
        CalendarSyncSettingsRow(calendarManager: CalendarSyncManager())
            .remindersListRow()
    }
    .remindersGroupedStyle()
    .preferredColorScheme(.dark)
}
