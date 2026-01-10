//
//  EventKitPermissionGate.swift
//  TasksApp
//
//  Permission request UI for calendar access
//  Handles authorization flow and denied state with Settings link
//

import EventKit
import SwiftUI

// MARK: - Permission State

/// Represents the current state of EventKit permission
enum EventKitPermissionState: Equatable {
    case notDetermined
    case authorized
    case denied
    case restricted
    case writeOnly

    init(from status: EKAuthorizationStatus) {
        switch status {
        case .notDetermined:
            self = .notDetermined
        case .authorized:
            self = .authorized
        case .denied:
            self = .denied
        case .restricted:
            self = .restricted
        case .fullAccess:
            self = .authorized
        case .writeOnly:
            self = .writeOnly
        @unknown default:
            self = .denied
        }
    }

    var isUsable: Bool {
        switch self {
        case .authorized:
            return true
        default:
            return false
        }
    }
}

// MARK: - EventKit Permission Gate View

/// A view that gates content behind calendar permission
/// Shows appropriate UI based on authorization status
struct EventKitPermissionGate<Content: View>: View {

    // MARK: - Properties

    @ObservedObject var calendarManager: CalendarSyncManager
    @ViewBuilder let content: () -> Content

    @State private var isRequestingPermission = false

    // MARK: - Computed Properties

    private var permissionState: EventKitPermissionState {
        EventKitPermissionState(from: calendarManager.authorizationStatus)
    }

    // MARK: - Body

    var body: some View {
        Group {
            switch permissionState {
            case .notDetermined:
                notDeterminedView

            case .authorized:
                content()

            case .denied:
                deniedView

            case .restricted:
                restrictedView

            case .writeOnly:
                writeOnlyView
            }
        }
    }

    // MARK: - Not Determined View

    private var notDeterminedView: some View {
        VStack(spacing: RemindersKit.Spacing.xxl) {
            Spacer()

            // Icon
            ZStack {
                Circle()
                    .fill(RemindersColors.accentBlue.opacity(0.15))
                    .frame(width: 100, height: 100)

                Image(systemName: "calendar.badge.plus")
                    .font(.system(size: 44, weight: .medium))
                    .foregroundColor(RemindersColors.accentBlue)
            }

            // Title and Description
            VStack(spacing: RemindersKit.Spacing.sm) {
                Text("Calendar Access")
                    .font(RemindersTypography.title2)
                    .foregroundColor(RemindersColors.textPrimary)

                Text("Allow access to your calendars to sync tasks with calendar events and import events as tasks.")
                    .font(RemindersTypography.body)
                    .foregroundColor(RemindersColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, RemindersKit.Spacing.xl)
            }

            // Features list
            VStack(alignment: .leading, spacing: RemindersKit.Spacing.md) {
                featureRow(
                    icon: "arrow.triangle.2.circlepath",
                    title: "Two-way sync",
                    description: "Keep tasks and events in sync"
                )

                featureRow(
                    icon: "calendar",
                    title: "Import events",
                    description: "Turn calendar events into tasks"
                )

                featureRow(
                    icon: "bell.badge",
                    title: "See reminders",
                    description: "View tasks on your calendar"
                )
            }
            .padding(.horizontal, RemindersKit.Spacing.xxl)

            Spacer()

            // Request Permission Button
            Button {
                requestPermission()
            } label: {
                HStack(spacing: RemindersKit.Spacing.sm) {
                    if isRequestingPermission {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(0.9)
                    }
                    Text("Allow Calendar Access")
                        .font(RemindersTypography.button)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, RemindersKit.Spacing.buttonPaddingV)
                .background(RemindersColors.accentBlue)
                .foregroundColor(.white)
                .clipShape(RoundedRectangle(cornerRadius: RemindersKit.Radius.button))
            }
            .disabled(isRequestingPermission)
            .padding(.horizontal, RemindersKit.Spacing.xl)

            // Skip Button
            Button {
                // Just dismiss or navigate away
            } label: {
                Text("Not Now")
                    .font(RemindersTypography.button)
                    .foregroundColor(RemindersColors.textSecondary)
            }
            .padding(.bottom, RemindersKit.Spacing.xl)
        }
        .background(RemindersColors.background)
    }

    // MARK: - Denied View

    private var deniedView: some View {
        VStack(spacing: RemindersKit.Spacing.xxl) {
            Spacer()

            // Icon
            ZStack {
                Circle()
                    .fill(RemindersColors.accentOrange.opacity(0.15))
                    .frame(width: 100, height: 100)

                Image(systemName: "calendar.badge.exclamationmark")
                    .font(.system(size: 44, weight: .medium))
                    .foregroundColor(RemindersColors.accentOrange)
            }

            // Title and Description
            VStack(spacing: RemindersKit.Spacing.sm) {
                Text("Calendar Access Denied")
                    .font(RemindersTypography.title2)
                    .foregroundColor(RemindersColors.textPrimary)

                Text("Calendar sync requires access to your calendars. You can enable this in Settings.")
                    .font(RemindersTypography.body)
                    .foregroundColor(RemindersColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, RemindersKit.Spacing.xl)
            }

            Spacer()

            // Open Settings Button
            Button {
                openSettings()
            } label: {
                HStack(spacing: RemindersKit.Spacing.sm) {
                    Image(systemName: "gear")
                    Text("Open Settings")
                        .font(RemindersTypography.button)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, RemindersKit.Spacing.buttonPaddingV)
                .background(RemindersColors.accentBlue)
                .foregroundColor(.white)
                .clipShape(RoundedRectangle(cornerRadius: RemindersKit.Radius.button))
            }
            .padding(.horizontal, RemindersKit.Spacing.xl)

            // Info text
            Text("Go to Settings > Privacy & Security > Calendars > Orion Tasks and enable calendar access.")
                .font(RemindersTypography.footnote)
                .foregroundColor(RemindersColors.textTertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, RemindersKit.Spacing.xl)
                .padding(.bottom, RemindersKit.Spacing.xl)
        }
        .background(RemindersColors.background)
    }

    // MARK: - Restricted View

    private var restrictedView: some View {
        VStack(spacing: RemindersKit.Spacing.xxl) {
            Spacer()

            // Icon
            ZStack {
                Circle()
                    .fill(RemindersColors.accentRed.opacity(0.15))
                    .frame(width: 100, height: 100)

                Image(systemName: "lock.fill")
                    .font(.system(size: 44, weight: .medium))
                    .foregroundColor(RemindersColors.accentRed)
            }

            // Title and Description
            VStack(spacing: RemindersKit.Spacing.sm) {
                Text("Calendar Access Restricted")
                    .font(RemindersTypography.title2)
                    .foregroundColor(RemindersColors.textPrimary)

                Text("Calendar access is restricted on this device. This may be due to parental controls or device management policies.")
                    .font(RemindersTypography.body)
                    .foregroundColor(RemindersColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, RemindersKit.Spacing.xl)
            }

            Spacer()

            // Contact Admin text
            Text("Please contact your device administrator if you need to enable calendar sync.")
                .font(RemindersTypography.footnote)
                .foregroundColor(RemindersColors.textTertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, RemindersKit.Spacing.xl)
                .padding(.bottom, RemindersKit.Spacing.xl)
        }
        .background(RemindersColors.background)
    }

    // MARK: - Write Only View

    private var writeOnlyView: some View {
        VStack(spacing: RemindersKit.Spacing.xxl) {
            Spacer()

            // Icon
            ZStack {
                Circle()
                    .fill(RemindersColors.accentOrange.opacity(0.15))
                    .frame(width: 100, height: 100)

                Image(systemName: "calendar.badge.minus")
                    .font(.system(size: 44, weight: .medium))
                    .foregroundColor(RemindersColors.accentOrange)
            }

            // Title and Description
            VStack(spacing: RemindersKit.Spacing.sm) {
                Text("Limited Calendar Access")
                    .font(RemindersTypography.title2)
                    .foregroundColor(RemindersColors.textPrimary)

                Text("Calendar sync needs full access to work properly. Currently, only write access is granted.")
                    .font(RemindersTypography.body)
                    .foregroundColor(RemindersColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, RemindersKit.Spacing.xl)
            }

            Spacer()

            // Open Settings Button
            Button {
                openSettings()
            } label: {
                HStack(spacing: RemindersKit.Spacing.sm) {
                    Image(systemName: "gear")
                    Text("Update in Settings")
                        .font(RemindersTypography.button)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, RemindersKit.Spacing.buttonPaddingV)
                .background(RemindersColors.accentBlue)
                .foregroundColor(.white)
                .clipShape(RoundedRectangle(cornerRadius: RemindersKit.Radius.button))
            }
            .padding(.horizontal, RemindersKit.Spacing.xl)
            .padding(.bottom, RemindersKit.Spacing.xl)
        }
        .background(RemindersColors.background)
    }

    // MARK: - Helper Views

    private func featureRow(icon: String, title: String, description: String) -> some View {
        HStack(alignment: .top, spacing: RemindersKit.Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .medium))
                .foregroundColor(RemindersColors.accentBlue)
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: RemindersKit.Spacing.xxxs) {
                Text(title)
                    .font(RemindersTypography.headline)
                    .foregroundColor(RemindersColors.textPrimary)

                Text(description)
                    .font(RemindersTypography.subheadline)
                    .foregroundColor(RemindersColors.textSecondary)
            }

            Spacer()
        }
    }

    // MARK: - Actions

    private func requestPermission() {
        isRequestingPermission = true

        Task {
            _ = await calendarManager.requestCalendarAccess()
            isRequestingPermission = false
        }
    }

    private func openSettings() {
        #if os(iOS)
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
        #endif
    }
}

// MARK: - Compact Permission Banner

/// A compact banner for showing permission status in settings
struct EventKitPermissionBanner: View {

    @ObservedObject var calendarManager: CalendarSyncManager
    @State private var isRequestingPermission = false

    private var permissionState: EventKitPermissionState {
        EventKitPermissionState(from: calendarManager.authorizationStatus)
    }

    var body: some View {
        if !permissionState.isUsable {
            HStack(spacing: RemindersKit.Spacing.md) {
                Image(systemName: iconName)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(iconColor)

                VStack(alignment: .leading, spacing: RemindersKit.Spacing.xxxs) {
                    Text(titleText)
                        .font(RemindersTypography.subheadline)
                        .foregroundColor(RemindersColors.textPrimary)

                    Text(subtitleText)
                        .font(RemindersTypography.caption1)
                        .foregroundColor(RemindersColors.textSecondary)
                }

                Spacer()

                Button {
                    handleAction()
                } label: {
                    if isRequestingPermission {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: RemindersColors.accentBlue))
                            .scaleEffect(0.8)
                    } else {
                        Text(buttonText)
                            .font(RemindersTypography.subheadlineBold)
                            .foregroundColor(RemindersColors.accentBlue)
                    }
                }
                .disabled(isRequestingPermission)
            }
            .padding(RemindersKit.Spacing.md)
            .background(bannerColor.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: RemindersKit.Radius.md))
        }
    }

    private var iconName: String {
        switch permissionState {
        case .notDetermined:
            return "calendar.badge.plus"
        case .denied:
            return "exclamationmark.triangle.fill"
        case .restricted:
            return "lock.fill"
        case .writeOnly:
            return "exclamationmark.circle.fill"
        default:
            return "checkmark.circle.fill"
        }
    }

    private var iconColor: Color {
        switch permissionState {
        case .notDetermined:
            return RemindersColors.accentBlue
        case .denied, .restricted:
            return RemindersColors.accentOrange
        case .writeOnly:
            return RemindersColors.accentYellow
        default:
            return RemindersColors.accentGreen
        }
    }

    private var bannerColor: Color {
        switch permissionState {
        case .notDetermined:
            return RemindersColors.accentBlue
        case .denied, .restricted:
            return RemindersColors.accentOrange
        case .writeOnly:
            return RemindersColors.accentYellow
        default:
            return RemindersColors.accentGreen
        }
    }

    private var titleText: String {
        switch permissionState {
        case .notDetermined:
            return "Calendar access needed"
        case .denied:
            return "Calendar access denied"
        case .restricted:
            return "Calendar restricted"
        case .writeOnly:
            return "Limited access"
        default:
            return "Calendar connected"
        }
    }

    private var subtitleText: String {
        switch permissionState {
        case .notDetermined:
            return "Enable to sync with calendars"
        case .denied:
            return "Open Settings to enable"
        case .restricted:
            return "Contact your administrator"
        case .writeOnly:
            return "Full access required"
        default:
            return "Two-way sync enabled"
        }
    }

    private var buttonText: String {
        switch permissionState {
        case .notDetermined:
            return "Enable"
        case .denied, .writeOnly:
            return "Settings"
        default:
            return ""
        }
    }

    private func handleAction() {
        switch permissionState {
        case .notDetermined:
            requestPermission()
        case .denied, .writeOnly:
            openSettings()
        default:
            break
        }
    }

    private func requestPermission() {
        isRequestingPermission = true
        Task {
            _ = await calendarManager.requestCalendarAccess()
            isRequestingPermission = false
        }
    }

    private func openSettings() {
        #if os(iOS)
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
        #endif
    }
}

// MARK: - Preview

#Preview("Not Determined") {
    // For preview purposes, create a mock state
    let manager = CalendarSyncManager()
    return EventKitPermissionGate(calendarManager: manager) {
        Text("Content shown when authorized")
    }
}

#Preview("Permission Banner") {
    let manager = CalendarSyncManager()
    return VStack {
        EventKitPermissionBanner(calendarManager: manager)
            .padding()
        Spacer()
    }
    .background(RemindersColors.background)
}
