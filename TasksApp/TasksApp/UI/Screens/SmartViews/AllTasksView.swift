//
//  AllTasksView.swift
//  TasksApp
//
//  All tasks smart view showing all incomplete tasks across all lists
//

import SwiftUI

// MARK: - All Tasks View Model

@MainActor
final class AllTasksViewModel: ObservableObject {
    // MARK: - Published Properties

    @Published var tasksByList: [TaskList: [Task]] = [:]
    @Published var isLoading: Bool = false
    @Published var showCompletedTasks: Bool = false
    @Published var sortOrder: AllTasksSortOrder = .list
    @Published var searchText: String = ""

    enum AllTasksSortOrder: String, CaseIterable {
        case list = "List"
        case dueDate = "Due Date"
        case priority = "Priority"
        case createdDate = "Created Date"
        case alphabetical = "Alphabetical"
    }

    // Sample data for previews
    init() {
        loadSampleData()
    }

    // MARK: - Computed Properties

    var sortedLists: [TaskList] {
        Array(tasksByList.keys).sorted { $0.sortOrder < $1.sortOrder }
    }

    var filteredLists: [TaskList] {
        if searchText.isEmpty {
            return sortedLists
        }
        return sortedLists.filter { list in
            list.name.localizedCaseInsensitiveContains(searchText) ||
            tasksForList(list).contains { $0.title.localizedCaseInsensitiveContains(searchText) }
        }
    }

    var isEmpty: Bool {
        tasksByList.values.allSatisfy { $0.isEmpty }
    }

    var totalTaskCount: Int {
        tasksByList.values.reduce(0) { $0 + $1.count }
    }

    var allTasks: [Task] {
        tasksByList.values.flatMap { $0 }
    }

    var filteredTasks: [Task] {
        if searchText.isEmpty {
            return allTasks
        }
        return allTasks.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
    }

    // MARK: - Methods

    func tasksForList(_ list: TaskList) -> [Task] {
        let tasks = tasksByList[list] ?? []
        if searchText.isEmpty {
            return tasks
        }
        return tasks.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
    }

    func taskCount(for list: TaskList) -> Int {
        tasksForList(list).count
    }

    func toggleTaskCompletion(_ task: Task) {
        for list in sortedLists {
            if var tasks = tasksByList[list],
               let index = tasks.firstIndex(where: { $0.id == task.id }) {
                tasks[index].toggleCompletion()
                tasksByList[list] = tasks
                return
            }
        }
    }

    func toggleTaskFlag(_ task: Task) {
        for list in sortedLists {
            if var tasks = tasksByList[list],
               let index = tasks.firstIndex(where: { $0.id == task.id }) {
                tasks[index].toggleFlag()
                tasksByList[list] = tasks
                return
            }
        }
    }

    func deleteTask(_ task: Task) {
        for list in sortedLists {
            tasksByList[list]?.removeAll { $0.id == task.id }
        }
    }

    func refresh() async {
        isLoading = true
        try? await Foundation.Task.sleep(nanoseconds: 500_000_000)
        loadSampleData()
        isLoading = false
    }

    // MARK: - Private Methods

    private func loadSampleData() {
        let calendar = Calendar.current
        let now = Date()
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: now)!
        let nextWeek = calendar.date(byAdding: .weekOfYear, value: 1, to: now)!

        let lists = TaskList.sampleLists

        tasksByList = [:]

        // Inbox tasks
        if let inbox = lists.first(where: { $0.id == "inbox" }) {
            tasksByList[inbox] = [
                Task(
                    title: "Sort through emails",
                    dueDate: now,
                    listId: inbox.id
                ),
                Task(
                    title: "Review meeting notes",
                    notes: "From yesterday's sync",
                    listId: inbox.id
                ),
                Task(
                    title: "Quick errand",
                    flag: true,
                    listId: inbox.id
                )
            ]
        }

        // Work tasks
        if let work = lists.first(where: { $0.id == "work" }) {
            tasksByList[work] = [
                Task(
                    title: "Complete quarterly report",
                    notes: "Include sales figures and projections",
                    dueDate: tomorrow,
                    priority: .high,
                    flag: true,
                    redBeaconEnabled: true,
                    listId: work.id
                ),
                Task(
                    title: "Review pull requests",
                    dueDate: now,
                    priority: .medium,
                    listId: work.id
                ),
                Task(
                    title: "Update documentation",
                    dueDate: nextWeek,
                    listId: work.id
                ),
                Task(
                    title: "Prepare presentation",
                    notes: "For Friday's client meeting",
                    dueDate: calendar.date(byAdding: .day, value: 3, to: now)!,
                    priority: .high,
                    listId: work.id
                )
            ]
        }

        // Personal tasks
        if let personal = lists.first(where: { $0.id == "personal" }) {
            tasksByList[personal] = [
                Task(
                    title: "Call mom",
                    dueDate: now,
                    listId: personal.id
                ),
                Task(
                    title: "Read book chapter",
                    notes: "Chapter 12 - Design Patterns",
                    flag: true,
                    listId: personal.id
                ),
                Task(
                    title: "Plan weekend trip",
                    dueDate: nextWeek,
                    listId: personal.id
                )
            ]
        }

        // Shopping tasks
        if let shopping = lists.first(where: { $0.id == "shopping" }) {
            tasksByList[shopping] = [
                Task(
                    title: "Groceries",
                    notes: "Milk, eggs, bread, cheese",
                    dueDate: now,
                    listId: shopping.id
                ),
                Task(
                    title: "Buy birthday gift",
                    dueDate: calendar.date(byAdding: .day, value: 5, to: now)!,
                    flag: true,
                    listId: shopping.id
                )
            ]
        }

        // Health tasks
        if let health = lists.first(where: { $0.id == "health" }) {
            tasksByList[health] = [
                Task(
                    title: "Morning workout",
                    dueDate: now,
                    dueTime: calendar.date(bySettingHour: 7, minute: 0, second: 0, of: now),
                    listId: health.id
                ),
                Task(
                    title: "Take vitamins",
                    repeatRule: .daily(),
                    listId: health.id
                ),
                Task(
                    title: "Schedule annual checkup",
                    dueDate: nextWeek,
                    listId: health.id
                )
            ]
        }
    }
}

// MARK: - All Tasks View

struct AllTasksView: View {
    @StateObject private var viewModel = AllTasksViewModel()
    @State private var selectedTask: Task?
    @State private var showingNewTask: Bool = false
    @State private var expandedLists: Set<String> = []

    var body: some View {
        Group {
            if viewModel.isEmpty {
                emptyState
            } else {
                taskList
            }
        }
        .background(RemindersColors.background)
        .navigationTitle("All")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                addButton
            }

            ToolbarItem(placement: .navigationBarTrailing) {
                menuButton
            }
        }
        .searchable(text: $viewModel.searchText, prompt: "Search reminders")
        .refreshable {
            await viewModel.refresh()
        }
        .onAppear {
            // Expand all lists by default
            expandedLists = Set(viewModel.sortedLists.map { $0.id })
        }
    }

    // MARK: - Task List

    private var taskList: some View {
        List {
            // Summary header
            summarySection

            // Tasks grouped by list
            ForEach(viewModel.filteredLists) { list in
                listSection(for: list)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(RemindersColors.background)
    }

    // MARK: - Summary Section

    private var summarySection: some View {
        Section {
            HStack(spacing: RemindersKit.Spacing.xl) {
                VStack(alignment: .leading, spacing: RemindersKit.Spacing.xxs) {
                    Text("\(viewModel.totalTaskCount)")
                        .font(RemindersTypography.roundedLarge)
                        .foregroundColor(RemindersColors.textPrimary)

                    Text("Reminders")
                        .font(RemindersTypography.caption1)
                        .foregroundColor(RemindersColors.textSecondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: RemindersKit.Spacing.xxs) {
                    Text("\(viewModel.filteredLists.count)")
                        .font(RemindersTypography.roundedLarge)
                        .foregroundColor(RemindersColors.textPrimary)

                    Text("Lists")
                        .font(RemindersTypography.caption1)
                        .foregroundColor(RemindersColors.textSecondary)
                }
            }
            .padding(.vertical, RemindersKit.Spacing.sm)
        }
        .listRowBackground(RemindersColors.backgroundSecondary)
    }

    // MARK: - List Section

    private func listSection(for list: TaskList) -> some View {
        Section {
            if expandedLists.contains(list.id) {
                ForEach(viewModel.tasksForList(list)) { task in
                    AllTasksTaskRow(
                        task: task,
                        listColor: list.color.color,
                        onToggleComplete: { viewModel.toggleTaskCompletion(task) },
                        onToggleFlag: { viewModel.toggleTaskFlag(task) },
                        onDelete: { viewModel.deleteTask(task) },
                        onTap: { selectedTask = task }
                    )
                }
            }
        } header: {
            Button {
                withAnimation(RemindersKit.Animation.standard) {
                    if expandedLists.contains(list.id) {
                        expandedLists.remove(list.id)
                    } else {
                        expandedLists.insert(list.id)
                    }
                }
            } label: {
                HStack(spacing: RemindersKit.Spacing.sm) {
                    // List Icon
                    ZStack {
                        Circle()
                            .fill(list.color.color)
                            .frame(width: 24, height: 24)

                        Image(systemName: list.icon.rawValue)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.white)
                    }

                    Text(list.name)
                        .font(RemindersTypography.footnoteBold)
                        .foregroundColor(RemindersColors.textPrimary)

                    Spacer()

                    Text("\(viewModel.taskCount(for: list))")
                        .font(RemindersTypography.footnote)
                        .foregroundColor(RemindersColors.textSecondary)

                    Image(systemName: expandedLists.contains(list.id) ? "chevron.down" : "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(RemindersColors.textTertiary)
                }
                .textCase(nil)
            }
            .buttonStyle(.plain)
        }
        .listRowBackground(RemindersColors.backgroundSecondary)
        .listRowSeparatorTint(RemindersColors.separator)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: RemindersKit.Spacing.xl) {
            Spacer()

            Image(systemName: "tray.fill")
                .font(.system(size: 64, weight: .light))
                .foregroundColor(RemindersColors.textTertiary.opacity(0.5))

            VStack(spacing: RemindersKit.Spacing.sm) {
                Text("No Reminders")
                    .font(RemindersTypography.title3)
                    .foregroundColor(RemindersColors.textPrimary)

                Text("Reminders you add will appear here.")
                    .font(RemindersTypography.body)
                    .foregroundColor(RemindersColors.textSecondary)
                    .multilineTextAlignment(.center)
            }

            Button {
                showingNewTask = true
            } label: {
                HStack(spacing: RemindersKit.Spacing.sm) {
                    Image(systemName: "plus.circle.fill")
                    Text("New Reminder")
                }
                .font(RemindersTypography.bodyBold)
                .foregroundColor(RemindersColors.accentBlue)
            }
            .padding(.top, RemindersKit.Spacing.md)

            Spacer()
        }
        .padding()
    }

    // MARK: - Toolbar Items

    private var addButton: some View {
        Button {
            showingNewTask = true
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 17, weight: .medium))
                .foregroundColor(RemindersColors.accentBlue)
        }
    }

    private var menuButton: some View {
        Menu {
            Toggle("Show Completed", isOn: $viewModel.showCompletedTasks)

            Divider()

            Picker("Sort By", selection: $viewModel.sortOrder) {
                ForEach(AllTasksViewModel.AllTasksSortOrder.allCases, id: \.self) { order in
                    Text(order.rawValue).tag(order)
                }
            }

            Divider()

            Button {
                withAnimation {
                    expandedLists = Set(viewModel.sortedLists.map { $0.id })
                }
            } label: {
                Label("Expand All", systemImage: "arrow.up.left.and.arrow.down.right")
            }

            Button {
                withAnimation {
                    expandedLists.removeAll()
                }
            } label: {
                Label("Collapse All", systemImage: "arrow.down.right.and.arrow.up.left")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 17, weight: .medium))
                .foregroundColor(RemindersColors.accentBlue)
        }
    }
}

// MARK: - All Tasks Task Row

struct AllTasksTaskRow: View {
    let task: Task
    let listColor: Color
    let onToggleComplete: () -> Void
    let onToggleFlag: () -> Void
    let onDelete: () -> Void
    let onTap: () -> Void

    @State private var isChecked: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: RemindersKit.Spacing.md) {
            // Checkbox
            checkboxButton

            // Task Content
            VStack(alignment: .leading, spacing: RemindersKit.Spacing.xxs) {
                // Title
                Text(task.title)
                    .font(RemindersTypography.body)
                    .foregroundColor(task.isCompleted ? RemindersColors.textTertiary : RemindersColors.textPrimary)
                    .strikethrough(task.isCompleted, color: RemindersColors.textTertiary)
                    .lineLimit(2)

                // Notes preview
                if let notes = task.notes, !notes.isEmpty {
                    Text(notes)
                        .font(RemindersTypography.subheadline)
                        .foregroundColor(RemindersColors.textSecondary)
                        .lineLimit(1)
                }

                // Metadata row
                if hasMetadata {
                    metadataRow
                }
            }

            Spacer()

            // Flag indicator
            if task.flag {
                Image(systemName: "flag.fill")
                    .font(.system(size: 12))
                    .foregroundColor(RemindersColors.accentOrange)
            }
        }
        .padding(.vertical, RemindersKit.Spacing.xs)
        .contentShape(Rectangle())
        .onTapGesture {
            onTap()
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .swipeActions(edge: .trailing) {
            Button {
                onToggleFlag()
            } label: {
                Label(task.flag ? "Unflag" : "Flag", systemImage: task.flag ? "flag.slash" : "flag.fill")
            }
            .tint(RemindersColors.accentOrange)
        }
        .swipeActions(edge: .leading) {
            Button {
                onToggleComplete()
            } label: {
                Label("Complete", systemImage: "checkmark.circle.fill")
            }
            .tint(RemindersColors.accentGreen)
        }
    }

    // MARK: - Checkbox

    private var checkboxButton: some View {
        Button {
            withAnimation(RemindersKit.Animation.completion) {
                isChecked = true
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                onToggleComplete()
            }
        } label: {
            ZStack {
                Circle()
                    .stroke(checkboxBorderColor, lineWidth: 2)
                    .frame(width: RemindersKit.Size.checkbox, height: RemindersKit.Size.checkbox)

                if isChecked || task.isCompleted {
                    Circle()
                        .fill(listColor)
                        .frame(width: RemindersKit.Size.checkbox, height: RemindersKit.Size.checkbox)

                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var checkboxBorderColor: Color {
        if task.isOverdue {
            return RemindersColors.accentRed
        } else if task.priority == .high {
            return RemindersColors.priorityHigh
        } else if task.priority == .medium {
            return RemindersColors.priorityMedium
        }
        return listColor.opacity(0.6)
    }

    // MARK: - Metadata

    private var hasMetadata: Bool {
        task.dueDate != nil || task.priority != .none || task.redBeaconEnabled
    }

    private var metadataRow: some View {
        HStack(spacing: RemindersKit.Spacing.sm) {
            // Due date
            if let dueDate = task.dueDate {
                HStack(spacing: RemindersKit.Spacing.xxs) {
                    Image(systemName: "calendar")
                        .font(.system(size: 11))
                    Text(formatDate(dueDate))
                        .font(RemindersTypography.caption1)
                }
                .foregroundColor(task.isOverdue ? RemindersColors.accentRed : RemindersColors.textSecondary)
            }

            // Time
            if let dueTime = task.dueTime {
                HStack(spacing: RemindersKit.Spacing.xxs) {
                    Image(systemName: "clock")
                        .font(.system(size: 11))
                    Text(formatTime(dueTime))
                        .font(RemindersTypography.caption1)
                }
                .foregroundColor(task.isOverdue ? RemindersColors.accentRed : RemindersColors.textSecondary)
            }

            // Priority
            if task.priority != .none {
                HStack(spacing: 2) {
                    ForEach(0..<task.priority.rawValue, id: \.self) { _ in
                        Image(systemName: "exclamationmark")
                            .font(.system(size: 10, weight: .bold))
                    }
                }
                .foregroundColor(priorityColor)
            }

            // Red beacon
            if task.redBeaconEnabled {
                Circle()
                    .fill(RemindersColors.accentRed)
                    .frame(width: 8, height: 8)
            }
        }
    }

    private var priorityColor: Color {
        switch task.priority {
        case .high: return RemindersColors.priorityHigh
        case .medium: return RemindersColors.priorityMedium
        case .low: return RemindersColors.priorityLow
        case .none: return RemindersColors.textTertiary
        }
    }

    private func formatDate(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "Today"
        } else if calendar.isDateInTomorrow(date) {
            return "Tomorrow"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d"
            return formatter.string(from: date)
        }
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Preview

#Preview("All Tasks View") {
    NavigationStack {
        AllTasksView()
    }
    .preferredColorScheme(.dark)
}

#Preview("All Tasks Task Row") {
    List {
        AllTasksTaskRow(
            task: Task(
                title: "Complete important project",
                notes: "Don't forget the documentation",
                dueDate: Date(),
                priority: .high,
                flag: true,
                redBeaconEnabled: true,
                listId: "work"
            ),
            listColor: ListColor.blue.color,
            onToggleComplete: { },
            onToggleFlag: { },
            onDelete: { },
            onTap: { }
        )

        AllTasksTaskRow(
            task: Task(
                title: "Simple task",
                listId: "personal"
            ),
            listColor: ListColor.orange.color,
            onToggleComplete: { },
            onToggleFlag: { },
            onDelete: { },
            onTap: { }
        )
    }
    .listStyle(.insetGrouped)
    .scrollContentBackground(.hidden)
    .background(RemindersColors.background)
    .preferredColorScheme(.dark)
}
