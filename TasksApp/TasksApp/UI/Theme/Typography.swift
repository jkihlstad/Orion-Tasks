//
//  Typography.swift
//  TasksApp
//
//  Text styles matching Apple Reminders typography system
//

import SwiftUI

// MARK: - Typography System

struct RemindersTypography {

    // MARK: - Font Weights

    enum Weight {
        case regular
        case medium
        case semibold
        case bold
        case heavy

        var fontWeight: Font.Weight {
            switch self {
            case .regular: return .regular
            case .medium: return .medium
            case .semibold: return .semibold
            case .bold: return .bold
            case .heavy: return .heavy
            }
        }
    }

    // MARK: - Text Style Definitions

    /// Large title - 34pt Bold (navigation titles)
    static var largeTitle: Font {
        .system(size: 34, weight: .bold, design: .default)
    }

    /// Title 1 - 28pt Bold
    static var title1: Font {
        .system(size: 28, weight: .bold, design: .default)
    }

    /// Title 2 - 22pt Bold
    static var title2: Font {
        .system(size: 22, weight: .bold, design: .default)
    }

    /// Title 3 - 20pt Semibold
    static var title3: Font {
        .system(size: 20, weight: .semibold, design: .default)
    }

    /// Headline - 17pt Semibold (list headers, important labels)
    static var headline: Font {
        .system(size: 17, weight: .semibold, design: .default)
    }

    /// Body - 17pt Regular (primary content)
    static var body: Font {
        .system(size: 17, weight: .regular, design: .default)
    }

    /// Body Bold - 17pt Semibold
    static var bodyBold: Font {
        .system(size: 17, weight: .semibold, design: .default)
    }

    /// Callout - 16pt Regular
    static var callout: Font {
        .system(size: 16, weight: .regular, design: .default)
    }

    /// Callout Bold - 16pt Semibold
    static var calloutBold: Font {
        .system(size: 16, weight: .semibold, design: .default)
    }

    /// Subheadline - 15pt Regular (secondary text)
    static var subheadline: Font {
        .system(size: 15, weight: .regular, design: .default)
    }

    /// Subheadline Bold - 15pt Semibold
    static var subheadlineBold: Font {
        .system(size: 15, weight: .semibold, design: .default)
    }

    /// Footnote - 13pt Regular (metadata, timestamps)
    static var footnote: Font {
        .system(size: 13, weight: .regular, design: .default)
    }

    /// Footnote Bold - 13pt Semibold
    static var footnoteBold: Font {
        .system(size: 13, weight: .semibold, design: .default)
    }

    /// Caption 1 - 12pt Regular (small labels)
    static var caption1: Font {
        .system(size: 12, weight: .regular, design: .default)
    }

    /// Caption 1 Bold - 12pt Medium
    static var caption1Bold: Font {
        .system(size: 12, weight: .medium, design: .default)
    }

    /// Caption 2 - 11pt Regular (smallest text)
    static var caption2: Font {
        .system(size: 11, weight: .regular, design: .default)
    }

    /// Caption 2 Bold - 11pt Semibold
    static var caption2Bold: Font {
        .system(size: 11, weight: .semibold, design: .default)
    }

    // MARK: - Specialized Styles

    /// Navigation bar title
    static var navTitle: Font {
        .system(size: 17, weight: .semibold, design: .default)
    }

    /// Navigation bar large title
    static var navLargeTitle: Font {
        .system(size: 34, weight: .bold, design: .default)
    }

    /// Button text
    static var button: Font {
        .system(size: 17, weight: .semibold, design: .default)
    }

    /// Small button text
    static var buttonSmall: Font {
        .system(size: 15, weight: .semibold, design: .default)
    }

    /// Tab bar label
    static var tabBar: Font {
        .system(size: 10, weight: .medium, design: .default)
    }

    /// Badge text (for counts)
    static var badge: Font {
        .system(size: 15, weight: .medium, design: .rounded)
    }

    /// Large badge/count (like sidebar counts)
    static var badgeLarge: Font {
        .system(size: 17, weight: .semibold, design: .rounded)
    }

    /// Task title
    static var taskTitle: Font {
        .system(size: 17, weight: .regular, design: .default)
    }

    /// Task subtitle/notes
    static var taskSubtitle: Font {
        .system(size: 15, weight: .regular, design: .default)
    }

    /// Task metadata (date, priority)
    static var taskMetadata: Font {
        .system(size: 13, weight: .regular, design: .default)
    }

    /// List name in sidebar
    static var listName: Font {
        .system(size: 17, weight: .regular, design: .default)
    }

    /// Section header text
    static var sectionHeader: Font {
        .system(size: 13, weight: .regular, design: .default)
    }

    /// Section header text (uppercase style)
    static var sectionHeaderUppercase: Font {
        .system(size: 12, weight: .regular, design: .default)
    }

    // MARK: - Monospaced Variants

    /// Monospaced body (for code or IDs)
    static var monoBody: Font {
        .system(size: 17, weight: .regular, design: .monospaced)
    }

    /// Monospaced caption
    static var monoCaption: Font {
        .system(size: 12, weight: .regular, design: .monospaced)
    }

    // MARK: - Rounded Variants (for numbers, badges)

    /// Rounded body
    static var roundedBody: Font {
        .system(size: 17, weight: .regular, design: .rounded)
    }

    /// Rounded headline
    static var roundedHeadline: Font {
        .system(size: 17, weight: .semibold, design: .rounded)
    }

    /// Rounded large number
    static var roundedLarge: Font {
        .system(size: 28, weight: .bold, design: .rounded)
    }
}

// MARK: - Text Style Modifier

struct RemindersTextStyle: ViewModifier {
    let font: Font
    let color: Color
    let lineSpacing: CGFloat

    init(
        font: Font,
        color: Color = RemindersColors.textPrimary,
        lineSpacing: CGFloat = 0
    ) {
        self.font = font
        self.color = color
        self.lineSpacing = lineSpacing
    }

    func body(content: Content) -> some View {
        content
            .font(font)
            .foregroundColor(color)
            .lineSpacing(lineSpacing)
    }
}

// MARK: - View Extensions

extension View {

    /// Apply a Reminders text style
    func remindersTextStyle(
        _ font: Font,
        color: Color = RemindersColors.textPrimary
    ) -> some View {
        self.modifier(RemindersTextStyle(font: font, color: color))
    }

    // Convenience methods for common styles

    func largeTitleStyle() -> some View {
        remindersTextStyle(RemindersTypography.largeTitle)
    }

    func headlineStyle() -> some View {
        remindersTextStyle(RemindersTypography.headline)
    }

    func bodyStyle() -> some View {
        remindersTextStyle(RemindersTypography.body)
    }

    func secondaryBodyStyle() -> some View {
        remindersTextStyle(RemindersTypography.body, color: RemindersColors.textSecondary)
    }

    func captionStyle() -> some View {
        remindersTextStyle(RemindersTypography.caption1, color: RemindersColors.textSecondary)
    }

    func footnoteStyle() -> some View {
        remindersTextStyle(RemindersTypography.footnote, color: RemindersColors.textSecondary)
    }
}

// MARK: - Attributed String Support

extension RemindersTypography {

    /// Create attributed string attributes for a given style
    static func attributes(
        for font: Font,
        color: Color = RemindersColors.textPrimary
    ) -> AttributeContainer {
        var container = AttributeContainer()
        container.font = font
        container.foregroundColor = color
        return container
    }
}

// MARK: - Line Heights

extension RemindersTypography {

    /// Standard line heights for each text style
    enum LineHeight {
        static let largeTitle: CGFloat = 41
        static let title1: CGFloat = 34
        static let title2: CGFloat = 28
        static let title3: CGFloat = 25
        static let headline: CGFloat = 22
        static let body: CGFloat = 22
        static let callout: CGFloat = 21
        static let subheadline: CGFloat = 20
        static let footnote: CGFloat = 18
        static let caption1: CGFloat = 16
        static let caption2: CGFloat = 13
    }
}

// MARK: - Preview

#Preview {
    ScrollView {
        VStack(alignment: .leading, spacing: 16) {
            Group {
                Text("Large Title")
                    .font(RemindersTypography.largeTitle)

                Text("Title 1")
                    .font(RemindersTypography.title1)

                Text("Title 2")
                    .font(RemindersTypography.title2)

                Text("Title 3")
                    .font(RemindersTypography.title3)

                Text("Headline")
                    .font(RemindersTypography.headline)

                Text("Body")
                    .font(RemindersTypography.body)

                Text("Callout")
                    .font(RemindersTypography.callout)
            }
            .foregroundColor(RemindersColors.textPrimary)

            Group {
                Text("Subheadline")
                    .font(RemindersTypography.subheadline)

                Text("Footnote")
                    .font(RemindersTypography.footnote)

                Text("Caption 1")
                    .font(RemindersTypography.caption1)

                Text("Caption 2")
                    .font(RemindersTypography.caption2)
            }
            .foregroundColor(RemindersColors.textSecondary)

            Divider()
                .background(RemindersColors.separator)

            Group {
                Text("Task Title Style")
                    .font(RemindersTypography.taskTitle)
                    .foregroundColor(RemindersColors.textPrimary)

                Text("Task Subtitle")
                    .font(RemindersTypography.taskSubtitle)
                    .foregroundColor(RemindersColors.textSecondary)

                Text("Task Metadata - Today")
                    .font(RemindersTypography.taskMetadata)
                    .foregroundColor(RemindersColors.today)
            }

            Divider()
                .background(RemindersColors.separator)

            HStack {
                Text("Badge: ")
                    .font(RemindersTypography.body)
                    .foregroundColor(RemindersColors.textPrimary)

                Text("42")
                    .font(RemindersTypography.badge)
                    .foregroundColor(RemindersColors.textSecondary)
            }
        }
        .padding()
    }
    .background(RemindersColors.background)
}
