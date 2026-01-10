//
//  PriorityPicker.swift
//  TasksApp
//
//  Priority selection component matching Apple Reminders style
//

import SwiftUI

// MARK: - Priority Picker

struct PriorityPicker: View {

    // MARK: - Properties

    @Binding var selectedPriority: Priority
    let style: PriorityPickerStyle

    // MARK: - Initialization

    init(
        selectedPriority: Binding<Priority>,
        style: PriorityPickerStyle = .inline
    ) {
        self._selectedPriority = selectedPriority
        self.style = style
    }

    // MARK: - Body

    var body: some View {
        switch style {
        case .inline:
            inlinePicker
        case .menu:
            menuPicker
        case .segmented:
            segmentedPicker
        case .list:
            listPicker
        }
    }

    // MARK: - Inline Picker

    private var inlinePicker: some View {
        HStack(spacing: RemindersKit.Spacing.sm) {
            ForEach(Priority.allCases, id: \.self) { priority in
                PriorityButton(
                    priority: priority,
                    isSelected: selectedPriority == priority
                ) {
                    withAnimation(RemindersKit.Animation.quick) {
                        selectedPriority = priority
                    }

                    // Haptic feedback
                    let generator = UIImpactFeedbackGenerator(style: .light)
                    generator.impactOccurred()
                }
            }
        }
    }

    // MARK: - Menu Picker

    private var menuPicker: some View {
        Menu {
            ForEach(Priority.allCases, id: \.self) { priority in
                Button {
                    selectedPriority = priority
                } label: {
                    Label {
                        Text(priority.displayName)
                    } icon: {
                        if priority != .none {
                            Image(systemName: priority.symbolName)
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: RemindersKit.Spacing.xs) {
                if selectedPriority != .none {
                    Image(systemName: selectedPriority.symbolName)
                        .foregroundColor(selectedPriority.color)
                }

                Text(selectedPriority.displayName)
                    .font(RemindersTypography.body)
                    .foregroundColor(selectedPriority == .none ? RemindersColors.textSecondary : selectedPriority.color)

                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(RemindersColors.textSecondary)
            }
            .padding(.horizontal, RemindersKit.Spacing.md)
            .padding(.vertical, RemindersKit.Spacing.sm)
            .background(RemindersColors.backgroundTertiary)
            .clipShape(RoundedRectangle(cornerRadius: RemindersKit.Radius.md))
        }
    }

    // MARK: - Segmented Picker

    private var segmentedPicker: some View {
        HStack(spacing: 0) {
            ForEach(Priority.allCases, id: \.self) { priority in
                Button {
                    withAnimation(RemindersKit.Animation.quick) {
                        selectedPriority = priority
                    }
                } label: {
                    VStack(spacing: RemindersKit.Spacing.xxs) {
                        if priority != .none {
                            Image(systemName: priority.symbolName)
                                .font(.system(size: 14, weight: .semibold))
                        } else {
                            Image(systemName: "minus")
                                .font(.system(size: 14, weight: .semibold))
                        }

                        Text(priority.shortName)
                            .font(RemindersTypography.caption2)
                    }
                    .foregroundColor(selectedPriority == priority ? .white : RemindersColors.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, RemindersKit.Spacing.sm)
                    .background(
                        selectedPriority == priority
                            ? (priority == .none ? RemindersColors.textSecondary : priority.color)
                            : Color.clear
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .background(RemindersColors.backgroundTertiary)
        .clipShape(RoundedRectangle(cornerRadius: RemindersKit.Radius.md))
    }

    // MARK: - List Picker

    private var listPicker: some View {
        ForEach(Priority.allCases, id: \.self) { priority in
            Button {
                selectedPriority = priority
            } label: {
                HStack {
                    if priority != .none {
                        Image(systemName: priority.symbolName)
                            .foregroundColor(priority.color)
                            .frame(width: 24)
                    } else {
                        Image(systemName: "minus")
                            .foregroundColor(RemindersColors.textSecondary)
                            .frame(width: 24)
                    }

                    Text(priority.displayName)
                        .font(RemindersTypography.body)
                        .foregroundColor(RemindersColors.textPrimary)

                    Spacer()

                    if selectedPriority == priority {
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(RemindersColors.accentBlue)
                    }
                }
                .padding(.vertical, RemindersKit.Spacing.sm)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Priority Picker Style

enum PriorityPickerStyle {
    case inline    // Horizontal buttons
    case menu      // Dropdown menu
    case segmented // Segmented control style
    case list      // Vertical list
}

// MARK: - Priority Button

struct PriorityButton: View {
    let priority: Priority
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: RemindersKit.Spacing.xxs) {
                ZStack {
                    Circle()
                        .fill(isSelected ? priority.color.opacity(0.2) : Color.clear)
                        .frame(width: 40, height: 40)

                    if priority != .none {
                        Image(systemName: priority.symbolName)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(isSelected ? priority.color : RemindersColors.textSecondary)
                    } else {
                        Image(systemName: "minus")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(isSelected ? RemindersColors.textPrimary : RemindersColors.textSecondary)
                    }
                }
                .overlay(
                    Circle()
                        .stroke(isSelected ? priority.color : Color.clear, lineWidth: 2)
                        .frame(width: 40, height: 40)
                )

                Text(priority.shortName)
                    .font(RemindersTypography.caption2)
                    .foregroundColor(isSelected ? priority.color : RemindersColors.textSecondary)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Priority Extensions

extension Priority {
    var color: Color {
        switch self {
        case .none: return RemindersColors.textSecondary
        case .low: return RemindersColors.priorityLow
        case .medium: return RemindersColors.priorityMedium
        case .high: return RemindersColors.priorityHigh
        }
    }

    var shortName: String {
        switch self {
        case .none: return "None"
        case .low: return "Low"
        case .medium: return "Med"
        case .high: return "High"
        }
    }
}

// MARK: - Compact Priority Badge

struct PriorityBadge: View {
    let priority: Priority

    var body: some View {
        if priority != .none {
            HStack(spacing: 2) {
                ForEach(0..<priority.rawValue, id: \.self) { _ in
                    Image(systemName: "exclamationmark")
                        .font(.system(size: 10, weight: .bold))
                }
            }
            .foregroundColor(priority.color)
        }
    }
}

// MARK: - Priority Row (for settings/detail views)

struct PriorityRow: View {
    @Binding var priority: Priority

    var body: some View {
        HStack {
            Label {
                Text("Priority")
                    .font(RemindersTypography.body)
                    .foregroundColor(RemindersColors.textPrimary)
            } icon: {
                Image(systemName: "flag.fill")
                    .foregroundColor(RemindersColors.accentOrange)
            }

            Spacer()

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
                        }
                    }
                }
            } label: {
                HStack(spacing: RemindersKit.Spacing.xs) {
                    if priority != .none {
                        PriorityBadge(priority: priority)
                    }

                    Text(priority.displayName)
                        .font(RemindersTypography.body)
                        .foregroundColor(priority == .none ? RemindersColors.textSecondary : priority.color)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(RemindersColors.textTertiary)
                }
            }
        }
    }
}

// MARK: - Preview

#Preview("Priority Picker") {
    struct PreviewWrapper: View {
        @State private var priority1: Priority = .none
        @State private var priority2: Priority = .medium
        @State private var priority3: Priority = .high
        @State private var priority4: Priority = .low

        var body: some View {
            ScrollView {
                VStack(spacing: 32) {
                    // Inline style
                    Group {
                        Text("Inline Style")
                            .font(RemindersTypography.headline)
                            .foregroundColor(RemindersColors.textPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        PriorityPicker(selectedPriority: $priority1, style: .inline)
                    }

                    // Menu style
                    Group {
                        Text("Menu Style")
                            .font(RemindersTypography.headline)
                            .foregroundColor(RemindersColors.textPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        PriorityPicker(selectedPriority: $priority2, style: .menu)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    // Segmented style
                    Group {
                        Text("Segmented Style")
                            .font(RemindersTypography.headline)
                            .foregroundColor(RemindersColors.textPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        PriorityPicker(selectedPriority: $priority3, style: .segmented)
                    }

                    // List style
                    Group {
                        Text("List Style")
                            .font(RemindersTypography.headline)
                            .foregroundColor(RemindersColors.textPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        VStack(spacing: 0) {
                            PriorityPicker(selectedPriority: $priority4, style: .list)
                        }
                        .padding(.horizontal, RemindersKit.Spacing.lg)
                        .background(RemindersColors.backgroundSecondary)
                        .clipShape(RoundedRectangle(cornerRadius: RemindersKit.Radius.lg))
                    }

                    // Priority Row
                    Group {
                        Text("Priority Row")
                            .font(RemindersTypography.headline)
                            .foregroundColor(RemindersColors.textPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        PriorityRow(priority: $priority1)
                            .padding(RemindersKit.Spacing.lg)
                            .background(RemindersColors.backgroundSecondary)
                            .clipShape(RoundedRectangle(cornerRadius: RemindersKit.Radius.lg))
                    }

                    // Badges
                    Group {
                        Text("Priority Badges")
                            .font(RemindersTypography.headline)
                            .foregroundColor(RemindersColors.textPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        HStack(spacing: 24) {
                            ForEach(Priority.allCases, id: \.self) { p in
                                VStack {
                                    PriorityBadge(priority: p)
                                        .frame(height: 20)
                                    Text(p.displayName)
                                        .font(RemindersTypography.caption2)
                                        .foregroundColor(RemindersColors.textSecondary)
                                }
                            }
                        }
                    }
                }
                .padding()
            }
            .background(RemindersColors.background)
        }
    }

    return PreviewWrapper()
}
