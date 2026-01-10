//
//  EmptyStateView.swift
//  TasksApp
//
//  Empty state component with icon and message
//

import SwiftUI

// MARK: - Empty State Style

enum EmptyStateStyle {
    case standard       // Centered with icon, title, message
    case compact        // Smaller, less padding
    case inline         // For use in lists
}

// MARK: - Empty State View

struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String?
    let style: EmptyStateStyle
    let iconColor: Color
    let action: EmptyStateAction?

    init(
        icon: String,
        title: String,
        message: String? = nil,
        style: EmptyStateStyle = .standard,
        iconColor: Color = RemindersColors.textTertiary,
        action: EmptyStateAction? = nil
    ) {
        self.icon = icon
        self.title = title
        self.message = message
        self.style = style
        self.iconColor = iconColor
        self.action = action
    }

    var body: some View {
        switch style {
        case .standard:
            standardView
        case .compact:
            compactView
        case .inline:
            inlineView
        }
    }

    // MARK: - Standard View

    private var standardView: some View {
        VStack(spacing: RemindersKit.Spacing.lg) {
            // Icon
            Image(systemName: icon)
                .font(.system(size: RemindersKit.Size.iconHuge, weight: .light))
                .foregroundColor(iconColor)
                .padding(.bottom, RemindersKit.Spacing.sm)

            // Title
            Text(title)
                .font(RemindersTypography.title3)
                .foregroundColor(RemindersColors.textPrimary)
                .multilineTextAlignment(.center)

            // Message
            if let message = message {
                Text(message)
                    .font(RemindersTypography.body)
                    .foregroundColor(RemindersColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, RemindersKit.Spacing.xxl)
            }

            // Action button
            if let action = action {
                actionButton(action)
                    .padding(.top, RemindersKit.Spacing.sm)
            }
        }
        .padding(RemindersKit.Spacing.xxxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Compact View

    private var compactView: some View {
        VStack(spacing: RemindersKit.Spacing.md) {
            // Icon
            Image(systemName: icon)
                .font(.system(size: RemindersKit.Size.iconXL, weight: .light))
                .foregroundColor(iconColor)

            // Title
            Text(title)
                .font(RemindersTypography.headline)
                .foregroundColor(RemindersColors.textPrimary)
                .multilineTextAlignment(.center)

            // Message
            if let message = message {
                Text(message)
                    .font(RemindersTypography.subheadline)
                    .foregroundColor(RemindersColors.textSecondary)
                    .multilineTextAlignment(.center)
            }

            // Action button
            if let action = action {
                actionButton(action)
            }
        }
        .padding(RemindersKit.Spacing.xl)
    }

    // MARK: - Inline View

    private var inlineView: some View {
        HStack(spacing: RemindersKit.Spacing.md) {
            // Icon
            Image(systemName: icon)
                .font(.system(size: RemindersKit.Size.icon, weight: .regular))
                .foregroundColor(iconColor)

            VStack(alignment: .leading, spacing: RemindersKit.Spacing.xxs) {
                // Title
                Text(title)
                    .font(RemindersTypography.subheadline)
                    .foregroundColor(RemindersColors.textSecondary)

                // Message
                if let message = message {
                    Text(message)
                        .font(RemindersTypography.caption1)
                        .foregroundColor(RemindersColors.textTertiary)
                }
            }

            Spacer()

            // Action button
            if let action = action {
                TextButton(action.title, icon: action.icon, color: action.color) {
                    action.action()
                }
            }
        }
        .padding(RemindersKit.Spacing.lg)
    }

    // MARK: - Action Button

    @ViewBuilder
    private func actionButton(_ action: EmptyStateAction) -> some View {
        if action.isPrimary {
            PrimaryButton(
                action.title,
                icon: action.icon,
                style: .primary,
                size: .medium
            ) {
                action.action()
            }
            .frame(maxWidth: 200)
        } else {
            TextButton(action.title, icon: action.icon, color: action.color) {
                action.action()
            }
        }
    }
}

// MARK: - Empty State Action

struct EmptyStateAction {
    let title: String
    let icon: String?
    let color: Color
    let isPrimary: Bool
    let action: () -> Void

    init(
        title: String,
        icon: String? = nil,
        color: Color = RemindersColors.accentBlue,
        isPrimary: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.icon = icon
        self.color = color
        self.isPrimary = isPrimary
        self.action = action
    }
}

// MARK: - Preset Empty States

extension EmptyStateView {

    /// No tasks empty state
    static func noTasks(action: @escaping () -> Void) -> EmptyStateView {
        EmptyStateView(
            icon: "checklist",
            title: "No Reminders",
            message: "Reminders you add will appear here.",
            iconColor: RemindersColors.textTertiary,
            action: EmptyStateAction(
                title: "New Reminder",
                icon: "plus",
                isPrimary: true,
                action: action
            )
        )
    }

    /// No completed tasks
    static var noCompletedTasks: EmptyStateView {
        EmptyStateView(
            icon: "checkmark.circle",
            title: "No Completed Reminders",
            message: "Completed reminders will appear here.",
            iconColor: RemindersColors.accentGreen.opacity(0.5)
        )
    }

    /// No search results
    static func noSearchResults(query: String) -> EmptyStateView {
        EmptyStateView(
            icon: "magnifyingglass",
            title: "No Results",
            message: "No reminders match \"\(query)\".",
            iconColor: RemindersColors.textTertiary
        )
    }

    /// No lists
    static func noLists(action: @escaping () -> Void) -> EmptyStateView {
        EmptyStateView(
            icon: "list.bullet",
            title: "No Lists",
            message: "Create a list to organize your reminders.",
            iconColor: RemindersColors.textTertiary,
            action: EmptyStateAction(
                title: "Add List",
                icon: "plus",
                isPrimary: true,
                action: action
            )
        )
    }

    /// Today view empty
    static var noTodayTasks: EmptyStateView {
        EmptyStateView(
            icon: "calendar",
            title: "Nothing Due Today",
            message: "Reminders due today will appear here.",
            iconColor: RemindersColors.accentBlue.opacity(0.5)
        )
    }

    /// Scheduled view empty
    static var noScheduledTasks: EmptyStateView {
        EmptyStateView(
            icon: "calendar.badge.clock",
            title: "No Scheduled Reminders",
            message: "Reminders with due dates will appear here.",
            iconColor: RemindersColors.accentRed.opacity(0.5)
        )
    }

    /// Flagged view empty
    static var noFlaggedTasks: EmptyStateView {
        EmptyStateView(
            icon: "flag.fill",
            title: "No Flagged Reminders",
            message: "Flagged reminders will appear here.",
            iconColor: RemindersColors.accentOrange.opacity(0.5)
        )
    }

    /// All tasks completed celebration
    static var allTasksCompleted: EmptyStateView {
        EmptyStateView(
            icon: "party.popper.fill",
            title: "All Done!",
            message: "You've completed all your reminders.",
            iconColor: RemindersColors.accentGreen
        )
    }

    /// Error state
    static func error(message: String, retryAction: @escaping () -> Void) -> EmptyStateView {
        EmptyStateView(
            icon: "exclamationmark.triangle",
            title: "Something Went Wrong",
            message: message,
            iconColor: RemindersColors.accentRed,
            action: EmptyStateAction(
                title: "Try Again",
                icon: "arrow.clockwise",
                action: retryAction
            )
        )
    }

    /// Offline state
    static var offline: EmptyStateView {
        EmptyStateView(
            icon: "wifi.slash",
            title: "No Connection",
            message: "Check your internet connection and try again.",
            iconColor: RemindersColors.textTertiary
        )
    }
}

// MARK: - Preview

#Preview {
    ScrollView {
        VStack(spacing: 40) {
            // Standard empty state
            EmptyStateView.noTasks { print("Add task") }
                .frame(height: 350)
                .background(RemindersColors.backgroundSecondary)
                .clipShape(RoundedRectangle(cornerRadius: RemindersKit.Radius.lg))

            // Compact empty state
            EmptyStateView(
                icon: "magnifyingglass",
                title: "No Results",
                message: "Try a different search term.",
                style: .compact
            )
            .frame(height: 200)
            .background(RemindersColors.backgroundSecondary)
            .clipShape(RoundedRectangle(cornerRadius: RemindersKit.Radius.lg))

            // Inline empty state
            EmptyStateView(
                icon: "tray",
                title: "No items in this section",
                style: .inline,
                action: EmptyStateAction(title: "Add", icon: "plus") { }
            )
            .background(RemindersColors.backgroundSecondary)
            .clipShape(RoundedRectangle(cornerRadius: RemindersKit.Radius.lg))

            // Today empty
            EmptyStateView.noTodayTasks
                .frame(height: 300)
                .background(RemindersColors.backgroundSecondary)
                .clipShape(RoundedRectangle(cornerRadius: RemindersKit.Radius.lg))

            // All completed
            EmptyStateView.allTasksCompleted
                .frame(height: 300)
                .background(RemindersColors.backgroundSecondary)
                .clipShape(RoundedRectangle(cornerRadius: RemindersKit.Radius.lg))

            // Error state
            EmptyStateView.error(message: "Failed to load reminders.") { print("Retry") }
                .frame(height: 300)
                .background(RemindersColors.backgroundSecondary)
                .clipShape(RoundedRectangle(cornerRadius: RemindersKit.Radius.lg))
        }
        .padding()
    }
    .background(RemindersColors.background)
}
