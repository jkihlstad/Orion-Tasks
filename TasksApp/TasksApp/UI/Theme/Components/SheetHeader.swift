//
//  SheetHeader.swift
//  TasksApp
//
//  Modal sheet header component with title and close button
//

import SwiftUI

// MARK: - Sheet Header Style

enum SheetHeaderStyle {
    case standard        // Title centered, close button on right
    case navigation      // Cancel/Done style with title centered
    case compact         // Smaller header with just close button
}

// MARK: - Sheet Header

struct SheetHeader: View {
    let title: String
    let subtitle: String?
    let style: SheetHeaderStyle
    let leadingAction: SheetHeaderAction?
    let trailingAction: SheetHeaderAction?
    let onClose: (() -> Void)?

    init(
        title: String,
        subtitle: String? = nil,
        style: SheetHeaderStyle = .standard,
        leadingAction: SheetHeaderAction? = nil,
        trailingAction: SheetHeaderAction? = nil,
        onClose: (() -> Void)? = nil
    ) {
        self.title = title
        self.subtitle = subtitle
        self.style = style
        self.leadingAction = leadingAction
        self.trailingAction = trailingAction
        self.onClose = onClose
    }

    var body: some View {
        switch style {
        case .standard:
            standardHeader
        case .navigation:
            navigationHeader
        case .compact:
            compactHeader
        }
    }

    // MARK: - Standard Header

    private var standardHeader: some View {
        VStack(spacing: 0) {
            // Drag indicator
            dragIndicator

            // Header content
            HStack {
                // Leading spacer or action
                if let leading = leadingAction {
                    headerButton(leading)
                } else {
                    Spacer()
                        .frame(width: 60)
                }

                Spacer()

                // Title and subtitle
                VStack(spacing: 2) {
                    Text(title)
                        .font(RemindersTypography.headline)
                        .foregroundColor(RemindersColors.textPrimary)

                    if let subtitle = subtitle {
                        Text(subtitle)
                            .font(RemindersTypography.caption1)
                            .foregroundColor(RemindersColors.textSecondary)
                    }
                }

                Spacer()

                // Trailing action or close button
                if let trailing = trailingAction {
                    headerButton(trailing)
                } else if let onClose = onClose {
                    CloseButton(action: onClose)
                        .frame(width: 60, alignment: .trailing)
                } else {
                    Spacer()
                        .frame(width: 60)
                }
            }
            .padding(.horizontal, RemindersKit.Spacing.lg)
            .padding(.vertical, RemindersKit.Spacing.md)

            // Separator
            Divider()
                .background(RemindersColors.separator)
        }
        .background(RemindersColors.backgroundElevated)
    }

    // MARK: - Navigation Header

    private var navigationHeader: some View {
        VStack(spacing: 0) {
            // Drag indicator
            dragIndicator

            // Header content
            ZStack {
                // Title centered
                VStack(spacing: 2) {
                    Text(title)
                        .font(RemindersTypography.headline)
                        .foregroundColor(RemindersColors.textPrimary)

                    if let subtitle = subtitle {
                        Text(subtitle)
                            .font(RemindersTypography.caption1)
                            .foregroundColor(RemindersColors.textSecondary)
                    }
                }

                // Leading and trailing actions
                HStack {
                    if let leading = leadingAction {
                        headerButton(leading)
                    } else if let onClose = onClose {
                        Button(action: onClose) {
                            Text("Cancel")
                                .font(RemindersTypography.body)
                                .foregroundColor(RemindersColors.accentBlue)
                        }
                    }

                    Spacer()

                    if let trailing = trailingAction {
                        headerButton(trailing)
                    }
                }
            }
            .padding(.horizontal, RemindersKit.Spacing.lg)
            .padding(.vertical, RemindersKit.Spacing.md)

            // Separator
            Divider()
                .background(RemindersColors.separator)
        }
        .background(RemindersColors.backgroundElevated)
    }

    // MARK: - Compact Header

    private var compactHeader: some View {
        HStack {
            Spacer()

            if let onClose = onClose {
                CloseButton(action: onClose)
            }
        }
        .padding(.horizontal, RemindersKit.Spacing.lg)
        .padding(.top, RemindersKit.Spacing.md)
        .background(RemindersColors.backgroundElevated)
    }

    // MARK: - Components

    private var dragIndicator: some View {
        RoundedRectangle(cornerRadius: RemindersKit.Radius.full)
            .fill(RemindersColors.fillSecondary)
            .frame(width: RemindersKit.Size.sheetGrabber, height: RemindersKit.Size.sheetGrabberHeight)
            .padding(.top, RemindersKit.Spacing.sm)
            .padding(.bottom, RemindersKit.Spacing.xs)
    }

    @ViewBuilder
    private func headerButton(_ action: SheetHeaderAction) -> some View {
        Button(action: action.action) {
            HStack(spacing: RemindersKit.Spacing.xxs) {
                if let icon = action.icon {
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: action.isEmphasized ? .semibold : .regular))
                }

                if let title = action.title {
                    Text(title)
                        .font(action.isEmphasized ? RemindersTypography.bodyBold : RemindersTypography.body)
                }
            }
            .foregroundColor(action.isDestructive ? RemindersColors.accentRed : RemindersColors.accentBlue)
        }
        .disabled(action.isDisabled)
        .opacity(action.isDisabled ? RemindersKit.Opacity.disabled : 1)
        .frame(minWidth: 60, alignment: action.alignment)
    }
}

// MARK: - Sheet Header Action

struct SheetHeaderAction {
    let title: String?
    let icon: String?
    let isEmphasized: Bool
    let isDestructive: Bool
    let isDisabled: Bool
    let alignment: Alignment
    let action: () -> Void

    init(
        title: String? = nil,
        icon: String? = nil,
        isEmphasized: Bool = false,
        isDestructive: Bool = false,
        isDisabled: Bool = false,
        alignment: Alignment = .center,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.icon = icon
        self.isEmphasized = isEmphasized
        self.isDestructive = isDestructive
        self.isDisabled = isDisabled
        self.alignment = alignment
        self.action = action
    }

    // Common presets
    static func cancel(_ action: @escaping () -> Void) -> SheetHeaderAction {
        SheetHeaderAction(title: "Cancel", alignment: .leading, action: action)
    }

    static func done(_ action: @escaping () -> Void) -> SheetHeaderAction {
        SheetHeaderAction(title: "Done", isEmphasized: true, alignment: .trailing, action: action)
    }

    static func save(_ action: @escaping () -> Void) -> SheetHeaderAction {
        SheetHeaderAction(title: "Save", isEmphasized: true, alignment: .trailing, action: action)
    }

    static func add(_ action: @escaping () -> Void) -> SheetHeaderAction {
        SheetHeaderAction(title: "Add", isEmphasized: true, alignment: .trailing, action: action)
    }

    static func delete(_ action: @escaping () -> Void) -> SheetHeaderAction {
        SheetHeaderAction(title: "Delete", isDestructive: true, alignment: .trailing, action: action)
    }

    static func edit(_ action: @escaping () -> Void) -> SheetHeaderAction {
        SheetHeaderAction(title: "Edit", alignment: .trailing, action: action)
    }
}

// MARK: - Sheet Container

struct SheetContainer<Content: View>: View {
    let title: String
    let subtitle: String?
    let style: SheetHeaderStyle
    let leadingAction: SheetHeaderAction?
    let trailingAction: SheetHeaderAction?
    let onClose: (() -> Void)?
    let content: Content

    init(
        title: String,
        subtitle: String? = nil,
        style: SheetHeaderStyle = .standard,
        leadingAction: SheetHeaderAction? = nil,
        trailingAction: SheetHeaderAction? = nil,
        onClose: (() -> Void)? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.style = style
        self.leadingAction = leadingAction
        self.trailingAction = trailingAction
        self.onClose = onClose
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(
                title: title,
                subtitle: subtitle,
                style: style,
                leadingAction: leadingAction,
                trailingAction: trailingAction,
                onClose: onClose
            )

            content
        }
        .background(RemindersColors.backgroundElevated)
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 24) {
        // Standard header with close
        SheetHeader(
            title: "New Task",
            onClose: { print("Close tapped") }
        )

        Spacer()
            .frame(height: 20)

        // Standard header with subtitle
        SheetHeader(
            title: "Task Details",
            subtitle: "My List",
            onClose: { print("Close tapped") }
        )

        Spacer()
            .frame(height: 20)

        // Navigation style
        SheetHeader(
            title: "Edit Task",
            style: .navigation,
            leadingAction: .cancel { print("Cancel") },
            trailingAction: .done { print("Done") }
        )

        Spacer()
            .frame(height: 20)

        // Navigation with disabled save
        SheetHeader(
            title: "New List",
            style: .navigation,
            leadingAction: .cancel { print("Cancel") },
            trailingAction: SheetHeaderAction(
                title: "Save",
                isEmphasized: true,
                isDisabled: true,
                alignment: .trailing,
                action: { print("Save") }
            )
        )

        Spacer()
            .frame(height: 20)

        // Compact header
        SheetHeader(
            title: "",
            style: .compact,
            onClose: { print("Close") }
        )

        Spacer()

        // Full sheet container example
        SheetContainer(
            title: "Add Reminder",
            style: .navigation,
            leadingAction: .cancel { },
            trailingAction: .add { }
        ) {
            VStack {
                Text("Sheet content goes here")
                    .foregroundColor(RemindersColors.textSecondary)
                    .padding()
                Spacer()
            }
        }
        .frame(height: 300)
        .clipShape(RoundedRectangle(cornerRadius: RemindersKit.Radius.sheet))
    }
    .background(RemindersColors.background)
}
