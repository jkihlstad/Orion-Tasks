//
//  PersistenceController.swift
//  TasksApp
//
//  CoreData stack with singleton, app group support, preview container, and background context
//

import CoreData
import Foundation

/// PersistenceController manages the CoreData stack for the Tasks app
/// Provides thread-safe access to managed object contexts and supports app group sharing
final class PersistenceController: @unchecked Sendable {

    // MARK: - Singleton

    /// Shared singleton instance for production use
    static let shared = PersistenceController()

    /// Preview instance for SwiftUI previews with in-memory store
    static var preview: PersistenceController = {
        let controller = PersistenceController(inMemory: true)

        // Populate with sample data for previews
        let context = controller.container.viewContext

        // Create sample task list
        let sampleList = CDTaskList(context: context)
        sampleList.id = UUID().uuidString
        sampleList.name = "My Tasks"
        sampleList.color = "#007AFF"
        sampleList.icon = "list.bullet"
        sampleList.createdAt = Date()
        sampleList.modifiedAt = Date()
        sampleList.sortOrder = 0
        sampleList.isDefault = true

        // Create sample tasks
        for i in 0..<5 {
            let task = CDTask(context: context)
            task.id = UUID().uuidString
            task.title = "Sample Task \(i + 1)"
            task.notes = "This is a sample task for preview purposes"
            task.isCompleted = i % 2 == 0
            task.priority = Int16(i % 4)
            task.createdAt = Date()
            task.modifiedAt = Date()
            task.sortOrder = Int32(i)
            task.list = sampleList
        }

        // Create sample tags
        let tag = CDTag(context: context)
        tag.id = UUID().uuidString
        tag.name = "Important"
        tag.color = "#FF3B30"
        tag.createdAt = Date()

        do {
            try context.save()
        } catch {
            let nsError = error as NSError
            fatalError("Failed to save preview context: \(nsError), \(nsError.userInfo)")
        }

        return controller
    }()

    // MARK: - Properties

    /// The persistent container for CoreData
    let container: NSPersistentContainer

    /// App group identifier for sharing data with extensions/widgets
    private static let appGroupIdentifier = "group.com.orion.tasks"

    /// CoreData model name
    private static let modelName = "TasksModel"

    // MARK: - Initialization

    /// Initialize the persistence controller
    /// - Parameter inMemory: If true, uses in-memory store (for previews/testing)
    init(inMemory: Bool = false) {
        // Create the managed object model programmatically
        let model = Self.createManagedObjectModel()

        container = NSPersistentContainer(name: Self.modelName, managedObjectModel: model)

        // Configure store description
        if inMemory {
            container.persistentStoreDescriptions.first?.url = URL(fileURLWithPath: "/dev/null")
        } else {
            // Use app group container for sharing with extensions
            if let appGroupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Self.appGroupIdentifier) {
                let storeURL = appGroupURL.appendingPathComponent("\(Self.modelName).sqlite")

                let description = NSPersistentStoreDescription(url: storeURL)
                description.shouldMigrateStoreAutomatically = true
                description.shouldInferMappingModelAutomatically = true

                // Enable persistent history tracking for sync
                description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
                description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)

                container.persistentStoreDescriptions = [description]
            }
        }

        // Load persistent stores
        container.loadPersistentStores { storeDescription, error in
            if let error = error as NSError? {
                // In production, handle this more gracefully
                // Consider logging, attempting recovery, or showing user alert
                fatalError("Failed to load persistent store: \(error), \(error.userInfo)")
            }
        }

        // Configure view context
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        container.viewContext.name = "viewContext"

        // Enable query generation for consistent reads
        try? container.viewContext.setQueryGenerationFrom(.current)
    }

    // MARK: - Context Management

    /// The main view context for UI operations (main thread only)
    var viewContext: NSManagedObjectContext {
        container.viewContext
    }

    /// Creates a new background context for sync operations
    /// - Returns: A new managed object context configured for background operations
    func newBackgroundContext() -> NSManagedObjectContext {
        let context = container.newBackgroundContext()
        context.automaticallyMergesChangesFromParent = true
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        context.name = "backgroundContext-\(UUID().uuidString.prefix(8))"
        return context
    }

    /// Performs a task on the background context
    /// - Parameter block: The work to perform
    func performBackgroundTask(_ block: @escaping (NSManagedObjectContext) -> Void) {
        container.performBackgroundTask { context in
            context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
            block(context)
        }
    }

    /// Performs a task on the background context and waits for completion
    /// - Parameter block: The work to perform
    /// - Returns: The result of the block
    func performBackgroundTaskAndWait<T>(_ block: (NSManagedObjectContext) throws -> T) throws -> T {
        let context = newBackgroundContext()
        var result: T!
        var thrownError: Error?

        context.performAndWait {
            do {
                result = try block(context)
            } catch {
                thrownError = error
            }
        }

        if let error = thrownError {
            throw error
        }

        return result
    }

    // MARK: - Save Operations

    /// Saves the view context if there are changes
    func save() {
        let context = viewContext
        guard context.hasChanges else { return }

        context.performAndWait {
            do {
                try context.save()
            } catch {
                let nsError = error as NSError
                // In production, log this error and potentially attempt recovery
                print("Error saving view context: \(nsError), \(nsError.userInfo)")
            }
        }
    }

    /// Saves any context if there are changes
    /// - Parameter context: The context to save
    func save(context: NSManagedObjectContext) {
        guard context.hasChanges else { return }

        context.performAndWait {
            do {
                try context.save()
            } catch {
                let nsError = error as NSError
                print("Error saving context: \(nsError), \(nsError.userInfo)")
            }
        }
    }

    // MARK: - Batch Operations

    /// Executes a batch delete request
    /// - Parameters:
    ///   - fetchRequest: The fetch request defining objects to delete
    ///   - context: The context to use (defaults to background context)
    /// - Returns: The batch delete result
    @discardableResult
    func batchDelete<T: NSManagedObject>(
        fetchRequest: NSFetchRequest<T>,
        context: NSManagedObjectContext? = nil
    ) throws -> NSBatchDeleteResult {
        let ctx = context ?? newBackgroundContext()

        var result: NSBatchDeleteResult!
        var thrownError: Error?

        ctx.performAndWait {
            do {
                let deleteRequest = NSBatchDeleteRequest(fetchRequest: fetchRequest as! NSFetchRequest<NSFetchRequestResult>)
                deleteRequest.resultType = .resultTypeObjectIDs

                result = try ctx.execute(deleteRequest) as? NSBatchDeleteResult

                // Merge changes to view context
                if let objectIDs = result.result as? [NSManagedObjectID] {
                    let changes = [NSDeletedObjectsKey: objectIDs]
                    NSManagedObjectContext.mergeChanges(fromRemoteContextSave: changes, into: [self.viewContext])
                }
            } catch {
                thrownError = error
            }
        }

        if let error = thrownError {
            throw error
        }

        return result
    }

    /// Executes a batch update request
    /// - Parameters:
    ///   - entityName: The entity name to update
    ///   - propertiesToUpdate: Dictionary of property names to new values
    ///   - predicate: Optional predicate to filter objects
    ///   - context: The context to use
    /// - Returns: The batch update result
    @discardableResult
    func batchUpdate(
        entityName: String,
        propertiesToUpdate: [String: Any],
        predicate: NSPredicate? = nil,
        context: NSManagedObjectContext? = nil
    ) throws -> NSBatchUpdateResult {
        let ctx = context ?? newBackgroundContext()

        var result: NSBatchUpdateResult!
        var thrownError: Error?

        ctx.performAndWait {
            do {
                let updateRequest = NSBatchUpdateRequest(entityName: entityName)
                updateRequest.propertiesToUpdate = propertiesToUpdate
                updateRequest.predicate = predicate
                updateRequest.resultType = .updatedObjectIDsResultType

                result = try ctx.execute(updateRequest) as? NSBatchUpdateResult

                // Merge changes to view context
                if let objectIDs = result.result as? [NSManagedObjectID] {
                    let changes = [NSUpdatedObjectsKey: objectIDs]
                    NSManagedObjectContext.mergeChanges(fromRemoteContextSave: changes, into: [self.viewContext])
                }
            } catch {
                thrownError = error
            }
        }

        if let error = thrownError {
            throw error
        }

        return result
    }

    // MARK: - Persistent History

    /// Clears persistent history older than the specified date
    /// - Parameter date: The cutoff date
    func clearPersistentHistory(before date: Date) {
        performBackgroundTask { context in
            let deleteRequest = NSPersistentHistoryChangeRequest.deleteHistory(before: date)
            do {
                try context.execute(deleteRequest)
            } catch {
                print("Error clearing persistent history: \(error)")
            }
        }
    }

    // MARK: - Model Creation

    /// Creates the managed object model programmatically
    /// This replaces the .xcdatamodeld file
    private static func createManagedObjectModel() -> NSManagedObjectModel {
        let model = NSManagedObjectModel()

        // Create all entities
        let taskEntity = createTaskEntity()
        let taskListEntity = createTaskListEntity()
        let tagEntity = createTagEntity()
        let attachmentEntity = createAttachmentEntity()
        let pendingEventEntity = createPendingEventEntity()
        let syncStateEntity = createSyncStateEntity()
        let calendarLinkEntity = createCalendarLinkEntity()

        // Set up relationships
        setupRelationships(
            taskEntity: taskEntity,
            taskListEntity: taskListEntity,
            tagEntity: tagEntity,
            attachmentEntity: attachmentEntity,
            calendarLinkEntity: calendarLinkEntity
        )

        model.entities = [
            taskEntity,
            taskListEntity,
            tagEntity,
            attachmentEntity,
            pendingEventEntity,
            syncStateEntity,
            calendarLinkEntity
        ]

        return model
    }

    // MARK: - Entity Creation Helpers

    private static func createTaskEntity() -> NSEntityDescription {
        let entity = NSEntityDescription()
        entity.name = "CDTask"
        entity.managedObjectClassName = "CDTask"

        var properties: [NSPropertyDescription] = []

        // Primary identifier
        properties.append(createAttribute(name: "id", type: .stringAttributeType, optional: false))

        // Content
        properties.append(createAttribute(name: "title", type: .stringAttributeType, optional: false))
        properties.append(createAttribute(name: "notes", type: .stringAttributeType, optional: true))

        // Status
        properties.append(createAttribute(name: "isCompleted", type: .booleanAttributeType, optional: false, defaultValue: false))
        properties.append(createAttribute(name: "completedAt", type: .dateAttributeType, optional: true))

        // Scheduling
        properties.append(createAttribute(name: "dueDate", type: .dateAttributeType, optional: true))
        properties.append(createAttribute(name: "startDate", type: .dateAttributeType, optional: true))
        properties.append(createAttribute(name: "reminderDate", type: .dateAttributeType, optional: true))

        // Recurrence (stored as JSON string)
        properties.append(createAttribute(name: "recurrenceRule", type: .stringAttributeType, optional: true))

        // Priority (0 = none, 1 = low, 2 = medium, 3 = high)
        properties.append(createAttribute(name: "priority", type: .integer16AttributeType, optional: false, defaultValue: 0))

        // Organization
        properties.append(createAttribute(name: "sortOrder", type: .integer32AttributeType, optional: false, defaultValue: 0))
        properties.append(createAttribute(name: "listId", type: .stringAttributeType, optional: true))

        // Subtasks
        properties.append(createAttribute(name: "parentTaskId", type: .stringAttributeType, optional: true))
        properties.append(createAttribute(name: "subtaskIds", type: .transformableAttributeType, optional: true))

        // Metadata
        properties.append(createAttribute(name: "createdAt", type: .dateAttributeType, optional: false))
        properties.append(createAttribute(name: "modifiedAt", type: .dateAttributeType, optional: false))
        properties.append(createAttribute(name: "createdBy", type: .stringAttributeType, optional: true))

        // Sync metadata
        properties.append(createAttribute(name: "serverVersion", type: .integer64AttributeType, optional: true))
        properties.append(createAttribute(name: "syncStatus", type: .integer16AttributeType, optional: false, defaultValue: 0))
        properties.append(createAttribute(name: "lastSyncedAt", type: .dateAttributeType, optional: true))
        properties.append(createAttribute(name: "isDeleted", type: .booleanAttributeType, optional: false, defaultValue: false))

        // Location
        properties.append(createAttribute(name: "latitude", type: .doubleAttributeType, optional: true))
        properties.append(createAttribute(name: "longitude", type: .doubleAttributeType, optional: true))
        properties.append(createAttribute(name: "locationName", type: .stringAttributeType, optional: true))
        properties.append(createAttribute(name: "locationRadius", type: .doubleAttributeType, optional: true))

        // URL
        properties.append(createAttribute(name: "url", type: .stringAttributeType, optional: true))

        // Energy level (for AI scheduling)
        properties.append(createAttribute(name: "energyLevel", type: .integer16AttributeType, optional: true))

        // Estimated duration in minutes
        properties.append(createAttribute(name: "estimatedDuration", type: .integer32AttributeType, optional: true))

        entity.properties = properties

        // Create index on id
        let idIndex = NSFetchIndexDescription(name: "byId", elements: [
            NSFetchIndexElementDescription(property: properties.first { $0.name == "id" } as! NSAttributeDescription, collationType: .binary)
        ])

        // Create index on listId
        let listIndex = NSFetchIndexDescription(name: "byListId", elements: [
            NSFetchIndexElementDescription(property: properties.first { $0.name == "listId" } as! NSAttributeDescription, collationType: .binary)
        ])

        // Create index on dueDate
        let dueDateIndex = NSFetchIndexDescription(name: "byDueDate", elements: [
            NSFetchIndexElementDescription(property: properties.first { $0.name == "dueDate" } as! NSAttributeDescription, collationType: .binary)
        ])

        entity.indexes = [idIndex, listIndex, dueDateIndex]

        return entity
    }

    private static func createTaskListEntity() -> NSEntityDescription {
        let entity = NSEntityDescription()
        entity.name = "CDTaskList"
        entity.managedObjectClassName = "CDTaskList"

        var properties: [NSPropertyDescription] = []

        // Primary identifier
        properties.append(createAttribute(name: "id", type: .stringAttributeType, optional: false))

        // Content
        properties.append(createAttribute(name: "name", type: .stringAttributeType, optional: false))
        properties.append(createAttribute(name: "icon", type: .stringAttributeType, optional: true))
        properties.append(createAttribute(name: "color", type: .stringAttributeType, optional: true))

        // Organization
        properties.append(createAttribute(name: "sortOrder", type: .integer32AttributeType, optional: false, defaultValue: 0))
        properties.append(createAttribute(name: "isDefault", type: .booleanAttributeType, optional: false, defaultValue: false))

        // Smart list filter (stored as JSON)
        properties.append(createAttribute(name: "smartFilter", type: .stringAttributeType, optional: true))
        properties.append(createAttribute(name: "isSmartList", type: .booleanAttributeType, optional: false, defaultValue: false))

        // Metadata
        properties.append(createAttribute(name: "createdAt", type: .dateAttributeType, optional: false))
        properties.append(createAttribute(name: "modifiedAt", type: .dateAttributeType, optional: false))

        // Sync metadata
        properties.append(createAttribute(name: "serverVersion", type: .integer64AttributeType, optional: true))
        properties.append(createAttribute(name: "syncStatus", type: .integer16AttributeType, optional: false, defaultValue: 0))
        properties.append(createAttribute(name: "lastSyncedAt", type: .dateAttributeType, optional: true))
        properties.append(createAttribute(name: "isDeleted", type: .booleanAttributeType, optional: false, defaultValue: false))

        // Sharing
        properties.append(createAttribute(name: "ownerId", type: .stringAttributeType, optional: true))
        properties.append(createAttribute(name: "sharedWith", type: .transformableAttributeType, optional: true))

        entity.properties = properties

        return entity
    }

    private static func createTagEntity() -> NSEntityDescription {
        let entity = NSEntityDescription()
        entity.name = "CDTag"
        entity.managedObjectClassName = "CDTag"

        var properties: [NSPropertyDescription] = []

        properties.append(createAttribute(name: "id", type: .stringAttributeType, optional: false))
        properties.append(createAttribute(name: "name", type: .stringAttributeType, optional: false))
        properties.append(createAttribute(name: "color", type: .stringAttributeType, optional: true))
        properties.append(createAttribute(name: "createdAt", type: .dateAttributeType, optional: false))
        properties.append(createAttribute(name: "modifiedAt", type: .dateAttributeType, optional: true))

        // Sync metadata
        properties.append(createAttribute(name: "serverVersion", type: .integer64AttributeType, optional: true))
        properties.append(createAttribute(name: "syncStatus", type: .integer16AttributeType, optional: false, defaultValue: 0))
        properties.append(createAttribute(name: "isDeleted", type: .booleanAttributeType, optional: false, defaultValue: false))

        entity.properties = properties

        return entity
    }

    private static func createAttachmentEntity() -> NSEntityDescription {
        let entity = NSEntityDescription()
        entity.name = "CDAttachmentRef"
        entity.managedObjectClassName = "CDAttachmentRef"

        var properties: [NSPropertyDescription] = []

        properties.append(createAttribute(name: "id", type: .stringAttributeType, optional: false))
        properties.append(createAttribute(name: "taskId", type: .stringAttributeType, optional: false))
        properties.append(createAttribute(name: "fileName", type: .stringAttributeType, optional: false))
        properties.append(createAttribute(name: "mimeType", type: .stringAttributeType, optional: true))
        properties.append(createAttribute(name: "fileSize", type: .integer64AttributeType, optional: true))
        properties.append(createAttribute(name: "localPath", type: .stringAttributeType, optional: true))
        properties.append(createAttribute(name: "remoteURL", type: .stringAttributeType, optional: true))
        properties.append(createAttribute(name: "thumbnailPath", type: .stringAttributeType, optional: true))
        properties.append(createAttribute(name: "createdAt", type: .dateAttributeType, optional: false))

        // Upload status
        properties.append(createAttribute(name: "uploadStatus", type: .integer16AttributeType, optional: false, defaultValue: 0))
        properties.append(createAttribute(name: "uploadProgress", type: .doubleAttributeType, optional: true))

        entity.properties = properties

        return entity
    }

    private static func createPendingEventEntity() -> NSEntityDescription {
        let entity = NSEntityDescription()
        entity.name = "CDPendingEvent"
        entity.managedObjectClassName = "CDPendingEvent"

        var properties: [NSPropertyDescription] = []

        // Event identification
        properties.append(createAttribute(name: "id", type: .stringAttributeType, optional: false))
        properties.append(createAttribute(name: "eventType", type: .stringAttributeType, optional: false))

        // Target entity
        properties.append(createAttribute(name: "entityType", type: .stringAttributeType, optional: false))
        properties.append(createAttribute(name: "entityId", type: .stringAttributeType, optional: false))

        // Event payload (JSON)
        properties.append(createAttribute(name: "payload", type: .stringAttributeType, optional: false))

        // Ordering and timing
        properties.append(createAttribute(name: "createdAt", type: .dateAttributeType, optional: false))
        properties.append(createAttribute(name: "sequence", type: .integer64AttributeType, optional: false, defaultValue: 0))

        // Retry tracking
        properties.append(createAttribute(name: "retryCount", type: .integer16AttributeType, optional: false, defaultValue: 0))
        properties.append(createAttribute(name: "lastAttemptAt", type: .dateAttributeType, optional: true))
        properties.append(createAttribute(name: "nextRetryAt", type: .dateAttributeType, optional: true))
        properties.append(createAttribute(name: "errorMessage", type: .stringAttributeType, optional: true))

        // Status
        properties.append(createAttribute(name: "status", type: .integer16AttributeType, optional: false, defaultValue: 0))

        entity.properties = properties

        // Index for processing order
        let processingIndex = NSFetchIndexDescription(name: "byProcessingOrder", elements: [
            NSFetchIndexElementDescription(property: properties.first { $0.name == "status" } as! NSAttributeDescription, collationType: .binary),
            NSFetchIndexElementDescription(property: properties.first { $0.name == "sequence" } as! NSAttributeDescription, collationType: .binary)
        ])

        entity.indexes = [processingIndex]

        return entity
    }

    private static func createSyncStateEntity() -> NSEntityDescription {
        let entity = NSEntityDescription()
        entity.name = "CDSyncState"
        entity.managedObjectClassName = "CDSyncState"

        var properties: [NSPropertyDescription] = []

        // Cursor/version tracking
        properties.append(createAttribute(name: "key", type: .stringAttributeType, optional: false))
        properties.append(createAttribute(name: "cursor", type: .stringAttributeType, optional: true))
        properties.append(createAttribute(name: "serverVersion", type: .integer64AttributeType, optional: true))

        // Sync timing
        properties.append(createAttribute(name: "lastSyncStarted", type: .dateAttributeType, optional: true))
        properties.append(createAttribute(name: "lastSyncCompleted", type: .dateAttributeType, optional: true))
        properties.append(createAttribute(name: "lastSyncError", type: .stringAttributeType, optional: true))

        // Full sync tracking
        properties.append(createAttribute(name: "lastFullSyncAt", type: .dateAttributeType, optional: true))
        properties.append(createAttribute(name: "fullSyncRequired", type: .booleanAttributeType, optional: false, defaultValue: false))

        // Statistics
        properties.append(createAttribute(name: "totalSyncs", type: .integer64AttributeType, optional: false, defaultValue: 0))
        properties.append(createAttribute(name: "failedSyncs", type: .integer64AttributeType, optional: false, defaultValue: 0))

        entity.properties = properties

        return entity
    }

    private static func createCalendarLinkEntity() -> NSEntityDescription {
        let entity = NSEntityDescription()
        entity.name = "CDCalendarLink"
        entity.managedObjectClassName = "CDCalendarLink"

        var properties: [NSPropertyDescription] = []

        properties.append(createAttribute(name: "id", type: .stringAttributeType, optional: false))
        properties.append(createAttribute(name: "taskId", type: .stringAttributeType, optional: false))
        properties.append(createAttribute(name: "calendarEventId", type: .stringAttributeType, optional: false))
        properties.append(createAttribute(name: "calendarId", type: .stringAttributeType, optional: true))

        // Sync direction
        properties.append(createAttribute(name: "syncDirection", type: .integer16AttributeType, optional: false, defaultValue: 0))

        // Tracking
        properties.append(createAttribute(name: "createdAt", type: .dateAttributeType, optional: false))
        properties.append(createAttribute(name: "lastSyncedAt", type: .dateAttributeType, optional: true))
        properties.append(createAttribute(name: "taskModifiedAt", type: .dateAttributeType, optional: true))
        properties.append(createAttribute(name: "eventModifiedAt", type: .dateAttributeType, optional: true))

        entity.properties = properties

        return entity
    }

    private static func setupRelationships(
        taskEntity: NSEntityDescription,
        taskListEntity: NSEntityDescription,
        tagEntity: NSEntityDescription,
        attachmentEntity: NSEntityDescription,
        calendarLinkEntity: NSEntityDescription
    ) {
        // Task -> TaskList (many-to-one)
        let taskToListRelation = NSRelationshipDescription()
        taskToListRelation.name = "list"
        taskToListRelation.destinationEntity = taskListEntity
        taskToListRelation.minCount = 0
        taskToListRelation.maxCount = 1
        taskToListRelation.deleteRule = .nullifyDeleteRule

        // TaskList -> Tasks (one-to-many)
        let listToTasksRelation = NSRelationshipDescription()
        listToTasksRelation.name = "tasks"
        listToTasksRelation.destinationEntity = taskEntity
        listToTasksRelation.minCount = 0
        listToTasksRelation.maxCount = 0 // 0 means to-many
        listToTasksRelation.deleteRule = .cascadeDeleteRule

        taskToListRelation.inverseRelationship = listToTasksRelation
        listToTasksRelation.inverseRelationship = taskToListRelation

        // Task -> Tags (many-to-many)
        let taskToTagsRelation = NSRelationshipDescription()
        taskToTagsRelation.name = "tags"
        taskToTagsRelation.destinationEntity = tagEntity
        taskToTagsRelation.minCount = 0
        taskToTagsRelation.maxCount = 0
        taskToTagsRelation.deleteRule = .nullifyDeleteRule

        // Tags -> Tasks (many-to-many)
        let tagToTasksRelation = NSRelationshipDescription()
        tagToTasksRelation.name = "tasks"
        tagToTasksRelation.destinationEntity = taskEntity
        tagToTasksRelation.minCount = 0
        tagToTasksRelation.maxCount = 0
        tagToTasksRelation.deleteRule = .nullifyDeleteRule

        taskToTagsRelation.inverseRelationship = tagToTasksRelation
        tagToTasksRelation.inverseRelationship = taskToTagsRelation

        // Task -> Attachments (one-to-many)
        let taskToAttachmentsRelation = NSRelationshipDescription()
        taskToAttachmentsRelation.name = "attachments"
        taskToAttachmentsRelation.destinationEntity = attachmentEntity
        taskToAttachmentsRelation.minCount = 0
        taskToAttachmentsRelation.maxCount = 0
        taskToAttachmentsRelation.deleteRule = .cascadeDeleteRule

        // Attachment -> Task (many-to-one)
        let attachmentToTaskRelation = NSRelationshipDescription()
        attachmentToTaskRelation.name = "task"
        attachmentToTaskRelation.destinationEntity = taskEntity
        attachmentToTaskRelation.minCount = 0
        attachmentToTaskRelation.maxCount = 1
        attachmentToTaskRelation.deleteRule = .nullifyDeleteRule

        taskToAttachmentsRelation.inverseRelationship = attachmentToTaskRelation
        attachmentToTaskRelation.inverseRelationship = taskToAttachmentsRelation

        // Task -> CalendarLinks (one-to-many)
        let taskToCalendarLinksRelation = NSRelationshipDescription()
        taskToCalendarLinksRelation.name = "calendarLinks"
        taskToCalendarLinksRelation.destinationEntity = calendarLinkEntity
        taskToCalendarLinksRelation.minCount = 0
        taskToCalendarLinksRelation.maxCount = 0
        taskToCalendarLinksRelation.deleteRule = .cascadeDeleteRule

        // CalendarLink -> Task (many-to-one)
        let calendarLinkToTaskRelation = NSRelationshipDescription()
        calendarLinkToTaskRelation.name = "task"
        calendarLinkToTaskRelation.destinationEntity = taskEntity
        calendarLinkToTaskRelation.minCount = 0
        calendarLinkToTaskRelation.maxCount = 1
        calendarLinkToTaskRelation.deleteRule = .nullifyDeleteRule

        taskToCalendarLinksRelation.inverseRelationship = calendarLinkToTaskRelation
        calendarLinkToTaskRelation.inverseRelationship = taskToCalendarLinksRelation

        // Task -> ParentTask (self-referencing for subtasks)
        let taskToParentRelation = NSRelationshipDescription()
        taskToParentRelation.name = "parentTask"
        taskToParentRelation.destinationEntity = taskEntity
        taskToParentRelation.minCount = 0
        taskToParentRelation.maxCount = 1
        taskToParentRelation.deleteRule = .nullifyDeleteRule

        // Task -> Subtasks (self-referencing)
        let taskToSubtasksRelation = NSRelationshipDescription()
        taskToSubtasksRelation.name = "subtasks"
        taskToSubtasksRelation.destinationEntity = taskEntity
        taskToSubtasksRelation.minCount = 0
        taskToSubtasksRelation.maxCount = 0
        taskToSubtasksRelation.deleteRule = .cascadeDeleteRule

        taskToParentRelation.inverseRelationship = taskToSubtasksRelation
        taskToSubtasksRelation.inverseRelationship = taskToParentRelation

        // Add relationships to entities
        var taskProperties = taskEntity.properties
        taskProperties.append(contentsOf: [
            taskToListRelation,
            taskToTagsRelation,
            taskToAttachmentsRelation,
            taskToCalendarLinksRelation,
            taskToParentRelation,
            taskToSubtasksRelation
        ])
        taskEntity.properties = taskProperties

        var listProperties = taskListEntity.properties
        listProperties.append(listToTasksRelation)
        taskListEntity.properties = listProperties

        var tagProperties = tagEntity.properties
        tagProperties.append(tagToTasksRelation)
        tagEntity.properties = tagProperties

        var attachmentProperties = attachmentEntity.properties
        attachmentProperties.append(attachmentToTaskRelation)
        attachmentEntity.properties = attachmentProperties

        var calendarLinkProperties = calendarLinkEntity.properties
        calendarLinkProperties.append(calendarLinkToTaskRelation)
        calendarLinkEntity.properties = calendarLinkProperties
    }

    private static func createAttribute(
        name: String,
        type: NSAttributeType,
        optional: Bool,
        defaultValue: Any? = nil
    ) -> NSAttributeDescription {
        let attribute = NSAttributeDescription()
        attribute.name = name
        attribute.attributeType = type
        attribute.isOptional = optional

        if let defaultValue = defaultValue {
            attribute.defaultValue = defaultValue
        }

        // Configure transformable type for arrays
        if type == .transformableAttributeType {
            attribute.valueTransformerName = NSValueTransformerName.secureUnarchiveFromDataTransformerName.rawValue
            attribute.attributeValueClassName = "NSArray"
        }

        return attribute
    }
}

// MARK: - Error Types

enum PersistenceError: LocalizedError {
    case saveFailed(Error)
    case fetchFailed(Error)
    case entityNotFound(String)
    case invalidData(String)
    case batchOperationFailed(Error)

    var errorDescription: String? {
        switch self {
        case .saveFailed(let error):
            return "Failed to save: \(error.localizedDescription)"
        case .fetchFailed(let error):
            return "Failed to fetch: \(error.localizedDescription)"
        case .entityNotFound(let id):
            return "Entity not found: \(id)"
        case .invalidData(let message):
            return "Invalid data: \(message)"
        case .batchOperationFailed(let error):
            return "Batch operation failed: \(error.localizedDescription)"
        }
    }
}
