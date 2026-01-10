//
//  PermissionsView.swift
//  TasksApp
//
//  System permissions request flow for notifications, calendar,
//  and microphone access with clear explanations
//

import SwiftUI
import UserNotifications
import EventKit
import AVFoundation

// MARK: - Permission Type

enum PermissionType: CaseIterable, Identifiable {
    case notifications
    case calendar
    case microphone

    var id: Self { self }

    var title: String {
        switch self {
        case .notifications:
            return "Notifications"
        case .calendar:
            return "Calendar Access"
        case .microphone:
            return "Microphone"
        }
    }

    var subtitle: String {
        switch self {
        case .notifications:
            return "Stay on top of your tasks"
        case .calendar:
            return "Sync with your schedule"
        case .microphone:
            return "Create tasks with your voice"
        }
    }

    var description: String {
        switch self {
        case .notifications:
            return "Receive reminders for due tasks, important updates, and smart alerts based on your preferences. You can customize notification settings at any time."
        case .calendar:
            return "See your calendar events alongside tasks, import events as tasks, and optionally mirror tasks to your calendar. We only read and write to calendars you choose."
        case .microphone:
            return "Use voice input to quickly create and manage tasks. Audio is processed in real-time and not stored on our servers."
        }
    }

    var icon: String {
        switch self {
        case .notifications:
            return "bell.badge.fill"
        case .calendar:
            return "calendar"
        case .microphone:
            return "mic.fill"
        }
    }

    var iconColor: Color {
        switch self {
        case .notifications:
            return RemindersColors.accentRed
        case .calendar:
            return RemindersColors.accentOrange
        case .microphone:
            return RemindersColors.accentPurple
        }
    }

    var requiredConsentScope: ConsentScope? {
        switch self {
        case .notifications:
            return nil // Always show
        case .calendar:
            return .calendar
        case .microphone:
            return .voice
        }
    }
}

// MARK: - Permission Status

enum PermissionStatus: Equatable {
    case notDetermined
    case authorized
    case denied
    case restricted
    case provisional // For notifications

    var displayText: String {
        switch self {
        case .notDetermined:
            return "Not Set"
        case .authorized:
            return "Allowed"
        case .denied:
            return "Denied"
        case .restricted:
            return "Restricted"
        case .provisional:
            return "Provisional"
        }
    }

    var isGranted: Bool {
        self == .authorized || self == .provisional
    }
}

// MARK: - Permissions View

struct PermissionsView: View {

    // MARK: - Environment

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    // MARK: - State

    @StateObject private var viewModel = PermissionsViewModel()

    // MARK: - Properties

    /// Consent preferences to determine which permissions to show
    let consentPreferences: ConsentPreferences

    /// Called when permissions flow is complete
    var onComplete: (() -> Void)?

    // MARK: - Computed Properties

    private var requiredPermissions: [PermissionType] {
        var permissions: [PermissionType] = [.notifications]

        if consentPreferences.hasCalendarConsent {
            permissions.append(.calendar)
        }

        if consentPreferences.hasVoiceConsent {
            permissions.append(.microphone)
        }

        return permissions
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                RemindersColors.background
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: RemindersKit.Spacing.xxl) {
                        // Header
                        headerSection

                        // Permission cards
                        VStack(spacing: RemindersKit.Spacing.md) {
                            ForEach(requiredPermissions) { permission in
                                permissionCard(permission)
                            }
                        }
                        .padding(.horizontal, RemindersKit.Spacing.lg)

                        // Info section
                        infoSection

                        Spacer(minLength: RemindersKit.Spacing.huge)

                        // Continue button
                        continueButton
                    }
                    .padding(.top, RemindersKit.Spacing.xl)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Skip") {
                        onComplete?()
                    }
                    .foregroundColor(RemindersColors.textSecondary)
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            viewModel.checkAllPermissions()
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        VStack(spacing: RemindersKit.Spacing.md) {
            // Icon
            ZStack {
                Circle()
                    .fill(RemindersColors.accentBlue.opacity(0.15))
                    .frame(width: 80, height: 80)

                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 36))
                    .foregroundColor(RemindersColors.accentBlue)
            }

            // Title
            Text("Enable Permissions")
                .font(RemindersTypography.title1)
                .foregroundColor(RemindersColors.textPrimary)

            // Subtitle
            Text("Grant access to unlock the full potential of Tasks. You can change these anytime in Settings.")
                .font(RemindersTypography.body)
                .foregroundColor(RemindersColors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, RemindersKit.Spacing.xl)
        }
    }

    // MARK: - Permission Card

    private func permissionCard(_ permission: PermissionType) -> some View {
        let status = viewModel.permissionStatus(for: permission)

        return VStack(spacing: 0) {
            // Main content
            HStack(spacing: RemindersKit.Spacing.md) {
                // Icon
                Image(systemName: permission.icon)
                    .font(.system(size: 24))
                    .foregroundColor(permission.iconColor)
                    .frame(width: 48, height: 48)
                    .background(permission.iconColor.opacity(0.15))
                    .cornerRadius(RemindersKit.Radius.md)

                // Text
                VStack(alignment: .leading, spacing: RemindersKit.Spacing.xxs) {
                    Text(permission.title)
                        .font(RemindersTypography.headline)
                        .foregroundColor(RemindersColors.textPrimary)

                    Text(permission.subtitle)
                        .font(RemindersTypography.subheadline)
                        .foregroundColor(RemindersColors.textSecondary)
                }

                Spacer()

                // Status/Action
                permissionActionButton(permission: permission, status: status)
            }
            .padding(RemindersKit.Spacing.md)

            // Description (expandable)
            if viewModel.expandedPermission == permission {
                VStack(alignment: .leading, spacing: RemindersKit.Spacing.md) {
                    Divider()
                        .background(RemindersColors.separator)

                    Text(permission.description)
                        .font(RemindersTypography.footnote)
                        .foregroundColor(RemindersColors.textSecondary)
                        .padding(.horizontal, RemindersKit.Spacing.md)
                        .padding(.bottom, RemindersKit.Spacing.md)

                    // Open settings if denied
                    if status == .denied {
                        Button {
                            openSettings()
                        } label: {
                            HStack {
                                Image(systemName: "gear")
                                Text("Open Settings")
                            }
                            .font(RemindersTypography.subheadlineBold)
                            .foregroundColor(RemindersColors.accentBlue)
                        }
                        .padding(.horizontal, RemindersKit.Spacing.md)
                        .padding(.bottom, RemindersKit.Spacing.md)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(RemindersColors.backgroundSecondary)
        .cornerRadius(RemindersKit.Radius.lg)
        .onTapGesture {
            withAnimation(RemindersKit.Animation.smooth) {
                if viewModel.expandedPermission == permission {
                    viewModel.expandedPermission = nil
                } else {
                    viewModel.expandedPermission = permission
                }
            }
        }
    }

    // MARK: - Permission Action Button

    @ViewBuilder
    private func permissionActionButton(permission: PermissionType, status: PermissionStatus) -> some View {
        switch status {
        case .notDetermined:
            Button("Allow") {
                Task {
                    await viewModel.requestPermission(permission)
                }
            }
            .font(RemindersTypography.buttonSmall)
            .foregroundColor(.white)
            .padding(.horizontal, RemindersKit.Spacing.md)
            .padding(.vertical, RemindersKit.Spacing.sm)
            .background(RemindersColors.accentBlue)
            .cornerRadius(RemindersKit.Radius.buttonSmall)

        case .authorized, .provisional:
            HStack(spacing: RemindersKit.Spacing.xxs) {
                Image(systemName: "checkmark.circle.fill")
                Text("Allowed")
            }
            .font(RemindersTypography.subheadline)
            .foregroundColor(RemindersColors.accentGreen)

        case .denied:
            HStack(spacing: RemindersKit.Spacing.xxs) {
                Image(systemName: "xmark.circle.fill")
                Text("Denied")
            }
            .font(RemindersTypography.subheadline)
            .foregroundColor(RemindersColors.accentRed)

        case .restricted:
            Text("Restricted")
                .font(RemindersTypography.subheadline)
                .foregroundColor(RemindersColors.textTertiary)
        }
    }

    // MARK: - Info Section

    private var infoSection: some View {
        VStack(spacing: RemindersKit.Spacing.md) {
            HStack(spacing: RemindersKit.Spacing.sm) {
                Image(systemName: "lock.shield.fill")
                    .foregroundColor(RemindersColors.accentGreen)

                Text("Your privacy is protected")
                    .font(RemindersTypography.headline)
                    .foregroundColor(RemindersColors.textPrimary)
            }

            VStack(alignment: .leading, spacing: RemindersKit.Spacing.sm) {
                infoRow(icon: "checkmark", text: "Permissions can be changed anytime in Settings")
                infoRow(icon: "checkmark", text: "We only access what you explicitly allow")
                infoRow(icon: "checkmark", text: "No data is shared without your consent")
            }
        }
        .padding(RemindersKit.Spacing.lg)
        .background(RemindersColors.backgroundSecondary)
        .cornerRadius(RemindersKit.Radius.lg)
        .padding(.horizontal, RemindersKit.Spacing.lg)
    }

    private func infoRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: RemindersKit.Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(RemindersColors.accentGreen)
                .frame(width: 20)

            Text(text)
                .font(RemindersTypography.footnote)
                .foregroundColor(RemindersColors.textSecondary)

            Spacer()
        }
    }

    // MARK: - Continue Button

    private var continueButton: some View {
        VStack(spacing: RemindersKit.Spacing.md) {
            PrimaryButton(
                viewModel.allRequiredPermissionsGranted(for: requiredPermissions)
                ? "Continue"
                : "Continue Anyway",
                icon: "arrow.right"
            ) {
                onComplete?()
            }

            if !viewModel.allRequiredPermissionsGranted(for: requiredPermissions) {
                Text("Some features may be limited without all permissions.")
                    .font(RemindersTypography.caption1)
                    .foregroundColor(RemindersColors.textTertiary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, RemindersKit.Spacing.xl)
        .padding(.bottom, RemindersKit.Spacing.xxxl)
    }

    // MARK: - Actions

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            openURL(url)
        }
    }
}

// MARK: - Permissions View Model

@MainActor
final class PermissionsViewModel: ObservableObject {

    // MARK: - Published Properties

    @Published private(set) var notificationStatus: PermissionStatus = .notDetermined
    @Published private(set) var calendarStatus: PermissionStatus = .notDetermined
    @Published private(set) var microphoneStatus: PermissionStatus = .notDetermined

    @Published var expandedPermission: PermissionType?
    @Published private(set) var isRequesting: Bool = false

    // MARK: - Properties

    private let notificationCenter = UNUserNotificationCenter.current()
    private let eventStore = EKEventStore()

    // MARK: - Permission Status

    func permissionStatus(for permission: PermissionType) -> PermissionStatus {
        switch permission {
        case .notifications:
            return notificationStatus
        case .calendar:
            return calendarStatus
        case .microphone:
            return microphoneStatus
        }
    }

    func allRequiredPermissionsGranted(for permissions: [PermissionType]) -> Bool {
        permissions.allSatisfy { permissionStatus(for: $0).isGranted }
    }

    // MARK: - Check Permissions

    func checkAllPermissions() {
        checkNotificationPermission()
        checkCalendarPermission()
        checkMicrophonePermission()
    }

    private func checkNotificationPermission() {
        Task {
            let settings = await notificationCenter.notificationSettings()
            await MainActor.run {
                switch settings.authorizationStatus {
                case .notDetermined:
                    notificationStatus = .notDetermined
                case .authorized:
                    notificationStatus = .authorized
                case .denied:
                    notificationStatus = .denied
                case .provisional:
                    notificationStatus = .provisional
                case .ephemeral:
                    notificationStatus = .authorized
                @unknown default:
                    notificationStatus = .notDetermined
                }
            }
        }
    }

    private func checkCalendarPermission() {
        let status = EKEventStore.authorizationStatus(for: .event)
        switch status {
        case .notDetermined:
            calendarStatus = .notDetermined
        case .authorized, .fullAccess:
            calendarStatus = .authorized
        case .denied:
            calendarStatus = .denied
        case .restricted, .writeOnly:
            calendarStatus = .restricted
        @unknown default:
            calendarStatus = .notDetermined
        }
    }

    private func checkMicrophonePermission() {
        switch AVAudioApplication.shared.recordPermission {
        case .undetermined:
            microphoneStatus = .notDetermined
        case .granted:
            microphoneStatus = .authorized
        case .denied:
            microphoneStatus = .denied
        @unknown default:
            microphoneStatus = .notDetermined
        }
    }

    // MARK: - Request Permissions

    func requestPermission(_ permission: PermissionType) async {
        isRequesting = true
        defer { isRequesting = false }

        switch permission {
        case .notifications:
            await requestNotificationPermission()
        case .calendar:
            await requestCalendarPermission()
        case .microphone:
            await requestMicrophonePermission()
        }

        Logger.shared.logConsent(
            event: "Permission requested",
            details: "\(permission.title): \(permissionStatus(for: permission).displayText)"
        )
    }

    private func requestNotificationPermission() async {
        do {
            let granted = try await notificationCenter.requestAuthorization(
                options: [.alert, .badge, .sound, .provisional]
            )
            notificationStatus = granted ? .authorized : .denied
        } catch {
            Logger.shared.error(error, message: "Failed to request notification permission", category: .app)
            notificationStatus = .denied
        }
    }

    private func requestCalendarPermission() async {
        do {
            if #available(iOS 17.0, *) {
                let granted = try await eventStore.requestFullAccessToEvents()
                calendarStatus = granted ? .authorized : .denied
            } else {
                let granted = try await eventStore.requestAccess(to: .event)
                calendarStatus = granted ? .authorized : .denied
            }
        } catch {
            Logger.shared.error(error, message: "Failed to request calendar permission", category: .calendar)
            calendarStatus = .denied
        }
    }

    private func requestMicrophonePermission() async {
        let granted = await AVAudioApplication.requestRecordPermission()
        microphoneStatus = granted ? .authorized : .denied
    }
}

// MARK: - Preview

#Preview("All Permissions") {
    PermissionsView(
        consentPreferences: .fullConsent,
        onComplete: { print("Complete") }
    )
}

#Preview("Notifications Only") {
    PermissionsView(
        consentPreferences: .minimalConsent,
        onComplete: { print("Complete") }
    )
}
