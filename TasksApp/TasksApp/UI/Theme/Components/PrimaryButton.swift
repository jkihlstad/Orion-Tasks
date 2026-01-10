//
//  PrimaryButton.swift
//  TasksApp
//
//  Styled button component matching Apple Reminders
//

import SwiftUI

// MARK: - Button Style Enum

enum RemindersButtonStyle {
    case primary      // Filled blue background
    case secondary    // Subtle background, colored text
    case destructive  // Red destructive action
    case plain        // Text only, no background
    case icon         // Icon-only circular button
}

enum RemindersButtonSize {
    case small
    case medium
    case large

    var verticalPadding: CGFloat {
        switch self {
        case .small: return 8
        case .medium: return 12
        case .large: return 16
        }
    }

    var horizontalPadding: CGFloat {
        switch self {
        case .small: return 12
        case .medium: return 20
        case .large: return 24
        }
    }

    var font: Font {
        switch self {
        case .small: return RemindersTypography.buttonSmall
        case .medium: return RemindersTypography.button
        case .large: return RemindersTypography.button
        }
    }

    var iconSize: CGFloat {
        switch self {
        case .small: return 16
        case .medium: return 20
        case .large: return 24
        }
    }
}

// MARK: - Primary Button

struct PrimaryButton: View {
    let title: String
    let icon: String?
    let style: RemindersButtonStyle
    let size: RemindersButtonSize
    let isLoading: Bool
    let isDisabled: Bool
    let action: () -> Void

    init(
        _ title: String,
        icon: String? = nil,
        style: RemindersButtonStyle = .primary,
        size: RemindersButtonSize = .medium,
        isLoading: Bool = false,
        isDisabled: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.icon = icon
        self.style = style
        self.size = size
        self.isLoading = isLoading
        self.isDisabled = isDisabled
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: RemindersKit.Spacing.sm) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: foregroundColor))
                        .scaleEffect(0.8)
                } else {
                    if let icon = icon {
                        Image(systemName: icon)
                            .font(.system(size: size.iconSize, weight: .semibold))
                    }

                    Text(title)
                        .font(size.font)
                }
            }
            .frame(maxWidth: style == .icon ? nil : .infinity)
            .padding(.vertical, size.verticalPadding)
            .padding(.horizontal, size.horizontalPadding)
            .foregroundColor(foregroundColor)
            .background(backgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(borderColor, lineWidth: hasBorder ? 1 : 0)
            )
        }
        .disabled(isDisabled || isLoading)
        .opacity(isDisabled ? RemindersKit.Opacity.disabled : 1)
        .animation(RemindersKit.Animation.quick, value: isLoading)
        .animation(RemindersKit.Animation.quick, value: isDisabled)
    }

    // MARK: - Style Properties

    private var foregroundColor: Color {
        switch style {
        case .primary:
            return .white
        case .secondary:
            return RemindersColors.accentBlue
        case .destructive:
            return RemindersColors.accentRed
        case .plain:
            return RemindersColors.accentBlue
        case .icon:
            return RemindersColors.accentBlue
        }
    }

    private var backgroundColor: Color {
        switch style {
        case .primary:
            return RemindersColors.accentBlue
        case .secondary:
            return RemindersColors.accentBlue.opacity(0.15)
        case .destructive:
            return RemindersColors.accentRed.opacity(0.15)
        case .plain:
            return .clear
        case .icon:
            return RemindersColors.fillTertiary
        }
    }

    private var borderColor: Color {
        switch style {
        case .secondary:
            return RemindersColors.accentBlue.opacity(0.3)
        case .destructive:
            return RemindersColors.accentRed.opacity(0.3)
        default:
            return .clear
        }
    }

    private var hasBorder: Bool {
        style == .secondary || style == .destructive
    }

    private var cornerRadius: CGFloat {
        switch size {
        case .small: return RemindersKit.Radius.buttonSmall
        case .medium: return RemindersKit.Radius.button
        case .large: return RemindersKit.Radius.button
        }
    }
}

// MARK: - Icon Button

struct IconButton: View {
    let icon: String
    let style: RemindersButtonStyle
    let size: CGFloat
    let action: () -> Void

    init(
        icon: String,
        style: RemindersButtonStyle = .plain,
        size: CGFloat = 44,
        action: @escaping () -> Void
    ) {
        self.icon = icon
        self.style = style
        self.size = size
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size * 0.45, weight: .medium))
                .foregroundColor(foregroundColor)
                .frame(width: size, height: size)
                .background(backgroundColor)
                .clipShape(Circle())
        }
    }

    private var foregroundColor: Color {
        switch style {
        case .primary:
            return .white
        case .destructive:
            return RemindersColors.accentRed
        default:
            return RemindersColors.accentBlue
        }
    }

    private var backgroundColor: Color {
        switch style {
        case .primary:
            return RemindersColors.accentBlue
        case .secondary:
            return RemindersColors.fillTertiary
        case .destructive:
            return RemindersColors.accentRed.opacity(0.15)
        default:
            return .clear
        }
    }
}

// MARK: - Close Button (X button for sheets)

struct CloseButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(RemindersColors.textSecondary)
                .frame(width: 30, height: 30)
                .background(RemindersColors.fillTertiary)
                .clipShape(Circle())
        }
    }
}

// MARK: - Add Button (+ button)

struct AddButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 28, height: 28)
                .background(RemindersColors.accentBlue)
                .clipShape(Circle())
        }
    }
}

// MARK: - Text Button (for inline actions)

struct TextButton: View {
    let title: String
    let icon: String?
    let color: Color
    let action: () -> Void

    init(
        _ title: String,
        icon: String? = nil,
        color: Color = RemindersColors.accentBlue,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.icon = icon
        self.color = color
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: RemindersKit.Spacing.xs) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .semibold))
                }

                Text(title)
                    .font(RemindersTypography.subheadlineBold)
            }
            .foregroundColor(color)
        }
    }
}

// MARK: - Button Styles for SwiftUI Button

struct RemindersButtonPressedStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? RemindersKit.Opacity.pressed : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(RemindersKit.Animation.quick, value: configuration.isPressed)
    }
}

struct RemindersScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(RemindersKit.Animation.quick, value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == RemindersButtonPressedStyle {
    static var remindersPressedStyle: RemindersButtonPressedStyle { .init() }
}

extension ButtonStyle where Self == RemindersScaleButtonStyle {
    static var remindersScaleStyle: RemindersScaleButtonStyle { .init() }
}

// MARK: - Preview

#Preview {
    ScrollView {
        VStack(spacing: 24) {
            // Primary buttons
            Group {
                Text("Primary Buttons")
                    .font(RemindersTypography.headline)
                    .foregroundColor(RemindersColors.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                PrimaryButton("Add New Task", icon: "plus") {
                    print("Primary tapped")
                }

                PrimaryButton("Save Changes") {
                    print("Primary tapped")
                }

                PrimaryButton("Loading...", isLoading: true) {
                    print("Loading tapped")
                }

                PrimaryButton("Disabled", isDisabled: true) {
                    print("Disabled tapped")
                }
            }

            // Secondary buttons
            Group {
                Text("Secondary Buttons")
                    .font(RemindersTypography.headline)
                    .foregroundColor(RemindersColors.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                PrimaryButton("Edit List", icon: "pencil", style: .secondary) {
                    print("Secondary tapped")
                }

                PrimaryButton("Cancel", style: .secondary) {
                    print("Secondary tapped")
                }
            }

            // Destructive buttons
            Group {
                Text("Destructive Buttons")
                    .font(RemindersTypography.headline)
                    .foregroundColor(RemindersColors.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                PrimaryButton("Delete Task", icon: "trash", style: .destructive) {
                    print("Destructive tapped")
                }
            }

            // Button sizes
            Group {
                Text("Button Sizes")
                    .font(RemindersTypography.headline)
                    .foregroundColor(RemindersColors.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 12) {
                    PrimaryButton("Small", size: .small) { }
                    PrimaryButton("Medium", size: .medium) { }
                    PrimaryButton("Large", size: .large) { }
                }
            }

            // Icon buttons
            Group {
                Text("Icon Buttons")
                    .font(RemindersTypography.headline)
                    .foregroundColor(RemindersColors.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 16) {
                    CloseButton { }
                    AddButton { }
                    IconButton(icon: "bell", style: .secondary) { }
                    IconButton(icon: "trash", style: .destructive) { }
                }
            }

            // Text buttons
            Group {
                Text("Text Buttons")
                    .font(RemindersTypography.headline)
                    .foregroundColor(RemindersColors.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 24) {
                    TextButton("Add Reminder", icon: "plus.circle.fill") { }
                    TextButton("Delete", icon: "trash", color: RemindersColors.accentRed) { }
                }
            }
        }
        .padding()
    }
    .background(RemindersColors.background)
}
