//
//  CoreDataModels.swift
//  TasksApp
//
//  NSManagedObject subclasses for CoreData entities
//  These classes correspond to the programmatically defined model in PersistenceController
//

import CoreData
import Foundation

// MARK: - Sync Status Enum

/// Represents the synchronization status of an entity
@objc public enum SyncStatus: Int16 {
    case synced = 0           // Fully synced with server
    case pendingUpload = 1    // Local changes need to be uploaded
    case pendingDownload = 2  // Server changes need to be downloaded
    case conflict = 3         // Conflict between local and server
    case error = 4            // Sync error occurred
}

// MARK: - Event Status Enum

/// Represents the status of a pending event in the outbox queue
@objc public enum EventStatus: Int16 {
    case pending = 0          // Waiting to be processed
    case processing = 1       // Currently being processed
    case completed = 2        // Successfully processed
    case failed = 3           // Failed after max retries
    case cancelled = 4        // Cancelled by user
}

// MARK: - Upload Status Enum

/// Represents the upload status of an attachment
@objc public enum UploadStatus: Int16 {
    case pending = 0          // Not yet uploaded
    case uploading = 1        // Currently uploading
    case completed = 2        // Successfully uploaded
    case failed = 3           // Upload failed
}

// MARK: - Calendar Sync Direction Enum

/// Represents the sync direction for calendar links
@objc public enum CalendarSyncDirection: Int16 {
    case taskToCalendar = 0   // Task is source of truth
    case calendarToTask = 1   // Calendar event is source of truth
    case bidirectional = 2    // Changes sync both ways
}

// MARK: - Task Priority Enum

/// Represents task priority levels
@objc public enum TaskPriority: Int16 {
    case none = 0
    case low = 1
    case medium = 2
    case high = 3
}

// MARK: - CDTask Entity

/**
 CDTask Entity - Represents a task in the Tasks app

 Attributes:
 - id: String (required) - Unique identifier (UUID)
 - title: String (required) - Task title
 - notes: String? - Optional task description/notes
 - isCompleted: Bool - Completion status (default: false)
 - completedAt: Date? - When the task was completed
 - dueDate: Date? - Optional due date
 - startDate: Date? - Optional start date
 - reminderDate: Date? - When to send reminder notification
 - recurrenceRule: String? - JSON-encoded recurrence rule
 - priority: Int16 - Priority level (0=none, 1=low, 2=medium, 3=high)
 - sortOrder: Int32 - Order within list
 - listId: String? - ID of parent list (denormalized for queries)
 - parentTaskId: String? - ID of parent task (for subtasks)
 - subtaskIds: [String]? - IDs of subtasks (transformable)
 - createdAt: Date (required) - Creation timestamp
 - modifiedAt: Date (required) - Last modification timestamp
 - createdBy: String? - User ID who created the task
 - serverVersion: Int64? - Server version for conflict resolution
 - syncStatus: Int16 - Sync status (default: 0)
 - lastSyncedAt: Date? - Last successful sync timestamp
 - isDeleted: Bool - Soft delete flag (default: false)
 - latitude: Double? - Location latitude
 - longitude: Double? - Location longitude
 - locationName: String? - Human-readable location name
 - locationRadius: Double? - Geofence radius in meters
 - url: String? - Associated URL
 - energyLevel: Int16? - Required energy level (for AI scheduling)
 - estimatedDuration: Int32? - Estimated duration in minutes

 Relationships:
 - list: CDTaskList? - Parent task list (to-one)
 - tags: Set<CDTag> - Associated tags (to-many)
 - attachments: Set<CDAttachmentRef> - File attachments (to-many)
 - calendarLinks: Set<CDCalendarLink> - Calendar event links (to-many)
 - parentTask: CDTask? - Parent task for subtasks (to-one)
 - subtasks: Set<CDTask> - Child subtasks (to-many)

 Indexes:
 - byId: id
 - byListId: listId
 - byDueDate: dueDate
 */
@objc(CDTask)
public class CDTask: NSManagedObject {

    // MARK: - Attributes

    @NSManaged public var id: String
    @NSManaged public var title: String
    @NSManaged public var notes: String?
    @NSManaged public var isCompleted: Bool
    @NSManaged public var completedAt: Date?
    @NSManaged public var dueDate: Date?
    @NSManaged public var startDate: Date?
    @NSManaged public var reminderDate: Date?
    @NSManaged public var recurrenceRule: String?
    @NSManaged public var priority: Int16
    @NSManaged public var sortOrder: Int32
    @NSManaged public var listId: String?
    @NSManaged public var parentTaskId: String?
    @NSManaged public var subtaskIds: NSArray?
    @NSManaged public var createdAt: Date
    @NSManaged public var modifiedAt: Date
    @NSManaged public var createdBy: String?
    @NSManaged public var serverVersion: NSNumber?
    @NSManaged public var syncStatus: Int16
    @NSManaged public var lastSyncedAt: Date?
    @NSManaged public var isDeleted: Bool
    @NSManaged public var latitude: NSNumber?
    @NSManaged public var longitude: NSNumber?
    @NSManaged public var locationName: String?
    @NSManaged public var locationRadius: NSNumber?
    @NSManaged public var url: String?
    @NSManaged public var energyLevel: NSNumber?
    @NSManaged public var estimatedDuration: NSNumber?

    // MARK: - Relationships

    @NSManaged public var list: CDTaskList?
    @NSManaged public var tags: NSSet?
    @NSManaged public var attachments: NSSet?
    @NSManaged public var calendarLinks: NSSet?
    @NSManaged public var parentTask: CDTask?
    @NSManaged public var subtasks: NSSet?

    // MARK: - Fetch Request

    @nonobjc public class func fetchRequest() -> NSFetchRequest<CDTask> {
        return NSFetchRequest<CDTask>(entityName: "CDTask")
    }

    // MARK: - Convenience Properties

    public var priorityLevel: TaskPriority {
        get { TaskPriority(rawValue: priority) ?? .none }
        set { priority = newValue.rawValue }
    }

    public var currentSyncStatus: SyncStatus {
        get { SyncStatus(rawValue: syncStatus) ?? .synced }
        set { syncStatus = newValue.rawValue }
    }

    public var tagsArray: [CDTag] {
        get { tags?.allObjects as? [CDTag] ?? [] }
    }

    public var attachmentsArray: [CDAttachmentRef] {
        get { attachments?.allObjects as? [CDAttachmentRef] ?? [] }
    }

    public var subtasksArray: [CDTask] {
        get { subtasks?.allObjects as? [CDTask] ?? [] }
    }

    public var calendarLinksArray: [CDCalendarLink] {
        get { calendarLinks?.allObjects as? [CDCalendarLink] ?? [] }
    }

    public var hasLocation: Bool {
        latitude != nil && longitude != nil
    }

    public var isOverdue: Bool {
        guard let dueDate = dueDate, !isCompleted else { return false }
        return dueDate < Date()
    }

    public var isDueToday: Bool {
        guard let dueDate = dueDate else { return false }
        return Calendar.current.isDateInToday(dueDate)
    }

    public var isDueTomorrow: Bool {
        guard let dueDate = dueDate else { return false }
        return Calendar.current.isDateInTomorrow(dueDate)
    }

    public var isDueThisWeek: Bool {
        guard let dueDate = dueDate else { return false }
        return Calendar.current.isDate(dueDate, equalTo: Date(), toGranularity: .weekOfYear)
    }
}

// MARK: - CDTask Generated Accessors

extension CDTask {
    @objc(addTagsObject:)
    @NSManaged public func addToTags(_ value: CDTag)

    @objc(removeTagsObject:)
    @NSManaged public func removeFromTags(_ value: CDTag)

    @objc(addTags:)
    @NSManaged public func addToTags(_ values: NSSet)

    @objc(removeTags:)
    @NSManaged public func removeFromTags(_ values: NSSet)

    @objc(addAttachmentsObject:)
    @NSManaged public func addToAttachments(_ value: CDAttachmentRef)

    @objc(removeAttachmentsObject:)
    @NSManaged public func removeFromAttachments(_ value: CDAttachmentRef)

    @objc(addSubtasksObject:)
    @NSManaged public func addToSubtasks(_ value: CDTask)

    @objc(removeSubtasksObject:)
    @NSManaged public func removeFromSubtasks(_ value: CDTask)

    @objc(addCalendarLinksObject:)
    @NSManaged public func addToCalendarLinks(_ value: CDCalendarLink)

    @objc(removeCalendarLinksObject:)
    @NSManaged public func removeFromCalendarLinks(_ value: CDCalendarLink)
}

// MARK: - CDTaskList Entity

/**
 CDTaskList Entity - Represents a task list/project

 Attributes:
 - id: String (required) - Unique identifier
 - name: String (required) - List name
 - icon: String? - SF Symbol name
 - color: String? - Hex color code
 - sortOrder: Int32 - Display order
 - isDefault: Bool - Whether this is the default list
 - smartFilter: String? - JSON-encoded filter for smart lists
 - isSmartList: Bool - Whether this is a smart/filtered list
 - createdAt: Date (required) - Creation timestamp
 - modifiedAt: Date (required) - Last modification timestamp
 - serverVersion: Int64? - Server version
 - syncStatus: Int16 - Sync status
 - lastSyncedAt: Date? - Last sync timestamp
 - isDeleted: Bool - Soft delete flag
 - ownerId: String? - Owner user ID
 - sharedWith: [String]? - User IDs shared with (transformable)

 Relationships:
 - tasks: Set<CDTask> - Tasks in this list (to-many, cascade delete)
 */
@objc(CDTaskList)
public class CDTaskList: NSManagedObject {

    // MARK: - Attributes

    @NSManaged public var id: String
    @NSManaged public var name: String
    @NSManaged public var icon: String?
    @NSManaged public var color: String?
    @NSManaged public var sortOrder: Int32
    @NSManaged public var isDefault: Bool
    @NSManaged public var smartFilter: String?
    @NSManaged public var isSmartList: Bool
    @NSManaged public var createdAt: Date
    @NSManaged public var modifiedAt: Date
    @NSManaged public var serverVersion: NSNumber?
    @NSManaged public var syncStatus: Int16
    @NSManaged public var lastSyncedAt: Date?
    @NSManaged public var isDeleted: Bool
    @NSManaged public var ownerId: String?
    @NSManaged public var sharedWith: NSArray?

    // MARK: - Relationships

    @NSManaged public var tasks: NSSet?

    // MARK: - Fetch Request

    @nonobjc public class func fetchRequest() -> NSFetchRequest<CDTaskList> {
        return NSFetchRequest<CDTaskList>(entityName: "CDTaskList")
    }

    // MARK: - Convenience Properties

    public var currentSyncStatus: SyncStatus {
        get { SyncStatus(rawValue: syncStatus) ?? .synced }
        set { syncStatus = newValue.rawValue }
    }

    public var tasksArray: [CDTask] {
        get { tasks?.allObjects as? [CDTask] ?? [] }
    }

    public var taskCount: Int {
        tasks?.count ?? 0
    }

    public var completedTaskCount: Int {
        tasksArray.filter { $0.isCompleted }.count
    }

    public var incompleteTaskCount: Int {
        tasksArray.filter { !$0.isCompleted }.count
    }

    public var isShared: Bool {
        (sharedWith?.count ?? 0) > 0
    }
}

// MARK: - CDTaskList Generated Accessors

extension CDTaskList {
    @objc(addTasksObject:)
    @NSManaged public func addToTasks(_ value: CDTask)

    @objc(removeTasksObject:)
    @NSManaged public func removeFromTasks(_ value: CDTask)

    @objc(addTasks:)
    @NSManaged public func addToTasks(_ values: NSSet)

    @objc(removeTasks:)
    @NSManaged public func removeFromTasks(_ values: NSSet)
}

// MARK: - CDTag Entity

/**
 CDTag Entity - Represents a tag for categorizing tasks

 Attributes:
 - id: String (required) - Unique identifier
 - name: String (required) - Tag name
 - color: String? - Hex color code
 - createdAt: Date (required) - Creation timestamp
 - modifiedAt: Date? - Last modification timestamp
 - serverVersion: Int64? - Server version
 - syncStatus: Int16 - Sync status
 - isDeleted: Bool - Soft delete flag

 Relationships:
 - tasks: Set<CDTask> - Tasks with this tag (to-many)
 */
@objc(CDTag)
public class CDTag: NSManagedObject {

    // MARK: - Attributes

    @NSManaged public var id: String
    @NSManaged public var name: String
    @NSManaged public var color: String?
    @NSManaged public var createdAt: Date
    @NSManaged public var modifiedAt: Date?
    @NSManaged public var serverVersion: NSNumber?
    @NSManaged public var syncStatus: Int16
    @NSManaged public var isDeleted: Bool

    // MARK: - Relationships

    @NSManaged public var tasks: NSSet?

    // MARK: - Fetch Request

    @nonobjc public class func fetchRequest() -> NSFetchRequest<CDTag> {
        return NSFetchRequest<CDTag>(entityName: "CDTag")
    }

    // MARK: - Convenience Properties

    public var currentSyncStatus: SyncStatus {
        get { SyncStatus(rawValue: syncStatus) ?? .synced }
        set { syncStatus = newValue.rawValue }
    }

    public var tasksArray: [CDTask] {
        get { tasks?.allObjects as? [CDTask] ?? [] }
    }

    public var taskCount: Int {
        tasks?.count ?? 0
    }
}

// MARK: - CDTag Generated Accessors

extension CDTag {
    @objc(addTasksObject:)
    @NSManaged public func addToTasks(_ value: CDTask)

    @objc(removeTasksObject:)
    @NSManaged public func removeFromTasks(_ value: CDTask)

    @objc(addTasks:)
    @NSManaged public func addToTasks(_ values: NSSet)

    @objc(removeTasks:)
    @NSManaged public func removeFromTasks(_ values: NSSet)
}

// MARK: - CDAttachmentRef Entity

/**
 CDAttachmentRef Entity - Represents a file attachment reference

 Attributes:
 - id: String (required) - Unique identifier
 - taskId: String (required) - Parent task ID (denormalized)
 - fileName: String (required) - Original file name
 - mimeType: String? - MIME type
 - fileSize: Int64? - File size in bytes
 - localPath: String? - Local file path
 - remoteURL: String? - Remote storage URL
 - thumbnailPath: String? - Local thumbnail path
 - createdAt: Date (required) - Creation timestamp
 - uploadStatus: Int16 - Upload status
 - uploadProgress: Double? - Upload progress (0.0 - 1.0)

 Relationships:
 - task: CDTask? - Parent task (to-one)
 */
@objc(CDAttachmentRef)
public class CDAttachmentRef: NSManagedObject {

    // MARK: - Attributes

    @NSManaged public var id: String
    @NSManaged public var taskId: String
    @NSManaged public var fileName: String
    @NSManaged public var mimeType: String?
    @NSManaged public var fileSize: NSNumber?
    @NSManaged public var localPath: String?
    @NSManaged public var remoteURL: String?
    @NSManaged public var thumbnailPath: String?
    @NSManaged public var createdAt: Date
    @NSManaged public var uploadStatus: Int16
    @NSManaged public var uploadProgress: NSNumber?

    // MARK: - Relationships

    @NSManaged public var task: CDTask?

    // MARK: - Fetch Request

    @nonobjc public class func fetchRequest() -> NSFetchRequest<CDAttachmentRef> {
        return NSFetchRequest<CDAttachmentRef>(entityName: "CDAttachmentRef")
    }

    // MARK: - Convenience Properties

    public var currentUploadStatus: UploadStatus {
        get { UploadStatus(rawValue: uploadStatus) ?? .pending }
        set { uploadStatus = newValue.rawValue }
    }

    public var isUploaded: Bool {
        currentUploadStatus == .completed && remoteURL != nil
    }

    public var isImage: Bool {
        guard let mimeType = mimeType else { return false }
        return mimeType.hasPrefix("image/")
    }

    public var isVideo: Bool {
        guard let mimeType = mimeType else { return false }
        return mimeType.hasPrefix("video/")
    }

    public var isPDF: Bool {
        mimeType == "application/pdf"
    }

    public var localURL: URL? {
        guard let localPath = localPath else { return nil }
        return URL(fileURLWithPath: localPath)
    }

    public var remote: URL? {
        guard let remoteURL = remoteURL else { return nil }
        return URL(string: remoteURL)
    }
}

// MARK: - CDPendingEvent Entity

/**
 CDPendingEvent Entity - Outbox queue for offline-first sync

 Stores local changes that need to be synced to the server.
 Implements FIFO queue with retry logic.

 Attributes:
 - id: String (required) - Unique identifier
 - eventType: String (required) - Type of event (create, update, delete)
 - entityType: String (required) - Type of entity (task, list, tag)
 - entityId: String (required) - ID of the affected entity
 - payload: String (required) - JSON-encoded event data
 - createdAt: Date (required) - When the event was created
 - sequence: Int64 (required) - Monotonic sequence number for ordering
 - retryCount: Int16 - Number of retry attempts
 - lastAttemptAt: Date? - Last processing attempt
 - nextRetryAt: Date? - Scheduled next retry time
 - errorMessage: String? - Last error message
 - status: Int16 - Event status

 Indexes:
 - byProcessingOrder: status, sequence
 */
@objc(CDPendingEvent)
public class CDPendingEvent: NSManagedObject {

    // MARK: - Constants

    public static let maxRetryCount: Int16 = 5
    public static let baseRetryDelay: TimeInterval = 1.0 // seconds

    // MARK: - Attributes

    @NSManaged public var id: String
    @NSManaged public var eventType: String
    @NSManaged public var entityType: String
    @NSManaged public var entityId: String
    @NSManaged public var payload: String
    @NSManaged public var createdAt: Date
    @NSManaged public var sequence: Int64
    @NSManaged public var retryCount: Int16
    @NSManaged public var lastAttemptAt: Date?
    @NSManaged public var nextRetryAt: Date?
    @NSManaged public var errorMessage: String?
    @NSManaged public var status: Int16

    // MARK: - Fetch Request

    @nonobjc public class func fetchRequest() -> NSFetchRequest<CDPendingEvent> {
        return NSFetchRequest<CDPendingEvent>(entityName: "CDPendingEvent")
    }

    // MARK: - Convenience Properties

    public var currentStatus: EventStatus {
        get { EventStatus(rawValue: status) ?? .pending }
        set { status = newValue.rawValue }
    }

    public var canRetry: Bool {
        retryCount < Self.maxRetryCount && currentStatus != .cancelled
    }

    public var isReadyForProcessing: Bool {
        guard currentStatus == .pending else { return false }
        if let nextRetryAt = nextRetryAt {
            return Date() >= nextRetryAt
        }
        return true
    }

    /// Calculate exponential backoff delay for retries
    public var nextRetryDelay: TimeInterval {
        // Exponential backoff: 1s, 2s, 4s, 8s, 16s
        return Self.baseRetryDelay * pow(2.0, Double(retryCount))
    }

    /// Schedule the next retry
    public func scheduleRetry() {
        retryCount += 1
        lastAttemptAt = Date()
        nextRetryAt = Date().addingTimeInterval(nextRetryDelay)

        if retryCount >= Self.maxRetryCount {
            currentStatus = .failed
        } else {
            currentStatus = .pending
        }
    }
}

// MARK: - Event Type Constants

extension CDPendingEvent {
    public struct EventTypes {
        public static let create = "create"
        public static let update = "update"
        public static let delete = "delete"
        public static let complete = "complete"
        public static let uncomplete = "uncomplete"
        public static let move = "move"
        public static let reorder = "reorder"
        public static let addTag = "addTag"
        public static let removeTag = "removeTag"
    }

    public struct EntityTypes {
        public static let task = "task"
        public static let taskList = "taskList"
        public static let tag = "tag"
        public static let attachment = "attachment"
    }
}

// MARK: - CDSyncState Entity

/**
 CDSyncState Entity - Tracks sync metadata and cursors

 Stores server cursors, last sync times, and sync statistics.
 Used for incremental sync and conflict resolution.

 Attributes:
 - key: String (required) - Unique key for this sync state (e.g., "tasks", "lists")
 - cursor: String? - Server cursor for pagination
 - serverVersion: Int64? - Last known server version
 - lastSyncStarted: Date? - When last sync started
 - lastSyncCompleted: Date? - When last sync completed successfully
 - lastSyncError: String? - Last sync error message
 - lastFullSyncAt: Date? - When last full sync was performed
 - fullSyncRequired: Bool - Whether a full sync is needed
 - totalSyncs: Int64 - Total number of syncs performed
 - failedSyncs: Int64 - Number of failed syncs
 */
@objc(CDSyncState)
public class CDSyncState: NSManagedObject {

    // MARK: - Attributes

    @NSManaged public var key: String
    @NSManaged public var cursor: String?
    @NSManaged public var serverVersion: NSNumber?
    @NSManaged public var lastSyncStarted: Date?
    @NSManaged public var lastSyncCompleted: Date?
    @NSManaged public var lastSyncError: String?
    @NSManaged public var lastFullSyncAt: Date?
    @NSManaged public var fullSyncRequired: Bool
    @NSManaged public var totalSyncs: Int64
    @NSManaged public var failedSyncs: Int64

    // MARK: - Fetch Request

    @nonobjc public class func fetchRequest() -> NSFetchRequest<CDSyncState> {
        return NSFetchRequest<CDSyncState>(entityName: "CDSyncState")
    }

    // MARK: - Convenience Properties

    public var isSyncing: Bool {
        guard let started = lastSyncStarted else { return false }
        if let completed = lastSyncCompleted {
            return started > completed
        }
        return true
    }

    public var hasEverSynced: Bool {
        lastSyncCompleted != nil
    }

    public var syncSuccessRate: Double {
        guard totalSyncs > 0 else { return 0 }
        let successfulSyncs = totalSyncs - failedSyncs
        return Double(successfulSyncs) / Double(totalSyncs)
    }

    public var timeSinceLastSync: TimeInterval? {
        guard let lastSync = lastSyncCompleted else { return nil }
        return Date().timeIntervalSince(lastSync)
    }

    /// Check if a sync is needed based on time threshold
    public func needsSync(threshold: TimeInterval = 300) -> Bool {
        if fullSyncRequired { return true }
        guard let timeSinceLastSync = timeSinceLastSync else { return true }
        return timeSinceLastSync >= threshold
    }

    /// Record a sync start
    public func recordSyncStarted() {
        lastSyncStarted = Date()
    }

    /// Record a successful sync completion
    public func recordSyncCompleted(cursor: String? = nil, serverVersion: Int64? = nil) {
        lastSyncCompleted = Date()
        lastSyncError = nil
        totalSyncs += 1
        fullSyncRequired = false

        if let cursor = cursor {
            self.cursor = cursor
        }
        if let version = serverVersion {
            self.serverVersion = NSNumber(value: version)
        }
    }

    /// Record a sync failure
    public func recordSyncFailed(error: String) {
        lastSyncError = error
        failedSyncs += 1
        totalSyncs += 1
    }
}

// MARK: - Sync State Keys

extension CDSyncState {
    public struct Keys {
        public static let tasks = "tasks"
        public static let lists = "taskLists"
        public static let tags = "tags"
        public static let global = "global"
    }
}

// MARK: - CDCalendarLink Entity

/**
 CDCalendarLink Entity - Links tasks to calendar events

 Enables two-way sync between tasks and calendar events.

 Attributes:
 - id: String (required) - Unique identifier
 - taskId: String (required) - Associated task ID
 - calendarEventId: String (required) - Calendar event identifier
 - calendarId: String? - Calendar identifier
 - syncDirection: Int16 - Sync direction (task->calendar, calendar->task, bidirectional)
 - createdAt: Date (required) - Creation timestamp
 - lastSyncedAt: Date? - Last sync timestamp
 - taskModifiedAt: Date? - Task modification time at last sync
 - eventModifiedAt: Date? - Calendar event modification time at last sync

 Relationships:
 - task: CDTask? - Associated task (to-one)
 */
@objc(CDCalendarLink)
public class CDCalendarLink: NSManagedObject {

    // MARK: - Attributes

    @NSManaged public var id: String
    @NSManaged public var taskId: String
    @NSManaged public var calendarEventId: String
    @NSManaged public var calendarId: String?
    @NSManaged public var syncDirection: Int16
    @NSManaged public var createdAt: Date
    @NSManaged public var lastSyncedAt: Date?
    @NSManaged public var taskModifiedAt: Date?
    @NSManaged public var eventModifiedAt: Date?

    // MARK: - Relationships

    @NSManaged public var task: CDTask?

    // MARK: - Fetch Request

    @nonobjc public class func fetchRequest() -> NSFetchRequest<CDCalendarLink> {
        return NSFetchRequest<CDCalendarLink>(entityName: "CDCalendarLink")
    }

    // MARK: - Convenience Properties

    public var direction: CalendarSyncDirection {
        get { CalendarSyncDirection(rawValue: syncDirection) ?? .taskToCalendar }
        set { syncDirection = newValue.rawValue }
    }

    /// Determines if the task needs to be updated from the calendar
    public var taskNeedsUpdate: Bool {
        guard direction != .taskToCalendar else { return false }
        guard let eventModified = eventModifiedAt,
              let taskModified = taskModifiedAt else { return false }
        return eventModified > taskModified
    }

    /// Determines if the calendar event needs to be updated from the task
    public var eventNeedsUpdate: Bool {
        guard direction != .calendarToTask else { return false }
        guard let eventModified = eventModifiedAt,
              let taskModified = taskModifiedAt else { return false }
        return taskModified > eventModified
    }

    /// Record a sync operation
    public func recordSync(taskModified: Date?, eventModified: Date?) {
        lastSyncedAt = Date()
        taskModifiedAt = taskModified
        eventModifiedAt = eventModified
    }
}

// MARK: - NSManagedObject Identifiable Conformance

extension CDTask: Identifiable {}
extension CDTaskList: Identifiable {}
extension CDTag: Identifiable {}
extension CDAttachmentRef: Identifiable {}
extension CDPendingEvent: Identifiable {}
extension CDSyncState: Identifiable {
    public var id: String { key }
}
extension CDCalendarLink: Identifiable {}
