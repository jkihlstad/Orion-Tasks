//
//  TaskDetailView.swift
//  TasksApp
//
//  Full task editor view matching Apple Reminders style
//

import SwiftUI

// MARK: - Task Detail View

struct TaskDetailView: View {

    // MARK: - Properties

    @Binding var task: Task
    let lists: [TaskList]
    let tags: [Tag]
    let onSave: (Task) -> Void
    let onDelete: () -> Void

    // MARK: - State

    @State private var editedTask: Task
    @State private var showDeleteConfirmation = false
    @State private var showListPicker = false
    @State private var showTagPicker = false
    @State private var subtaskObjects: [Task] = []

    // Date/Time state
    @State private var hasDate = false
    @State private var hasTime = false
    @State private var hasRepeat = false

    // MARK: - Environment

    @Environment(\.dismiss) private var dismiss

    // MARK: - Initialization

    init(
        task: Binding<Task>,
        lists: [TaskList] = TaskList.sampleLists,
        tags: [Tag] = Tag.sampleTags,
        onSave: @escaping (Task) -> Void = { _ in },
        onDelete: @escaping () -> Void = {}
    ) {
        self._task = task
        self.lists = lists
        self.tags = tags
        self.onSave = onSave
        self.onDelete = onDelete
        self._editedTask = State(initialValue: task.wrappedValue)
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: RemindersKit.Spacing.lg) {
                    // Title and Notes
                    titleNotesSection

                    // Date & Time
                    dateTimeSection

                    // Repeat
                    repeatSection

                    // Priority
                    prioritySection

                    // Tags
                    tagsSection

                    // Flag
                    flagSection

                    // List
                    listSection

                    // Red Beacon
                    beaconSection

                    // Calendar Mirror
                    calendarMirrorSection

                    // Subtasks
                    subtasksSection

                    // Attachments
                    attachmentsSection

                    // Delete button
                    deleteButton
                }
                .padding(RemindersKit.Spacing.lg)
            }
            .background(RemindersColors.background)
            .navigationTitle("Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(RemindersColors.accentBlue)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        saveAndDismiss()
                    }
                    .fontWeight(.semibold)
                    .foregroundColor(RemindersColors.accentBlue)
                }
            }
            .toolbarBackground(RemindersColors.backgroundSecondary, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .onAppear {
            loadTaskState()
        }
        .sheet(isPresented: $showListPicker) {
            listPickerSheet
        }
        .sheet(isPresented: $showTagPicker) {
            tagPickerSheet
        }
        .alert("Delete Reminder", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                onDelete()
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to delete this reminder? This action cannot be undone.")
        }
    }

    // MARK: - Title and Notes Section

    private var titleNotesSection: some View {
        VStack(spacing: 0) {
            // Title
            HStack(spacing: RemindersKit.Spacing.md) {
                TaskCheckbox(
                    isChecked: Binding(
                        get: { editedTask.isCompleted },
                        set: { _ in editedTask.toggleCompletion() }
                    ),
                    color: currentListColor
                )

                TextField("Title", text: $editedTask.title, axis: .vertical)
                    .font(RemindersTypography.body)
                    .foregroundColor(RemindersColors.textPrimary)
                    .lineLimit(1...5)
            }
            .padding(RemindersKit.Spacing.md)

            Divider()
                .background(RemindersColors.separator)

            // Notes
            HStack(alignment: .top, spacing: RemindersKit.Spacing.md) {
                Color.clear
                    .frame(width: 22, height: 22)

                TextField("Notes", text: Binding(
                    get: { editedTask.notes ?? "" },
                    set: { editedTask.notes = $0.isEmpty ? nil : $0 }
                ), axis: .vertical)
                    .font(RemindersTypography.subheadline)
                    .foregroundColor(RemindersColors.textSecondary)
                    .lineLimit(1...10)
            }
            .padding(RemindersKit.Spacing.md)
        }
        .background(RemindersColors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: RemindersKit.Radius.lg))
    }

    // MARK: - Date & Time Section

    private var dateTimeSection: some View {
        DateTimePicker(
            date: $editedTask.dueDate,
            time: $editedTask.dueTime,
            hasDate: $hasDate,
            hasTime: $hasTime
        )
    }

    // MARK: - Repeat Section

    private var repeatSection: some View {
        RepeatRulePicker(
            repeatRule: $editedTask.repeatRule,
            isEnabled: $hasRepeat
        )
    }

    // MARK: - Priority Section

    private var prioritySection: some View {
        VStack(spacing: 0) {
            HStack {
                Label {
                    Text("Priority")
                        .font(RemindersTypography.body)
                        .foregroundColor(RemindersColors.textPrimary)
                } icon: {
                    ZStack {
                        RoundedRectangle(cornerRadius: RemindersKit.Radius.sm)
                            .fill(RemindersColors.accentOrange)
                            .frame(width: 30, height: 30)

                        Image(systemName: "exclamationmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)
                    }
                }

                Spacer()
            }
            .padding(RemindersKit.Spacing.md)

            Divider()
                .background(RemindersColors.separator)
                .padding(.leading, 54)

            PriorityPicker(selectedPriority: $editedTask.priority, style: .segmented)
                .padding(RemindersKit.Spacing.md)
        }
        .background(RemindersColors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: RemindersKit.Radius.lg))
    }

    // MARK: - Tags Section

    private var tagsSection: some View {
        VStack(spacing: 0) {
            Button {
                showTagPicker = true
            } label: {
                HStack {
                    Label {
                        Text("Tags")
                            .font(RemindersTypography.body)
                            .foregroundColor(RemindersColors.textPrimary)
                    } icon: {
                        ZStack {
                            RoundedRectangle(cornerRadius: RemindersKit.Radius.sm)
                                .fill(RemindersColors.accentCyan)
                                .frame(width: 30, height: 30)

                            Image(systemName: "tag.fill")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.white)
                        }
                    }

                    Spacer()

                    if editedTask.tags.isEmpty {
                        Text("None")
                            .font(RemindersTypography.body)
                            .foregroundColor(RemindersColors.textSecondary)
                    } else {
                        Text("\(editedTask.tags.count)")
                            .font(RemindersTypography.body)
                            .foregroundColor(RemindersColors.accentBlue)
                    }

                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(RemindersColors.textTertiary)
                }
                .padding(RemindersKit.Spacing.md)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Show selected tags
            if !editedTask.tags.isEmpty {
                Divider()
                    .background(RemindersColors.separator)
                    .padding(.leading, 54)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: RemindersKit.Spacing.sm) {
                        ForEach(selectedTags) { tag in
                            TagChip(tag: tag) {
                                editedTask.removeTag(tag.id)
                            }
                        }
                    }
                    .padding(.horizontal, RemindersKit.Spacing.md)
                    .padding(.vertical, RemindersKit.Spacing.sm)
                }
            }
        }
        .background(RemindersColors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: RemindersKit.Radius.lg))
    }

    // MARK: - Flag Section

    private var flagSection: some View {
        toggleRow(
            icon: "flag.fill",
            iconColor: RemindersColors.accentOrange,
            title: "Flag",
            isOn: $editedTask.flag
        )
    }

    // MARK: - List Section

    private var listSection: some View {
        Button {
            showListPicker = true
        } label: {
            HStack {
                Label {
                    Text("List")
                        .font(RemindersTypography.body)
                        .foregroundColor(RemindersColors.textPrimary)
                } icon: {
                    ZStack {
                        RoundedRectangle(cornerRadius: RemindersKit.Radius.sm)
                            .fill(currentListColor)
                            .frame(width: 30, height: 30)

                        Image(systemName: currentList?.icon.rawValue ?? "list.bullet")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                    }
                }

                Spacer()

                Text(currentList?.name ?? "Unknown")
                    .font(RemindersTypography.body)
                    .foregroundColor(RemindersColors.accentBlue)

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(RemindersColors.textTertiary)
            }
            .padding(RemindersKit.Spacing.md)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(RemindersColors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: RemindersKit.Radius.lg))
    }

    // MARK: - Red Beacon Section

    private var beaconSection: some View {
        VStack(spacing: 0) {
            toggleRow(
                icon: "smallcircle.filled.circle",
                iconColor: RemindersColors.accentRed,
                title: "Red Beacon",
                isOn: $editedTask.redBeaconEnabled
            )

            if editedTask.redBeaconEnabled {
                Divider()
                    .background(RemindersColors.separator)
                    .padding(.leading, 54)

                HStack {
                    Text("The red beacon makes this reminder stand out with a pulsing red indicator, helping you focus on urgent tasks.")
                        .font(RemindersTypography.caption1)
                        .foregroundColor(RemindersColors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(RemindersKit.Spacing.md)
                .padding(.leading, 42)
            }
        }
        .background(RemindersColors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: RemindersKit.Radius.lg))
    }

    // MARK: - Calendar Mirror Section

    private var calendarMirrorSection: some View {
        VStack(spacing: 0) {
            toggleRow(
                icon: "calendar.badge.clock",
                iconColor: RemindersColors.accentPurple,
                title: "Mirror to Calendar",
                isOn: $editedTask.mirrorToCalendarEnabled
            )

            if editedTask.mirrorToCalendarEnabled {
                Divider()
                    .background(RemindersColors.separator)
                    .padding(.leading, 54)

                HStack {
                    Text("This reminder will appear as an event in your calendar app, making it visible alongside your other appointments.")
                        .font(RemindersTypography.caption1)
                        .foregroundColor(RemindersColors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(RemindersKit.Spacing.md)
                .padding(.leading, 42)
            }
        }
        .background(RemindersColors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: RemindersKit.Radius.lg))
    }

    // MARK: - Subtasks Section

    private var subtasksSection: some View {
        SubtaskSection(
            subtasks: $subtaskObjects,
            parentTaskId: editedTask.id,
            listId: editedTask.listId,
            listColor: currentListColor,
            onSubtaskToggle: { subtask in
                if let index = subtaskObjects.firstIndex(where: { $0.id == subtask.id }) {
                    subtaskObjects[index].toggleCompletion()
                }
            },
            onSubtaskDelete: { subtask in
                subtaskObjects.removeAll { $0.id == subtask.id }
                editedTask.removeSubtask(subtask.id)
            },
            onSubtaskTap: { _ in }
        )
    }

    // MARK: - Attachments Section

    private var attachmentsSection: some View {
        VStack(spacing: 0) {
            HStack {
                Label {
                    Text("Attachments")
                        .font(RemindersTypography.body)
                        .foregroundColor(RemindersColors.textPrimary)
                } icon: {
                    ZStack {
                        RoundedRectangle(cornerRadius: RemindersKit.Radius.sm)
                            .fill(RemindersColors.textSecondary)
                            .frame(width: 30, height: 30)

                        Image(systemName: "paperclip")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                    }
                }

                Spacer()

                if !editedTask.attachments.isEmpty {
                    Text("\(editedTask.attachments.count)")
                        .font(RemindersTypography.body)
                        .foregroundColor(RemindersColors.textSecondary)
                }

                Button {
                    // Add attachment action
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 22))
                        .foregroundColor(currentListColor)
                }
            }
            .padding(RemindersKit.Spacing.md)

            // Attachment list
            if !editedTask.attachments.isEmpty {
                Divider()
                    .background(RemindersColors.separator)

                ForEach(editedTask.attachments) { attachment in
                    AttachmentRow(attachment: attachment) {
                        editedTask.removeAttachment(withId: attachment.id)
                    }

                    if attachment.id != editedTask.attachments.last?.id {
                        Divider()
                            .background(RemindersColors.separator)
                            .padding(.leading, 54)
                    }
                }
            }
        }
        .background(RemindersColors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: RemindersKit.Radius.lg))
    }

    // MARK: - Delete Button

    private var deleteButton: some View {
        Button {
            showDeleteConfirmation = true
        } label: {
            HStack {
                Spacer()
                Text("Delete Reminder")
                    .font(RemindersTypography.body)
                    .foregroundColor(RemindersColors.accentRed)
                Spacer()
            }
            .padding(RemindersKit.Spacing.md)
        }
        .buttonStyle(.plain)
        .background(RemindersColors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: RemindersKit.Radius.lg))
    }

    // MARK: - List Picker Sheet

    private var listPickerSheet: some View {
        NavigationStack {
            List {
                ForEach(lists) { list in
                    Button {
                        editedTask.listId = list.id
                        showListPicker = false
                    } label: {
                        HStack {
                            ZStack {
                                RoundedRectangle(cornerRadius: RemindersKit.Radius.sm)
                                    .fill(list.color.color)
                                    .frame(width: 30, height: 30)

                                Image(systemName: list.icon.rawValue)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.white)
                            }

                            Text(list.name)
                                .font(RemindersTypography.body)
                                .foregroundColor(RemindersColors.textPrimary)

                            Spacer()

                            if editedTask.listId == list.id {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(RemindersColors.accentBlue)
                            }
                        }
                    }
                    .listRowBackground(RemindersColors.backgroundSecondary)
                }
            }
            .remindersGroupedStyle()
            .navigationTitle("List")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        showListPicker = false
                    }
                    .foregroundColor(RemindersColors.accentBlue)
                }
            }
        }
        .presentationDetents([.medium])
        .remindersSheet()
    }

    // MARK: - Tag Picker Sheet

    private var tagPickerSheet: some View {
        NavigationStack {
            List {
                ForEach(tags) { tag in
                    Button {
                        if editedTask.tags.contains(tag.id) {
                            editedTask.removeTag(tag.id)
                        } else {
                            editedTask.addTag(tag.id)
                        }
                    } label: {
                        HStack {
                            Circle()
                                .fill(tag.color.color)
                                .frame(width: 12, height: 12)

                            Text(tag.name)
                                .font(RemindersTypography.body)
                                .foregroundColor(RemindersColors.textPrimary)

                            Spacer()

                            if editedTask.tags.contains(tag.id) {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(RemindersColors.accentBlue)
                            }
                        }
                    }
                    .listRowBackground(RemindersColors.backgroundSecondary)
                }
            }
            .remindersGroupedStyle()
            .navigationTitle("Tags")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        showTagPicker = false
                    }
                    .foregroundColor(RemindersColors.accentBlue)
                }
            }
        }
        .presentationDetents([.medium])
        .remindersSheet()
    }

    // MARK: - Helper Views

    @ViewBuilder
    private func toggleRow(icon: String, iconColor: Color, title: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Label {
                Text(title)
                    .font(RemindersTypography.body)
                    .foregroundColor(RemindersColors.textPrimary)
            } icon: {
                ZStack {
                    RoundedRectangle(cornerRadius: RemindersKit.Radius.sm)
                        .fill(iconColor)
                        .frame(width: 30, height: 30)

                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                }
            }

            Spacer()

            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(RemindersColors.accentBlue)
        }
        .padding(RemindersKit.Spacing.md)
        .background(RemindersColors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: RemindersKit.Radius.lg))
    }

    // MARK: - Computed Properties

    private var currentList: TaskList? {
        lists.first { $0.id == editedTask.listId }
    }

    private var currentListColor: Color {
        currentList?.color.color ?? RemindersColors.accentBlue
    }

    private var selectedTags: [Tag] {
        tags.filter { editedTask.tags.contains($0.id) }
    }

    // MARK: - Actions

    private func loadTaskState() {
        hasDate = editedTask.dueDate != nil
        hasTime = editedTask.dueTime != nil
        hasRepeat = editedTask.repeatRule != nil

        // Load subtasks (in real app, fetch from repository)
        subtaskObjects = editedTask.subtasks.map { id in
            Task(id: id, title: "Subtask \(id.prefix(4))", listId: editedTask.listId, parentId: editedTask.id)
        }
    }

    private func saveAndDismiss() {
        // Update subtask IDs
        editedTask.subtasks = subtaskObjects.map { $0.id }

        // Sync date/time state
        if !hasDate {
            editedTask.dueDate = nil
            editedTask.dueTime = nil
        }
        if !hasTime {
            editedTask.dueTime = nil
        }
        if !hasRepeat {
            editedTask.repeatRule = nil
        }

        editedTask.updatedAt = Date()
        task = editedTask
        onSave(editedTask)
        dismiss()
    }
}

// MARK: - Tag Chip

struct TagChip: View {
    let tag: Tag
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: RemindersKit.Spacing.xxs) {
            Circle()
                .fill(tag.color.color)
                .frame(width: 8, height: 8)

            Text(tag.name)
                .font(RemindersTypography.caption1)
                .foregroundColor(tag.color.color)

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundColor(RemindersColors.textSecondary)
            }
        }
        .padding(.horizontal, RemindersKit.Spacing.sm)
        .padding(.vertical, RemindersKit.Spacing.xxs)
        .background(tag.color.backgroundColor)
        .clipShape(Capsule())
    }
}

// MARK: - Attachment Row

struct AttachmentRow: View {
    let attachment: AttachmentRef
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: RemindersKit.Spacing.md) {
            // Icon
            ZStack {
                RoundedRectangle(cornerRadius: RemindersKit.Radius.sm)
                    .fill(RemindersColors.backgroundTertiary)
                    .frame(width: 40, height: 40)

                Image(systemName: attachment.mediaType.symbolName)
                    .font(.system(size: 16))
                    .foregroundColor(RemindersColors.textSecondary)
            }

            // Details
            VStack(alignment: .leading, spacing: 2) {
                Text(attachment.originalFilename ?? "Attachment")
                    .font(RemindersTypography.subheadline)
                    .foregroundColor(RemindersColors.textPrimary)
                    .lineLimit(1)

                if let size = attachment.formattedFileSize {
                    Text(size)
                        .font(RemindersTypography.caption2)
                        .foregroundColor(RemindersColors.textSecondary)
                }
            }

            Spacer()

            // Delete button
            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(.system(size: 14))
                    .foregroundColor(RemindersColors.accentRed)
            }
        }
        .padding(RemindersKit.Spacing.md)
    }
}

// MARK: - Preview

#Preview("Task Detail View") {
    struct PreviewWrapper: View {
        @State private var task = Task(
            title: "Review project proposal",
            notes: "Check the budget section carefully and provide feedback by end of week",
            dueDate: Date(),
            dueTime: Date(),
            repeatRule: .weekly(),
            priority: .high,
            tags: ["work", "urgent"],
            flag: true,
            subtasks: ["sub1", "sub2"],
            attachments: [.sample],
            redBeaconEnabled: true,
            mirrorToCalendarEnabled: true,
            listId: "work"
        )

        var body: some View {
            TaskDetailView(
                task: $task,
                lists: TaskList.sampleLists,
                tags: Tag.sampleTags,
                onSave: { _ in },
                onDelete: {}
            )
        }
    }

    return PreviewWrapper()
}
