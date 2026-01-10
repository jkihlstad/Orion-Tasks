//
//  CompletedView.swift
//  TasksApp
//
//  Completed smart view showing all completed tasks
//

import SwiftUI

// MARK: - Completed Time Period

/// Groups for organizing completed tasks by time period
enum CompletedTimePeriod: String, CaseIterable, Identifiable {
    case today
    case yesterday
    case thisWeek
    case lastWeek
    case thisMonth
    case older

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: return "Today"
        case .yesterday: return "Yesterday"
        case .thisWeek: return "This Week"
        case .lastWeek: return "Last Week"
        case .thisMonth: return "This Month"
        case .older: return "Older"
        }
    }

    var icon: String {
        switch self {
        case .today: return "checkmark.circle.fill"
        case .yesterday: return "clock.arrow.circlepath"
        case .thisWeek: return "calendar"
        case .lastWeek: return "calendar.badge.minus"
        case .thisMonth: return "calendar.circle"
        case .older: return "archivebox"
        }
    }
}

// MARK: - Completed View Model

@MainActor
final class CompletedViewModel: ObservableObject {
    // MARK: - Published Properties

    @Published var tasksByPeriod: [CompletedTimePeriod: [Task]] = [:]
    @Published var isLoading: Bool = false
    @Published var sortOrder: CompletedSortOrder = .completedDate
    @Published var groupByPeriod: Bool = true
    @Published var showClearAlert: Bool = false

    enum CompletedSortOrder: String, CaseIterable {
        case completedDate = "Completed Date"
        case list = "List"
        case priority = "Priority"
        case dueDate = "Due Date"
    }

    // Sample data for previews
    init() {
        loadSampleData()
    }

    // MARK: - Computed Properties

    var activePeriods: [CompletedTimePeriod] {
        CompletedTimePeriod.allCases.filter { period in
            guard let tasks = tasksByPeriod[period] else { return false }
            return !tasks.isEmpty
        }
    }

    var isEmpty: Bool {
        tasksByPeriod.values.allSatisfy { $0.isEmpty }
    }

    var totalTaskCount: Int {
        tasksByPeriod.values.reduce(0) { $0 + $1.count }
    }

    var allCompletedTasks: [Task] {
        tasksByPeriod.values.flatMap { $0 }.sorted { task1, task2 in
            guard let date1 = task1.completedAt else { return false }
            guard let date2 = task2.completedAt else { return true }
            return date1 > date2
        }
    }

    // MARK: - Methods

    func tasks(for period: CompletedTimePeriod) -> [Task] {
        tasksByPeriod[period] ?? []
    }

    func taskCount(for period: CompletedTimePeriod) -> Int {
        tasksByPeriod[period]?.count ?? 0
    }

    func uncompleteTask(_ task: Task) {
        for period in CompletedTimePeriod.allCases {
            if var tasks = tasksByPeriod[period],
               let index = tasks.firstIndex(where: { $0.id == task.id }) {
                tasks[index].uncomplete()
                tasks.remove(at: index)
                tasksByPeriod[period] = tasks
                return
            }
        }
    }

    func deleteTask(_ task: Task) {
        for period in CompletedTimePeriod.allCases {
            tasksByPeriod[period]?.removeAll { $0.id == task.id }
        }
    }

    func clearAllCompleted() {
        for period in CompletedTimePeriod.allCases {
            tasksByPeriod[period] = []
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
        let todayMorning = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: now)!
        let todayAfternoon = calendar.date(bySettingHour: 14, minute: 30, second: 0, of: now)!
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now)!
        let twoDaysAgo = calendar.date(byAdding: .day, value: -2, to: now)!
        let fourDaysAgo = calendar.date(byAdding: .day, value: -4, to: now)!
        let lastWeek = calendar.date(byAdding: .weekOfYear, value: -1, to: now)!
        let twoWeeksAgo = calendar.date(byAdding: .weekOfYear, value: -2, to: now)!
        let lastMonth = calendar.date(byAdding: .month, value: -1, to: now)!

        tasksByPeriod = [
            .today: [
                Task(
                    title: "Morning standup",
                    dueDate: now,
                    completedAt: todayMorning,
                    listId: "work"
                ),
                Task(
                    title: "Review documentation",
                    completedAt: todayAfternoon,
                    listId: "work"
                ),
                Task(
                    title: "Reply to emails",
                    completedAt: todayMorning,
                    listId: "inbox"
                )
            ],
            .yesterday: [
                Task(
                    title: "Finish project milestone",
                    notes: "Version 2.0 release",
                    dueDate: yesterday,
                    priority: .high,
                    completedAt: yesterday,
                    listId: "work"
                ),
                Task(
                    title: "Grocery shopping",
                    completedAt: yesterday,
                    listId: "shopping"
                )
            ],
            .thisWeek: [
                Task(
                    title: "Weekly team sync",
                    dueDate: twoDaysAgo,
                    completedAt: twoDaysAgo,
                    listId: "work"
                ),
                Task(
                    title: "Gym session",
                    completedAt: fourDaysAgo,
                    listId: "health"
                ),
                Task(
                    title: "Read book chapter",
                    notes: "Chapter 10 completed",
                    completedAt: twoDaysAgo,
                    listId: "personal"
                )
            ],
            .lastWeek: [
                Task(
                    title: "Prepare quarterly presentation",
                    priority: .high,
                    completedAt: lastWeek,
                    listId: "work"
                ),
                Task(
                    title: "Car wash",
                    completedAt: lastWeek,
                    listId: "personal"
                )
            ],
            .thisMonth: [
                Task(
                    title: "Complete online course",
                    notes: "Swift advanced topics",
                    completedAt: twoWeeksAgo,
                    listId: "personal"
                ),
                Task(
                    title: "Update portfolio",
                    completedAt: twoWeeksAgo,
                    listId: "work"
                )
            ],
            .older: [
                Task(
                    title: "Annual health checkup",
                    completedAt: lastMonth,
                    listId: "health"
                ),
                Task(
                    title: "Home organization",
                    completedAt: lastMonth,
                    listId: "personal"
                )
            ]
        ]
    }

    private func completedTask(title: String, notes: String? = nil, dueDate: Date? = nil, priority: Priority = .none, completedAt: Date, listId: String) -> Task {
        var task = Task(
            title: title,
            notes: notes,
            dueDate: dueDate,
            priority: priority,
            listId: listId
        )
        task.completedAt = completedAt
        return task
    }
}

// MARK: - Completed View

struct CompletedView: View {
    @StateObject private var viewModel = CompletedViewModel()
    @State private var selectedTask: Task?
    @State private var expandedPeriods: Set<CompletedTimePeriod> = Set(CompletedTimePeriod.allCases)

    var body: some View {
        Group {
            if viewModel.isEmpty {
                emptyState
            } else {
                taskList
            }
        }
        .background(RemindersColors.background)
        .navigationTitle("Completed")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                menuButton
            }
        }
        .refreshable {
            await viewModel.refresh()
        }
        .alert("Clear All Completed?", isPresented: $viewModel.showClearAlert) {
            Button("Clear", role: .destructive) {
                withAnimation {
                    viewModel.clearAllCompleted()
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will permanently delete all \(viewModel.totalTaskCount) completed reminders. This action cannot be undone.")
        }
    }

    // MARK: - Task List

    private var taskList: some View {
        List {
            // Summary header
            summarySection

            // Tasks grouped by time period
            if viewModel.groupByPeriod {
                ForEach(viewModel.activePeriods) { period in
                    periodSection(for: period)
                }
            } else {
                flatListSection
            }

            // Clear all button
            clearAllSection
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(RemindersColors.background)
    }

    // MARK: - Summary Section

    private var summarySection: some View {
        Section {
            HStack(spacing: RemindersKit.Spacing.md) {
                // Checkmark icon
                ZStack {
                    Circle()
                        .fill(RemindersColors.accentGreen)
                        .frame(width: 48, height: 48)

                    Image(systemName: "checkmark")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(.white)
                }

                VStack(alignment: .leading, spacing: RemindersKit.Spacing.xxs) {
                    Text("\(viewModel.totalTaskCount)")
                        .font(RemindersTypography.roundedLarge)
                        .foregroundColor(RemindersColors.textPrimary)

                    Text("Completed Reminders")
                        .font(RemindersTypography.caption1)
                        .foregroundColor(RemindersColors.textSecondary)
                }

                Spacer()
            }
            .padding(.vertical, RemindersKit.Spacing.sm)
        }
        .listRowBackground(RemindersColors.backgroundSecondary)
    }

    // MARK: - Period Section

    private func periodSection(for period: CompletedTimePeriod) -> some View {
        Section {
            if expandedPeriods.contains(period) {
                ForEach(viewModel.tasks(for: period)) { task in
                    let list = TaskList.sampleLists.first { $0.id == task.listId } ?? TaskList.inbox
                    CompletedTaskRow(
                        task: task,
                        listColor: list.color.color,
                        listName: list.name,
                        onUncomplete: { viewModel.uncompleteTask(task) },
                        onDelete: { viewModel.deleteTask(task) },
                        onTap: { selectedTask = task }
                    )
                }
            }
        } header: {
            Button {
                withAnimation(RemindersKit.Animation.standard) {
                    if expandedPeriods.contains(period) {
                        expandedPeriods.remove(period)
                    } else {
                        expandedPeriods.insert(period)
                    }
                }
            } label: {
                HStack(spacing: RemindersKit.Spacing.sm) {
                    Image(systemName: period.icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(RemindersColors.accentGreen)

                    Text(period.title)
                        .font(RemindersTypography.footnoteBold)
                        .foregroundColor(RemindersColors.textPrimary)

                    Spacer()

                    Text("\(viewModel.taskCount(for: period))")
                        .font(RemindersTypography.footnote)
                        .foregroundColor(RemindersColors.textSecondary)

                    Image(systemName: expandedPeriods.contains(period) ? "chevron.down" : "chevron.right")
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
            ForEach(viewModel.allCompletedTasks) { task in
                let list = TaskList.sampleLists.first { $0.id == task.listId } ?? TaskList.inbox
                CompletedTaskRow(
                    task: task,
                    listColor: list.color.color,
                    listName: list.name,
                    showCompletedDate: true,
                    onUncomplete: { viewModel.uncompleteTask(task) },
                    onDelete: { viewModel.deleteTask(task) },
                    onTap: { selectedTask = task }
                )
            }
        }
        .listRowBackground(RemindersColors.backgroundSecondary)
        .listRowSeparatorTint(RemindersColors.separator)
    }

    // MARK: - Clear All Section

    private var clearAllSection: some View {
        Section {
            Button(role: .destructive) {
                viewModel.showClearAlert = true
            } label: {
                HStack {
                    Spacer()
                    Label("Clear All Completed", systemImage: "trash")
                        .font(RemindersTypography.body)
                        .foregroundColor(RemindersColors.accentRed)
                    Spacer()
                }
            }
        }
        .listRowBackground(RemindersColors.backgroundSecondary)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: RemindersKit.Spacing.xl) {
            Spacer()

            Image(systemName: "checkmark.circle")
                .font(.system(size: 64, weight: .light))
                .foregroundColor(RemindersColors.accentGreen.opacity(0.5))

            VStack(spacing: RemindersKit.Spacing.sm) {
                Text("No Completed Reminders")
                    .font(RemindersTypography.title3)
                    .foregroundColor(RemindersColors.textPrimary)

                Text("Completed reminders will appear here.")
                    .font(RemindersTypography.body)
                    .foregroundColor(RemindersColors.textSecondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: RemindersKit.Spacing.md) {
                HStack(spacing: RemindersKit.Spacing.sm) {
                    Image(systemName: "circle")
                        .foregroundColor(RemindersColors.textTertiary)
                    Text("Tap the circle to complete a reminder")
                        .font(RemindersTypography.subheadline)
                        .foregroundColor(RemindersColors.textSecondary)
                }
            }
            .padding(.top, RemindersKit.Spacing.lg)

            Spacer()
        }
        .padding()
    }

    // MARK: - Menu Button

    private var menuButton: some View {
        Menu {
            Toggle("Group by Time", isOn: $viewModel.groupByPeriod)

            Divider()

            Picker("Sort By", selection: $viewModel.sortOrder) {
                ForEach(CompletedViewModel.CompletedSortOrder.allCases, id: \.self) { order in
                    Text(order.rawValue).tag(order)
                }
            }

            if viewModel.groupByPeriod {
                Divider()

                Button {
                    withAnimation {
                        expandedPeriods = Set(CompletedTimePeriod.allCases)
                    }
                } label: {
                    Label("Expand All", systemImage: "arrow.up.left.and.arrow.down.right")
                }

                Button {
                    withAnimation {
                        expandedPeriods.removeAll()
                    }
                } label: {
                    Label("Collapse All", systemImage: "arrow.down.right.and.arrow.up.left")
                }
            }

            if !viewModel.isEmpty {
                Divider()

                Button(role: .destructive) {
                    viewModel.showClearAlert = true
                } label: {
                    Label("Clear All", systemImage: "trash")
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 17, weight: .medium))
                .foregroundColor(RemindersColors.accentBlue)
        }
    }
}

// MARK: - Completed Task Row

struct CompletedTaskRow: View {
    let task: Task
    let listColor: Color
    let listName: String
    var showCompletedDate: Bool = false
    let onUncomplete: () -> Void
    let onDelete: () -> Void
    let onTap: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: RemindersKit.Spacing.md) {
            // Completed checkbox
            completedCheckbox

            // Task Content
            VStack(alignment: .leading, spacing: RemindersKit.Spacing.xxs) {
                // Title (struck through)
                Text(task.title)
                    .font(RemindersTypography.body)
                    .foregroundColor(RemindersColors.textTertiary)
                    .strikethrough(true, color: RemindersColors.textTertiary)
                    .lineLimit(2)

                // Notes preview
                if let notes = task.notes, !notes.isEmpty {
                    Text(notes)
                        .font(RemindersTypography.subheadline)
                        .foregroundColor(RemindersColors.textTertiary.opacity(0.7))
                        .lineLimit(1)
                }

                // Metadata row
                metadataRow
            }

            Spacer()
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
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                onUncomplete()
            } label: {
                Label("Uncomplete", systemImage: "arrow.uturn.backward.circle")
            }
            .tint(RemindersColors.accentBlue)
        }
    }

    // MARK: - Completed Checkbox

    private var completedCheckbox: some View {
        Button {
            withAnimation(RemindersKit.Animation.standard) {
                onUncomplete()
            }
        } label: {
            ZStack {
                Circle()
                    .fill(listColor.opacity(0.3))
                    .frame(width: RemindersKit.Size.checkbox, height: RemindersKit.Size.checkbox)

                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(listColor)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Metadata Row

    private var metadataRow: some View {
        HStack(spacing: RemindersKit.Spacing.sm) {
            // List indicator
            HStack(spacing: RemindersKit.Spacing.xxs) {
                Circle()
                    .fill(listColor)
                    .frame(width: 8, height: 8)
                Text(listName)
                    .font(RemindersTypography.caption1)
            }
            .foregroundColor(RemindersColors.textTertiary)

            // Completed date
            if showCompletedDate, let completedAt = task.completedAt {
                Text(formatCompletedDate(completedAt))
                    .font(RemindersTypography.caption1)
                    .foregroundColor(RemindersColors.textTertiary)
            }

            // Original due date (if had one)
            if let dueDate = task.dueDate {
                HStack(spacing: RemindersKit.Spacing.xxs) {
                    Image(systemName: "calendar")
                        .font(.system(size: 11))
                    Text(formatDate(dueDate))
                        .font(RemindersTypography.caption1)
                }
                .foregroundColor(RemindersColors.textTertiary)
            }
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }

    private func formatCompletedDate(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            return formatter.string(from: date)
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

#Preview("Completed View") {
    NavigationStack {
        CompletedView()
    }
    .preferredColorScheme(.dark)
}

#Preview("Completed View Empty") {
    NavigationStack {
        CompletedView()
    }
    .preferredColorScheme(.dark)
}

#Preview("Completed Task Row") {
    List {
        CompletedTaskRow(
            task: {
                var task = Task(
                    title: "Completed important task",
                    notes: "This was a big one",
                    dueDate: Date(),
                    priority: .high,
                    listId: "work"
                )
                task.completedAt = Date()
                return task
            }(),
            listColor: ListColor.blue.color,
            listName: "Work",
            showCompletedDate: true,
            onUncomplete: { },
            onDelete: { },
            onTap: { }
        )

        CompletedTaskRow(
            task: {
                var task = Task(
                    title: "Simple completed task",
                    listId: "personal"
                )
                task.completedAt = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
                return task
            }(),
            listColor: ListColor.orange.color,
            listName: "Personal",
            onUncomplete: { },
            onDelete: { },
            onTap: { }
        )
    }
    .listStyle(.insetGrouped)
    .scrollContentBackground(.hidden)
    .background(RemindersColors.background)
    .preferredColorScheme(.dark)
}
