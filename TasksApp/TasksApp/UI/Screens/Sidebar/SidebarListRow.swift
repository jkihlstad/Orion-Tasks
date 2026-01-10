//
//  SidebarListRow.swift
//  TasksApp
//
//  Sidebar list row component with icon, name, count badge, and swipe actions
//

import SwiftUI

// MARK: - Sidebar List Row

struct SidebarListRow: View {
    let list: TaskList
    let taskCount: Int
    let onDelete: () -> Void
    let onEdit: () -> Void

    @State private var showingDeleteConfirmation: Bool = false

    var body: some View {
        HStack(spacing: RemindersKit.Spacing.md) {
            // List Icon
            listIcon

            // List Name
            Text(list.name)
                .font(RemindersTypography.body)
                .foregroundColor(RemindersColors.textPrimary)
                .lineLimit(1)

            Spacer()

            // Task Count Badge
            if taskCount > 0 {
                taskCountBadge
            }

            // Chevron for navigation
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(RemindersColors.textTertiary)
        }
        .padding(.vertical, RemindersKit.Spacing.xxs)
        .contentShape(Rectangle())
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            deleteSwipeButton
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            editSwipeButton
        }
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            pinSwipeButton
        }
        .confirmationDialog(
            "Delete \"\(list.name)\"?",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete List", role: .destructive) {
                withAnimation(RemindersKit.Animation.standard) {
                    onDelete()
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will delete all reminders in this list. This action cannot be undone.")
        }
    }

    // MARK: - List Icon

    private var listIcon: some View {
        ZStack {
            Circle()
                .fill(list.color.color)
                .frame(width: RemindersKit.Size.listIcon, height: RemindersKit.Size.listIcon)

            Image(systemName: list.icon.rawValue)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
        }
    }

    // MARK: - Task Count Badge

    private var taskCountBadge: some View {
        Text("\(taskCount)")
            .font(RemindersTypography.badge)
            .foregroundColor(RemindersColors.textSecondary)
    }

    // MARK: - Swipe Actions

    private var deleteSwipeButton: some View {
        Button(role: .destructive) {
            showingDeleteConfirmation = true
        } label: {
            Label("Delete", systemImage: "trash.fill")
        }
        .tint(RemindersColors.accentRed)
    }

    private var editSwipeButton: some View {
        Button {
            onEdit()
        } label: {
            Label("Edit", systemImage: "pencil")
        }
        .tint(RemindersColors.accentOrange)
    }

    private var pinSwipeButton: some View {
        Button {
            // Handle pin action
        } label: {
            Label("Pin", systemImage: "pin.fill")
        }
        .tint(RemindersColors.accentYellow)
    }
}

// MARK: - Compact List Row (for smaller displays)

struct CompactListRow: View {
    let list: TaskList
    let taskCount: Int
    let isSelected: Bool

    var body: some View {
        HStack(spacing: RemindersKit.Spacing.sm) {
            // Icon
            ZStack {
                Circle()
                    .fill(list.color.color)
                    .frame(width: 24, height: 24)

                Image(systemName: list.icon.rawValue)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white)
            }

            // Name
            Text(list.name)
                .font(RemindersTypography.subheadline)
                .foregroundColor(RemindersColors.textPrimary)
                .lineLimit(1)

            Spacer()

            // Count
            if taskCount > 0 {
                Text("\(taskCount)")
                    .font(RemindersTypography.caption1)
                    .foregroundColor(RemindersColors.textTertiary)
            }
        }
        .padding(.horizontal, RemindersKit.Spacing.md)
        .padding(.vertical, RemindersKit.Spacing.sm)
        .background(isSelected ? RemindersColors.backgroundTertiary : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: RemindersKit.Radius.sm))
    }
}

// MARK: - List Row with Drag Handle (for reordering)

struct ReorderableListRow: View {
    let list: TaskList
    let taskCount: Int
    let isEditing: Bool
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: RemindersKit.Spacing.md) {
            // Delete button in edit mode
            if isEditing {
                Button {
                    withAnimation(RemindersKit.Animation.standard) {
                        onDelete()
                    }
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 22))
                        .foregroundColor(RemindersColors.accentRed)
                }
                .buttonStyle(.plain)
                .transition(.scale.combined(with: .opacity))
            }

            // List Icon
            ZStack {
                Circle()
                    .fill(list.color.color)
                    .frame(width: RemindersKit.Size.listIcon, height: RemindersKit.Size.listIcon)

                Image(systemName: list.icon.rawValue)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
            }

            // List Name
            Text(list.name)
                .font(RemindersTypography.body)
                .foregroundColor(RemindersColors.textPrimary)
                .lineLimit(1)

            Spacer()

            // Task Count
            if taskCount > 0 && !isEditing {
                Text("\(taskCount)")
                    .font(RemindersTypography.badge)
                    .foregroundColor(RemindersColors.textSecondary)
            }

            // Drag handle in edit mode
            if isEditing {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(RemindersColors.textTertiary)
                    .frame(width: 24)
                    .transition(.scale.combined(with: .opacity))
            } else {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(RemindersColors.textTertiary)
            }
        }
        .padding(.vertical, RemindersKit.Spacing.xxs)
        .contentShape(Rectangle())
        .animation(RemindersKit.Animation.standard, value: isEditing)
    }
}

// MARK: - List Info Row (shows more details)

struct ListInfoRow: View {
    let list: TaskList
    let taskCount: Int
    let completedCount: Int

    var body: some View {
        HStack(spacing: RemindersKit.Spacing.md) {
            // Large Icon
            ZStack {
                Circle()
                    .fill(list.color.color)
                    .frame(width: 44, height: 44)

                Image(systemName: list.icon.rawValue)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.white)
            }

            // List Details
            VStack(alignment: .leading, spacing: RemindersKit.Spacing.xxs) {
                Text(list.name)
                    .font(RemindersTypography.headline)
                    .foregroundColor(RemindersColors.textPrimary)

                HStack(spacing: RemindersKit.Spacing.sm) {
                    Label("\(taskCount)", systemImage: "circle")
                        .font(RemindersTypography.caption1)
                        .foregroundColor(RemindersColors.textSecondary)

                    Label("\(completedCount)", systemImage: "checkmark.circle.fill")
                        .font(RemindersTypography.caption1)
                        .foregroundColor(RemindersColors.accentGreen)
                }
            }

            Spacer()

            // Navigation indicator
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(RemindersColors.textTertiary)
        }
        .padding(.vertical, RemindersKit.Spacing.sm)
        .contentShape(Rectangle())
    }
}

// MARK: - Preview

#Preview("Sidebar List Row") {
    List {
        SidebarListRow(
            list: TaskList.sample,
            taskCount: 12,
            onDelete: { print("Delete") },
            onEdit: { print("Edit") }
        )

        SidebarListRow(
            list: TaskList(name: "Work", color: .blue, icon: .briefcase),
            taskCount: 5,
            onDelete: { print("Delete") },
            onEdit: { print("Edit") }
        )

        SidebarListRow(
            list: TaskList(name: "Shopping", color: .green, icon: .cart),
            taskCount: 0,
            onDelete: { print("Delete") },
            onEdit: { print("Edit") }
        )
    }
    .listStyle(.sidebar)
    .scrollContentBackground(.hidden)
    .background(RemindersColors.background)
    .preferredColorScheme(.dark)
}

#Preview("Compact List Row") {
    VStack(spacing: 4) {
        CompactListRow(
            list: TaskList.sample,
            taskCount: 12,
            isSelected: true
        )

        CompactListRow(
            list: TaskList(name: "Work", color: .blue, icon: .briefcase),
            taskCount: 5,
            isSelected: false
        )

        CompactListRow(
            list: TaskList(name: "Shopping", color: .green, icon: .cart),
            taskCount: 0,
            isSelected: false
        )
    }
    .padding()
    .background(RemindersColors.backgroundSecondary)
    .preferredColorScheme(.dark)
}

#Preview("Reorderable List Row") {
    VStack(spacing: 0) {
        ReorderableListRow(
            list: TaskList.sample,
            taskCount: 12,
            isEditing: false,
            onDelete: { }
        )
        .padding(.horizontal)

        Divider()
            .background(RemindersColors.separator)

        ReorderableListRow(
            list: TaskList(name: "Work", color: .blue, icon: .briefcase),
            taskCount: 5,
            isEditing: true,
            onDelete: { }
        )
        .padding(.horizontal)

        Divider()
            .background(RemindersColors.separator)

        ReorderableListRow(
            list: TaskList(name: "Shopping", color: .green, icon: .cart),
            taskCount: 3,
            isEditing: true,
            onDelete: { }
        )
        .padding(.horizontal)
    }
    .padding(.vertical)
    .background(RemindersColors.backgroundSecondary)
    .clipShape(RoundedRectangle(cornerRadius: RemindersKit.Radius.lg))
    .padding()
    .background(RemindersColors.background)
    .preferredColorScheme(.dark)
}

#Preview("List Info Row") {
    VStack(spacing: 0) {
        ListInfoRow(
            list: TaskList.sample,
            taskCount: 12,
            completedCount: 8
        )

        Divider()
            .background(RemindersColors.separator)

        ListInfoRow(
            list: TaskList(name: "Work Projects", color: .blue, icon: .briefcase),
            taskCount: 24,
            completedCount: 18
        )
    }
    .padding()
    .background(RemindersColors.backgroundSecondary)
    .clipShape(RoundedRectangle(cornerRadius: RemindersKit.Radius.lg))
    .padding()
    .background(RemindersColors.background)
    .preferredColorScheme(.dark)
}
