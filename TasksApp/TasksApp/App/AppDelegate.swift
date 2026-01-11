// AppDelegate.swift
// TasksApp - AppDelegate for push notification handling
//
// Integrates SharedKit PushNotificationManager for unified notification handling
// Handles task reminders, due date alerts, and sync notifications

import UIKit
import SharedKit
import UserNotifications

class AppDelegate: NSObject, UIApplicationDelegate {

    // MARK: - Push Notification Manager
    private let pushManager = PushNotificationManager.shared

    // MARK: - App Lifecycle
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Set up push notification handling
        setupPushNotifications()

        return true
    }

    // MARK: - Push Notification Setup
    private func setupPushNotifications() {
        // Set up PushNotificationManager as the delegate
        pushManager.applicationDidFinishLaunching()

        // Register notification handler for this app
        pushManager.registerHandler(TasksNotificationHandler(), for: Bundle.main.bundleIdentifier ?? "")

        // Configure backend URL and JWT provider
        if let backendURL = URL(string: "https://api.orion.app") {
            pushManager.configure(backendURL: backendURL) {
                // Get JWT from Clerk session
                try await ClerkAuthProvider.shared.getToken()
            }
        }

        // Request authorization and register for remote notifications
        Task {
            do {
                let authorized = try await pushManager.setup(with: [.alert, .sound, .badge])
                if authorized {
                    print("[TasksApp] Push notifications authorized and registered")
                }
            } catch {
                print("[TasksApp] Failed to set up push notifications: \(error)")
            }
        }
    }

    // MARK: - Push Notifications
    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Task {
            await pushManager.didRegisterForRemoteNotifications(withDeviceToken: deviceToken)
        }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        pushManager.didFailToRegisterForRemoteNotifications(withError: error)
        print("[TasksApp] Failed to register for remote notifications: \(error)")
    }

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        pushManager.processRemoteNotification(userInfo, completionHandler: completionHandler)
    }
}

// MARK: - Tasks Notification Handler

/// Handles push notifications specific to the tasks app
final class TasksNotificationHandler: PushNotificationHandler, @unchecked Sendable {

    func handleNotification(payload: [AnyHashable: Any]) async {
        // Handle incoming notification while app is in foreground
        print("[TasksNotificationHandler] Received notification: \(payload)")

        // Check notification type and handle accordingly
        if let type = payload["type"] as? String {
            switch type {
            case "task_reminder":
                // Task reminder notification
                await MainActor.run {
                    NotificationCenter.default.post(
                        name: .taskReminderReceived,
                        object: nil,
                        userInfo: payload
                    )
                }
            case "task_due":
                // Task is due soon or overdue
                await MainActor.run {
                    NotificationCenter.default.post(
                        name: .taskDueAlertReceived,
                        object: nil,
                        userInfo: payload
                    )
                }
            case "sync":
                // Sync notification - trigger sync
                await MainActor.run {
                    NotificationCenter.default.post(
                        name: .taskSyncRequested,
                        object: nil,
                        userInfo: payload
                    )
                }
            case "ai_suggestion":
                // AI suggestion for task
                await MainActor.run {
                    NotificationCenter.default.post(
                        name: .taskAISuggestionReceived,
                        object: nil,
                        userInfo: payload
                    )
                }
            case "red_beacon":
                // Red Beacon priority alert
                await MainActor.run {
                    NotificationCenter.default.post(
                        name: .taskRedBeaconAlert,
                        object: nil,
                        userInfo: payload
                    )
                }
            default:
                break
            }
        }
    }

    func handleNotificationTap(payload: [AnyHashable: Any], action: String?) async {
        // Handle user tapping on notification
        print("[TasksNotificationHandler] Notification tapped with action: \(action ?? "default")")

        await MainActor.run {
            // Handle different actions
            if let action = action {
                switch action {
                case OrionNotificationAction.complete.rawValue:
                    // Mark task as complete
                    if let taskId = payload["taskId"] as? String {
                        NotificationCenter.default.post(
                            name: .taskMarkComplete,
                            object: nil,
                            userInfo: ["taskId": taskId]
                        )
                    }
                case OrionNotificationAction.snooze.rawValue:
                    // Snooze the task reminder
                    if let taskId = payload["taskId"] as? String {
                        NotificationCenter.default.post(
                            name: .taskSnooze,
                            object: nil,
                            userInfo: ["taskId": taskId]
                        )
                    }
                case OrionNotificationAction.view.rawValue:
                    // Open task detail view
                    if let taskId = payload["taskId"] as? String {
                        NotificationCenter.default.post(
                            name: .taskOpenDetail,
                            object: nil,
                            userInfo: ["taskId": taskId]
                        )
                    }
                default:
                    break
                }
            } else {
                // Default tap - open the task detail
                if let taskId = payload["taskId"] as? String {
                    NotificationCenter.default.post(
                        name: .taskOpenDetail,
                        object: nil,
                        userInfo: ["taskId": taskId]
                    )
                }
            }
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let taskReminderReceived = Notification.Name("taskReminderReceived")
    static let taskDueAlertReceived = Notification.Name("taskDueAlertReceived")
    static let taskSyncRequested = Notification.Name("taskSyncRequested")
    static let taskAISuggestionReceived = Notification.Name("taskAISuggestionReceived")
    static let taskRedBeaconAlert = Notification.Name("taskRedBeaconAlert")
    static let taskMarkComplete = Notification.Name("taskMarkComplete")
    static let taskSnooze = Notification.Name("taskSnooze")
    static let taskOpenDetail = Notification.Name("taskOpenDetail")
}
