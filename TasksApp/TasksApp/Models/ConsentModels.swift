//
//  ConsentModels.swift
//  TasksApp
//
//  Domain models for user consent and privacy preferences
//

import Foundation

// MARK: - ConsentScope

/// Defines the different scopes of user consent for data processing
enum ConsentScope: String, Codable, Hashable, CaseIterable, Sendable {
    /// Consent for basic task data sync and storage
    case tasks

    /// Consent for voice input and transcription
    case voice

    /// Consent for calendar integration and data access
    case calendar

    /// Consent for AI-powered features and suggestions
    case ai

    /// Display name for the consent scope
    var displayName: String {
        switch self {
        case .tasks: return "Tasks & Reminders"
        case .voice: return "Voice Input"
        case .calendar: return "Calendar Integration"
        case .ai: return "AI Features"
        }
    }

    /// Description of what this consent scope covers
    var description: String {
        switch self {
        case .tasks:
            return "Store and sync your tasks, lists, and reminders across devices."
        case .voice:
            return "Use voice input to create and manage tasks. Voice data may be processed to improve recognition."
        case .calendar:
            return "Connect with your calendar to import events as tasks and mirror tasks to calendar."
        case .ai:
            return "Use AI-powered features like smart suggestions, natural language processing, and task prioritization."
        }
    }

    /// SF Symbol name for the scope
    var symbolName: String {
        switch self {
        case .tasks: return "checkmark.circle"
        case .voice: return "mic.fill"
        case .calendar: return "calendar"
        case .ai: return "sparkles"
        }
    }

    /// Whether this scope requires explicit opt-in (vs default on)
    var requiresExplicitOptIn: Bool {
        switch self {
        case .tasks: return false  // Required for basic functionality
        case .voice: return true
        case .calendar: return true
        case .ai: return true
        }
    }

    /// Data retention period description
    var retentionDescription: String {
        switch self {
        case .tasks:
            return "Task data is retained until you delete it or your account."
        case .voice:
            return "Voice recordings are processed in real-time and not permanently stored."
        case .calendar:
            return "Calendar data is synced in real-time. Imported events follow task retention."
        case .ai:
            return "AI processing is done in real-time. No personal data is retained for training."
        }
    }
}

// MARK: - IntelligenceLevel

/// Defines the level of AI intelligence/processing the user consents to
enum IntelligenceLevel: String, Codable, Hashable, CaseIterable, Sendable {
    /// No AI features enabled - fully manual operation
    case none

    /// Basic AI features only (on-device processing where possible)
    case basic

    /// Standard AI features with cloud processing
    case standard

    /// Full AI capabilities including personalization
    case full

    /// Display name for the intelligence level
    var displayName: String {
        switch self {
        case .none: return "Off"
        case .basic: return "Basic"
        case .standard: return "Standard"
        case .full: return "Full"
        }
    }

    /// Description of what this level enables
    var description: String {
        switch self {
        case .none:
            return "All AI features are disabled. Tasks are managed manually without suggestions or automation."
        case .basic:
            return "Basic on-device processing for date parsing and simple suggestions. No cloud AI processing."
        case .standard:
            return "Smart suggestions, natural language input, and priority recommendations using cloud AI."
        case .full:
            return "Full AI capabilities including personalized suggestions, pattern learning, and proactive reminders."
        }
    }

    /// Features enabled at this level
    var enabledFeatures: [String] {
        switch self {
        case .none:
            return []
        case .basic:
            return [
                "Natural date parsing",
                "Simple autocomplete",
                "On-device suggestions"
            ]
        case .standard:
            return [
                "Natural date parsing",
                "Smart autocomplete",
                "Priority suggestions",
                "Task categorization",
                "Natural language input"
            ]
        case .full:
            return [
                "Natural date parsing",
                "Smart autocomplete",
                "Priority suggestions",
                "Task categorization",
                "Natural language input",
                "Personalized suggestions",
                "Pattern learning",
                "Proactive reminders",
                "Smart scheduling"
            ]
        }
    }

    /// Whether cloud processing is used
    var usesCloudProcessing: Bool {
        switch self {
        case .none, .basic: return false
        case .standard, .full: return true
        }
    }

    /// Numeric value for comparison
    var level: Int {
        switch self {
        case .none: return 0
        case .basic: return 1
        case .standard: return 2
        case .full: return 3
        }
    }
}

// MARK: - ScopeConsent

/// Individual consent status for a specific scope
struct ScopeConsent: Codable, Hashable, Sendable {
    /// The scope this consent applies to
    let scope: ConsentScope

    /// Whether consent is granted
    var isGranted: Bool

    /// When consent was last updated
    var updatedAt: Date

    /// Optional reason/note for the consent status
    var reason: String?

    /// Creates a new scope consent
    init(scope: ConsentScope, isGranted: Bool, updatedAt: Date = Date(), reason: String? = nil) {
        self.scope = scope
        self.isGranted = isGranted
        self.updatedAt = updatedAt
        self.reason = reason
    }

    /// Toggles the consent status
    mutating func toggle() {
        isGranted.toggle()
        updatedAt = Date()
    }

    /// Grants consent
    mutating func grant() {
        isGranted = true
        updatedAt = Date()
    }

    /// Revokes consent
    mutating func revoke(reason: String? = nil) {
        isGranted = false
        self.reason = reason
        updatedAt = Date()
    }
}

// MARK: - ConsentPreferences

/// Complete consent preferences for a user
struct ConsentPreferences: Codable, Hashable, Sendable {

    // MARK: - Properties

    /// Consent status for each scope
    var scopeConsents: [ConsentScope: ScopeConsent]

    /// Selected AI intelligence level
    var intelligenceLevel: IntelligenceLevel

    /// Whether the user has completed the initial consent flow
    var hasCompletedOnboarding: Bool

    /// When preferences were last updated
    var updatedAt: Date

    /// User's preferred data region (for GDPR compliance)
    var preferredDataRegion: String?

    /// Whether to show consent reminders
    var showConsentReminders: Bool

    // MARK: - Initialization

    /// Creates default consent preferences (all optional scopes off)
    init(
        scopeConsents: [ConsentScope: ScopeConsent]? = nil,
        intelligenceLevel: IntelligenceLevel = .none,
        hasCompletedOnboarding: Bool = false,
        updatedAt: Date = Date(),
        preferredDataRegion: String? = nil,
        showConsentReminders: Bool = true
    ) {
        if let consents = scopeConsents {
            self.scopeConsents = consents
        } else {
            // Default consents
            self.scopeConsents = [
                .tasks: ScopeConsent(scope: .tasks, isGranted: true),
                .voice: ScopeConsent(scope: .voice, isGranted: false),
                .calendar: ScopeConsent(scope: .calendar, isGranted: false),
                .ai: ScopeConsent(scope: .ai, isGranted: false)
            ]
        }
        self.intelligenceLevel = intelligenceLevel
        self.hasCompletedOnboarding = hasCompletedOnboarding
        self.updatedAt = updatedAt
        self.preferredDataRegion = preferredDataRegion
        self.showConsentReminders = showConsentReminders
    }

    // MARK: - Computed Properties

    /// Whether tasks consent is granted (required for app functionality)
    var hasTasksConsent: Bool {
        scopeConsents[.tasks]?.isGranted ?? true
    }

    /// Whether voice consent is granted
    var hasVoiceConsent: Bool {
        scopeConsents[.voice]?.isGranted ?? false
    }

    /// Whether calendar consent is granted
    var hasCalendarConsent: Bool {
        scopeConsents[.calendar]?.isGranted ?? false
    }

    /// Whether AI consent is granted
    var hasAIConsent: Bool {
        scopeConsents[.ai]?.isGranted ?? false
    }

    /// All granted scopes
    var grantedScopes: [ConsentScope] {
        scopeConsents.filter { $0.value.isGranted }.map { $0.key }
    }

    /// All revoked scopes
    var revokedScopes: [ConsentScope] {
        scopeConsents.filter { !$0.value.isGranted }.map { $0.key }
    }

    /// Whether any AI features are enabled
    var hasAnyAIEnabled: Bool {
        hasAIConsent && intelligenceLevel != .none
    }

    // MARK: - Methods

    /// Checks if a specific scope is granted
    func isGranted(_ scope: ConsentScope) -> Bool {
        scopeConsents[scope]?.isGranted ?? false
    }

    /// Updates consent for a specific scope
    mutating func setConsent(for scope: ConsentScope, granted: Bool, reason: String? = nil) {
        if var consent = scopeConsents[scope] {
            if granted {
                consent.grant()
            } else {
                consent.revoke(reason: reason)
            }
            scopeConsents[scope] = consent
        } else {
            scopeConsents[scope] = ScopeConsent(scope: scope, isGranted: granted, reason: reason)
        }
        updatedAt = Date()

        // If AI consent is revoked, reset intelligence level
        if scope == .ai && !granted {
            intelligenceLevel = .none
        }
    }

    /// Sets the intelligence level
    mutating func setIntelligenceLevel(_ level: IntelligenceLevel) {
        intelligenceLevel = level
        updatedAt = Date()

        // If setting any AI level, ensure AI consent is granted
        if level != .none {
            setConsent(for: .ai, granted: true)
        }
    }

    /// Marks onboarding as complete
    mutating func completeOnboarding() {
        hasCompletedOnboarding = true
        updatedAt = Date()
    }

    /// Revokes all optional consents
    mutating func revokeAllOptionalConsents() {
        for scope in ConsentScope.allCases where scope.requiresExplicitOptIn {
            setConsent(for: scope, granted: false, reason: "User revoked all consents")
        }
        intelligenceLevel = .none
        updatedAt = Date()
    }
}

// MARK: - ConsentSnapshot

/// Immutable snapshot of consent preferences at a point in time
struct ConsentSnapshot: Identifiable, Codable, Hashable, Sendable {

    // MARK: - Properties

    /// Unique identifier for this snapshot
    let id: String

    /// The consent preferences at this point in time
    let preferences: ConsentPreferences

    /// When this snapshot was created
    let createdAt: Date

    /// User ID this snapshot belongs to
    let userId: String

    /// Device ID that created this snapshot
    let deviceId: String

    /// App version at time of snapshot
    let appVersion: String

    /// Reason for creating this snapshot
    let reason: SnapshotReason

    /// Hash of the preferences for verification
    let preferencesHash: String

    // MARK: - SnapshotReason

    /// Reasons for creating a consent snapshot
    enum SnapshotReason: String, Codable, Hashable, Sendable {
        /// Initial consent during onboarding
        case initialConsent

        /// User updated their preferences
        case userUpdate

        /// Scheduled periodic snapshot
        case periodic

        /// Before a major operation requiring consent verification
        case preOperation

        /// App update that affects consent
        case appUpdate

        /// Regulatory compliance requirement
        case compliance
    }

    // MARK: - Initialization

    init(
        id: String = UUID().uuidString,
        preferences: ConsentPreferences,
        createdAt: Date = Date(),
        userId: String,
        deviceId: String,
        appVersion: String,
        reason: SnapshotReason
    ) {
        self.id = id
        self.preferences = preferences
        self.createdAt = createdAt
        self.userId = userId
        self.deviceId = deviceId
        self.appVersion = appVersion
        self.reason = reason

        // Create a simple hash of the preferences
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        if let data = try? encoder.encode(preferences),
           let string = String(data: data, encoding: .utf8) {
            self.preferencesHash = String(string.hashValue)
        } else {
            self.preferencesHash = UUID().uuidString
        }
    }

    // MARK: - Computed Properties

    /// Summary of granted consents at this snapshot
    var grantedScopesSummary: String {
        preferences.grantedScopes.map { $0.displayName }.joined(separator: ", ")
    }

    /// Whether this snapshot represents full consent
    var hasFullConsent: Bool {
        ConsentScope.allCases.allSatisfy { preferences.isGranted($0) }
    }

    /// Whether this snapshot represents minimal consent
    var hasMinimalConsent: Bool {
        preferences.grantedScopes.count == 1 && preferences.hasTasksConsent
    }
}

// MARK: - ConsentChange

/// Represents a change in consent preferences
struct ConsentChange: Codable, Hashable, Sendable {
    /// The scope that changed
    let scope: ConsentScope?

    /// Previous value (nil if new)
    let previousValue: Bool?

    /// New value
    let newValue: Bool

    /// When the change occurred
    let changedAt: Date

    /// Whether this was a grant (true) or revoke (false)
    var isGrant: Bool {
        newValue && !(previousValue ?? false)
    }

    /// Whether this was a revocation
    var isRevoke: Bool {
        !newValue && (previousValue ?? true)
    }

    /// Creates a consent change for a scope
    static func forScope(_ scope: ConsentScope, from previous: Bool?, to new: Bool) -> ConsentChange {
        ConsentChange(scope: scope, previousValue: previous, newValue: new, changedAt: Date())
    }

    /// Creates a consent change for intelligence level
    static func forIntelligenceLevel(from previous: IntelligenceLevel?, to new: IntelligenceLevel) -> ConsentChange {
        ConsentChange(
            scope: nil,
            previousValue: previous.map { $0 != .none },
            newValue: new != .none,
            changedAt: Date()
        )
    }
}

// MARK: - Sample Data

extension ConsentPreferences {
    /// Default preferences for new users
    static let `default` = ConsentPreferences()

    /// Full consent for testing
    static let fullConsent: ConsentPreferences = {
        var prefs = ConsentPreferences()
        for scope in ConsentScope.allCases {
            prefs.setConsent(for: scope, granted: true)
        }
        prefs.intelligenceLevel = .full
        prefs.hasCompletedOnboarding = true
        return prefs
    }()

    /// Minimal consent for testing
    static let minimalConsent: ConsentPreferences = {
        var prefs = ConsentPreferences()
        prefs.hasCompletedOnboarding = true
        return prefs
    }()
}

extension ConsentSnapshot {
    /// Sample snapshot for previews and testing
    static let sample = ConsentSnapshot(
        preferences: .fullConsent,
        userId: "user-123",
        deviceId: "device-456",
        appVersion: "1.0.0",
        reason: .initialConsent
    )
}
