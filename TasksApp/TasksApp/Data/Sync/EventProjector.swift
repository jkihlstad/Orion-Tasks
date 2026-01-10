//
//  EventProjector.swift
//  TasksApp
//
//  Applies domain events to local CoreData projections
//  Maintains consistent local state from event stream
//

import Foundation
import CoreData
import Combine

// MARK: - Projection Error

/// Errors that can occur during event projection
enum ProjectionError: LocalizedError {
    case invalidPayload(String)
    case entityNotFound(String, String)
    case contextSaveFailed(Error)
    case unsupportedEventType(String)
    case invalidState(String)

    var errorDescription: String? {
        switch self {
        case .invalidPayload(let message):
            return "Invalid event payload: \(message)"
        case .entityNotFound(let entityType, let entityId):
            return "\(entityType) not found: \(entityId)"
        case .contextSaveFailed(let error):
            return "Failed to save context: \(error.localizedDescription)"
        case .unsupportedEventType(let eventType):
            return "Unsupported event type: \(eventType)"
        case .invalidState(let message):
            return "Invalid state: \(message)"
        }
    }
}

// MARK: - Projection Result

/// Result of projecting an event
struct ProjectionResult {
    /// The event that was projected
    let event: DomainEvent

    /// Whether the projection succeeded
    let success: Bool

    /// Error if projection failed
    let error: ProjectionError?

    /// IDs of entities that were affected
    let affectedEntityIds: [String]

    /// Type of entities affected
    let affectedEntityType: String?

    /// Whether this projection caused any actual changes
    let hadChanges: Bool

    static func success(
        event: DomainEvent,
        affectedIds: [String] = [],
        entityType: String? = nil,
        hadChanges: Bool = true
    ) -> ProjectionResult {
        ProjectionResult(
            event: event,
            success: true,
            error: nil,
            affectedEntityIds: affectedIds,
            affectedEntityType: entityType,
            hadChanges: hadChanges
        )
    }

    static func failure(event: DomainEvent, error: ProjectionError) -> ProjectionResult {
        ProjectionResult(
            event: event,
            success: false,
            error: error,
            affectedEntityIds: [],
            affectedEntityType: nil,
            hadChanges: false
        )
    }
}

// MARK: - Event Projector

/// Projects domain events onto local CoreData state
final class EventProjector: @unchecked Sendable {

    // MARK: - Properties

    private let persistenceController: PersistenceController
    private let conflictResolver: ConflictResolver
    private let projectionSubject = PassthroughSubject<ProjectionResult, Never>()

    /// Publisher for projection results
    var projectionResults: AnyPublisher<ProjectionResult, Never> {
        projectionSubject.eraseToAnyPublisher()
    }

    // MARK: - Initialization

    init(
        persistenceController: PersistenceController = .shared,
        conflictResolver: ConflictResolver
    ) {
        self.persistenceController = persistenceController
        self.conflictResolver = conflictResolver
    }

    // MARK: - Public Methods

    /// Projects a single event onto local state
    @discardableResult
    func project(_ event: DomainEvent, context: NSManagedObjectContext? = nil) -> ProjectionResult {
        let ctx = context ?? persistenceController.newBackgroundContext()
        var result: ProjectionResult!

        ctx.performAndWait {
            do {
                result = try projectEvent(event, context: ctx)
                if result.success && result.hadChanges {
                    try ctx.save()
                }
            } catch let projectionError as ProjectionError {
                result = .failure(event: event, error: projectionError)
            } catch {
                result = .failure(event: event, error: .contextSaveFailed(error))
            }
        }

        projectionSubject.send(result)
        return result
    }

    /// Projects multiple events in order
    func projectBatch(_ events: [DomainEvent], context: NSManagedObjectContext? = nil) -> [ProjectionResult] {
        let ctx = context ?? persistenceController.newBackgroundContext()
        var results: [ProjectionResult] = []

        ctx.performAndWait {
            for event in events {
                do {
                    let result = try projectEvent(event, context: ctx)
                    results.append(result)
                } catch let projectionError as ProjectionError {
                    results.append(.failure(event: event, error: projectionError))
                } catch {
                    results.append(.failure(event: event, error: .contextSaveFailed(error)))
                }
            }

            // Save all changes at once
            if ctx.hasChanges {
                do {
                    try ctx.save()
                } catch {
                    // Mark all successful results as failed due to save error
                    results = results.map { result in
                        if result.success {
                            return .failure(event: result.event, error: .contextSaveFailed(error))
                        }
                        return result
                    }
                }
            }
        }

        results.forEach { projectionSubject.send($0) }
        return results
    }

    // MARK: - Private Event Projection

    private func projectEvent(_ event: DomainEvent, context: NSManagedObjectContext) throws -> ProjectionResult {
        switch event.eventType {
        // List Events
        case .tasksListCreated:
            return try projectListCreated(event, context: context)
        case .tasksListUpdated:
            return try projectListUpdated(event, context: context)
        case .tasksListDeleted:
            return try projectListDeleted(event, context: context)
        case .tasksListReordered:
            return try projectListReordered(event, context: context)

        // Task Events
        case .tasksTaskCreated:
            return try projectTaskCreated(event, context: context)
        case .tasksTaskUpdated:
            return try projectTaskUpdated(event, context: context)
        case .tasksTaskDeleted:
            return try projectTaskDeleted(event, context: context)
        case .tasksTaskCompleted:
            return try projectTaskCompleted(event, context: context)
        case .tasksTaskUncompleted:
            return try projectTaskUncompleted(event, context: context)
        case .tasksTaskMoved:
            return try projectTaskMoved(event, context: context)
        case .tasksTaskReordered:
            return try projectTaskReordered(event, context: context)
        case .tasksTaskFlagged:
            return try projectTaskFlagged(event, context: context)
        case .tasksTaskUnflagged:
            return try projectTaskUnflagged(event, context: context)

        // Subtask Events
        case .tasksSubtaskAdded:
            return try projectSubtaskAdded(event, context: context)
        case .tasksSubtaskRemoved:
            return try projectSubtaskRemoved(event, context: context)

        // Tag Events
        case .tasksTagCreated:
            return try projectTagCreated(event, context: context)
        case .tasksTagUpdated:
            return try projectTagUpdated(event, context: context)
        case .tasksTagDeleted:
            return try projectTagDeleted(event, context: context)
        case .tasksTagAssigned:
            return try projectTagAssigned(event, context: context)
        case .tasksTagUnassigned:
            return try projectTagUnassigned(event, context: context)

        // Attachment Events
        case .tasksAttachmentAdded:
            return try projectAttachmentAdded(event, context: context)
        case .tasksAttachmentRemoved:
            return try projectAttachmentRemoved(event, context: context)
        case .tasksAttachmentStatusChanged:
            return try projectAttachmentStatusChanged(event, context: context)

        // Bulk Operations
        case .tasksBulkCompleted:
            return try projectBulkCompleted(event, context: context)
        case .tasksBulkDeleted:
            return try projectBulkDeleted(event, context: context)
        case .tasksBulkMoved:
            return try projectBulkMoved(event, context: context)

        // Calendar Events (handled separately)
        case .tasksCalendarMirrored, .tasksCalendarUnmirrored,
             .tasksCalendarImported, .tasksCalendarSynced:
            return .success(event: event, hadChanges: false)

        // Consent Events (handled separately)
        case .tasksConsentUpdated, .tasksConsentSnapshotCreated:
            return .success(event: event, hadChanges: false)
        }
    }

    // MARK: - List Projections

    private func projectListCreated(_ event: DomainEvent, context: NSManagedObjectContext) throws -> ProjectionResult {
        let payload = try event.decodePayload(TaskListPayload.self)

        // Check if list already exists
        if fetchTaskList(byId: payload.id, context: context) != nil {
            return .success(event: event, affectedIds: [payload.id], entityType: "taskList", hadChanges: false)
        }

        let list = CDTaskList(context: context)
        list.id = payload.id
        list.name = payload.name
        list.color = payload.color
        list.icon = payload.icon
        list.sortOrder = Int32(payload.sortOrder ?? 0)
        list.isDefault = payload.isDefault ?? false
        list.isSmartList = payload.isSmartList ?? false
        list.smartFilter = payload.smartFilter
        list.createdAt = payload.createdAt ?? event.timestamp
        list.modifiedAt = payload.modifiedAt ?? event.timestamp
        list.syncStatus = SyncStatus.synced.rawValue

        if let serverVersion = event.serverSequence {
            list.serverVersion = NSNumber(value: serverVersion)
        }

        return .success(event: event, affectedIds: [payload.id], entityType: "taskList")
    }

    private func projectListUpdated(_ event: DomainEvent, context: NSManagedObjectContext) throws -> ProjectionResult {
        let payload = try event.decodePayload(TaskListPayload.self)

        guard let list = fetchTaskList(byId: payload.id, context: context) else {
            throw ProjectionError.entityNotFound("TaskList", payload.id)
        }

        // Apply updates
        if let name = payload.name { list.name = name }
        if let color = payload.color { list.color = color }
        if let icon = payload.icon { list.icon = icon }
        if let sortOrder = payload.sortOrder { list.sortOrder = Int32(sortOrder) }
        if let isDefault = payload.isDefault { list.isDefault = isDefault }
        list.modifiedAt = event.timestamp

        if let serverVersion = event.serverSequence {
            list.serverVersion = NSNumber(value: serverVersion)
        }

        return .success(event: event, affectedIds: [payload.id], entityType: "taskList")
    }

    private func projectListDeleted(_ event: DomainEvent, context: NSManagedObjectContext) throws -> ProjectionResult {
        let payload = try event.decodePayload(EntityDeletedPayload.self)

        guard let list = fetchTaskList(byId: payload.entityId, context: context) else {
            return .success(event: event, affectedIds: [payload.entityId], entityType: "taskList", hadChanges: false)
        }

        // Soft delete
        list.isDeleted = true
        list.modifiedAt = event.timestamp

        return .success(event: event, affectedIds: [payload.entityId], entityType: "taskList")
    }

    private func projectListReordered(_ event: DomainEvent, context: NSManagedObjectContext) throws -> ProjectionResult {
        let payload = try event.decodePayload(ListReorderPayload.self)
        var affectedIds: [String] = []

        for (index, listId) in payload.listIds.enumerated() {
            if let list = fetchTaskList(byId: listId, context: context) {
                list.sortOrder = Int32(index)
                affectedIds.append(listId)
            }
        }

        return .success(event: event, affectedIds: affectedIds, entityType: "taskList")
    }

    // MARK: - Task Projections

    private func projectTaskCreated(_ event: DomainEvent, context: NSManagedObjectContext) throws -> ProjectionResult {
        let payload = try event.decodePayload(TaskPayload.self)

        // Check if task already exists
        if fetchTask(byId: payload.id, context: context) != nil {
            return .success(event: event, affectedIds: [payload.id], entityType: "task", hadChanges: false)
        }

        let task = CDTask(context: context)
        task.id = payload.id
        task.title = payload.title
        task.notes = payload.notes
        task.isCompleted = payload.isCompleted ?? false
        task.completedAt = payload.completedAt
        task.dueDate = payload.dueDate
        task.reminderDate = payload.reminderDate
        task.priority = Int16(payload.priority ?? 0)
        task.sortOrder = Int32(payload.sortOrder ?? 0)
        task.listId = payload.listId
        task.parentTaskId = payload.parentTaskId
        task.createdAt = payload.createdAt ?? event.timestamp
        task.modifiedAt = payload.modifiedAt ?? event.timestamp
        task.syncStatus = SyncStatus.synced.rawValue

        // Set up list relationship
        if let listId = payload.listId, let list = fetchTaskList(byId: listId, context: context) {
            task.list = list
        }

        if let serverVersion = event.serverSequence {
            task.serverVersion = NSNumber(value: serverVersion)
        }

        return .success(event: event, affectedIds: [payload.id], entityType: "task")
    }

    private func projectTaskUpdated(_ event: DomainEvent, context: NSManagedObjectContext) throws -> ProjectionResult {
        let payload = try event.decodePayload(TaskPayload.self)

        guard let task = fetchTask(byId: payload.id, context: context) else {
            throw ProjectionError.entityNotFound("Task", payload.id)
        }

        // Apply updates
        if let title = payload.title { task.title = title }
        if let notes = payload.notes { task.notes = notes }
        if let isCompleted = payload.isCompleted { task.isCompleted = isCompleted }
        if let completedAt = payload.completedAt { task.completedAt = completedAt }
        if let dueDate = payload.dueDate { task.dueDate = dueDate }
        if let reminderDate = payload.reminderDate { task.reminderDate = reminderDate }
        if let priority = payload.priority { task.priority = Int16(priority) }
        if let sortOrder = payload.sortOrder { task.sortOrder = Int32(sortOrder) }
        task.modifiedAt = event.timestamp

        if let serverVersion = event.serverSequence {
            task.serverVersion = NSNumber(value: serverVersion)
        }

        return .success(event: event, affectedIds: [payload.id], entityType: "task")
    }

    private func projectTaskDeleted(_ event: DomainEvent, context: NSManagedObjectContext) throws -> ProjectionResult {
        let payload = try event.decodePayload(EntityDeletedPayload.self)

        guard let task = fetchTask(byId: payload.entityId, context: context) else {
            return .success(event: event, affectedIds: [payload.entityId], entityType: "task", hadChanges: false)
        }

        // Soft delete
        task.isDeleted = true
        task.modifiedAt = event.timestamp

        return .success(event: event, affectedIds: [payload.entityId], entityType: "task")
    }

    private func projectTaskCompleted(_ event: DomainEvent, context: NSManagedObjectContext) throws -> ProjectionResult {
        let payload = try event.decodePayload(TaskCompletionPayload.self)

        guard let task = fetchTask(byId: payload.taskId, context: context) else {
            throw ProjectionError.entityNotFound("Task", payload.taskId)
        }

        task.isCompleted = true
        task.completedAt = payload.completedAt ?? event.timestamp
        task.modifiedAt = event.timestamp

        return .success(event: event, affectedIds: [payload.taskId], entityType: "task")
    }

    private func projectTaskUncompleted(_ event: DomainEvent, context: NSManagedObjectContext) throws -> ProjectionResult {
        let payload = try event.decodePayload(TaskCompletionPayload.self)

        guard let task = fetchTask(byId: payload.taskId, context: context) else {
            throw ProjectionError.entityNotFound("Task", payload.taskId)
        }

        task.isCompleted = false
        task.completedAt = nil
        task.modifiedAt = event.timestamp

        return .success(event: event, affectedIds: [payload.taskId], entityType: "task")
    }

    private func projectTaskMoved(_ event: DomainEvent, context: NSManagedObjectContext) throws -> ProjectionResult {
        let payload = try event.decodePayload(EntityMovedPayload.self)

        guard let task = fetchTask(byId: payload.entityId, context: context) else {
            throw ProjectionError.entityNotFound("Task", payload.entityId)
        }

        if let newListId = payload.toListId {
            task.listId = newListId
            if let newList = fetchTaskList(byId: newListId, context: context) {
                task.list = newList
            }
        }

        if let newIndex = payload.toIndex {
            task.sortOrder = Int32(newIndex)
        }

        task.modifiedAt = event.timestamp

        return .success(event: event, affectedIds: [payload.entityId], entityType: "task")
    }

    private func projectTaskReordered(_ event: DomainEvent, context: NSManagedObjectContext) throws -> ProjectionResult {
        let payload = try event.decodePayload(TaskReorderPayload.self)
        var affectedIds: [String] = []

        for (index, taskId) in payload.taskIds.enumerated() {
            if let task = fetchTask(byId: taskId, context: context) {
                task.sortOrder = Int32(index)
                affectedIds.append(taskId)
            }
        }

        return .success(event: event, affectedIds: affectedIds, entityType: "task")
    }

    private func projectTaskFlagged(_ event: DomainEvent, context: NSManagedObjectContext) throws -> ProjectionResult {
        let payload = try event.decodePayload(TaskFlagPayload.self)

        guard let task = fetchTask(byId: payload.taskId, context: context) else {
            throw ProjectionError.entityNotFound("Task", payload.taskId)
        }

        // Note: CDTask doesn't have a flag property currently, would need to be added
        // For now, we'll just update the modification time
        task.modifiedAt = event.timestamp

        return .success(event: event, affectedIds: [payload.taskId], entityType: "task")
    }

    private func projectTaskUnflagged(_ event: DomainEvent, context: NSManagedObjectContext) throws -> ProjectionResult {
        let payload = try event.decodePayload(TaskFlagPayload.self)

        guard let task = fetchTask(byId: payload.taskId, context: context) else {
            throw ProjectionError.entityNotFound("Task", payload.taskId)
        }

        task.modifiedAt = event.timestamp

        return .success(event: event, affectedIds: [payload.taskId], entityType: "task")
    }

    // MARK: - Subtask Projections

    private func projectSubtaskAdded(_ event: DomainEvent, context: NSManagedObjectContext) throws -> ProjectionResult {
        let payload = try event.decodePayload(SubtaskPayload.self)

        guard let parentTask = fetchTask(byId: payload.parentTaskId, context: context) else {
            throw ProjectionError.entityNotFound("Task", payload.parentTaskId)
        }

        guard let subtask = fetchTask(byId: payload.subtaskId, context: context) else {
            throw ProjectionError.entityNotFound("Subtask", payload.subtaskId)
        }

        subtask.parentTask = parentTask
        subtask.parentTaskId = payload.parentTaskId
        parentTask.addToSubtasks(subtask)
        parentTask.modifiedAt = event.timestamp

        return .success(event: event, affectedIds: [payload.parentTaskId, payload.subtaskId], entityType: "task")
    }

    private func projectSubtaskRemoved(_ event: DomainEvent, context: NSManagedObjectContext) throws -> ProjectionResult {
        let payload = try event.decodePayload(SubtaskPayload.self)

        guard let parentTask = fetchTask(byId: payload.parentTaskId, context: context) else {
            throw ProjectionError.entityNotFound("Task", payload.parentTaskId)
        }

        guard let subtask = fetchTask(byId: payload.subtaskId, context: context) else {
            return .success(event: event, affectedIds: [payload.parentTaskId], entityType: "task", hadChanges: false)
        }

        subtask.parentTask = nil
        subtask.parentTaskId = nil
        parentTask.removeFromSubtasks(subtask)
        parentTask.modifiedAt = event.timestamp

        return .success(event: event, affectedIds: [payload.parentTaskId, payload.subtaskId], entityType: "task")
    }

    // MARK: - Tag Projections

    private func projectTagCreated(_ event: DomainEvent, context: NSManagedObjectContext) throws -> ProjectionResult {
        let payload = try event.decodePayload(TagPayload.self)

        // Check if tag already exists
        if fetchTag(byId: payload.id, context: context) != nil {
            return .success(event: event, affectedIds: [payload.id], entityType: "tag", hadChanges: false)
        }

        let tag = CDTag(context: context)
        tag.id = payload.id
        tag.name = payload.name
        tag.color = payload.color
        tag.createdAt = payload.createdAt ?? event.timestamp
        tag.modifiedAt = event.timestamp
        tag.syncStatus = SyncStatus.synced.rawValue

        return .success(event: event, affectedIds: [payload.id], entityType: "tag")
    }

    private func projectTagUpdated(_ event: DomainEvent, context: NSManagedObjectContext) throws -> ProjectionResult {
        let payload = try event.decodePayload(TagPayload.self)

        guard let tag = fetchTag(byId: payload.id, context: context) else {
            throw ProjectionError.entityNotFound("Tag", payload.id)
        }

        if let name = payload.name { tag.name = name }
        if let color = payload.color { tag.color = color }
        tag.modifiedAt = event.timestamp

        return .success(event: event, affectedIds: [payload.id], entityType: "tag")
    }

    private func projectTagDeleted(_ event: DomainEvent, context: NSManagedObjectContext) throws -> ProjectionResult {
        let payload = try event.decodePayload(EntityDeletedPayload.self)

        guard let tag = fetchTag(byId: payload.entityId, context: context) else {
            return .success(event: event, affectedIds: [payload.entityId], entityType: "tag", hadChanges: false)
        }

        tag.isDeleted = true
        tag.modifiedAt = event.timestamp

        return .success(event: event, affectedIds: [payload.entityId], entityType: "tag")
    }

    private func projectTagAssigned(_ event: DomainEvent, context: NSManagedObjectContext) throws -> ProjectionResult {
        let payload = try event.decodePayload(TagAssignmentPayload.self)

        guard let task = fetchTask(byId: payload.taskId, context: context) else {
            throw ProjectionError.entityNotFound("Task", payload.taskId)
        }

        guard let tag = fetchTag(byId: payload.tagId, context: context) else {
            throw ProjectionError.entityNotFound("Tag", payload.tagId)
        }

        task.addToTags(tag)
        task.modifiedAt = event.timestamp

        return .success(event: event, affectedIds: [payload.taskId, payload.tagId], entityType: "task")
    }

    private func projectTagUnassigned(_ event: DomainEvent, context: NSManagedObjectContext) throws -> ProjectionResult {
        let payload = try event.decodePayload(TagAssignmentPayload.self)

        guard let task = fetchTask(byId: payload.taskId, context: context) else {
            throw ProjectionError.entityNotFound("Task", payload.taskId)
        }

        guard let tag = fetchTag(byId: payload.tagId, context: context) else {
            return .success(event: event, affectedIds: [payload.taskId], entityType: "task", hadChanges: false)
        }

        task.removeFromTags(tag)
        task.modifiedAt = event.timestamp

        return .success(event: event, affectedIds: [payload.taskId, payload.tagId], entityType: "task")
    }

    // MARK: - Attachment Projections

    private func projectAttachmentAdded(_ event: DomainEvent, context: NSManagedObjectContext) throws -> ProjectionResult {
        let payload = try event.decodePayload(AttachmentEventPayload.self)

        guard let task = fetchTask(byId: payload.taskId, context: context) else {
            throw ProjectionError.entityNotFound("Task", payload.taskId)
        }

        let attachment = CDAttachmentRef(context: context)
        attachment.id = payload.attachment.id
        attachment.taskId = payload.taskId
        attachment.fileName = payload.attachment.originalFilename ?? "attachment"
        attachment.mimeType = payload.attachment.mimeType
        attachment.localPath = payload.attachment.localPath
        attachment.remoteURL = payload.attachment.remoteUrl
        attachment.createdAt = payload.attachment.createdAt

        task.addToAttachments(attachment)
        task.modifiedAt = event.timestamp

        return .success(event: event, affectedIds: [payload.taskId, payload.attachment.id], entityType: "attachment")
    }

    private func projectAttachmentRemoved(_ event: DomainEvent, context: NSManagedObjectContext) throws -> ProjectionResult {
        let payload = try event.decodePayload(AttachmentEventPayload.self)

        guard let task = fetchTask(byId: payload.taskId, context: context) else {
            throw ProjectionError.entityNotFound("Task", payload.taskId)
        }

        if let attachment = fetchAttachment(byId: payload.attachment.id, context: context) {
            task.removeFromAttachments(attachment)
            context.delete(attachment)
        }

        task.modifiedAt = event.timestamp

        return .success(event: event, affectedIds: [payload.taskId, payload.attachment.id], entityType: "attachment")
    }

    private func projectAttachmentStatusChanged(_ event: DomainEvent, context: NSManagedObjectContext) throws -> ProjectionResult {
        let payload = try event.decodePayload(AttachmentStatusPayload.self)

        guard let attachment = fetchAttachment(byId: payload.attachmentId, context: context) else {
            throw ProjectionError.entityNotFound("Attachment", payload.attachmentId)
        }

        attachment.uploadStatus = Int16(payload.status.rawValue)
        if let remoteUrl = payload.remoteUrl {
            attachment.remoteURL = remoteUrl
        }

        return .success(event: event, affectedIds: [payload.attachmentId], entityType: "attachment")
    }

    // MARK: - Bulk Projections

    private func projectBulkCompleted(_ event: DomainEvent, context: NSManagedObjectContext) throws -> ProjectionResult {
        let payload = try event.decodePayload(BulkOperationPayload.self)
        var affectedIds: [String] = []

        for taskId in payload.entityIds {
            if let task = fetchTask(byId: taskId, context: context) {
                task.isCompleted = true
                task.completedAt = event.timestamp
                task.modifiedAt = event.timestamp
                affectedIds.append(taskId)
            }
        }

        return .success(event: event, affectedIds: affectedIds, entityType: "task")
    }

    private func projectBulkDeleted(_ event: DomainEvent, context: NSManagedObjectContext) throws -> ProjectionResult {
        let payload = try event.decodePayload(BulkOperationPayload.self)
        var affectedIds: [String] = []

        for taskId in payload.entityIds {
            if let task = fetchTask(byId: taskId, context: context) {
                task.isDeleted = true
                task.modifiedAt = event.timestamp
                affectedIds.append(taskId)
            }
        }

        return .success(event: event, affectedIds: affectedIds, entityType: "task")
    }

    private func projectBulkMoved(_ event: DomainEvent, context: NSManagedObjectContext) throws -> ProjectionResult {
        let payload = try event.decodePayload(BulkOperationPayload.self)
        var affectedIds: [String] = []

        let newList: CDTaskList?
        if let listId = payload.targetListId {
            newList = fetchTaskList(byId: listId, context: context)
        } else {
            newList = nil
        }

        for taskId in payload.entityIds {
            if let task = fetchTask(byId: taskId, context: context) {
                task.list = newList
                task.listId = payload.targetListId
                task.modifiedAt = event.timestamp
                affectedIds.append(taskId)
            }
        }

        return .success(event: event, affectedIds: affectedIds, entityType: "task")
    }

    // MARK: - Fetch Helpers

    private func fetchTask(byId id: String, context: NSManagedObjectContext) -> CDTask? {
        let request = CDTask.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id)
        request.fetchLimit = 1
        return try? context.fetch(request).first
    }

    private func fetchTaskList(byId id: String, context: NSManagedObjectContext) -> CDTaskList? {
        let request = CDTaskList.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id)
        request.fetchLimit = 1
        return try? context.fetch(request).first
    }

    private func fetchTag(byId id: String, context: NSManagedObjectContext) -> CDTag? {
        let request = CDTag.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id)
        request.fetchLimit = 1
        return try? context.fetch(request).first
    }

    private func fetchAttachment(byId id: String, context: NSManagedObjectContext) -> CDAttachmentRef? {
        let request = CDAttachmentRef.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id)
        request.fetchLimit = 1
        return try? context.fetch(request).first
    }
}

// MARK: - Payload Types

/// Payload for TaskList events
private struct TaskListPayload: Codable {
    let id: String
    let name: String?
    let color: String?
    let icon: String?
    let sortOrder: Int?
    let isDefault: Bool?
    let isSmartList: Bool?
    let smartFilter: String?
    let createdAt: Date?
    let modifiedAt: Date?
}

/// Payload for Task events
private struct TaskPayload: Codable {
    let id: String
    let title: String?
    let notes: String?
    let isCompleted: Bool?
    let completedAt: Date?
    let dueDate: Date?
    let reminderDate: Date?
    let priority: Int?
    let sortOrder: Int?
    let listId: String?
    let parentTaskId: String?
    let createdAt: Date?
    let modifiedAt: Date?
}

/// Payload for task completion events
private struct TaskCompletionPayload: Codable {
    let taskId: String
    let completedAt: Date?
}

/// Payload for task flag events
private struct TaskFlagPayload: Codable {
    let taskId: String
}

/// Payload for task reorder events
private struct TaskReorderPayload: Codable {
    let listId: String
    let taskIds: [String]
}

/// Payload for list reorder events
private struct ListReorderPayload: Codable {
    let listIds: [String]
}

/// Payload for subtask events
private struct SubtaskPayload: Codable {
    let parentTaskId: String
    let subtaskId: String
}

/// Payload for Tag events
private struct TagPayload: Codable {
    let id: String
    let name: String?
    let color: String?
    let createdAt: Date?
}

/// Payload for attachment status changes
private struct AttachmentStatusPayload: Codable {
    let attachmentId: String
    let status: UploadStatusValue
    let remoteUrl: String?

    enum UploadStatusValue: Int, Codable {
        case pending = 0
        case uploading = 1
        case completed = 2
        case failed = 3
    }
}
