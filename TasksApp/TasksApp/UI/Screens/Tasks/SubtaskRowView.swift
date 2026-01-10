//
//  SubtaskRowView.swift
//  TasksApp
//
//  Subtask row component matching Apple Reminders style
//

import SwiftUI

// MARK: - Subtask Row View

struct SubtaskRowView: View {

    // MARK: - Properties

    @Binding var subtask: Task
    let listColor: Color
    let onToggle: () -> Void
    let onDelete: () -> Void
    let onTap: () -> Void

    // MARK: - State

    @State private var isEditing = false
    @FocusState private var isTitleFocused: Bool

    // MARK: - Initialization

    init(
        subtask: Binding<Task>,
        listColor: Color = RemindersColors.accentBlue,
        onToggle: @escaping () -> Void = {},
        onDelete: @escaping () -> Void = {},
        onTap: @escaping () -> Void = {}
    ) {
        self._subtask = subtask
        self.listColor = listColor
        self.onToggle = onToggle
        self.onDelete = onDelete
        self.onTap = onTap
    }

    // MARK: - Body

    var body: some View {
        HStack(spacing: RemindersKit.Spacing.checkboxContent) {
            // Subtask checkbox (smaller)
            SubtaskCheckbox(
                isChecked: Binding(
                    get: { subtask.isCompleted },
                    set: { _ in onToggle() }
                ),
                color: listColor,
                onToggle: onToggle
            )

            // Title
            if isEditing {
                TextField("Subtask", text: $subtask.title)
                    .font(RemindersTypography.subheadline)
                    .foregroundColor(subtask.isCompleted ? RemindersColors.textSecondary : RemindersColors.textPrimary)
                    .focused($isTitleFocused)
                    .onSubmit {
                        isEditing = false
                    }
            } else {
                Text(subtask.title)
                    .font(RemindersTypography.subheadline)
                    .foregroundColor(subtask.isCompleted ? RemindersColors.textSecondary : RemindersColors.textPrimary)
                    .strikethrough(subtask.isCompleted, color: RemindersColors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        onTap()
                    }
                    .onLongPressGesture {
                        isEditing = true
                        isTitleFocused = true
                    }
            }

            Spacer()
        }
        .padding(.vertical, RemindersKit.Spacing.xs)
        .padding(.leading, RemindersKit.Spacing.xl) // Indent for subtasks
        .contentShape(Rectangle())
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash.fill")
            }
        }
    }
}

// MARK: - Subtask Section

struct SubtaskSection: View {

    // MARK: - Properties

    @Binding var subtasks: [Task]
    let parentTaskId: String
    let listId: String
    let listColor: Color
    let onSubtaskToggle: (Task) -> Void
    let onSubtaskDelete: (Task) -> Void
    let onSubtaskTap: (Task) -> Void

    // MARK: - State

    @State private var newSubtaskTitle = ""
    @State private var isAddingSubtask = false
    @FocusState private var isNewSubtaskFocused: Bool

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Section header
            HStack {
                Label {
                    Text("Subtasks")
                        .font(RemindersTypography.headline)
                        .foregroundColor(RemindersColors.textPrimary)
                } icon: {
                    Image(systemName: "checklist")
                        .foregroundColor(listColor)
                }

                Spacer()

                if !subtasks.isEmpty {
                    Text("\(completedCount)/\(subtasks.count)")
                        .font(RemindersTypography.caption1)
                        .foregroundColor(RemindersColors.textSecondary)
                }

                Button {
                    withAnimation(RemindersKit.Animation.quick) {
                        isAddingSubtask = true
                        isNewSubtaskFocused = true
                    }
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 22))
                        .foregroundColor(listColor)
                }
            }
            .padding(RemindersKit.Spacing.md)

            // Subtasks list
            if !subtasks.isEmpty || isAddingSubtask {
                Divider()
                    .background(RemindersColors.separator)

                VStack(spacing: 0) {
                    ForEach($subtasks) { $subtask in
                        SubtaskRowView(
                            subtask: $subtask,
                            listColor: listColor,
                            onToggle: { onSubtaskToggle(subtask) },
                            onDelete: { onSubtaskDelete(subtask) },
                            onTap: { onSubtaskTap(subtask) }
                        )

                        if subtask.id != subtasks.last?.id || isAddingSubtask {
                            Divider()
                                .background(RemindersColors.separator)
                                .padding(.leading, 54)
                        }
                    }

                    // New subtask input
                    if isAddingSubtask {
                        newSubtaskRow
                    }
                }
            }

            // Empty state / Add button
            if subtasks.isEmpty && !isAddingSubtask {
                Button {
                    withAnimation(RemindersKit.Animation.quick) {
                        isAddingSubtask = true
                        isNewSubtaskFocused = true
                    }
                } label: {
                    HStack {
                        Image(systemName: "plus")
                            .font(.system(size: 14, weight: .medium))

                        Text("Add Subtask")
                            .font(RemindersTypography.body)
                    }
                    .foregroundColor(listColor)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(RemindersKit.Spacing.md)
                }
                .buttonStyle(.plain)
            }
        }
        .background(RemindersColors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: RemindersKit.Radius.lg))
    }

    // MARK: - New Subtask Row

    private var newSubtaskRow: some View {
        HStack(spacing: RemindersKit.Spacing.checkboxContent) {
            // Empty checkbox placeholder
            Circle()
                .stroke(RemindersColors.checkboxBorder, lineWidth: 1.5)
                .frame(width: 18, height: 18)

            TextField("New Subtask", text: $newSubtaskTitle)
                .font(RemindersTypography.subheadline)
                .foregroundColor(RemindersColors.textPrimary)
                .focused($isNewSubtaskFocused)
                .onSubmit {
                    addSubtask()
                }

            Button {
                addSubtask()
            } label: {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 22))
                    .foregroundColor(newSubtaskTitle.isEmpty ? RemindersColors.textTertiary : listColor)
            }
            .disabled(newSubtaskTitle.isEmpty)

            Button {
                cancelAddSubtask()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 22))
                    .foregroundColor(RemindersColors.textSecondary)
            }
        }
        .padding(.vertical, RemindersKit.Spacing.xs)
        .padding(.horizontal, RemindersKit.Spacing.md)
        .padding(.leading, RemindersKit.Spacing.xl)
    }

    // MARK: - Computed Properties

    private var completedCount: Int {
        subtasks.filter { $0.isCompleted }.count
    }

    // MARK: - Actions

    private func addSubtask() {
        guard !newSubtaskTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        let newSubtask = Task(
            title: newSubtaskTitle.trimmingCharacters(in: .whitespacesAndNewlines),
            listId: listId,
            parentId: parentTaskId
        )

        withAnimation(RemindersKit.Animation.quick) {
            subtasks.append(newSubtask)
            newSubtaskTitle = ""
        }

        // Keep focus for adding more
        isNewSubtaskFocused = true
    }

    private func cancelAddSubtask() {
        withAnimation(RemindersKit.Animation.quick) {
            newSubtaskTitle = ""
            isAddingSubtask = false
        }
    }
}

// MARK: - Compact Subtask List (for task row)

struct CompactSubtaskList: View {
    let subtasks: [Task]
    let maxVisible: Int

    init(subtasks: [Task], maxVisible: Int = 3) {
        self.subtasks = subtasks
        self.maxVisible = maxVisible
    }

    var body: some View {
        if !subtasks.isEmpty {
            VStack(alignment: .leading, spacing: RemindersKit.Spacing.xxs) {
                ForEach(Array(subtasks.prefix(maxVisible))) { subtask in
                    HStack(spacing: RemindersKit.Spacing.xs) {
                        Image(systemName: subtask.isCompleted ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 10))
                            .foregroundColor(subtask.isCompleted ? RemindersColors.textTertiary : RemindersColors.textSecondary)

                        Text(subtask.title)
                            .font(RemindersTypography.caption1)
                            .foregroundColor(subtask.isCompleted ? RemindersColors.textTertiary : RemindersColors.textSecondary)
                            .strikethrough(subtask.isCompleted)
                            .lineLimit(1)
                    }
                }

                if subtasks.count > maxVisible {
                    Text("+\(subtasks.count - maxVisible) more")
                        .font(RemindersTypography.caption2)
                        .foregroundColor(RemindersColors.textTertiary)
                }
            }
        }
    }
}

// MARK: - Preview

#Preview("Subtask Row") {
    struct PreviewWrapper: View {
        @State private var subtask1 = Task(
            title: "Buy groceries",
            listId: "sample"
        )
        @State private var subtask2 = Task(
            title: "Call the bank",
            completedAt: Date(),
            listId: "sample"
        )
        @State private var subtasks: [Task] = [
            Task(title: "Research options", listId: "sample"),
            Task(title: "Compare prices", listId: "sample"),
            Task(title: "Make decision", completedAt: Date(), listId: "sample")
        ]

        var body: some View {
            ScrollView {
                VStack(spacing: 24) {
                    // Individual rows
                    Group {
                        Text("Subtask Rows")
                            .font(RemindersTypography.headline)
                            .foregroundColor(RemindersColors.textPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        VStack(spacing: 0) {
                            SubtaskRowView(
                                subtask: $subtask1,
                                listColor: RemindersColors.accentBlue
                            )

                            Divider()
                                .background(RemindersColors.separator)
                                .padding(.leading, 54)

                            SubtaskRowView(
                                subtask: $subtask2,
                                listColor: RemindersColors.accentBlue
                            )
                        }
                        .background(RemindersColors.backgroundSecondary)
                        .clipShape(RoundedRectangle(cornerRadius: RemindersKit.Radius.lg))
                    }

                    // Full section
                    Group {
                        Text("Subtask Section")
                            .font(RemindersTypography.headline)
                            .foregroundColor(RemindersColors.textPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        SubtaskSection(
                            subtasks: $subtasks,
                            parentTaskId: "parent-1",
                            listId: "sample",
                            listColor: RemindersColors.accentOrange,
                            onSubtaskToggle: { _ in },
                            onSubtaskDelete: { _ in },
                            onSubtaskTap: { _ in }
                        )
                    }

                    // Compact list
                    Group {
                        Text("Compact List")
                            .font(RemindersTypography.headline)
                            .foregroundColor(RemindersColors.textPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        CompactSubtaskList(subtasks: subtasks)
                            .padding()
                            .background(RemindersColors.backgroundSecondary)
                            .clipShape(RoundedRectangle(cornerRadius: RemindersKit.Radius.lg))
                    }

                    Spacer()
                }
                .padding()
            }
            .background(RemindersColors.background)
        }
    }

    return PreviewWrapper()
}
