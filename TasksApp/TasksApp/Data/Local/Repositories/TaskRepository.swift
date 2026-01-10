//
//  TaskRepository.swift
//  TasksApp
//
//  Repository for Task CRUD operations with thread-safe CoreData access
//

import CoreData
import Foundation
import Combine

/// Repository for managing Task entities in CoreData
/// Provides thread-safe CRUD operations with batch support and local search
final class TaskRepository: @unchecked Sendable {

    // MARK: - Properties

    private let persistenceController: PersistenceController

    /// Publisher for task changes
    private let taskChangesSubject = PassthroughSubject<TaskChange, Never>()
    var taskChanges: AnyPublisher<TaskChange, Never> {
        taskChangesSubject.eraseToAnyPublisher()
    }

    // MARK: - Initialization

    init(persistenceController: PersistenceController = .shared) {
        self.persistenceController = persistenceController
    }

    // MARK: - Create Operations

    /// Creates a new task
    /// - Parameters:
    ///   - title: Task title
    ///   - notes: Optional notes
    ///   - dueDate: Optional due date
    ///   - priority: Task priority
    ///   - listId: Optional list ID
    ///   - context: Optional context (uses view context if nil)
    /// - Returns: The created task
    @discardableResult
    func createTask(
        title: String,
        notes: String? = nil,
        dueDate: Date? = nil,
        priority: TaskPriority = .none,
        listId: String? = nil,
        context: NSManagedObjectContext? = nil
    ) throws -> CDTask {
        let ctx = context ?? persistenceController.viewContext
        var createdTask: CDTask!
        var thrownError: Error?

        ctx.performAndWait {
            let task = CDTask(context: ctx)
            task.id = UUID().uuidString
            task.title = title
            task.notes = notes
            task.dueDate = dueDate
            task.priority = priority.rawValue
            task.isCompleted = false
            task.createdAt = Date()
            task.modifiedAt = Date()
            task.sortOrder = getNextSortOrder(listId: listId, context: ctx)
            task.listId = listId
            task.syncStatus = SyncStatus.pendingUpload.rawValue

            // Associate with list if provided
            if let listId = listId {
                task.list = fetchListById(listId, context: ctx)
            }

            do {
                try ctx.save()
                createdTask = task
            } catch {
                thrownError = error
            }
        }

        if let error = thrownError {
            throw PersistenceError.saveFailed(error)
        }

        taskChangesSubject.send(.created(createdTask))
        return createdTask
    }

    /// Creates multiple tasks in a batch operation
    /// - Parameters:
    ///   - tasks: Array of task data tuples
    ///   - listId: Optional list ID for all tasks
    /// - Returns: Array of created tasks
    @discardableResult
    func createTasks(
        _ tasks: [(title: String, notes: String?, dueDate: Date?, priority: TaskPriority)],
        listId: String? = nil
    ) throws -> [CDTask] {
        let context = persistenceController.newBackgroundContext()
        var createdTasks: [CDTask] = []
        var thrownError: Error?

        context.performAndWait {
            let list: CDTaskList? = listId.flatMap { fetchListById($0, context: context) }
            var currentSortOrder = getNextSortOrder(listId: listId, context: context)

            for taskData in tasks {
                let task = CDTask(context: context)
                task.id = UUID().uuidString
                task.title = taskData.title
                task.notes = taskData.notes
                task.dueDate = taskData.dueDate
                task.priority = taskData.priority.rawValue
                task.isCompleted = false
                task.createdAt = Date()
                task.modifiedAt = Date()
                task.sortOrder = currentSortOrder
                task.listId = listId
                task.list = list
                task.syncStatus = SyncStatus.pendingUpload.rawValue

                createdTasks.append(task)
                currentSortOrder += 1
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

        createdTasks.forEach { taskChangesSubject.send(.created($0)) }
        return createdTasks
    }

    // MARK: - Read Operations

    /// Fetches a task by ID
    /// - Parameters:
    ///   - id: Task ID
    ///   - context: Optional context
    /// - Returns: The task if found
    func fetchTask(byId id: String, context: NSManagedObjectContext? = nil) -> CDTask? {
        let ctx = context ?? persistenceController.viewContext
        var result: CDTask?

        ctx.performAndWait {
            let request = CDTask.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@ AND isDeleted == NO", id)
            request.fetchLimit = 1

            result = try? ctx.fetch(request).first
        }

        return result
    }

    /// Fetches all tasks with optional filtering
    /// - Parameters:
    ///   - predicate: Optional filter predicate
    ///   - sortDescriptors: Optional sort descriptors
    ///   - limit: Optional fetch limit
    ///   - context: Optional context
    /// - Returns: Array of matching tasks
    func fetchTasks(
        predicate: NSPredicate? = nil,
        sortDescriptors: [NSSortDescriptor]? = nil,
        limit: Int? = nil,
        context: NSManagedObjectContext? = nil
    ) throws -> [CDTask] {
        let ctx = context ?? persistenceController.viewContext
        var tasks: [CDTask] = []
        var thrownError: Error?

        ctx.performAndWait {
            let request = CDTask.fetchRequest()

            // Combine with isDeleted filter
            let deletedPredicate = NSPredicate(format: "isDeleted == NO")
            if let predicate = predicate {
                request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [deletedPredicate, predicate])
            } else {
                request.predicate = deletedPredicate
            }

            request.sortDescriptors = sortDescriptors ?? [
                NSSortDescriptor(key: "sortOrder", ascending: true),
                NSSortDescriptor(key: "createdAt", ascending: false)
            ]

            if let limit = limit {
                request.fetchLimit = limit
            }

            do {
                tasks = try ctx.fetch(request)
            } catch {
                thrownError = error
            }
        }

        if let error = thrownError {
            throw PersistenceError.fetchFailed(error)
        }

        return tasks
    }

    /// Fetches tasks for a specific list
    /// - Parameters:
    ///   - listId: List ID
    ///   - includeCompleted: Whether to include completed tasks
    ///   - context: Optional context
    /// - Returns: Array of tasks in the list
    func fetchTasks(
        forListId listId: String,
        includeCompleted: Bool = true,
        context: NSManagedObjectContext? = nil
    ) throws -> [CDTask] {
        var predicates = [
            NSPredicate(format: "listId == %@", listId)
        ]

        if !includeCompleted {
            predicates.append(NSPredicate(format: "isCompleted == NO"))
        }

        let compoundPredicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)

        return try fetchTasks(
            predicate: compoundPredicate,
            sortDescriptors: [
                NSSortDescriptor(key: "isCompleted", ascending: true),
                NSSortDescriptor(key: "sortOrder", ascending: true)
            ],
            context: context
        )
    }

    /// Fetches incomplete tasks
    func fetchIncompleteTasks(context: NSManagedObjectContext? = nil) throws -> [CDTask] {
        let predicate = NSPredicate(format: "isCompleted == NO")
        return try fetchTasks(
            predicate: predicate,
            sortDescriptors: [
                NSSortDescriptor(key: "dueDate", ascending: true),
                NSSortDescriptor(key: "priority", ascending: false),
                NSSortDescriptor(key: "sortOrder", ascending: true)
            ],
            context: context
        )
    }

    /// Fetches tasks due today
    func fetchTasksDueToday(context: NSManagedObjectContext? = nil) throws -> [CDTask] {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!

        let predicate = NSPredicate(
            format: "dueDate >= %@ AND dueDate < %@ AND isCompleted == NO",
            startOfDay as NSDate,
            endOfDay as NSDate
        )

        return try fetchTasks(
            predicate: predicate,
            sortDescriptors: [
                NSSortDescriptor(key: "dueDate", ascending: true),
                NSSortDescriptor(key: "priority", ascending: false)
            ],
            context: context
        )
    }

    /// Fetches overdue tasks
    func fetchOverdueTasks(context: NSManagedObjectContext? = nil) throws -> [CDTask] {
        let now = Date()
        let predicate = NSPredicate(
            format: "dueDate < %@ AND isCompleted == NO",
            now as NSDate
        )

        return try fetchTasks(
            predicate: predicate,
            sortDescriptors: [
                NSSortDescriptor(key: "dueDate", ascending: true),
                NSSortDescriptor(key: "priority", ascending: false)
            ],
            context: context
        )
    }

    /// Fetches tasks for a date range
    func fetchTasks(
        from startDate: Date,
        to endDate: Date,
        includeCompleted: Bool = true,
        context: NSManagedObjectContext? = nil
    ) throws -> [CDTask] {
        var predicates = [
            NSPredicate(format: "dueDate >= %@ AND dueDate <= %@", startDate as NSDate, endDate as NSDate)
        ]

        if !includeCompleted {
            predicates.append(NSPredicate(format: "isCompleted == NO"))
        }

        let compoundPredicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)

        return try fetchTasks(
            predicate: compoundPredicate,
            sortDescriptors: [
                NSSortDescriptor(key: "dueDate", ascending: true),
                NSSortDescriptor(key: "priority", ascending: false)
            ],
            context: context
        )
    }

    /// Fetches tasks with a specific priority
    func fetchTasks(
        withPriority priority: TaskPriority,
        context: NSManagedObjectContext? = nil
    ) throws -> [CDTask] {
        let predicate = NSPredicate(format: "priority == %d AND isCompleted == NO", priority.rawValue)
        return try fetchTasks(predicate: predicate, context: context)
    }

    /// Fetches subtasks for a parent task
    func fetchSubtasks(
        forParentId parentId: String,
        context: NSManagedObjectContext? = nil
    ) throws -> [CDTask] {
        let predicate = NSPredicate(format: "parentTaskId == %@", parentId)
        return try fetchTasks(
            predicate: predicate,
            sortDescriptors: [NSSortDescriptor(key: "sortOrder", ascending: true)],
            context: context
        )
    }

    /// Fetches tasks pending sync
    func fetchTasksPendingSync(context: NSManagedObjectContext? = nil) throws -> [CDTask] {
        let predicate = NSPredicate(format: "syncStatus == %d", SyncStatus.pendingUpload.rawValue)
        return try fetchTasks(
            predicate: predicate,
            sortDescriptors: [NSSortDescriptor(key: "modifiedAt", ascending: true)],
            context: context
        )
    }

    /// Count tasks matching predicate
    func countTasks(predicate: NSPredicate? = nil, context: NSManagedObjectContext? = nil) -> Int {
        let ctx = context ?? persistenceController.viewContext
        var count = 0

        ctx.performAndWait {
            let request = CDTask.fetchRequest()

            let deletedPredicate = NSPredicate(format: "isDeleted == NO")
            if let predicate = predicate {
                request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [deletedPredicate, predicate])
            } else {
                request.predicate = deletedPredicate
            }

            count = (try? ctx.count(for: request)) ?? 0
        }

        return count
    }

    // MARK: - Search Operations

    /// Searches tasks by title and notes
    /// - Parameters:
    ///   - query: Search query
    ///   - listId: Optional list ID to filter by
    ///   - includeCompleted: Whether to include completed tasks
    ///   - context: Optional context
    /// - Returns: Array of matching tasks
    func searchTasks(
        query: String,
        listId: String? = nil,
        includeCompleted: Bool = true,
        context: NSManagedObjectContext? = nil
    ) throws -> [CDTask] {
        guard !query.isEmpty else {
            return try fetchTasks(context: context)
        }

        var predicates: [NSPredicate] = [
            NSPredicate(format: "title CONTAINS[cd] %@ OR notes CONTAINS[cd] %@", query, query)
        ]

        if let listId = listId {
            predicates.append(NSPredicate(format: "listId == %@", listId))
        }

        if !includeCompleted {
            predicates.append(NSPredicate(format: "isCompleted == NO"))
        }

        let compoundPredicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)

        return try fetchTasks(
            predicate: compoundPredicate,
            sortDescriptors: [
                NSSortDescriptor(key: "modifiedAt", ascending: false)
            ],
            context: context
        )
    }

    /// Searches tasks with advanced filters
    func searchTasks(
        query: String? = nil,
        listIds: [String]? = nil,
        tagIds: [String]? = nil,
        priorities: [TaskPriority]? = nil,
        dueDateRange: (start: Date, end: Date)? = nil,
        isCompleted: Bool? = nil,
        hasReminder: Bool? = nil,
        context: NSManagedObjectContext? = nil
    ) throws -> [CDTask] {
        var predicates: [NSPredicate] = []

        if let query = query, !query.isEmpty {
            predicates.append(NSPredicate(format: "title CONTAINS[cd] %@ OR notes CONTAINS[cd] %@", query, query))
        }

        if let listIds = listIds, !listIds.isEmpty {
            predicates.append(NSPredicate(format: "listId IN %@", listIds))
        }

        if let tagIds = tagIds, !tagIds.isEmpty {
            predicates.append(NSPredicate(format: "ANY tags.id IN %@", tagIds))
        }

        if let priorities = priorities, !priorities.isEmpty {
            let priorityValues = priorities.map { $0.rawValue }
            predicates.append(NSPredicate(format: "priority IN %@", priorityValues))
        }

        if let range = dueDateRange {
            predicates.append(NSPredicate(
                format: "dueDate >= %@ AND dueDate <= %@",
                range.start as NSDate,
                range.end as NSDate
            ))
        }

        if let isCompleted = isCompleted {
            predicates.append(NSPredicate(format: "isCompleted == %@", NSNumber(value: isCompleted)))
        }

        if let hasReminder = hasReminder {
            if hasReminder {
                predicates.append(NSPredicate(format: "reminderDate != nil"))
            } else {
                predicates.append(NSPredicate(format: "reminderDate == nil"))
            }
        }

        let compoundPredicate = predicates.isEmpty
            ? nil
            : NSCompoundPredicate(andPredicateWithSubpredicates: predicates)

        return try fetchTasks(
            predicate: compoundPredicate,
            sortDescriptors: [
                NSSortDescriptor(key: "dueDate", ascending: true),
                NSSortDescriptor(key: "priority", ascending: false),
                NSSortDescriptor(key: "modifiedAt", ascending: false)
            ],
            context: context
        )
    }

    // MARK: - Update Operations

    /// Updates a task
    /// - Parameters:
    ///   - id: Task ID
    ///   - updates: Closure to perform updates
    /// - Returns: The updated task
    @discardableResult
    func updateTask(
        id: String,
        updates: @escaping (CDTask) -> Void
    ) throws -> CDTask {
        let context = persistenceController.viewContext
        var updatedTask: CDTask?
        var thrownError: Error?

        context.performAndWait {
            guard let task = fetchTask(byId: id, context: context) else {
                thrownError = PersistenceError.entityNotFound(id)
                return
            }

            updates(task)
            task.modifiedAt = Date()
            task.syncStatus = SyncStatus.pendingUpload.rawValue

            do {
                try context.save()
                updatedTask = task
            } catch {
                thrownError = error
            }
        }

        if let error = thrownError {
            throw error
        }

        guard let task = updatedTask else {
            throw PersistenceError.entityNotFound(id)
        }

        taskChangesSubject.send(.updated(task))
        return task
    }

    /// Batch update tasks
    /// - Parameters:
    ///   - ids: Task IDs to update
    ///   - updates: Closure to perform updates on each task
    func updateTasks(
        ids: [String],
        updates: @escaping (CDTask) -> Void
    ) throws {
        let context = persistenceController.newBackgroundContext()
        var thrownError: Error?

        context.performAndWait {
            let request = CDTask.fetchRequest()
            request.predicate = NSPredicate(format: "id IN %@ AND isDeleted == NO", ids)

            do {
                let tasks = try context.fetch(request)
                for task in tasks {
                    updates(task)
                    task.modifiedAt = Date()
                    task.syncStatus = SyncStatus.pendingUpload.rawValue
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

    /// Marks a task as completed
    @discardableResult
    func completeTask(id: String, completedAt: Date = Date()) throws -> CDTask {
        return try updateTask(id: id) { task in
            task.isCompleted = true
            task.completedAt = completedAt
        }
    }

    /// Marks a task as incomplete
    @discardableResult
    func uncompleteTask(id: String) throws -> CDTask {
        return try updateTask(id: id) { task in
            task.isCompleted = false
            task.completedAt = nil
        }
    }

    /// Toggles task completion status
    @discardableResult
    func toggleTaskCompletion(id: String) throws -> CDTask {
        let context = persistenceController.viewContext
        var updatedTask: CDTask?
        var thrownError: Error?

        context.performAndWait {
            guard let task = fetchTask(byId: id, context: context) else {
                thrownError = PersistenceError.entityNotFound(id)
                return
            }

            task.isCompleted.toggle()
            task.completedAt = task.isCompleted ? Date() : nil
            task.modifiedAt = Date()
            task.syncStatus = SyncStatus.pendingUpload.rawValue

            do {
                try context.save()
                updatedTask = task
            } catch {
                thrownError = error
            }
        }

        if let error = thrownError {
            throw error
        }

        guard let task = updatedTask else {
            throw PersistenceError.entityNotFound(id)
        }

        taskChangesSubject.send(.updated(task))
        return task
    }

    /// Moves a task to a different list
    @discardableResult
    func moveTask(id: String, toListId listId: String?) throws -> CDTask {
        return try updateTask(id: id) { task in
            task.listId = listId
            if let listId = listId {
                task.list = self.fetchListById(listId, context: task.managedObjectContext!)
            } else {
                task.list = nil
            }
            task.sortOrder = self.getNextSortOrder(listId: listId, context: task.managedObjectContext!)
        }
    }

    /// Reorders tasks within a list
    func reorderTasks(ids: [String], inListId listId: String?) throws {
        let context = persistenceController.newBackgroundContext()
        var thrownError: Error?

        context.performAndWait {
            let request = CDTask.fetchRequest()
            request.predicate = NSPredicate(format: "id IN %@", ids)

            do {
                let tasks = try context.fetch(request)
                let taskDict = Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0) })

                for (index, id) in ids.enumerated() {
                    if let task = taskDict[id] {
                        task.sortOrder = Int32(index)
                        task.modifiedAt = Date()
                        task.syncStatus = SyncStatus.pendingUpload.rawValue
                    }
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

    /// Sets task priority
    @discardableResult
    func setTaskPriority(id: String, priority: TaskPriority) throws -> CDTask {
        return try updateTask(id: id) { task in
            task.priority = priority.rawValue
        }
    }

    /// Sets task due date
    @discardableResult
    func setTaskDueDate(id: String, dueDate: Date?) throws -> CDTask {
        return try updateTask(id: id) { task in
            task.dueDate = dueDate
        }
    }

    /// Adds a tag to a task
    func addTag(tagId: String, toTaskId taskId: String) throws {
        let context = persistenceController.viewContext

        context.performAndWait {
            guard let task = fetchTask(byId: taskId, context: context) else { return }

            let tagRequest = CDTag.fetchRequest()
            tagRequest.predicate = NSPredicate(format: "id == %@", tagId)
            tagRequest.fetchLimit = 1

            if let tag = try? context.fetch(tagRequest).first {
                task.addToTags(tag)
                task.modifiedAt = Date()
                task.syncStatus = SyncStatus.pendingUpload.rawValue
                try? context.save()
            }
        }
    }

    /// Removes a tag from a task
    func removeTag(tagId: String, fromTaskId taskId: String) throws {
        let context = persistenceController.viewContext

        context.performAndWait {
            guard let task = fetchTask(byId: taskId, context: context) else { return }

            if let tag = task.tagsArray.first(where: { $0.id == tagId }) {
                task.removeFromTags(tag)
                task.modifiedAt = Date()
                task.syncStatus = SyncStatus.pendingUpload.rawValue
                try? context.save()
            }
        }
    }

    // MARK: - Delete Operations

    /// Soft deletes a task (marks as deleted)
    func deleteTask(id: String) throws {
        let context = persistenceController.viewContext
        var thrownError: Error?

        context.performAndWait {
            guard let task = fetchTask(byId: id, context: context) else {
                thrownError = PersistenceError.entityNotFound(id)
                return
            }

            task.isDeleted = true
            task.modifiedAt = Date()
            task.syncStatus = SyncStatus.pendingUpload.rawValue

            do {
                try context.save()
                taskChangesSubject.send(.deleted(id))
            } catch {
                thrownError = error
            }
        }

        if let error = thrownError {
            throw error
        }
    }

    /// Soft deletes multiple tasks
    func deleteTasks(ids: [String]) throws {
        let context = persistenceController.newBackgroundContext()
        var thrownError: Error?

        context.performAndWait {
            let request = CDTask.fetchRequest()
            request.predicate = NSPredicate(format: "id IN %@", ids)

            do {
                let tasks = try context.fetch(request)
                for task in tasks {
                    task.isDeleted = true
                    task.modifiedAt = Date()
                    task.syncStatus = SyncStatus.pendingUpload.rawValue
                }
                try context.save()
            } catch {
                thrownError = error
            }
        }

        if let error = thrownError {
            throw PersistenceError.saveFailed(error)
        }

        ids.forEach { taskChangesSubject.send(.deleted($0)) }
    }

    /// Permanently deletes a task (hard delete)
    func permanentlyDeleteTask(id: String) throws {
        let context = persistenceController.viewContext
        var thrownError: Error?

        context.performAndWait {
            let request = CDTask.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", id)
            request.fetchLimit = 1

            do {
                if let task = try context.fetch(request).first {
                    context.delete(task)
                    try context.save()
                }
            } catch {
                thrownError = error
            }
        }

        if let error = thrownError {
            throw PersistenceError.saveFailed(error)
        }

        taskChangesSubject.send(.deleted(id))
    }

    /// Batch delete completed tasks older than specified date
    func deleteCompletedTasks(olderThan date: Date) throws {
        let request = CDTask.fetchRequest()
        request.predicate = NSPredicate(
            format: "isCompleted == YES AND completedAt < %@",
            date as NSDate
        )

        try persistenceController.batchDelete(fetchRequest: request)
    }

    /// Purges all soft-deleted tasks (hard delete)
    func purgeDeletedTasks() throws {
        let request = CDTask.fetchRequest()
        request.predicate = NSPredicate(format: "isDeleted == YES")

        try persistenceController.batchDelete(fetchRequest: request)
    }

    // MARK: - Sync Operations

    /// Marks tasks as synced
    func markTasksAsSynced(ids: [String], serverVersion: Int64? = nil) throws {
        let context = persistenceController.newBackgroundContext()
        var thrownError: Error?

        context.performAndWait {
            let request = CDTask.fetchRequest()
            request.predicate = NSPredicate(format: "id IN %@", ids)

            do {
                let tasks = try context.fetch(request)
                let now = Date()
                for task in tasks {
                    task.syncStatus = SyncStatus.synced.rawValue
                    task.lastSyncedAt = now
                    if let version = serverVersion {
                        task.serverVersion = NSNumber(value: version)
                    }
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

    /// Updates task from server data (for sync)
    func updateFromServer(
        id: String,
        serverData: [String: Any],
        serverVersion: Int64,
        context: NSManagedObjectContext? = nil
    ) throws {
        let ctx = context ?? persistenceController.newBackgroundContext()
        var thrownError: Error?

        ctx.performAndWait {
            let task: CDTask
            if let existingTask = fetchTask(byId: id, context: ctx) {
                task = existingTask
            } else {
                task = CDTask(context: ctx)
                task.id = id
                task.createdAt = Date()
            }

            // Update fields from server data
            if let title = serverData["title"] as? String {
                task.title = title
            }
            if let notes = serverData["notes"] as? String {
                task.notes = notes
            }
            if let isCompleted = serverData["isCompleted"] as? Bool {
                task.isCompleted = isCompleted
            }
            if let priority = serverData["priority"] as? Int16 {
                task.priority = priority
            }
            if let dueDate = serverData["dueDate"] as? Date {
                task.dueDate = dueDate
            }
            if let listId = serverData["listId"] as? String {
                task.listId = listId
            }

            task.serverVersion = NSNumber(value: serverVersion)
            task.syncStatus = SyncStatus.synced.rawValue
            task.lastSyncedAt = Date()
            task.modifiedAt = Date()

            do {
                try ctx.save()
            } catch {
                thrownError = error
            }
        }

        if let error = thrownError {
            throw PersistenceError.saveFailed(error)
        }
    }

    // MARK: - Helper Methods

    private func getNextSortOrder(listId: String?, context: NSManagedObjectContext) -> Int32 {
        let request = CDTask.fetchRequest()

        if let listId = listId {
            request.predicate = NSPredicate(format: "listId == %@ AND isDeleted == NO", listId)
        } else {
            request.predicate = NSPredicate(format: "listId == nil AND isDeleted == NO")
        }

        request.sortDescriptors = [NSSortDescriptor(key: "sortOrder", ascending: false)]
        request.fetchLimit = 1

        if let maxTask = try? context.fetch(request).first {
            return maxTask.sortOrder + 1
        }

        return 0
    }

    private func fetchListById(_ id: String, context: NSManagedObjectContext) -> CDTaskList? {
        let request = CDTaskList.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id)
        request.fetchLimit = 1
        return try? context.fetch(request).first
    }
}

// MARK: - Task Change Types

enum TaskChange {
    case created(CDTask)
    case updated(CDTask)
    case deleted(String)
}

// MARK: - Fetch Request Builder

extension TaskRepository {

    /// Builder for constructing complex task queries
    struct QueryBuilder {
        private var predicates: [NSPredicate] = []
        private var sortDescriptors: [NSSortDescriptor] = []
        private var fetchLimit: Int?

        func withListId(_ listId: String) -> QueryBuilder {
            var builder = self
            builder.predicates.append(NSPredicate(format: "listId == %@", listId))
            return builder
        }

        func withPriority(_ priority: TaskPriority) -> QueryBuilder {
            var builder = self
            builder.predicates.append(NSPredicate(format: "priority == %d", priority.rawValue))
            return builder
        }

        func incomplete() -> QueryBuilder {
            var builder = self
            builder.predicates.append(NSPredicate(format: "isCompleted == NO"))
            return builder
        }

        func completed() -> QueryBuilder {
            var builder = self
            builder.predicates.append(NSPredicate(format: "isCompleted == YES"))
            return builder
        }

        func dueWithin(days: Int) -> QueryBuilder {
            var builder = self
            let endDate = Calendar.current.date(byAdding: .day, value: days, to: Date())!
            builder.predicates.append(NSPredicate(
                format: "dueDate <= %@ AND dueDate != nil",
                endDate as NSDate
            ))
            return builder
        }

        func overdue() -> QueryBuilder {
            var builder = self
            builder.predicates.append(NSPredicate(
                format: "dueDate < %@ AND isCompleted == NO",
                Date() as NSDate
            ))
            return builder
        }

        func sortedBy(_ key: String, ascending: Bool = true) -> QueryBuilder {
            var builder = self
            builder.sortDescriptors.append(NSSortDescriptor(key: key, ascending: ascending))
            return builder
        }

        func limit(_ count: Int) -> QueryBuilder {
            var builder = self
            builder.fetchLimit = count
            return builder
        }

        func build() -> (predicate: NSPredicate?, sortDescriptors: [NSSortDescriptor], limit: Int?) {
            let predicate = predicates.isEmpty
                ? nil
                : NSCompoundPredicate(andPredicateWithSubpredicates: predicates)

            let finalSortDescriptors = sortDescriptors.isEmpty
                ? [NSSortDescriptor(key: "sortOrder", ascending: true)]
                : sortDescriptors

            return (predicate, finalSortDescriptors, fetchLimit)
        }
    }

    /// Creates a new query builder
    func query() -> QueryBuilder {
        return QueryBuilder()
    }

    /// Executes a query built with QueryBuilder
    func execute(query: QueryBuilder, context: NSManagedObjectContext? = nil) throws -> [CDTask] {
        let (predicate, sortDescriptors, limit) = query.build()
        return try fetchTasks(
            predicate: predicate,
            sortDescriptors: sortDescriptors,
            limit: limit,
            context: context
        )
    }
}
