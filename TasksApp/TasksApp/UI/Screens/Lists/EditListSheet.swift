//
//  EditListSheet.swift
//  TasksApp
//
//  Sheet for editing an existing task list, matching Apple Reminders style
//

import SwiftUI

// MARK: - Edit List Sheet

struct EditListSheet: View {
    @Environment(\.dismiss) private var dismiss

    // The list being edited
    let list: TaskList

    // Form state
    @State private var name: String
    @State private var selectedColor: ListColor
    @State private var selectedIcon: ListIcon

    // UI state
    @State private var showDeleteConfirmation: Bool = false

    // Focus state
    @FocusState private var isNameFocused: Bool

    // Callbacks
    let onSave: (String, ListColor, ListIcon) -> Void
    let onDelete: () -> Void

    init(
        list: TaskList,
        onSave: @escaping (String, ListColor, ListIcon) -> Void,
        onDelete: @escaping () -> Void
    ) {
        self.list = list
        self._name = State(initialValue: list.name)
        self._selectedColor = State(initialValue: list.color)
        self._selectedIcon = State(initialValue: list.icon)
        self.onSave = onSave
        self.onDelete = onDelete
    }

    // MARK: - Computed Properties

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var hasChanges: Bool {
        name != list.name ||
        selectedColor != list.color ||
        selectedIcon != list.icon
    }

    private var canDelete: Bool {
        // Cannot delete the inbox list
        !list.isInbox
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: RemindersKit.Spacing.xl) {
                    // List preview
                    listPreview
                        .padding(.top, RemindersKit.Spacing.xl)

                    // Name input
                    nameInputSection

                    // Color picker
                    ListColorPicker(selectedColor: $selectedColor)
                        .padding(.horizontal, RemindersKit.Spacing.lg)

                    // Icon picker
                    ListIconPicker(selectedIcon: $selectedIcon, accentColor: selectedColor.color)
                        .padding(.horizontal, RemindersKit.Spacing.lg)

                    // Delete button
                    if canDelete {
                        deleteButton
                            .padding(.horizontal, RemindersKit.Spacing.lg)
                            .padding(.top, RemindersKit.Spacing.lg)
                    }

                    Spacer(minLength: RemindersKit.Spacing.xxxl)
                }
            }
            .background(RemindersColors.backgroundGrouped)
            .navigationTitle("Edit List")
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
                        saveList()
                    }
                    .font(RemindersTypography.bodyBold)
                    .foregroundColor(
                        isValid && hasChanges
                        ? RemindersColors.accentBlue
                        : RemindersColors.textTertiary
                    )
                    .disabled(!isValid || !hasChanges)
                }
            }
            .toolbarBackground(RemindersColors.backgroundElevated, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .confirmationDialog(
                "Delete List",
                isPresented: $showDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete List", role: .destructive) {
                    deleteList()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Are you sure you want to delete \"\(list.name)\"? All reminders in this list will also be deleted.")
            }
        }
        .presentationBackground(RemindersColors.backgroundGrouped)
        .presentationDragIndicator(.visible)
    }

    // MARK: - Subviews

    private var listPreview: some View {
        VStack(spacing: RemindersKit.Spacing.md) {
            // Icon preview
            ZStack {
                Circle()
                    .fill(selectedColor.color)
                    .frame(width: 80, height: 80)
                    .shadow(color: selectedColor.color.opacity(0.4), radius: 8, x: 0, y: 4)

                Image(systemName: selectedIcon.rawValue)
                    .font(.system(size: 36, weight: .bold))
                    .foregroundColor(.white)
            }
            .animation(RemindersKit.Animation.spring, value: selectedColor)
            .animation(RemindersKit.Animation.spring, value: selectedIcon)

            // Name preview
            Text(name.isEmpty ? "List Name" : name)
                .font(RemindersTypography.title3)
                .foregroundColor(name.isEmpty ? RemindersColors.textTertiary : RemindersColors.textPrimary)
                .animation(RemindersKit.Animation.quick, value: name)
        }
    }

    private var nameInputSection: some View {
        VStack(alignment: .leading, spacing: RemindersKit.Spacing.sm) {
            TextField("List Name", text: $name)
                .font(RemindersTypography.body)
                .foregroundColor(RemindersColors.textPrimary)
                .focused($isNameFocused)
                .textInputAutocapitalization(.words)
                .submitLabel(.done)
                .onSubmit {
                    if isValid && hasChanges {
                        saveList()
                    }
                }
                .padding(RemindersKit.Spacing.lg)
                .background(RemindersColors.backgroundSecondary)
                .clipShape(RoundedRectangle(cornerRadius: RemindersKit.Radius.insetGrouped))
        }
        .padding(.horizontal, RemindersKit.Spacing.lg)
    }

    private var deleteButton: some View {
        Button(action: { showDeleteConfirmation = true }) {
            HStack {
                Spacer()
                Text("Delete List")
                    .font(RemindersTypography.body)
                    .foregroundColor(RemindersColors.accentRed)
                Spacer()
            }
            .padding(RemindersKit.Spacing.lg)
            .background(RemindersColors.backgroundSecondary)
            .clipShape(RoundedRectangle(cornerRadius: RemindersKit.Radius.insetGrouped))
        }
    }

    // MARK: - Actions

    private func saveList() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        onSave(trimmedName, selectedColor, selectedIcon)
        dismiss()
    }

    private func deleteList() {
        onDelete()
        dismiss()
    }
}

// MARK: - Preview

#Preview("Edit List Sheet") {
    struct PreviewWrapper: View {
        @State private var showSheet = true

        var body: some View {
            Color.clear
                .sheet(isPresented: $showSheet) {
                    EditListSheet(
                        list: TaskList(
                            id: "preview",
                            name: "Work Projects",
                            color: .blue,
                            icon: .briefcase
                        ),
                        onSave: { name, color, icon in
                            print("Saved list: \(name), color: \(color), icon: \(icon)")
                        },
                        onDelete: {
                            print("Deleted list")
                        }
                    )
                }
        }
    }

    return PreviewWrapper()
}

#Preview("Edit Inbox List") {
    struct PreviewWrapper: View {
        @State private var showSheet = true

        var body: some View {
            Color.clear
                .sheet(isPresented: $showSheet) {
                    EditListSheet(
                        list: TaskList.inbox,
                        onSave: { name, color, icon in
                            print("Saved inbox: \(name), color: \(color), icon: \(icon)")
                        },
                        onDelete: {
                            print("Cannot delete inbox")
                        }
                    )
                }
        }
    }

    return PreviewWrapper()
}

#Preview("Edit List Sheet - Embedded") {
    EditListSheet(
        list: TaskList(
            id: "shopping",
            name: "Shopping",
            color: .green,
            icon: .cart
        ),
        onSave: { name, color, icon in
            print("Saved: \(name)")
        },
        onDelete: {
            print("Deleted")
        }
    )
}
