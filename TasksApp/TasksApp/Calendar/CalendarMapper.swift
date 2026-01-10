//
//  CalendarMapper.swift
//  TasksApp
//
//  Maps between Task and EKEvent models
//  Handles conversion, URL deep links, and recurrence rules
//

import EventKit
import Foundation

// MARK: - Calendar Mapper

/// Utility for mapping between Task and EKEvent models
enum CalendarMapper {

    // MARK: - Constants

    /// Default duration for all-day events when no time is specified
    private static let defaultAllDayDuration: TimeInterval = 86400 // 24 hours

    /// Default duration for timed events
    private static let defaultTimedDuration: TimeInterval = 3600 // 1 hour

    // MARK: - Task to Event

    /// Updates an EKEvent with data from a Task
    /// - Parameters:
    ///   - event: The EKEvent to update
    ///   - task: The source Task
    static func updateEvent(_ event: EKEvent, from task: TaskModel) {
        // Set title
        event.title = task.title

        // Set notes with task link marker for fallback identification
        event.notes = buildEventNotes(from: task)

        // Set URL for deep linking
        event.url = buildTaskURL(for: task)

        // Set dates
        configureDates(for: event, from: task)

        // Set recurrence rules
        configureRecurrence(for: event, from: task)

        // Set alarms based on task priority
        configureAlarms(for: event, from: task)
    }

    /// Creates an EKEvent from a Task
    /// - Parameters:
    ///   - task: The source Task
    ///   - eventStore: The EKEventStore to use
    ///   - calendar: The calendar to add the event to
    /// - Returns: The configured EKEvent
    static func createEvent(from task: TaskModel, eventStore: EKEventStore, calendar: EKCalendar) -> EKEvent {
        let event = EKEvent(eventStore: eventStore)
        event.calendar = calendar
        updateEvent(event, from: task)
        return event
    }

    // MARK: - Event to Task

    /// Creates a Task from an EKEvent
    /// - Parameters:
    ///   - event: The source EKEvent
    ///   - defaultListId: The list ID to assign to the new task
    /// - Returns: A new Task, or nil if the event cannot be converted
    static func taskFromEvent(_ event: EKEvent, defaultListId: String = "inbox") -> TaskModel? {
        guard let title = event.title, !title.isEmpty else {
            return nil
        }

        // Extract original notes (remove task link marker if present)
        let notes = extractOriginalNotes(from: event.notes)

        // Determine due date
        let dueDate = event.isAllDay ? event.startDate : event.startDate
        let dueTime = event.isAllDay ? nil : event.startDate

        // Convert recurrence
        let repeatRule = recurrenceRule(from: event)

        // Determine priority based on alarms
        let priority = priorityFromAlarms(event.alarms)

        // Create event source for tracking
        let eventSource = EventSource(
            sourceType: .appleCalendar,
            originalEventId: event.eventIdentifier,
            calendarId: event.calendar.calendarIdentifier,
            lastSyncedAt: Date(),
            sourceUrl: event.url?.absoluteString
        )

        return TaskModel(
            title: title,
            notes: notes,
            dueDate: dueDate,
            dueTime: dueTime,
            repeatRule: repeatRule,
            priority: priority,
            importedFromCalendar: true,
            eventSource: eventSource,
            listId: defaultListId
        )
    }

    // MARK: - Notes Handling

    /// Builds event notes including the task link marker
    private static func buildEventNotes(from task: TaskModel) -> String {
        var parts: [String] = []

        // Add original notes if present
        if let notes = task.notes, !notes.isEmpty {
            parts.append(notes)
        }

        // Add task link marker
        parts.append("\(CalendarSyncConfig.taskLinkMarker)\(task.id)\(CalendarSyncConfig.taskLinkMarkerEnd)")

        return parts.joined(separator: "\n\n")
    }

    /// Extracts original notes by removing the task link marker
    private static func extractOriginalNotes(from notes: String?) -> String? {
        guard let notes = notes else { return nil }

        // Find and remove task link marker
        let markerStart = CalendarSyncConfig.taskLinkMarker
        let markerEnd = CalendarSyncConfig.taskLinkMarkerEnd

        if let startRange = notes.range(of: markerStart),
           let endRange = notes.range(of: markerEnd, range: startRange.upperBound..<notes.endIndex) {
            var cleanNotes = notes
            cleanNotes.removeSubrange(startRange.lowerBound..<endRange.upperBound)
            cleanNotes = cleanNotes.trimmingCharacters(in: .whitespacesAndNewlines)
            return cleanNotes.isEmpty ? nil : cleanNotes
        }

        return notes.isEmpty ? nil : notes
    }

    /// Extracts task ID from event notes if present
    static func extractTaskId(from notes: String?) -> String? {
        guard let notes = notes else { return nil }

        let markerStart = CalendarSyncConfig.taskLinkMarker
        let markerEnd = CalendarSyncConfig.taskLinkMarkerEnd

        if let startRange = notes.range(of: markerStart),
           let endRange = notes.range(of: markerEnd, range: startRange.upperBound..<notes.endIndex) {
            return String(notes[startRange.upperBound..<endRange.lowerBound])
        }

        return nil
    }

    // MARK: - URL Deep Linking

    /// Builds a deep link URL for a task
    private static func buildTaskURL(for task: TaskModel) -> URL? {
        var components = URLComponents()
        components.scheme = CalendarSyncConfig.taskURLScheme
        components.host = "task"
        components.path = "/\(task.id)"
        return components.url
    }

    /// Extracts task ID from a deep link URL
    static func extractTaskId(from url: URL?) -> String? {
        guard let url = url,
              url.scheme == CalendarSyncConfig.taskURLScheme,
              url.host == "task" else {
            return nil
        }

        let path = url.path
        if path.hasPrefix("/") {
            return String(path.dropFirst())
        }
        return path.isEmpty ? nil : path
    }

    // MARK: - Date Configuration

    /// Configures dates for an event based on task due date/time
    private static func configureDates(for event: EKEvent, from task: TaskModel) {
        if let dueDate = task.dueDate {
            if let dueTime = task.dueTime {
                // Combine date and time
                let calendar = Calendar.current
                let dateComponents = calendar.dateComponents([.year, .month, .day], from: dueDate)
                let timeComponents = calendar.dateComponents([.hour, .minute], from: dueTime)

                var combinedComponents = DateComponents()
                combinedComponents.year = dateComponents.year
                combinedComponents.month = dateComponents.month
                combinedComponents.day = dateComponents.day
                combinedComponents.hour = timeComponents.hour
                combinedComponents.minute = timeComponents.minute

                if let combinedDate = calendar.date(from: combinedComponents) {
                    event.startDate = combinedDate
                    event.endDate = combinedDate.addingTimeInterval(defaultTimedDuration)
                    event.isAllDay = false
                } else {
                    configureFallbackAllDay(event: event, date: dueDate)
                }
            } else {
                // All-day event
                configureFallbackAllDay(event: event, date: dueDate)
            }
        } else {
            // No due date - use tomorrow as default
            let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
            configureFallbackAllDay(event: event, date: tomorrow)
        }
    }

    private static func configureFallbackAllDay(event: EKEvent, date: Date) {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        event.startDate = startOfDay
        event.endDate = startOfDay.addingTimeInterval(defaultAllDayDuration)
        event.isAllDay = true
    }

    // MARK: - Recurrence Rules

    /// Configures recurrence rules on an event
    private static func configureRecurrence(for event: EKEvent, from task: TaskModel) {
        // Clear existing rules
        event.recurrenceRules?.forEach { event.removeRecurrenceRule($0) }

        guard let repeatRule = task.repeatRule else { return }

        var recurrenceRule: EKRecurrenceRule?

        switch repeatRule.frequency {
        case .daily:
            recurrenceRule = EKRecurrenceRule(
                recurrenceWith: .daily,
                interval: repeatRule.interval,
                end: recurrenceEnd(from: repeatRule)
            )

        case .weekly:
            let daysOfWeek = weekDays(from: repeatRule.weekDays)
            recurrenceRule = EKRecurrenceRule(
                recurrenceWith: .weekly,
                interval: repeatRule.interval,
                daysOfTheWeek: daysOfWeek.isEmpty ? nil : daysOfWeek,
                daysOfTheMonth: nil,
                monthsOfTheYear: nil,
                weeksOfTheYear: nil,
                daysOfTheYear: nil,
                setPositions: nil,
                end: recurrenceEnd(from: repeatRule)
            )

        case .monthly:
            var daysOfMonth: [NSNumber]? = nil
            if let dayOfMonth = repeatRule.dayOfMonth {
                daysOfMonth = [NSNumber(value: dayOfMonth)]
            }
            recurrenceRule = EKRecurrenceRule(
                recurrenceWith: .monthly,
                interval: repeatRule.interval,
                daysOfTheWeek: nil,
                daysOfTheMonth: daysOfMonth,
                monthsOfTheYear: nil,
                weeksOfTheYear: nil,
                daysOfTheYear: nil,
                setPositions: nil,
                end: recurrenceEnd(from: repeatRule)
            )

        case .yearly:
            var monthsOfYear: [NSNumber]? = nil
            var daysOfMonth: [NSNumber]? = nil
            if let month = repeatRule.monthOfYear {
                monthsOfYear = [NSNumber(value: month)]
            }
            if let day = repeatRule.dayOfMonth {
                daysOfMonth = [NSNumber(value: day)]
            }
            recurrenceRule = EKRecurrenceRule(
                recurrenceWith: .yearly,
                interval: repeatRule.interval,
                daysOfTheWeek: nil,
                daysOfTheMonth: daysOfMonth,
                monthsOfTheYear: monthsOfYear,
                weeksOfTheYear: nil,
                daysOfTheYear: nil,
                setPositions: nil,
                end: recurrenceEnd(from: repeatRule)
            )

        case .custom:
            // For custom, try to use daily as a fallback
            recurrenceRule = EKRecurrenceRule(
                recurrenceWith: .daily,
                interval: repeatRule.interval,
                end: recurrenceEnd(from: repeatRule)
            )
        }

        if let rule = recurrenceRule {
            event.addRecurrenceRule(rule)
        }
    }

    /// Converts RepeatRule.WeekDay to EKRecurrenceDayOfWeek array
    private static func weekDays(from weekDay: RepeatRule.WeekDay?) -> [EKRecurrenceDayOfWeek] {
        guard let weekDay = weekDay else { return [] }

        var days: [EKRecurrenceDayOfWeek] = []

        if weekDay.contains(.sunday) { days.append(EKRecurrenceDayOfWeek(.sunday)) }
        if weekDay.contains(.monday) { days.append(EKRecurrenceDayOfWeek(.monday)) }
        if weekDay.contains(.tuesday) { days.append(EKRecurrenceDayOfWeek(.tuesday)) }
        if weekDay.contains(.wednesday) { days.append(EKRecurrenceDayOfWeek(.wednesday)) }
        if weekDay.contains(.thursday) { days.append(EKRecurrenceDayOfWeek(.thursday)) }
        if weekDay.contains(.friday) { days.append(EKRecurrenceDayOfWeek(.friday)) }
        if weekDay.contains(.saturday) { days.append(EKRecurrenceDayOfWeek(.saturday)) }

        return days
    }

    /// Creates a recurrence end from RepeatRule
    private static func recurrenceEnd(from rule: RepeatRule) -> EKRecurrenceEnd? {
        if let endDate = rule.endDate {
            return EKRecurrenceEnd(end: endDate)
        } else if let count = rule.occurrenceCount {
            return EKRecurrenceEnd(occurrenceCount: count)
        }
        return nil
    }

    /// Converts EKEvent recurrence to RepeatRule
    private static func recurrenceRule(from event: EKEvent) -> RepeatRule? {
        guard let rules = event.recurrenceRules, let rule = rules.first else {
            return nil
        }

        let frequency: RepeatRule.Frequency
        switch rule.frequency {
        case .daily:
            frequency = .daily
        case .weekly:
            frequency = .weekly
        case .monthly:
            frequency = .monthly
        case .yearly:
            frequency = .yearly
        @unknown default:
            frequency = .custom
        }

        var weekDays: RepeatRule.WeekDay? = nil
        if let daysOfWeek = rule.daysOfTheWeek {
            var days = RepeatRule.WeekDay()
            for day in daysOfWeek {
                switch day.dayOfTheWeek {
                case .sunday: days.insert(.sunday)
                case .monday: days.insert(.monday)
                case .tuesday: days.insert(.tuesday)
                case .wednesday: days.insert(.wednesday)
                case .thursday: days.insert(.thursday)
                case .friday: days.insert(.friday)
                case .saturday: days.insert(.saturday)
                @unknown default: break
                }
            }
            weekDays = days
        }

        var dayOfMonth: Int? = nil
        if let days = rule.daysOfTheMonth, let first = days.first {
            dayOfMonth = first.intValue
        }

        var monthOfYear: Int? = nil
        if let months = rule.monthsOfTheYear, let first = months.first {
            monthOfYear = first.intValue
        }

        var endDate: Date? = nil
        var occurrenceCount: Int? = nil
        if let end = rule.recurrenceEnd {
            if let date = end.endDate {
                endDate = date
            } else if end.occurrenceCount > 0 {
                occurrenceCount = end.occurrenceCount
            }
        }

        return RepeatRule(
            frequency: frequency,
            interval: rule.interval,
            weekDays: weekDays,
            dayOfMonth: dayOfMonth,
            monthOfYear: monthOfYear,
            endDate: endDate,
            occurrenceCount: occurrenceCount
        )
    }

    // MARK: - Alarms and Priority

    /// Configures alarms based on task priority
    private static func configureAlarms(for event: EKEvent, from task: TaskModel) {
        // Clear existing alarms
        event.alarms?.forEach { event.removeAlarm($0) }

        // Add alarms based on priority
        switch task.priority {
        case .high:
            // Multiple reminders for high priority
            event.addAlarm(EKAlarm(relativeOffset: -3600)) // 1 hour before
            event.addAlarm(EKAlarm(relativeOffset: -1800)) // 30 min before
            event.addAlarm(EKAlarm(relativeOffset: 0)) // At time

        case .medium:
            event.addAlarm(EKAlarm(relativeOffset: -1800)) // 30 min before

        case .low:
            event.addAlarm(EKAlarm(relativeOffset: 0)) // At time only

        case .none:
            // No alarms for no priority
            break
        }

        // Add alarm if task has red beacon enabled (always remind)
        if task.redBeaconEnabled && task.priority == .none {
            event.addAlarm(EKAlarm(relativeOffset: -600)) // 10 min before
        }
    }

    /// Infers priority from event alarms
    private static func priorityFromAlarms(_ alarms: [EKAlarm]?) -> Priority {
        guard let alarms = alarms else { return .none }

        switch alarms.count {
        case 0:
            return .none
        case 1:
            return .low
        case 2:
            return .medium
        default:
            return .high
        }
    }

    // MARK: - Comparison Utilities

    /// Checks if a task and event are in sync
    static func isInSync(task: TaskModel, event: EKEvent) -> Bool {
        // Compare title
        guard task.title == event.title else { return false }

        // Compare notes (excluding task link marker)
        let eventNotes = extractOriginalNotes(from: event.notes)
        if task.notes != eventNotes {
            return false
        }

        // Compare dates
        if let dueDate = task.dueDate {
            guard let eventStart = event.startDate else { return false }

            if let dueTime = task.dueTime {
                // Compare full date/time
                let taskFullDate = task.fullDueDate ?? dueDate
                let calendar = Calendar.current
                let taskComponents = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: taskFullDate)
                let eventComponents = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: eventStart)

                if taskComponents != eventComponents {
                    return false
                }
            } else {
                // Compare date only for all-day
                let calendar = Calendar.current
                if !calendar.isDate(dueDate, inSameDayAs: eventStart) {
                    return false
                }
            }
        }

        return true
    }

    /// Determines which is more recent - task or event
    static func moreRecentSource(task: TaskModel, event: EKEvent, mapping: TaskEventMapping?) -> SyncSource {
        guard let mapping = mapping else { return .task }

        let taskUpdated = task.updatedAt
        let mappingTaskUpdated = mapping.taskUpdatedAt

        // If task was updated since last sync
        if taskUpdated > mappingTaskUpdated {
            return .task
        }

        // If event was updated since last sync
        if let eventUpdated = event.lastModifiedDate,
           let mappingEventUpdated = mapping.eventUpdatedAt,
           eventUpdated > mappingEventUpdated {
            return .event
        }

        // Default to task as source of truth
        return .task
    }
}

// MARK: - Sync Source

/// Indicates which source should be used for sync conflict resolution
enum SyncSource {
    case task
    case event
}

// MARK: - Extension for Date Comparison

extension EKEvent {
    /// The last modified date of the event
    var lastModifiedDateSafe: Date? {
        return lastModifiedDate
    }
}
