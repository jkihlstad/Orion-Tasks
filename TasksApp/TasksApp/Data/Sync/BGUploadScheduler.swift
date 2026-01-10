//
//  BGUploadScheduler.swift
//  TasksApp
//
//  Background upload scheduling using BGTaskScheduler
//  Handles event upload when app is backgrounded
//

import Foundation
import BackgroundTasks
import Combine
import UIKit

// MARK: - Background Task Identifiers

/// Background task identifiers for the Tasks app
enum BGTaskIdentifiers {
    /// Sync pending events to server
    static let eventSync = "com.orion.tasksapp.sync.events"

    /// Upload pending attachments
    static let mediaUpload = "com.orion.tasksapp.sync.media"

    /// Refresh data from server
    static let dataRefresh = "com.orion.tasksapp.refresh"

    /// All identifiers to register
    static let all: [String] = [eventSync, mediaUpload, dataRefresh]
}

// MARK: - Background Task Result

/// Result of a background task execution
struct BGTaskResult: Sendable {
    let taskIdentifier: String
    let success: Bool
    let itemsProcessed: Int
    let duration: TimeInterval
    let error: Error?

    static func success(
        identifier: String,
        itemsProcessed: Int = 0,
        duration: TimeInterval = 0
    ) -> BGTaskResult {
        BGTaskResult(
            taskIdentifier: identifier,
            success: true,
            itemsProcessed: itemsProcessed,
            duration: duration,
            error: nil
        )
    }

    static func failure(
        identifier: String,
        error: Error,
        duration: TimeInterval = 0
    ) -> BGTaskResult {
        BGTaskResult(
            taskIdentifier: identifier,
            success: false,
            itemsProcessed: 0,
            duration: duration,
            error: error
        )
    }
}

// MARK: - Background Upload Scheduler

/// Manages background upload tasks using BGTaskScheduler
final class BGUploadScheduler: @unchecked Sendable {

    // MARK: - Shared Instance

    static let shared = BGUploadScheduler()

    // MARK: - Properties

    private var syncEngine: SyncEngineCoordinator?
    private var mediaUploadClient: MediaUploadClientImpl?
    private var networkMonitor: NetworkStatusMonitor?

    private let taskResultSubject = PassthroughSubject<BGTaskResult, Never>()
    var taskResults: AnyPublisher<BGTaskResult, Never> {
        taskResultSubject.eraseToAnyPublisher()
    }

    /// Last successful task completion times
    private var lastCompletionTimes: [String: Date] = [:]
    private let lock = NSLock()

    /// Minimum time between task scheduling
    private let minimumScheduleInterval: TimeInterval = 15 * 60 // 15 minutes

    // MARK: - Initialization

    private init() {}

    // MARK: - Configuration

    /// Configures the scheduler with required dependencies
    func configure(
        syncEngine: SyncEngineCoordinator,
        mediaUploadClient: MediaUploadClientImpl,
        networkMonitor: NetworkStatusMonitor
    ) {
        self.syncEngine = syncEngine
        self.mediaUploadClient = mediaUploadClient
        self.networkMonitor = networkMonitor
    }

    // MARK: - Registration

    /// Registers all background tasks with the system
    /// Call this in application(_:didFinishLaunchingWithOptions:)
    func registerBackgroundTasks() {
        // Register event sync task
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: BGTaskIdentifiers.eventSync,
            using: nil
        ) { [weak self] task in
            self?.handleEventSyncTask(task as! BGProcessingTask)
        }

        // Register media upload task
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: BGTaskIdentifiers.mediaUpload,
            using: nil
        ) { [weak self] task in
            self?.handleMediaUploadTask(task as! BGProcessingTask)
        }

        // Register data refresh task
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: BGTaskIdentifiers.dataRefresh,
            using: nil
        ) { [weak self] task in
            self?.handleDataRefreshTask(task as! BGAppRefreshTask)
        }

        #if DEBUG
        print("[BGUploadScheduler] Registered background tasks: \(BGTaskIdentifiers.all)")
        #endif
    }

    // MARK: - Scheduling

    /// Schedules all background tasks when app enters background
    func scheduleBackgroundTasks() {
        scheduleEventSync()
        scheduleMediaUpload()
        scheduleDataRefresh()
    }

    /// Schedules event sync task
    func scheduleEventSync(earliestDate: Date? = nil) {
        let request = BGProcessingTaskRequest(identifier: BGTaskIdentifiers.eventSync)
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = false

        let scheduleDate = earliestDate ?? calculateNextScheduleDate(for: BGTaskIdentifiers.eventSync)
        request.earliestBeginDate = scheduleDate

        submitTask(request)
    }

    /// Schedules media upload task
    func scheduleMediaUpload(earliestDate: Date? = nil) {
        let request = BGProcessingTaskRequest(identifier: BGTaskIdentifiers.mediaUpload)
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = false // Don't require power for better reliability

        let scheduleDate = earliestDate ?? calculateNextScheduleDate(for: BGTaskIdentifiers.mediaUpload)
        request.earliestBeginDate = scheduleDate

        submitTask(request)
    }

    /// Schedules data refresh task
    func scheduleDataRefresh(earliestDate: Date? = nil) {
        let request = BGAppRefreshTaskRequest(identifier: BGTaskIdentifiers.dataRefresh)

        let scheduleDate = earliestDate ?? Date(timeIntervalSinceNow: 60 * 60) // 1 hour
        request.earliestBeginDate = scheduleDate

        submitTask(request)
    }

    /// Cancels all scheduled background tasks
    func cancelAllScheduledTasks() {
        for identifier in BGTaskIdentifiers.all {
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: identifier)
        }

        #if DEBUG
        print("[BGUploadScheduler] Cancelled all scheduled tasks")
        #endif
    }

    /// Cancels a specific scheduled task
    func cancelTask(identifier: String) {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: identifier)

        #if DEBUG
        print("[BGUploadScheduler] Cancelled task: \(identifier)")
        #endif
    }

    // MARK: - Task Handlers

    private func handleEventSyncTask(_ task: BGProcessingTask) {
        let startTime = Date()

        #if DEBUG
        print("[BGUploadScheduler] Starting event sync task")
        #endif

        // Schedule next sync before starting current one
        scheduleEventSync()

        // Set up expiration handler
        task.expirationHandler = { [weak self] in
            self?.syncEngine?.pause()
            task.setTaskCompleted(success: false)

            let result = BGTaskResult.failure(
                identifier: BGTaskIdentifiers.eventSync,
                error: BGUploadError.taskExpired,
                duration: Date().timeIntervalSince(startTime)
            )
            self?.taskResultSubject.send(result)
        }

        // Perform sync
        Task {
            guard let syncEngine = self.syncEngine else {
                task.setTaskCompleted(success: false)
                return
            }

            let syncResult = await syncEngine.performBackgroundSync()
            let duration = Date().timeIntervalSince(startTime)

            task.setTaskCompleted(success: syncResult.success)

            let result: BGTaskResult
            if syncResult.success {
                result = .success(
                    identifier: BGTaskIdentifiers.eventSync,
                    itemsProcessed: syncResult.pushedEvents,
                    duration: duration
                )
                self.recordCompletion(for: BGTaskIdentifiers.eventSync)
            } else {
                result = .failure(
                    identifier: BGTaskIdentifiers.eventSync,
                    error: syncResult.error ?? BGUploadError.unknown,
                    duration: duration
                )
            }

            self.taskResultSubject.send(result)

            #if DEBUG
            print("[BGUploadScheduler] Event sync completed: \(syncResult.success), items: \(syncResult.pushedEvents)")
            #endif
        }
    }

    private func handleMediaUploadTask(_ task: BGProcessingTask) {
        let startTime = Date()

        #if DEBUG
        print("[BGUploadScheduler] Starting media upload task")
        #endif

        // Schedule next upload before starting current one
        scheduleMediaUpload()

        // Set up expiration handler
        task.expirationHandler = { [weak self] in
            self?.mediaUploadClient?.cancelAllUploads()
            task.setTaskCompleted(success: false)

            let result = BGTaskResult.failure(
                identifier: BGTaskIdentifiers.mediaUpload,
                error: BGUploadError.taskExpired,
                duration: Date().timeIntervalSince(startTime)
            )
            self?.taskResultSubject.send(result)
        }

        // Perform media uploads
        Task {
            guard let mediaClient = self.mediaUploadClient else {
                task.setTaskCompleted(success: false)
                return
            }

            do {
                let uploadCount = try await mediaClient.uploadPendingAttachments()
                let duration = Date().timeIntervalSince(startTime)

                task.setTaskCompleted(success: true)
                self.recordCompletion(for: BGTaskIdentifiers.mediaUpload)

                let result = BGTaskResult.success(
                    identifier: BGTaskIdentifiers.mediaUpload,
                    itemsProcessed: uploadCount,
                    duration: duration
                )
                self.taskResultSubject.send(result)

                #if DEBUG
                print("[BGUploadScheduler] Media upload completed: \(uploadCount) items")
                #endif

            } catch {
                let duration = Date().timeIntervalSince(startTime)
                task.setTaskCompleted(success: false)

                let result = BGTaskResult.failure(
                    identifier: BGTaskIdentifiers.mediaUpload,
                    error: error,
                    duration: duration
                )
                self.taskResultSubject.send(result)

                #if DEBUG
                print("[BGUploadScheduler] Media upload failed: \(error)")
                #endif
            }
        }
    }

    private func handleDataRefreshTask(_ task: BGAppRefreshTask) {
        let startTime = Date()

        #if DEBUG
        print("[BGUploadScheduler] Starting data refresh task")
        #endif

        // Schedule next refresh before starting current one
        scheduleDataRefresh()

        // Set up expiration handler
        task.expirationHandler = {
            task.setTaskCompleted(success: false)
        }

        // Perform refresh
        Task {
            guard let syncEngine = self.syncEngine else {
                task.setTaskCompleted(success: false)
                return
            }

            let syncResult = await syncEngine.performFullSync()
            let duration = Date().timeIntervalSince(startTime)

            task.setTaskCompleted(success: syncResult.success)

            if syncResult.success {
                self.recordCompletion(for: BGTaskIdentifiers.dataRefresh)
            }

            #if DEBUG
            print("[BGUploadScheduler] Data refresh completed: \(syncResult.success), duration: \(duration)s")
            #endif
        }
    }

    // MARK: - Private Methods

    private func submitTask(_ request: BGTaskRequest) {
        do {
            try BGTaskScheduler.shared.submit(request)

            #if DEBUG
            print("[BGUploadScheduler] Scheduled task: \(request.identifier), earliest: \(request.earliestBeginDate ?? Date())")
            #endif

        } catch BGTaskScheduler.Error.notPermitted {
            print("[BGUploadScheduler] Background tasks not permitted")
        } catch BGTaskScheduler.Error.tooManyPendingTaskRequests {
            print("[BGUploadScheduler] Too many pending task requests")
        } catch BGTaskScheduler.Error.unavailable {
            print("[BGUploadScheduler] Background tasks unavailable")
        } catch {
            print("[BGUploadScheduler] Failed to schedule task: \(error)")
        }
    }

    private func calculateNextScheduleDate(for identifier: String) -> Date {
        lock.lock()
        defer { lock.unlock() }

        let baseInterval: TimeInterval
        switch identifier {
        case BGTaskIdentifiers.eventSync:
            baseInterval = 15 * 60 // 15 minutes
        case BGTaskIdentifiers.mediaUpload:
            baseInterval = 30 * 60 // 30 minutes
        case BGTaskIdentifiers.dataRefresh:
            baseInterval = 60 * 60 // 1 hour
        default:
            baseInterval = minimumScheduleInterval
        }

        // Check if we've completed recently
        if let lastCompletion = lastCompletionTimes[identifier] {
            let timeSinceCompletion = Date().timeIntervalSince(lastCompletion)
            if timeSinceCompletion < baseInterval {
                return Date(timeIntervalSinceNow: baseInterval - timeSinceCompletion)
            }
        }

        return Date(timeIntervalSinceNow: baseInterval)
    }

    private func recordCompletion(for identifier: String) {
        lock.lock()
        defer { lock.unlock() }
        lastCompletionTimes[identifier] = Date()
    }

    // MARK: - Debug Support

    #if DEBUG
    /// Triggers a background task immediately for testing
    /// Only works in debug builds
    func debugTriggerTask(_ identifier: String) {
        switch identifier {
        case BGTaskIdentifiers.eventSync:
            Task {
                _ = await syncEngine?.performBackgroundSync()
            }
        case BGTaskIdentifiers.mediaUpload:
            Task {
                _ = try? await mediaUploadClient?.uploadPendingAttachments()
            }
        case BGTaskIdentifiers.dataRefresh:
            Task {
                _ = await syncEngine?.performFullSync()
            }
        default:
            break
        }
    }

    /// Lists all pending task requests
    func debugListPendingTasks() async {
        let requests = await BGTaskScheduler.shared.pendingTaskRequests()
        print("[BGUploadScheduler] Pending tasks:")
        for request in requests {
            print("  - \(request.identifier): earliest \(request.earliestBeginDate ?? Date())")
        }
    }
    #endif
}

// MARK: - Background Upload Error

/// Errors specific to background upload operations
enum BGUploadError: LocalizedError {
    case taskExpired
    case notConfigured
    case networkUnavailable
    case unknown

    var errorDescription: String? {
        switch self {
        case .taskExpired:
            return "Background task expired before completion"
        case .notConfigured:
            return "Background scheduler not configured"
        case .networkUnavailable:
            return "Network unavailable for background upload"
        case .unknown:
            return "Unknown background upload error"
        }
    }
}

// MARK: - App Lifecycle Integration

extension BGUploadScheduler {

    /// Call when app enters background
    func applicationDidEnterBackground() {
        scheduleBackgroundTasks()
    }

    /// Call when app will enter foreground
    func applicationWillEnterForeground() {
        // Cancel any pending tasks that would run soon
        // as foreground app will handle sync directly
    }

    /// Call when app is about to terminate
    func applicationWillTerminate() {
        // Ensure tasks are scheduled for next launch
        scheduleBackgroundTasks()
    }
}

// MARK: - Scene Lifecycle Integration

extension BGUploadScheduler {

    /// Call when scene phase changes to background
    func sceneDidEnterBackground() {
        scheduleBackgroundTasks()
    }

    /// Call when scene phase changes to active
    func sceneDidBecomeActive() {
        // App is now active, can cancel aggressive background scheduling
    }
}

// MARK: - Processing Task Priority

extension BGUploadScheduler {

    /// Determines if a task should run based on current conditions
    func shouldExecuteTask(_ identifier: String) -> Bool {
        guard let networkMonitor = networkMonitor else {
            return false
        }

        // Check network connectivity
        guard networkMonitor.isConnected else {
            return false
        }

        // Check if on expensive connection for media uploads
        if identifier == BGTaskIdentifiers.mediaUpload {
            return !networkMonitor.isExpensive
        }

        return true
    }

    /// Gets the priority for a task
    func taskPriority(_ identifier: String) -> Float {
        switch identifier {
        case BGTaskIdentifiers.eventSync:
            return 0.8 // High priority - user data should sync quickly
        case BGTaskIdentifiers.mediaUpload:
            return 0.5 // Medium priority - can wait for good conditions
        case BGTaskIdentifiers.dataRefresh:
            return 0.3 // Lower priority - nice to have but not critical
        default:
            return 0.5
        }
    }
}
