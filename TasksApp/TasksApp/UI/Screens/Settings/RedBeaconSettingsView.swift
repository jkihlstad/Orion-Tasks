//
//  RedBeaconSettingsView.swift
//  TasksApp
//
//  Settings view for Red Beacon escalation feature
//  Configures escalation presets and Time Sensitive notifications
//

import SwiftUI
import UserNotifications

// MARK: - Escalation Preset

/// Predefined escalation timing presets
enum EscalationPreset: String, CaseIterable, Identifiable, Codable {
    case gentle = "gentle"
    case moderate = "moderate"
    case aggressive = "aggressive"
    case custom = "custom"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .gentle: return "Gentle"
        case .moderate: return "Moderate"
        case .aggressive: return "Aggressive"
        case .custom: return "Custom"
        }
    }

    var description: String {
        switch self {
        case .gentle:
            return "Reminders at 1 hour, 30 min, and 15 min before due time"
        case .moderate:
            return "Reminders at 2 hours, 1 hour, 30 min, and 5 min before"
        case .aggressive:
            return "Frequent reminders starting 4 hours before, escalating to every 5 min"
        case .custom:
            return "Configure your own reminder schedule"
        }
    }

    var icon: String {
        switch self {
        case .gentle: return "bell"
        case .moderate: return "bell.badge"
        case .aggressive: return "bell.badge.fill"
        case .custom: return "slider.horizontal.3"
        }
    }

    var color: Color {
        switch self {
        case .gentle: return RemindersColors.accentGreen
        case .moderate: return RemindersColors.accentOrange
        case .aggressive: return RemindersColors.accentRed
        case .custom: return RemindersColors.accentBlue
        }
    }

    /// Notification intervals in minutes before due time
    var intervals: [Int] {
        switch self {
        case .gentle:
            return [60, 30, 15]
        case .moderate:
            return [120, 60, 30, 5]
        case .aggressive:
            return [240, 120, 60, 30, 15, 10, 5]
        case .custom:
            return [] // Configured by user
        }
    }
}

// MARK: - Red Beacon Settings

/// User settings for Red Beacon feature
struct RedBeaconSettings: Codable, Equatable {
    /// Whether Red Beacon is globally enabled
    var isEnabled: Bool

    /// Selected escalation preset
    var preset: EscalationPreset

    /// Custom intervals (in minutes) when using custom preset
    var customIntervals: [Int]

    /// Whether to use Time Sensitive notifications
    var useTimeSensitive: Bool

    /// Whether to include sound with notifications
    var includeSound: Bool

    /// Custom sound name (nil for default)
    var soundName: String?

    /// Whether to announce via TTS when speaking enabled
    var announceWithTTS: Bool

    /// Whether to show badge on app icon
    var showBadge: Bool

    /// Default settings
    static let `default` = RedBeaconSettings(
        isEnabled: true,
        preset: .moderate,
        customIntervals: [60, 30, 15, 5],
        useTimeSensitive: true,
        includeSound: true,
        soundName: nil,
        announceWithTTS: false,
        showBadge: true
    )
}

// MARK: - Red Beacon Settings View Model

@MainActor
final class RedBeaconSettingsViewModel: ObservableObject {

    // MARK: - Published Properties

    @Published var settings: RedBeaconSettings {
        didSet {
            saveSettings()
        }
    }

    @Published private(set) var notificationAuthStatus: UNAuthorizationStatus = .notDetermined
    @Published private(set) var isTimeSensitiveAvailable: Bool = false
    @Published private(set) var isSendingTestNotification: Bool = false
    @Published var showingCustomIntervalsEditor: Bool = false

    // MARK: - Properties

    private let userDefaults: UserDefaults
    private let notificationCenter: UNUserNotificationCenter
    private let settingsKey = "red_beacon_settings"

    // MARK: - Initialization

    init(
        userDefaults: UserDefaults = .standard,
        notificationCenter: UNUserNotificationCenter = .current()
    ) {
        self.userDefaults = userDefaults
        self.notificationCenter = notificationCenter

        // Load saved settings
        if let data = userDefaults.data(forKey: settingsKey),
           let decoded = try? JSONDecoder().decode(RedBeaconSettings.self, from: data) {
            self.settings = decoded
        } else {
            self.settings = .default
        }

        // Check notification status
        Task {
            await checkNotificationStatus()
        }
    }

    // MARK: - Public Methods

    /// Request notification permissions
    func requestNotificationPermission() async {
        do {
            let granted = try await notificationCenter.requestAuthorization(
                options: [.alert, .badge, .sound, .criticalAlert, .providesAppNotificationSettings]
            )

            notificationAuthStatus = granted ? .authorized : .denied

            // Check Time Sensitive availability
            await checkTimeSensitiveAvailability()
        } catch {
            notificationAuthStatus = .denied
        }
    }

    /// Check current notification authorization status
    func checkNotificationStatus() async {
        let settings = await notificationCenter.notificationSettings()
        notificationAuthStatus = settings.authorizationStatus

        // Check for Time Sensitive
        if #available(iOS 15.0, *) {
            isTimeSensitiveAvailable = settings.timeSensitiveSetting == .enabled
        }
    }

    /// Send a test notification
    func sendTestNotification() async {
        guard notificationAuthStatus == .authorized else {
            await requestNotificationPermission()
            return
        }

        isSendingTestNotification = true
        defer { isSendingTestNotification = false }

        let content = UNMutableNotificationContent()
        content.title = "Red Beacon Test"
        content.body = "This is how your Red Beacon notifications will appear."
        content.categoryIdentifier = "RED_BEACON_TEST"

        if settings.includeSound {
            if let soundName = settings.soundName {
                content.sound = UNNotificationSound(named: UNNotificationSoundName(rawValue: soundName))
            } else {
                content.sound = .default
            }
        }

        if settings.showBadge {
            content.badge = 1
        }

        // Set as Time Sensitive if available and enabled
        if #available(iOS 15.0, *), settings.useTimeSensitive, isTimeSensitiveAvailable {
            content.interruptionLevel = .timeSensitive
        }

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 3, repeats: false)
        let request = UNNotificationRequest(
            identifier: "red_beacon_test_\(UUID().uuidString)",
            content: content,
            trigger: trigger
        )

        do {
            try await notificationCenter.add(request)
        } catch {
            print("[RedBeacon] Failed to send test notification: \(error)")
        }
    }

    /// Open system settings for notifications
    func openNotificationSettings() {
        #if os(iOS)
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
        #endif
    }

    /// Update custom intervals
    func updateCustomIntervals(_ intervals: [Int]) {
        settings.customIntervals = intervals.sorted(by: >)
    }

    /// Get effective intervals based on current preset
    var effectiveIntervals: [Int] {
        if settings.preset == .custom {
            return settings.customIntervals
        }
        return settings.preset.intervals
    }

    // MARK: - Private Methods

    private func saveSettings() {
        if let data = try? JSONEncoder().encode(settings) {
            userDefaults.set(data, forKey: settingsKey)
        }
    }

    private func checkTimeSensitiveAvailability() async {
        if #available(iOS 15.0, *) {
            let settings = await notificationCenter.notificationSettings()
            isTimeSensitiveAvailable = settings.timeSensitiveSetting == .enabled
        }
    }
}

// MARK: - Red Beacon Settings View

struct RedBeaconSettingsView: View {

    @StateObject private var viewModel = RedBeaconSettingsViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: RemindersKit.Spacing.xxl) {
                    // Header card
                    headerCard

                    // Main toggle
                    mainToggleSection

                    // Escalation presets
                    if viewModel.settings.isEnabled {
                        escalationPresetsSection

                        // Custom intervals (when custom preset selected)
                        if viewModel.settings.preset == .custom {
                            customIntervalsSection
                        }

                        // Notification settings
                        notificationSettingsSection

                        // Time Sensitive instructions
                        timeSensitiveInstructions

                        // Test notification
                        testNotificationSection
                    }
                }
                .padding(RemindersKit.Spacing.lg)
            }
            .background(RemindersColors.background)
            .navigationTitle("Red Beacon")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(RemindersColors.accentBlue)
                }
            }
        }
        .task {
            await viewModel.checkNotificationStatus()
        }
    }

    // MARK: - Header Card

    private var headerCard: some View {
        VStack(spacing: RemindersKit.Spacing.md) {
            // Beacon icon
            ZStack {
                Circle()
                    .fill(RemindersColors.accentRed.opacity(0.2))
                    .frame(width: 80, height: 80)

                Circle()
                    .fill(RemindersColors.accentRed.opacity(0.4))
                    .frame(width: 60, height: 60)

                Circle()
                    .fill(RemindersColors.accentRed)
                    .frame(width: 40, height: 40)

                Image(systemName: "exclamationmark")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white)
            }

            Text("Red Beacon")
                .font(RemindersTypography.title2)
                .foregroundColor(RemindersColors.textPrimary)

            Text("Escalating reminders for high-priority tasks that need your attention.")
                .font(RemindersTypography.subheadline)
                .foregroundColor(RemindersColors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, RemindersKit.Spacing.lg)
        }
        .padding(.vertical, RemindersKit.Spacing.xl)
    }

    // MARK: - Main Toggle Section

    private var mainToggleSection: some View {
        VStack(spacing: 0) {
            Toggle(isOn: $viewModel.settings.isEnabled) {
                HStack(spacing: RemindersKit.Spacing.md) {
                    Image(systemName: "bell.badge.fill")
                        .font(.system(size: 20))
                        .foregroundColor(RemindersColors.accentRed)
                        .frame(width: 32)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Enable Red Beacon")
                            .font(RemindersTypography.body)
                            .foregroundColor(RemindersColors.textPrimary)

                        Text("Get escalating reminders for beacon-enabled tasks")
                            .font(RemindersTypography.caption1)
                            .foregroundColor(RemindersColors.textSecondary)
                    }
                }
            }
            .tint(RemindersColors.accentRed)
            .padding(RemindersKit.Spacing.lg)
        }
        .background(RemindersColors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: RemindersKit.Radius.lg))
    }

    // MARK: - Escalation Presets Section

    private var escalationPresetsSection: some View {
        VStack(alignment: .leading, spacing: RemindersKit.Spacing.md) {
            Text("ESCALATION INTENSITY")
                .font(RemindersTypography.sectionHeaderUppercase)
                .foregroundColor(RemindersColors.textSecondary)
                .padding(.horizontal, RemindersKit.Spacing.xs)

            VStack(spacing: 0) {
                ForEach(EscalationPreset.allCases) { preset in
                    presetRow(preset)

                    if preset != EscalationPreset.allCases.last {
                        Divider()
                            .background(RemindersColors.separator)
                            .padding(.leading, 56)
                    }
                }
            }
            .background(RemindersColors.backgroundSecondary)
            .clipShape(RoundedRectangle(cornerRadius: RemindersKit.Radius.lg))
        }
    }

    private func presetRow(_ preset: EscalationPreset) -> some View {
        Button {
            viewModel.settings.preset = preset
        } label: {
            HStack(spacing: RemindersKit.Spacing.md) {
                Image(systemName: preset.icon)
                    .font(.system(size: 18))
                    .foregroundColor(preset.color)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(preset.displayName)
                        .font(RemindersTypography.body)
                        .foregroundColor(RemindersColors.textPrimary)

                    Text(preset.description)
                        .font(RemindersTypography.caption1)
                        .foregroundColor(RemindersColors.textSecondary)
                        .lineLimit(2)
                }

                Spacer()

                if viewModel.settings.preset == preset {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(RemindersColors.accentBlue)
                }
            }
            .padding(RemindersKit.Spacing.lg)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Custom Intervals Section

    private var customIntervalsSection: some View {
        VStack(alignment: .leading, spacing: RemindersKit.Spacing.md) {
            Text("CUSTOM INTERVALS")
                .font(RemindersTypography.sectionHeaderUppercase)
                .foregroundColor(RemindersColors.textSecondary)
                .padding(.horizontal, RemindersKit.Spacing.xs)

            VStack(spacing: RemindersKit.Spacing.md) {
                HStack {
                    Text("Remind me before due time:")
                        .font(RemindersTypography.subheadline)
                        .foregroundColor(RemindersColors.textPrimary)

                    Spacer()

                    Button("Edit") {
                        viewModel.showingCustomIntervalsEditor = true
                    }
                    .font(RemindersTypography.subheadlineBold)
                    .foregroundColor(RemindersColors.accentBlue)
                }

                // Display current intervals
                FlowLayout(spacing: RemindersKit.Spacing.sm) {
                    ForEach(viewModel.settings.customIntervals, id: \.self) { interval in
                        IntervalBadge(minutes: interval)
                    }
                }
            }
            .padding(RemindersKit.Spacing.lg)
            .background(RemindersColors.backgroundSecondary)
            .clipShape(RoundedRectangle(cornerRadius: RemindersKit.Radius.lg))
        }
        .sheet(isPresented: $viewModel.showingCustomIntervalsEditor) {
            CustomIntervalsEditorView(
                intervals: viewModel.settings.customIntervals,
                onSave: { newIntervals in
                    viewModel.updateCustomIntervals(newIntervals)
                }
            )
        }
    }

    // MARK: - Notification Settings Section

    private var notificationSettingsSection: some View {
        VStack(alignment: .leading, spacing: RemindersKit.Spacing.md) {
            Text("NOTIFICATION OPTIONS")
                .font(RemindersTypography.sectionHeaderUppercase)
                .foregroundColor(RemindersColors.textSecondary)
                .padding(.horizontal, RemindersKit.Spacing.xs)

            VStack(spacing: 0) {
                // Time Sensitive toggle
                if #available(iOS 15.0, *) {
                    Toggle(isOn: $viewModel.settings.useTimeSensitive) {
                        HStack(spacing: RemindersKit.Spacing.md) {
                            Image(systemName: "clock.badge.exclamationmark")
                                .font(.system(size: 18))
                                .foregroundColor(RemindersColors.accentOrange)
                                .frame(width: 32)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Time Sensitive")
                                    .font(RemindersTypography.body)
                                    .foregroundColor(RemindersColors.textPrimary)

                                Text("Break through Focus and Do Not Disturb")
                                    .font(RemindersTypography.caption1)
                                    .foregroundColor(RemindersColors.textSecondary)
                            }
                        }
                    }
                    .tint(RemindersColors.accentOrange)
                    .padding(RemindersKit.Spacing.lg)

                    Divider()
                        .background(RemindersColors.separator)
                        .padding(.leading, 56)
                }

                // Sound toggle
                Toggle(isOn: $viewModel.settings.includeSound) {
                    HStack(spacing: RemindersKit.Spacing.md) {
                        Image(systemName: "speaker.wave.2.fill")
                            .font(.system(size: 18))
                            .foregroundColor(RemindersColors.accentBlue)
                            .frame(width: 32)

                        Text("Play Sound")
                            .font(RemindersTypography.body)
                            .foregroundColor(RemindersColors.textPrimary)
                    }
                }
                .tint(RemindersColors.accentBlue)
                .padding(RemindersKit.Spacing.lg)

                Divider()
                    .background(RemindersColors.separator)
                    .padding(.leading, 56)

                // Badge toggle
                Toggle(isOn: $viewModel.settings.showBadge) {
                    HStack(spacing: RemindersKit.Spacing.md) {
                        Image(systemName: "app.badge.fill")
                            .font(.system(size: 18))
                            .foregroundColor(RemindersColors.accentRed)
                            .frame(width: 32)

                        Text("Show Badge")
                            .font(RemindersTypography.body)
                            .foregroundColor(RemindersColors.textPrimary)
                    }
                }
                .tint(RemindersColors.accentRed)
                .padding(RemindersKit.Spacing.lg)
            }
            .background(RemindersColors.backgroundSecondary)
            .clipShape(RoundedRectangle(cornerRadius: RemindersKit.Radius.lg))
        }
    }

    // MARK: - Time Sensitive Instructions

    @ViewBuilder
    private var timeSensitiveInstructions: some View {
        if viewModel.settings.useTimeSensitive && !viewModel.isTimeSensitiveAvailable {
            VStack(alignment: .leading, spacing: RemindersKit.Spacing.md) {
                Text("ENABLE TIME SENSITIVE")
                    .font(RemindersTypography.sectionHeaderUppercase)
                    .foregroundColor(RemindersColors.textSecondary)
                    .padding(.horizontal, RemindersKit.Spacing.xs)

                VStack(alignment: .leading, spacing: RemindersKit.Spacing.md) {
                    HStack(alignment: .top, spacing: RemindersKit.Spacing.md) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(RemindersColors.accentOrange)

                        VStack(alignment: .leading, spacing: RemindersKit.Spacing.sm) {
                            Text("Time Sensitive notifications are not enabled")
                                .font(RemindersTypography.bodyBold)
                                .foregroundColor(RemindersColors.textPrimary)

                            Text("To allow Red Beacon notifications to break through Focus mode:")
                                .font(RemindersTypography.subheadline)
                                .foregroundColor(RemindersColors.textSecondary)
                        }
                    }

                    VStack(alignment: .leading, spacing: RemindersKit.Spacing.sm) {
                        instructionStep(1, "Open Settings app")
                        instructionStep(2, "Tap Notifications")
                        instructionStep(3, "Find and tap Tasks")
                        instructionStep(4, "Enable \"Time Sensitive Notifications\"")
                    }
                    .padding(.leading, RemindersKit.Spacing.xl)

                    PrimaryButton("Open Settings", icon: "gear", style: .secondary, size: .small) {
                        viewModel.openNotificationSettings()
                    }
                }
                .padding(RemindersKit.Spacing.lg)
                .background(RemindersColors.accentOrange.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: RemindersKit.Radius.lg))
                .overlay(
                    RoundedRectangle(cornerRadius: RemindersKit.Radius.lg)
                        .stroke(RemindersColors.accentOrange.opacity(0.3), lineWidth: 1)
                )
            }
        }
    }

    private func instructionStep(_ number: Int, _ text: String) -> some View {
        HStack(spacing: RemindersKit.Spacing.sm) {
            Text("\(number).")
                .font(RemindersTypography.subheadlineBold)
                .foregroundColor(RemindersColors.accentBlue)
                .frame(width: 20)

            Text(text)
                .font(RemindersTypography.subheadline)
                .foregroundColor(RemindersColors.textPrimary)
        }
    }

    // MARK: - Test Notification Section

    private var testNotificationSection: some View {
        VStack(alignment: .leading, spacing: RemindersKit.Spacing.md) {
            Text("TEST NOTIFICATION")
                .font(RemindersTypography.sectionHeaderUppercase)
                .foregroundColor(RemindersColors.textSecondary)
                .padding(.horizontal, RemindersKit.Spacing.xs)

            VStack(spacing: RemindersKit.Spacing.md) {
                Text("Send a test notification to see how Red Beacon alerts will appear.")
                    .font(RemindersTypography.subheadline)
                    .foregroundColor(RemindersColors.textSecondary)

                PrimaryButton(
                    "Send Test Notification",
                    icon: "bell.badge",
                    isLoading: viewModel.isSendingTestNotification
                ) {
                    Task {
                        await viewModel.sendTestNotification()
                    }
                }

                if viewModel.notificationAuthStatus != .authorized {
                    HStack {
                        Image(systemName: "exclamationmark.circle")
                            .foregroundColor(RemindersColors.accentOrange)

                        Text("Notification permission required")
                            .font(RemindersTypography.caption1)
                            .foregroundColor(RemindersColors.textSecondary)
                    }
                }
            }
            .padding(RemindersKit.Spacing.lg)
            .background(RemindersColors.backgroundSecondary)
            .clipShape(RoundedRectangle(cornerRadius: RemindersKit.Radius.lg))
        }
    }
}

// MARK: - Interval Badge

struct IntervalBadge: View {
    let minutes: Int

    private var displayText: String {
        if minutes >= 60 {
            let hours = minutes / 60
            let remaining = minutes % 60
            if remaining == 0 {
                return "\(hours)h"
            }
            return "\(hours)h \(remaining)m"
        }
        return "\(minutes)m"
    }

    var body: some View {
        Text(displayText)
            .font(RemindersTypography.caption1Bold)
            .foregroundColor(RemindersColors.accentBlue)
            .padding(.horizontal, RemindersKit.Spacing.sm)
            .padding(.vertical, RemindersKit.Spacing.xxs)
            .background(RemindersColors.accentBlue.opacity(0.15))
            .clipShape(Capsule())
    }
}

// MARK: - Flow Layout

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(in: proposal.width ?? 0, subviews: subviews, spacing: spacing)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(in: bounds.width, subviews: subviews, spacing: spacing)

        for (index, position) in result.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: ProposedViewSize(result.sizes[index])
            )
        }
    }

    struct FlowResult {
        var positions: [CGPoint] = []
        var sizes: [CGSize] = []
        var size: CGSize = .zero

        init(in containerWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var currentX: CGFloat = 0
            var currentY: CGFloat = 0
            var lineHeight: CGFloat = 0
            var maxWidth: CGFloat = 0

            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)

                if currentX + size.width > containerWidth && currentX > 0 {
                    currentX = 0
                    currentY += lineHeight + spacing
                    lineHeight = 0
                }

                positions.append(CGPoint(x: currentX, y: currentY))
                sizes.append(size)

                lineHeight = max(lineHeight, size.height)
                currentX += size.width + spacing
                maxWidth = max(maxWidth, currentX)
            }

            size = CGSize(width: maxWidth, height: currentY + lineHeight)
        }
    }
}

// MARK: - Custom Intervals Editor View

struct CustomIntervalsEditorView: View {

    @Environment(\.dismiss) private var dismiss

    @State private var intervals: [Int]
    @State private var newInterval: String = ""

    let onSave: ([Int]) -> Void

    private let presetIntervals = [5, 10, 15, 30, 60, 120, 240]

    init(intervals: [Int], onSave: @escaping ([Int]) -> Void) {
        _intervals = State(initialValue: intervals)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: RemindersKit.Spacing.xxl) {
                    // Current intervals
                    currentIntervalsSection

                    // Quick add presets
                    quickAddSection

                    // Add custom
                    customAddSection
                }
                .padding(RemindersKit.Spacing.lg)
            }
            .background(RemindersColors.background)
            .navigationTitle("Custom Intervals")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(RemindersColors.textSecondary)
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        onSave(intervals)
                        dismiss()
                    }
                    .font(RemindersTypography.bodyBold)
                    .foregroundColor(RemindersColors.accentBlue)
                }
            }
        }
    }

    private var currentIntervalsSection: some View {
        VStack(alignment: .leading, spacing: RemindersKit.Spacing.md) {
            Text("CURRENT INTERVALS")
                .font(RemindersTypography.sectionHeaderUppercase)
                .foregroundColor(RemindersColors.textSecondary)

            if intervals.isEmpty {
                Text("No intervals configured. Add some below.")
                    .font(RemindersTypography.subheadline)
                    .foregroundColor(RemindersColors.textTertiary)
                    .padding(RemindersKit.Spacing.lg)
                    .frame(maxWidth: .infinity)
                    .background(RemindersColors.backgroundSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: RemindersKit.Radius.lg))
            } else {
                VStack(spacing: 0) {
                    ForEach(intervals.sorted(by: >), id: \.self) { interval in
                        HStack {
                            IntervalBadge(minutes: interval)

                            Spacer()

                            Button {
                                intervals.removeAll { $0 == interval }
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundColor(RemindersColors.accentRed)
                            }
                        }
                        .padding(RemindersKit.Spacing.md)

                        if interval != intervals.sorted(by: >).last {
                            Divider()
                                .background(RemindersColors.separator)
                        }
                    }
                }
                .background(RemindersColors.backgroundSecondary)
                .clipShape(RoundedRectangle(cornerRadius: RemindersKit.Radius.lg))
            }
        }
    }

    private var quickAddSection: some View {
        VStack(alignment: .leading, spacing: RemindersKit.Spacing.md) {
            Text("QUICK ADD")
                .font(RemindersTypography.sectionHeaderUppercase)
                .foregroundColor(RemindersColors.textSecondary)

            FlowLayout(spacing: RemindersKit.Spacing.sm) {
                ForEach(presetIntervals, id: \.self) { interval in
                    Button {
                        if !intervals.contains(interval) {
                            intervals.append(interval)
                        }
                    } label: {
                        HStack(spacing: RemindersKit.Spacing.xxs) {
                            if intervals.contains(interval) {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 10, weight: .bold))
                            } else {
                                Image(systemName: "plus")
                                    .font(.system(size: 10, weight: .bold))
                            }

                            Text(formatInterval(interval))
                        }
                        .font(RemindersTypography.caption1Bold)
                        .foregroundColor(intervals.contains(interval) ? .white : RemindersColors.accentBlue)
                        .padding(.horizontal, RemindersKit.Spacing.sm)
                        .padding(.vertical, RemindersKit.Spacing.xs)
                        .background(intervals.contains(interval) ? RemindersColors.accentBlue : RemindersColors.accentBlue.opacity(0.15))
                        .clipShape(Capsule())
                    }
                }
            }
        }
    }

    private var customAddSection: some View {
        VStack(alignment: .leading, spacing: RemindersKit.Spacing.md) {
            Text("ADD CUSTOM (MINUTES)")
                .font(RemindersTypography.sectionHeaderUppercase)
                .foregroundColor(RemindersColors.textSecondary)

            HStack(spacing: RemindersKit.Spacing.md) {
                TextField("Minutes", text: $newInterval)
                    .keyboardType(.numberPad)
                    .textFieldStyle(.roundedBorder)

                Button("Add") {
                    if let value = Int(newInterval), value > 0, !intervals.contains(value) {
                        intervals.append(value)
                        newInterval = ""
                    }
                }
                .disabled(Int(newInterval) == nil || Int(newInterval)! <= 0)
                .foregroundColor(RemindersColors.accentBlue)
            }
        }
    }

    private func formatInterval(_ minutes: Int) -> String {
        if minutes >= 60 {
            let hours = minutes / 60
            return "\(hours) hour\(hours > 1 ? "s" : "")"
        }
        return "\(minutes) min"
    }
}

// MARK: - Preview

#Preview {
    RedBeaconSettingsView()
}
