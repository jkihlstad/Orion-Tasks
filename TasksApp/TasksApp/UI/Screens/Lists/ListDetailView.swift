//
//  ListDetailView.swift
//  TasksApp
//
//  Detail view for a task list showing all tasks, matching Apple Reminders style
//

import SwiftUI

// MARK: - List Detail View

struct ListDetailView: View {
    // The list being displayed
    let list: TaskList

    // Tasks data
    let tasks: [Task]
    let completedTasks: [Task]

    // UI State
    @State private var showCompletedSection: Bool = false
    @State private var showEditSheet: Bool = false
    @State private var showNewTaskSheet: Bool = false
    @State private var isRefreshing: Bool = false

    // Callbacks
    let onTaskToggle: (Task) -> Void
    let onTaskTap: (Task) -> Void
    let onTaskDelete: (Task) -> Void
    let onAddTask: () -> Void
    let onEditList: () -> Void
    let onDeleteList: () -> Void
    let onRefresh: () async -> Void

    init(
        list: TaskList,
        tasks: [Task] = [],
        completedTasks: [Task] = [],
        onTaskToggle: @escaping (Task) -> Void = { _ in },
        onTaskTap: @escaping (Task) -> Void = { _ in },
        onTaskDelete: @escaping (Task) -> Void = { _ in },
        onAddTask: @escaping () -> Void = {},
        onEditList: @escaping () -> Void = {},
        onDeleteList: @escaping () -> Void = {},
        onRefresh: @escaping () async -> Void = {}
    ) {
        self.list = list
        self.tasks = tasks
        self.completedTasks = completedTasks
        self.onTaskToggle = onTaskToggle
        self.onTaskTap = onTaskTap
        self.onTaskDelete = onTaskDelete
        self.onAddTask = onAddTask
        self.onEditList = onEditList
        self.onDeleteList = onDeleteList
        self.onRefresh = onRefresh
    }

    // MARK: - Computed Properties

    private var isEmpty: Bool {
        tasks.isEmpty && completedTasks.isEmpty
    }

    private var totalCount: Int {
        tasks.count + completedTasks.count
    }

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .bottom) {
            // Main content
            Group {
                if isEmpty {
                    emptyStateView
                } else {
                    taskListView
                }
            }

            // Floating add button
            if !isEmpty {
                floatingAddButton
            }
        }
        .background(RemindersColors.backgroundGrouped)
        .navigationTitle(list.name)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button(action: onEditList) {
                        Label("Edit List", systemImage: "pencil")
                    }

                    if !list.isInbox {
                        Button(role: .destructive, action: onDeleteList) {
                            Label("Delete List", systemImage: "trash")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 20))
                        .foregroundColor(list.color.color)
                }
            }
        }
        .toolbarBackground(RemindersColors.backgroundGrouped, for: .navigationBar)
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 0) {
            // List header
            listHeader
                .padding(.top, RemindersKit.Spacing.lg)

            Spacer()

            // Empty state
            EmptyStateView(
                icon: "checklist",
                title: "No Reminders",
                message: "Reminders you add to this list will appear here.",
                iconColor: list.color.color.opacity(0.6),
                action: EmptyStateAction(
                    title: "New Reminder",
                    icon: "plus",
                    isPrimary: true,
                    action: onAddTask
                )
            )

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Task List View

    private var taskListView: some View {
        List {
            // List header section
            Section {
                listHeader
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())

            // Active tasks section
            if !tasks.isEmpty {
                Section {
                    ForEach(tasks) { task in
                        TaskRowView(
                            task: task,
                            accentColor: list.color.color,
                            onToggle: { onTaskToggle(task) },
                            onTap: { onTaskTap(task) }
                        )
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                onTaskDelete(task)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                } header: {
                    if !completedTasks.isEmpty {
                        Text("\(tasks.count) Remaining")
                            .font(RemindersTypography.footnote)
                            .foregroundColor(RemindersColors.textSecondary)
                            .textCase(.uppercase)
                    }
                }
                .listRowBackground(RemindersColors.backgroundSecondary)
                .listRowSeparatorTint(RemindersColors.separator)
            }

            // Completed tasks section
            if !completedTasks.isEmpty {
                Section {
                    if showCompletedSection {
                        ForEach(completedTasks) { task in
                            TaskRowView(
                                task: task,
                                accentColor: list.color.color,
                                onToggle: { onTaskToggle(task) },
                                onTap: { onTaskTap(task) }
                            )
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    onTaskDelete(task)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                } header: {
                    Button(action: { withAnimation { showCompletedSection.toggle() } }) {
                        HStack {
                            Text("Completed (\(completedTasks.count))")
                                .font(RemindersTypography.footnote)
                                .foregroundColor(RemindersColors.textSecondary)
                                .textCase(.uppercase)

                            Spacer()

                            Image(systemName: showCompletedSection ? "chevron.down" : "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(RemindersColors.textSecondary)
                        }
                    }
                }
                .listRowBackground(RemindersColors.backgroundSecondary)
                .listRowSeparatorTint(RemindersColors.separator)
            }

            // Bottom padding for floating button
            Section {
                Spacer()
                    .frame(height: 80)
            }
            .listRowBackground(Color.clear)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .refreshable {
            await onRefresh()
        }
    }

    // MARK: - List Header

    private var listHeader: some View {
        HStack(spacing: RemindersKit.Spacing.md) {
            // List icon
            ZStack {
                Circle()
                    .fill(list.color.color)
                    .frame(width: 44, height: 44)

                Image(systemName: list.icon.rawValue)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(list.name)
                    .font(RemindersTypography.headline)
                    .foregroundColor(RemindersColors.textPrimary)

                Text("\(totalCount) reminder\(totalCount == 1 ? "" : "s")")
                    .font(RemindersTypography.caption1)
                    .foregroundColor(RemindersColors.textSecondary)
            }

            Spacer()
        }
        .padding(.horizontal, RemindersKit.Spacing.lg)
        .padding(.vertical, RemindersKit.Spacing.md)
    }

    // MARK: - Floating Add Button

    private var floatingAddButton: some View {
        HStack {
            Button(action: onAddTask) {
                HStack(spacing: RemindersKit.Spacing.sm) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 24))

                    Text("New Reminder")
                        .font(RemindersTypography.bodyBold)
                }
                .foregroundColor(list.color.color)
            }
            .padding(.horizontal, RemindersKit.Spacing.lg)
            .padding(.vertical, RemindersKit.Spacing.md)
            .background(RemindersColors.backgroundSecondary)
            .clipShape(Capsule())
            .shadow(color: Color.black.opacity(0.2), radius: 8, x: 0, y: 4)

            Spacer()
        }
        .padding(.horizontal, RemindersKit.Spacing.lg)
        .padding(.bottom, RemindersKit.Spacing.lg)
    }
}

// MARK: - Task Row View

struct TaskRowView: View {
    let task: Task
    let accentColor: Color
    let onToggle: () -> Void
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: RemindersKit.Spacing.checkboxContent) {
                // Checkbox
                Button(action: onToggle) {
                    taskCheckbox
                }
                .buttonStyle(.plain)

                // Task content
                VStack(alignment: .leading, spacing: 4) {
                    // Title
                    Text(task.title)
                        .font(RemindersTypography.taskTitle)
                        .foregroundColor(
                            task.isCompleted
                            ? RemindersColors.textSecondary
                            : RemindersColors.textPrimary
                        )
                        .strikethrough(task.isCompleted, color: RemindersColors.textSecondary)
                        .lineLimit(2)

                    // Notes
                    if let notes = task.notes, !notes.isEmpty {
                        Text(notes)
                            .font(RemindersTypography.taskSubtitle)
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

                // Disclosure indicator
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(RemindersColors.textTertiary)
            }
            .padding(.vertical, RemindersKit.Spacing.sm)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Checkbox

    private var taskCheckbox: some View {
        ZStack {
            Circle()
                .stroke(
                    task.isCompleted ? accentColor : RemindersColors.checkboxBorder,
                    lineWidth: 2
                )
                .frame(width: RemindersKit.Size.checkbox, height: RemindersKit.Size.checkbox)

            if task.isCompleted {
                Circle()
                    .fill(accentColor)
                    .frame(width: RemindersKit.Size.checkbox - 4, height: RemindersKit.Size.checkbox - 4)

                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white)
            }
        }
        .animation(RemindersKit.Animation.completion, value: task.isCompleted)
    }

    // MARK: - Metadata

    private var hasMetadata: Bool {
        task.dueDate != nil || task.priority != .none || task.redBeaconEnabled
    }

    private var metadataRow: some View {
        HStack(spacing: RemindersKit.Spacing.sm) {
            // Red beacon
            if task.redBeaconEnabled {
                Circle()
                    .fill(RemindersColors.accentRed)
                    .frame(width: 8, height: 8)
            }

            // Priority
            if task.priority != .none {
                Image(systemName: task.priority.symbolName)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(priorityColor)
            }

            // Due date
            if let dueDate = task.dueDate {
                HStack(spacing: 4) {
                    Image(systemName: task.hasTimeReminder ? "clock" : "calendar")
                        .font(.system(size: 10))

                    Text(formatDueDate(dueDate))
                        .font(RemindersTypography.taskMetadata)
                }
                .foregroundColor(dueDateColor)
            }

            Spacer()
        }
    }

    private var priorityColor: Color {
        switch task.priority {
        case .high: return RemindersColors.priorityHigh
        case .medium: return RemindersColors.priorityMedium
        case .low: return RemindersColors.priorityLow
        case .none: return RemindersColors.textSecondary
        }
    }

    private var dueDateColor: Color {
        guard let dueDate = task.dueDate else { return RemindersColors.textSecondary }

        if task.isOverdue {
            return RemindersColors.overdue
        } else if Calendar.current.isDateInToday(dueDate) {
            return RemindersColors.today
        } else {
            return RemindersColors.scheduled
        }
    }

    private func formatDueDate(_ date: Date) -> String {
        let calendar = Calendar.current

        if calendar.isDateInToday(date) {
            if let dueTime = task.dueTime {
                let formatter = DateFormatter()
                formatter.timeStyle = .short
                return "Today, \(formatter.string(from: dueTime))"
            }
            return "Today"
        } else if calendar.isDateInTomorrow(date) {
            return "Tomorrow"
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .none
            return formatter.string(from: date)
        }
    }
}

// MARK: - Preview

#Preview("List with Tasks") {
    NavigationStack {
        ListDetailView(
            list: TaskList(
                id: "work",
                name: "Work Projects",
                color: .blue,
                icon: .briefcase
            ),
            tasks: [
                Task(
                    id: "1",
                    title: "Review project proposal",
                    notes: "Check the budget section",
                    dueDate: Date(),
                    priority: .high,
                    flag: true,
                    listId: "work"
                ),
                Task(
                    id: "2",
                    title: "Send meeting notes to team",
                    dueDate: Date().addingTimeInterval(86400),
                    listId: "work"
                ),
                Task(
                    id: "3",
                    title: "Prepare presentation slides",
                    notes: "Include Q3 metrics",
                    redBeaconEnabled: true,
                    listId: "work"
                ),
                Task(
                    id: "4",
                    title: "Update documentation",
                    priority: .medium,
                    listId: "work"
                )
            ],
            completedTasks: [
                Task(
                    id: "5",
                    title: "Complete weekly report",
                    completedAt: Date(),
                    listId: "work"
                ),
                Task(
                    id: "6",
                    title: "Submit expense claims",
                    completedAt: Date().addingTimeInterval(-86400),
                    listId: "work"
                )
            ]
        )
    }
}

#Preview("Empty List") {
    NavigationStack {
        ListDetailView(
            list: TaskList(
                id: "personal",
                name: "Personal",
                color: .orange,
                icon: .person
            ),
            tasks: [],
            completedTasks: []
        )
    }
}

#Preview("Shopping List") {
    NavigationStack {
        ListDetailView(
            list: TaskList(
                id: "shopping",
                name: "Shopping",
                color: .green,
                icon: .cart
            ),
            tasks: [
                Task(id: "1", title: "Milk", listId: "shopping"),
                Task(id: "2", title: "Bread", listId: "shopping"),
                Task(id: "3", title: "Eggs", listId: "shopping"),
                Task(id: "4", title: "Butter", listId: "shopping"),
                Task(id: "5", title: "Cheese", listId: "shopping")
            ],
            completedTasks: []
        )
    }
}

#Preview("Inbox") {
    NavigationStack {
        ListDetailView(
            list: TaskList.inbox,
            tasks: [
                Task(
                    id: "1",
                    title: "Quick task from Siri",
                    dueDate: Date(),
                    listId: "inbox"
                )
            ],
            completedTasks: []
        )
    }
}
