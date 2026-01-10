//
//  TodayView.swift
//  TasksApp
//
//  Today smart view showing tasks due today with overdue section
//

import SwiftUI

// MARK: - Today View Model

@MainActor
final class TodayViewModel: ObservableObject {
    // MARK: - Published Properties

    @Published var overdueTasks: [Task] = []
    @Published var todayTasks: [Task] = []
    @Published var tasksByList: [TaskList: [Task]] = [:]
    @Published var isLoading: Bool = false
    @Published var showCompletedTasks: Bool = false

    // Sample data for previews
    init() {
        loadSampleData()
    }

    // MARK: - Computed Properties

    var hasOverdueTasks: Bool {
        !overdueTasks.isEmpty
    }

    var hasTodayTasks: Bool {
        !todayTasks.isEmpty
    }

    var isEmpty: Bool {
        overdueTasks.isEmpty && todayTasks.isEmpty
    }

    var totalTaskCount: Int {
        overdueTasks.count + todayTasks.count
    }

    var overdueCount: Int {
        overdueTasks.count
    }

    // MARK: - Methods

    func toggleTaskCompletion(_ task: Task) {
        // In production, this would update the repository
        if let index = overdueTasks.firstIndex(where: { $0.id == task.id }) {
            overdueTasks[index].toggleCompletion()
        } else if let index = todayTasks.firstIndex(where: { $0.id == task.id }) {
            todayTasks[index].toggleCompletion()
        }
    }

    func toggleTaskFlag(_ task: Task) {
        if let index = overdueTasks.firstIndex(where: { $0.id == task.id }) {
            overdueTasks[index].toggleFlag()
        } else if let index = todayTasks.firstIndex(where: { $0.id == task.id }) {
            todayTasks[index].toggleFlag()
        }
    }

    func deleteTask(_ task: Task) {
        overdueTasks.removeAll { $0.id == task.id }
        todayTasks.removeAll { $0.id == task.id }
    }

    func refresh() async {
        isLoading = true
        // Simulate network delay
        try? await Foundation.Task.sleep(nanoseconds: 500_000_000)
        loadSampleData()
        isLoading = false
    }

    // MARK: - Private Methods

    private func loadSampleData() {
        let calendar = Calendar.current
        let yesterday = calendar.date(byAdding: .day, value: -1, to: Date())!
        let twoDaysAgo = calendar.date(byAdding: .day, value: -2, to: Date())!

        // Overdue tasks
        overdueTasks = [
            Task(
                title: "Submit quarterly report",
                notes: "Q4 financial summary",
                dueDate: twoDaysAgo,
                priority: .high,
                flag: true,
                redBeaconEnabled: true,
                listId: "work"
            ),
            Task(
                title: "Pay electricity bill",
                dueDate: yesterday,
                priority: .medium,
                listId: "personal"
            ),
            Task(
                title: "Call dentist for appointment",
                dueDate: yesterday,
                listId: "health"
            )
        ]

        // Today's tasks
        todayTasks = [
            Task(
                title: "Team standup meeting",
                notes: "Discuss sprint progress",
                dueDate: Date(),
                dueTime: calendar.date(bySettingHour: 9, minute: 30, second: 0, of: Date()),
                listId: "work"
            ),
            Task(
                title: "Review pull requests",
                dueDate: Date(),
                priority: .medium,
                listId: "work"
            ),
            Task(
                title: "Grocery shopping",
                notes: "Milk, eggs, bread, vegetables",
                dueDate: Date(),
                listId: "shopping"
            ),
            Task(
                title: "Evening workout",
                dueDate: Date(),
                dueTime: calendar.date(bySettingHour: 18, minute: 0, second: 0, of: Date()),
                listId: "health"
            ),
            Task(
                title: "Read chapter 5",
                notes: "Swift programming book",
                dueDate: Date(),
                flag: true,
                listId: "personal"
            )
        ]

        // Group by list for the grouped view
        let allTasks = todayTasks
        let lists = TaskList.sampleLists

        tasksByList = Dictionary(grouping: allTasks) { task in
            lists.first { $0.id == task.listId } ?? TaskList.inbox
        }
    }
}

// MARK: - Today View

struct TodayView: View {
    @StateObject private var viewModel = TodayViewModel()
    @State private var selectedTask: Task?
    @State private var showingNewTask: Bool = false

    var body: some View {
        Group {
            if viewModel.isEmpty {
                emptyState
            } else {
                taskList
            }
        }
        .background(RemindersColors.background)
        .navigationTitle("Today")
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
    }

    // MARK: - Task List

    private var taskList: some View {
        List {
            // Overdue Section
            if viewModel.hasOverdueTasks {
                overdueSection
            }

            // Today Section (grouped by list)
            todaySection
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(RemindersColors.background)
    }

    // MARK: - Overdue Section

    private var overdueSection: some View {
        Section {
            ForEach(viewModel.overdueTasks) { task in
                TodayTaskRow(
                    task: task,
                    onToggleComplete: { viewModel.toggleTaskCompletion(task) },
                    onToggleFlag: { viewModel.toggleTaskFlag(task) },
                    onDelete: { viewModel.deleteTask(task) },
                    onTap: { selectedTask = task }
                )
            }
        } header: {
            HStack {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(RemindersColors.accentRed)

                Text("Overdue")
                    .font(RemindersTypography.footnoteBold)
                    .foregroundColor(RemindersColors.accentRed)

                Spacer()

                Text("\(viewModel.overdueCount)")
                    .font(RemindersTypography.footnote)
                    .foregroundColor(RemindersColors.accentRed)
            }
            .textCase(nil)
        }
        .listRowBackground(RemindersColors.backgroundSecondary)
        .listRowSeparatorTint(RemindersColors.separator)
    }

    // MARK: - Today Section

    private var todaySection: some View {
        Section {
            ForEach(viewModel.todayTasks) { task in
                TodayTaskRow(
                    task: task,
                    onToggleComplete: { viewModel.toggleTaskCompletion(task) },
                    onToggleFlag: { viewModel.toggleTaskFlag(task) },
                    onDelete: { viewModel.deleteTask(task) },
                    onTap: { selectedTask = task }
                )
            }
        } header: {
            HStack {
                Image(systemName: "calendar")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(RemindersColors.accentBlue)

                Text(todayHeaderText)
                    .font(RemindersTypography.footnoteBold)
                    .foregroundColor(RemindersColors.textPrimary)

                Spacer()

                Text("\(viewModel.todayTasks.count)")
                    .font(RemindersTypography.footnote)
                    .foregroundColor(RemindersColors.textSecondary)
            }
            .textCase(nil)
        }
        .listRowBackground(RemindersColors.backgroundSecondary)
        .listRowSeparatorTint(RemindersColors.separator)
    }

    private var todayHeaderText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d"
        return formatter.string(from: Date())
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: RemindersKit.Spacing.xl) {
            Spacer()

            Image(systemName: "calendar")
                .font(.system(size: 64, weight: .light))
                .foregroundColor(RemindersColors.accentBlue.opacity(0.5))

            VStack(spacing: RemindersKit.Spacing.sm) {
                Text("Nothing Due Today")
                    .font(RemindersTypography.title3)
                    .foregroundColor(RemindersColors.textPrimary)

                Text("Reminders due today will appear here.")
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

            Button {
                // Sort action
            } label: {
                Label("Sort by Time", systemImage: "clock")
            }

            Button {
                // Sort action
            } label: {
                Label("Sort by Priority", systemImage: "exclamationmark.circle")
            }

            Button {
                // Sort action
            } label: {
                Label("Sort by List", systemImage: "list.bullet")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 17, weight: .medium))
                .foregroundColor(RemindersColors.accentBlue)
        }
    }
}

// MARK: - Today Task Row

struct TodayTaskRow: View {
    let task: Task
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
                metadataRow
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
                        .fill(RemindersColors.accentBlue)
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
        return RemindersColors.checkboxBorder
    }

    // MARK: - Metadata Row

    private var metadataRow: some View {
        HStack(spacing: RemindersKit.Spacing.sm) {
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

            // Overdue indicator
            if task.isOverdue {
                Text("Overdue")
                    .font(RemindersTypography.caption1Bold)
                    .foregroundColor(RemindersColors.accentRed)
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

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Preview

#Preview("Today View") {
    NavigationStack {
        TodayView()
    }
    .preferredColorScheme(.dark)
}

#Preview("Today View Empty") {
    NavigationStack {
        TodayView()
    }
    .preferredColorScheme(.dark)
    .onAppear {
        // Would need to modify view model for empty state preview
    }
}

#Preview("Today Task Row") {
    List {
        TodayTaskRow(
            task: Task(
                title: "Complete project documentation",
                notes: "Include API reference and setup guide",
                dueDate: Date(),
                dueTime: Date(),
                priority: .high,
                flag: true,
                redBeaconEnabled: true,
                listId: "work"
            ),
            onToggleComplete: { },
            onToggleFlag: { },
            onDelete: { },
            onTap: { }
        )

        TodayTaskRow(
            task: Task(
                title: "Buy groceries",
                dueDate: Calendar.current.date(byAdding: .day, value: -1, to: Date())!,
                listId: "shopping"
            ),
            onToggleComplete: { },
            onToggleFlag: { },
            onDelete: { },
            onTap: { }
        )

        TodayTaskRow(
            task: Task(
                title: "Call mom",
                dueDate: Date(),
                listId: "personal"
            ),
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
