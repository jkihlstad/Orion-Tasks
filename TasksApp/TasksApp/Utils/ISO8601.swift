//
//  ISO8601.swift
//  TasksApp
//
//  Date formatting utilities for ISO8601, relative dates,
//  and due date display formatting
//

import Foundation

// MARK: - ISO8601 Date Formatter

/// Centralized date formatting utilities
struct DateFormatting {

    // MARK: - ISO8601 Formatters

    /// Standard ISO8601 formatter with internet date time format
    static let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    /// ISO8601 formatter without fractional seconds
    static let iso8601Simple: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    /// ISO8601 formatter for date only
    static let iso8601DateOnly: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        return formatter
    }()

    // MARK: - Standard Formatters

    /// Time only formatter (e.g., "2:30 PM")
    static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()

    /// Date only formatter (e.g., "Jan 15, 2025")
    static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .none
        formatter.dateStyle = .medium
        return formatter
    }()

    /// Short date formatter (e.g., "1/15/25")
    static let shortDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .none
        formatter.dateStyle = .short
        return formatter
    }()

    /// Full date and time formatter
    static let fullFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .medium
        return formatter
    }()

    /// Day of week formatter (e.g., "Monday")
    static let dayOfWeekFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        return formatter
    }()

    /// Short day of week formatter (e.g., "Mon")
    static let shortDayOfWeekFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter
    }()

    /// Month and day formatter (e.g., "Jan 15")
    static let monthDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter
    }()

    /// Month, day, and year formatter (e.g., "Jan 15, 2025")
    static let monthDayYearFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter
    }()

    // MARK: - ISO8601 Conversion

    /// Converts a Date to ISO8601 string
    static func toISO8601(_ date: Date) -> String {
        iso8601.string(from: date)
    }

    /// Converts an ISO8601 string to Date
    static func fromISO8601(_ string: String) -> Date? {
        // Try with fractional seconds first
        if let date = iso8601.date(from: string) {
            return date
        }
        // Fall back to simple format
        return iso8601Simple.date(from: string)
    }

    /// Converts a Date to ISO8601 date-only string
    static func toISO8601DateOnly(_ date: Date) -> String {
        iso8601DateOnly.string(from: date)
    }

    // MARK: - Standard Formatting

    /// Formats time only
    static func formatTime(_ date: Date) -> String {
        timeFormatter.string(from: date)
    }

    /// Formats date only
    static func formatDate(_ date: Date) -> String {
        dateFormatter.string(from: date)
    }

    /// Formats date and time
    static func formatDateTime(_ date: Date) -> String {
        fullFormatter.string(from: date)
    }
}

// MARK: - Relative Date Formatting

extension DateFormatting {

    /// Result type for relative date formatting
    enum RelativeDateResult {
        case today
        case tomorrow
        case yesterday
        case thisWeek(dayName: String)
        case nextWeek(dayName: String)
        case lastWeek(dayName: String)
        case thisYear(formatted: String)
        case otherYear(formatted: String)

        var displayString: String {
            switch self {
            case .today:
                return "Today"
            case .tomorrow:
                return "Tomorrow"
            case .yesterday:
                return "Yesterday"
            case .thisWeek(let dayName):
                return dayName
            case .nextWeek(let dayName):
                return "Next \(dayName)"
            case .lastWeek(let dayName):
                return "Last \(dayName)"
            case .thisYear(let formatted):
                return formatted
            case .otherYear(let formatted):
                return formatted
            }
        }
    }

    /// Determines the relative date category for display
    static func relativeDate(from date: Date, relativeTo referenceDate: Date = Date()) -> RelativeDateResult {
        let calendar = Calendar.current
        let now = referenceDate

        // Strip time components for date comparison
        let dateComponents = calendar.dateComponents([.year, .month, .day], from: date)
        let nowComponents = calendar.dateComponents([.year, .month, .day], from: now)

        guard let dateDay = calendar.date(from: dateComponents),
              let nowDay = calendar.date(from: nowComponents) else {
            return .otherYear(formatted: monthDayYearFormatter.string(from: date))
        }

        let daysDifference = calendar.dateComponents([.day], from: nowDay, to: dateDay).day ?? 0

        // Check for today, tomorrow, yesterday
        if daysDifference == 0 {
            return .today
        } else if daysDifference == 1 {
            return .tomorrow
        } else if daysDifference == -1 {
            return .yesterday
        }

        // Check for this week (within -6 to +6 days)
        let dayName = dayOfWeekFormatter.string(from: date)

        if daysDifference > 1 && daysDifference <= 6 {
            // Check if it's the same week
            let dateWeek = calendar.component(.weekOfYear, from: date)
            let nowWeek = calendar.component(.weekOfYear, from: now)

            if dateWeek == nowWeek {
                return .thisWeek(dayName: dayName)
            } else {
                return .nextWeek(dayName: dayName)
            }
        }

        if daysDifference >= -6 && daysDifference < -1 {
            // Check if it's the same week
            let dateWeek = calendar.component(.weekOfYear, from: date)
            let nowWeek = calendar.component(.weekOfYear, from: now)

            if dateWeek == nowWeek {
                return .thisWeek(dayName: dayName)
            } else {
                return .lastWeek(dayName: dayName)
            }
        }

        // Check if same year
        let dateYear = calendar.component(.year, from: date)
        let nowYear = calendar.component(.year, from: now)

        if dateYear == nowYear {
            return .thisYear(formatted: monthDayFormatter.string(from: date))
        }

        return .otherYear(formatted: monthDayYearFormatter.string(from: date))
    }

    /// Returns a user-friendly relative date string
    static func relativeString(from date: Date, relativeTo referenceDate: Date = Date()) -> String {
        relativeDate(from: date, relativeTo: referenceDate).displayString
    }

    /// Returns relative date string with time if applicable
    static func relativeStringWithTime(from date: Date, relativeTo referenceDate: Date = Date()) -> String {
        let relative = relativeString(from: date, relativeTo: referenceDate)
        let time = formatTime(date)
        return "\(relative) at \(time)"
    }
}

// MARK: - Due Date Formatting

extension DateFormatting {

    /// Due date status for styling purposes
    enum DueDateStatus {
        case overdue
        case dueToday
        case dueSoon // Within 24 hours
        case upcoming
        case noDueDate

        var isUrgent: Bool {
            switch self {
            case .overdue, .dueToday, .dueSoon:
                return true
            case .upcoming, .noDueDate:
                return false
            }
        }
    }

    /// Determines the due date status
    static func dueDateStatus(for date: Date?, relativeTo referenceDate: Date = Date()) -> DueDateStatus {
        guard let date = date else {
            return .noDueDate
        }

        let calendar = Calendar.current
        let now = referenceDate

        // Check if overdue (past due date)
        if date < now {
            // Check if it's still today
            if calendar.isDate(date, inSameDayAs: now) {
                // Check if time has passed
                if date < now {
                    return .overdue
                }
                return .dueToday
            }
            return .overdue
        }

        // Check if due today
        if calendar.isDate(date, inSameDayAs: now) {
            return .dueToday
        }

        // Check if due within 24 hours
        let hoursDifference = calendar.dateComponents([.hour], from: now, to: date).hour ?? 0
        if hoursDifference <= 24 {
            return .dueSoon
        }

        return .upcoming
    }

    /// Formats a due date for display in task lists
    static func formatDueDate(_ date: Date?, relativeTo referenceDate: Date = Date()) -> String? {
        guard let date = date else { return nil }

        let status = dueDateStatus(for: date, relativeTo: referenceDate)
        let relative = relativeDate(from: date, relativeTo: referenceDate)

        switch status {
        case .overdue:
            switch relative {
            case .yesterday:
                return "Yesterday"
            case .lastWeek(let day):
                return "Last \(day)"
            default:
                return relativeString(from: date, relativeTo: referenceDate)
            }

        case .dueToday:
            return "Today"

        case .dueSoon:
            return "Tomorrow"

        case .upcoming:
            return relative.displayString

        case .noDueDate:
            return nil
        }
    }

    /// Formats a due date with time for detail views
    static func formatDueDateWithTime(_ date: Date?, relativeTo referenceDate: Date = Date()) -> String? {
        guard let date = date else { return nil }

        let dateString = formatDueDate(date, relativeTo: referenceDate) ?? relativeString(from: date, relativeTo: referenceDate)
        let timeString = formatTime(date)

        return "\(dateString), \(timeString)"
    }

    /// Returns abbreviated due date for compact displays
    static func formatDueDateCompact(_ date: Date?, relativeTo referenceDate: Date = Date()) -> String? {
        guard let date = date else { return nil }

        let calendar = Calendar.current
        let now = referenceDate

        // Today
        if calendar.isDate(date, inSameDayAs: now) {
            return formatTime(date)
        }

        // Tomorrow
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now),
           calendar.isDate(date, inSameDayAs: tomorrow) {
            return "Tmrw"
        }

        // Yesterday
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday) {
            return "Yest"
        }

        // Within a week - show day name
        let daysDifference = calendar.dateComponents([.day], from: now, to: date).day ?? 0
        if abs(daysDifference) <= 6 {
            return shortDayOfWeekFormatter.string(from: date)
        }

        // Same year - show month and day
        let dateYear = calendar.component(.year, from: date)
        let nowYear = calendar.component(.year, from: now)

        if dateYear == nowYear {
            return monthDayFormatter.string(from: date)
        }

        // Different year
        return shortDateFormatter.string(from: date)
    }
}

// MARK: - Date Extensions

extension Date {

    /// ISO8601 string representation
    var iso8601String: String {
        DateFormatting.toISO8601(self)
    }

    /// Creates a Date from an ISO8601 string
    init?(iso8601 string: String) {
        guard let date = DateFormatting.fromISO8601(string) else {
            return nil
        }
        self = date
    }

    /// Returns relative date string
    func relativeString(to referenceDate: Date = Date()) -> String {
        DateFormatting.relativeString(from: self, relativeTo: referenceDate)
    }

    /// Returns formatted due date string
    func dueDateString(relativeTo referenceDate: Date = Date()) -> String? {
        DateFormatting.formatDueDate(self, relativeTo: referenceDate)
    }

    /// Returns due date status
    func dueDateStatus(relativeTo referenceDate: Date = Date()) -> DateFormatting.DueDateStatus {
        DateFormatting.dueDateStatus(for: self, relativeTo: referenceDate)
    }

    /// Formatted time string
    var timeString: String {
        DateFormatting.formatTime(self)
    }

    /// Formatted date string
    var dateString: String {
        DateFormatting.formatDate(self)
    }

    /// Formatted date and time string
    var dateTimeString: String {
        DateFormatting.formatDateTime(self)
    }

    /// Start of the day
    var startOfDay: Date {
        Calendar.current.startOfDay(for: self)
    }

    /// End of the day
    var endOfDay: Date {
        var components = DateComponents()
        components.day = 1
        components.second = -1
        return Calendar.current.date(byAdding: components, to: startOfDay) ?? self
    }

    /// Whether the date is today
    var isToday: Bool {
        Calendar.current.isDateInToday(self)
    }

    /// Whether the date is tomorrow
    var isTomorrow: Bool {
        Calendar.current.isDateInTomorrow(self)
    }

    /// Whether the date is yesterday
    var isYesterday: Bool {
        Calendar.current.isDateInYesterday(self)
    }

    /// Whether the date is in the past
    var isPast: Bool {
        self < Date()
    }

    /// Whether the date is in the future
    var isFuture: Bool {
        self > Date()
    }

    /// Whether the date is overdue (past and not today)
    var isOverdue: Bool {
        isPast && !isToday
    }
}

// MARK: - String Extension for ISO8601

extension String {

    /// Parses the string as an ISO8601 date
    var iso8601Date: Date? {
        DateFormatting.fromISO8601(self)
    }
}
