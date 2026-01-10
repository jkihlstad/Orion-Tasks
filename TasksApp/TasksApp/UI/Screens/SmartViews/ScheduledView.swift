//
//  ScheduledView.swift
//  TasksApp
//
//  Scheduled smart view showing tasks with due dates grouped by time period
//

import SwiftUI

// MARK: - Schedule Group

/// Groups for organizing scheduled tasks by time period
enum ScheduleGroup: String, CaseIterable, Identifiable {
    case overdue
    case today
    case tomorrow
    case thisWeek
    case nextWeek
    case later

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overdue: return "Overdue"
        case .today: return "Today"
        case .tomorrow: return "Tomorrow"
        case .thisWeek: return "This Week"
        case .nextWeek: return "Next Week"
        case .later: return "Later"
        }
    }

    var icon: String {
        switch self {
        case .overdue: return "exclamationmark.circle.fill"
        case .today: return "calendar"
        case .tomorrow: return "sunrise.fill"
        case .thisWeek: return "calendar.badge.clock"
        case .nextWeek: return "calendar"
        case .later: return "calendar.badge.plus"
        }
    }

    var color: Color {
        switch self {
        case .overdue: return RemindersColors.accentRed
        case .today: return RemindersColors.accentBlue
        case .tomorrow: return RemindersColors.accentOrange
        case .thisWeek: return RemindersColors.accentPurple
        case .nextWeek: return RemindersColors.accentCyan
        case .later: return RemindersColors.textSecondary
        }
    }
}

// MARK: - Scheduled View Model

@MainActor
final class ScheduledViewModel: ObservableObject {
    // MARK: - Published Properties

    @Published var tasksByGroup: [ScheduleGroup: [Task]] = [:]
    @Published var isLoading: Bool = false
    @Published var showCompletedTasks: Bool = false
    @Published var sortOrder: ScheduledSortOrder = .date

    enum ScheduledSortOrder: String, CaseIterable {
        case date = "Date"
        case priority = "Priority"
        case list = "List"
    }

    // Sample data for previews
    init() {
        loadSampleData()
    }

    // MARK: - Computed Properties

    var activeGroups: [ScheduleGroup] {
        ScheduleGroup.allCases.filter { group in
            guard let tasks = tasksByGroup[group] else { return false }
            return !tasks.isEmpty
        }
    }

    var isEmpty: Bool {
        tasksByGroup.values.allSatisfy { $0.isEmpty }
    }

    var totalTaskCount: Int {
        tasksByGroup.values.reduce(0) { $0 + $1.count }
    }

    var overdueCount: Int {
        tasksByGroup[.overdue]?.count ?? 0
    }

    // MARK: - Methods

    func tasks(for group: ScheduleGroup) -> [Task] {
        tasksByGroup[group] ?? []
    }

    func taskCount(for group: ScheduleGroup) -> Int {
        tasksByGroup[group]?.count ?? 0
    }

    func toggleTaskCompletion(_ task: Task) {
        for group in ScheduleGroup.allCases {
            if var tasks = tasksByGroup[group],
               let index = tasks.firstIndex(where: { $0.id == task.id }) {
                tasks[index].toggleCompletion()
                tasksByGroup[group] = tasks
                return
            }
        }
    }

    func toggleTaskFlag(_ task: Task) {
        for group in ScheduleGroup.allCases {
            if var tasks = tasksByGroup[group],
               let index = tasks.firstIndex(where: { $0.id == task.id }) {
                tasks[index].toggleFlag()
                tasksByGroup[group] = tasks
                return
            }
        }
    }

    func deleteTask(_ task: Task) {
        for group in ScheduleGroup.allCases {
            tasksByGroup[group]?.removeAll { $0.id == task.id }
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

        // Calculate dates
        let twoDaysAgo = calendar.date(byAdding: .day, value: -2, to: now)!
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now)!
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: now)!
        let inThreeDays = calendar.date(byAdding: .day, value: 3, to: now)!
        let inFiveDays = calendar.date(byAdding: .day, value: 5, to: now)!
        let nextWeek = calendar.date(byAdding: .weekOfYear, value: 1, to: now)!
        let inTwoWeeks = calendar.date(byAdding: .weekOfYear, value: 2, to: now)!

        tasksByGroup = [
            .overdue: [
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
                )
            ],
            .today: [
                Task(
                    title: "Team standup meeting",
                    notes: "Discuss sprint progress",
                    dueDate: now,
                    dueTime: calendar.date(bySettingHour: 9, minute: 30, second: 0, of: now),
                    listId: "work"
                ),
                Task(
                    title: "Review pull requests",
                    dueDate: now,
                    priority: .medium,
                    listId: "work"
                ),
                Task(
                    title: "Grocery shopping",
                    dueDate: now,
                    listId: "shopping"
                )
            ],
            .tomorrow: [
                Task(
                    title: "Doctor appointment",
                    dueDate: tomorrow,
                    dueTime: calendar.date(bySettingHour: 10, minute: 0, second: 0, of: tomorrow),
                    listId: "health"
                ),
                Task(
                    title: "Send project proposal",
                    dueDate: tomorrow,
                    priority: .high,
                    listId: "work"
                )
            ],
            .thisWeek: [
                Task(
                    title: "Weekly team sync",
                    dueDate: inThreeDays,
                    listId: "work"
                ),
                Task(
                    title: "Gym session",
                    dueDate: inThreeDays,
                    listId: "health"
                ),
                Task(
                    title: "Finish book chapter",
                    dueDate: inFiveDays,
                    flag: true,
                    listId: "personal"
                )
            ],
            .nextWeek: [
                Task(
                    title: "Monthly review",
                    dueDate: nextWeek,
                    priority: .medium,
                    listId: "work"
                ),
                Task(
                    title: "Car service appointment",
                    dueDate: nextWeek,
                    listId: "personal"
                )
            ],
            .later: [
                Task(
                    title: "Renew passport",
                    dueDate: inTwoWeeks,
                    listId: "personal"
                ),
                Task(
                    title: "Plan vacation",
                    dueDate: calendar.date(byAdding: .month, value: 1, to: now)!,
                    flag: true,
                    listId: "personal"
                )
            ]
        ]
    }
}

// MARK: - Scheduled View

struct ScheduledView: View {
    @StateObject private var viewModel = ScheduledViewModel()
    @State private var selectedTask: Task?
    @State private var showingNewTask: Bool = false
    @State private var expandedGroups: Set<ScheduleGroup> = Set(ScheduleGroup.allCases)

    var body: some View {
        Group {
            if viewModel.isEmpty {
                emptyState
            } else {
                taskList
            }
        }
        .background(RemindersColors.background)
        .navigationTitle("Scheduled")
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
            ForEach(viewModel.activeGroups) { group in
                scheduleSection(for: group)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(RemindersColors.background)
    }

    // MARK: - Schedule Section

    private func scheduleSection(for group: ScheduleGroup) -> some View {
        Section {
            if expandedGroups.contains(group) {
                ForEach(viewModel.tasks(for: group)) { task in
                    ScheduledTaskRow(
                        task: task,
                        showDate: group != .today,
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
                    if expandedGroups.contains(group) {
                        expandedGroups.remove(group)
                    } else {
                        expandedGroups.insert(group)
                    }
                }
            } label: {
                HStack {
                    Image(systemName: group.icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(group.color)

                    Text(group.title)
                        .font(RemindersTypography.footnoteBold)
                        .foregroundColor(group == .overdue ? group.color : RemindersColors.textPrimary)

                    Spacer()

                    Text("\(viewModel.taskCount(for: group))")
                        .font(RemindersTypography.footnote)
                        .foregroundColor(group == .overdue ? group.color : RemindersColors.textSecondary)

                    Image(systemName: expandedGroups.contains(group) ? "chevron.down" : "chevron.right")
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

            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 64, weight: .light))
                .foregroundColor(RemindersColors.accentRed.opacity(0.5))

            VStack(spacing: RemindersKit.Spacing.sm) {
                Text("No Scheduled Reminders")
                    .font(RemindersTypography.title3)
                    .foregroundColor(RemindersColors.textPrimary)

                Text("Reminders with due dates will appear here.")
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
                ForEach(ScheduledViewModel.ScheduledSortOrder.allCases, id: \.self) { order in
                    Text(order.rawValue).tag(order)
                }
            }

            Divider()

            Button {
                withAnimation {
                    expandedGroups = Set(ScheduleGroup.allCases)
                }
            } label: {
                Label("Expand All", systemImage: "arrow.up.left.and.arrow.down.right")
            }

            Button {
                withAnimation {
                    expandedGroups.removeAll()
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

// MARK: - Scheduled Task Row

struct ScheduledTaskRow: View {
    let task: Task
    let showDate: Bool
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
            // Date
            if showDate, let dueDate = task.dueDate {
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
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Preview

#Preview("Scheduled View") {
    NavigationStack {
        ScheduledView()
    }
    .preferredColorScheme(.dark)
}

#Preview("Scheduled Task Row") {
    List {
        ScheduledTaskRow(
            task: Task(
                title: "Submit project report",
                notes: "Include all deliverables",
                dueDate: Date(),
                dueTime: Date(),
                priority: .high,
                flag: true,
                listId: "work"
            ),
            showDate: true,
            onToggleComplete: { },
            onToggleFlag: { },
            onDelete: { },
            onTap: { }
        )

        ScheduledTaskRow(
            task: Task(
                title: "Gym session",
                dueDate: Calendar.current.date(byAdding: .day, value: 2, to: Date())!,
                listId: "health"
            ),
            showDate: true,
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
