//
//  NewListSheet.swift
//  TasksApp
//
//  Sheet for creating a new task list, matching Apple Reminders style
//

import SwiftUI

// MARK: - New List Sheet

struct NewListSheet: View {
    @Environment(\.dismiss) private var dismiss

    // Form state
    @State private var name: String = ""
    @State private var selectedColor: ListColor = .blue
    @State private var selectedIcon: ListIcon = .list

    // Focus state
    @FocusState private var isNameFocused: Bool

    // Callback for when a new list is created
    let onCreate: (String, ListColor, ListIcon) -> Void

    init(onCreate: @escaping (String, ListColor, ListIcon) -> Void) {
        self.onCreate = onCreate
    }

    // MARK: - Computed Properties

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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

                    Spacer(minLength: RemindersKit.Spacing.xxxl)
                }
            }
            .background(RemindersColors.backgroundGrouped)
            .navigationTitle("New List")
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
                        createList()
                    }
                    .font(RemindersTypography.bodyBold)
                    .foregroundColor(isValid ? RemindersColors.accentBlue : RemindersColors.textTertiary)
                    .disabled(!isValid)
                }
            }
            .toolbarBackground(RemindersColors.backgroundElevated, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .presentationBackground(RemindersColors.backgroundGrouped)
        .presentationDragIndicator(.visible)
        .onAppear {
            // Delay focus to allow sheet animation
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                isNameFocused = true
            }
        }
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
            Text(name.isEmpty ? "New List" : name)
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
                    if isValid {
                        createList()
                    }
                }
                .padding(RemindersKit.Spacing.lg)
                .background(RemindersColors.backgroundSecondary)
                .clipShape(RoundedRectangle(cornerRadius: RemindersKit.Radius.insetGrouped))
        }
        .padding(.horizontal, RemindersKit.Spacing.lg)
    }

    // MARK: - Actions

    private func createList() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        onCreate(trimmedName, selectedColor, selectedIcon)
        dismiss()
    }
}

// MARK: - Preview

#Preview("New List Sheet") {
    struct PreviewWrapper: View {
        @State private var showSheet = true

        var body: some View {
            Color.clear
                .sheet(isPresented: $showSheet) {
                    NewListSheet { name, color, icon in
                        print("Created list: \(name), color: \(color), icon: \(icon)")
                    }
                }
        }
    }

    return PreviewWrapper()
}

#Preview("New List Sheet - Embedded") {
    NewListSheet { name, color, icon in
        print("Created list: \(name), color: \(color), icon: \(icon)")
    }
}
