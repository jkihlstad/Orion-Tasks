//
//  ListRepository.swift
//  TasksApp
//
//  Repository for TaskList CRUD operations with thread-safe CoreData access
//

import CoreData
import Foundation
import Combine

/// Repository for managing TaskList entities in CoreData
/// Provides thread-safe CRUD operations with batch support
final class ListRepository: @unchecked Sendable {

    // MARK: - Properties

    private let persistenceController: PersistenceController

    /// Publisher for list changes
    private let listChangesSubject = PassthroughSubject<ListChange, Never>()
    var listChanges: AnyPublisher<ListChange, Never> {
        listChangesSubject.eraseToAnyPublisher()
    }

    // MARK: - Initialization

    init(persistenceController: PersistenceController = .shared) {
        self.persistenceController = persistenceController
    }

    // MARK: - Create Operations

    /// Creates a new task list
    /// - Parameters:
    ///   - name: List name
    ///   - icon: Optional SF Symbol name
    ///   - color: Optional hex color code
    ///   - isDefault: Whether this is the default list
    ///   - context: Optional context (uses view context if nil)
    /// - Returns: The created list
    @discardableResult
    func createList(
        name: String,
        icon: String? = nil,
        color: String? = nil,
        isDefault: Bool = false,
        context: NSManagedObjectContext? = nil
    ) throws -> CDTaskList {
        let ctx = context ?? persistenceController.viewContext
        var createdList: CDTaskList!
        var thrownError: Error?

        ctx.performAndWait {
            // If creating a default list, unset any existing default
            if isDefault {
                unsetDefaultList(context: ctx)
            }

            let list = CDTaskList(context: ctx)
            list.id = UUID().uuidString
            list.name = name
            list.icon = icon
            list.color = color
            list.isDefault = isDefault
            list.isSmartList = false
            list.createdAt = Date()
            list.modifiedAt = Date()
            list.sortOrder = getNextSortOrder(context: ctx)
            list.syncStatus = SyncStatus.pendingUpload.rawValue

            do {
                try ctx.save()
                createdList = list
            } catch {
                thrownError = error
            }
        }

        if let error = thrownError {
            throw PersistenceError.saveFailed(error)
        }

        listChangesSubject.send(.created(createdList))
        return createdList
    }

    /// Creates a smart list with a filter
    /// - Parameters:
    ///   - name: List name
    ///   - icon: SF Symbol name
    ///   - color: Hex color code
    ///   - smartFilter: JSON-encoded filter configuration
    /// - Returns: The created smart list
    @discardableResult
    func createSmartList(
        name: String,
        icon: String? = nil,
        color: String? = nil,
        smartFilter: String
    ) throws -> CDTaskList {
        let context = persistenceController.viewContext
        var createdList: CDTaskList!
        var thrownError: Error?

        context.performAndWait {
            let list = CDTaskList(context: context)
            list.id = UUID().uuidString
            list.name = name
            list.icon = icon
            list.color = color
            list.isDefault = false
            list.isSmartList = true
            list.smartFilter = smartFilter
            list.createdAt = Date()
            list.modifiedAt = Date()
            list.sortOrder = getNextSortOrder(context: context)
            list.syncStatus = SyncStatus.pendingUpload.rawValue

            do {
                try context.save()
                createdList = list
            } catch {
                thrownError = error
            }
        }

        if let error = thrownError {
            throw PersistenceError.saveFailed(error)
        }

        listChangesSubject.send(.created(createdList))
        return createdList
    }

    /// Creates multiple lists in a batch operation
    /// - Parameter lists: Array of list data tuples
    /// - Returns: Array of created lists
    @discardableResult
    func createLists(
        _ lists: [(name: String, icon: String?, color: String?)]
    ) throws -> [CDTaskList] {
        let context = persistenceController.newBackgroundContext()
        var createdLists: [CDTaskList] = []
        var thrownError: Error?

        context.performAndWait {
            var currentSortOrder = getNextSortOrder(context: context)

            for listData in lists {
                let list = CDTaskList(context: context)
                list.id = UUID().uuidString
                list.name = listData.name
                list.icon = listData.icon
                list.color = listData.color
                list.isDefault = false
                list.isSmartList = false
                list.createdAt = Date()
                list.modifiedAt = Date()
                list.sortOrder = currentSortOrder
                list.syncStatus = SyncStatus.pendingUpload.rawValue

                createdLists.append(list)
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

        createdLists.forEach { listChangesSubject.send(.created($0)) }
        return createdLists
    }

    // MARK: - Read Operations

    /// Fetches a list by ID
    /// - Parameters:
    ///   - id: List ID
    ///   - context: Optional context
    /// - Returns: The list if found
    func fetchList(byId id: String, context: NSManagedObjectContext? = nil) -> CDTaskList? {
        let ctx = context ?? persistenceController.viewContext
        var result: CDTaskList?

        ctx.performAndWait {
            let request = CDTaskList.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@ AND isDeleted == NO", id)
            request.fetchLimit = 1

            result = try? ctx.fetch(request).first
        }

        return result
    }

    /// Fetches all lists
    /// - Parameters:
    ///   - includeSmartLists: Whether to include smart lists
    ///   - context: Optional context
    /// - Returns: Array of lists
    func fetchAllLists(
        includeSmartLists: Bool = true,
        context: NSManagedObjectContext? = nil
    ) throws -> [CDTaskList] {
        let ctx = context ?? persistenceController.viewContext
        var lists: [CDTaskList] = []
        var thrownError: Error?

        ctx.performAndWait {
            let request = CDTaskList.fetchRequest()

            var predicates = [NSPredicate(format: "isDeleted == NO")]

            if !includeSmartLists {
                predicates.append(NSPredicate(format: "isSmartList == NO"))
            }

            request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
            request.sortDescriptors = [
                NSSortDescriptor(key: "sortOrder", ascending: true),
                NSSortDescriptor(key: "createdAt", ascending: true)
            ]

            do {
                lists = try ctx.fetch(request)
            } catch {
                thrownError = error
            }
        }

        if let error = thrownError {
            throw PersistenceError.fetchFailed(error)
        }

        return lists
    }

    /// Fetches regular (non-smart) lists
    func fetchRegularLists(context: NSManagedObjectContext? = nil) throws -> [CDTaskList] {
        return try fetchAllLists(includeSmartLists: false, context: context)
    }

    /// Fetches smart lists only
    func fetchSmartLists(context: NSManagedObjectContext? = nil) throws -> [CDTaskList] {
        let ctx = context ?? persistenceController.viewContext
        var lists: [CDTaskList] = []
        var thrownError: Error?

        ctx.performAndWait {
            let request = CDTaskList.fetchRequest()
            request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                NSPredicate(format: "isDeleted == NO"),
                NSPredicate(format: "isSmartList == YES")
            ])
            request.sortDescriptors = [NSSortDescriptor(key: "sortOrder", ascending: true)]

            do {
                lists = try ctx.fetch(request)
            } catch {
                thrownError = error
            }
        }

        if let error = thrownError {
            throw PersistenceError.fetchFailed(error)
        }

        return lists
    }

    /// Fetches the default list
    func fetchDefaultList(context: NSManagedObjectContext? = nil) -> CDTaskList? {
        let ctx = context ?? persistenceController.viewContext
        var result: CDTaskList?

        ctx.performAndWait {
            let request = CDTaskList.fetchRequest()
            request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                NSPredicate(format: "isDeleted == NO"),
                NSPredicate(format: "isDefault == YES")
            ])
            request.fetchLimit = 1

            result = try? ctx.fetch(request).first
        }

        return result
    }

    /// Fetches lists pending sync
    func fetchListsPendingSync(context: NSManagedObjectContext? = nil) throws -> [CDTaskList] {
        let ctx = context ?? persistenceController.viewContext
        var lists: [CDTaskList] = []
        var thrownError: Error?

        ctx.performAndWait {
            let request = CDTaskList.fetchRequest()
            request.predicate = NSPredicate(format: "syncStatus == %d", SyncStatus.pendingUpload.rawValue)
            request.sortDescriptors = [NSSortDescriptor(key: "modifiedAt", ascending: true)]

            do {
                lists = try ctx.fetch(request)
            } catch {
                thrownError = error
            }
        }

        if let error = thrownError {
            throw PersistenceError.fetchFailed(error)
        }

        return lists
    }

    /// Fetches shared lists
    func fetchSharedLists(context: NSManagedObjectContext? = nil) throws -> [CDTaskList] {
        let ctx = context ?? persistenceController.viewContext
        var lists: [CDTaskList] = []
        var thrownError: Error?

        ctx.performAndWait {
            let request = CDTaskList.fetchRequest()
            request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                NSPredicate(format: "isDeleted == NO"),
                NSPredicate(format: "sharedWith != nil"),
                NSPredicate(format: "sharedWith.@count > 0")
            ])
            request.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]

            do {
                lists = try ctx.fetch(request)
            } catch {
                thrownError = error
            }
        }

        if let error = thrownError {
            throw PersistenceError.fetchFailed(error)
        }

        return lists
    }

    /// Counts lists
    func countLists(includeSmartLists: Bool = true, context: NSManagedObjectContext? = nil) -> Int {
        let ctx = context ?? persistenceController.viewContext
        var count = 0

        ctx.performAndWait {
            let request = CDTaskList.fetchRequest()

            var predicates = [NSPredicate(format: "isDeleted == NO")]
            if !includeSmartLists {
                predicates.append(NSPredicate(format: "isSmartList == NO"))
            }
            request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)

            count = (try? ctx.count(for: request)) ?? 0
        }

        return count
    }

    /// Search lists by name
    func searchLists(
        query: String,
        context: NSManagedObjectContext? = nil
    ) throws -> [CDTaskList] {
        guard !query.isEmpty else {
            return try fetchAllLists(context: context)
        }

        let ctx = context ?? persistenceController.viewContext
        var lists: [CDTaskList] = []
        var thrownError: Error?

        ctx.performAndWait {
            let request = CDTaskList.fetchRequest()
            request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                NSPredicate(format: "isDeleted == NO"),
                NSPredicate(format: "name CONTAINS[cd] %@", query)
            ])
            request.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]

            do {
                lists = try ctx.fetch(request)
            } catch {
                thrownError = error
            }
        }

        if let error = thrownError {
            throw PersistenceError.fetchFailed(error)
        }

        return lists
    }

    // MARK: - Update Operations

    /// Updates a list
    /// - Parameters:
    ///   - id: List ID
    ///   - updates: Closure to perform updates
    /// - Returns: The updated list
    @discardableResult
    func updateList(
        id: String,
        updates: @escaping (CDTaskList) -> Void
    ) throws -> CDTaskList {
        let context = persistenceController.viewContext
        var updatedList: CDTaskList?
        var thrownError: Error?

        context.performAndWait {
            guard let list = fetchList(byId: id, context: context) else {
                thrownError = PersistenceError.entityNotFound(id)
                return
            }

            updates(list)
            list.modifiedAt = Date()
            list.syncStatus = SyncStatus.pendingUpload.rawValue

            do {
                try context.save()
                updatedList = list
            } catch {
                thrownError = error
            }
        }

        if let error = thrownError {
            throw error
        }

        guard let list = updatedList else {
            throw PersistenceError.entityNotFound(id)
        }

        listChangesSubject.send(.updated(list))
        return list
    }

    /// Renames a list
    @discardableResult
    func renameList(id: String, newName: String) throws -> CDTaskList {
        return try updateList(id: id) { list in
            list.name = newName
        }
    }

    /// Updates list appearance
    @discardableResult
    func updateListAppearance(
        id: String,
        icon: String?,
        color: String?
    ) throws -> CDTaskList {
        return try updateList(id: id) { list in
            list.icon = icon
            list.color = color
        }
    }

    /// Sets a list as the default
    @discardableResult
    func setDefaultList(id: String) throws -> CDTaskList {
        let context = persistenceController.viewContext
        var updatedList: CDTaskList?
        var thrownError: Error?

        context.performAndWait {
            // Unset existing default
            unsetDefaultList(context: context)

            guard let list = fetchList(byId: id, context: context) else {
                thrownError = PersistenceError.entityNotFound(id)
                return
            }

            list.isDefault = true
            list.modifiedAt = Date()
            list.syncStatus = SyncStatus.pendingUpload.rawValue

            do {
                try context.save()
                updatedList = list
            } catch {
                thrownError = error
            }
        }

        if let error = thrownError {
            throw error
        }

        guard let list = updatedList else {
            throw PersistenceError.entityNotFound(id)
        }

        listChangesSubject.send(.updated(list))
        return list
    }

    /// Updates smart list filter
    @discardableResult
    func updateSmartFilter(id: String, filter: String) throws -> CDTaskList {
        return try updateList(id: id) { list in
            list.smartFilter = filter
        }
    }

    /// Reorders lists
    func reorderLists(ids: [String]) throws {
        let context = persistenceController.newBackgroundContext()
        var thrownError: Error?

        context.performAndWait {
            let request = CDTaskList.fetchRequest()
            request.predicate = NSPredicate(format: "id IN %@", ids)

            do {
                let lists = try context.fetch(request)
                let listDict = Dictionary(uniqueKeysWithValues: lists.map { ($0.id, $0) })

                for (index, id) in ids.enumerated() {
                    if let list = listDict[id] {
                        list.sortOrder = Int32(index)
                        list.modifiedAt = Date()
                        list.syncStatus = SyncStatus.pendingUpload.rawValue
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

    /// Shares a list with users
    func shareList(id: String, withUserIds userIds: [String]) throws {
        let context = persistenceController.viewContext
        var thrownError: Error?

        context.performAndWait {
            guard let list = fetchList(byId: id, context: context) else {
                thrownError = PersistenceError.entityNotFound(id)
                return
            }

            list.sharedWith = userIds as NSArray
            list.modifiedAt = Date()
            list.syncStatus = SyncStatus.pendingUpload.rawValue

            do {
                try context.save()
            } catch {
                thrownError = error
            }
        }

        if let error = thrownError {
            throw error
        }
    }

    /// Removes sharing from a list
    func unshareList(id: String, fromUserIds userIds: [String]) throws {
        let context = persistenceController.viewContext
        var thrownError: Error?

        context.performAndWait {
            guard let list = fetchList(byId: id, context: context) else {
                thrownError = PersistenceError.entityNotFound(id)
                return
            }

            if let currentShared = list.sharedWith as? [String] {
                let updatedShared = currentShared.filter { !userIds.contains($0) }
                list.sharedWith = updatedShared as NSArray
            }

            list.modifiedAt = Date()
            list.syncStatus = SyncStatus.pendingUpload.rawValue

            do {
                try context.save()
            } catch {
                thrownError = error
            }
        }

        if let error = thrownError {
            throw error
        }
    }

    // MARK: - Delete Operations

    /// Soft deletes a list (marks as deleted)
    /// - Parameters:
    ///   - id: List ID
    ///   - moveTasks: Whether to move tasks to another list (otherwise deletes them)
    ///   - targetListId: Target list for tasks if moving
    func deleteList(
        id: String,
        moveTasks: Bool = false,
        targetListId: String? = nil
    ) throws {
        let context = persistenceController.viewContext
        var thrownError: Error?

        context.performAndWait {
            guard let list = fetchList(byId: id, context: context) else {
                thrownError = PersistenceError.entityNotFound(id)
                return
            }

            // Handle tasks in the list
            if moveTasks, let targetId = targetListId {
                let targetList = fetchList(byId: targetId, context: context)
                for task in list.tasksArray {
                    task.listId = targetId
                    task.list = targetList
                    task.modifiedAt = Date()
                    task.syncStatus = SyncStatus.pendingUpload.rawValue
                }
            } else {
                // Soft delete all tasks in the list
                for task in list.tasksArray {
                    task.isDeleted = true
                    task.modifiedAt = Date()
                    task.syncStatus = SyncStatus.pendingUpload.rawValue
                }
            }

            list.isDeleted = true
            list.modifiedAt = Date()
            list.syncStatus = SyncStatus.pendingUpload.rawValue

            do {
                try context.save()
                listChangesSubject.send(.deleted(id))
            } catch {
                thrownError = error
            }
        }

        if let error = thrownError {
            throw error
        }
    }

    /// Permanently deletes a list (hard delete)
    func permanentlyDeleteList(id: String) throws {
        let context = persistenceController.viewContext
        var thrownError: Error?

        context.performAndWait {
            let request = CDTaskList.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", id)
            request.fetchLimit = 1

            do {
                if let list = try context.fetch(request).first {
                    context.delete(list)
                    try context.save()
                }
            } catch {
                thrownError = error
            }
        }

        if let error = thrownError {
            throw PersistenceError.saveFailed(error)
        }

        listChangesSubject.send(.deleted(id))
    }

    /// Purges all soft-deleted lists (hard delete)
    func purgeDeletedLists() throws {
        let request = CDTaskList.fetchRequest()
        request.predicate = NSPredicate(format: "isDeleted == YES")

        try persistenceController.batchDelete(fetchRequest: request)
    }

    // MARK: - Sync Operations

    /// Marks lists as synced
    func markListsAsSynced(ids: [String], serverVersion: Int64? = nil) throws {
        let context = persistenceController.newBackgroundContext()
        var thrownError: Error?

        context.performAndWait {
            let request = CDTaskList.fetchRequest()
            request.predicate = NSPredicate(format: "id IN %@", ids)

            do {
                let lists = try context.fetch(request)
                let now = Date()
                for list in lists {
                    list.syncStatus = SyncStatus.synced.rawValue
                    list.lastSyncedAt = now
                    if let version = serverVersion {
                        list.serverVersion = NSNumber(value: version)
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

    /// Updates list from server data (for sync)
    func updateFromServer(
        id: String,
        serverData: [String: Any],
        serverVersion: Int64,
        context: NSManagedObjectContext? = nil
    ) throws {
        let ctx = context ?? persistenceController.newBackgroundContext()
        var thrownError: Error?

        ctx.performAndWait {
            let list: CDTaskList
            if let existingList = fetchList(byId: id, context: ctx) {
                list = existingList
            } else {
                list = CDTaskList(context: ctx)
                list.id = id
                list.createdAt = Date()
            }

            // Update fields from server data
            if let name = serverData["name"] as? String {
                list.name = name
            }
            if let icon = serverData["icon"] as? String {
                list.icon = icon
            }
            if let color = serverData["color"] as? String {
                list.color = color
            }
            if let isDefault = serverData["isDefault"] as? Bool {
                list.isDefault = isDefault
            }
            if let isSmartList = serverData["isSmartList"] as? Bool {
                list.isSmartList = isSmartList
            }
            if let smartFilter = serverData["smartFilter"] as? String {
                list.smartFilter = smartFilter
            }

            list.serverVersion = NSNumber(value: serverVersion)
            list.syncStatus = SyncStatus.synced.rawValue
            list.lastSyncedAt = Date()
            list.modifiedAt = Date()

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

    // MARK: - Statistics

    /// Gets task counts for a list
    func getTaskCounts(forListId id: String) -> (total: Int, completed: Int, incomplete: Int) {
        let context = persistenceController.viewContext
        var total = 0
        var completed = 0

        context.performAndWait {
            guard let list = fetchList(byId: id, context: context) else { return }
            let tasks = list.tasksArray.filter { !$0.isDeleted }
            total = tasks.count
            completed = tasks.filter { $0.isCompleted }.count
        }

        return (total, completed, total - completed)
    }

    /// Gets task counts for all lists
    func getAllListTaskCounts() -> [String: (total: Int, completed: Int, incomplete: Int)] {
        let context = persistenceController.viewContext
        var counts: [String: (total: Int, completed: Int, incomplete: Int)] = [:]

        context.performAndWait {
            let request = CDTaskList.fetchRequest()
            request.predicate = NSPredicate(format: "isDeleted == NO AND isSmartList == NO")

            if let lists = try? context.fetch(request) {
                for list in lists {
                    let tasks = list.tasksArray.filter { !$0.isDeleted }
                    let total = tasks.count
                    let completed = tasks.filter { $0.isCompleted }.count
                    counts[list.id] = (total, completed, total - completed)
                }
            }
        }

        return counts
    }

    // MARK: - Helper Methods

    private func getNextSortOrder(context: NSManagedObjectContext) -> Int32 {
        let request = CDTaskList.fetchRequest()
        request.predicate = NSPredicate(format: "isDeleted == NO")
        request.sortDescriptors = [NSSortDescriptor(key: "sortOrder", ascending: false)]
        request.fetchLimit = 1

        if let maxList = try? context.fetch(request).first {
            return maxList.sortOrder + 1
        }

        return 0
    }

    private func unsetDefaultList(context: NSManagedObjectContext) {
        let request = CDTaskList.fetchRequest()
        request.predicate = NSPredicate(format: "isDefault == YES")

        if let lists = try? context.fetch(request) {
            for list in lists {
                list.isDefault = false
                list.modifiedAt = Date()
                list.syncStatus = SyncStatus.pendingUpload.rawValue
            }
        }
    }

    /// Ensures at least one default list exists
    func ensureDefaultListExists() throws {
        let context = persistenceController.viewContext

        context.performAndWait {
            if fetchDefaultList(context: context) == nil {
                // Check if any lists exist
                let request = CDTaskList.fetchRequest()
                request.predicate = NSPredicate(format: "isDeleted == NO AND isSmartList == NO")
                request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
                request.fetchLimit = 1

                if let firstList = try? context.fetch(request).first {
                    // Set the first list as default
                    firstList.isDefault = true
                    firstList.modifiedAt = Date()
                    try? context.save()
                }
            }
        }
    }
}

// MARK: - List Change Types

enum ListChange {
    case created(CDTaskList)
    case updated(CDTaskList)
    case deleted(String)
}

// MARK: - Smart Filter Types

extension ListRepository {

    /// Predefined smart filter types
    struct SmartFilters {

        /// All incomplete tasks
        static var allIncomplete: String {
            return """
            {"type": "incomplete"}
            """
        }

        /// Tasks due today
        static var dueToday: String {
            return """
            {"type": "dueToday"}
            """
        }

        /// Tasks due this week
        static var dueThisWeek: String {
            return """
            {"type": "dueThisWeek"}
            """
        }

        /// Overdue tasks
        static var overdue: String {
            return """
            {"type": "overdue"}
            """
        }

        /// High priority tasks
        static var highPriority: String {
            return """
            {"type": "priority", "value": 3}
            """
        }

        /// Tasks with reminders
        static var withReminders: String {
            return """
            {"type": "hasReminder"}
            """
        }

        /// Recently completed tasks
        static var recentlyCompleted: String {
            return """
            {"type": "recentlyCompleted", "days": 7}
            """
        }

        /// Unscheduled tasks (no due date)
        static var unscheduled: String {
            return """
            {"type": "noDueDate"}
            """
        }

        /// Creates a filter for tasks with specific tags
        static func withTags(_ tagIds: [String]) -> String {
            let tagIdsJson = tagIds.map { "\"\($0)\"" }.joined(separator: ", ")
            return """
            {"type": "tags", "tagIds": [\(tagIdsJson)]}
            """
        }

        /// Creates a custom date range filter
        static func dateRange(start: Date, end: Date) -> String {
            let formatter = ISO8601DateFormatter()
            return """
            {"type": "dateRange", "start": "\(formatter.string(from: start))", "end": "\(formatter.string(from: end))"}
            """
        }
    }
}

// MARK: - Default Lists Setup

extension ListRepository {

    /// Creates default lists for new users
    func createDefaultLists() throws {
        let context = persistenceController.viewContext
        var thrownError: Error?

        context.performAndWait {
            // Check if any lists exist
            let request = CDTaskList.fetchRequest()
            request.predicate = NSPredicate(format: "isDeleted == NO")

            do {
                let existingCount = try context.count(for: request)
                guard existingCount == 0 else { return }

                // Create default "Inbox" list
                let inbox = CDTaskList(context: context)
                inbox.id = UUID().uuidString
                inbox.name = "Inbox"
                inbox.icon = "tray"
                inbox.color = "#007AFF"
                inbox.isDefault = true
                inbox.isSmartList = false
                inbox.createdAt = Date()
                inbox.modifiedAt = Date()
                inbox.sortOrder = 0
                inbox.syncStatus = SyncStatus.pendingUpload.rawValue

                // Create "Personal" list
                let personal = CDTaskList(context: context)
                personal.id = UUID().uuidString
                personal.name = "Personal"
                personal.icon = "person"
                personal.color = "#34C759"
                personal.isDefault = false
                personal.isSmartList = false
                personal.createdAt = Date()
                personal.modifiedAt = Date()
                personal.sortOrder = 1
                personal.syncStatus = SyncStatus.pendingUpload.rawValue

                // Create "Work" list
                let work = CDTaskList(context: context)
                work.id = UUID().uuidString
                work.name = "Work"
                work.icon = "briefcase"
                work.color = "#FF9500"
                work.isDefault = false
                work.isSmartList = false
                work.createdAt = Date()
                work.modifiedAt = Date()
                work.sortOrder = 2
                work.syncStatus = SyncStatus.pendingUpload.rawValue

                try context.save()
            } catch {
                thrownError = error
            }
        }

        if let error = thrownError {
            throw PersistenceError.saveFailed(error)
        }
    }

    /// Creates default smart lists
    func createDefaultSmartLists() throws {
        let context = persistenceController.viewContext
        var thrownError: Error?

        context.performAndWait {
            // Check if smart lists exist
            let request = CDTaskList.fetchRequest()
            request.predicate = NSPredicate(format: "isDeleted == NO AND isSmartList == YES")

            do {
                let existingCount = try context.count(for: request)
                guard existingCount == 0 else { return }

                // Today
                let today = CDTaskList(context: context)
                today.id = "smart-today"
                today.name = "Today"
                today.icon = "sun.max"
                today.color = "#FF3B30"
                today.isSmartList = true
                today.smartFilter = SmartFilters.dueToday
                today.createdAt = Date()
                today.modifiedAt = Date()
                today.sortOrder = 100
                today.syncStatus = SyncStatus.synced.rawValue

                // Upcoming
                let upcoming = CDTaskList(context: context)
                upcoming.id = "smart-upcoming"
                upcoming.name = "Upcoming"
                upcoming.icon = "calendar"
                upcoming.color = "#5856D6"
                upcoming.isSmartList = true
                upcoming.smartFilter = SmartFilters.dueThisWeek
                upcoming.createdAt = Date()
                upcoming.modifiedAt = Date()
                upcoming.sortOrder = 101
                upcoming.syncStatus = SyncStatus.synced.rawValue

                // All Tasks
                let all = CDTaskList(context: context)
                all.id = "smart-all"
                all.name = "All Tasks"
                all.icon = "list.bullet"
                all.color = "#8E8E93"
                all.isSmartList = true
                all.smartFilter = SmartFilters.allIncomplete
                all.createdAt = Date()
                all.modifiedAt = Date()
                all.sortOrder = 102
                all.syncStatus = SyncStatus.synced.rawValue

                try context.save()
            } catch {
                thrownError = error
            }
        }

        if let error = thrownError {
            throw PersistenceError.saveFailed(error)
        }
    }
}
