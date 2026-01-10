//
//  EventRepository.swift
//  TasksApp
//
//  Repository for Pending Event (outbox queue) operations with thread-safe CoreData access
//

import CoreData
import Foundation
import Combine

/// Repository for managing the Pending Event outbox queue in CoreData
/// Implements FIFO queue with retry logic for offline-first sync
final class EventRepository: @unchecked Sendable {

    // MARK: - Properties

    private let persistenceController: PersistenceController

    /// Monotonically increasing sequence counter for ordering
    private var sequenceCounter: Int64 = 0
    private let sequenceLock = NSLock()

    /// Publisher for queue changes
    private let queueChangesSubject = PassthroughSubject<QueueChange, Never>()
    var queueChanges: AnyPublisher<QueueChange, Never> {
        queueChangesSubject.eraseToAnyPublisher()
    }

    // MARK: - Initialization

    init(persistenceController: PersistenceController = .shared) {
        self.persistenceController = persistenceController
        initializeSequenceCounter()
    }

    private func initializeSequenceCounter() {
        let context = persistenceController.newBackgroundContext()

        context.performAndWait {
            let request = CDPendingEvent.fetchRequest()
            request.sortDescriptors = [NSSortDescriptor(key: "sequence", ascending: false)]
            request.fetchLimit = 1

            if let lastEvent = try? context.fetch(request).first {
                sequenceCounter = lastEvent.sequence + 1
            }
        }
    }

    private func nextSequence() -> Int64 {
        sequenceLock.lock()
        defer { sequenceLock.unlock() }
        let sequence = sequenceCounter
        sequenceCounter += 1
        return sequence
    }

    // MARK: - Enqueue Operations

    /// Enqueues a new event to the outbox
    /// - Parameters:
    ///   - eventType: Type of event (create, update, delete, etc.)
    ///   - entityType: Type of entity (task, list, tag)
    ///   - entityId: ID of the affected entity
    ///   - payload: Event payload as dictionary
    /// - Returns: The created pending event
    @discardableResult
    func enqueue(
        eventType: String,
        entityType: String,
        entityId: String,
        payload: [String: Any]
    ) throws -> CDPendingEvent {
        let context = persistenceController.viewContext
        var createdEvent: CDPendingEvent!
        var thrownError: Error?

        // Serialize payload to JSON
        guard let payloadData = try? JSONSerialization.data(withJSONObject: payload),
              let payloadString = String(data: payloadData, encoding: .utf8) else {
            throw PersistenceError.invalidData("Failed to serialize event payload")
        }

        context.performAndWait {
            let event = CDPendingEvent(context: context)
            event.id = UUID().uuidString
            event.eventType = eventType
            event.entityType = entityType
            event.entityId = entityId
            event.payload = payloadString
            event.createdAt = Date()
            event.sequence = nextSequence()
            event.retryCount = 0
            event.status = EventStatus.pending.rawValue

            do {
                try context.save()
                createdEvent = event
            } catch {
                thrownError = error
            }
        }

        if let error = thrownError {
            throw PersistenceError.saveFailed(error)
        }

        queueChangesSubject.send(.enqueued(createdEvent))
        return createdEvent
    }

    /// Enqueues a task create event
    @discardableResult
    func enqueueTaskCreate(task: CDTask) throws -> CDPendingEvent {
        let payload: [String: Any] = [
            "id": task.id,
            "title": task.title,
            "notes": task.notes as Any,
            "isCompleted": task.isCompleted,
            "priority": task.priority,
            "dueDate": task.dueDate?.timeIntervalSince1970 as Any,
            "listId": task.listId as Any,
            "createdAt": task.createdAt.timeIntervalSince1970,
            "modifiedAt": task.modifiedAt.timeIntervalSince1970
        ]

        return try enqueue(
            eventType: CDPendingEvent.EventTypes.create,
            entityType: CDPendingEvent.EntityTypes.task,
            entityId: task.id,
            payload: payload
        )
    }

    /// Enqueues a task update event
    @discardableResult
    func enqueueTaskUpdate(task: CDTask, changedFields: [String: Any]) throws -> CDPendingEvent {
        var payload: [String: Any] = [
            "id": task.id,
            "modifiedAt": task.modifiedAt.timeIntervalSince1970
        ]
        payload.merge(changedFields) { _, new in new }

        return try enqueue(
            eventType: CDPendingEvent.EventTypes.update,
            entityType: CDPendingEvent.EntityTypes.task,
            entityId: task.id,
            payload: payload
        )
    }

    /// Enqueues a task delete event
    @discardableResult
    func enqueueTaskDelete(taskId: String) throws -> CDPendingEvent {
        let payload: [String: Any] = [
            "id": taskId,
            "deletedAt": Date().timeIntervalSince1970
        ]

        return try enqueue(
            eventType: CDPendingEvent.EventTypes.delete,
            entityType: CDPendingEvent.EntityTypes.task,
            entityId: taskId,
            payload: payload
        )
    }

    /// Enqueues a task completion event
    @discardableResult
    func enqueueTaskComplete(taskId: String, completedAt: Date) throws -> CDPendingEvent {
        let payload: [String: Any] = [
            "id": taskId,
            "isCompleted": true,
            "completedAt": completedAt.timeIntervalSince1970
        ]

        return try enqueue(
            eventType: CDPendingEvent.EventTypes.complete,
            entityType: CDPendingEvent.EntityTypes.task,
            entityId: taskId,
            payload: payload
        )
    }

    /// Enqueues a task uncomplete event
    @discardableResult
    func enqueueTaskUncomplete(taskId: String) throws -> CDPendingEvent {
        let payload: [String: Any] = [
            "id": taskId,
            "isCompleted": false,
            "completedAt": NSNull()
        ]

        return try enqueue(
            eventType: CDPendingEvent.EventTypes.uncomplete,
            entityType: CDPendingEvent.EntityTypes.task,
            entityId: taskId,
            payload: payload
        )
    }

    /// Enqueues a task move event
    @discardableResult
    func enqueueTaskMove(taskId: String, toListId: String?) throws -> CDPendingEvent {
        let payload: [String: Any] = [
            "id": taskId,
            "listId": toListId as Any,
            "movedAt": Date().timeIntervalSince1970
        ]

        return try enqueue(
            eventType: CDPendingEvent.EventTypes.move,
            entityType: CDPendingEvent.EntityTypes.task,
            entityId: taskId,
            payload: payload
        )
    }

    /// Enqueues a list create event
    @discardableResult
    func enqueueListCreate(list: CDTaskList) throws -> CDPendingEvent {
        let payload: [String: Any] = [
            "id": list.id,
            "name": list.name,
            "icon": list.icon as Any,
            "color": list.color as Any,
            "isDefault": list.isDefault,
            "createdAt": list.createdAt.timeIntervalSince1970
        ]

        return try enqueue(
            eventType: CDPendingEvent.EventTypes.create,
            entityType: CDPendingEvent.EntityTypes.taskList,
            entityId: list.id,
            payload: payload
        )
    }

    /// Enqueues a list update event
    @discardableResult
    func enqueueListUpdate(list: CDTaskList, changedFields: [String: Any]) throws -> CDPendingEvent {
        var payload: [String: Any] = [
            "id": list.id,
            "modifiedAt": list.modifiedAt.timeIntervalSince1970
        ]
        payload.merge(changedFields) { _, new in new }

        return try enqueue(
            eventType: CDPendingEvent.EventTypes.update,
            entityType: CDPendingEvent.EntityTypes.taskList,
            entityId: list.id,
            payload: payload
        )
    }

    /// Enqueues a list delete event
    @discardableResult
    func enqueueListDelete(listId: String) throws -> CDPendingEvent {
        let payload: [String: Any] = [
            "id": listId,
            "deletedAt": Date().timeIntervalSince1970
        ]

        return try enqueue(
            eventType: CDPendingEvent.EventTypes.delete,
            entityType: CDPendingEvent.EntityTypes.taskList,
            entityId: listId,
            payload: payload
        )
    }

    /// Enqueues multiple events in a batch
    @discardableResult
    func enqueueBatch(
        events: [(eventType: String, entityType: String, entityId: String, payload: [String: Any])]
    ) throws -> [CDPendingEvent] {
        let context = persistenceController.newBackgroundContext()
        var createdEvents: [CDPendingEvent] = []
        var thrownError: Error?

        context.performAndWait {
            for eventData in events {
                guard let payloadData = try? JSONSerialization.data(withJSONObject: eventData.payload),
                      let payloadString = String(data: payloadData, encoding: .utf8) else {
                    continue
                }

                let event = CDPendingEvent(context: context)
                event.id = UUID().uuidString
                event.eventType = eventData.eventType
                event.entityType = eventData.entityType
                event.entityId = eventData.entityId
                event.payload = payloadString
                event.createdAt = Date()
                event.sequence = nextSequence()
                event.retryCount = 0
                event.status = EventStatus.pending.rawValue

                createdEvents.append(event)
            }

            do {
                try context.save()
            } catch {
                thrownError = error
            }
        }

        if let error = thrownError {
            throw PersistenceError.saveFailed(error)
        }

        createdEvents.forEach { queueChangesSubject.send(.enqueued($0)) }
        return createdEvents
    }

    // MARK: - Dequeue Operations

    /// Fetches the next pending event to process (FIFO order)
    func dequeueNext(context: NSManagedObjectContext? = nil) -> CDPendingEvent? {
        let ctx = context ?? persistenceController.viewContext
        var result: CDPendingEvent?

        ctx.performAndWait {
            let request = CDPendingEvent.fetchRequest()
            request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                NSPredicate(format: "status == %d", EventStatus.pending.rawValue),
                NSPredicate(format: "nextRetryAt == nil OR nextRetryAt <= %@", Date() as NSDate)
            ])
            request.sortDescriptors = [NSSortDescriptor(key: "sequence", ascending: true)]
            request.fetchLimit = 1

            if let event = try? ctx.fetch(request).first {
                event.status = EventStatus.processing.rawValue
                event.lastAttemptAt = Date()
                try? ctx.save()
                result = event
            }
        }

        if let event = result {
            queueChangesSubject.send(.processing(event))
        }

        return result
    }

    /// Fetches a batch of pending events to process
    func dequeueBatch(limit: Int = 10, context: NSManagedObjectContext? = nil) -> [CDPendingEvent] {
        let ctx = context ?? persistenceController.newBackgroundContext()
        var results: [CDPendingEvent] = []

        ctx.performAndWait {
            let request = CDPendingEvent.fetchRequest()
            request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                NSPredicate(format: "status == %d", EventStatus.pending.rawValue),
                NSPredicate(format: "nextRetryAt == nil OR nextRetryAt <= %@", Date() as NSDate)
            ])
            request.sortDescriptors = [NSSortDescriptor(key: "sequence", ascending: true)]
            request.fetchLimit = limit

            if let events = try? ctx.fetch(request) {
                let now = Date()
                for event in events {
                    event.status = EventStatus.processing.rawValue
                    event.lastAttemptAt = now
                }
                try? ctx.save()
                results = events
            }
        }

        results.forEach { queueChangesSubject.send(.processing($0)) }
        return results
    }

    // MARK: - Status Updates

    /// Marks an event as completed
    func markCompleted(eventId: String) throws {
        let context = persistenceController.viewContext
        var thrownError: Error?

        context.performAndWait {
            let request = CDPendingEvent.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", eventId)
            request.fetchLimit = 1

            do {
                if let event = try context.fetch(request).first {
                    event.status = EventStatus.completed.rawValue
                    try context.save()
                    queueChangesSubject.send(.completed(eventId))
                }
            } catch {
                thrownError = error
            }
        }

        if let error = thrownError {
            throw PersistenceError.saveFailed(error)
        }
    }

    /// Marks multiple events as completed
    func markCompleted(eventIds: [String]) throws {
        let context = persistenceController.newBackgroundContext()
        var thrownError: Error?

        context.performAndWait {
            let request = CDPendingEvent.fetchRequest()
            request.predicate = NSPredicate(format: "id IN %@", eventIds)

            do {
                let events = try context.fetch(request)
                for event in events {
                    event.status = EventStatus.completed.rawValue
                }
                try context.save()
            } catch {
                thrownError = error
            }
        }

        if let error = thrownError {
            throw PersistenceError.saveFailed(error)
        }

        eventIds.forEach { queueChangesSubject.send(.completed($0)) }
    }

    /// Marks an event as failed and schedules a retry
    func markFailed(eventId: String, error: String) throws {
        let context = persistenceController.viewContext
        var thrownError: Error?
        var shouldNotify = false
        var finalStatus: EventStatus = .pending

        context.performAndWait {
            let request = CDPendingEvent.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", eventId)
            request.fetchLimit = 1

            do {
                if let event = try context.fetch(request).first {
                    event.errorMessage = error
                    event.scheduleRetry()
                    finalStatus = event.currentStatus
                    shouldNotify = true
                    try context.save()
                }
            } catch {
                thrownError = error as? Error
            }
        }

        if let error = thrownError {
            throw PersistenceError.saveFailed(error)
        }

        if shouldNotify {
            if finalStatus == .failed {
                queueChangesSubject.send(.failed(eventId, error))
            } else {
                queueChangesSubject.send(.retryScheduled(eventId))
            }
        }
    }

    /// Marks an event as cancelled
    func markCancelled(eventId: String) throws {
        let context = persistenceController.viewContext
        var thrownError: Error?

        context.performAndWait {
            let request = CDPendingEvent.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", eventId)
            request.fetchLimit = 1

            do {
                if let event = try context.fetch(request).first {
                    event.status = EventStatus.cancelled.rawValue
                    try context.save()
                    queueChangesSubject.send(.cancelled(eventId))
                }
            } catch {
                thrownError = error
            }
        }

        if let error = thrownError {
            throw PersistenceError.saveFailed(error)
        }
    }

    /// Resets a failed or cancelled event to pending for retry
    func resetToPending(eventId: String) throws {
        let context = persistenceController.viewContext
        var thrownError: Error?

        context.performAndWait {
            let request = CDPendingEvent.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", eventId)
            request.fetchLimit = 1

            do {
                if let event = try context.fetch(request).first {
                    event.status = EventStatus.pending.rawValue
                    event.retryCount = 0
                    event.nextRetryAt = nil
                    event.errorMessage = nil
                    try context.save()
                }
            } catch {
                thrownError = error
            }
        }

        if let error = thrownError {
            throw PersistenceError.saveFailed(error)
        }
    }

    // MARK: - Query Operations

    /// Fetches an event by ID
    func fetchEvent(byId id: String, context: NSManagedObjectContext? = nil) -> CDPendingEvent? {
        let ctx = context ?? persistenceController.viewContext
        var result: CDPendingEvent?

        ctx.performAndWait {
            let request = CDPendingEvent.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", id)
            request.fetchLimit = 1

            result = try? ctx.fetch(request).first
        }

        return result
    }

    /// Fetches all pending events
    func fetchPendingEvents(context: NSManagedObjectContext? = nil) throws -> [CDPendingEvent] {
        let ctx = context ?? persistenceController.viewContext
        var events: [CDPendingEvent] = []
        var thrownError: Error?

        ctx.performAndWait {
            let request = CDPendingEvent.fetchRequest()
            request.predicate = NSPredicate(format: "status == %d", EventStatus.pending.rawValue)
            request.sortDescriptors = [NSSortDescriptor(key: "sequence", ascending: true)]

            do {
                events = try ctx.fetch(request)
            } catch {
                thrownError = error
            }
        }

        if let error = thrownError {
            throw PersistenceError.fetchFailed(error)
        }

        return events
    }

    /// Fetches failed events
    func fetchFailedEvents(context: NSManagedObjectContext? = nil) throws -> [CDPendingEvent] {
        let ctx = context ?? persistenceController.viewContext
        var events: [CDPendingEvent] = []
        var thrownError: Error?

        ctx.performAndWait {
            let request = CDPendingEvent.fetchRequest()
            request.predicate = NSPredicate(format: "status == %d", EventStatus.failed.rawValue)
            request.sortDescriptors = [NSSortDescriptor(key: "sequence", ascending: true)]

            do {
                events = try ctx.fetch(request)
            } catch {
                thrownError = error
            }
        }

        if let error = thrownError {
            throw PersistenceError.fetchFailed(error)
        }

        return events
    }

    /// Fetches events for a specific entity
    func fetchEvents(
        forEntityType entityType: String,
        entityId: String,
        context: NSManagedObjectContext? = nil
    ) throws -> [CDPendingEvent] {
        let ctx = context ?? persistenceController.viewContext
        var events: [CDPendingEvent] = []
        var thrownError: Error?

        ctx.performAndWait {
            let request = CDPendingEvent.fetchRequest()
            request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                NSPredicate(format: "entityType == %@", entityType),
                NSPredicate(format: "entityId == %@", entityId)
            ])
            request.sortDescriptors = [NSSortDescriptor(key: "sequence", ascending: true)]

            do {
                events = try ctx.fetch(request)
            } catch {
                thrownError = error
            }
        }

        if let error = thrownError {
            throw PersistenceError.fetchFailed(error)
        }

        return events
    }

    /// Fetches events ready for retry
    func fetchEventsReadyForRetry(context: NSManagedObjectContext? = nil) throws -> [CDPendingEvent] {
        let ctx = context ?? persistenceController.viewContext
        var events: [CDPendingEvent] = []
        var thrownError: Error?

        ctx.performAndWait {
            let request = CDPendingEvent.fetchRequest()
            request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                NSPredicate(format: "status == %d", EventStatus.pending.rawValue),
                NSPredicate(format: "retryCount > 0"),
                NSPredicate(format: "nextRetryAt <= %@", Date() as NSDate)
            ])
            request.sortDescriptors = [NSSortDescriptor(key: "sequence", ascending: true)]

            do {
                events = try ctx.fetch(request)
            } catch {
                thrownError = error
            }
        }

        if let error = thrownError {
            throw PersistenceError.fetchFailed(error)
        }

        return events
    }

    /// Counts pending events
    func countPendingEvents(context: NSManagedObjectContext? = nil) -> Int {
        let ctx = context ?? persistenceController.viewContext
        var count = 0

        ctx.performAndWait {
            let request = CDPendingEvent.fetchRequest()
            request.predicate = NSPredicate(format: "status == %d", EventStatus.pending.rawValue)
            count = (try? ctx.count(for: request)) ?? 0
        }

        return count
    }

    /// Counts total queued events (pending + processing)
    func countQueuedEvents(context: NSManagedObjectContext? = nil) -> Int {
        let ctx = context ?? persistenceController.viewContext
        var count = 0

        ctx.performAndWait {
            let request = CDPendingEvent.fetchRequest()
            request.predicate = NSPredicate(
                format: "status == %d OR status == %d",
                EventStatus.pending.rawValue,
                EventStatus.processing.rawValue
            )
            count = (try? ctx.count(for: request)) ?? 0
        }

        return count
    }

    /// Checks if there are any pending events
    var hasPendingEvents: Bool {
        return countPendingEvents() > 0
    }

    // MARK: - Delete Operations

    /// Deletes completed events older than specified date
    func deleteCompletedEvents(olderThan date: Date) throws {
        let request = CDPendingEvent.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "status == %d", EventStatus.completed.rawValue),
            NSPredicate(format: "createdAt < %@", date as NSDate)
        ])

        try persistenceController.batchDelete(fetchRequest: request)
    }

    /// Deletes all completed events
    func deleteAllCompletedEvents() throws {
        let request = CDPendingEvent.fetchRequest()
        request.predicate = NSPredicate(format: "status == %d", EventStatus.completed.rawValue)

        try persistenceController.batchDelete(fetchRequest: request)
    }

    /// Deletes events for a specific entity (e.g., when entity is permanently deleted)
    func deleteEvents(forEntityId entityId: String) throws {
        let request = CDPendingEvent.fetchRequest()
        request.predicate = NSPredicate(format: "entityId == %@", entityId)

        try persistenceController.batchDelete(fetchRequest: request)
    }

    /// Clears all events (use with caution!)
    func clearAllEvents() throws {
        let request = CDPendingEvent.fetchRequest()
        try persistenceController.batchDelete(fetchRequest: request)
        queueChangesSubject.send(.cleared)
    }

    // MARK: - Merge Operations

    /// Merges/coalesces events for the same entity to reduce sync overhead
    /// For example, multiple updates to the same task can be merged into one
    func coalesceEvents(forEntityId entityId: String) throws {
        let context = persistenceController.newBackgroundContext()
        var thrownError: Error?

        context.performAndWait {
            let request = CDPendingEvent.fetchRequest()
            request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                NSPredicate(format: "entityId == %@", entityId),
                NSPredicate(format: "status == %d", EventStatus.pending.rawValue),
                NSPredicate(format: "eventType == %@", CDPendingEvent.EventTypes.update)
            ])
            request.sortDescriptors = [NSSortDescriptor(key: "sequence", ascending: true)]

            do {
                let events = try context.fetch(request)
                guard events.count > 1 else { return }

                // Merge all payloads into the last event
                var mergedPayload: [String: Any] = [:]

                for event in events {
                    if let payloadData = event.payload.data(using: .utf8),
                       let payload = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any] {
                        mergedPayload.merge(payload) { _, new in new }
                    }
                }

                // Keep the last event and update its payload
                let lastEvent = events.last!
                if let payloadData = try? JSONSerialization.data(withJSONObject: mergedPayload),
                   let payloadString = String(data: payloadData, encoding: .utf8) {
                    lastEvent.payload = payloadString
                }

                // Delete all but the last event
                for event in events.dropLast() {
                    context.delete(event)
                }

                try context.save()
            } catch {
                thrownError = error
            }
        }

        if let error = thrownError {
            throw PersistenceError.saveFailed(error)
        }
    }

    // MARK: - Sync State Operations

    /// Gets or creates sync state for a key
    func getOrCreateSyncState(key: String, context: NSManagedObjectContext? = nil) -> CDSyncState {
        let ctx = context ?? persistenceController.viewContext
        var syncState: CDSyncState!

        ctx.performAndWait {
            let request = CDSyncState.fetchRequest()
            request.predicate = NSPredicate(format: "key == %@", key)
            request.fetchLimit = 1

            if let existing = try? ctx.fetch(request).first {
                syncState = existing
            } else {
                let newState = CDSyncState(context: ctx)
                newState.key = key
                newState.fullSyncRequired = true
                newState.totalSyncs = 0
                newState.failedSyncs = 0
                try? ctx.save()
                syncState = newState
            }
        }

        return syncState
    }

    /// Updates sync state cursor
    func updateSyncCursor(key: String, cursor: String, serverVersion: Int64? = nil) throws {
        let context = persistenceController.viewContext
        var thrownError: Error?

        context.performAndWait {
            let syncState = getOrCreateSyncState(key: key, context: context)
            syncState.cursor = cursor
            if let version = serverVersion {
                syncState.serverVersion = NSNumber(value: version)
            }
            syncState.lastSyncCompleted = Date()

            do {
                try context.save()
            } catch {
                thrownError = error
            }
        }

        if let error = thrownError {
            throw PersistenceError.saveFailed(error)
        }
    }

    /// Marks a full sync as required
    func requireFullSync(key: String) throws {
        let context = persistenceController.viewContext
        var thrownError: Error?

        context.performAndWait {
            let syncState = getOrCreateSyncState(key: key, context: context)
            syncState.fullSyncRequired = true
            syncState.cursor = nil

            do {
                try context.save()
            } catch {
                thrownError = error
            }
        }

        if let error = thrownError {
            throw PersistenceError.saveFailed(error)
        }
    }

    /// Gets the current sync cursor for a key
    func getSyncCursor(key: String) -> String? {
        let context = persistenceController.viewContext
        var cursor: String?

        context.performAndWait {
            let request = CDSyncState.fetchRequest()
            request.predicate = NSPredicate(format: "key == %@", key)
            request.fetchLimit = 1

            cursor = try? context.fetch(request).first?.cursor
        }

        return cursor
    }

    /// Checks if a full sync is required
    func isFullSyncRequired(key: String) -> Bool {
        let context = persistenceController.viewContext
        var required = true

        context.performAndWait {
            let request = CDSyncState.fetchRequest()
            request.predicate = NSPredicate(format: "key == %@", key)
            request.fetchLimit = 1

            if let syncState = try? context.fetch(request).first {
                required = syncState.fullSyncRequired
            }
        }

        return required
    }
}

// MARK: - Queue Change Types

enum QueueChange {
    case enqueued(CDPendingEvent)
    case processing(CDPendingEvent)
    case completed(String)
    case failed(String, String)
    case retryScheduled(String)
    case cancelled(String)
    case cleared
}

// MARK: - Queue Statistics

extension EventRepository {

    struct QueueStatistics {
        let pendingCount: Int
        let processingCount: Int
        let completedCount: Int
        let failedCount: Int
        let cancelledCount: Int
        let oldestPendingDate: Date?
        let totalEventsProcessed: Int

        var totalCount: Int {
            pendingCount + processingCount + completedCount + failedCount + cancelledCount
        }

        var hasWork: Bool {
            pendingCount > 0 || processingCount > 0
        }
    }

    /// Gets queue statistics
    func getQueueStatistics() -> QueueStatistics {
        let context = persistenceController.viewContext
        var stats = QueueStatistics(
            pendingCount: 0,
            processingCount: 0,
            completedCount: 0,
            failedCount: 0,
            cancelledCount: 0,
            oldestPendingDate: nil,
            totalEventsProcessed: 0
        )

        context.performAndWait {
            let request = CDPendingEvent.fetchRequest()

            // Count by status
            for status in [EventStatus.pending, .processing, .completed, .failed, .cancelled] {
                request.predicate = NSPredicate(format: "status == %d", status.rawValue)
                let count = (try? context.count(for: request)) ?? 0

                switch status {
                case .pending:
                    stats = QueueStatistics(
                        pendingCount: count,
                        processingCount: stats.processingCount,
                        completedCount: stats.completedCount,
                        failedCount: stats.failedCount,
                        cancelledCount: stats.cancelledCount,
                        oldestPendingDate: stats.oldestPendingDate,
                        totalEventsProcessed: stats.totalEventsProcessed
                    )
                case .processing:
                    stats = QueueStatistics(
                        pendingCount: stats.pendingCount,
                        processingCount: count,
                        completedCount: stats.completedCount,
                        failedCount: stats.failedCount,
                        cancelledCount: stats.cancelledCount,
                        oldestPendingDate: stats.oldestPendingDate,
                        totalEventsProcessed: stats.totalEventsProcessed
                    )
                case .completed:
                    stats = QueueStatistics(
                        pendingCount: stats.pendingCount,
                        processingCount: stats.processingCount,
                        completedCount: count,
                        failedCount: stats.failedCount,
                        cancelledCount: stats.cancelledCount,
                        oldestPendingDate: stats.oldestPendingDate,
                        totalEventsProcessed: count
                    )
                case .failed:
                    stats = QueueStatistics(
                        pendingCount: stats.pendingCount,
                        processingCount: stats.processingCount,
                        completedCount: stats.completedCount,
                        failedCount: count,
                        cancelledCount: stats.cancelledCount,
                        oldestPendingDate: stats.oldestPendingDate,
                        totalEventsProcessed: stats.totalEventsProcessed
                    )
                case .cancelled:
                    stats = QueueStatistics(
                        pendingCount: stats.pendingCount,
                        processingCount: stats.processingCount,
                        completedCount: stats.completedCount,
                        failedCount: stats.failedCount,
                        cancelledCount: count,
                        oldestPendingDate: stats.oldestPendingDate,
                        totalEventsProcessed: stats.totalEventsProcessed
                    )
                }
            }

            // Get oldest pending event date
            request.predicate = NSPredicate(format: "status == %d", EventStatus.pending.rawValue)
            request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
            request.fetchLimit = 1

            if let oldestEvent = try? context.fetch(request).first {
                stats = QueueStatistics(
                    pendingCount: stats.pendingCount,
                    processingCount: stats.processingCount,
                    completedCount: stats.completedCount,
                    failedCount: stats.failedCount,
                    cancelledCount: stats.cancelledCount,
                    oldestPendingDate: oldestEvent.createdAt,
                    totalEventsProcessed: stats.totalEventsProcessed
                )
            }
        }

        return stats
    }
}

// MARK: - Event Payload Helpers

extension EventRepository {

    /// Parses event payload to dictionary
    func parsePayload(_ event: CDPendingEvent) -> [String: Any]? {
        guard let data = event.payload.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    /// Gets a specific field from event payload
    func getPayloadField<T>(_ event: CDPendingEvent, field: String) -> T? {
        guard let payload = parsePayload(event) else { return nil }
        return payload[field] as? T
    }
}
