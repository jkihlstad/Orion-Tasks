//
//  TasksAPI.swift
//  TasksApp
//
//  Tasks API endpoints for Convex backend
//  Provides typed methods for all task-related operations
//

import Foundation
import Combine

// MARK: - API Response Types

/// Response for list queries
struct TaskListResponse: Codable {
    let id: String
    let name: String
    let color: String?
    let icon: String?
    let sortOrder: Int
    let isDefault: Bool
    let isSmartList: Bool
    let smartFilter: String?
    let taskCount: Int?
    let createdAt: Date
    let modifiedAt: Date
}

/// Response for task queries
struct TaskResponse: Codable {
    let id: String
    let title: String
    let notes: String?
    let isCompleted: Bool
    let completedAt: Date?
    let dueDate: Date?
    let dueTime: Date?
    let reminderDate: Date?
    let priority: Int
    let sortOrder: Int
    let listId: String?
    let parentTaskId: String?
    let subtaskIds: [String]?
    let tagIds: [String]?
    let attachmentIds: [String]?
    let flag: Bool
    let redBeaconEnabled: Bool
    let mirrorToCalendarEnabled: Bool
    let linkedEventIdentifier: String?
    let createdAt: Date
    let modifiedAt: Date
}

/// Response for tag queries
struct TagResponse: Codable {
    let id: String
    let name: String
    let color: String?
    let taskCount: Int?
    let createdAt: Date
}

/// Response for attachment queries
struct AttachmentResponse: Codable {
    let id: String
    let taskId: String
    let fileName: String
    let mimeType: String?
    let fileSize: Int64?
    let localPath: String?
    let remoteUrl: String?
    let thumbnailUrl: String?
    let uploadStatus: String
    let createdAt: Date
}

/// Response for smart view queries
struct SmartViewResponse: Codable {
    let viewType: String
    let tasks: [TaskResponse]
    let totalCount: Int
    let metadata: SmartViewMetadata?

    struct SmartViewMetadata: Codable {
        let overdueCount: Int?
        let dueTodayCount: Int?
        let flaggedCount: Int?
    }
}

/// Response for search queries
struct SearchResponse: Codable {
    let tasks: [TaskResponse]
    let lists: [TaskListResponse]
    let tags: [TagResponse]
    let totalResults: Int
    let query: String
}

/// Response for sync/changes queries
struct ChangesQueryResponse: Codable {
    let events: [[String: AnyCodable]]
    let cursor: String?
    let version: Int64?
    let hasMore: Bool
}

/// Response for batch insert
struct BatchInsertResponse: Codable {
    let insertedCount: Int
    let failedCount: Int
    let failedIds: [String]?
    let serverVersion: Int64?
}

// MARK: - Smart View Types

/// Types of smart views
enum SmartViewType: String, Codable, CaseIterable {
    case today = "today"
    case scheduled = "scheduled"
    case flagged = "flagged"
    case all = "all"
    case completed = "completed"
    case overdue = "overdue"
    case thisWeek = "this_week"
    case noDate = "no_date"
}

// MARK: - Tasks API Client

/// Client for Tasks API endpoints
final class TasksAPI: @unchecked Sendable {

    // MARK: - Properties

    private let convexClient: ConvexClient

    // Function paths
    private enum Functions {
        // List functions
        static let queryLists = "lists:queryLists"
        static let getList = "lists:getList"
        static let createList = "lists:createList"
        static let updateList = "lists:updateList"
        static let deleteList = "lists:deleteList"
        static let reorderLists = "lists:reorderLists"

        // Task functions
        static let queryTasksByList = "tasks:queryTasksByList"
        static let queryTaskDetail = "tasks:queryTaskDetail"
        static let querySmartView = "tasks:querySmartView"
        static let querySearch = "tasks:querySearch"
        static let createTask = "tasks:createTask"
        static let updateTask = "tasks:updateTask"
        static let deleteTask = "tasks:deleteTask"
        static let completeTask = "tasks:completeTask"
        static let uncompleteTask = "tasks:uncompleteTask"
        static let moveTask = "tasks:moveTask"
        static let reorderTasks = "tasks:reorderTasks"
        static let flagTask = "tasks:flagTask"
        static let unflagTask = "tasks:unflagTask"

        // Subtask functions
        static let addSubtask = "tasks:addSubtask"
        static let removeSubtask = "tasks:removeSubtask"

        // Tag functions
        static let queryTags = "tags:queryTags"
        static let createTag = "tags:createTag"
        static let updateTag = "tags:updateTag"
        static let deleteTag = "tags:deleteTag"
        static let assignTag = "tags:assignTag"
        static let unassignTag = "tags:unassignTag"

        // Attachment functions
        static let queryAttachments = "attachments:queryAttachments"
        static let addAttachment = "attachments:addAttachment"
        static let removeAttachment = "attachments:removeAttachment"
        static let getUploadUrl = "attachments:getUploadUrl"

        // Sync functions
        static let insertBatch = "sync:insertBatch"
        static let queryChanges = "sync:queryChanges"
        static let getSyncState = "sync:getSyncState"

        // Bulk operations
        static let bulkComplete = "tasks:bulkComplete"
        static let bulkDelete = "tasks:bulkDelete"
        static let bulkMove = "tasks:bulkMove"
    }

    // MARK: - Initialization

    init(convexClient: ConvexClient) {
        self.convexClient = convexClient
    }

    // MARK: - List Operations

    /// Queries all lists for the current user
    func queryLists() async throws -> [TaskListResponse] {
        try await convexClient.queryArray(
            Functions.queryLists,
            elementType: TaskListResponse.self
        )
    }

    /// Gets a single list by ID
    func getList(id: String) async throws -> TaskListResponse? {
        try await convexClient.queryOptional(
            Functions.getList,
            args: ["listId": id],
            responseType: TaskListResponse.self
        )
    }

    /// Creates a new list
    func createList(
        name: String,
        color: String? = nil,
        icon: String? = nil
    ) async throws -> TaskListResponse {
        var args: [String: Any] = ["name": name]
        if let color = color { args["color"] = color }
        if let icon = icon { args["icon"] = icon }

        return try await convexClient.mutation(
            Functions.createList,
            args: args,
            responseType: TaskListResponse.self
        )
    }

    /// Updates a list
    func updateList(
        id: String,
        name: String? = nil,
        color: String? = nil,
        icon: String? = nil
    ) async throws -> TaskListResponse {
        var args: [String: Any] = ["listId": id]
        if let name = name { args["name"] = name }
        if let color = color { args["color"] = color }
        if let icon = icon { args["icon"] = icon }

        return try await convexClient.mutation(
            Functions.updateList,
            args: args,
            responseType: TaskListResponse.self
        )
    }

    /// Deletes a list
    func deleteList(id: String) async throws {
        try await convexClient.mutation(
            Functions.deleteList,
            args: ["listId": id]
        )
    }

    /// Reorders lists
    func reorderLists(listIds: [String]) async throws {
        try await convexClient.mutation(
            Functions.reorderLists,
            args: ["listIds": listIds]
        )
    }

    // MARK: - Task Operations

    /// Queries tasks by list
    func queryTasksByList(
        listId: String,
        includeCompleted: Bool = false,
        limit: Int? = nil,
        cursor: String? = nil
    ) async throws -> [TaskResponse] {
        var args: [String: Any] = [
            "listId": listId,
            "includeCompleted": includeCompleted
        ]
        if let limit = limit { args["limit"] = limit }
        if let cursor = cursor { args["cursor"] = cursor }

        return try await convexClient.queryArray(
            Functions.queryTasksByList,
            args: args,
            elementType: TaskResponse.self
        )
    }

    /// Queries task detail
    func queryTaskDetail(taskId: String) async throws -> TaskResponse? {
        try await convexClient.queryOptional(
            Functions.queryTaskDetail,
            args: ["taskId": taskId],
            responseType: TaskResponse.self
        )
    }

    /// Queries smart view (Today, Flagged, etc.)
    func querySmartView(
        viewType: SmartViewType,
        limit: Int? = nil
    ) async throws -> SmartViewResponse {
        var args: [String: Any] = ["viewType": viewType.rawValue]
        if let limit = limit { args["limit"] = limit }

        return try await convexClient.query(
            Functions.querySmartView,
            args: args,
            responseType: SmartViewResponse.self
        )
    }

    /// Searches tasks, lists, and tags
    func querySearch(
        query: String,
        limit: Int? = nil
    ) async throws -> SearchResponse {
        var args: [String: Any] = ["query": query]
        if let limit = limit { args["limit"] = limit }

        return try await convexClient.query(
            Functions.querySearch,
            args: args,
            responseType: SearchResponse.self
        )
    }

    /// Creates a new task
    func createTask(
        title: String,
        listId: String,
        notes: String? = nil,
        dueDate: Date? = nil,
        dueTime: Date? = nil,
        priority: Int = 0,
        flag: Bool = false,
        tagIds: [String]? = nil
    ) async throws -> TaskResponse {
        var args: [String: Any] = [
            "title": title,
            "listId": listId,
            "priority": priority,
            "flag": flag
        ]
        if let notes = notes { args["notes"] = notes }
        if let dueDate = dueDate { args["dueDate"] = Int64(dueDate.timeIntervalSince1970 * 1000) }
        if let dueTime = dueTime { args["dueTime"] = Int64(dueTime.timeIntervalSince1970 * 1000) }
        if let tagIds = tagIds { args["tagIds"] = tagIds }

        return try await convexClient.mutation(
            Functions.createTask,
            args: args,
            responseType: TaskResponse.self
        )
    }

    /// Updates a task
    func updateTask(
        taskId: String,
        title: String? = nil,
        notes: String? = nil,
        dueDate: Date? = nil,
        dueTime: Date? = nil,
        priority: Int? = nil,
        flag: Bool? = nil
    ) async throws -> TaskResponse {
        var args: [String: Any] = ["taskId": taskId]
        if let title = title { args["title"] = title }
        if let notes = notes { args["notes"] = notes }
        if let dueDate = dueDate { args["dueDate"] = Int64(dueDate.timeIntervalSince1970 * 1000) }
        if let dueTime = dueTime { args["dueTime"] = Int64(dueTime.timeIntervalSince1970 * 1000) }
        if let priority = priority { args["priority"] = priority }
        if let flag = flag { args["flag"] = flag }

        return try await convexClient.mutation(
            Functions.updateTask,
            args: args,
            responseType: TaskResponse.self
        )
    }

    /// Deletes a task
    func deleteTask(taskId: String) async throws {
        try await convexClient.mutation(
            Functions.deleteTask,
            args: ["taskId": taskId]
        )
    }

    /// Completes a task
    func completeTask(taskId: String) async throws -> TaskResponse {
        try await convexClient.mutation(
            Functions.completeTask,
            args: ["taskId": taskId],
            responseType: TaskResponse.self
        )
    }

    /// Uncompletes a task
    func uncompleteTask(taskId: String) async throws -> TaskResponse {
        try await convexClient.mutation(
            Functions.uncompleteTask,
            args: ["taskId": taskId],
            responseType: TaskResponse.self
        )
    }

    /// Moves a task to a different list
    func moveTask(taskId: String, toListId: String) async throws -> TaskResponse {
        try await convexClient.mutation(
            Functions.moveTask,
            args: ["taskId": taskId, "toListId": toListId],
            responseType: TaskResponse.self
        )
    }

    /// Reorders tasks within a list
    func reorderTasks(listId: String, taskIds: [String]) async throws {
        try await convexClient.mutation(
            Functions.reorderTasks,
            args: ["listId": listId, "taskIds": taskIds]
        )
    }

    /// Flags a task
    func flagTask(taskId: String) async throws -> TaskResponse {
        try await convexClient.mutation(
            Functions.flagTask,
            args: ["taskId": taskId],
            responseType: TaskResponse.self
        )
    }

    /// Unflags a task
    func unflagTask(taskId: String) async throws -> TaskResponse {
        try await convexClient.mutation(
            Functions.unflagTask,
            args: ["taskId": taskId],
            responseType: TaskResponse.self
        )
    }

    // MARK: - Subtask Operations

    /// Adds a subtask to a parent task
    func addSubtask(parentTaskId: String, subtaskId: String) async throws {
        try await convexClient.mutation(
            Functions.addSubtask,
            args: ["parentTaskId": parentTaskId, "subtaskId": subtaskId]
        )
    }

    /// Removes a subtask from a parent task
    func removeSubtask(parentTaskId: String, subtaskId: String) async throws {
        try await convexClient.mutation(
            Functions.removeSubtask,
            args: ["parentTaskId": parentTaskId, "subtaskId": subtaskId]
        )
    }

    // MARK: - Tag Operations

    /// Queries all tags
    func queryTags() async throws -> [TagResponse] {
        try await convexClient.queryArray(
            Functions.queryTags,
            elementType: TagResponse.self
        )
    }

    /// Creates a new tag
    func createTag(name: String, color: String? = nil) async throws -> TagResponse {
        var args: [String: Any] = ["name": name]
        if let color = color { args["color"] = color }

        return try await convexClient.mutation(
            Functions.createTag,
            args: args,
            responseType: TagResponse.self
        )
    }

    /// Updates a tag
    func updateTag(tagId: String, name: String? = nil, color: String? = nil) async throws -> TagResponse {
        var args: [String: Any] = ["tagId": tagId]
        if let name = name { args["name"] = name }
        if let color = color { args["color"] = color }

        return try await convexClient.mutation(
            Functions.updateTag,
            args: args,
            responseType: TagResponse.self
        )
    }

    /// Deletes a tag
    func deleteTag(tagId: String) async throws {
        try await convexClient.mutation(
            Functions.deleteTag,
            args: ["tagId": tagId]
        )
    }

    /// Assigns a tag to a task
    func assignTag(taskId: String, tagId: String) async throws {
        try await convexClient.mutation(
            Functions.assignTag,
            args: ["taskId": taskId, "tagId": tagId]
        )
    }

    /// Unassigns a tag from a task
    func unassignTag(taskId: String, tagId: String) async throws {
        try await convexClient.mutation(
            Functions.unassignTag,
            args: ["taskId": taskId, "tagId": tagId]
        )
    }

    // MARK: - Attachment Operations

    /// Queries attachments for a task
    func queryAttachments(taskId: String) async throws -> [AttachmentResponse] {
        try await convexClient.queryArray(
            Functions.queryAttachments,
            args: ["taskId": taskId],
            elementType: AttachmentResponse.self
        )
    }

    /// Gets upload URL for a new attachment
    func getUploadUrl(
        taskId: String,
        fileName: String,
        mimeType: String,
        fileSize: Int64
    ) async throws -> UploadUrlResponse {
        try await convexClient.mutation(
            Functions.getUploadUrl,
            args: [
                "taskId": taskId,
                "fileName": fileName,
                "mimeType": mimeType,
                "fileSize": fileSize
            ],
            responseType: UploadUrlResponse.self
        )
    }

    /// Adds an attachment record (after upload completes)
    func addAttachment(
        taskId: String,
        attachmentId: String,
        fileName: String,
        mimeType: String,
        fileSize: Int64,
        remoteUrl: String
    ) async throws -> AttachmentResponse {
        try await convexClient.mutation(
            Functions.addAttachment,
            args: [
                "taskId": taskId,
                "attachmentId": attachmentId,
                "fileName": fileName,
                "mimeType": mimeType,
                "fileSize": fileSize,
                "remoteUrl": remoteUrl
            ],
            responseType: AttachmentResponse.self
        )
    }

    /// Removes an attachment
    func removeAttachment(attachmentId: String) async throws {
        try await convexClient.mutation(
            Functions.removeAttachment,
            args: ["attachmentId": attachmentId]
        )
    }

    // MARK: - Sync Operations

    /// Inserts a batch of events
    func insertBatch(events: [[String: Any]]) async throws -> BatchInsertResponse {
        try await convexClient.mutation(
            Functions.insertBatch,
            args: ["events": events],
            responseType: BatchInsertResponse.self
        )
    }

    /// Queries changes since cursor
    func queryChanges(since cursor: String?) async throws -> ChangesResponse {
        var args: [String: Any] = [:]
        if let cursor = cursor { args["cursor"] = cursor }

        let response: ChangesQueryResponse = try await convexClient.query(
            Functions.queryChanges,
            args: args,
            responseType: ChangesQueryResponse.self
        )

        // Convert to ChangesResponse format used by SyncEngine
        let events: [[String: Any]] = response.events.map { event in
            var dict: [String: Any] = [:]
            for (key, value) in event {
                dict[key] = value.value
            }
            return dict
        }

        return ChangesResponse(
            events: events,
            cursor: response.cursor,
            version: response.version,
            hasMore: response.hasMore
        )
    }

    /// Gets current sync state
    func getSyncState() async throws -> SyncStateResponse {
        try await convexClient.query(
            Functions.getSyncState,
            responseType: SyncStateResponse.self
        )
    }

    // MARK: - Bulk Operations

    /// Completes multiple tasks
    func bulkComplete(taskIds: [String]) async throws -> BulkOperationResponse {
        try await convexClient.mutation(
            Functions.bulkComplete,
            args: ["taskIds": taskIds],
            responseType: BulkOperationResponse.self
        )
    }

    /// Deletes multiple tasks
    func bulkDelete(taskIds: [String]) async throws -> BulkOperationResponse {
        try await convexClient.mutation(
            Functions.bulkDelete,
            args: ["taskIds": taskIds],
            responseType: BulkOperationResponse.self
        )
    }

    /// Moves multiple tasks to a list
    func bulkMove(taskIds: [String], toListId: String) async throws -> BulkOperationResponse {
        try await convexClient.mutation(
            Functions.bulkMove,
            args: ["taskIds": taskIds, "toListId": toListId],
            responseType: BulkOperationResponse.self
        )
    }
}

// MARK: - Additional Response Types

/// Response for upload URL request
struct UploadUrlResponse: Codable {
    let uploadUrl: String
    let attachmentId: String
    let expiresAt: Date
}

/// Response for sync state
struct SyncStateResponse: Codable {
    let cursor: String?
    let serverVersion: Int64
    let lastSyncAt: Date?
    let pendingEventsCount: Int
}

/// Response for bulk operations
struct BulkOperationResponse: Codable {
    let successCount: Int
    let failedCount: Int
    let failedIds: [String]?
}

// MARK: - AnyCodable Helper

/// Type-erased Codable wrapper
struct AnyCodable: Codable {
    let value: Any

    init(_ value: Any) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map { $0.value }
        } else if let dictionary = try? container.decode([String: AnyCodable].self) {
            value = dictionary.mapValues { $0.value }
        } else if container.decodeNil() {
            value = NSNull()
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unable to decode value"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch value {
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let bool as Bool:
            try container.encode(bool)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })
        case let dictionary as [String: Any]:
            try container.encode(dictionary.mapValues { AnyCodable($0) })
        case is NSNull:
            try container.encodeNil()
        default:
            throw EncodingError.invalidValue(
                value,
                EncodingError.Context(
                    codingPath: encoder.codingPath,
                    debugDescription: "Unable to encode value of type \(type(of: value))"
                )
            )
        }
    }
}

// MARK: - TasksAPIClient Protocol Conformance

extension TasksAPI: TasksAPIClient {
    func insertBatch(events: [[String: Any]]) async throws {
        _ = try await insertBatch(events: events) as BatchInsertResponse
    }
}
