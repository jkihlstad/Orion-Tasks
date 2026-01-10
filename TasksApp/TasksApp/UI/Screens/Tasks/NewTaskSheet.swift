//
//  NewTaskSheet.swift
//  TasksApp
//
//  Quick task creation sheet matching Apple Reminders style
//

import SwiftUI

// MARK: - New Task Sheet

struct NewTaskSheet: View {

    // MARK: - Properties

    @Binding var isPresented: Bool
    let listId: String
    let listColor: Color
    let listName: String
    let onSave: (Task) -> Void

    // MARK: - State

    @State private var title = ""
    @State private var notes = ""
    @State private var dueDate: Date? = nil
    @State private var dueTime: Date? = nil
    @State private var hasDate = false
    @State private var hasTime = false
    @State private var priority: Priority = .none
    @State private var flag = false
    @State private var showDatePicker = false
    @State private var showPriorityPicker = false
    @State private var showListPicker = false

    @FocusState private var isTitleFocused: Bool

    // MARK: - Environment

    @Environment(\.dismiss) private var dismiss

    // MARK: - Body

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Title input
                titleSection

                Divider()
                    .background(RemindersColors.separator)

                // Notes input
                notesSection

                Divider()
                    .background(RemindersColors.separator)

                // Quick options
                quickOptionsSection

                Spacer()
            }
            .background(RemindersColors.backgroundElevated)
            .navigationTitle("New Reminder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                        isPresented = false
                    }
                    .foregroundColor(RemindersColors.accentBlue)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        saveTask()
                    }
                    .fontWeight(.semibold)
                    .foregroundColor(canSave ? RemindersColors.accentBlue : RemindersColors.textTertiary)
                    .disabled(!canSave)
                }
            }
            .toolbarBackground(RemindersColors.backgroundSecondary, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .onAppear {
            isTitleFocused = true
        }
        .sheet(isPresented: $showDatePicker) {
            datePickerSheet
        }
        .remindersSheet()
    }

    // MARK: - Title Section

    private var titleSection: some View {
        HStack(spacing: RemindersKit.Spacing.md) {
            // Checkbox preview
            Circle()
                .stroke(listColor, lineWidth: 2)
                .frame(width: 22, height: 22)

            TextField("Title", text: $title, axis: .vertical)
                .font(RemindersTypography.body)
                .foregroundColor(RemindersColors.textPrimary)
                .focused($isTitleFocused)
                .submitLabel(.next)
                .lineLimit(1...3)
        }
        .padding(RemindersKit.Spacing.lg)
    }

    // MARK: - Notes Section

    private var notesSection: some View {
        HStack(alignment: .top, spacing: RemindersKit.Spacing.md) {
            // Spacer to align with title
            Color.clear
                .frame(width: 22, height: 22)

            TextField("Notes", text: $notes, axis: .vertical)
                .font(RemindersTypography.subheadline)
                .foregroundColor(RemindersColors.textSecondary)
                .lineLimit(1...5)
        }
        .padding(RemindersKit.Spacing.lg)
    }

    // MARK: - Quick Options Section

    private var quickOptionsSection: some View {
        VStack(spacing: 0) {
            // Date quick options
            dateQuickOptions

            Divider()
                .background(RemindersColors.separator)

            // Bottom row: Priority, Flag, List
            HStack(spacing: RemindersKit.Spacing.lg) {
                // Date button
                QuickOptionButton(
                    icon: "calendar",
                    label: hasDate ? formattedDate : "Date",
                    color: hasDate ? RemindersColors.accentRed : RemindersColors.textSecondary,
                    isActive: hasDate
                ) {
                    showDatePicker = true
                }

                // Priority button
                Menu {
                    ForEach(Priority.allCases, id: \.self) { p in
                        Button {
                            priority = p
                        } label: {
                            HStack {
                                if p != .none {
                                    Image(systemName: p.symbolName)
                                }
                                Text(p.displayName)
                                if priority == p {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    QuickOptionButtonContent(
                        icon: priority != .none ? priority.symbolName : "flag",
                        label: priority.displayName,
                        color: priority.color,
                        isActive: priority != .none
                    )
                }

                // Flag button
                QuickOptionButton(
                    icon: flag ? "flag.fill" : "flag",
                    label: "Flag",
                    color: flag ? RemindersColors.accentOrange : RemindersColors.textSecondary,
                    isActive: flag
                ) {
                    flag.toggle()

                    // Haptic feedback
                    let generator = UIImpactFeedbackGenerator(style: .light)
                    generator.impactOccurred()
                }

                Spacer()

                // List indicator
                HStack(spacing: RemindersKit.Spacing.xs) {
                    Circle()
                        .fill(listColor)
                        .frame(width: 10, height: 10)

                    Text(listName)
                        .font(RemindersTypography.caption1)
                        .foregroundColor(RemindersColors.textSecondary)
                }
            }
            .padding(RemindersKit.Spacing.lg)
        }
    }

    // MARK: - Date Quick Options

    private var dateQuickOptions: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: RemindersKit.Spacing.sm) {
                QuickDateChip(title: "Today", icon: "sun.max.fill", color: RemindersColors.today) {
                    setDate(Date())
                }

                QuickDateChip(title: "Tomorrow", icon: "sunrise.fill", color: RemindersColors.accentOrange) {
                    setDate(Calendar.current.date(byAdding: .day, value: 1, to: Date()))
                }

                QuickDateChip(title: "Weekend", icon: "sparkles", color: RemindersColors.accentPurple) {
                    let calendar = Calendar.current
                    let weekday = calendar.component(.weekday, from: Date())
                    let daysUntilSaturday = (7 - weekday + 7) % 7
                    setDate(calendar.date(byAdding: .day, value: daysUntilSaturday == 0 ? 7 : daysUntilSaturday, to: Date()))
                }

                QuickDateChip(title: "Next Week", icon: "calendar", color: RemindersColors.accentCyan) {
                    setDate(Calendar.current.date(byAdding: .day, value: 7, to: Date()))
                }

                if hasDate {
                    QuickDateChip(title: "Clear", icon: "xmark.circle.fill", color: RemindersColors.textSecondary) {
                        clearDate()
                    }
                }
            }
            .padding(.horizontal, RemindersKit.Spacing.lg)
            .padding(.vertical, RemindersKit.Spacing.md)
        }
    }

    // MARK: - Date Picker Sheet

    private var datePickerSheet: some View {
        NavigationStack {
            DateTimePicker(
                date: $dueDate,
                time: $dueTime,
                hasDate: $hasDate,
                hasTime: $hasTime,
                showQuickOptions: false
            )
            .padding()
            .background(RemindersColors.background)
            .navigationTitle("Date & Time")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        showDatePicker = false
                    }
                    .foregroundColor(RemindersColors.accentBlue)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .remindersSheet()
    }

    // MARK: - Computed Properties

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var formattedDate: String {
        guard let date = dueDate else { return "" }
        let calendar = Calendar.current

        if calendar.isDateInToday(date) {
            return "Today"
        } else if calendar.isDateInTomorrow(date) {
            return "Tomorrow"
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }

    // MARK: - Actions

    private func setDate(_ date: Date?) {
        withAnimation(RemindersKit.Animation.quick) {
            dueDate = date
            hasDate = date != nil
        }

        // Haptic feedback
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
    }

    private func clearDate() {
        withAnimation(RemindersKit.Animation.quick) {
            dueDate = nil
            dueTime = nil
            hasDate = false
            hasTime = false
        }
    }

    private func saveTask() {
        let task = Task(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            notes: notes.isEmpty ? nil : notes.trimmingCharacters(in: .whitespacesAndNewlines),
            dueDate: dueDate,
            dueTime: dueTime,
            priority: priority,
            flag: flag,
            listId: listId
        )

        onSave(task)
        dismiss()
        isPresented = false
    }
}

// MARK: - Quick Option Button

private struct QuickOptionButton: View {
    let icon: String
    let label: String
    let color: Color
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            QuickOptionButtonContent(
                icon: icon,
                label: label,
                color: color,
                isActive: isActive
            )
        }
        .buttonStyle(.plain)
    }
}

private struct QuickOptionButtonContent: View {
    let icon: String
    let label: String
    let color: Color
    let isActive: Bool

    var body: some View {
        VStack(spacing: RemindersKit.Spacing.xxs) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: isActive ? .semibold : .regular))
                .foregroundColor(color)

            Text(label)
                .font(RemindersTypography.caption2)
                .foregroundColor(isActive ? color : RemindersColors.textSecondary)
        }
        .frame(minWidth: 50)
    }
}

// MARK: - Quick Date Chip

private struct QuickDateChip: View {
    let title: String
    let icon: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: RemindersKit.Spacing.xs) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))

                Text(title)
                    .font(RemindersTypography.caption1Bold)
            }
            .foregroundColor(color)
            .padding(.horizontal, RemindersKit.Spacing.md)
            .padding(.vertical, RemindersKit.Spacing.sm)
            .background(color.opacity(0.15))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Inline New Task Row

/// Inline task creation row for adding tasks directly in a list
struct InlineNewTaskRow: View {
    @Binding var isActive: Bool
    let listId: String
    let listColor: Color
    let onSave: (Task) -> Void

    @State private var title = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: RemindersKit.Spacing.checkboxContent) {
            // Empty checkbox
            Circle()
                .stroke(RemindersColors.checkboxBorder, lineWidth: 2)
                .frame(width: 22, height: 22)

            if isActive {
                TextField("New Reminder", text: $title)
                    .font(RemindersTypography.body)
                    .foregroundColor(RemindersColors.textPrimary)
                    .focused($isFocused)
                    .submitLabel(.done)
                    .onSubmit {
                        saveTask()
                    }
            } else {
                Text("New Reminder")
                    .font(RemindersTypography.body)
                    .foregroundColor(RemindersColors.textTertiary)
            }

            Spacer()

            if isActive && !title.isEmpty {
                Button {
                    saveTask()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(listColor)
                }
            }
        }
        .padding(.vertical, RemindersKit.Spacing.listRowVertical)
        .padding(.horizontal, RemindersKit.Spacing.listRowHorizontal)
        .background(RemindersColors.backgroundSecondary)
        .contentShape(Rectangle())
        .onTapGesture {
            if !isActive {
                isActive = true
                isFocused = true
            }
        }
        .onChange(of: isActive) { _, newValue in
            if newValue {
                isFocused = true
            } else {
                title = ""
            }
        }
    }

    private func saveTask() {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        let task = Task(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            listId: listId
        )

        onSave(task)

        // Reset for next task
        title = ""
        isFocused = true
    }
}

// MARK: - Preview

#Preview("New Task Sheet") {
    struct PreviewWrapper: View {
        @State private var isPresented = true
        @State private var isInlineActive = false

        var body: some View {
            ZStack {
                RemindersColors.background
                    .ignoresSafeArea()

                VStack(spacing: 24) {
                    // Inline row preview
                    VStack(spacing: 0) {
                        Text("Inline New Task")
                            .font(RemindersTypography.headline)
                            .foregroundColor(RemindersColors.textPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()

                        InlineNewTaskRow(
                            isActive: $isInlineActive,
                            listId: "sample",
                            listColor: RemindersColors.accentBlue
                        ) { task in
                            print("Created task: \(task.title)")
                        }
                        .clipShape(RoundedRectangle(cornerRadius: RemindersKit.Radius.lg))
                        .padding(.horizontal)
                    }

                    Button("Show New Task Sheet") {
                        isPresented = true
                    }
                    .font(RemindersTypography.button)
                    .foregroundColor(RemindersColors.accentBlue)

                    Spacer()
                }
            }
            .sheet(isPresented: $isPresented) {
                NewTaskSheet(
                    isPresented: $isPresented,
                    listId: "sample",
                    listColor: RemindersColors.accentBlue,
                    listName: "Personal"
                ) { task in
                    print("Created task: \(task.title)")
                }
            }
        }
    }

    return PreviewWrapper()
}
