//
//  RedBeaconRules.swift
//  TasksApp
//
//  Red Beacon escalation configuration and user preferences
//

import Foundation

// MARK: - Escalation Preset

/// Predefined escalation intensity levels for Red Beacon notifications
enum EscalationPreset: String, Codable, CaseIterable, Identifiable, Sendable {
    case none
    case light
    case moderate
    case aggressive

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none: return "Off"
        case .light: return "Light"
        case .moderate: return "Moderate"
        case .aggressive: return "Aggressive"
        }
    }

    var description: String {
        switch self {
        case .none:
            return "No escalating reminders"
        case .light:
            return "Gentle reminders at due time and 15 minutes after"
        case .moderate:
            return "Reminders at due time, +5 min, +15 min, +60 min"
        case .aggressive:
            return "Persistent reminders until task is completed"
        }
    }

    /// Time intervals (in seconds) after due time to send escalation notifications
    var escalationIntervals: [TimeInterval] {
        switch self {
        case .none:
            return []
        case .light:
            return [0, 15 * 60]  // At due time, +15 min
        case .moderate:
            return [0, 5 * 60, 15 * 60, 60 * 60]  // At due time, +5, +15, +60 min
        case .aggressive:
            return [0, 5 * 60, 15 * 60, 30 * 60, 60 * 60, 120 * 60]  // At due time, +5, +15, +30, +60, +120 min
        }
    }

    /// Whether to use Time Sensitive interruption level
    var usesTimeSensitive: Bool {
        switch self {
        case .none: return false
        case .light: return false
        case .moderate: return true
        case .aggressive: return true
        }
    }

    /// Number of escalation notifications
    var escalationCount: Int {
        escalationIntervals.count
    }

    /// Icon for the preset
    var iconName: String {
        switch self {
        case .none: return "bell.slash"
        case .light: return "bell"
        case .moderate: return "bell.badge"
        case .aggressive: return "bell.badge.fill"
        }
    }
}

// MARK: - Escalation Timing Configuration

/// Custom timing configuration for advanced users
struct EscalationTiming: Codable, Hashable, Sendable {

    /// Intervals in minutes after due time
    var intervalsInMinutes: [Int]

    /// Whether to use Time Sensitive notifications (iOS 15+)
    var useTimeSensitive: Bool

    /// Whether to include sound with notifications
    var includeSound: Bool

    /// Maximum number of escalations before stopping
    var maxEscalations: Int

    /// Default configuration matching moderate preset
    static let `default` = EscalationTiming(
        intervalsInMinutes: [0, 5, 15, 60],
        useTimeSensitive: true,
        includeSound: true,
        maxEscalations: 4
    )

    /// Intervals converted to seconds
    var intervalsInSeconds: [TimeInterval] {
        intervalsInMinutes.map { TimeInterval($0 * 60) }
    }

    /// Creates timing from a preset
    init(from preset: EscalationPreset) {
        self.intervalsInMinutes = preset.escalationIntervals.map { Int($0 / 60) }
        self.useTimeSensitive = preset.usesTimeSensitive
        self.includeSound = true
        self.maxEscalations = preset.escalationCount
    }

    init(
        intervalsInMinutes: [Int],
        useTimeSensitive: Bool,
        includeSound: Bool,
        maxEscalations: Int
    ) {
        self.intervalsInMinutes = intervalsInMinutes
        self.useTimeSensitive = useTimeSensitive
        self.includeSound = includeSound
        self.maxEscalations = maxEscalations
    }
}

// MARK: - Red Beacon Preferences

/// User preferences for Red Beacon notification behavior
final class RedBeaconPreferences: ObservableObject {

    // MARK: - Singleton

    static let shared = RedBeaconPreferences()

    // MARK: - UserDefaults Keys

    private enum Keys {
        static let escalationPreset = "redBeacon.escalationPreset"
        static let customTiming = "redBeacon.customTiming"
        static let isEnabled = "redBeacon.isEnabled"
        static let useTimeSensitive = "redBeacon.useTimeSensitive"
        static let showFocusHints = "redBeacon.showFocusHints"
        static let badgeCountEnabled = "redBeacon.badgeCountEnabled"
        static let soundEnabled = "redBeacon.soundEnabled"
        static let snoozeDefaultMinutes = "redBeacon.snoozeDefaultMinutes"
    }

    // MARK: - Published Properties

    /// Currently selected escalation preset
    @Published var escalationPreset: EscalationPreset {
        didSet {
            savePreset()
        }
    }

    /// Whether Red Beacon notifications are enabled globally
    @Published var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: Keys.isEnabled)
        }
    }

    /// Whether to use Time Sensitive notifications when available
    @Published var useTimeSensitive: Bool {
        didSet {
            UserDefaults.standard.set(useTimeSensitive, forKey: Keys.useTimeSensitive)
        }
    }

    /// Whether to show Focus mode hints to the user
    @Published var showFocusHints: Bool {
        didSet {
            UserDefaults.standard.set(showFocusHints, forKey: Keys.showFocusHints)
        }
    }

    /// Whether to update app badge count with overdue tasks
    @Published var badgeCountEnabled: Bool {
        didSet {
            UserDefaults.standard.set(badgeCountEnabled, forKey: Keys.badgeCountEnabled)
        }
    }

    /// Whether to include sound with notifications
    @Published var soundEnabled: Bool {
        didSet {
            UserDefaults.standard.set(soundEnabled, forKey: Keys.soundEnabled)
        }
    }

    /// Default snooze duration in minutes
    @Published var snoozeDefaultMinutes: Int {
        didSet {
            UserDefaults.standard.set(snoozeDefaultMinutes, forKey: Keys.snoozeDefaultMinutes)
        }
    }

    /// Custom timing configuration (for advanced users)
    @Published var customTiming: EscalationTiming {
        didSet {
            saveCustomTiming()
        }
    }

    // MARK: - Computed Properties

    /// The effective timing configuration based on preset or custom
    var effectiveTiming: EscalationTiming {
        EscalationTiming(from: escalationPreset)
    }

    /// Snooze duration as TimeInterval
    var snoozeDuration: TimeInterval {
        TimeInterval(snoozeDefaultMinutes * 60)
    }

    // MARK: - Initialization

    private init() {
        // Load saved preferences
        let savedPresetRaw = UserDefaults.standard.string(forKey: Keys.escalationPreset)
        self.escalationPreset = EscalationPreset(rawValue: savedPresetRaw ?? "") ?? .moderate

        self.isEnabled = UserDefaults.standard.object(forKey: Keys.isEnabled) as? Bool ?? true
        self.useTimeSensitive = UserDefaults.standard.object(forKey: Keys.useTimeSensitive) as? Bool ?? true
        self.showFocusHints = UserDefaults.standard.object(forKey: Keys.showFocusHints) as? Bool ?? true
        self.badgeCountEnabled = UserDefaults.standard.object(forKey: Keys.badgeCountEnabled) as? Bool ?? true
        self.soundEnabled = UserDefaults.standard.object(forKey: Keys.soundEnabled) as? Bool ?? true
        self.snoozeDefaultMinutes = UserDefaults.standard.object(forKey: Keys.snoozeDefaultMinutes) as? Int ?? 15

        // Load custom timing
        if let data = UserDefaults.standard.data(forKey: Keys.customTiming),
           let timing = try? JSONDecoder().decode(EscalationTiming.self, from: data) {
            self.customTiming = timing
        } else {
            self.customTiming = .default
        }
    }

    // MARK: - Persistence

    private func savePreset() {
        UserDefaults.standard.set(escalationPreset.rawValue, forKey: Keys.escalationPreset)
    }

    private func saveCustomTiming() {
        if let data = try? JSONEncoder().encode(customTiming) {
            UserDefaults.standard.set(data, forKey: Keys.customTiming)
        }
    }

    // MARK: - Convenience Methods

    /// Resets all preferences to defaults
    func resetToDefaults() {
        escalationPreset = .moderate
        isEnabled = true
        useTimeSensitive = true
        showFocusHints = true
        badgeCountEnabled = true
        soundEnabled = true
        snoozeDefaultMinutes = 15
        customTiming = .default
    }

    /// Available snooze options in minutes
    static let snoozeOptions: [Int] = [5, 10, 15, 30, 60]

    /// Snooze option display names
    static func snoozeDisplayName(for minutes: Int) -> String {
        if minutes < 60 {
            return "\(minutes) min"
        } else {
            let hours = minutes / 60
            return hours == 1 ? "1 hour" : "\(hours) hours"
        }
    }
}

// MARK: - Notification Identifier Helpers

extension RedBeaconPreferences {

    /// Generates notification identifier for a task escalation
    static func notificationIdentifier(taskId: String, escalationIndex: Int) -> String {
        "redbeacon.\(taskId).escalation.\(escalationIndex)"
    }

    /// Parses task ID from notification identifier
    static func taskId(from notificationIdentifier: String) -> String? {
        let components = notificationIdentifier.components(separatedBy: ".")
        guard components.count >= 3,
              components[0] == "redbeacon" else {
            return nil
        }
        return components[1]
    }

    /// Checks if identifier is a Red Beacon notification
    static func isRedBeaconNotification(_ identifier: String) -> Bool {
        identifier.hasPrefix("redbeacon.")
    }
}

// MARK: - Escalation Message Generator

extension EscalationPreset {

    /// Generates notification body for a given escalation level
    func notificationBody(for taskTitle: String, escalationIndex: Int) -> String {
        let intervals = escalationIntervals
        guard escalationIndex < intervals.count else {
            return "Task: \(taskTitle)"
        }

        let minutesOverdue = Int(intervals[escalationIndex] / 60)

        switch escalationIndex {
        case 0:
            return "Due now: \(taskTitle)"
        case 1:
            return "\(taskTitle) is \(minutesOverdue) minutes overdue"
        case 2:
            return "Still pending: \(taskTitle) (\(minutesOverdue) min overdue)"
        case 3:
            return "Urgent: \(taskTitle) is \(minutesOverdue) minutes overdue"
        default:
            let hoursOverdue = minutesOverdue / 60
            if hoursOverdue >= 1 {
                return "Task overdue by \(hoursOverdue)+ hour\(hoursOverdue > 1 ? "s" : ""): \(taskTitle)"
            }
            return "Overdue: \(taskTitle)"
        }
    }

    /// Notification title for escalation level
    func notificationTitle(for escalationIndex: Int) -> String {
        switch escalationIndex {
        case 0:
            return "Task Due"
        case 1, 2:
            return "Task Reminder"
        default:
            return "Urgent Reminder"
        }
    }
}
