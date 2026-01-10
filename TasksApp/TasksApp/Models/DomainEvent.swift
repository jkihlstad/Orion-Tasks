//
//  DomainEvent.swift
//  TasksApp
//
//  Append-only event model for event sourcing and sync
//

import Foundation

// MARK: - DomainEventType

/// All possible event types in the Tasks domain
enum DomainEventType: String, Codable, Hashable, Sendable, CaseIterable {

    // MARK: - List Events

    /// A new list was created
    case tasksListCreated = "tasks.list.created"

    /// A list was updated (renamed, color changed, etc.)
    case tasksListUpdated = "tasks.list.updated"

    /// A list was deleted
    case tasksListDeleted = "tasks.list.deleted"

    /// Lists were reordered
    case tasksListReordered = "tasks.list.reordered"

    // MARK: - Task Events

    /// A new task was created
    case tasksTaskCreated = "tasks.task.created"

    /// A task was updated
    case tasksTaskUpdated = "tasks.task.updated"

    /// A task was deleted
    case tasksTaskDeleted = "tasks.task.deleted"

    /// A task was completed
    case tasksTaskCompleted = "tasks.task.completed"

    /// A task was uncompleted
    case tasksTaskUncompleted = "tasks.task.uncompleted"

    /// A task was moved to a different list
    case tasksTaskMoved = "tasks.task.moved"

    /// Tasks were reordered within a list
    case tasksTaskReordered = "tasks.task.reordered"

    /// A task was flagged
    case tasksTaskFlagged = "tasks.task.flagged"

    /// A task was unflagged
    case tasksTaskUnflagged = "tasks.task.unflagged"

    // MARK: - Subtask Events

    /// A subtask was added to a task
    case tasksSubtaskAdded = "tasks.subtask.added"

    /// A subtask was removed from a task
    case tasksSubtaskRemoved = "tasks.subtask.removed"

    // MARK: - Tag Events

    /// A new tag was created
    case tasksTagCreated = "tasks.tag.created"

    /// A tag was updated
    case tasksTagUpdated = "tasks.tag.updated"

    /// A tag was deleted
    case tasksTagDeleted = "tasks.tag.deleted"

    /// A tag was added to a task
    case tasksTagAssigned = "tasks.tag.assigned"

    /// A tag was removed from a task
    case tasksTagUnassigned = "tasks.tag.unassigned"

    // MARK: - Attachment Events

    /// An attachment was added to a task
    case tasksAttachmentAdded = "tasks.attachment.added"

    /// An attachment was removed from a task
    case tasksAttachmentRemoved = "tasks.attachment.removed"

    /// An attachment upload status changed
    case tasksAttachmentStatusChanged = "tasks.attachment.status_changed"

    // MARK: - Calendar Integration Events

    /// A task was mirrored to calendar
    case tasksCalendarMirrored = "tasks.calendar.mirrored"

    /// A task was unmirrored from calendar
    case tasksCalendarUnmirrored = "tasks.calendar.unmirrored"

    /// A task was imported from calendar
    case tasksCalendarImported = "tasks.calendar.imported"

    /// Calendar sync was triggered
    case tasksCalendarSynced = "tasks.calendar.synced"

    // MARK: - Consent Events

    /// Consent preferences were updated
    case tasksConsentUpdated = "tasks.consent.updated"

    /// A consent snapshot was created
    case tasksConsentSnapshotCreated = "tasks.consent.snapshot_created"

    // MARK: - Bulk Operations

    /// Multiple tasks were completed
    case tasksBulkCompleted = "tasks.bulk.completed"

    /// Multiple tasks were deleted
    case tasksBulkDeleted = "tasks.bulk.deleted"

    /// Multiple tasks were moved
    case tasksBulkMoved = "tasks.bulk.moved"

    // MARK: - Computed Properties

    /// The domain this event belongs to (always "tasks" for this app)
    var domain: String {
        "tasks"
    }

    /// The entity type this event affects
    var entityType: String {
        let components = rawValue.split(separator: ".")
        guard components.count >= 2 else { return "unknown" }
        return String(components[1])
    }

    /// The action performed
    var action: String {
        let components = rawValue.split(separator: ".")
        guard components.count >= 3 else { return "unknown" }
        return String(components[2])
    }

    /// Whether this event represents a creation
    var isCreateEvent: Bool {
        action == "created" || action == "added"
    }

    /// Whether this event represents an update
    var isUpdateEvent: Bool {
        action == "updated" || action == "status_changed"
    }

    /// Whether this event represents a deletion
    var isDeleteEvent: Bool {
        action == "deleted" || action == "removed"
    }
}

// MARK: - MediaRef

/// Reference to media associated with an event
struct MediaRef: Codable, Hashable, Sendable {
    /// Unique identifier for the media
    let id: String

    /// Type of media (image, video, audio, document)
    let mediaType: MediaType

    /// Local file path (relative to documents directory)
    let localPath: String?

    /// Remote URL for uploaded media
    let remoteUrl: String?

    /// File size in bytes
    let fileSize: Int64?

    /// Content hash for deduplication
    let contentHash: String?
}

// MARK: - DomainEvent

/// Append-only event representing a change in the domain
struct DomainEvent: Identifiable, Codable, Hashable, Sendable {

    // MARK: - Identity

    /// Unique identifier for this event
    let eventId: String

    /// User who generated this event
    let userId: String

    /// Device that generated this event
    let deviceId: String

    /// App instance that generated this event
    let appId: String

    // MARK: - Timing

    /// When this event occurred
    let timestamp: Date

    // MARK: - Event Data

    /// The type of event
    let eventType: DomainEventType

    /// Schema version for the payload (for migrations)
    let schemaVersion: Int

    /// The event payload containing entity data
    let payload: Data

    // MARK: - Attachments

    /// References to media attached to this event
    let mediaRefs: [MediaRef]

    // MARK: - Consent

    /// ID of the consent snapshot at the time of this event
    let consentSnapshotId: String?

    // MARK: - Sync Metadata

    /// Sequence number for ordering (local device)
    let localSequence: Int64?

    /// Server-assigned sequence number (after sync)
    var serverSequence: Int64?

    /// Whether this event has been synced to the server
    var isSynced: Bool

    /// When this event was synced (if synced)
    var syncedAt: Date?

    // MARK: - Identifiable

    var id: String { eventId }

    // MARK: - Initialization

    init(
        eventId: String = UUID().uuidString,
        userId: String,
        deviceId: String,
        appId: String,
        timestamp: Date = Date(),
        eventType: DomainEventType,
        schemaVersion: Int = 1,
        payload: Data,
        mediaRefs: [MediaRef] = [],
        consentSnapshotId: String? = nil,
        localSequence: Int64? = nil,
        serverSequence: Int64? = nil,
        isSynced: Bool = false,
        syncedAt: Date? = nil
    ) {
        self.eventId = eventId
        self.userId = userId
        self.deviceId = deviceId
        self.appId = appId
        self.timestamp = timestamp
        self.eventType = eventType
        self.schemaVersion = schemaVersion
        self.payload = payload
        self.mediaRefs = mediaRefs
        self.consentSnapshotId = consentSnapshotId
        self.localSequence = localSequence
        self.serverSequence = serverSequence
        self.isSynced = isSynced
        self.syncedAt = syncedAt
    }

    // MARK: - Convenience Initializers

    /// Creates an event with a Codable payload
    static func create<T: Encodable>(
        userId: String,
        deviceId: String,
        appId: String,
        eventType: DomainEventType,
        payload: T,
        mediaRefs: [MediaRef] = [],
        consentSnapshotId: String? = nil
    ) throws -> DomainEvent {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let payloadData = try encoder.encode(payload)

        return DomainEvent(
            userId: userId,
            deviceId: deviceId,
            appId: appId,
            eventType: eventType,
            payload: payloadData,
            mediaRefs: mediaRefs,
            consentSnapshotId: consentSnapshotId
        )
    }

    // MARK: - Payload Decoding

    /// Decodes the payload to a specific type
    func decodePayload<T: Decodable>(_ type: T.Type) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(type, from: payload)
    }

    /// Attempts to decode the payload, returning nil on failure
    func tryDecodePayload<T: Decodable>(_ type: T.Type) -> T? {
        try? decodePayload(type)
    }

    // MARK: - Mutating Methods

    /// Marks the event as synced
    mutating func markSynced(serverSequence: Int64) {
        self.serverSequence = serverSequence
        self.isSynced = true
        self.syncedAt = Date()
    }
}

// MARK: - DomainEvent Hashable

extension DomainEvent {
    static func == (lhs: DomainEvent, rhs: DomainEvent) -> Bool {
        lhs.eventId == rhs.eventId
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(eventId)
    }
}

// MARK: - Common Payload Types

/// Payload for entity creation events
struct EntityCreatedPayload<T: Codable>: Codable {
    let entity: T
}

/// Payload for entity update events
struct EntityUpdatedPayload<T: Codable>: Codable {
    let entityId: String
    let previousState: T?
    let newState: T
    let changedFields: [String]
}

/// Payload for entity deletion events
struct EntityDeletedPayload: Codable {
    let entityId: String
    let deletedAt: Date
    let reason: String?
}

/// Payload for move/reorder events
struct EntityMovedPayload: Codable {
    let entityId: String
    let fromListId: String?
    let toListId: String?
    let fromIndex: Int?
    let toIndex: Int?
}

/// Payload for bulk operations
struct BulkOperationPayload: Codable {
    let entityIds: [String]
    let operation: String
    let targetListId: String?
}

/// Payload for tag assignment events
struct TagAssignmentPayload: Codable {
    let taskId: String
    let tagId: String
}

/// Payload for attachment events
struct AttachmentEventPayload: Codable {
    let taskId: String
    let attachment: AttachmentRef
}

// MARK: - Sample Data

extension DomainEvent {
    /// Sample event for previews and testing
    static var sample: DomainEvent {
        let payload = try! JSONEncoder().encode(["taskId": "sample-task-1", "title": "Sample Task"])
        return DomainEvent(
            userId: "user-123",
            deviceId: "device-456",
            appId: "tasks-app",
            eventType: .tasksTaskCreated,
            payload: payload,
            consentSnapshotId: "consent-789"
        )
    }
}
