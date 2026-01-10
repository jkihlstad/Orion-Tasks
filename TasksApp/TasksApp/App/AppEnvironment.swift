//
//  AppEnvironment.swift
//  TasksApp
//
//  Dependency injection container providing all app services
//  Centralized management of services, state, and configuration
//

import SwiftUI
import Combine
#if os(iOS)
import BackgroundTasks
import UIKit
#endif
import UserNotifications

// MARK: - App Environment

@MainActor
final class AppEnvironment: ObservableObject {

    // MARK: - Published Services

    @Published private(set) var authProvider: AuthProvider
    @Published private(set) var syncEngine: SyncEngine
    @Published private(set) var calendarSyncManager: CalendarSyncManager
    @Published private(set) var notificationScheduler: NotificationScheduler

    // MARK: - Internal Services

    let networkMonitor: NetworkMonitor
    let analyticsService: AnalyticsService
    let crashReporter: CrashReporter
    let featureFlagService: FeatureFlagService
    let cacheManager: CacheManager
    let secureStorage: SecureStorage
    let hapticFeedback: HapticFeedbackGenerator

    // MARK: - Configuration

    let configuration: AppConfiguration

    // MARK: - State

    @Published var isInitialized: Bool = false
    @Published var initializationError: AppError?

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Background Task Identifiers

    static let syncBackgroundTaskIdentifier = "com.orion.tasksapp.sync"
    static let notificationRefreshTaskIdentifier = "com.orion.tasksapp.notifications"

    // MARK: - Initialization

    init() {
        // Load configuration
        self.configuration = AppConfiguration.current

        // Initialize core services first (no dependencies)
        self.secureStorage = SecureStorage()
        self.networkMonitor = NetworkMonitor()
        self.analyticsService = AnalyticsService(configuration: configuration)
        self.crashReporter = CrashReporter(configuration: configuration)
        self.featureFlagService = FeatureFlagService(configuration: configuration)
        self.cacheManager = CacheManager(configuration: configuration)
        self.hapticFeedback = HapticFeedbackGenerator()

        // Initialize auth provider with secure storage
        self.authProvider = AuthProvider(
            secureStorage: secureStorage,
            configuration: configuration
        )

        // Initialize sync engine with dependencies
        self.syncEngine = SyncEngine(
            authProvider: authProvider,
            networkMonitor: networkMonitor,
            cacheManager: cacheManager,
            configuration: configuration
        )

        // Initialize calendar sync manager
        self.calendarSyncManager = CalendarSyncManager(
            syncEngine: syncEngine,
            configuration: configuration
        )

        // Initialize notification scheduler
        self.notificationScheduler = NotificationScheduler(
            syncEngine: syncEngine,
            configuration: configuration
        )

        // Setup bindings and observers
        setupBindings()
        #if os(iOS)
        setupBackgroundTasks()
        #endif

        // Initialize services
        Task {
            await initialize()
        }
    }

    // MARK: - Setup

    private func setupBindings() {
        // Monitor network status changes
        networkMonitor.$isConnected
            .removeDuplicates()
            .sink { [weak self] isConnected in
                Task { @MainActor in
                    if isConnected {
                        await self?.syncEngine.resumeSync()
                    } else {
                        self?.syncEngine.pauseSync()
                    }
                }
            }
            .store(in: &cancellables)

        // Monitor authentication state
        authProvider.$isAuthenticated
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] isAuthenticated in
                Task { @MainActor in
                    if isAuthenticated {
                        await self?.handleUserAuthenticated()
                    } else {
                        await self?.handleUserSignedOut()
                    }
                }
            }
            .store(in: &cancellables)

        // Monitor sync errors
        syncEngine.$lastError
            .compactMap { $0 }
            .sink { [weak self] error in
                self?.crashReporter.recordError(error)
                self?.analyticsService.track(event: .syncError(error: error))
            }
            .store(in: &cancellables)
    }

    #if os(iOS)
    private func setupBackgroundTasks() {
        // Register background tasks
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.syncBackgroundTaskIdentifier,
            using: nil
        ) { [weak self] task in
            Task { @MainActor in
                await self?.handleBackgroundSync(task: task as! BGProcessingTask)
            }
        }

        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.notificationRefreshTaskIdentifier,
            using: nil
        ) { [weak self] task in
            Task { @MainActor in
                await self?.handleNotificationRefresh(task: task as! BGAppRefreshTask)
            }
        }
    }
    #endif

    // MARK: - Initialization

    private func initialize() async {
        do {
            // Start network monitoring
            networkMonitor.start()

            // Initialize crash reporting
            crashReporter.initialize()

            // Load feature flags
            await featureFlagService.loadFlags()

            // Restore authentication state
            await authProvider.restoreSession()

            // Initialize sync engine if authenticated
            if authProvider.isAuthenticated {
                await syncEngine.initialize()
            }

            // Load cached data
            await cacheManager.warmCache()

            // Analytics
            analyticsService.track(event: .appLaunched)

            isInitialized = true

        } catch {
            initializationError = AppError.initialization(underlying: error)
            crashReporter.recordError(error)
        }
    }

    // MARK: - State Management

    func saveState() {
        // Save any pending state changes
        syncEngine.savePendingChanges()
        cacheManager.persistCache()

        analyticsService.track(event: .appBackgrounded)
    }

    func clearUserData() {
        Task {
            // Clear all user-specific data
            await syncEngine.clearAllData()
            await cacheManager.clearCache()
            secureStorage.clearAll()
            notificationScheduler.cancelAllNotifications()
            calendarSyncManager.disconnectCalendar()

            analyticsService.track(event: .userDataCleared)
        }
    }

    // MARK: - Background Tasks

    #if os(iOS)
    func scheduleBackgroundTasks() {
        // Schedule sync task
        let syncRequest = BGProcessingTaskRequest(identifier: Self.syncBackgroundTaskIdentifier)
        syncRequest.requiresNetworkConnectivity = true
        syncRequest.requiresExternalPower = false
        syncRequest.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60) // 15 minutes

        do {
            try BGTaskScheduler.shared.submit(syncRequest)
        } catch {
            crashReporter.recordError(error)
        }

        // Schedule notification refresh task
        let notificationRequest = BGAppRefreshTaskRequest(identifier: Self.notificationRefreshTaskIdentifier)
        notificationRequest.earliestBeginDate = Date(timeIntervalSinceNow: 60 * 60) // 1 hour

        do {
            try BGTaskScheduler.shared.submit(notificationRequest)
        } catch {
            crashReporter.recordError(error)
        }
    }

    private func handleBackgroundSync(task: BGProcessingTask) async {
        // Set expiration handler
        task.expirationHandler = { [weak self] in
            self?.syncEngine.pauseSync()
            task.setTaskCompleted(success: false)
        }

        do {
            await syncEngine.performBackgroundSync()
            task.setTaskCompleted(success: true)
        } catch {
            crashReporter.recordError(error)
            task.setTaskCompleted(success: false)
        }

        // Schedule next sync
        scheduleBackgroundTasks()
    }

    private func handleNotificationRefresh(task: BGAppRefreshTask) async {
        task.expirationHandler = {
            task.setTaskCompleted(success: false)
        }

        await notificationScheduler.rescheduleAllNotifications()
        task.setTaskCompleted(success: true)

        // Schedule next refresh
        scheduleBackgroundTasks()
    }
    #else
    func scheduleBackgroundTasks() {
        // Background tasks not available on macOS
    }
    #endif

    // MARK: - Authentication Handlers

    private func handleUserAuthenticated() async {
        await syncEngine.initialize()
        await syncEngine.performInitialSync()
        await calendarSyncManager.requestCalendarAccess()
        await notificationScheduler.requestNotificationPermission()

        analyticsService.track(event: .userAuthenticated)
    }

    private func handleUserSignedOut() async {
        clearUserData()
        analyticsService.track(event: .userSignedOut)
    }
}

// MARK: - Auth Provider

@MainActor
final class AuthProvider: ObservableObject {

    // MARK: - Published Properties

    @Published private(set) var isAuthenticated: Bool = false
    @Published private(set) var currentUser: User?
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var error: AuthError?

    // MARK: - Clerk Integration Properties

    @Published private(set) var clerkSessionToken: String?
    @Published private(set) var clerkUserId: String?

    // MARK: - Dependencies

    private let secureStorage: SecureStorage
    private let configuration: AppConfiguration

    // MARK: - Constants

    private enum StorageKeys {
        static let sessionToken = "clerk_session_token"
        static let userId = "clerk_user_id"
        static let userProfile = "user_profile"
    }

    // MARK: - Initialization

    init(secureStorage: SecureStorage, configuration: AppConfiguration) {
        self.secureStorage = secureStorage
        self.configuration = configuration
    }

    // MARK: - Session Management

    func restoreSession() async {
        isLoading = true
        defer { isLoading = false }

        // Check for stored session
        guard let token = secureStorage.getString(forKey: StorageKeys.sessionToken),
              let userId = secureStorage.getString(forKey: StorageKeys.userId) else {
            return
        }

        // Validate session with Clerk
        do {
            let isValid = try await validateClerkSession(token: token)
            if isValid {
                clerkSessionToken = token
                clerkUserId = userId

                // Load user profile
                if let userData = secureStorage.getData(forKey: StorageKeys.userProfile) {
                    currentUser = try? JSONDecoder().decode(User.self, from: userData)
                }

                isAuthenticated = true
            } else {
                // Session expired, clear storage
                clearSession()
            }
        } catch {
            self.error = .sessionValidationFailed(underlying: error)
            clearSession()
        }
    }

    // MARK: - Clerk Authentication

    func signInWithClerk() async {
        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            // Clerk authentication flow
            // This is a placeholder for actual Clerk SDK integration
            let authResult = try await performClerkAuthentication()

            // Store session
            secureStorage.setString(authResult.sessionToken, forKey: StorageKeys.sessionToken)
            secureStorage.setString(authResult.userId, forKey: StorageKeys.userId)

            clerkSessionToken = authResult.sessionToken
            clerkUserId = authResult.userId
            currentUser = authResult.user

            // Cache user profile
            if let userData = try? JSONEncoder().encode(authResult.user) {
                secureStorage.setData(userData, forKey: StorageKeys.userProfile)
            }

            isAuthenticated = true

        } catch {
            self.error = .authenticationFailed(underlying: error)
        }
    }

    func signOut() async {
        isLoading = true
        defer { isLoading = false }

        // Revoke Clerk session
        if let token = clerkSessionToken {
            try? await revokeClerkSession(token: token)
        }

        clearSession()
        isAuthenticated = false
    }

    func refreshToken() async throws -> String {
        guard let currentToken = clerkSessionToken else {
            throw AuthError.noSession
        }

        let newToken = try await refreshClerkToken(currentToken: currentToken)
        clerkSessionToken = newToken
        secureStorage.setString(newToken, forKey: StorageKeys.sessionToken)

        return newToken
    }

    // MARK: - Private Methods

    private func clearSession() {
        secureStorage.removeValue(forKey: StorageKeys.sessionToken)
        secureStorage.removeValue(forKey: StorageKeys.userId)
        secureStorage.removeValue(forKey: StorageKeys.userProfile)

        clerkSessionToken = nil
        clerkUserId = nil
        currentUser = nil
    }

    // MARK: - Clerk API Placeholders

    private func validateClerkSession(token: String) async throws -> Bool {
        // TODO: Implement actual Clerk session validation
        // This should call Clerk's API to verify the session token

        // Placeholder implementation
        guard !token.isEmpty else { return false }

        // Simulated API call delay
        try await Task.sleep(nanoseconds: 100_000_000)

        return true
    }

    private func performClerkAuthentication() async throws -> ClerkAuthResult {
        // TODO: Implement actual Clerk authentication flow
        // This should integrate with Clerk's iOS SDK

        // Placeholder implementation
        try await Task.sleep(nanoseconds: 500_000_000)

        // Return mock result for development
        return ClerkAuthResult(
            sessionToken: UUID().uuidString,
            userId: UUID().uuidString,
            user: User(
                id: UUID().uuidString,
                email: "user@example.com",
                displayName: "Test User",
                avatarURL: nil,
                createdAt: Date(),
                updatedAt: Date()
            )
        )
    }

    private func revokeClerkSession(token: String) async throws {
        // TODO: Implement actual Clerk session revocation
        try await Task.sleep(nanoseconds: 100_000_000)
    }

    private func refreshClerkToken(currentToken: String) async throws -> String {
        // TODO: Implement actual Clerk token refresh
        try await Task.sleep(nanoseconds: 100_000_000)
        return UUID().uuidString
    }
}

// MARK: - Clerk Auth Result

struct ClerkAuthResult {
    let sessionToken: String
    let userId: String
    let user: User
}

// MARK: - User Model

struct User: Codable, Identifiable, Equatable {
    let id: String
    let email: String
    let displayName: String
    let avatarURL: URL?
    let createdAt: Date
    let updatedAt: Date

    var initials: String {
        let components = displayName.split(separator: " ")
        let initials = components.prefix(2).compactMap { $0.first }.map(String.init)
        return initials.joined().uppercased()
    }
}

// MARK: - Auth Errors

enum AuthError: LocalizedError {
    case noSession
    case sessionExpired
    case authenticationFailed(underlying: Error)
    case sessionValidationFailed(underlying: Error)
    case tokenRefreshFailed(underlying: Error)

    var errorDescription: String? {
        switch self {
        case .noSession:
            return "No active session"
        case .sessionExpired:
            return "Session has expired"
        case .authenticationFailed(let error):
            return "Authentication failed: \(error.localizedDescription)"
        case .sessionValidationFailed(let error):
            return "Session validation failed: \(error.localizedDescription)"
        case .tokenRefreshFailed(let error):
            return "Token refresh failed: \(error.localizedDescription)"
        }
    }
}

// MARK: - Sync Engine

@MainActor
final class SyncEngine: ObservableObject {

    // MARK: - Published Properties

    @Published private(set) var isSyncing: Bool = false
    @Published private(set) var lastSyncDate: Date?
    @Published private(set) var syncStatus: SyncStatus = .idle
    @Published private(set) var lastError: SyncError?
    @Published private(set) var pendingChangesCount: Int = 0

    // MARK: - Dependencies

    private weak var authProvider: AuthProvider?
    private let networkMonitor: NetworkMonitor
    private let cacheManager: CacheManager
    private let configuration: AppConfiguration

    // MARK: - State

    private var syncTask: Task<Void, Never>?
    private var isPaused: Bool = false
    private var retryCount: Int = 0
    private let maxRetries: Int = 3

    // MARK: - Initialization

    init(
        authProvider: AuthProvider,
        networkMonitor: NetworkMonitor,
        cacheManager: CacheManager,
        configuration: AppConfiguration
    ) {
        self.authProvider = authProvider
        self.networkMonitor = networkMonitor
        self.cacheManager = cacheManager
        self.configuration = configuration
    }

    // MARK: - Initialization

    func initialize() async {
        syncStatus = .initializing

        // Load local state
        await loadLocalState()

        syncStatus = .idle
    }

    // MARK: - Sync Operations

    func performInitialSync() async {
        guard !isSyncing else { return }
        guard networkMonitor.isConnected else {
            syncStatus = .offline
            return
        }

        isSyncing = true
        syncStatus = .syncing
        lastError = nil

        defer {
            isSyncing = false
        }

        do {
            // Fetch all data from server
            try await fetchAllData()

            // Push any local changes
            try await pushPendingChanges()

            lastSyncDate = Date()
            syncStatus = .completed
            retryCount = 0

        } catch {
            lastError = SyncError.syncFailed(underlying: error)
            syncStatus = .failed
            scheduleRetry()
        }
    }

    func performBackgroundSync() async {
        guard !isSyncing, !isPaused else { return }
        guard networkMonitor.isConnected else { return }

        isSyncing = true
        defer { isSyncing = false }

        do {
            // Incremental sync - only fetch changes since last sync
            try await fetchIncrementalChanges()
            try await pushPendingChanges()

            lastSyncDate = Date()

        } catch {
            lastError = SyncError.syncFailed(underlying: error)
        }
    }

    func syncNow() async {
        guard !isSyncing else { return }

        isPaused = false
        await performBackgroundSync()
    }

    func pauseSync() {
        isPaused = true
        syncTask?.cancel()
        syncStatus = .paused
    }

    func resumeSync() async {
        isPaused = false

        if networkMonitor.isConnected {
            syncStatus = .idle
            await syncNow()
        } else {
            syncStatus = .offline
        }
    }

    // MARK: - Data Operations

    func savePendingChanges() {
        // Save pending changes to local storage for later sync
        // This is called when app enters background
    }

    func clearAllData() async {
        syncTask?.cancel()

        // Clear all local data
        await cacheManager.clearCache()

        lastSyncDate = nil
        pendingChangesCount = 0
        syncStatus = .idle
    }

    // MARK: - Private Methods

    private func loadLocalState() async {
        // Load cached data and pending changes count
    }

    private func fetchAllData() async throws {
        // TODO: Implement full data fetch from Convex backend
        try await Task.sleep(nanoseconds: 1_000_000_000)
    }

    private func fetchIncrementalChanges() async throws {
        // TODO: Implement incremental sync from Convex backend
        try await Task.sleep(nanoseconds: 500_000_000)
    }

    private func pushPendingChanges() async throws {
        // TODO: Implement pushing local changes to Convex backend
        guard pendingChangesCount > 0 else { return }

        try await Task.sleep(nanoseconds: 500_000_000)
        pendingChangesCount = 0
    }

    private func scheduleRetry() {
        guard retryCount < maxRetries else {
            syncStatus = .failed
            return
        }

        retryCount += 1
        let delay = pow(2.0, Double(retryCount)) // Exponential backoff

        syncTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await syncNow()
        }
    }
}

// MARK: - Sync Status

enum SyncStatus: Equatable {
    case idle
    case initializing
    case syncing
    case completed
    case failed
    case paused
    case offline

    var displayText: String {
        switch self {
        case .idle: return "Up to date"
        case .initializing: return "Initializing..."
        case .syncing: return "Syncing..."
        case .completed: return "Synced"
        case .failed: return "Sync failed"
        case .paused: return "Sync paused"
        case .offline: return "Offline"
        }
    }
}

// MARK: - Sync Errors

enum SyncError: LocalizedError {
    case syncFailed(underlying: Error)
    case networkUnavailable
    case authenticationRequired
    case conflictDetected
    case dataCorruption

    var errorDescription: String? {
        switch self {
        case .syncFailed(let error):
            return "Sync failed: \(error.localizedDescription)"
        case .networkUnavailable:
            return "Network unavailable"
        case .authenticationRequired:
            return "Authentication required"
        case .conflictDetected:
            return "Data conflict detected"
        case .dataCorruption:
            return "Data corruption detected"
        }
    }
}

// MARK: - Calendar Sync Manager

@MainActor
final class CalendarSyncManager: ObservableObject {

    // MARK: - Published Properties

    @Published private(set) var isAuthorized: Bool = false
    @Published private(set) var connectedCalendars: [CalendarInfo] = []
    @Published private(set) var isSyncing: Bool = false
    @Published private(set) var lastSyncDate: Date?
    @Published private(set) var error: CalendarError?

    // MARK: - Dependencies

    private weak var syncEngine: SyncEngine?
    private let configuration: AppConfiguration

    // MARK: - Initialization

    init(syncEngine: SyncEngine, configuration: AppConfiguration) {
        self.syncEngine = syncEngine
        self.configuration = configuration
    }

    // MARK: - Authorization

    func requestCalendarAccess() async {
        // TODO: Implement EventKit authorization request
        // EKEventStore().requestAccess(to: .event)

        // Placeholder
        try? await Task.sleep(nanoseconds: 500_000_000)
        isAuthorized = true
    }

    func checkAuthorizationStatus() {
        // TODO: Check EKEventStore authorization status
    }

    // MARK: - Calendar Operations

    func refreshCalendarEvents() async {
        guard isAuthorized else { return }
        guard !isSyncing else { return }

        isSyncing = true
        defer { isSyncing = false }

        do {
            // TODO: Fetch calendar events using EventKit
            try await Task.sleep(nanoseconds: 500_000_000)
            lastSyncDate = Date()
        } catch {
            self.error = .fetchFailed(underlying: error)
        }
    }

    func createCalendarEvent(for task: TaskItem) async throws {
        guard isAuthorized else {
            throw CalendarError.notAuthorized
        }

        // TODO: Create EKEvent for task
    }

    func updateCalendarEvent(for task: TaskItem) async throws {
        guard isAuthorized else {
            throw CalendarError.notAuthorized
        }

        // TODO: Update EKEvent for task
    }

    func deleteCalendarEvent(for task: TaskItem) async throws {
        // TODO: Delete EKEvent for task
    }

    func disconnectCalendar() {
        connectedCalendars = []
        isAuthorized = false
    }
}

// MARK: - Calendar Info

struct CalendarInfo: Identifiable, Equatable {
    let id: String
    let title: String
    let color: Color
    var isEnabled: Bool
}

// MARK: - Calendar Errors

enum CalendarError: LocalizedError {
    case notAuthorized
    case fetchFailed(underlying: Error)
    case createFailed(underlying: Error)
    case updateFailed(underlying: Error)
    case deleteFailed(underlying: Error)

    var errorDescription: String? {
        switch self {
        case .notAuthorized:
            return "Calendar access not authorized"
        case .fetchFailed(let error):
            return "Failed to fetch calendar events: \(error.localizedDescription)"
        case .createFailed(let error):
            return "Failed to create calendar event: \(error.localizedDescription)"
        case .updateFailed(let error):
            return "Failed to update calendar event: \(error.localizedDescription)"
        case .deleteFailed(let error):
            return "Failed to delete calendar event: \(error.localizedDescription)"
        }
    }
}

// MARK: - Notification Scheduler

@MainActor
final class NotificationScheduler: ObservableObject {

    // MARK: - Published Properties

    @Published private(set) var isAuthorized: Bool = false
    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @Published private(set) var pendingNotifications: [String] = []
    @Published private(set) var badgeCount: Int = 0

    // MARK: - Dependencies

    private weak var syncEngine: SyncEngine?
    private let configuration: AppConfiguration
    private let notificationCenter: UNUserNotificationCenter

    // MARK: - Initialization

    init(syncEngine: SyncEngine, configuration: AppConfiguration) {
        self.syncEngine = syncEngine
        self.configuration = configuration
        self.notificationCenter = UNUserNotificationCenter.current()

        checkAuthorizationStatus()
    }

    // MARK: - Authorization

    func requestNotificationPermission() async {
        do {
            let granted = try await notificationCenter.requestAuthorization(
                options: [.alert, .badge, .sound, .provisional]
            )
            isAuthorized = granted
            authorizationStatus = granted ? .authorized : .denied
        } catch {
            isAuthorized = false
            authorizationStatus = .denied
        }
    }

    func checkAuthorizationStatus() {
        Task {
            let settings = await notificationCenter.notificationSettings()
            await MainActor.run {
                authorizationStatus = settings.authorizationStatus
                isAuthorized = settings.authorizationStatus == .authorized ||
                               settings.authorizationStatus == .provisional
            }
        }
    }

    // MARK: - Notification Scheduling

    func scheduleNotification(for task: TaskItem) async throws {
        guard isAuthorized else {
            throw NotificationError.notAuthorized
        }

        guard let dueDate = task.dueDate else {
            return
        }

        let content = UNMutableNotificationContent()
        content.title = task.title
        content.body = task.notes ?? "Task due"
        content.sound = .default
        content.badge = NSNumber(value: badgeCount + 1)
        content.categoryIdentifier = "TASK_REMINDER"
        content.userInfo = ["taskId": task.id]

        // Schedule for due date
        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: dueDate
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)

        let request = UNNotificationRequest(
            identifier: "task-\(task.id)",
            content: content,
            trigger: trigger
        )

        try await notificationCenter.add(request)
        pendingNotifications.append(task.id)
    }

    func cancelNotification(for taskId: String) {
        notificationCenter.removePendingNotificationRequests(withIdentifiers: ["task-\(taskId)"])
        pendingNotifications.removeAll { $0 == taskId }
    }

    func cancelAllNotifications() {
        notificationCenter.removeAllPendingNotificationRequests()
        pendingNotifications = []
    }

    func rescheduleAllNotifications() async {
        // Cancel all existing notifications
        notificationCenter.removeAllPendingNotificationRequests()
        pendingNotifications = []

        // TODO: Fetch all tasks with due dates and reschedule
        // This should be called when the app enters background or on significant time change
    }

    // MARK: - Badge Management

    func refreshBadgeCount() {
        Task {
            // TODO: Calculate badge count based on overdue tasks
            let count = 0 // Placeholder
            await MainActor.run {
                badgeCount = count
                UNUserNotificationCenter.current().setBadgeCount(count)
            }
        }
    }

    func clearBadge() {
        badgeCount = 0
        UNUserNotificationCenter.current().setBadgeCount(0)
    }
}

// MARK: - Notification Errors

enum NotificationError: LocalizedError {
    case notAuthorized
    case schedulingFailed(underlying: Error)

    var errorDescription: String? {
        switch self {
        case .notAuthorized:
            return "Notification permission not granted"
        case .schedulingFailed(let error):
            return "Failed to schedule notification: \(error.localizedDescription)"
        }
    }
}

// MARK: - Task Item (Placeholder Model)

struct TaskItem: Identifiable {
    let id: String
    var title: String
    var notes: String?
    var dueDate: Date?
    var isCompleted: Bool
    var priority: TaskPriority
    var listId: String?

    enum TaskPriority: Int, Codable {
        case none = 0
        case low = 1
        case medium = 2
        case high = 3
    }
}

// MARK: - Supporting Services

// Network Monitor
final class NetworkMonitor: ObservableObject {
    @Published private(set) var isConnected: Bool = true
    @Published private(set) var connectionType: ConnectionType = .wifi

    enum ConnectionType {
        case wifi
        case cellular
        case ethernet
        case unknown
    }

    func start() {
        // TODO: Implement NWPathMonitor
    }

    func stop() {
        // TODO: Stop monitoring
    }
}

// Analytics Service
final class AnalyticsService {
    private let configuration: AppConfiguration

    init(configuration: AppConfiguration) {
        self.configuration = configuration
    }

    func track(event: AnalyticsEvent) {
        guard configuration.analyticsEnabled else { return }
        // TODO: Implement analytics tracking
        #if DEBUG
        print("[Analytics] \(event)")
        #endif
    }
}

enum AnalyticsEvent: CustomStringConvertible {
    case appLaunched
    case appBackgrounded
    case userAuthenticated
    case userSignedOut
    case userDataCleared
    case syncError(error: Error)
    case taskCreated
    case taskCompleted
    case taskDeleted
    case listCreated
    case listDeleted

    var description: String {
        switch self {
        case .appLaunched: return "app_launched"
        case .appBackgrounded: return "app_backgrounded"
        case .userAuthenticated: return "user_authenticated"
        case .userSignedOut: return "user_signed_out"
        case .userDataCleared: return "user_data_cleared"
        case .syncError(let error): return "sync_error: \(error.localizedDescription)"
        case .taskCreated: return "task_created"
        case .taskCompleted: return "task_completed"
        case .taskDeleted: return "task_deleted"
        case .listCreated: return "list_created"
        case .listDeleted: return "list_deleted"
        }
    }
}

// Crash Reporter
final class CrashReporter {
    private let configuration: AppConfiguration

    init(configuration: AppConfiguration) {
        self.configuration = configuration
    }

    func initialize() {
        // TODO: Initialize crash reporting service (e.g., Sentry, Firebase Crashlytics)
    }

    func recordError(_ error: Error) {
        #if DEBUG
        print("[CrashReporter] Error: \(error.localizedDescription)")
        #endif
        // TODO: Send to crash reporting service
    }

    func setUserIdentifier(_ identifier: String?) {
        // TODO: Set user identifier for crash reports
    }
}

// Feature Flag Service
final class FeatureFlagService: ObservableObject {
    @Published private(set) var flags: [String: Bool] = [:]

    private let configuration: AppConfiguration

    init(configuration: AppConfiguration) {
        self.configuration = configuration
    }

    func loadFlags() async {
        // TODO: Load feature flags from remote config
        flags = [
            "ai_suggestions_enabled": true,
            "calendar_sync_enabled": true,
            "collaborative_lists_enabled": false
        ]
    }

    func isEnabled(_ flag: String) -> Bool {
        flags[flag] ?? false
    }
}

// Cache Manager
final class CacheManager {
    private let configuration: AppConfiguration

    init(configuration: AppConfiguration) {
        self.configuration = configuration
    }

    func warmCache() async {
        // TODO: Pre-load frequently accessed data into memory
    }

    func clearCache() async {
        // TODO: Clear all cached data
    }

    func persistCache() {
        // TODO: Write cache to disk
    }
}

// Secure Storage
final class SecureStorage {

    func getString(forKey key: String) -> String? {
        // TODO: Implement Keychain access
        UserDefaults.standard.string(forKey: key)
    }

    func setString(_ value: String, forKey key: String) {
        // TODO: Implement Keychain storage
        UserDefaults.standard.set(value, forKey: key)
    }

    func getData(forKey key: String) -> Data? {
        UserDefaults.standard.data(forKey: key)
    }

    func setData(_ value: Data, forKey key: String) {
        UserDefaults.standard.set(value, forKey: key)
    }

    func removeValue(forKey key: String) {
        UserDefaults.standard.removeObject(forKey: key)
    }

    func clearAll() {
        // TODO: Clear all keychain items for this app
        let domain = Bundle.main.bundleIdentifier!
        UserDefaults.standard.removePersistentDomain(forName: domain)
    }
}

// Haptic Feedback Generator
final class HapticFeedbackGenerator {
    #if os(iOS)
    func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.impactOccurred()
    }

    func notification(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(type)
    }

    func selection() {
        let generator = UISelectionFeedbackGenerator()
        generator.selectionChanged()
    }
    #else
    func impact(_ style: Int) {
        // Haptic feedback not available on macOS
    }

    func notification(_ type: Int) {
        // Haptic feedback not available on macOS
    }

    func selection() {
        // Haptic feedback not available on macOS
    }
    #endif
}

// MARK: - App Configuration

struct AppConfiguration {
    let environment: Environment
    let apiBaseURL: URL
    let clerkPublishableKey: String
    let convexURL: URL
    let analyticsEnabled: Bool
    let loggingEnabled: Bool

    enum Environment: String {
        case development
        case staging
        case production
    }

    static var current: AppConfiguration {
        #if DEBUG
        return .development
        #else
        return .production
        #endif
    }

    static let development = AppConfiguration(
        environment: .development,
        apiBaseURL: URL(string: "https://api.dev.orion-tasks.com")!,
        clerkPublishableKey: "pk_test_PLACEHOLDER",
        convexURL: URL(string: "https://dev-convex.cloud")!,
        analyticsEnabled: false,
        loggingEnabled: true
    )

    static let staging = AppConfiguration(
        environment: .staging,
        apiBaseURL: URL(string: "https://api.staging.orion-tasks.com")!,
        clerkPublishableKey: "pk_test_PLACEHOLDER",
        convexURL: URL(string: "https://staging-convex.cloud")!,
        analyticsEnabled: true,
        loggingEnabled: true
    )

    static let production = AppConfiguration(
        environment: .production,
        apiBaseURL: URL(string: "https://api.orion-tasks.com")!,
        clerkPublishableKey: "pk_live_PLACEHOLDER",
        convexURL: URL(string: "https://prod-convex.cloud")!,
        analyticsEnabled: true,
        loggingEnabled: false
    )
}

// MARK: - App Errors

enum AppError: LocalizedError {
    case initialization(underlying: Error)
    case network(underlying: Error)
    case authentication(underlying: Error)
    case sync(underlying: Error)
    case unknown

    var errorDescription: String? {
        switch self {
        case .initialization(let error):
            return "Initialization failed: \(error.localizedDescription)"
        case .network(let error):
            return "Network error: \(error.localizedDescription)"
        case .authentication(let error):
            return "Authentication error: \(error.localizedDescription)"
        case .sync(let error):
            return "Sync error: \(error.localizedDescription)"
        case .unknown:
            return "An unknown error occurred"
        }
    }
}
