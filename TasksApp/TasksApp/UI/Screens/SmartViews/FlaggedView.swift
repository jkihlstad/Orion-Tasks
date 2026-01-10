//
//  FlaggedView.swift
//  TasksApp
//
//  Flagged smart view showing all flagged tasks
//

import SwiftUI

// MARK: - Flagged View Model

@MainActor
final class FlaggedViewModel: ObservableObject {
    // MARK: - Published Properties

    @Published var flaggedTasks: [Task] = []
    @Published var tasksByList: [TaskList: [Task]] = [:]
    @Published var isLoading: Bool = false
    @Published var showCompletedTasks: Bool = false
    @Published var sortOrder: FlaggedSortOrder = .list
    @Published var groupByList: Bool = true

    enum FlaggedSortOrder: String, CaseIterable {
        case list = "List"
        case dueDate = "Due Date"
        case priority = "Priority"
        case dateAdded = "Date Added"
    }

    // Sample data for previews
    init() {
        loadSampleData()
    }

    // MARK: - Computed Properties

    var sortedLists: [TaskList] {
        Array(tasksByList.keys).sorted { $0.sortOrder < $1.sortOrder }
    }

    var isEmpty: Bool {
        flaggedTasks.isEmpty
    }

    var totalTaskCount: Int {
        flaggedTasks.count
    }

    var sortedTasks: [Task] {
        switch sortOrder {
        case .list:
            return flaggedTasks.sorted { $0.listId < $1.listId }
        case .dueDate:
            return flaggedTasks.sorted { task1, task2 in
                guard let date1 = task1.dueDate else { return false }
                guard let date2 = task2.dueDate else { return true }
                return date1 < date2
            }
        case .priority:
            return flaggedTasks.sorted { $0.priority.rawValue > $1.priority.rawValue }
        case .dateAdded:
            return flaggedTasks.sorted { $0.createdAt > $1.createdAt }
        }
    }

    // MARK: - Methods

    func tasksForList(_ list: TaskList) -> [Task] {
        tasksByList[list] ?? []
    }

    func taskCount(for list: TaskList) -> Int {
        tasksForList(list).count
    }

    func toggleTaskCompletion(_ task: Task) {
        if let index = flaggedTasks.firstIndex(where: { $0.id == task.id }) {
            flaggedTasks[index].toggleCompletion()
        }
        updateTasksByList()
    }

    func unflagTask(_ task: Task) {
        flaggedTasks.removeAll { $0.id == task.id }
        updateTasksByList()
    }

    func deleteTask(_ task: Task) {
        flaggedTasks.removeAll { $0.id == task.id }
        updateTasksByList()
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
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now)!

        flaggedTasks = [
            Task(
                title: "Submit quarterly report",
                notes: "Q4 financial summary - URGENT",
                dueDate: yesterday,
                priority: .high,
                flag: true,
                redBeaconEnabled: true,
                listId: "work"
            ),
            Task(
                title: "Prepare presentation",
                notes: "For Friday's client meeting",
                dueDate: calendar.date(byAdding: .day, value: 3, to: now)!,
                priority: .high,
                flag: true,
                listId: "work"
            ),
            Task(
                title: "Read book chapter",
                notes: "Chapter 12 - Design Patterns",
                flag: true,
                listId: "personal"
            ),
            Task(
                title: "Buy birthday gift",
                dueDate: calendar.date(byAdding: .day, value: 5, to: now)!,
                flag: true,
                listId: "shopping"
            ),
            Task(
                title: "Quick errand",
                flag: true,
                listId: "inbox"
            ),
            Task(
                title: "Plan vacation",
                dueDate: nextWeek,
                flag: true,
                listId: "personal"
            ),
            Task(
                title: "Finish book chapter",
                dueDate: tomorrow,
                flag: true,
                listId: "personal"
            )
        ]

        updateTasksByList()
    }

    private func updateTasksByList() {
        let lists = TaskList.sampleLists
        tasksByList = Dictionary(grouping: flaggedTasks) { task in
            lists.first { $0.id == task.listId } ?? TaskList.inbox
        }
    }
}

// MARK: - Flagged View

struct FlaggedView: View {
    @StateObject private var viewModel = FlaggedViewModel()
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
        .navigationTitle("Flagged")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                addButton
            }

            ToolbarItem(placement: .navigationBarTrailing) {
                menuButton
            }
        }
        .refreshable {
            await viewModel.refresh()
        }
        .onAppear {
            expandedLists = Set(viewModel.sortedLists.map { $0.id })
        }
    }

    // MARK: - Task List

    private var taskList: some View {
        List {
            // Summary header
            summarySection

            if viewModel.groupByList {
                // Grouped by list
                ForEach(viewModel.sortedLists) { list in
                    listSection(for: list)
                }
            } else {
                // Flat list
                flatListSection
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(RemindersColors.background)
    }

    // MARK: - Summary Section

    private var summarySection: some View {
        Section {
            HStack(spacing: RemindersKit.Spacing.md) {
                // Flag icon
                Image(systemName: "flag.fill")
                    .font(.system(size: 32, weight: .medium))
                    .foregroundColor(RemindersColors.accentOrange)

                VStack(alignment: .leading, spacing: RemindersKit.Spacing.xxs) {
                    Text("\(viewModel.totalTaskCount)")
                        .font(RemindersTypography.roundedLarge)
                        .foregroundColor(RemindersColors.textPrimary)

                    Text("Flagged Reminders")
                        .font(RemindersTypography.caption1)
                        .foregroundColor(RemindersColors.textSecondary)
                }

                Spacer()
            }
            .padding(.vertical, RemindersKit.Spacing.sm)
        }
        .listRowBackground(RemindersColors.backgroundSecondary)
    }

    // MARK: - List Section (Grouped View)

    private func listSection(for list: TaskList) -> some View {
        Section {
            if expandedLists.contains(list.id) {
                ForEach(viewModel.tasksForList(list)) { task in
                    FlaggedTaskRow(
                        task: task,
                        listColor: list.color.color,
                        onToggleComplete: { viewModel.toggleTaskCompletion(task) },
                        onUnflag: { viewModel.unflagTask(task) },
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

    // MARK: - Flat List Section

    private var flatListSection: some View {
        Section {
            ForEach(viewModel.sortedTasks) { task in
                let list = TaskList.sampleLists.first { $0.id == task.listId } ?? TaskList.inbox
                FlaggedTaskRow(
                    task: task,
                    listColor: list.color.color,
                    showListName: true,
                    listName: list.name,
                    onToggleComplete: { viewModel.toggleTaskCompletion(task) },
                    onUnflag: { viewModel.unflagTask(task) },
                    onDelete: { viewModel.deleteTask(task) },
                    onTap: { selectedTask = task }
                )
            }
        }
        .listRowBackground(RemindersColors.backgroundSecondary)
        .listRowSeparatorTint(RemindersColors.separator)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: RemindersKit.Spacing.xl) {
            Spacer()

            Image(systemName: "flag.fill")
                .font(.system(size: 64, weight: .light))
                .foregroundColor(RemindersColors.accentOrange.opacity(0.5))

            VStack(spacing: RemindersKit.Spacing.sm) {
                Text("No Flagged Reminders")
                    .font(RemindersTypography.title3)
                    .foregroundColor(RemindersColors.textPrimary)

                Text("Flagged reminders will appear here for quick access.")
                    .font(RemindersTypography.body)
                    .foregroundColor(RemindersColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, RemindersKit.Spacing.xl)
            }

            VStack(spacing: RemindersKit.Spacing.md) {
                HStack(spacing: RemindersKit.Spacing.sm) {
                    Image(systemName: "hand.tap")
                        .foregroundColor(RemindersColors.textTertiary)
                    Text("Swipe right on any reminder to flag it")
                        .font(RemindersTypography.subheadline)
                        .foregroundColor(RemindersColors.textSecondary)
                }
            }
            .padding(.top, RemindersKit.Spacing.lg)

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

            Toggle("Group by List", isOn: $viewModel.groupByList)

            Divider()

            Picker("Sort By", selection: $viewModel.sortOrder) {
                ForEach(FlaggedViewModel.FlaggedSortOrder.allCases, id: \.self) { order in
                    Text(order.rawValue).tag(order)
                }
            }

            if viewModel.groupByList {
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
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 17, weight: .medium))
                .foregroundColor(RemindersColors.accentBlue)
        }
    }
}

// MARK: - Flagged Task Row

struct FlaggedTaskRow: View {
    let task: Task
    let listColor: Color
    var showListName: Bool = false
    var listName: String = ""
    let onToggleComplete: () -> Void
    let onUnflag: () -> Void
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
                metadataRow
            }

            Spacer()

            // Flag indicator
            Image(systemName: "flag.fill")
                .font(.system(size: 12))
                .foregroundColor(RemindersColors.accentOrange)
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
                onUnflag()
            } label: {
                Label("Unflag", systemImage: "flag.slash")
            }
            .tint(RemindersColors.textSecondary)
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

    // MARK: - Metadata Row

    private var metadataRow: some View {
        HStack(spacing: RemindersKit.Spacing.sm) {
            // List name (when not grouped)
            if showListName && !listName.isEmpty {
                HStack(spacing: RemindersKit.Spacing.xxs) {
                    Circle()
                        .fill(listColor)
                        .frame(width: 8, height: 8)
                    Text(listName)
                        .font(RemindersTypography.caption1)
                }
                .foregroundColor(RemindersColors.textSecondary)
            }

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
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d"
            return formatter.string(from: date)
        }
    }
}

// MARK: - Preview

#Preview("Flagged View") {
    NavigationStack {
        FlaggedView()
    }
    .preferredColorScheme(.dark)
}

#Preview("Flagged View Empty") {
    NavigationStack {
        FlaggedView()
    }
    .preferredColorScheme(.dark)
}

#Preview("Flagged Task Row") {
    List {
        FlaggedTaskRow(
            task: Task(
                title: "Important flagged task",
                notes: "Don't forget this one",
                dueDate: Date(),
                priority: .high,
                flag: true,
                redBeaconEnabled: true,
                listId: "work"
            ),
            listColor: ListColor.blue.color,
            onToggleComplete: { },
            onUnflag: { },
            onDelete: { },
            onTap: { }
        )

        FlaggedTaskRow(
            task: Task(
                title: "Simple flagged task",
                flag: true,
                listId: "personal"
            ),
            listColor: ListColor.orange.color,
            showListName: true,
            listName: "Personal",
            onToggleComplete: { },
            onUnflag: { },
            onDelete: { },
            onTap: { }
        )
    }
    .listStyle(.insetGrouped)
    .scrollContentBackground(.hidden)
    .background(RemindersColors.background)
    .preferredColorScheme(.dark)
}
