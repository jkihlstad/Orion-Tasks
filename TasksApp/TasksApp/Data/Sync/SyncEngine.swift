//
//  SyncEngine.swift
//  TasksApp
//
//  Main sync coordinator for offline-first synchronization
//  Handles event queueing, conflict resolution, and network-aware sync
//

import Foundation
import CoreData
import Combine

// MARK: - Sync Engine State

/// Current state of the sync engine
enum SyncEngineState: Equatable, Sendable {
    case idle
    case initializing
    case syncing(progress: Double)
    case paused
    case offline
    case error(SyncEngineError)

    var isActive: Bool {
        switch self {
        case .syncing:
            return true
        default:
            return false
        }
    }

    var canSync: Bool {
        switch self {
        case .idle, .error:
            return true
        default:
            return false
        }
    }

    var displayText: String {
        switch self {
        case .idle:
            return "Up to date"
        case .initializing:
            return "Initializing..."
        case .syncing(let progress):
            if progress > 0 {
                return "Syncing \(Int(progress * 100))%"
            }
            return "Syncing..."
        case .paused:
            return "Sync paused"
        case .offline:
            return "Offline"
        case .error(let error):
            return "Sync error: \(error.localizedDescription)"
        }
    }
}

// MARK: - Sync Engine Error

/// Errors that can occur during sync
enum SyncEngineError: LocalizedError, Equatable {
    case networkUnavailable
    case authenticationRequired
    case serverError(Int, String)
    case conflictResolutionFailed
    case dataCorruption
    case quotaExceeded
    case rateLimited(retryAfter: TimeInterval)
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .networkUnavailable:
            return "Network unavailable"
        case .authenticationRequired:
            return "Authentication required"
        case .serverError(let code, let message):
            return "Server error (\(code)): \(message)"
        case .conflictResolutionFailed:
            return "Failed to resolve conflicts"
        case .dataCorruption:
            return "Data corruption detected"
        case .quotaExceeded:
            return "Storage quota exceeded"
        case .rateLimited(let retryAfter):
            return "Rate limited, retry after \(Int(retryAfter))s"
        case .unknown(let message):
            return message
        }
    }

    static func == (lhs: SyncEngineError, rhs: SyncEngineError) -> Bool {
        lhs.errorDescription == rhs.errorDescription
    }
}

// MARK: - Sync Configuration

/// Configuration for the sync engine
struct SyncConfiguration: Sendable {
    /// Maximum events to upload in a single batch
    let batchSize: Int

    /// Minimum interval between sync attempts
    let minSyncInterval: TimeInterval

    /// Maximum retry attempts for failed operations
    let maxRetryAttempts: Int

    /// Base delay for exponential backoff (seconds)
    let baseRetryDelay: TimeInterval

    /// Maximum delay for exponential backoff (seconds)
    let maxRetryDelay: TimeInterval

    /// Whether to sync automatically when network becomes available
    let autoSyncOnConnect: Bool

    /// Whether to sync on app foreground
    let syncOnForeground: Bool

    /// Conflict resolution policy
    let conflictPolicy: ConflictPolicy

    static let `default` = SyncConfiguration(
        batchSize: 50,
        minSyncInterval: 5.0,
        maxRetryAttempts: 5,
        baseRetryDelay: 1.0,
        maxRetryDelay: 60.0,
        autoSyncOnConnect: true,
        syncOnForeground: true,
        conflictPolicy: .standard
    )

    static let aggressive = SyncConfiguration(
        batchSize: 100,
        minSyncInterval: 2.0,
        maxRetryAttempts: 3,
        baseRetryDelay: 0.5,
        maxRetryDelay: 30.0,
        autoSyncOnConnect: true,
        syncOnForeground: true,
        conflictPolicy: .standard
    )

    static let conservative = SyncConfiguration(
        batchSize: 25,
        minSyncInterval: 30.0,
        maxRetryAttempts: 10,
        baseRetryDelay: 2.0,
        maxRetryDelay: 300.0,
        autoSyncOnConnect: true,
        syncOnForeground: false,
        conflictPolicy: .standard
    )
}

// MARK: - Sync Engine

/// Main coordinator for offline-first synchronization
@MainActor
final class SyncEngineCoordinator: ObservableObject {

    // MARK: - Published Properties

    @Published private(set) var state: SyncEngineState = .idle
    @Published private(set) var lastSyncDate: Date?
    @Published private(set) var pendingEventCount: Int = 0
    @Published private(set) var failedEventCount: Int = 0
    @Published private(set) var lastError: SyncEngineError?
    @Published private(set) var isSyncing: Bool = false

    // MARK: - Combine Publishers

    /// Publisher for state changes
    var statePublisher: AnyPublisher<SyncEngineState, Never> {
        $state.eraseToAnyPublisher()
    }

    /// Publisher for sync completion
    private let syncCompletedSubject = PassthroughSubject<SyncResult, Never>()
    var syncCompleted: AnyPublisher<SyncResult, Never> {
        syncCompletedSubject.eraseToAnyPublisher()
    }

    /// Publisher for sync errors
    private let syncErrorSubject = PassthroughSubject<SyncEngineError, Never>()
    var syncErrors: AnyPublisher<SyncEngineError, Never> {
        syncErrorSubject.eraseToAnyPublisher()
    }

    // MARK: - Dependencies

    private let persistenceController: PersistenceController
    private let eventRepository: EventRepository
    private let networkMonitor: NetworkStatusMonitor
    private let eventProjector: EventProjector
    private let conflictResolver: ConflictResolver
    private let configuration: SyncConfiguration

    // API client - set after initialization
    private var apiClient: TasksAPIClient?

    // MARK: - Internal State

    private var isPaused: Bool = false
    private var retryCount: Int = 0
    private var currentSyncTask: Task<Void, Never>?
    private var lastSyncAttempt: Date?
    private var cancellables = Set<AnyCancellable>()
    private let syncLock = NSLock()

    // Device identification
    private let deviceId: String

    // MARK: - Initialization

    init(
        persistenceController: PersistenceController = .shared,
        networkMonitor: NetworkStatusMonitor,
        configuration: SyncConfiguration = .default,
        deviceId: String = UUID().uuidString
    ) {
        self.persistenceController = persistenceController
        self.eventRepository = EventRepository(persistenceController: persistenceController)
        self.networkMonitor = networkMonitor
        self.configuration = configuration
        self.deviceId = deviceId

        self.conflictResolver = ConflictResolver(
            policy: configuration.conflictPolicy,
            deviceId: deviceId
        )
        self.eventProjector = EventProjector(
            persistenceController: persistenceController,
            conflictResolver: conflictResolver
        )

        setupObservers()
    }

    // MARK: - Setup

    private func setupObservers() {
        // Observe network connectivity changes
        networkMonitor.connectivityChanged
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isConnected in
                Task { @MainActor in
                    await self?.handleConnectivityChange(isConnected: isConnected)
                }
            }
            .store(in: &cancellables)

        // Observe event queue changes
        eventRepository.queueChanges
            .receive(on: DispatchQueue.main)
            .sink { [weak self] change in
                self?.handleQueueChange(change)
            }
            .store(in: &cancellables)

        // Update pending count periodically
        Timer.publish(every: 5, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.updatePendingCounts()
            }
            .store(in: &cancellables)
    }

    /// Configures the API client
    func configure(apiClient: TasksAPIClient) {
        self.apiClient = apiClient
    }

    // MARK: - Public Methods

    /// Initializes the sync engine
    func initialize() async {
        state = .initializing

        // Load sync state from storage
        updatePendingCounts()

        // Check network status
        if !networkMonitor.isConnected {
            state = .offline
            return
        }

        state = .idle
    }

    /// Performs a full sync with the server
    func performFullSync() async -> SyncResult {
        guard !isSyncing else {
            return SyncResult(success: false, error: .unknown("Sync already in progress"))
        }

        guard networkMonitor.isConnected else {
            state = .offline
            return SyncResult(success: false, error: .networkUnavailable)
        }

        guard !isPaused else {
            return SyncResult(success: false, error: .unknown("Sync is paused"))
        }

        isSyncing = true
        state = .syncing(progress: 0)
        lastError = nil

        defer {
            isSyncing = false
            if state.isActive {
                state = .idle
            }
        }

        do {
            // Step 1: Push pending local changes
            state = .syncing(progress: 0.1)
            let pushResult = try await pushPendingEvents()

            // Step 2: Pull changes from server
            state = .syncing(progress: 0.5)
            let pullResult = try await pullServerChanges()

            // Step 3: Resolve any conflicts
            state = .syncing(progress: 0.9)
            let conflicts = try await resolveConflicts()

            // Update state
            lastSyncDate = Date()
            retryCount = 0
            state = .idle

            let result = SyncResult(
                success: true,
                pushedEvents: pushResult.count,
                pulledEvents: pullResult.count,
                resolvedConflicts: conflicts.count
            )

            syncCompletedSubject.send(result)
            return result

        } catch let error as SyncEngineError {
            lastError = error
            state = .error(error)
            syncErrorSubject.send(error)
            scheduleRetry()
            return SyncResult(success: false, error: error)

        } catch {
            let syncError = SyncEngineError.unknown(error.localizedDescription)
            lastError = syncError
            state = .error(syncError)
            syncErrorSubject.send(syncError)
            scheduleRetry()
            return SyncResult(success: false, error: syncError)
        }
    }

    /// Performs an incremental sync (just pending changes)
    func performIncrementalSync() async -> SyncResult {
        guard !isSyncing, networkMonitor.isConnected, !isPaused else {
            return SyncResult(success: false)
        }

        // Throttle sync attempts
        if let lastAttempt = lastSyncAttempt,
           Date().timeIntervalSince(lastAttempt) < configuration.minSyncInterval {
            return SyncResult(success: false)
        }

        lastSyncAttempt = Date()

        isSyncing = true
        state = .syncing(progress: 0)

        defer {
            isSyncing = false
            if state.isActive {
                state = .idle
            }
        }

        do {
            let pushResult = try await pushPendingEvents()
            lastSyncDate = Date()
            state = .idle

            let result = SyncResult(success: true, pushedEvents: pushResult.count)
            syncCompletedSubject.send(result)
            return result

        } catch let error as SyncEngineError {
            lastError = error
            state = .error(error)
            return SyncResult(success: false, error: error)

        } catch {
            let syncError = SyncEngineError.unknown(error.localizedDescription)
            lastError = syncError
            state = .error(syncError)
            return SyncResult(success: false, error: syncError)
        }
    }

    /// Syncs immediately
    func syncNow() async -> SyncResult {
        isPaused = false
        return await performIncrementalSync()
    }

    /// Pauses sync operations
    func pause() {
        syncLock.lock()
        defer { syncLock.unlock() }

        isPaused = true
        currentSyncTask?.cancel()
        currentSyncTask = nil
        state = .paused
    }

    /// Resumes sync operations
    func resume() async {
        syncLock.lock()
        isPaused = false
        syncLock.unlock()

        if networkMonitor.isConnected {
            state = .idle
            _ = await syncNow()
        } else {
            state = .offline
        }
    }

    /// Saves pending changes (called when app backgrounds)
    func savePendingChanges() {
        persistenceController.save()
    }

    /// Clears all sync data
    func clearAllData() async {
        currentSyncTask?.cancel()

        try? eventRepository.clearAllEvents()
        lastSyncDate = nil
        pendingEventCount = 0
        failedEventCount = 0
        state = .idle
    }

    /// Performs background sync (called from BGTaskScheduler)
    func performBackgroundSync() async -> SyncResult {
        guard networkMonitor.isConnected else {
            return SyncResult(success: false, error: .networkUnavailable)
        }

        return await performIncrementalSync()
    }

    // MARK: - Event Enqueueing

    /// Enqueues a domain event for sync
    func enqueueEvent(_ event: DomainEvent) throws {
        // First, project the event locally
        eventProjector.project(event)

        // Then enqueue for server sync
        try eventRepository.enqueue(
            eventType: event.eventType.rawValue,
            entityType: event.eventType.entityType,
            entityId: extractEntityId(from: event),
            payload: try payloadToDictionary(event.payload)
        )

        updatePendingCounts()

        // Trigger sync if connected
        if networkMonitor.isConnected && !isPaused {
            Task {
                _ = await performIncrementalSync()
            }
        }
    }

    /// Enqueues multiple events for sync
    func enqueueEvents(_ events: [DomainEvent]) throws {
        // Project events locally
        eventProjector.projectBatch(events)

        // Build batch for server sync
        let eventData = try events.map { event -> (eventType: String, entityType: String, entityId: String, payload: [String: Any]) in
            (
                eventType: event.eventType.rawValue,
                entityType: event.eventType.entityType,
                entityId: extractEntityId(from: event),
                payload: try payloadToDictionary(event.payload)
            )
        }

        try eventRepository.enqueueBatch(events: eventData)
        updatePendingCounts()

        // Trigger sync if connected
        if networkMonitor.isConnected && !isPaused {
            Task {
                _ = await performIncrementalSync()
            }
        }
    }

    // MARK: - Private Methods

    private func pushPendingEvents() async throws -> [CDPendingEvent] {
        guard let apiClient = apiClient else {
            throw SyncEngineError.unknown("API client not configured")
        }

        var pushedEvents: [CDPendingEvent] = []
        let context = persistenceController.newBackgroundContext()

        // Process events in batches
        while true {
            let batch = eventRepository.dequeueBatch(limit: configuration.batchSize, context: context)

            if batch.isEmpty {
                break
            }

            // Convert to API format
            let apiEvents = batch.compactMap { event -> [String: Any]? in
                guard let payload = eventRepository.parsePayload(event) else { return nil }
                return [
                    "id": event.id,
                    "eventType": event.eventType,
                    "entityType": event.entityType,
                    "entityId": event.entityId,
                    "payload": payload,
                    "timestamp": ISO8601DateFormatter().string(from: event.createdAt),
                    "sequence": event.sequence
                ]
            }

            do {
                // Send to server
                try await apiClient.insertBatch(events: apiEvents)

                // Mark as completed
                let eventIds = batch.map { $0.id }
                try eventRepository.markCompleted(eventIds: eventIds)
                pushedEvents.append(contentsOf: batch)

            } catch {
                // Mark as failed and schedule retry
                for event in batch {
                    try? eventRepository.markFailed(eventId: event.id, error: error.localizedDescription)
                }
                throw SyncEngineError.serverError(500, error.localizedDescription)
            }
        }

        updatePendingCounts()
        return pushedEvents
    }

    private func pullServerChanges() async throws -> [DomainEvent] {
        guard let apiClient = apiClient else {
            throw SyncEngineError.unknown("API client not configured")
        }

        var pulledEvents: [DomainEvent] = []

        // Get cursor from sync state
        let cursor = eventRepository.getSyncCursor(key: CDSyncState.Keys.global)

        // Fetch changes from server
        let response = try await apiClient.queryChanges(since: cursor)

        // Project each event locally
        for eventData in response.events {
            if let event = parseDomainEvent(from: eventData) {
                eventProjector.project(event)
                pulledEvents.append(event)
            }
        }

        // Update cursor
        if let newCursor = response.cursor {
            try eventRepository.updateSyncCursor(
                key: CDSyncState.Keys.global,
                cursor: newCursor,
                serverVersion: response.version
            )
        }

        return pulledEvents
    }

    private func resolveConflicts() async throws -> [ConflictRecord] {
        // Get any conflicts that need resolution
        return conflictResolver.getConflictHistory().filter { $0.resolvedAt == nil }
    }

    private func handleConnectivityChange(isConnected: Bool) async {
        if isConnected {
            if isPaused {
                state = .paused
            } else {
                state = .idle
                if configuration.autoSyncOnConnect {
                    _ = await syncNow()
                }
            }
        } else {
            state = .offline
        }
    }

    private func handleQueueChange(_ change: QueueChange) {
        updatePendingCounts()

        switch change {
        case .failed(_, let error):
            print("[SyncEngine] Event failed: \(error)")
        default:
            break
        }
    }

    private func updatePendingCounts() {
        pendingEventCount = eventRepository.countPendingEvents()

        let stats = eventRepository.getQueueStatistics()
        failedEventCount = stats.failedCount
    }

    private func scheduleRetry() {
        guard retryCount < configuration.maxRetryAttempts else {
            state = .error(.unknown("Max retry attempts exceeded"))
            return
        }

        retryCount += 1
        let delay = min(
            configuration.baseRetryDelay * pow(2.0, Double(retryCount - 1)),
            configuration.maxRetryDelay
        )

        currentSyncTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            _ = await syncNow()
        }
    }

    private func extractEntityId(from event: DomainEvent) -> String {
        // Try to extract entity ID from payload
        if let payload = try? event.decodePayload([String: Any].self),
           let id = payload["id"] as? String ?? payload["entityId"] as? String {
            return id
        }
        return event.eventId
    }

    private func payloadToDictionary(_ payload: Data) throws -> [String: Any] {
        guard let dict = try JSONSerialization.jsonObject(with: payload) as? [String: Any] else {
            throw SyncEngineError.dataCorruption
        }
        return dict
    }

    private func parseDomainEvent(from data: [String: Any]) -> DomainEvent? {
        guard let eventTypeString = data["eventType"] as? String,
              let eventType = DomainEventType(rawValue: eventTypeString),
              let eventId = data["id"] as? String ?? data["eventId"] as? String,
              let userId = data["userId"] as? String,
              let payloadData = data["payload"] else {
            return nil
        }

        let payload: Data
        if let payloadDict = payloadData as? [String: Any] {
            payload = (try? JSONSerialization.data(withJSONObject: payloadDict)) ?? Data()
        } else if let payloadString = payloadData as? String {
            payload = payloadString.data(using: .utf8) ?? Data()
        } else {
            payload = Data()
        }

        let timestamp: Date
        if let timestampString = data["timestamp"] as? String {
            timestamp = ISO8601DateFormatter().date(from: timestampString) ?? Date()
        } else if let timestampInterval = data["timestamp"] as? TimeInterval {
            timestamp = Date(timeIntervalSince1970: timestampInterval)
        } else {
            timestamp = Date()
        }

        return DomainEvent(
            eventId: eventId,
            userId: userId,
            deviceId: data["deviceId"] as? String ?? deviceId,
            appId: data["appId"] as? String ?? "tasks-app",
            timestamp: timestamp,
            eventType: eventType,
            payload: payload,
            serverSequence: data["serverSequence"] as? Int64,
            isSynced: true,
            syncedAt: Date()
        )
    }
}

// MARK: - Sync Result

/// Result of a sync operation
struct SyncResult: Sendable {
    let success: Bool
    let pushedEvents: Int
    let pulledEvents: Int
    let resolvedConflicts: Int
    let error: SyncEngineError?

    init(
        success: Bool,
        pushedEvents: Int = 0,
        pulledEvents: Int = 0,
        resolvedConflicts: Int = 0,
        error: SyncEngineError? = nil
    ) {
        self.success = success
        self.pushedEvents = pushedEvents
        self.pulledEvents = pulledEvents
        self.resolvedConflicts = resolvedConflicts
        self.error = error
    }
}

// MARK: - Changes Response

/// Response from server when querying changes
struct ChangesResponse {
    let events: [[String: Any]]
    let cursor: String?
    let version: Int64?
    let hasMore: Bool
}

// MARK: - TasksAPIClient Protocol

/// Protocol for the Tasks API client
protocol TasksAPIClient: Sendable {
    func insertBatch(events: [[String: Any]]) async throws
    func queryChanges(since cursor: String?) async throws -> ChangesResponse
}
