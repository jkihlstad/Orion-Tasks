//
//  FeatureFlags.swift
//  TasksApp
//
//  Feature flag management with local defaults, UserDefaults persistence,
//  and remote configuration support
//

import Foundation
import Combine

// MARK: - Feature Flag Keys

/// All available feature flags in the app
enum FeatureFlag: String, CaseIterable, Sendable {
    // AI Features
    case aiSuggestionsEnabled = "ai_suggestions_enabled"
    case aiSmartScheduling = "ai_smart_scheduling"
    case aiPriorityRecommendations = "ai_priority_recommendations"
    case aiNaturalLanguageInput = "ai_natural_language_input"

    // Integration Features
    case calendarSyncEnabled = "calendar_sync_enabled"
    case calendarBidirectionalSync = "calendar_bidirectional_sync"
    case voiceInputEnabled = "voice_input_enabled"
    case voiceTranscription = "voice_transcription"

    // Red Beacon Features
    case redBeaconEnabled = "red_beacon_enabled"
    case redBeaconAutoEscalation = "red_beacon_auto_escalation"
    case redBeaconNotifications = "red_beacon_notifications"

    // Collaborative Features
    case sharedListsEnabled = "shared_lists_enabled"
    case realTimeCollaboration = "realtime_collaboration"
    case commentsEnabled = "comments_enabled"

    // Experimental Features
    case experimentalUI = "experimental_ui"
    case betaFeatures = "beta_features"
    case debugMode = "debug_mode"

    // System Features
    case offlineMode = "offline_mode"
    case backgroundSync = "background_sync"
    case pushNotifications = "push_notifications"
    case widgetsEnabled = "widgets_enabled"

    /// Display name for the feature flag
    var displayName: String {
        switch self {
        case .aiSuggestionsEnabled: return "AI Suggestions"
        case .aiSmartScheduling: return "Smart Scheduling"
        case .aiPriorityRecommendations: return "Priority Recommendations"
        case .aiNaturalLanguageInput: return "Natural Language Input"
        case .calendarSyncEnabled: return "Calendar Sync"
        case .calendarBidirectionalSync: return "Bidirectional Calendar Sync"
        case .voiceInputEnabled: return "Voice Input"
        case .voiceTranscription: return "Voice Transcription"
        case .redBeaconEnabled: return "Red Beacon"
        case .redBeaconAutoEscalation: return "Auto Escalation"
        case .redBeaconNotifications: return "Beacon Notifications"
        case .sharedListsEnabled: return "Shared Lists"
        case .realTimeCollaboration: return "Real-time Collaboration"
        case .commentsEnabled: return "Comments"
        case .experimentalUI: return "Experimental UI"
        case .betaFeatures: return "Beta Features"
        case .debugMode: return "Debug Mode"
        case .offlineMode: return "Offline Mode"
        case .backgroundSync: return "Background Sync"
        case .pushNotifications: return "Push Notifications"
        case .widgetsEnabled: return "Widgets"
        }
    }

    /// Default value for the feature flag
    var defaultValue: Bool {
        switch self {
        // AI features - off by default until user consents
        case .aiSuggestionsEnabled: return false
        case .aiSmartScheduling: return false
        case .aiPriorityRecommendations: return false
        case .aiNaturalLanguageInput: return false

        // Integration features - off by default until user enables
        case .calendarSyncEnabled: return false
        case .calendarBidirectionalSync: return false
        case .voiceInputEnabled: return false
        case .voiceTranscription: return false

        // Red Beacon - enabled by default
        case .redBeaconEnabled: return true
        case .redBeaconAutoEscalation: return false
        case .redBeaconNotifications: return true

        // Collaborative features - off by default
        case .sharedListsEnabled: return false
        case .realTimeCollaboration: return false
        case .commentsEnabled: return false

        // Experimental features - off by default
        case .experimentalUI: return false
        case .betaFeatures: return false
        case .debugMode: false

        // System features - mostly on by default
        case .offlineMode: return true
        case .backgroundSync: return true
        case .pushNotifications: return true
        case .widgetsEnabled: return true
        }
    }

    /// Whether this flag requires consent to be enabled
    var requiresConsent: Bool {
        switch self {
        case .aiSuggestionsEnabled,
             .aiSmartScheduling,
             .aiPriorityRecommendations,
             .aiNaturalLanguageInput:
            return true
        case .voiceInputEnabled, .voiceTranscription:
            return true
        case .calendarSyncEnabled, .calendarBidirectionalSync:
            return true
        default:
            return false
        }
    }

    /// The consent scope required for this flag
    var requiredConsentScope: ConsentScope? {
        switch self {
        case .aiSuggestionsEnabled,
             .aiSmartScheduling,
             .aiPriorityRecommendations,
             .aiNaturalLanguageInput:
            return .ai
        case .voiceInputEnabled, .voiceTranscription:
            return .voice
        case .calendarSyncEnabled, .calendarBidirectionalSync:
            return .calendar
        default:
            return nil
        }
    }
}

// MARK: - Feature Flags Manager

/// Manages feature flags with local storage and remote configuration
@MainActor
final class FeatureFlags: ObservableObject {

    // MARK: - Singleton

    static let shared = FeatureFlags()

    // MARK: - Published Properties

    @Published private(set) var flags: [FeatureFlag: Bool] = [:]
    @Published private(set) var isLoaded: Bool = false
    @Published private(set) var lastRemoteFetch: Date?

    // MARK: - Properties

    private let userDefaults: UserDefaults
    private let userDefaultsPrefix = "feature_flag_"
    private var cancellables = Set<AnyCancellable>()

    /// Remote configuration URL (set during app initialization)
    var remoteConfigURL: URL?

    /// Interval between remote config fetches (default: 1 hour)
    var remoteFetchInterval: TimeInterval = 3600

    // MARK: - Initialization

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        loadLocalFlags()
    }

    // MARK: - Flag Access

    /// Checks if a feature flag is enabled
    func isEnabled(_ flag: FeatureFlag) -> Bool {
        flags[flag] ?? flag.defaultValue
    }

    /// Subscript access for feature flags
    subscript(flag: FeatureFlag) -> Bool {
        get { isEnabled(flag) }
        set { setFlag(flag, enabled: newValue) }
    }

    /// Sets a feature flag value
    func setFlag(_ flag: FeatureFlag, enabled: Bool) {
        flags[flag] = enabled
        saveFlag(flag, enabled: enabled)

        Logger.shared.info(
            "Feature flag '\(flag.displayName)' set to \(enabled)",
            category: .app
        )
    }

    /// Resets a feature flag to its default value
    func resetFlag(_ flag: FeatureFlag) {
        flags[flag] = flag.defaultValue
        userDefaults.removeObject(forKey: userDefaultsPrefix + flag.rawValue)

        Logger.shared.info(
            "Feature flag '\(flag.displayName)' reset to default (\(flag.defaultValue))",
            category: .app
        )
    }

    /// Resets all feature flags to their default values
    func resetAllFlags() {
        for flag in FeatureFlag.allCases {
            flags[flag] = flag.defaultValue
            userDefaults.removeObject(forKey: userDefaultsPrefix + flag.rawValue)
        }

        Logger.shared.info("All feature flags reset to defaults", category: .app)
    }

    // MARK: - Consent Integration

    /// Updates feature flags based on consent preferences
    func updateFromConsent(_ preferences: ConsentPreferences) {
        // Enable/disable AI features based on AI consent
        let aiEnabled = preferences.hasAIConsent && preferences.intelligenceLevel != .none
        setFlag(.aiSuggestionsEnabled, enabled: aiEnabled)
        setFlag(.aiSmartScheduling, enabled: aiEnabled && preferences.intelligenceLevel.level >= 2)
        setFlag(.aiPriorityRecommendations, enabled: aiEnabled)
        setFlag(.aiNaturalLanguageInput, enabled: aiEnabled)

        // Enable/disable voice features based on voice consent
        let voiceEnabled = preferences.hasVoiceConsent
        setFlag(.voiceInputEnabled, enabled: voiceEnabled)
        setFlag(.voiceTranscription, enabled: voiceEnabled)

        // Enable/disable calendar features based on calendar consent
        let calendarEnabled = preferences.hasCalendarConsent
        setFlag(.calendarSyncEnabled, enabled: calendarEnabled)
        setFlag(.calendarBidirectionalSync, enabled: calendarEnabled)

        Logger.shared.logConsent(
            event: "Feature flags updated from consent",
            details: "AI: \(aiEnabled), Voice: \(voiceEnabled), Calendar: \(calendarEnabled)"
        )
    }

    /// Checks if a flag can be enabled based on consent
    func canEnable(_ flag: FeatureFlag, with consent: ConsentPreferences) -> Bool {
        guard let requiredScope = flag.requiredConsentScope else {
            return true
        }
        return consent.isGranted(requiredScope)
    }

    // MARK: - Local Storage

    private func loadLocalFlags() {
        for flag in FeatureFlag.allCases {
            let key = userDefaultsPrefix + flag.rawValue
            if userDefaults.object(forKey: key) != nil {
                flags[flag] = userDefaults.bool(forKey: key)
            } else {
                flags[flag] = flag.defaultValue
            }
        }
        isLoaded = true

        Logger.shared.debug("Loaded \(flags.count) feature flags from local storage", category: .app)
    }

    private func saveFlag(_ flag: FeatureFlag, enabled: Bool) {
        let key = userDefaultsPrefix + flag.rawValue
        userDefaults.set(enabled, forKey: key)
    }

    // MARK: - Remote Configuration

    /// Fetches feature flags from remote configuration
    func fetchRemoteFlags() async {
        guard let url = remoteConfigURL else {
            Logger.shared.debug("No remote config URL set, skipping remote fetch", category: .app)
            return
        }

        // Check if we should fetch (based on interval)
        if let lastFetch = lastRemoteFetch,
           Date().timeIntervalSince(lastFetch) < remoteFetchInterval {
            Logger.shared.debug("Skipping remote fetch, within interval", category: .app)
            return
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)

            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode) else {
                Logger.shared.warning("Remote config fetch failed with status code", category: .app)
                return
            }

            let remoteFlags = try JSONDecoder().decode(RemoteFlagsResponse.self, from: data)
            applyRemoteFlags(remoteFlags)

            lastRemoteFetch = Date()
            Logger.shared.info("Remote feature flags fetched successfully", category: .app)

        } catch {
            Logger.shared.error(error, message: "Failed to fetch remote feature flags", category: .app)
        }
    }

    private func applyRemoteFlags(_ response: RemoteFlagsResponse) {
        for (key, value) in response.flags {
            if let flag = FeatureFlag(rawValue: key) {
                // Only apply remote flag if not overridden locally
                if !response.overrideLocal.contains(key) {
                    flags[flag] = value
                    saveFlag(flag, enabled: value)
                }
            }
        }
    }

    // MARK: - Debugging

    /// Returns all flags as a dictionary for debugging
    func allFlagsAsDictionary() -> [String: Bool] {
        var result: [String: Bool] = [:]
        for flag in FeatureFlag.allCases {
            result[flag.rawValue] = isEnabled(flag)
        }
        return result
    }

    /// Logs all current flag values
    func logAllFlags() {
        Logger.shared.debug("Current feature flags:", category: .app)
        for flag in FeatureFlag.allCases {
            Logger.shared.debug("  \(flag.rawValue): \(isEnabled(flag))", category: .app)
        }
    }
}

// MARK: - Remote Flags Response

/// Response structure for remote feature flag configuration
private struct RemoteFlagsResponse: Codable {
    let flags: [String: Bool]
    let overrideLocal: [String]

    enum CodingKeys: String, CodingKey {
        case flags
        case overrideLocal = "override_local"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        flags = try container.decode([String: Bool].self, forKey: .flags)
        overrideLocal = try container.decodeIfPresent([String].self, forKey: .overrideLocal) ?? []
    }
}

// MARK: - Convenience Extensions

extension FeatureFlags {

    // MARK: - AI Feature Shortcuts

    var aiSuggestionsEnabled: Bool {
        isEnabled(.aiSuggestionsEnabled)
    }

    var aiSmartSchedulingEnabled: Bool {
        isEnabled(.aiSmartScheduling)
    }

    var aiNaturalLanguageEnabled: Bool {
        isEnabled(.aiNaturalLanguageInput)
    }

    // MARK: - Integration Shortcuts

    var calendarSyncEnabled: Bool {
        isEnabled(.calendarSyncEnabled)
    }

    var voiceInputEnabled: Bool {
        isEnabled(.voiceInputEnabled)
    }

    // MARK: - Red Beacon Shortcuts

    var redBeaconEnabled: Bool {
        isEnabled(.redBeaconEnabled)
    }

    var redBeaconAutoEscalationEnabled: Bool {
        isEnabled(.redBeaconAutoEscalation)
    }

    // MARK: - System Shortcuts

    var offlineModeEnabled: Bool {
        isEnabled(.offlineMode)
    }

    var backgroundSyncEnabled: Bool {
        isEnabled(.backgroundSync)
    }

    var debugModeEnabled: Bool {
        isEnabled(.debugMode)
    }
}

// MARK: - SwiftUI Environment

import SwiftUI

private struct FeatureFlagsKey: EnvironmentKey {
    static let defaultValue: FeatureFlags = .shared
}

extension EnvironmentValues {
    var featureFlags: FeatureFlags {
        get { self[FeatureFlagsKey.self] }
        set { self[FeatureFlagsKey.self] = newValue }
    }
}
