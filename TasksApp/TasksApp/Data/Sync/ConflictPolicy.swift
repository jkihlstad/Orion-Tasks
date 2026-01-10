//
//  ConflictPolicy.swift
//  TasksApp
//
//  Conflict resolution policies for offline-first sync
//  Implements last-write-wins per field and various merge strategies
//

import Foundation

// MARK: - Conflict Type

/// Types of conflicts that can occur during sync
enum ConflictType: String, Codable, Sendable {
    /// Both client and server modified the same field
    case fieldConflict = "field_conflict"

    /// Entity was deleted on one side but modified on the other
    case deleteModifyConflict = "delete_modify_conflict"

    /// Entity was created with the same ID on both sides
    case duplicateCreate = "duplicate_create"

    /// Parent entity was deleted while child was modified
    case orphanedChild = "orphaned_child"

    /// Move to different lists on client and server
    case moveConflict = "move_conflict"

    /// Reorder conflict within the same list
    case reorderConflict = "reorder_conflict"
}

// MARK: - Conflict Resolution Strategy

/// Strategies for resolving conflicts
enum ConflictResolutionStrategy: String, Codable, Sendable {
    /// Server version always wins
    case serverWins = "server_wins"

    /// Client version always wins
    case clientWins = "client_wins"

    /// Most recent modification wins
    case lastWriteWins = "last_write_wins"

    /// Merge changes field by field
    case fieldLevelMerge = "field_level_merge"

    /// Keep both versions (create duplicate)
    case keepBoth = "keep_both"

    /// Require manual resolution
    case manual = "manual"
}

// MARK: - Field Conflict Info

/// Information about a conflict on a specific field
struct FieldConflict: Codable, Sendable {
    /// The field that has a conflict
    let fieldName: String

    /// The local value
    let localValue: AnyCodableValue?

    /// The server value
    let serverValue: AnyCodableValue?

    /// When the local value was set
    let localTimestamp: Date

    /// When the server value was set
    let serverTimestamp: Date

    /// The resolved value (after applying policy)
    var resolvedValue: AnyCodableValue?

    /// Which side won the resolution
    var winner: ConflictWinner?

    enum ConflictWinner: String, Codable, Sendable {
        case local
        case server
        case merged
    }
}

// MARK: - Conflict Record

/// A record of a detected conflict for logging/debugging
struct ConflictRecord: Identifiable, Codable, Sendable {
    let id: String
    let entityType: String
    let entityId: String
    let conflictType: ConflictType
    let fieldConflicts: [FieldConflict]
    let detectedAt: Date
    let resolvedAt: Date?
    let resolutionStrategy: ConflictResolutionStrategy
    let wasAutoResolved: Bool

    init(
        id: String = UUID().uuidString,
        entityType: String,
        entityId: String,
        conflictType: ConflictType,
        fieldConflicts: [FieldConflict] = [],
        detectedAt: Date = Date(),
        resolvedAt: Date? = nil,
        resolutionStrategy: ConflictResolutionStrategy,
        wasAutoResolved: Bool
    ) {
        self.id = id
        self.entityType = entityType
        self.entityId = entityId
        self.conflictType = conflictType
        self.fieldConflicts = fieldConflicts
        self.detectedAt = detectedAt
        self.resolvedAt = resolvedAt
        self.resolutionStrategy = resolutionStrategy
        self.wasAutoResolved = wasAutoResolved
    }
}

// MARK: - Sync Version

/// Version information for an entity used in conflict detection
struct SyncVersion: Codable, Equatable, Sendable {
    /// Server-assigned version number
    let serverVersion: Int64

    /// Last modification timestamp
    let modifiedAt: Date

    /// Device ID that made the modification
    let modifiedBy: String

    /// Hash of the content for change detection
    let contentHash: String?

    /// Field-level timestamps for granular conflict detection
    let fieldTimestamps: [String: Date]?

    /// Creates a new sync version
    init(
        serverVersion: Int64,
        modifiedAt: Date,
        modifiedBy: String,
        contentHash: String? = nil,
        fieldTimestamps: [String: Date]? = nil
    ) {
        self.serverVersion = serverVersion
        self.modifiedAt = modifiedAt
        self.modifiedBy = modifiedBy
        self.contentHash = contentHash
        self.fieldTimestamps = fieldTimestamps
    }

    /// Checks if this version is newer than another
    func isNewerThan(_ other: SyncVersion) -> Bool {
        if serverVersion != other.serverVersion {
            return serverVersion > other.serverVersion
        }
        return modifiedAt > other.modifiedAt
    }
}

// MARK: - Conflict Policy

/// Policy configuration for conflict resolution
struct ConflictPolicy: Sendable {

    // MARK: - Properties

    /// Default strategy for most conflicts
    let defaultStrategy: ConflictResolutionStrategy

    /// Per-entity type overrides
    let entityStrategies: [String: ConflictResolutionStrategy]

    /// Per-field overrides (key format: "entityType.fieldName")
    let fieldStrategies: [String: ConflictResolutionStrategy]

    /// Fields that should always use server value
    let serverAuthorityFields: Set<String>

    /// Fields that should always use client value
    let clientAuthorityFields: Set<String>

    /// Whether to log conflicts for debugging
    let logConflicts: Bool

    /// Whether to keep conflict history
    let keepConflictHistory: Bool

    // MARK: - Initialization

    init(
        defaultStrategy: ConflictResolutionStrategy = .fieldLevelMerge,
        entityStrategies: [String: ConflictResolutionStrategy] = [:],
        fieldStrategies: [String: ConflictResolutionStrategy] = [:],
        serverAuthorityFields: Set<String> = [],
        clientAuthorityFields: Set<String> = [],
        logConflicts: Bool = true,
        keepConflictHistory: Bool = true
    ) {
        self.defaultStrategy = defaultStrategy
        self.entityStrategies = entityStrategies
        self.fieldStrategies = fieldStrategies
        self.serverAuthorityFields = serverAuthorityFields
        self.clientAuthorityFields = clientAuthorityFields
        self.logConflicts = logConflicts
        self.keepConflictHistory = keepConflictHistory
    }

    // MARK: - Default Policies

    /// Standard policy for Tasks app
    static let standard = ConflictPolicy(
        defaultStrategy: .fieldLevelMerge,
        entityStrategies: [
            "task": .fieldLevelMerge,
            "taskList": .fieldLevelMerge,
            "tag": .lastWriteWins
        ],
        fieldStrategies: [
            "task.serverVersion": .serverWins,
            "task.syncStatus": .serverWins,
            "taskList.serverVersion": .serverWins,
            "task.isCompleted": .lastWriteWins,
            "task.completedAt": .lastWriteWins
        ],
        serverAuthorityFields: ["serverVersion", "syncStatus", "lastSyncedAt"],
        clientAuthorityFields: ["localSequence"],
        logConflicts: true,
        keepConflictHistory: true
    )

    /// Aggressive client-first policy (for testing)
    static let clientFirst = ConflictPolicy(
        defaultStrategy: .clientWins,
        logConflicts: true,
        keepConflictHistory: true
    )

    /// Conservative server-first policy
    static let serverFirst = ConflictPolicy(
        defaultStrategy: .serverWins,
        logConflicts: true,
        keepConflictHistory: true
    )

    // MARK: - Strategy Resolution

    /// Gets the resolution strategy for a specific entity and field
    func strategyFor(entityType: String, fieldName: String? = nil) -> ConflictResolutionStrategy {
        // Check field-specific strategy first
        if let field = fieldName {
            let fieldKey = "\(entityType).\(field)"
            if let strategy = fieldStrategies[fieldKey] {
                return strategy
            }

            // Check server/client authority fields
            if serverAuthorityFields.contains(field) {
                return .serverWins
            }
            if clientAuthorityFields.contains(field) {
                return .clientWins
            }
        }

        // Check entity-level strategy
        if let strategy = entityStrategies[entityType] {
            return strategy
        }

        // Fall back to default
        return defaultStrategy
    }
}

// MARK: - Conflict Resolver

/// Resolves conflicts between local and server versions
final class ConflictResolver: @unchecked Sendable {

    // MARK: - Properties

    private let policy: ConflictPolicy
    private let deviceId: String
    private var conflictHistory: [ConflictRecord] = []
    private let historyLock = NSLock()

    // MARK: - Initialization

    init(policy: ConflictPolicy = .standard, deviceId: String) {
        self.policy = policy
        self.deviceId = deviceId
    }

    // MARK: - Conflict Detection

    /// Detects conflicts between local and server versions
    func detectConflicts<T: Codable>(
        entityType: String,
        entityId: String,
        local: T,
        server: T,
        localVersion: SyncVersion,
        serverVersion: SyncVersion
    ) -> [FieldConflict] {
        var conflicts: [FieldConflict] = []

        // Convert to dictionaries for comparison
        guard let localDict = try? encodeToDictionary(local),
              let serverDict = try? encodeToDictionary(server) else {
            return conflicts
        }

        // Find all modified fields
        let allKeys = Set(localDict.keys).union(Set(serverDict.keys))

        for key in allKeys {
            let localValue = localDict[key]
            let serverValue = serverDict[key]

            // Skip if values are equal
            if areValuesEqual(localValue, serverValue) {
                continue
            }

            // Determine timestamps for this field
            let localTimestamp = localVersion.fieldTimestamps?[key] ?? localVersion.modifiedAt
            let serverTimestamp = serverVersion.fieldTimestamps?[key] ?? serverVersion.modifiedAt

            // Both sides modified this field - it's a conflict
            if localValue != nil && serverValue != nil {
                let conflict = FieldConflict(
                    fieldName: key,
                    localValue: localValue.flatMap { AnyCodableValue($0) },
                    serverValue: serverValue.flatMap { AnyCodableValue($0) },
                    localTimestamp: localTimestamp,
                    serverTimestamp: serverTimestamp,
                    resolvedValue: nil,
                    winner: nil
                )
                conflicts.append(conflict)
            }
        }

        return conflicts
    }

    // MARK: - Conflict Resolution

    /// Resolves a field conflict using the appropriate strategy
    func resolveFieldConflict(
        _ conflict: FieldConflict,
        entityType: String
    ) -> FieldConflict {
        var resolved = conflict
        let strategy = policy.strategyFor(entityType: entityType, fieldName: conflict.fieldName)

        switch strategy {
        case .serverWins:
            resolved.resolvedValue = conflict.serverValue
            resolved.winner = .server

        case .clientWins:
            resolved.resolvedValue = conflict.localValue
            resolved.winner = .local

        case .lastWriteWins:
            if conflict.localTimestamp > conflict.serverTimestamp {
                resolved.resolvedValue = conflict.localValue
                resolved.winner = .local
            } else {
                resolved.resolvedValue = conflict.serverValue
                resolved.winner = .server
            }

        case .fieldLevelMerge:
            // For field-level merge, use last-write-wins per field
            if conflict.localTimestamp > conflict.serverTimestamp {
                resolved.resolvedValue = conflict.localValue
                resolved.winner = .local
            } else {
                resolved.resolvedValue = conflict.serverValue
                resolved.winner = .server
            }

        case .keepBoth, .manual:
            // These require special handling - default to server for automatic resolution
            resolved.resolvedValue = conflict.serverValue
            resolved.winner = .server
        }

        return resolved
    }

    /// Resolves all conflicts for an entity
    func resolveEntity<T: Codable>(
        entityType: String,
        entityId: String,
        local: T,
        server: T,
        localVersion: SyncVersion,
        serverVersion: SyncVersion
    ) throws -> (resolved: T, conflicts: [FieldConflict]) {
        // Detect conflicts
        var conflicts = detectConflicts(
            entityType: entityType,
            entityId: entityId,
            local: local,
            server: server,
            localVersion: localVersion,
            serverVersion: serverVersion
        )

        // Resolve each conflict
        conflicts = conflicts.map { resolveFieldConflict($0, entityType: entityType) }

        // Build the resolved entity
        var resolvedDict = try encodeToDictionary(server) ?? [:]

        for conflict in conflicts {
            if let value = conflict.resolvedValue?.value {
                resolvedDict[conflict.fieldName] = value
            }
        }

        // Decode back to entity type
        let resolved = try decodeFromDictionary(resolvedDict, as: T.self)

        // Record conflict if needed
        if policy.keepConflictHistory && !conflicts.isEmpty {
            let record = ConflictRecord(
                entityType: entityType,
                entityId: entityId,
                conflictType: .fieldConflict,
                fieldConflicts: conflicts,
                resolvedAt: Date(),
                resolutionStrategy: policy.strategyFor(entityType: entityType),
                wasAutoResolved: true
            )
            addToHistory(record)
        }

        return (resolved, conflicts)
    }

    // MARK: - Delete/Modify Conflict Resolution

    /// Resolves a delete-modify conflict
    func resolveDeleteModifyConflict(
        entityType: String,
        entityId: String,
        wasDeletedOnServer: Bool,
        localModifiedAt: Date,
        serverDeletedAt: Date
    ) -> DeleteModifyResolution {
        let strategy = policy.strategyFor(entityType: entityType)

        switch strategy {
        case .serverWins:
            return wasDeletedOnServer ? .acceptDelete : .keepModified

        case .clientWins:
            return wasDeletedOnServer ? .keepModified : .acceptDelete

        case .lastWriteWins, .fieldLevelMerge:
            if wasDeletedOnServer {
                // Server deleted, client modified
                return localModifiedAt > serverDeletedAt ? .keepModified : .acceptDelete
            } else {
                // Client deleted, server modified
                return serverDeletedAt > localModifiedAt ? .keepModified : .acceptDelete
            }

        case .keepBoth:
            return .keepModified

        case .manual:
            return .requireManualResolution
        }
    }

    // MARK: - History Management

    /// Gets the conflict history
    func getConflictHistory() -> [ConflictRecord] {
        historyLock.lock()
        defer { historyLock.unlock() }
        return conflictHistory
    }

    /// Clears the conflict history
    func clearHistory() {
        historyLock.lock()
        defer { historyLock.unlock() }
        conflictHistory.removeAll()
    }

    /// Gets conflicts for a specific entity
    func getConflictsFor(entityId: String) -> [ConflictRecord] {
        historyLock.lock()
        defer { historyLock.unlock() }
        return conflictHistory.filter { $0.entityId == entityId }
    }

    // MARK: - Private Methods

    private func addToHistory(_ record: ConflictRecord) {
        historyLock.lock()
        defer { historyLock.unlock() }
        conflictHistory.append(record)

        // Keep history bounded
        if conflictHistory.count > 1000 {
            conflictHistory.removeFirst(100)
        }
    }

    private func encodeToDictionary<T: Encodable>(_ value: T) throws -> [String: Any]? {
        let data = try JSONEncoder().encode(value)
        return try JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private func decodeFromDictionary<T: Decodable>(_ dict: [String: Any], as type: T.Type) throws -> T {
        let data = try JSONSerialization.data(withJSONObject: dict)
        return try JSONDecoder().decode(type, from: data)
    }

    private func areValuesEqual(_ lhs: Any?, _ rhs: Any?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil):
            return true
        case (nil, _), (_, nil):
            return false
        case let (l as String, r as String):
            return l == r
        case let (l as Int, r as Int):
            return l == r
        case let (l as Double, r as Double):
            return l == r
        case let (l as Bool, r as Bool):
            return l == r
        case let (l as Date, r as Date):
            return l == r
        case let (l as [Any], r as [Any]):
            guard l.count == r.count else { return false }
            for (lItem, rItem) in zip(l, r) {
                if !areValuesEqual(lItem, rItem) { return false }
            }
            return true
        case let (l as [String: Any], r as [String: Any]):
            guard l.count == r.count else { return false }
            for (key, lValue) in l {
                guard let rValue = r[key], areValuesEqual(lValue, rValue) else { return false }
            }
            return true
        default:
            // Fall back to string comparison
            return String(describing: lhs) == String(describing: rhs)
        }
    }
}

// MARK: - Delete/Modify Resolution

/// Result of resolving a delete-modify conflict
enum DeleteModifyResolution {
    /// Accept the deletion
    case acceptDelete

    /// Keep the modified version
    case keepModified

    /// Requires manual resolution
    case requireManualResolution
}

// MARK: - AnyCodableValue

/// Type-erased codable value for storing arbitrary values in conflicts
struct AnyCodableValue: Codable, Sendable {
    let value: Any

    init(_ value: Any) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let intValue = try? container.decode(Int.self) {
            value = intValue
        } else if let doubleValue = try? container.decode(Double.self) {
            value = doubleValue
        } else if let boolValue = try? container.decode(Bool.self) {
            value = boolValue
        } else if let stringValue = try? container.decode(String.self) {
            value = stringValue
        } else if let arrayValue = try? container.decode([AnyCodableValue].self) {
            value = arrayValue.map { $0.value }
        } else if let dictValue = try? container.decode([String: AnyCodableValue].self) {
            value = dictValue.mapValues { $0.value }
        } else if container.decodeNil() {
            value = NSNull()
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Cannot decode value"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch value {
        case let intValue as Int:
            try container.encode(intValue)
        case let doubleValue as Double:
            try container.encode(doubleValue)
        case let boolValue as Bool:
            try container.encode(boolValue)
        case let stringValue as String:
            try container.encode(stringValue)
        case let arrayValue as [Any]:
            try container.encode(arrayValue.map { AnyCodableValue($0) })
        case let dictValue as [String: Any]:
            try container.encode(dictValue.mapValues { AnyCodableValue($0) })
        case is NSNull:
            try container.encodeNil()
        default:
            try container.encode(String(describing: value))
        }
    }
}

// MARK: - Merge Helpers

extension ConflictResolver {

    /// Merges two arrays, preferring items from the newer version
    func mergeArrays<T: Identifiable & Codable>(
        local: [T],
        server: [T],
        localTimestamp: Date,
        serverTimestamp: Date
    ) -> [T] where T.ID == String {
        var merged: [String: T] = [:]

        // Add all server items
        for item in server {
            merged[item.id] = item
        }

        // Merge local items based on timestamp
        for item in local {
            if let existing = merged[item.id] {
                // Both have this item - use timestamp to decide
                if localTimestamp > serverTimestamp {
                    merged[item.id] = item
                }
                // else keep server version (already in merged)
            } else {
                // Only in local - add it
                merged[item.id] = item
            }
        }

        return Array(merged.values)
    }

    /// Merges two sets of IDs
    func mergeIdSets(
        local: Set<String>,
        server: Set<String>,
        localAdded: Set<String>,
        localRemoved: Set<String>,
        serverAdded: Set<String>,
        serverRemoved: Set<String>
    ) -> Set<String> {
        var result = server

        // Add items that were added locally (unless removed on server)
        for id in localAdded {
            if !serverRemoved.contains(id) {
                result.insert(id)
            }
        }

        // Remove items that were removed locally (unless added on server)
        for id in localRemoved {
            if !serverAdded.contains(id) {
                result.remove(id)
            }
        }

        return result
    }
}
