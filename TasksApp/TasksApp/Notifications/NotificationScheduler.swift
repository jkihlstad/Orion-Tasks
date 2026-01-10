//
//  NotificationScheduler.swift
//  TasksApp
//
//  Full notification scheduler with Red Beacon escalation support
//

import Foundation
import UserNotifications
import UIKit

// MARK: - Notification Category Identifiers

enum NotificationCategory: String {
    case taskReminder = "TASK_REMINDER"
    case taskOverdue = "TASK_OVERDUE"
    case redBeaconEscalation = "RED_BEACON_ESCALATION"
}

// MARK: - Notification Action Identifiers

enum NotificationAction: String {
    case complete = "COMPLETE_TASK"
    case snooze = "SNOOZE_TASK"
    case snooze5 = "SNOOZE_5_MIN"
    case snooze15 = "SNOOZE_15_MIN"
    case snooze60 = "SNOOZE_1_HOUR"
    case viewTask = "VIEW_TASK"
}

// MARK: - Notification Scheduler

/// Manages all notification scheduling for the Tasks app
/// Supports Red Beacon escalation, Time Sensitive notifications, and DND-aware features
@MainActor
final class NotificationScheduler: NSObject, ObservableObject {

    // MARK: - Singleton

    static let shared = NotificationScheduler()

    // MARK: - Dependencies

    private let notificationCenter = UNUserNotificationCenter.current()
    private let preferences = RedBeaconPreferences.shared

    // MARK: - Published State

    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @Published private(set) var isTimeSensitiveAuthorized: Bool = false
    @Published private(set) var pendingNotificationCount: Int = 0

    // MARK: - Initialization

    private override init() {
        super.init()
        Task {
            await refreshAuthorizationStatus()
            await registerNotificationCategories()
        }
    }

    // MARK: - Authorization

    /// Requests notification permission from the user
    /// - Parameter includeTimeSensitive: Whether to request Time Sensitive permission (iOS 15+)
    /// - Returns: Whether permission was granted
    @discardableResult
    func requestAuthorization(includeTimeSensitive: Bool = true) async -> Bool {
        var options: UNAuthorizationOptions = [.alert, .sound, .badge]

        // Request Time Sensitive on iOS 15+
        if #available(iOS 15.0, *), includeTimeSensitive {
            options.insert(.timeSensitive)
        }

        do {
            let granted = try await notificationCenter.requestAuthorization(options: options)
            await refreshAuthorizationStatus()
            return granted
        } catch {
            print("[NotificationScheduler] Authorization error: \(error.localizedDescription)")
            return false
        }
    }

    /// Refreshes the current authorization status
    func refreshAuthorizationStatus() async {
        let settings = await notificationCenter.notificationSettings()
        authorizationStatus = settings.authorizationStatus

        if #available(iOS 15.0, *) {
            isTimeSensitiveAuthorized = settings.timeSensitiveSetting == .enabled
        } else {
            isTimeSensitiveAuthorized = false
        }

        // Update pending count
        let pendingRequests = await notificationCenter.pendingNotificationRequests()
        pendingNotificationCount = pendingRequests.count
    }

    /// Whether notifications are currently authorized
    var isAuthorized: Bool {
        authorizationStatus == .authorized || authorizationStatus == .provisional
    }

    // MARK: - Notification Categories

    /// Registers notification categories with actions
    private func registerNotificationCategories() async {
        // Complete action
        let completeAction = UNNotificationAction(
            identifier: NotificationAction.complete.rawValue,
            title: "Complete",
            options: [.authenticationRequired]
        )

        // Snooze actions
        let snooze5Action = UNNotificationAction(
            identifier: NotificationAction.snooze5.rawValue,
            title: "5 min",
            options: []
        )

        let snooze15Action = UNNotificationAction(
            identifier: NotificationAction.snooze15.rawValue,
            title: "15 min",
            options: []
        )

        let snooze60Action = UNNotificationAction(
            identifier: NotificationAction.snooze60.rawValue,
            title: "1 hour",
            options: []
        )

        // View action
        let viewAction = UNNotificationAction(
            identifier: NotificationAction.viewTask.rawValue,
            title: "View",
            options: [.foreground]
        )

        // Task reminder category
        let reminderCategory = UNNotificationCategory(
            identifier: NotificationCategory.taskReminder.rawValue,
            actions: [completeAction, snooze15Action, viewAction],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )

        // Red Beacon escalation category (more snooze options)
        let escalationCategory = UNNotificationCategory(
            identifier: NotificationCategory.redBeaconEscalation.rawValue,
            actions: [completeAction, snooze5Action, snooze15Action, snooze60Action],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )

        // Overdue category
        let overdueCategory = UNNotificationCategory(
            identifier: NotificationCategory.taskOverdue.rawValue,
            actions: [completeAction, snooze60Action, viewAction],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )

        notificationCenter.setNotificationCategories([
            reminderCategory,
            escalationCategory,
            overdueCategory
        ])
    }

    // MARK: - Task Reminder Scheduling

    /// Schedules a simple reminder notification for a task
    /// - Parameters:
    ///   - task: The task to remind about
    ///   - at: The date/time for the reminder
    func scheduleReminder(for task: Task, at date: Date) async {
        guard isAuthorized else {
            print("[NotificationScheduler] Not authorized to schedule notifications")
            return
        }

        guard date > Date() else {
            print("[NotificationScheduler] Cannot schedule notification in the past")
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "Task Reminder"
        content.body = task.title
        content.sound = preferences.soundEnabled ? .default : nil
        content.categoryIdentifier = NotificationCategory.taskReminder.rawValue
        content.userInfo = [
            "taskId": task.id,
            "listId": task.listId,
            "type": "reminder"
        ]

        // Set interruption level for iOS 15+
        if #available(iOS 15.0, *) {
            content.interruptionLevel = .active
        }

        // Update badge if enabled
        if preferences.badgeCountEnabled {
            await updateBadgeCount()
        }

        let identifier = "reminder.\(task.id)"
        let trigger = UNCalendarNotificationTrigger(
            dateMatching: Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: date
            ),
            repeats: false
        )

        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: trigger
        )

        do {
            try await notificationCenter.add(request)
            await refreshAuthorizationStatus()
            print("[NotificationScheduler] Scheduled reminder for task: \(task.id)")
        } catch {
            print("[NotificationScheduler] Failed to schedule reminder: \(error.localizedDescription)")
        }
    }

    // MARK: - Red Beacon Escalation Scheduling

    /// Schedules Red Beacon escalation notifications for a task
    /// This will schedule multiple notifications at increasing intervals after the due time
    /// - Parameters:
    ///   - task: The task with Red Beacon enabled
    ///   - dueDate: The due date/time for the task
    func scheduleRedBeaconEscalation(for task: Task, dueDate: Date) async {
        guard isAuthorized else {
            print("[NotificationScheduler] Not authorized to schedule notifications")
            return
        }

        guard preferences.isEnabled else {
            print("[NotificationScheduler] Red Beacon is disabled globally")
            return
        }

        guard task.redBeaconEnabled else {
            print("[NotificationScheduler] Red Beacon not enabled for this task")
            return
        }

        // Cancel any existing escalations for this task
        await cancelRedBeaconNotifications(for: task.id)

        let preset = preferences.escalationPreset
        guard preset != .none else {
            return
        }

        let intervals = preset.escalationIntervals
        let useTimeSensitive = preferences.useTimeSensitive && isTimeSensitiveAuthorized

        for (index, interval) in intervals.enumerated() {
            let notificationDate = dueDate.addingTimeInterval(interval)

            // Skip if notification time is in the past
            guard notificationDate > Date() else {
                continue
            }

            let content = UNMutableNotificationContent()
            content.title = preset.notificationTitle(for: index)
            content.body = preset.notificationBody(for: task.title, escalationIndex: index)
            content.sound = preferences.soundEnabled ? .default : nil
            content.categoryIdentifier = NotificationCategory.redBeaconEscalation.rawValue
            content.userInfo = [
                "taskId": task.id,
                "listId": task.listId,
                "type": "redBeacon",
                "escalationIndex": index
            ]

            // Set Time Sensitive interruption level on iOS 15+ for escalations
            if #available(iOS 15.0, *) {
                if useTimeSensitive && index > 0 {
                    // First notification is active, subsequent are time sensitive
                    content.interruptionLevel = .timeSensitive
                } else if index > 2 {
                    // Later escalations are always time sensitive
                    content.interruptionLevel = .timeSensitive
                } else {
                    content.interruptionLevel = .active
                }
            }

            // Add thread identifier for grouping
            content.threadIdentifier = "task.\(task.id)"

            let identifier = RedBeaconPreferences.notificationIdentifier(
                taskId: task.id,
                escalationIndex: index
            )

            let trigger = UNCalendarNotificationTrigger(
                dateMatching: Calendar.current.dateComponents(
                    [.year, .month, .day, .hour, .minute, .second],
                    from: notificationDate
                ),
                repeats: false
            )

            let request = UNNotificationRequest(
                identifier: identifier,
                content: content,
                trigger: trigger
            )

            do {
                try await notificationCenter.add(request)
                print("[NotificationScheduler] Scheduled escalation \(index) for task: \(task.id)")
            } catch {
                print("[NotificationScheduler] Failed to schedule escalation \(index): \(error.localizedDescription)")
            }
        }

        await refreshAuthorizationStatus()
    }

    /// Schedules a snoozed reminder
    /// - Parameters:
    ///   - task: The task to snooze
    ///   - minutes: Minutes to snooze
    func scheduleSnooze(for task: Task, minutes: Int) async {
        let snoozeDate = Date().addingTimeInterval(TimeInterval(minutes * 60))
        await scheduleReminder(for: task, at: snoozeDate)
    }

    // MARK: - Cancellation

    /// Cancels all notifications for a specific task
    func cancelNotifications(for taskId: String) async {
        let pendingRequests = await notificationCenter.pendingNotificationRequests()
        let identifiersToRemove = pendingRequests
            .filter { request in
                if let id = request.content.userInfo["taskId"] as? String {
                    return id == taskId
                }
                return request.identifier.contains(taskId)
            }
            .map { $0.identifier }

        notificationCenter.removePendingNotificationRequests(withIdentifiers: identifiersToRemove)
        notificationCenter.removeDeliveredNotifications(withIdentifiers: identifiersToRemove)

        await refreshAuthorizationStatus()
        print("[NotificationScheduler] Cancelled \(identifiersToRemove.count) notifications for task: \(taskId)")
    }

    /// Cancels only Red Beacon escalation notifications for a task
    func cancelRedBeaconNotifications(for taskId: String) async {
        let pendingRequests = await notificationCenter.pendingNotificationRequests()
        let identifiersToRemove = pendingRequests
            .filter { RedBeaconPreferences.isRedBeaconNotification($0.identifier) }
            .filter { $0.identifier.contains(taskId) }
            .map { $0.identifier }

        notificationCenter.removePendingNotificationRequests(withIdentifiers: identifiersToRemove)
        notificationCenter.removeDeliveredNotifications(withIdentifiers: identifiersToRemove)

        print("[NotificationScheduler] Cancelled \(identifiersToRemove.count) Red Beacon notifications for task: \(taskId)")
    }

    /// Cancels all pending notifications
    func cancelAllNotifications() {
        notificationCenter.removeAllPendingNotificationRequests()
        notificationCenter.removeAllDeliveredNotifications()
        print("[NotificationScheduler] Cancelled all notifications")
    }

    // MARK: - Badge Management

    /// Updates the app badge count with the number of overdue tasks
    /// - Parameter overdueCount: Number of overdue tasks (if known)
    func updateBadgeCount(to count: Int? = nil) async {
        guard preferences.badgeCountEnabled else {
            await clearBadge()
            return
        }

        let badgeCount = count ?? 0
        await setBadge(to: badgeCount)
    }

    /// Sets the app badge to a specific value
    private func setBadge(to count: Int) async {
        if #available(iOS 16.0, *) {
            do {
                try await notificationCenter.setBadgeCount(count)
            } catch {
                print("[NotificationScheduler] Failed to set badge: \(error.localizedDescription)")
            }
        } else {
            await MainActor.run {
                UIApplication.shared.applicationIconBadgeNumber = count
            }
        }
    }

    /// Clears the app badge
    func clearBadge() async {
        await setBadge(to: 0)
    }

    /// Increments the badge by a given amount
    func incrementBadge(by amount: Int = 1) async {
        if #available(iOS 16.0, *) {
            // Get current badge and increment
            let current = await UIApplication.shared.applicationIconBadgeNumber
            await setBadge(to: current + amount)
        } else {
            await MainActor.run {
                UIApplication.shared.applicationIconBadgeNumber += amount
            }
        }
    }

    /// Decrements the badge by a given amount
    func decrementBadge(by amount: Int = 1) async {
        if #available(iOS 16.0, *) {
            let current = await UIApplication.shared.applicationIconBadgeNumber
            await setBadge(to: max(0, current - amount))
        } else {
            await MainActor.run {
                let newValue = max(0, UIApplication.shared.applicationIconBadgeNumber - amount)
                UIApplication.shared.applicationIconBadgeNumber = newValue
            }
        }
    }

    // MARK: - Utility Methods

    /// Gets all pending notifications for a task
    func pendingNotifications(for taskId: String) async -> [UNNotificationRequest] {
        let pendingRequests = await notificationCenter.pendingNotificationRequests()
        return pendingRequests.filter { request in
            if let id = request.content.userInfo["taskId"] as? String {
                return id == taskId
            }
            return request.identifier.contains(taskId)
        }
    }

    /// Checks if a task has any pending notifications
    func hasScheduledNotifications(for taskId: String) async -> Bool {
        let notifications = await pendingNotifications(for: taskId)
        return !notifications.isEmpty
    }

    /// Gets the next scheduled notification date for a task
    func nextNotificationDate(for taskId: String) async -> Date? {
        let notifications = await pendingNotifications(for: taskId)
        let dates = notifications.compactMap { request -> Date? in
            guard let trigger = request.trigger as? UNCalendarNotificationTrigger else {
                return nil
            }
            return trigger.nextTriggerDate()
        }
        return dates.min()
    }

    // MARK: - Settings Deep Link

    /// Opens iOS Settings for the app's notification settings
    func openNotificationSettings() {
        Task { @MainActor in
            if let url = URL(string: UIApplication.openSettingsURLString) {
                if UIApplication.shared.canOpenURL(url) {
                    UIApplication.shared.open(url)
                }
            }
        }
    }

    /// Opens iOS Focus settings (best effort - may open general Settings)
    func openFocusSettings() {
        Task { @MainActor in
            // Try to open Focus settings directly (may not work on all iOS versions)
            if let focusURL = URL(string: "App-Prefs:FOCUS") {
                if UIApplication.shared.canOpenURL(focusURL) {
                    UIApplication.shared.open(focusURL)
                    return
                }
            }

            // Fallback to general settings
            if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(settingsURL)
            }
        }
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension NotificationScheduler: UNUserNotificationCenterDelegate {

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        // Show notifications even when app is in foreground
        return [.banner, .sound, .badge]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let userInfo = response.notification.request.content.userInfo
        guard let taskId = userInfo["taskId"] as? String else {
            return
        }

        let action = NotificationAction(rawValue: response.actionIdentifier)

        switch action {
        case .complete:
            // Post notification to complete the task
            await MainActor.run {
                NotificationCenter.default.post(
                    name: .taskCompletedFromNotification,
                    object: nil,
                    userInfo: ["taskId": taskId]
                )
            }

        case .snooze5:
            await handleSnooze(taskId: taskId, minutes: 5)

        case .snooze15, .snooze:
            await handleSnooze(taskId: taskId, minutes: 15)

        case .snooze60:
            await handleSnooze(taskId: taskId, minutes: 60)

        case .viewTask:
            // Post notification to navigate to task
            await MainActor.run {
                NotificationCenter.default.post(
                    name: .navigateToTaskFromNotification,
                    object: nil,
                    userInfo: ["taskId": taskId]
                )
            }

        case .none:
            // Default tap - open task
            if response.actionIdentifier == UNNotificationDefaultActionIdentifier {
                await MainActor.run {
                    NotificationCenter.default.post(
                        name: .navigateToTaskFromNotification,
                        object: nil,
                        userInfo: ["taskId": taskId]
                    )
                }
            }
        }
    }

    private func handleSnooze(taskId: String, minutes: Int) async {
        // Post notification to snooze the task
        await MainActor.run {
            NotificationCenter.default.post(
                name: .taskSnoozedFromNotification,
                object: nil,
                userInfo: [
                    "taskId": taskId,
                    "minutes": minutes
                ]
            )
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let taskCompletedFromNotification = Notification.Name("taskCompletedFromNotification")
    static let taskSnoozedFromNotification = Notification.Name("taskSnoozedFromNotification")
    static let navigateToTaskFromNotification = Notification.Name("navigateToTaskFromNotification")
}

// MARK: - Convenience Extension for Task

extension Task {

    /// Schedules Red Beacon notifications if enabled
    func scheduleRedBeaconIfNeeded() async {
        guard redBeaconEnabled,
              let dueDate = fullDueDate,
              !isCompleted else {
            return
        }

        await NotificationScheduler.shared.scheduleRedBeaconEscalation(
            for: self,
            dueDate: dueDate
        )
    }

    /// Cancels all scheduled notifications for this task
    func cancelScheduledNotifications() async {
        await NotificationScheduler.shared.cancelNotifications(for: id)
    }
}
