//
//  TasksApp.swift
//  TasksApp
//
//  Main application entry point for the Tasks app (Reminders clone)
//  Dark mode first design with Clerk authentication integration
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - App Entry Point

@main
struct TasksApp: App {

    // MARK: - State Objects

    @StateObject private var appEnvironment = AppEnvironment()
    @StateObject private var router = Router()

    // MARK: - Environment

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme

    // MARK: - App Storage

    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("preferredColorScheme") private var preferredColorScheme: String = "dark"

    // MARK: - Body

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appEnvironment)
                .environmentObject(appEnvironment.authProvider)
                .environmentObject(appEnvironment.syncEngine)
                .environmentObject(appEnvironment.calendarSyncManager)
                .environmentObject(appEnvironment.notificationScheduler)
                .environmentObject(router)
                .preferredColorScheme(resolvedColorScheme)
                .onAppear {
                    configureAppearance()
                    handleInitialRoute()
                }
                .onChange(of: scenePhase) { oldPhase, newPhase in
                    handleScenePhaseChange(from: oldPhase, to: newPhase)
                }
                .onChange(of: appEnvironment.authProvider.isAuthenticated) { _, isAuthenticated in
                    handleAuthenticationChange(isAuthenticated: isAuthenticated)
                }
        }
        .commands {
            appCommands
        }
    }

    // MARK: - Computed Properties

    private var resolvedColorScheme: ColorScheme? {
        switch preferredColorScheme {
        case "light":
            return .light
        case "dark":
            return .dark
        default:
            return .dark // Dark mode first
        }
    }

    // MARK: - App Commands

    @CommandsBuilder
    private var appCommands: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Task") {
                router.presentNewTask()
            }
            .keyboardShortcut("n", modifiers: .command)

            Button("New List") {
                router.presentNewList()
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])
        }

        CommandGroup(after: .sidebar) {
            Button("Show Sidebar") {
                router.toggleSidebar()
            }
            .keyboardShortcut("s", modifiers: [.command, .option])
        }

        CommandGroup(replacing: .appSettings) {
            Button("Settings...") {
                router.navigate(to: .settings)
            }
            .keyboardShortcut(",", modifiers: .command)
        }
    }

    // MARK: - Configuration

    private func configureAppearance() {
        #if os(iOS)
        // Configure navigation bar appearance for dark mode first
        let navigationBarAppearance = UINavigationBarAppearance()
        navigationBarAppearance.configureWithOpaqueBackground()
        navigationBarAppearance.backgroundColor = UIColor.systemBackground
        navigationBarAppearance.titleTextAttributes = [.foregroundColor: UIColor.label]
        navigationBarAppearance.largeTitleTextAttributes = [.foregroundColor: UIColor.label]

        UINavigationBar.appearance().standardAppearance = navigationBarAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = navigationBarAppearance
        UINavigationBar.appearance().compactAppearance = navigationBarAppearance

        // Configure tab bar appearance
        let tabBarAppearance = UITabBarAppearance()
        tabBarAppearance.configureWithOpaqueBackground()
        tabBarAppearance.backgroundColor = UIColor.systemBackground

        UITabBar.appearance().standardAppearance = tabBarAppearance
        UITabBar.appearance().scrollEdgeAppearance = tabBarAppearance

        // Configure table view appearance
        UITableView.appearance().backgroundColor = .clear
        UITableViewCell.appearance().backgroundColor = .clear

        // Set tint color
        UIView.appearance(whenContainedInInstancesOf: [UIAlertController.self]).tintColor = UIColor.systemBlue
        #endif
    }

    private func handleInitialRoute() {
        Task { @MainActor in
            // Small delay to ensure environment is fully initialized
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds

            if !hasCompletedOnboarding {
                router.navigate(to: .onboarding)
            } else if !appEnvironment.authProvider.isAuthenticated {
                router.navigate(to: .onboarding)
            } else {
                router.navigate(to: .sidebar)
            }
        }
    }

    // MARK: - Scene Phase Handling

    private func handleScenePhaseChange(from oldPhase: ScenePhase, to newPhase: ScenePhase) {
        switch newPhase {
        case .active:
            handleBecameActive()
        case .inactive:
            handleBecameInactive()
        case .background:
            handleEnteredBackground()
        @unknown default:
            break
        }
    }

    private func handleBecameActive() {
        // Resume sync operations
        Task {
            await appEnvironment.syncEngine.resumeSync()
            await appEnvironment.calendarSyncManager.refreshCalendarEvents()
        }

        // Refresh notification badges
        appEnvironment.notificationScheduler.refreshBadgeCount()

        // Check for pending deep links
        router.processPendingDeepLinks()
    }

    private func handleBecameInactive() {
        // Pause non-critical operations
        appEnvironment.syncEngine.pauseSync()
    }

    private func handleEnteredBackground() {
        // Persist state
        appEnvironment.saveState()

        // Schedule background tasks
        appEnvironment.scheduleBackgroundTasks()

        // Update notification schedules
        Task {
            await appEnvironment.notificationScheduler.rescheduleAllNotifications()
        }
    }

    // MARK: - Authentication Handling

    private func handleAuthenticationChange(isAuthenticated: Bool) {
        if isAuthenticated {
            // User just authenticated
            Task {
                await appEnvironment.syncEngine.performInitialSync()
                await appEnvironment.calendarSyncManager.requestCalendarAccess()
                await appEnvironment.notificationScheduler.requestNotificationPermission()
            }

            if hasCompletedOnboarding {
                router.navigate(to: .sidebar)
            }
        } else {
            // User signed out
            appEnvironment.clearUserData()
            router.navigate(to: .onboarding)
        }
    }
}

// MARK: - Root View

struct RootView: View {
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var authProvider: AuthProvider
    @EnvironmentObject private var appEnvironment: AppEnvironment

    @State private var showingSplash = true
    @State private var sidebarSelection: SidebarSelection?

    var body: some View {
        ZStack {
            // Background color for dark mode
            RemindersColors.background
                .ignoresSafeArea()

            if showingSplash {
                SplashView()
                    .transition(.opacity)
            } else {
                mainContent
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: showingSplash)
        .onAppear {
            // Show splash briefly for branding
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                withAnimation {
                    showingSplash = false
                }
            }
        }
    }

    @ViewBuilder
    private var mainContent: some View {
        switch router.currentRoot {
        case .onboarding:
            OnboardingContainerView()
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing),
                    removal: .move(edge: .leading)
                ))

        case .main:
            MainContainerView(sidebarSelection: $sidebarSelection)
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing),
                    removal: .move(edge: .leading)
                ))
        }
    }
}

// MARK: - Splash View

struct SplashView: View {
    @State private var animateIcon = false

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "checklist")
                .font(.system(size: 80, weight: .light))
                .foregroundStyle(RemindersColors.accentBlue)
                .scaleEffect(animateIcon ? 1.0 : 0.8)
                .opacity(animateIcon ? 1.0 : 0.5)

            Text("Tasks")
                .font(.largeTitle)
                .fontWeight(.semibold)
                .foregroundStyle(RemindersColors.textPrimary)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.6)) {
                animateIcon = true
            }
        }
    }
}

// MARK: - Onboarding Container View

struct OnboardingContainerView: View {
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var authProvider: AuthProvider
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    var body: some View {
        NavigationStack(path: $router.onboardingPath) {
            VStack(spacing: 24) {
                Spacer()

                Image(systemName: "checklist")
                    .font(.system(size: 100, weight: .light))
                    .foregroundStyle(RemindersColors.accentBlue)

                Text("Welcome to Tasks")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundStyle(RemindersColors.textPrimary)

                Text("Your intelligent task manager")
                    .font(.title3)
                    .foregroundStyle(RemindersColors.textSecondary)

                Spacer()

                Button(action: {
                    Task {
                        await authProvider.signInWithClerk()
                    }
                }) {
                    HStack {
                        Image(systemName: "arrow.right.circle.fill")
                        Text("Continue with Clerk")
                    }
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(RemindersColors.accentBlue)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding(.horizontal, 32)

                Button("Skip for Now") {
                    hasCompletedOnboarding = true
                    router.navigate(to: .sidebar)
                }
                .foregroundStyle(RemindersColors.textSecondary)
                .padding(.bottom, 32)
            }
            .background(RemindersColors.background)
            .navigationDestination(for: Router.OnboardingDestination.self) { destination in
                onboardingDestinationView(for: destination)
            }
        }
    }

    @ViewBuilder
    private func onboardingDestinationView(for destination: Router.OnboardingDestination) -> some View {
        switch destination {
        case .welcome:
            Text("Welcome").foregroundStyle(RemindersColors.textPrimary)
        case .features:
            Text("Features").foregroundStyle(RemindersColors.textPrimary)
        case .permissions:
            Text("Permissions").foregroundStyle(RemindersColors.textPrimary)
        case .authentication:
            Text("Authentication").foregroundStyle(RemindersColors.textPrimary)
        case .complete:
            Text("Complete").foregroundStyle(RemindersColors.textPrimary)
        }
    }
}

// MARK: - Main Container View

struct MainContainerView: View {
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var appEnvironment: AppEnvironment
    @Binding var sidebarSelection: SidebarSelection?

    @State private var columnVisibility: NavigationSplitViewVisibility = .automatic

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(selection: $sidebarSelection)
                .navigationTitle("Tasks")
        } content: {
            contentView
        } detail: {
            detailView
        }
        .navigationSplitViewStyle(.balanced)
        .sheet(item: $router.presentedSheet) { sheet in
            sheetView(for: sheet)
        }
        .fullScreenCover(item: $router.presentedFullScreenCover) { cover in
            fullScreenCoverView(for: cover)
        }
        .onChange(of: router.sidebarVisible) { _, visible in
            columnVisibility = visible ? .all : .detailOnly
        }
        .onChange(of: sidebarSelection) { _, selection in
            handleSidebarSelection(selection)
        }
    }

    @ViewBuilder
    private var contentView: some View {
        if let selection = sidebarSelection {
            switch selection {
            case .smartList(let type):
                smartListView(for: type)
            case .userList(let list):
                ListDetailView(list: list)
            }
        } else {
            ContentUnavailableView(
                "Select a List",
                systemImage: "list.bullet",
                description: Text("Choose a list from the sidebar to view tasks")
            )
        }
    }

    @ViewBuilder
    private func smartListView(for type: SmartListType) -> some View {
        switch type {
        case .today:
            TodayView()
        case .scheduled:
            ScheduledView()
        case .all:
            AllTasksView()
        case .flagged:
            FlaggedView()
        case .completed:
            CompletedView()
        }
    }

    @ViewBuilder
    private var detailView: some View {
        if let taskId = router.selectedTaskId {
            TaskDetailView(taskId: taskId)
        } else {
            ContentUnavailableView(
                "Select a Task",
                systemImage: "checklist",
                description: Text("Choose a task to view its details")
            )
        }
    }

    private func handleSidebarSelection(_ selection: SidebarSelection?) {
        guard let selection = selection else {
            router.clearListSelection()
            return
        }

        switch selection {
        case .smartList(let type):
            router.selectList(Router.ListDestination(from: type))
        case .userList(let list):
            router.selectList(.custom(list.id))
        }
    }

    @ViewBuilder
    private func sheetView(for sheet: Router.Sheet) -> some View {
        NavigationStack {
            switch sheet {
            case .newTask(let listId):
                NewTaskSheet(listId: listId)
            case .newList:
                NewListSheet()
            case .editTask(let taskId):
                TaskDetailView(taskId: taskId)
            case .editList(let listId):
                EditListSheet(listId: listId)
            case .taskPicker(let onSelect):
                TaskPickerSheet(onSelect: onSelect)
            case .datePicker(let date, let onSelect):
                DatePickerSheet(initialDate: date, onSelect: onSelect)
            case .share(let items):
                ShareSheet(items: items)
            }
        }
        .presentationDetents(sheet.presentationDetents)
        .presentationDragIndicator(.visible)
    }

    @ViewBuilder
    private func fullScreenCoverView(for cover: Router.FullScreenCover) -> some View {
        switch cover {
        case .settings:
            SettingsView()
        case .search:
            SearchView()
        case .calendarIntegration:
            CalendarIntegrationView()
        }
    }
}

// MARK: - Router Extension for ListDestination

extension Router.ListDestination {
    init(from type: SmartListType) {
        switch type {
        case .today: self = .today
        case .scheduled: self = .scheduled
        case .all: self = .all
        case .flagged: self = .flagged
        case .completed: self = .completed
        }
    }
}

// MARK: - Placeholder Sheet Views

struct TaskPickerSheet: View {
    let onSelect: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Text("Task Picker")
            .foregroundStyle(RemindersColors.textPrimary)
            .navigationTitle("Select Task")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
    }
}

struct DatePickerSheet: View {
    let initialDate: Date?
    let onSelect: (Date) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var selectedDate = Date()

    var body: some View {
        VStack {
            DatePicker("Select Date", selection: $selectedDate, displayedComponents: [.date, .hourAndMinute])
                .datePickerStyle(.graphical)
                .padding()

            Button("Select") {
                onSelect(selectedDate)
                dismiss()
            }
            .buttonStyle(.borderedProminent)
        }
        .foregroundStyle(RemindersColors.textPrimary)
        .navigationTitle("Select Date")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
        .onAppear {
            if let date = initialDate {
                selectedDate = date
            }
        }
    }
}

struct ShareSheet: View {
    let items: [Any]

    var body: some View {
        Text("Share Sheet")
            .foregroundStyle(RemindersColors.textPrimary)
    }
}

struct SearchView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    var body: some View {
        NavigationStack {
            VStack {
                TextField("Search tasks...", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .padding()

                Spacer()

                if searchText.isEmpty {
                    ContentUnavailableView(
                        "Search Tasks",
                        systemImage: "magnifyingglass",
                        description: Text("Enter a search term to find tasks")
                    )
                } else {
                    Text("Search results for: \(searchText)")
                        .foregroundStyle(RemindersColors.textSecondary)
                }

                Spacer()
            }
            .background(RemindersColors.background)
            .navigationTitle("Search")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

struct CalendarIntegrationView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Connected Calendars") {
                    Text("No calendars connected")
                        .foregroundStyle(RemindersColors.textSecondary)
                }

                Section("Settings") {
                    Toggle("Sync Tasks to Calendar", isOn: .constant(false))
                    Toggle("Import Calendar Events", isOn: .constant(false))
                }
            }
            .scrollContentBackground(.hidden)
            .background(RemindersColors.background)
            .navigationTitle("Calendar")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Placeholder Views for Views Not Yet Created

struct EditListSheet: View {
    let listId: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Text("Edit List: \(listId)")
            .foregroundStyle(RemindersColors.textPrimary)
            .navigationTitle("Edit List")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
    }
}

struct TaskDetailView: View {
    let taskId: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Task Details")
                    .font(RemindersTypography.headline)
                    .foregroundStyle(RemindersColors.textPrimary)

                Text("Task ID: \(taskId)")
                    .font(RemindersTypography.body)
                    .foregroundStyle(RemindersColors.textSecondary)
            }
            .padding()
        }
        .background(RemindersColors.background)
        .navigationTitle("Task")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
    }
}

struct ListDetailView: View {
    let list: TaskList
    @EnvironmentObject private var router: Router
    @State private var tasks: [TaskItem] = []
    @State private var showingNewTask = false

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            List {
                if tasks.isEmpty {
                    ContentUnavailableView(
                        "No Tasks",
                        systemImage: "checklist",
                        description: Text("Add a task to get started")
                    )
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(tasks) { task in
                        TaskRowPreview(task: task)
                            .listRowBackground(RemindersColors.backgroundSecondary)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(RemindersColors.background)

            // Floating add button
            Button {
                showingNewTask = true
            } label: {
                HStack {
                    Image(systemName: "plus.circle.fill")
                    Text("New Reminder")
                }
                .font(RemindersTypography.bodyBold)
                .foregroundStyle(RemindersColors.accentBlue)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(RemindersColors.backgroundSecondary)
                .clipShape(Capsule())
                .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
            }
            .padding()
        }
        .navigationTitle(list.name)
        .sheet(isPresented: $showingNewTask) {
            NavigationStack {
                NewTaskSheet(listId: list.id)
            }
        }
    }
}

struct TaskRowPreview: View {
    let task: TaskItem

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 22))
                .foregroundStyle(task.isCompleted ? RemindersColors.accentGreen : RemindersColors.textTertiary)

            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .font(RemindersTypography.body)
                    .foregroundStyle(task.isCompleted ? RemindersColors.textTertiary : RemindersColors.textPrimary)
                    .strikethrough(task.isCompleted)

                if let notes = task.notes, !notes.isEmpty {
                    Text(notes)
                        .font(RemindersTypography.footnote)
                        .foregroundStyle(RemindersColors.textSecondary)
                        .lineLimit(1)
                }
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }
}

struct NewTaskSheet: View {
    let listId: String?
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var notes = ""
    @FocusState private var titleFocused: Bool

    var body: some View {
        Form {
            Section {
                TextField("Title", text: $title)
                    .font(RemindersTypography.body)
                    .focused($titleFocused)

                TextField("Notes", text: $notes, axis: .vertical)
                    .font(RemindersTypography.body)
                    .lineLimit(3...6)
            }
            .listRowBackground(RemindersColors.backgroundSecondary)
        }
        .scrollContentBackground(.hidden)
        .background(RemindersColors.background)
        .navigationTitle("New Task")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Add") {
                    // Add task logic
                    dismiss()
                }
                .disabled(title.isEmpty)
            }
        }
        .onAppear {
            titleFocused = true
        }
    }
}

struct NewListSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var selectedColor: ListColor = .blue
    @State private var selectedIcon: ListIcon = .list

    var body: some View {
        Form {
            Section {
                TextField("List Name", text: $name)
                    .font(RemindersTypography.body)
            }
            .listRowBackground(RemindersColors.backgroundSecondary)

            Section("Color") {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 12) {
                    ForEach(ListColor.allCases, id: \.self) { color in
                        Circle()
                            .fill(color.color)
                            .frame(width: 36, height: 36)
                            .overlay {
                                if selectedColor == color {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundColor(.white)
                                }
                            }
                            .onTapGesture {
                                selectedColor = color
                            }
                    }
                }
                .padding(.vertical, 8)
            }
            .listRowBackground(RemindersColors.backgroundSecondary)

            Section("Icon") {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 12) {
                    ForEach(Array(ListIcon.allCases.prefix(24)), id: \.self) { icon in
                        ZStack {
                            Circle()
                                .fill(selectedIcon == icon ? selectedColor.color : RemindersColors.backgroundTertiary)
                                .frame(width: 36, height: 36)

                            Image(systemName: icon.rawValue)
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(selectedIcon == icon ? .white : RemindersColors.textSecondary)
                        }
                        .onTapGesture {
                            selectedIcon = icon
                        }
                    }
                }
                .padding(.vertical, 8)
            }
            .listRowBackground(RemindersColors.backgroundSecondary)
        }
        .scrollContentBackground(.hidden)
        .background(RemindersColors.background)
        .navigationTitle("New List")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Create") {
                    // Create list logic
                    dismiss()
                }
                .disabled(name.isEmpty)
            }
        }
    }
}

// MARK: - Placeholder Smart Views

struct TodayView: View {
    var body: some View {
        List {
            Section("Today") {
                Text("No tasks due today")
                    .foregroundStyle(RemindersColors.textSecondary)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(RemindersColors.background)
        .navigationTitle("Today")
    }
}

struct ScheduledView: View {
    var body: some View {
        List {
            Section("Scheduled") {
                Text("No scheduled tasks")
                    .foregroundStyle(RemindersColors.textSecondary)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(RemindersColors.background)
        .navigationTitle("Scheduled")
    }
}

struct AllTasksView: View {
    var body: some View {
        List {
            Section("All Tasks") {
                Text("No tasks")
                    .foregroundStyle(RemindersColors.textSecondary)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(RemindersColors.background)
        .navigationTitle("All")
    }
}

struct FlaggedView: View {
    var body: some View {
        List {
            Section("Flagged") {
                Text("No flagged tasks")
                    .foregroundStyle(RemindersColors.textSecondary)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(RemindersColors.background)
        .navigationTitle("Flagged")
    }
}

struct CompletedView: View {
    var body: some View {
        List {
            Section("Completed") {
                Text("No completed tasks")
                    .foregroundStyle(RemindersColors.textSecondary)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(RemindersColors.background)
        .navigationTitle("Completed")
    }
}

// MARK: - Settings View Placeholder

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Account") {
                    Label("Profile", systemImage: "person.circle")
                    Label("Sync", systemImage: "arrow.triangle.2.circlepath")
                }
                .listRowBackground(RemindersColors.backgroundSecondary)

                Section("Features") {
                    Label("Red Beacon", systemImage: "bell.badge.fill")
                    Label("Calendar Sync", systemImage: "calendar")
                    Label("AI Suggestions", systemImage: "sparkles")
                }
                .listRowBackground(RemindersColors.backgroundSecondary)

                Section("Preferences") {
                    Label("Appearance", systemImage: "paintbrush")
                    Label("Notifications", systemImage: "bell")
                }
                .listRowBackground(RemindersColors.backgroundSecondary)

                Section("About") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundStyle(RemindersColors.textSecondary)
                    }
                }
                .listRowBackground(RemindersColors.backgroundSecondary)
            }
            .scrollContentBackground(.hidden)
            .background(RemindersColors.background)
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
