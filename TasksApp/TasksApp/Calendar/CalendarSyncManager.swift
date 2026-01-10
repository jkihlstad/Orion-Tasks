//
//  CalendarSyncManager.swift
//  TasksApp
//
//  Main calendar sync coordinator using EventKit
//  Handles two-way sync between tasks and calendar events
//

import EventKit
import Foundation
import Combine
import SwiftUI

// MARK: - Calendar Sync Configuration

/// Configuration constants for calendar sync
enum CalendarSyncConfig {
    /// App name used for the dedicated calendar
    static let appName = "Orion Tasks"

    /// Calendar title for mirrored tasks
    static let calendarTitle = "\(appName) Tasks"

    /// URL scheme for task deep links
    static let taskURLScheme = "oriontasks"

    /// Marker prefix in notes to identify tasks
    static let taskLinkMarker = "[TaskLink:"

    /// Marker suffix in notes
    static let taskLinkMarkerEnd = "]"

    /// Minimum sync interval in seconds
    static let minimumSyncInterval: TimeInterval = 30

    /// Date range for fetching calendar events (days before today)
    static let fetchRangePastDays = 30

    /// Date range for fetching calendar events (days after today)
    static let fetchRangeFutureDays = 365
}

// MARK: - Calendar Sync Status

/// Current status of calendar sync
enum CalendarSyncStatus: Equatable {
    case idle
    case syncing
    case completed(Date)
    case failed(String)
    case disabled

    var displayText: String {
        switch self {
        case .idle:
            return "Ready to sync"
        case .syncing:
            return "Syncing..."
        case .completed(let date):
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .abbreviated
            return "Synced \(formatter.localizedString(for: date, relativeTo: Date()))"
        case .failed(let message):
            return "Failed: \(message)"
        case .disabled:
            return "Sync disabled"
        }
    }
}

// MARK: - Task-Event Mapping

/// Stores the mapping between tasks and calendar events
struct TaskEventMapping: Codable, Identifiable {
    let id: String // Task ID
    let eventIdentifier: String
    let calendarIdentifier: String
    let lastSyncedAt: Date
    let taskUpdatedAt: Date
    let eventUpdatedAt: Date?

    init(
        taskId: String,
        eventIdentifier: String,
        calendarIdentifier: String,
        taskUpdatedAt: Date,
        eventUpdatedAt: Date? = nil
    ) {
        self.id = taskId
        self.eventIdentifier = eventIdentifier
        self.calendarIdentifier = calendarIdentifier
        self.lastSyncedAt = Date()
        self.taskUpdatedAt = taskUpdatedAt
        self.eventUpdatedAt = eventUpdatedAt
    }
}

// MARK: - Calendar Sync Manager

/// Main coordinator for two-way calendar sync using EventKit
@MainActor
final class CalendarSyncManager: ObservableObject {

    // MARK: - Published Properties

    /// Current authorization status
    @Published private(set) var authorizationStatus: EKAuthorizationStatus = .notDetermined

    /// Whether calendar access is authorized
    @Published private(set) var isAuthorized: Bool = false

    /// Current sync status
    @Published private(set) var syncStatus: CalendarSyncStatus = .idle

    /// The dedicated app calendar for mirrored tasks
    @Published private(set) var appCalendar: EKCalendar?

    /// Calendars available for importing events as tasks
    @Published private(set) var availableCalendars: [EKCalendar] = []

    /// Calendars selected for importing events
    @Published var selectedCalendarIdentifiers: Set<String> = [] {
        didSet {
            saveSelectedCalendars()
        }
    }

    /// Whether global calendar sync is enabled
    @Published var isSyncEnabled: Bool = false {
        didSet {
            UserDefaults.standard.set(isSyncEnabled, forKey: StorageKeys.syncEnabled)
            if isSyncEnabled {
                Task { await performSync() }
            } else {
                syncStatus = .disabled
            }
        }
    }

    /// Last sync error
    @Published private(set) var lastError: CalendarSyncError?

    // MARK: - Private Properties

    private let eventStore: EKEventStore
    private var taskEventMappings: [String: TaskEventMapping] = [:]
    private var lastSyncDate: Date?
    private var syncTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Storage Keys

    private enum StorageKeys {
        static let syncEnabled = "calendar_sync_enabled"
        static let selectedCalendars = "calendar_sync_selected_calendars"
        static let taskEventMappings = "calendar_sync_task_event_mappings"
        static let appCalendarIdentifier = "calendar_sync_app_calendar_id"
        static let lastSyncDate = "calendar_sync_last_sync_date"
    }

    // MARK: - Initialization

    init() {
        self.eventStore = EKEventStore()

        loadPersistedState()
        checkAuthorizationStatus()
        setupNotifications()
    }

    // MARK: - Setup

    private func loadPersistedState() {
        isSyncEnabled = UserDefaults.standard.bool(forKey: StorageKeys.syncEnabled)

        if let data = UserDefaults.standard.data(forKey: StorageKeys.selectedCalendars),
           let identifiers = try? JSONDecoder().decode(Set<String>.self, from: data) {
            selectedCalendarIdentifiers = identifiers
        }

        if let data = UserDefaults.standard.data(forKey: StorageKeys.taskEventMappings),
           let mappings = try? JSONDecoder().decode([String: TaskEventMapping].self, from: data) {
            taskEventMappings = mappings
        }

        if let timestamp = UserDefaults.standard.object(forKey: StorageKeys.lastSyncDate) as? Date {
            lastSyncDate = timestamp
        }
    }

    private func setupNotifications() {
        // Listen for EventKit store changes
        NotificationCenter.default.publisher(for: .EKEventStoreChanged)
            .debounce(for: .seconds(1), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                Task { @MainActor in
                    await self?.handleEventStoreChanged()
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Authorization

    /// Checks the current authorization status
    func checkAuthorizationStatus() {
        if #available(iOS 17.0, *) {
            authorizationStatus = EKEventStore.authorizationStatus(for: .event)
        } else {
            authorizationStatus = EKEventStore.authorizationStatus(for: .event)
        }

        isAuthorized = authorizationStatus == .authorized

        if isAuthorized {
            loadCalendars()
        }
    }

    /// Requests calendar access from the user
    func requestCalendarAccess() async -> Bool {
        do {
            var granted: Bool

            if #available(iOS 17.0, *) {
                granted = try await eventStore.requestFullAccessToEvents()
            } else {
                granted = try await eventStore.requestAccess(to: .event)
            }

            authorizationStatus = EKEventStore.authorizationStatus(for: .event)
            isAuthorized = granted

            if granted {
                loadCalendars()
                await findOrCreateAppCalendar()
            }

            return granted
        } catch {
            lastError = .authorizationFailed(error)
            return false
        }
    }

    // MARK: - Calendar Management

    /// Loads available calendars
    private func loadCalendars() {
        availableCalendars = eventStore.calendars(for: .event)
            .filter { $0.allowsContentModifications }
            .sorted { $0.title < $1.title }

        // Try to find existing app calendar
        if let savedId = UserDefaults.standard.string(forKey: StorageKeys.appCalendarIdentifier),
           let calendar = eventStore.calendar(withIdentifier: savedId) {
            appCalendar = calendar
        }
    }

    /// Finds or creates the dedicated app calendar
    @discardableResult
    func findOrCreateAppCalendar() async -> EKCalendar? {
        // First try to find existing calendar
        if let existing = availableCalendars.first(where: { $0.title == CalendarSyncConfig.calendarTitle }) {
            appCalendar = existing
            UserDefaults.standard.set(existing.calendarIdentifier, forKey: StorageKeys.appCalendarIdentifier)
            return existing
        }

        // Create new calendar
        let newCalendar = EKCalendar(for: .event, eventStore: eventStore)
        newCalendar.title = CalendarSyncConfig.calendarTitle

        // Find a suitable source for the calendar
        if let localSource = eventStore.sources.first(where: { $0.sourceType == .local }) {
            newCalendar.source = localSource
        } else if let iCloudSource = eventStore.sources.first(where: { $0.sourceType == .calDAV && $0.title.lowercased().contains("icloud") }) {
            newCalendar.source = iCloudSource
        } else if let defaultSource = eventStore.defaultCalendarForNewEvents?.source {
            newCalendar.source = defaultSource
        } else {
            lastError = .noCalendarSource
            return nil
        }

        // Set calendar color to match app theme
        newCalendar.cgColor = CGColor(red: 0.04, green: 0.52, blue: 1.0, alpha: 1.0) // #0A84FF

        do {
            try eventStore.saveCalendar(newCalendar, commit: true)
            appCalendar = newCalendar
            UserDefaults.standard.set(newCalendar.calendarIdentifier, forKey: StorageKeys.appCalendarIdentifier)
            loadCalendars()
            return newCalendar
        } catch {
            lastError = .calendarCreationFailed(error)
            return nil
        }
    }

    // MARK: - Sync Operations

    /// Performs a full two-way sync
    func performSync() async {
        guard isAuthorized else {
            syncStatus = .failed("Calendar access not authorized")
            return
        }

        guard isSyncEnabled else {
            syncStatus = .disabled
            return
        }

        // Rate limit sync
        if let lastSync = lastSyncDate,
           Date().timeIntervalSince(lastSync) < CalendarSyncConfig.minimumSyncInterval {
            return
        }

        syncStatus = .syncing
        lastError = nil

        do {
            // Ensure app calendar exists
            if appCalendar == nil {
                await findOrCreateAppCalendar()
            }

            // Import events from selected calendars
            try await importCalendarEvents()

            // Sync completed
            lastSyncDate = Date()
            UserDefaults.standard.set(lastSyncDate, forKey: StorageKeys.lastSyncDate)
            syncStatus = .completed(lastSyncDate!)

        } catch {
            lastError = error as? CalendarSyncError ?? .syncFailed(error)
            syncStatus = .failed(error.localizedDescription)
        }
    }

    /// Syncs a specific task to the calendar
    func syncTaskToCalendar(_ task: TaskModel) async throws {
        guard isAuthorized else {
            throw CalendarSyncError.notAuthorized
        }

        guard task.mirrorToCalendarEnabled else {
            // If mirroring is disabled but event exists, delete it
            if let mapping = taskEventMappings[task.id] {
                try await deleteEventForTask(task.id)
                taskEventMappings.removeValue(forKey: task.id)
                saveMappings()
            }
            return
        }

        guard let calendar = appCalendar else {
            await findOrCreateAppCalendar()
            guard let calendar = appCalendar else {
                throw CalendarSyncError.noAppCalendar
            }
            try await syncTaskToCalendar(task, calendar: calendar)
            return
        }

        try await syncTaskToCalendar(task, calendar: calendar)
    }

    private func syncTaskToCalendar(_ task: TaskModel, calendar: EKCalendar) async throws {
        // Check for existing mapping
        if let mapping = taskEventMappings[task.id],
           let existingEvent = eventStore.event(withIdentifier: mapping.eventIdentifier) {
            // Update existing event
            CalendarMapper.updateEvent(existingEvent, from: task)
            try eventStore.save(existingEvent, span: .thisEvent)

            // Update mapping
            taskEventMappings[task.id] = TaskEventMapping(
                taskId: task.id,
                eventIdentifier: existingEvent.eventIdentifier,
                calendarIdentifier: calendar.calendarIdentifier,
                taskUpdatedAt: task.updatedAt,
                eventUpdatedAt: existingEvent.lastModifiedDate
            )
        } else {
            // Create new event
            let event = EKEvent(eventStore: eventStore)
            event.calendar = calendar
            CalendarMapper.updateEvent(event, from: task)

            try eventStore.save(event, span: .thisEvent)

            // Store mapping
            taskEventMappings[task.id] = TaskEventMapping(
                taskId: task.id,
                eventIdentifier: event.eventIdentifier,
                calendarIdentifier: calendar.calendarIdentifier,
                taskUpdatedAt: task.updatedAt,
                eventUpdatedAt: event.lastModifiedDate
            )
        }

        saveMappings()
    }

    /// Removes a task's calendar event
    func deleteEventForTask(_ taskId: String) async throws {
        guard let mapping = taskEventMappings[taskId],
              let event = eventStore.event(withIdentifier: mapping.eventIdentifier) else {
            taskEventMappings.removeValue(forKey: taskId)
            saveMappings()
            return
        }

        try eventStore.remove(event, span: .thisEvent)
        taskEventMappings.removeValue(forKey: taskId)
        saveMappings()
    }

    // MARK: - Import Operations

    /// Imports events from selected calendars as tasks
    private func importCalendarEvents() async throws {
        guard !selectedCalendarIdentifiers.isEmpty else { return }

        let calendars = availableCalendars.filter { selectedCalendarIdentifiers.contains($0.calendarIdentifier) }
        guard !calendars.isEmpty else { return }

        // Don't import from our own app calendar
        let importCalendars = calendars.filter { $0.calendarIdentifier != appCalendar?.calendarIdentifier }

        let startDate = Calendar.current.date(byAdding: .day, value: -CalendarSyncConfig.fetchRangePastDays, to: Date())!
        let endDate = Calendar.current.date(byAdding: .day, value: CalendarSyncConfig.fetchRangeFutureDays, to: Date())!

        let predicate = eventStore.predicateForEvents(withStart: startDate, end: endDate, calendars: importCalendars)
        let events = eventStore.events(matching: predicate)

        var importedTasks: [Task] = []

        for event in events {
            // Skip events that were created from our tasks (loop prevention)
            if isEventFromTask(event) {
                continue
            }

            // Skip events that are already imported
            if isEventAlreadyImported(event) {
                continue
            }

            // Convert event to task
            if let task = CalendarMapper.taskFromEvent(event) {
                importedTasks.append(task)
            }
        }

        // Note: The actual task creation should be delegated to a TaskRepository
        // This is a placeholder for the integration point
        for task in importedTasks {
            // Create the task in the app's data store
            // await taskRepository.createTask(task)
            print("[CalendarSync] Would import task: \(task.title)")
        }
    }

    /// Checks if an event was created from a task (loop prevention)
    private func isEventFromTask(_ event: EKEvent) -> Bool {
        // Check if event is in our app calendar
        if event.calendar.calendarIdentifier == appCalendar?.calendarIdentifier {
            return true
        }

        // Check for task link marker in notes
        if let notes = event.notes, notes.contains(CalendarSyncConfig.taskLinkMarker) {
            return true
        }

        // Check URL for our scheme
        if let url = event.url, url.scheme == CalendarSyncConfig.taskURLScheme {
            return true
        }

        return false
    }

    /// Checks if an event is already imported as a task
    private func isEventAlreadyImported(_ event: EKEvent) -> Bool {
        // Check if we have a mapping for this event's identifier
        return taskEventMappings.values.contains { $0.eventIdentifier == event.eventIdentifier }
    }

    // MARK: - Event Store Changes

    private func handleEventStoreChanged() async {
        loadCalendars()

        // Check if app calendar still exists
        if let savedId = UserDefaults.standard.string(forKey: StorageKeys.appCalendarIdentifier) {
            if eventStore.calendar(withIdentifier: savedId) == nil {
                appCalendar = nil
                await findOrCreateAppCalendar()
            }
        }

        if isSyncEnabled {
            await performSync()
        }
    }

    // MARK: - Mapping Management

    /// Returns the event identifier linked to a task
    func eventIdentifier(for taskId: String) -> String? {
        return taskEventMappings[taskId]?.eventIdentifier
    }

    /// Returns the mapping for a task
    func mapping(for taskId: String) -> TaskEventMapping? {
        return taskEventMappings[taskId]
    }

    /// Updates the mapping after a task is modified
    func updateMapping(for task: TaskModel, linkedEventIdentifier: String?) {
        if let eventId = linkedEventIdentifier {
            taskEventMappings[task.id] = TaskEventMapping(
                taskId: task.id,
                eventIdentifier: eventId,
                calendarIdentifier: appCalendar?.calendarIdentifier ?? "",
                taskUpdatedAt: task.updatedAt
            )
        } else {
            taskEventMappings.removeValue(forKey: task.id)
        }
        saveMappings()
    }

    // MARK: - Persistence

    private func saveMappings() {
        if let data = try? JSONEncoder().encode(taskEventMappings) {
            UserDefaults.standard.set(data, forKey: StorageKeys.taskEventMappings)
        }
    }

    private func saveSelectedCalendars() {
        if let data = try? JSONEncoder().encode(selectedCalendarIdentifiers) {
            UserDefaults.standard.set(data, forKey: StorageKeys.selectedCalendars)
        }
    }

    // MARK: - Cleanup

    /// Removes all app-created calendar events
    func removeAllSyncedEvents() async throws {
        guard let calendar = appCalendar else { return }

        let startDate = Calendar.current.date(byAdding: .year, value: -1, to: Date())!
        let endDate = Calendar.current.date(byAdding: .year, value: 2, to: Date())!

        let predicate = eventStore.predicateForEvents(withStart: startDate, end: endDate, calendars: [calendar])
        let events = eventStore.events(matching: predicate)

        for event in events {
            try eventStore.remove(event, span: .thisEvent)
        }

        try eventStore.commit()

        taskEventMappings.removeAll()
        saveMappings()
    }

    /// Disconnects calendar sync and removes data
    func disconnect() async {
        isSyncEnabled = false
        selectedCalendarIdentifiers.removeAll()
        taskEventMappings.removeAll()
        appCalendar = nil
        lastSyncDate = nil

        UserDefaults.standard.removeObject(forKey: StorageKeys.syncEnabled)
        UserDefaults.standard.removeObject(forKey: StorageKeys.selectedCalendars)
        UserDefaults.standard.removeObject(forKey: StorageKeys.taskEventMappings)
        UserDefaults.standard.removeObject(forKey: StorageKeys.appCalendarIdentifier)
        UserDefaults.standard.removeObject(forKey: StorageKeys.lastSyncDate)

        syncStatus = .disabled
    }
}

// MARK: - Calendar Sync Error

enum CalendarSyncError: LocalizedError {
    case notAuthorized
    case authorizationFailed(Error)
    case noCalendarSource
    case calendarCreationFailed(Error)
    case noAppCalendar
    case eventCreationFailed(Error)
    case eventUpdateFailed(Error)
    case eventDeletionFailed(Error)
    case syncFailed(Error)
    case importFailed(Error)

    var errorDescription: String? {
        switch self {
        case .notAuthorized:
            return "Calendar access not authorized"
        case .authorizationFailed(let error):
            return "Failed to get calendar authorization: \(error.localizedDescription)"
        case .noCalendarSource:
            return "No suitable calendar source found"
        case .calendarCreationFailed(let error):
            return "Failed to create app calendar: \(error.localizedDescription)"
        case .noAppCalendar:
            return "App calendar not available"
        case .eventCreationFailed(let error):
            return "Failed to create calendar event: \(error.localizedDescription)"
        case .eventUpdateFailed(let error):
            return "Failed to update calendar event: \(error.localizedDescription)"
        case .eventDeletionFailed(let error):
            return "Failed to delete calendar event: \(error.localizedDescription)"
        case .syncFailed(let error):
            return "Sync failed: \(error.localizedDescription)"
        case .importFailed(let error):
            return "Import failed: \(error.localizedDescription)"
        }
    }
}

// MARK: - EKCalendar Extension

extension EKCalendar {
    /// SwiftUI Color representation of the calendar color
    var swiftUIColor: Color {
        Color(cgColor: cgColor)
    }
}
