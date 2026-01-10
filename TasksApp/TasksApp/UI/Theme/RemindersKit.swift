//
//  RemindersKit.swift
//  TasksApp
//
//  Design tokens, spacing, corner radii, shadows for Apple Reminders style
//

import SwiftUI

// MARK: - Design Tokens

struct RemindersKit {

    // MARK: - Spacing Scale

    enum Spacing {
        /// 2pt - Minimal spacing
        static let xxxs: CGFloat = 2

        /// 4pt - Extra extra small
        static let xxs: CGFloat = 4

        /// 6pt - Extra small
        static let xs: CGFloat = 6

        /// 8pt - Small
        static let sm: CGFloat = 8

        /// 12pt - Medium small
        static let md: CGFloat = 12

        /// 16pt - Medium (standard)
        static let lg: CGFloat = 16

        /// 20pt - Large
        static let xl: CGFloat = 20

        /// 24pt - Extra large
        static let xxl: CGFloat = 24

        /// 32pt - Extra extra large
        static let xxxl: CGFloat = 32

        /// 40pt - Huge
        static let huge: CGFloat = 40

        /// 48pt - Massive
        static let massive: CGFloat = 48

        // MARK: - Semantic Spacing

        /// Standard list row horizontal padding
        static let listRowHorizontal: CGFloat = 16

        /// Standard list row vertical padding
        static let listRowVertical: CGFloat = 11

        /// Inset grouped list horizontal inset
        static let insetGroupedHorizontal: CGFloat = 16

        /// Section header top padding
        static let sectionHeaderTop: CGFloat = 24

        /// Section header bottom padding
        static let sectionHeaderBottom: CGFloat = 8

        /// Modal sheet top padding
        static let sheetTop: CGFloat = 20

        /// Standard icon-to-text spacing
        static let iconText: CGFloat = 12

        /// Checkbox to content spacing
        static let checkboxContent: CGFloat = 12

        /// Standard button padding
        static let buttonPaddingH: CGFloat = 20
        static let buttonPaddingV: CGFloat = 14

        /// Navigation bar height
        static let navBarHeight: CGFloat = 44

        /// Tab bar height
        static let tabBarHeight: CGFloat = 49

        /// Search bar height
        static let searchBarHeight: CGFloat = 36
    }

    // MARK: - Corner Radius

    enum Radius {
        /// 4pt - Subtle rounding
        static let xs: CGFloat = 4

        /// 6pt - Small elements
        static let sm: CGFloat = 6

        /// 8pt - Buttons, small cards
        static let md: CGFloat = 8

        /// 10pt - Standard cards
        static let lg: CGFloat = 10

        /// 12pt - Large cards
        static let xl: CGFloat = 12

        /// 14pt - Extra large
        static let xxl: CGFloat = 14

        /// 16pt - Sheets
        static let xxxl: CGFloat = 16

        /// Full circle
        static let full: CGFloat = .infinity

        // MARK: - Semantic Radii

        /// Inset grouped list corner radius
        static let insetGrouped: CGFloat = 10

        /// Modal sheet corner radius
        static let sheet: CGFloat = 12

        /// Button corner radius
        static let button: CGFloat = 10

        /// Small button corner radius
        static let buttonSmall: CGFloat = 8

        /// Checkbox corner radius
        static let checkbox: CGFloat = 11

        /// Tag/chip corner radius
        static let tag: CGFloat = 6

        /// Search bar corner radius
        static let searchBar: CGFloat = 10

        /// Context menu corner radius
        static let contextMenu: CGFloat = 14

        /// List icon corner radius
        static let listIcon: CGFloat = 7
    }

    // MARK: - Sizes

    enum Size {
        /// Checkbox size
        static let checkbox: CGFloat = 22

        /// Small checkbox
        static let checkboxSmall: CGFloat = 18

        /// Standard icon size
        static let icon: CGFloat = 22

        /// Small icon
        static let iconSmall: CGFloat = 17

        /// Large icon
        static let iconLarge: CGFloat = 28

        /// Extra large icon (empty states)
        static let iconXL: CGFloat = 48

        /// Huge icon (onboarding)
        static let iconHuge: CGFloat = 72

        /// List color icon size
        static let listIcon: CGFloat = 28

        /// Avatar/profile picture small
        static let avatarSmall: CGFloat = 32

        /// Avatar/profile picture medium
        static let avatarMedium: CGFloat = 44

        /// Avatar/profile picture large
        static let avatarLarge: CGFloat = 64

        /// Minimum touch target
        static let touchTarget: CGFloat = 44

        /// Badge size
        static let badge: CGFloat = 20

        /// Small badge
        static let badgeSmall: CGFloat = 16

        /// Beacon badge size
        static let beacon: CGFloat = 12

        /// Row height standard
        static let rowHeight: CGFloat = 44

        /// Row height with subtitle
        static let rowHeightLarge: CGFloat = 60

        /// Drag handle width
        static let dragHandle: CGFloat = 36

        /// Drag handle height
        static let dragHandleHeight: CGFloat = 5

        /// Sheet grabber width
        static let sheetGrabber: CGFloat = 36

        /// Sheet grabber height
        static let sheetGrabberHeight: CGFloat = 5
    }

    // MARK: - Shadows

    enum Shadow {
        /// Subtle shadow for cards
        static let subtle = ShadowStyle(
            color: Color.black.opacity(0.15),
            radius: 8,
            x: 0,
            y: 2
        )

        /// Medium shadow for floating elements
        static let medium = ShadowStyle(
            color: Color.black.opacity(0.25),
            radius: 16,
            x: 0,
            y: 4
        )

        /// Strong shadow for modals
        static let strong = ShadowStyle(
            color: Color.black.opacity(0.4),
            radius: 24,
            x: 0,
            y: 8
        )

        /// Glow effect for selected items
        static let glow = ShadowStyle(
            color: RemindersColors.accentBlue.opacity(0.4),
            radius: 8,
            x: 0,
            y: 0
        )

        /// Inner shadow simulation
        static let inner = ShadowStyle(
            color: Color.black.opacity(0.2),
            radius: 3,
            x: 0,
            y: 1
        )
    }

    // MARK: - Border Widths

    enum Border {
        /// Hairline border (0.5pt)
        static let hairline: CGFloat = 0.5

        /// Thin border (1pt)
        static let thin: CGFloat = 1

        /// Medium border (1.5pt)
        static let medium: CGFloat = 1.5

        /// Thick border (2pt)
        static let thick: CGFloat = 2

        /// Focus ring width
        static let focusRing: CGFloat = 3
    }

    // MARK: - Animation

    enum Animation {
        /// Quick animation (0.15s)
        static let quick: SwiftUI.Animation = .easeInOut(duration: 0.15)

        /// Standard animation (0.25s)
        static let standard: SwiftUI.Animation = .easeInOut(duration: 0.25)

        /// Smooth animation (0.35s)
        static let smooth: SwiftUI.Animation = .easeInOut(duration: 0.35)

        /// Spring animation
        static let spring: SwiftUI.Animation = .spring(response: 0.35, dampingFraction: 0.7)

        /// Bouncy spring
        static let bouncy: SwiftUI.Animation = .spring(response: 0.4, dampingFraction: 0.6)

        /// Slow animation (0.5s)
        static let slow: SwiftUI.Animation = .easeInOut(duration: 0.5)

        /// Completion checkmark animation
        static let completion: SwiftUI.Animation = .spring(response: 0.3, dampingFraction: 0.6)
    }

    // MARK: - Opacity

    enum Opacity {
        /// Fully visible
        static let full: Double = 1.0

        /// Slightly faded
        static let high: Double = 0.87

        /// Medium opacity
        static let medium: Double = 0.6

        /// Low opacity
        static let low: Double = 0.38

        /// Disabled state
        static let disabled: Double = 0.38

        /// Hint/placeholder
        static let hint: Double = 0.5

        /// Pressed state
        static let pressed: Double = 0.7

        /// Overlay background
        static let overlay: Double = 0.5

        /// Scrim/dimming background
        static let scrim: Double = 0.4
    }
}

// MARK: - Shadow Style

struct ShadowStyle {
    let color: Color
    let radius: CGFloat
    let x: CGFloat
    let y: CGFloat
}

// MARK: - View Extensions for Shadows

extension View {

    /// Apply a RemindersKit shadow style
    func remindersShadow(_ style: ShadowStyle) -> some View {
        self.shadow(
            color: style.color,
            radius: style.radius,
            x: style.x,
            y: style.y
        )
    }

    /// Apply subtle shadow
    func subtleShadow() -> some View {
        remindersShadow(RemindersKit.Shadow.subtle)
    }

    /// Apply medium shadow
    func mediumShadow() -> some View {
        remindersShadow(RemindersKit.Shadow.medium)
    }

    /// Apply strong shadow
    func strongShadow() -> some View {
        remindersShadow(RemindersKit.Shadow.strong)
    }
}

// MARK: - Inset Grouped List Style

struct RemindersGroupedStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(RemindersColors.backgroundGrouped)
    }
}

extension View {
    /// Apply Reminders-style inset grouped list styling
    func remindersGroupedStyle() -> some View {
        modifier(RemindersGroupedStyle())
    }
}

// MARK: - Card Style

struct RemindersCardStyle: ViewModifier {
    let isPressed: Bool

    init(isPressed: Bool = false) {
        self.isPressed = isPressed
    }

    func body(content: Content) -> some View {
        content
            .background(RemindersColors.backgroundSecondary)
            .clipShape(RoundedRectangle(cornerRadius: RemindersKit.Radius.insetGrouped))
            .opacity(isPressed ? RemindersKit.Opacity.pressed : RemindersKit.Opacity.full)
    }
}

extension View {
    /// Apply Reminders-style card styling
    func remindersCard(isPressed: Bool = false) -> some View {
        modifier(RemindersCardStyle(isPressed: isPressed))
    }
}

// MARK: - List Row Style

struct RemindersListRowStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .listRowBackground(RemindersColors.backgroundSecondary)
            .listRowSeparatorTint(RemindersColors.separator)
            .listRowInsets(EdgeInsets(
                top: RemindersKit.Spacing.listRowVertical,
                leading: RemindersKit.Spacing.listRowHorizontal,
                bottom: RemindersKit.Spacing.listRowVertical,
                trailing: RemindersKit.Spacing.listRowHorizontal
            ))
    }
}

extension View {
    /// Apply Reminders-style list row styling
    func remindersListRow() -> some View {
        modifier(RemindersListRowStyle())
    }
}

// MARK: - Sheet Style

struct RemindersSheetStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(RemindersColors.backgroundElevated)
            .presentationBackground(RemindersColors.backgroundElevated)
            .presentationCornerRadius(RemindersKit.Radius.sheet)
            .presentationDragIndicator(.visible)
    }
}

extension View {
    /// Apply Reminders-style sheet styling
    func remindersSheet() -> some View {
        modifier(RemindersSheetStyle())
    }
}

// MARK: - Preview

#Preview {
    ScrollView {
        VStack(alignment: .leading, spacing: 24) {
            // Spacing visualization
            Group {
                Text("Spacing Scale")
                    .font(RemindersTypography.headline)
                    .foregroundColor(RemindersColors.textPrimary)

                HStack(spacing: 8) {
                    spacingBlock(RemindersKit.Spacing.xxs, label: "xxs")
                    spacingBlock(RemindersKit.Spacing.xs, label: "xs")
                    spacingBlock(RemindersKit.Spacing.sm, label: "sm")
                    spacingBlock(RemindersKit.Spacing.md, label: "md")
                    spacingBlock(RemindersKit.Spacing.lg, label: "lg")
                    spacingBlock(RemindersKit.Spacing.xl, label: "xl")
                }
            }

            // Corner radius visualization
            Group {
                Text("Corner Radii")
                    .font(RemindersTypography.headline)
                    .foregroundColor(RemindersColors.textPrimary)

                HStack(spacing: 12) {
                    radiusBlock(RemindersKit.Radius.sm, label: "sm")
                    radiusBlock(RemindersKit.Radius.md, label: "md")
                    radiusBlock(RemindersKit.Radius.lg, label: "lg")
                    radiusBlock(RemindersKit.Radius.xl, label: "xl")
                }
            }

            // Shadows
            Group {
                Text("Shadows")
                    .font(RemindersTypography.headline)
                    .foregroundColor(RemindersColors.textPrimary)

                HStack(spacing: 24) {
                    shadowBlock(RemindersKit.Shadow.subtle, label: "Subtle")
                    shadowBlock(RemindersKit.Shadow.medium, label: "Medium")
                    shadowBlock(RemindersKit.Shadow.strong, label: "Strong")
                }
            }

            // Card example
            Group {
                Text("Card Style")
                    .font(RemindersTypography.headline)
                    .foregroundColor(RemindersColors.textPrimary)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Task Title")
                        .font(RemindersTypography.body)
                        .foregroundColor(RemindersColors.textPrimary)

                    Text("Some additional notes here")
                        .font(RemindersTypography.subheadline)
                        .foregroundColor(RemindersColors.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(RemindersKit.Spacing.lg)
                .remindersCard()
            }
        }
        .padding()
    }
    .background(RemindersColors.background)
}

@ViewBuilder
private func spacingBlock(_ spacing: CGFloat, label: String) -> some View {
    VStack(spacing: 4) {
        Rectangle()
            .fill(RemindersColors.accentBlue)
            .frame(width: spacing, height: 40)

        Text(label)
            .font(RemindersTypography.caption2)
            .foregroundColor(RemindersColors.textSecondary)
    }
}

@ViewBuilder
private func radiusBlock(_ radius: CGFloat, label: String) -> some View {
    VStack(spacing: 4) {
        RoundedRectangle(cornerRadius: radius)
            .fill(RemindersColors.backgroundTertiary)
            .frame(width: 50, height: 50)

        Text(label)
            .font(RemindersTypography.caption2)
            .foregroundColor(RemindersColors.textSecondary)
    }
}

@ViewBuilder
private func shadowBlock(_ shadow: ShadowStyle, label: String) -> some View {
    VStack(spacing: 8) {
        RoundedRectangle(cornerRadius: RemindersKit.Radius.md)
            .fill(RemindersColors.backgroundSecondary)
            .frame(width: 60, height: 60)
            .remindersShadow(shadow)

        Text(label)
            .font(RemindersTypography.caption2)
            .foregroundColor(RemindersColors.textSecondary)
    }
}
