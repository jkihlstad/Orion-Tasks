//
//  Colors.swift
//  TasksApp
//
//  Dark-first color palette matching Apple Reminders
//

import SwiftUI

// MARK: - Color Extension

extension Color {

    // MARK: - Initialization from Hex

    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - Reminders Color Palette

struct RemindersColors {

    // MARK: - Background Colors (Dark Mode First)

    /// Primary background - deep black like Reminders
    static let background = Color(hex: "000000")

    /// Secondary background - slightly elevated surfaces
    static let backgroundSecondary = Color(hex: "1C1C1E")

    /// Tertiary background - cards and grouped content
    static let backgroundTertiary = Color(hex: "2C2C2E")

    /// Elevated surface background - modals, sheets
    static let backgroundElevated = Color(hex: "1C1C1E")

    /// Grouped list background (inset grouped style)
    static let backgroundGrouped = Color(hex: "000000")

    /// Grouped list content background
    static let backgroundGroupedContent = Color(hex: "1C1C1E")

    // MARK: - Text Colors

    /// Primary text - bright white
    static let textPrimary = Color(hex: "FFFFFF")

    /// Secondary text - dimmed for less emphasis
    static let textSecondary = Color(hex: "8E8E93")

    /// Tertiary text - subtle hints and placeholders
    static let textTertiary = Color(hex: "48484A")

    /// Inverted text for light backgrounds
    static let textInverted = Color(hex: "000000")

    // MARK: - Accent Colors (Apple Reminders Style)

    /// Blue accent - primary actions like in Reminders
    static let accentBlue = Color(hex: "0A84FF")

    /// Red accent - for delete, overdue, and beacon badges
    static let accentRed = Color(hex: "FF453A")

    /// Orange accent - for flagged items
    static let accentOrange = Color(hex: "FF9F0A")

    /// Yellow accent - for priorities
    static let accentYellow = Color(hex: "FFD60A")

    /// Green accent - for completed tasks
    static let accentGreen = Color(hex: "30D158")

    /// Cyan/Teal accent - for tags
    static let accentCyan = Color(hex: "64D2FF")

    /// Purple accent - for lists
    static let accentPurple = Color(hex: "BF5AF2")

    /// Pink accent - for lists
    static let accentPink = Color(hex: "FF375F")

    // MARK: - Semantic Colors

    /// Success state
    static let success = Color(hex: "30D158")

    /// Warning state
    static let warning = Color(hex: "FF9F0A")

    /// Error state
    static let error = Color(hex: "FF453A")

    /// Info state
    static let info = Color(hex: "0A84FF")

    // MARK: - UI Element Colors

    /// Separator lines
    static let separator = Color(hex: "38383A")

    /// Opaque separator with less contrast
    static let separatorOpaque = Color(hex: "48484A")

    /// Fill color for controls
    static let fill = Color(hex: "787880").opacity(0.36)

    /// Secondary fill
    static let fillSecondary = Color(hex: "787880").opacity(0.32)

    /// Tertiary fill
    static let fillTertiary = Color(hex: "767680").opacity(0.24)

    /// Quaternary fill
    static let fillQuaternary = Color(hex: "767680").opacity(0.18)

    // MARK: - Interactive States

    /// Tint color (matches system blue)
    static let tint = Color(hex: "0A84FF")

    /// Disabled state
    static let disabled = Color(hex: "3A3A3C")

    /// Pressed/highlighted state overlay
    static let highlight = Color.white.opacity(0.1)

    // MARK: - Task-Specific Colors

    /// Checkbox unchecked border
    static let checkboxBorder = Color(hex: "48484A")

    /// Checkbox checked fill
    static let checkboxFill = Color(hex: "0A84FF")

    /// Priority high
    static let priorityHigh = Color(hex: "FF453A")

    /// Priority medium
    static let priorityMedium = Color(hex: "FF9F0A")

    /// Priority low
    static let priorityLow = Color(hex: "0A84FF")

    /// Overdue date color
    static let overdue = Color(hex: "FF453A")

    /// Today date color
    static let today = Color(hex: "0A84FF")

    /// Scheduled date color
    static let scheduled = Color(hex: "8E8E93")

    // MARK: - List Colors (Reminders-style preset colors)

    static let listRed = Color(hex: "FF453A")
    static let listOrange = Color(hex: "FF9F0A")
    static let listYellow = Color(hex: "FFD60A")
    static let listGreen = Color(hex: "30D158")
    static let listCyan = Color(hex: "64D2FF")
    static let listBlue = Color(hex: "0A84FF")
    static let listPurple = Color(hex: "BF5AF2")
    static let listPink = Color(hex: "FF375F")
    static let listBrown = Color(hex: "AC8E68")
    static let listGray = Color(hex: "8E8E93")

    /// All available list colors
    static let listColors: [Color] = [
        listRed, listOrange, listYellow, listGreen, listCyan,
        listBlue, listPurple, listPink, listBrown, listGray
    ]
}

// MARK: - Color Scheme Adaptive Colors

extension RemindersColors {

    /// Creates an adaptive color that switches between dark and light modes
    static func adaptive(dark: Color, light: Color) -> Color {
        // For this dark-first implementation, we default to dark
        // In a full implementation, this would use @Environment(\.colorScheme)
        return dark
    }
}

// MARK: - SwiftUI Color Extensions for Easy Access

extension Color {

    // Background shortcuts
    static var remindersBackground: Color { RemindersColors.background }
    static var remindersBackgroundSecondary: Color { RemindersColors.backgroundSecondary }
    static var remindersBackgroundTertiary: Color { RemindersColors.backgroundTertiary }
    static var remindersBackgroundElevated: Color { RemindersColors.backgroundElevated }

    // Text shortcuts
    static var remindersTextPrimary: Color { RemindersColors.textPrimary }
    static var remindersTextSecondary: Color { RemindersColors.textSecondary }
    static var remindersTextTertiary: Color { RemindersColors.textTertiary }

    // Accent shortcuts
    static var remindersAccent: Color { RemindersColors.accentBlue }
    static var remindersDestructive: Color { RemindersColors.accentRed }
}

// MARK: - Preview

#Preview {
    ScrollView {
        VStack(alignment: .leading, spacing: 20) {
            // Backgrounds
            Group {
                Text("Backgrounds")
                    .font(.headline)
                    .foregroundColor(RemindersColors.textPrimary)

                HStack(spacing: 12) {
                    colorSwatch(RemindersColors.background, label: "Primary")
                    colorSwatch(RemindersColors.backgroundSecondary, label: "Secondary")
                    colorSwatch(RemindersColors.backgroundTertiary, label: "Tertiary")
                }
            }

            // Accents
            Group {
                Text("Accents")
                    .font(.headline)
                    .foregroundColor(RemindersColors.textPrimary)

                HStack(spacing: 12) {
                    colorSwatch(RemindersColors.accentBlue, label: "Blue")
                    colorSwatch(RemindersColors.accentRed, label: "Red")
                    colorSwatch(RemindersColors.accentOrange, label: "Orange")
                    colorSwatch(RemindersColors.accentGreen, label: "Green")
                }
            }

            // List Colors
            Group {
                Text("List Colors")
                    .font(.headline)
                    .foregroundColor(RemindersColors.textPrimary)

                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 12) {
                    ForEach(RemindersColors.listColors.indices, id: \.self) { index in
                        Circle()
                            .fill(RemindersColors.listColors[index])
                            .frame(width: 40, height: 40)
                    }
                }
            }
        }
        .padding()
    }
    .background(RemindersColors.background)
}

@ViewBuilder
private func colorSwatch(_ color: Color, label: String) -> some View {
    VStack(spacing: 4) {
        RoundedRectangle(cornerRadius: 8)
            .fill(color)
            .frame(width: 60, height: 60)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(RemindersColors.separator, lineWidth: 1)
            )

        Text(label)
            .font(.caption2)
            .foregroundColor(RemindersColors.textSecondary)
    }
}
