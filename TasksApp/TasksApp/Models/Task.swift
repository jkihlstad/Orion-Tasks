//
//  Task.swift
//  TasksApp
//
//  Domain model for Task entity
//

import Foundation

// MARK: - Priority

/// Task priority levels
enum Priority: Int, Codable, Hashable, CaseIterable, Sendable {
    case none = 0
    case low = 1
    case medium = 2
    case high = 3

    var displayName: String {
        switch self {
        case .none: return "None"
        case .low: return "Low"
        case .medium: return "Medium"
        case .high: return "High"
        }
    }

    var symbolName: String {
        switch self {
        case .none: return ""
        case .low: return "exclamationmark"
        case .medium: return "exclamationmark.2"
        case .high: return "exclamationmark.3"
        }
    }
}

// MARK: - RepeatRule

/// Defines recurrence patterns for repeating tasks
struct RepeatRule: Codable, Hashable, Sendable {

    /// The frequency of repetition
    enum Frequency: String, Codable, Hashable, CaseIterable, Sendable {
        case daily
        case weekly
        case monthly
        case yearly
        case custom
    }

    /// Days of the week for weekly recurrence
    struct WeekDay: OptionSet, Codable, Hashable, Sendable {
        let rawValue: Int

        static let sunday    = WeekDay(rawValue: 1 << 0)
        static let monday    = WeekDay(rawValue: 1 << 1)
        static let tuesday   = WeekDay(rawValue: 1 << 2)
        static let wednesday = WeekDay(rawValue: 1 << 3)
        static let thursday  = WeekDay(rawValue: 1 << 4)
        static let friday    = WeekDay(rawValue: 1 << 5)
        static let saturday  = WeekDay(rawValue: 1 << 6)

        static let weekdays: WeekDay = [.monday, .tuesday, .wednesday, .thursday, .friday]
        static let weekends: WeekDay = [.saturday, .sunday]
        static let allDays: WeekDay = [.sunday, .monday, .tuesday, .wednesday, .thursday, .friday, .saturday]
    }

    /// The type of recurrence
    let frequency: Frequency

    /// Interval between occurrences (e.g., every 2 weeks)
    let interval: Int

    /// Specific days for weekly recurrence
    let weekDays: WeekDay?

    /// Day of month for monthly recurrence (1-31)
    let dayOfMonth: Int?

    /// Month of year for yearly recurrence (1-12)
    let monthOfYear: Int?

    /// End date for the recurrence (nil means forever)
    let endDate: Date?

    /// Maximum number of occurrences (nil means unlimited)
    let occurrenceCount: Int?

    /// Creates a daily repeat rule
    static func daily(interval: Int = 1, endDate: Date? = nil) -> RepeatRule {
        RepeatRule(
            frequency: .daily,
            interval: interval,
            weekDays: nil,
            dayOfMonth: nil,
            monthOfYear: nil,
            endDate: endDate,
            occurrenceCount: nil
        )
    }

    /// Creates a weekly repeat rule
    static func weekly(
        interval: Int = 1,
        on days: WeekDay = .allDays,
        endDate: Date? = nil
    ) -> RepeatRule {
        RepeatRule(
            frequency: .weekly,
            interval: interval,
            weekDays: days,
            dayOfMonth: nil,
            monthOfYear: nil,
            endDate: endDate,
            occurrenceCount: nil
        )
    }

    /// Creates a monthly repeat rule
    static func monthly(
        interval: Int = 1,
        dayOfMonth: Int,
        endDate: Date? = nil
    ) -> RepeatRule {
        RepeatRule(
            frequency: .monthly,
            interval: interval,
            weekDays: nil,
            dayOfMonth: dayOfMonth,
            monthOfYear: nil,
            endDate: endDate,
            occurrenceCount: nil
        )
    }

    /// Creates a yearly repeat rule
    static func yearly(
        interval: Int = 1,
        month: Int,
        day: Int,
        endDate: Date? = nil
    ) -> RepeatRule {
        RepeatRule(
            frequency: .yearly,
            interval: interval,
            weekDays: nil,
            dayOfMonth: day,
            monthOfYear: month,
            endDate: endDate,
            occurrenceCount: nil
        )
    }

    /// Display string for the repeat rule
    var displayDescription: String {
        switch frequency {
        case .daily:
            return interval == 1 ? "Daily" : "Every \(interval) days"
        case .weekly:
            return interval == 1 ? "Weekly" : "Every \(interval) weeks"
        case .monthly:
            return interval == 1 ? "Monthly" : "Every \(interval) months"
        case .yearly:
            return interval == 1 ? "Yearly" : "Every \(interval) years"
        case .custom:
            return "Custom"
        }
    }
}

// MARK: - EventSource

/// Describes the origin of a task when imported from external sources
struct EventSource: Codable, Hashable, Sendable {
    /// The type of calendar source
    enum SourceType: String, Codable, Hashable, Sendable {
        case appleCalendar
        case googleCalendar
        case outlook
        case other
    }

    /// The source type
    let sourceType: SourceType

    /// Original event identifier from the source
    let originalEventId: String

    /// Calendar identifier from the source
    let calendarId: String?

    /// When the event was last synced from the source
    let lastSyncedAt: Date

    /// URL to the original event (if available)
    let sourceUrl: String?
}

// MARK: - TaskModel

/// Core Task model representing a single task/reminder
/// Note: Named TaskModel to avoid conflict with Swift's Task type for async operations
struct TaskModel: Identifiable, Codable, Hashable, Sendable {

    // MARK: - Identity

    /// Unique identifier for the task
    let id: String

    // MARK: - Core Properties

    /// The main title/name of the task
    var title: String

    /// Additional notes or description
    var notes: String?

    // MARK: - Scheduling

    /// The due date for the task (date only, no time component)
    var dueDate: Date?

    /// The due time for the task (used with dueDate for precise timing)
    var dueTime: Date?

    /// Recurrence rule for repeating tasks
    var repeatRule: RepeatRule?

    // MARK: - Organization

    /// Priority level of the task
    var priority: Priority

    /// Tag IDs associated with this task
    var tags: [String]

    /// Whether the task is flagged for quick access
    var flag: Bool

    // MARK: - Subtasks

    /// IDs of subtasks belonging to this task
    var subtasks: [String]

    // MARK: - Attachments

    /// Attachment references for media/files
    var attachments: [AttachmentRef]

    // MARK: - Beacon & Calendar Integration

    /// Whether the red beacon visual indicator is enabled
    var redBeaconEnabled: Bool

    /// Whether to mirror this task to the system calendar
    var mirrorToCalendarEnabled: Bool

    /// EventKit identifier when mirrored to calendar
    var linkedEventIdentifier: String?

    // MARK: - Import Metadata

    /// Whether this task was imported from a calendar event
    var importedFromCalendar: Bool

    /// Source information when imported from external calendar
    var eventSource: EventSource?

    // MARK: - Hierarchy

    /// ID of the list this task belongs to
    var listId: String

    /// ID of the parent task (for subtasks)
    var parentId: String?

    // MARK: - Timestamps

    /// When the task was completed (nil if not completed)
    var completedAt: Date?

    /// When the task was created
    let createdAt: Date

    /// When the task was last modified
    var updatedAt: Date

    // MARK: - Computed Properties

    /// Whether the task is completed
    var isCompleted: Bool {
        completedAt != nil
    }

    /// Whether this task is a subtask
    var isSubtask: Bool {
        parentId != nil
    }

    /// Whether the task is overdue
    var isOverdue: Bool {
        guard let dueDate = dueDate, !isCompleted else { return false }

        if let dueTime = dueTime {
            let calendar = Calendar.current
            let dueDateComponents = calendar.dateComponents([.year, .month, .day], from: dueDate)
            let dueTimeComponents = calendar.dateComponents([.hour, .minute, .second], from: dueTime)

            var combinedComponents = DateComponents()
            combinedComponents.year = dueDateComponents.year
            combinedComponents.month = dueDateComponents.month
            combinedComponents.day = dueDateComponents.day
            combinedComponents.hour = dueTimeComponents.hour
            combinedComponents.minute = dueTimeComponents.minute
            combinedComponents.second = dueTimeComponents.second

            if let combinedDate = calendar.date(from: combinedComponents) {
                return combinedDate < Date()
            }
        }

        return calendar.startOfDay(for: dueDate) < calendar.startOfDay(for: Date())
    }

    private var calendar: Calendar { Calendar.current }

    /// Whether the task is due today
    var isDueToday: Bool {
        guard let dueDate = dueDate else { return false }
        return calendar.isDateInToday(dueDate)
    }

    /// Whether the task has a time-specific reminder
    var hasTimeReminder: Bool {
        dueTime != nil
    }

    /// Combined due date and time
    var fullDueDate: Date? {
        guard let dueDate = dueDate else { return nil }
        guard let dueTime = dueTime else { return dueDate }

        let dueDateComponents = calendar.dateComponents([.year, .month, .day], from: dueDate)
        let dueTimeComponents = calendar.dateComponents([.hour, .minute, .second], from: dueTime)

        var combinedComponents = DateComponents()
        combinedComponents.year = dueDateComponents.year
        combinedComponents.month = dueDateComponents.month
        combinedComponents.day = dueDateComponents.day
        combinedComponents.hour = dueTimeComponents.hour
        combinedComponents.minute = dueTimeComponents.minute
        combinedComponents.second = dueTimeComponents.second

        return calendar.date(from: combinedComponents)
    }

    // MARK: - Initialization

    /// Creates a new task with default values
    init(
        id: String = UUID().uuidString,
        title: String,
        notes: String? = nil,
        dueDate: Date? = nil,
        dueTime: Date? = nil,
        repeatRule: RepeatRule? = nil,
        priority: Priority = .none,
        tags: [String] = [],
        flag: Bool = false,
        subtasks: [String] = [],
        attachments: [AttachmentRef] = [],
        redBeaconEnabled: Bool = false,
        mirrorToCalendarEnabled: Bool = false,
        linkedEventIdentifier: String? = nil,
        importedFromCalendar: Bool = false,
        eventSource: EventSource? = nil,
        listId: String,
        parentId: String? = nil,
        completedAt: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.dueDate = dueDate
        self.dueTime = dueTime
        self.repeatRule = repeatRule
        self.priority = priority
        self.tags = tags
        self.flag = flag
        self.subtasks = subtasks
        self.attachments = attachments
        self.redBeaconEnabled = redBeaconEnabled
        self.mirrorToCalendarEnabled = mirrorToCalendarEnabled
        self.linkedEventIdentifier = linkedEventIdentifier
        self.importedFromCalendar = importedFromCalendar
        self.eventSource = eventSource
        self.listId = listId
        self.parentId = parentId
        self.completedAt = completedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    // MARK: - Mutating Methods

    /// Marks the task as completed
    mutating func complete() {
        completedAt = Date()
        updatedAt = Date()
    }

    /// Marks the task as incomplete
    mutating func uncomplete() {
        completedAt = nil
        updatedAt = Date()
    }

    /// Toggles the completion status
    mutating func toggleCompletion() {
        if isCompleted {
            uncomplete()
        } else {
            complete()
        }
    }

    /// Toggles the flag status
    mutating func toggleFlag() {
        flag.toggle()
        updatedAt = Date()
    }

    /// Adds a tag to the task
    mutating func addTag(_ tagId: String) {
        guard !tags.contains(tagId) else { return }
        tags.append(tagId)
        updatedAt = Date()
    }

    /// Removes a tag from the task
    mutating func removeTag(_ tagId: String) {
        tags.removeAll { $0 == tagId }
        updatedAt = Date()
    }

    /// Adds a subtask reference
    mutating func addSubtask(_ subtaskId: String) {
        guard !subtasks.contains(subtaskId) else { return }
        subtasks.append(subtaskId)
        updatedAt = Date()
    }

    /// Removes a subtask reference
    mutating func removeSubtask(_ subtaskId: String) {
        subtasks.removeAll { $0 == subtaskId }
        updatedAt = Date()
    }

    /// Adds an attachment
    mutating func addAttachment(_ attachment: AttachmentRef) {
        attachments.append(attachment)
        updatedAt = Date()
    }

    /// Removes an attachment
    mutating func removeAttachment(withId attachmentId: String) {
        attachments.removeAll { $0.id == attachmentId }
        updatedAt = Date()
    }
}

// MARK: - TaskModel Hashable

extension TaskModel {
    static func == (lhs: TaskModel, rhs: TaskModel) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - Sample Data

extension TaskModel {
    /// Sample task for previews and testing
    static let sample = TaskModel(
        title: "Review project proposal",
        notes: "Check the budget section carefully",
        dueDate: Date().addingTimeInterval(86400),
        priority: .medium,
        tags: ["work"],
        flag: true,
        listId: TaskList.sample.id
    )

    /// Empty task for new task creation
    static func empty(in listId: String) -> TaskModel {
        TaskModel(title: "", listId: listId)
    }
}

// MARK: - Typealias for convenience

/// Typealias allowing use of `Task` in contexts where the model is needed
/// Use carefully - may still conflict with Swift.Task in async contexts
typealias OrionTask = TaskModel
