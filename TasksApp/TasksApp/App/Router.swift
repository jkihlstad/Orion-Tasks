//
//  Router.swift
//  TasksApp
//
//  Navigation router managing app-wide navigation state
//  Supports sidebar, list detail, task detail, settings, and onboarding flows
//

import SwiftUI
import Combine

// MARK: - Router

@MainActor
final class Router: ObservableObject {

    // MARK: - Navigation State

    /// Current root view of the app
    @Published var currentRoot: RootDestination = .main

    /// Main navigation path for the primary content
    @Published var mainPath = NavigationPath()

    /// Onboarding navigation path
    @Published var onboardingPath = NavigationPath()

    /// Settings navigation path
    @Published var settingsPath = NavigationPath()

    // MARK: - Selection State

    /// Currently selected list in sidebar
    @Published var selectedListId: String?

    /// Currently selected task in list
    @Published var selectedTaskId: String?

    /// Sidebar visibility state
    @Published var sidebarVisible: Bool = true

    // MARK: - Presentation State

    /// Currently presented sheet
    @Published var presentedSheet: Sheet?

    /// Currently presented full screen cover
    @Published var presentedFullScreenCover: FullScreenCover?

    /// Alert to present
    @Published var presentedAlert: AlertItem?

    /// Confirmation dialog to present
    @Published var presentedConfirmation: ConfirmationItem?

    // MARK: - Tab State (for iPhone/Compact layout)

    @Published var selectedTab: Tab = .today

    // MARK: - Deep Link State

    private var pendingDeepLink: DeepLink?
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Navigation History

    private var navigationHistory: [NavigationHistoryEntry] = []
    private let maxHistorySize = 50

    // MARK: - Initialization

    init() {
        setupBindings()
    }

    private func setupBindings() {
        // Track navigation history
        $selectedListId
            .dropFirst()
            .sink { [weak self] listId in
                if let listId = listId {
                    self?.recordNavigation(.listSelected(listId))
                }
            }
            .store(in: &cancellables)

        $selectedTaskId
            .dropFirst()
            .sink { [weak self] taskId in
                if let taskId = taskId {
                    self?.recordNavigation(.taskSelected(taskId))
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Root Navigation

    func navigate(to destination: Destination) {
        switch destination {
        case .onboarding:
            withAnimation(.easeInOut(duration: 0.3)) {
                currentRoot = .onboarding
                resetMainState()
            }

        case .sidebar:
            withAnimation(.easeInOut(duration: 0.3)) {
                currentRoot = .main
                selectedListId = nil
                selectedTaskId = nil
            }
            recordNavigation(.rootChanged(.main))

        case .listDetail(let listId):
            currentRoot = .main
            selectedListId = listId
            selectedTaskId = nil
            recordNavigation(.listSelected(listId))

        case .taskDetail(let taskId, let listId):
            currentRoot = .main
            if let listId = listId {
                selectedListId = listId
            }
            selectedTaskId = taskId
            recordNavigation(.taskSelected(taskId))

        case .settings:
            presentedFullScreenCover = .settings
            recordNavigation(.settingsOpened)

        case .search:
            presentedFullScreenCover = .search
            recordNavigation(.searchOpened)
        }
    }

    // MARK: - List Navigation

    func selectList(_ destination: ListDestination) {
        switch destination {
        case .today:
            selectedListId = "smart-today"
        case .scheduled:
            selectedListId = "smart-scheduled"
        case .all:
            selectedListId = "smart-all"
        case .flagged:
            selectedListId = "smart-flagged"
        case .completed:
            selectedListId = "smart-completed"
        case .custom(let id):
            selectedListId = id
        }
        selectedTaskId = nil
    }

    func selectTask(_ taskId: String) {
        selectedTaskId = taskId
    }

    func clearTaskSelection() {
        selectedTaskId = nil
    }

    func clearListSelection() {
        selectedListId = nil
        selectedTaskId = nil
    }

    // MARK: - Sidebar Control

    func toggleSidebar() {
        withAnimation(.easeInOut(duration: 0.2)) {
            sidebarVisible.toggle()
        }
    }

    func showSidebar() {
        withAnimation(.easeInOut(duration: 0.2)) {
            sidebarVisible = true
        }
    }

    func hideSidebar() {
        withAnimation(.easeInOut(duration: 0.2)) {
            sidebarVisible = false
        }
    }

    // MARK: - Sheet Presentation

    func presentNewTask(listId: String? = nil) {
        presentedSheet = .newTask(listId: listId ?? selectedListId)
    }

    func presentNewList() {
        presentedSheet = .newList
    }

    func presentEditTask(_ taskId: String) {
        presentedSheet = .editTask(taskId: taskId)
    }

    func presentEditList(_ listId: String) {
        presentedSheet = .editList(listId: listId)
    }

    func presentTaskPicker(onSelect: @escaping (String) -> Void) {
        presentedSheet = .taskPicker(onSelect: onSelect)
    }

    func presentDatePicker(initialDate: Date? = nil, onSelect: @escaping (Date) -> Void) {
        presentedSheet = .datePicker(date: initialDate, onSelect: onSelect)
    }

    func presentShareSheet(items: [Any]) {
        presentedSheet = .share(items: items)
    }

    func dismissSheet() {
        presentedSheet = nil
    }

    // MARK: - Full Screen Cover Presentation

    func presentSettings() {
        presentedFullScreenCover = .settings
    }

    func presentSearch() {
        presentedFullScreenCover = .search
    }

    func presentCalendarIntegration() {
        presentedFullScreenCover = .calendarIntegration
    }

    func dismissFullScreenCover() {
        presentedFullScreenCover = nil
    }

    // MARK: - Alert Presentation

    func showAlert(
        title: String,
        message: String? = nil,
        primaryButton: AlertButton = .ok(),
        secondaryButton: AlertButton? = nil
    ) {
        presentedAlert = AlertItem(
            title: title,
            message: message,
            primaryButton: primaryButton,
            secondaryButton: secondaryButton
        )
    }

    func showErrorAlert(_ error: Error) {
        showAlert(
            title: "Error",
            message: error.localizedDescription,
            primaryButton: .ok()
        )
    }

    func showDeleteConfirmation(
        title: String = "Delete",
        message: String,
        onConfirm: @escaping () -> Void
    ) {
        presentedConfirmation = ConfirmationItem(
            title: title,
            message: message,
            confirmButton: .destructive(title: "Delete", action: onConfirm),
            cancelButton: .cancel()
        )
    }

    func dismissAlert() {
        presentedAlert = nil
    }

    func dismissConfirmation() {
        presentedConfirmation = nil
    }

    // MARK: - Deep Linking

    func handleDeepLink(_ url: URL) -> Bool {
        guard let deepLink = DeepLink(url: url) else {
            return false
        }

        return processDeepLink(deepLink)
    }

    func processPendingDeepLinks() {
        guard let deepLink = pendingDeepLink else { return }
        pendingDeepLink = nil
        _ = processDeepLink(deepLink)
    }

    private func processDeepLink(_ deepLink: DeepLink) -> Bool {
        // If app is not ready, store for later
        guard currentRoot == .main else {
            pendingDeepLink = deepLink
            return true
        }

        switch deepLink {
        case .task(let taskId):
            navigate(to: .taskDetail(taskId: taskId, listId: nil))
            return true

        case .list(let listId):
            navigate(to: .listDetail(listId: listId))
            return true

        case .newTask(let listId):
            presentNewTask(listId: listId)
            return true

        case .settings:
            presentSettings()
            return true

        case .search(let query):
            presentSearch()
            // TODO: Pass query to search view
            return true
        }
    }

    // MARK: - Navigation History

    func goBack() -> Bool {
        // Try to go back in current context
        if selectedTaskId != nil {
            selectedTaskId = nil
            return true
        }

        if selectedListId != nil {
            selectedListId = nil
            return true
        }

        if !mainPath.isEmpty {
            mainPath.removeLast()
            return true
        }

        return false
    }

    func popToRoot() {
        mainPath = NavigationPath()
        selectedListId = nil
        selectedTaskId = nil
    }

    private func recordNavigation(_ entry: NavigationHistoryEntry) {
        navigationHistory.append(entry)

        // Trim history if needed
        if navigationHistory.count > maxHistorySize {
            navigationHistory.removeFirst(navigationHistory.count - maxHistorySize)
        }
    }

    // MARK: - State Reset

    func resetMainState() {
        mainPath = NavigationPath()
        selectedListId = nil
        selectedTaskId = nil
        presentedSheet = nil
        presentedFullScreenCover = nil
        presentedAlert = nil
        presentedConfirmation = nil
    }

    func resetOnboardingState() {
        onboardingPath = NavigationPath()
    }

    func resetAllState() {
        resetMainState()
        resetOnboardingState()
        settingsPath = NavigationPath()
        navigationHistory = []
        pendingDeepLink = nil
    }
}

// MARK: - Root Destination

extension Router {
    enum RootDestination: Equatable {
        case onboarding
        case main
    }
}

// MARK: - Navigation Destinations

extension Router {
    enum Destination: Hashable {
        case onboarding
        case sidebar
        case listDetail(listId: String)
        case taskDetail(taskId: String, listId: String?)
        case settings
        case search
    }

    enum ListDestination: Hashable {
        case today
        case scheduled
        case all
        case flagged
        case completed
        case custom(id: String)
    }

    enum OnboardingDestination: Hashable {
        case welcome
        case features
        case permissions
        case authentication
        case complete
    }

    enum SettingsDestination: Hashable {
        case profile
        case account
        case appearance
        case notifications
        case calendar
        case sync
        case privacy
        case about
        case debug
    }
}

// MARK: - Sheet Types

extension Router {
    enum Sheet: Identifiable, Equatable {
        case newTask(listId: String?)
        case newList
        case editTask(taskId: String)
        case editList(listId: String)
        case taskPicker(onSelect: (String) -> Void)
        case datePicker(date: Date?, onSelect: (Date) -> Void)
        case share(items: [Any])

        var id: String {
            switch self {
            case .newTask(let listId):
                return "newTask-\(listId ?? "none")"
            case .newList:
                return "newList"
            case .editTask(let taskId):
                return "editTask-\(taskId)"
            case .editList(let listId):
                return "editList-\(listId)"
            case .taskPicker:
                return "taskPicker"
            case .datePicker:
                return "datePicker"
            case .share:
                return "share"
            }
        }

        var presentationDetents: Set<PresentationDetent> {
            switch self {
            case .newTask, .editTask:
                return [.medium, .large]
            case .newList, .editList:
                return [.medium]
            case .taskPicker:
                return [.medium, .large]
            case .datePicker:
                return [.medium]
            case .share:
                return [.medium]
            }
        }

        static func == (lhs: Sheet, rhs: Sheet) -> Bool {
            lhs.id == rhs.id
        }
    }
}

// MARK: - Full Screen Cover Types

extension Router {
    enum FullScreenCover: String, Identifiable {
        case settings
        case search
        case calendarIntegration

        var id: String { rawValue }
    }
}

// MARK: - Alert Types

extension Router {
    struct AlertItem: Identifiable {
        let id = UUID()
        let title: String
        let message: String?
        let primaryButton: AlertButton
        let secondaryButton: AlertButton?
    }

    struct AlertButton {
        let title: String
        let role: ButtonRole?
        let action: (() -> Void)?

        static func ok(action: (() -> Void)? = nil) -> AlertButton {
            AlertButton(title: "OK", role: nil, action: action)
        }

        static func cancel(action: (() -> Void)? = nil) -> AlertButton {
            AlertButton(title: "Cancel", role: .cancel, action: action)
        }

        static func destructive(title: String, action: @escaping () -> Void) -> AlertButton {
            AlertButton(title: title, role: .destructive, action: action)
        }

        static func custom(title: String, role: ButtonRole? = nil, action: @escaping () -> Void) -> AlertButton {
            AlertButton(title: title, role: role, action: action)
        }
    }

    struct ConfirmationItem: Identifiable {
        let id = UUID()
        let title: String
        let message: String
        let confirmButton: AlertButton
        let cancelButton: AlertButton
    }
}

// MARK: - Deep Link Types

extension Router {
    enum DeepLink {
        case task(id: String)
        case list(id: String)
        case newTask(listId: String?)
        case settings
        case search(query: String?)

        init?(url: URL) {
            // Expected format: tasksapp://[action]/[id]
            // Examples:
            // - tasksapp://task/123
            // - tasksapp://list/456
            // - tasksapp://new-task
            // - tasksapp://new-task?list=789
            // - tasksapp://settings
            // - tasksapp://search?q=meeting

            guard url.scheme == "tasksapp" || url.scheme == "orion-tasks" else {
                return nil
            }

            let pathComponents = url.pathComponents.filter { $0 != "/" }
            let host = url.host

            // Parse URL components
            let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?
                .reduce(into: [String: String]()) { $0[$1.name] = $1.value } ?? [:]

            // Determine action from host or first path component
            let action = host ?? pathComponents.first

            switch action {
            case "task":
                guard let taskId = pathComponents.dropFirst().first ?? queryItems["id"] else {
                    return nil
                }
                self = .task(id: taskId)

            case "list":
                guard let listId = pathComponents.dropFirst().first ?? queryItems["id"] else {
                    return nil
                }
                self = .list(id: listId)

            case "new-task", "newtask":
                self = .newTask(listId: queryItems["list"])

            case "settings":
                self = .settings

            case "search":
                self = .search(query: queryItems["q"])

            default:
                return nil
            }
        }
    }
}

// MARK: - Navigation History

extension Router {
    enum NavigationHistoryEntry {
        case rootChanged(RootDestination)
        case listSelected(String)
        case taskSelected(String)
        case sheetPresented(Sheet)
        case sheetDismissed
        case settingsOpened
        case searchOpened

        var timestamp: Date {
            Date()
        }
    }
}

// MARK: - Route Builder

extension Router {

    /// Builds a navigation URL for sharing or deep linking
    func buildURL(for destination: Destination) -> URL? {
        var components = URLComponents()
        components.scheme = "tasksapp"

        switch destination {
        case .taskDetail(let taskId, _):
            components.host = "task"
            components.path = "/\(taskId)"

        case .listDetail(let listId):
            components.host = "list"
            components.path = "/\(listId)"

        case .settings:
            components.host = "settings"

        case .search:
            components.host = "search"

        case .onboarding, .sidebar:
            return nil
        }

        return components.url
    }
}

// MARK: - Navigation Context

extension Router {

    /// Current navigation context for analytics and state restoration
    var currentContext: NavigationContext {
        NavigationContext(
            root: currentRoot,
            selectedListId: selectedListId,
            selectedTaskId: selectedTaskId,
            isPresentingSheet: presentedSheet != nil,
            isPresentingFullScreenCover: presentedFullScreenCover != nil
        )
    }

    struct NavigationContext: Codable, Equatable {
        let root: String
        let selectedListId: String?
        let selectedTaskId: String?
        let isPresentingSheet: Bool
        let isPresentingFullScreenCover: Bool

        init(
            root: RootDestination,
            selectedListId: String?,
            selectedTaskId: String?,
            isPresentingSheet: Bool,
            isPresentingFullScreenCover: Bool
        ) {
            self.root = root == .onboarding ? "onboarding" : "main"
            self.selectedListId = selectedListId
            self.selectedTaskId = selectedTaskId
            self.isPresentingSheet = isPresentingSheet
            self.isPresentingFullScreenCover = isPresentingFullScreenCover
        }
    }

    /// Restore navigation state from a context
    func restore(from context: NavigationContext) {
        currentRoot = context.root == "onboarding" ? .onboarding : .main
        selectedListId = context.selectedListId
        selectedTaskId = context.selectedTaskId
        // Note: Sheets and covers are not restored to avoid unexpected UI state
    }
}

// MARK: - Keyboard Shortcut Support

extension Router {

    /// Handle keyboard shortcuts for navigation
    func handleKeyboardShortcut(_ shortcut: KeyboardShortcut) -> Bool {
        switch shortcut {
        case .newTask:
            presentNewTask()
            return true

        case .newList:
            presentNewList()
            return true

        case .search:
            presentSearch()
            return true

        case .settings:
            presentSettings()
            return true

        case .goBack:
            return goBack()

        case .toggleSidebar:
            toggleSidebar()
            return true

        case .selectToday:
            selectList(.today)
            return true

        case .selectAll:
            selectList(.all)
            return true
        }
    }

    enum KeyboardShortcut {
        case newTask        // Cmd+N
        case newList        // Cmd+Shift+N
        case search         // Cmd+F
        case settings       // Cmd+,
        case goBack         // Cmd+[
        case toggleSidebar  // Cmd+Option+S
        case selectToday    // Cmd+1
        case selectAll      // Cmd+2
    }
}

// MARK: - Tab Support (for iPhone/Compact layout)

extension Router {
    enum Tab: String, CaseIterable, Identifiable {
        case today
        case all
        case lists
        case search
        case settings

        var id: String { rawValue }

        var title: String {
            switch self {
            case .today: return "Today"
            case .all: return "All"
            case .lists: return "Lists"
            case .search: return "Search"
            case .settings: return "Settings"
            }
        }

        var systemImage: String {
            switch self {
            case .today: return "star.fill"
            case .all: return "tray.fill"
            case .lists: return "list.bullet"
            case .search: return "magnifyingglass"
            case .settings: return "gear"
            }
        }
    }

    func selectTab(_ tab: Tab) {
        selectedTab = tab

        // Update list selection based on tab
        switch tab {
        case .today:
            selectList(.today)
        case .all:
            selectList(.all)
        case .lists:
            // Show lists view
            selectedListId = nil
        case .search:
            // Search handled separately
            break
        case .settings:
            // Settings handled separately
            break
        }
    }
}

// MARK: - Environment Key

private struct RouterKey: EnvironmentKey {
    static let defaultValue: Router? = nil
}

extension EnvironmentValues {
    var router: Router? {
        get { self[RouterKey.self] }
        set { self[RouterKey.self] = newValue }
    }
}

// MARK: - View Extension for Router Access

extension View {
    func withRouter(_ router: Router) -> some View {
        self.environment(\.router, router)
    }
}
