//
//  TaskRowView.swift
//  TasksApp
//
//  Task list row component matching Apple Reminders style
//

import SwiftUI

// MARK: - Task Row View

struct TaskRowView: View {

    // MARK: - Properties

    @Binding var task: Task
    let listColor: Color
    let showListIndicator: Bool
    let onToggle: () -> Void
    let onFlag: () -> Void
    let onDelete: () -> Void
    let onTap: () -> Void

    // MARK: - State

    @State private var isPressed = false
    @State private var completionOffset: CGFloat = 0
    @State private var opacity: Double = 1

    // MARK: - Initialization

    init(
        task: Binding<Task>,
        listColor: Color = RemindersColors.accentBlue,
        showListIndicator: Bool = false,
        onToggle: @escaping () -> Void = {},
        onFlag: @escaping () -> Void = {},
        onDelete: @escaping () -> Void = {},
        onTap: @escaping () -> Void = {}
    ) {
        self._task = task
        self.listColor = listColor
        self.showListIndicator = showListIndicator
        self.onToggle = onToggle
        self.onFlag = onFlag
        self.onDelete = onDelete
        self.onTap = onTap
    }

    // MARK: - Body

    var body: some View {
        HStack(spacing: 0) {
            // Priority sidebar indicator
            if task.priority != .none {
                Rectangle()
                    .fill(task.priority.color)
                    .frame(width: 3)
            }

            HStack(spacing: RemindersKit.Spacing.checkboxContent) {
                // Checkbox with priority
                PriorityCheckbox(
                    isChecked: Binding(
                        get: { task.isCompleted },
                        set: { _ in handleToggle() }
                    ),
                    priority: task.priority,
                    listColor: listColor,
                    onToggle: handleToggle
                )

                // Content
                VStack(alignment: .leading, spacing: RemindersKit.Spacing.xxs) {
                    // Title row
                    HStack(spacing: RemindersKit.Spacing.sm) {
                        Text(task.title.isEmpty ? "New Reminder" : task.title)
                            .font(RemindersTypography.taskTitle)
                            .foregroundColor(task.isCompleted ? RemindersColors.textSecondary : RemindersColors.textPrimary)
                            .strikethrough(task.isCompleted, color: RemindersColors.textSecondary)
                            .lineLimit(2)

                        Spacer()

                        // Indicators row
                        HStack(spacing: RemindersKit.Spacing.xs) {
                            // Red Beacon
                            if task.redBeaconEnabled {
                                BeaconBadge(size: .small, isAnimated: !task.isCompleted)
                            }

                            // Flag indicator
                            if task.flag {
                                Image(systemName: "flag.fill")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(RemindersColors.accentOrange)
                            }
                        }
                    }

                    // Notes preview
                    if let notes = task.notes, !notes.isEmpty {
                        Text(notes)
                            .font(RemindersTypography.taskSubtitle)
                            .foregroundColor(RemindersColors.textSecondary)
                            .lineLimit(1)
                    }

                    // Metadata row
                    metadataRow
                }

                // Chevron for navigation
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(RemindersColors.textTertiary)
            }
            .padding(.vertical, RemindersKit.Spacing.listRowVertical)
            .padding(.horizontal, RemindersKit.Spacing.listRowHorizontal)
        }
        .background(RemindersColors.backgroundSecondary)
        .opacity(opacity)
        .offset(x: completionOffset)
        .contentShape(Rectangle())
        .onTapGesture {
            onTap()
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                handleToggle()
            } label: {
                Label(
                    task.isCompleted ? "Uncomplete" : "Complete",
                    systemImage: task.isCompleted ? "arrow.uturn.backward" : "checkmark"
                )
            }
            .tint(RemindersColors.accentGreen)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash.fill")
            }

            Button(action: onFlag) {
                Label(task.flag ? "Unflag" : "Flag", systemImage: task.flag ? "flag.slash.fill" : "flag.fill")
            }
            .tint(RemindersColors.accentOrange)
        }
    }

    // MARK: - Metadata Row

    @ViewBuilder
    private var metadataRow: some View {
        let hasMetadata = task.dueDate != nil || task.repeatRule != nil || !task.tags.isEmpty || !task.subtasks.isEmpty || showListIndicator

        if hasMetadata {
            HStack(spacing: RemindersKit.Spacing.sm) {
                // Due date badge
                if let dueDate = task.dueDate {
                    DateTimeDisplay(date: dueDate, time: task.dueTime, showIcon: true)
                }

                // Repeat indicator
                if task.repeatRule != nil {
                    Image(systemName: "repeat")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(RemindersColors.accentGreen)
                }

                // Subtasks count
                if !task.subtasks.isEmpty {
                    HStack(spacing: 2) {
                        Image(systemName: "checklist")
                            .font(.system(size: 10, weight: .medium))

                        Text("\(task.subtasks.count)")
                            .font(RemindersTypography.caption2)
                    }
                    .foregroundColor(RemindersColors.textSecondary)
                }

                // Attachments indicator
                if !task.attachments.isEmpty {
                    Image(systemName: "paperclip")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(RemindersColors.textSecondary)
                }

                // Calendar mirror indicator
                if task.mirrorToCalendarEnabled {
                    Image(systemName: "calendar")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(RemindersColors.accentCyan)
                }

                Spacer()
            }
        }
    }

    // MARK: - Actions

    private func handleToggle() {
        // Haptic feedback
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()

        if !task.isCompleted {
            // Animate completion
            withAnimation(.easeInOut(duration: 0.3)) {
                completionOffset = 10
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    opacity = 0.5
                }
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                onToggle()

                // Reset animations
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        completionOffset = 0
                        opacity = 1
                    }
                }
            }
        } else {
            onToggle()
        }
    }
}

// MARK: - Compact Task Row

/// A more compact version for certain list views
struct CompactTaskRow: View {
    @Binding var task: Task
    let listColor: Color
    let onToggle: () -> Void
    let onTap: () -> Void

    var body: some View {
        HStack(spacing: RemindersKit.Spacing.sm) {
            TaskCheckbox(
                isChecked: Binding(
                    get: { task.isCompleted },
                    set: { _ in onToggle() }
                ),
                color: listColor,
                size: .small,
                onToggle: onToggle
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .font(RemindersTypography.subheadline)
                    .foregroundColor(task.isCompleted ? RemindersColors.textSecondary : RemindersColors.textPrimary)
                    .strikethrough(task.isCompleted)
                    .lineLimit(1)

                if let dueDate = task.dueDate {
                    Text(formatCompactDate(dueDate))
                        .font(RemindersTypography.caption2)
                        .foregroundColor(dateColor(for: dueDate))
                }
            }

            Spacer()

            HStack(spacing: RemindersKit.Spacing.xxs) {
                if task.redBeaconEnabled {
                    BeaconBadge(size: .small)
                }

                if task.flag {
                    Image(systemName: "flag.fill")
                        .font(.system(size: 10))
                        .foregroundColor(RemindersColors.accentOrange)
                }
            }
        }
        .padding(.vertical, RemindersKit.Spacing.xs)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }

    private func formatCompactDate(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInTomorrow(date) { return "Tomorrow" }

        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }

    private func dateColor(for date: Date) -> Color {
        let calendar = Calendar.current
        if date < calendar.startOfDay(for: Date()) {
            return RemindersColors.overdue
        } else if calendar.isDateInToday(date) {
            return RemindersColors.today
        }
        return RemindersColors.textSecondary
    }
}

// MARK: - Task Row with Drag Handle

struct ReorderableTaskRow: View {
    @Binding var task: Task
    let listColor: Color
    let onToggle: () -> Void
    let onTap: () -> Void

    var body: some View {
        HStack(spacing: RemindersKit.Spacing.sm) {
            // Drag handle
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(RemindersColors.textTertiary)
                .frame(width: 24)

            // Task content
            CompactTaskRow(
                task: $task,
                listColor: listColor,
                onToggle: onToggle,
                onTap: onTap
            )
        }
    }
}

// MARK: - Preview

#Preview("Task Row View") {
    struct PreviewWrapper: View {
        @State private var task1 = Task(
            title: "Review project proposal",
            notes: "Check the budget section carefully and provide feedback",
            dueDate: Date(),
            priority: .high,
            flag: true,
            redBeaconEnabled: true,
            listId: "sample"
        )

        @State private var task2 = Task(
            title: "Send weekly report",
            dueDate: Calendar.current.date(byAdding: .day, value: 1, to: Date()),
            dueTime: Date(),
            repeatRule: .weekly(),
            priority: .medium,
            subtasks: ["subtask1", "subtask2"],
            listId: "sample"
        )

        @State private var task3 = Task(
            title: "Buy groceries",
            notes: "Milk, eggs, bread",
            dueDate: Calendar.current.date(byAdding: .day, value: -1, to: Date()),
            listId: "sample"
        )

        @State private var task4 = Task(
            title: "Completed task",
            completedAt: Date(),
            listId: "sample"
        )

        @State private var task5 = Task(
            title: "Low priority task",
            priority: .low,
            mirrorToCalendarEnabled: true,
            listId: "sample"
        )

        var body: some View {
            ScrollView {
                VStack(spacing: 1) {
                    TaskRowView(
                        task: $task1,
                        listColor: RemindersColors.accentBlue,
                        onToggle: { task1.toggleCompletion() },
                        onFlag: { task1.toggleFlag() },
                        onDelete: {},
                        onTap: {}
                    )

                    TaskRowView(
                        task: $task2,
                        listColor: RemindersColors.accentOrange,
                        onToggle: { task2.toggleCompletion() },
                        onFlag: { task2.toggleFlag() },
                        onDelete: {},
                        onTap: {}
                    )

                    TaskRowView(
                        task: $task3,
                        listColor: RemindersColors.accentRed,
                        onToggle: { task3.toggleCompletion() },
                        onFlag: { task3.toggleFlag() },
                        onDelete: {},
                        onTap: {}
                    )

                    TaskRowView(
                        task: $task4,
                        listColor: RemindersColors.accentGreen,
                        onToggle: { task4.toggleCompletion() },
                        onFlag: { task4.toggleFlag() },
                        onDelete: {},
                        onTap: {}
                    )

                    TaskRowView(
                        task: $task5,
                        listColor: RemindersColors.accentPurple,
                        onToggle: { task5.toggleCompletion() },
                        onFlag: { task5.toggleFlag() },
                        onDelete: {},
                        onTap: {}
                    )
                }
                .clipShape(RoundedRectangle(cornerRadius: RemindersKit.Radius.lg))
                .padding()

                // Compact rows
                VStack(spacing: 0) {
                    Text("Compact Rows")
                        .font(RemindersTypography.headline)
                        .foregroundColor(RemindersColors.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()

                    VStack(spacing: 0) {
                        CompactTaskRow(
                            task: $task1,
                            listColor: RemindersColors.accentBlue,
                            onToggle: {},
                            onTap: {}
                        )
                        .padding(.horizontal)

                        Divider()
                            .background(RemindersColors.separator)
                            .padding(.leading, 54)

                        CompactTaskRow(
                            task: $task2,
                            listColor: RemindersColors.accentOrange,
                            onToggle: {},
                            onTap: {}
                        )
                        .padding(.horizontal)
                    }
                    .padding(.vertical, RemindersKit.Spacing.sm)
                    .background(RemindersColors.backgroundSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: RemindersKit.Radius.lg))
                    .padding(.horizontal)
                }
            }
            .background(RemindersColors.background)
        }
    }

    return PreviewWrapper()
}
