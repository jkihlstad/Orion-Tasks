//
//  ListColorPicker.swift
//  TasksApp
//
//  Color selection grid for task lists matching Apple Reminders
//

import SwiftUI

// MARK: - List Color Picker

struct ListColorPicker: View {
    @Binding var selectedColor: ListColor

    // Grid configuration
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 6)

    var body: some View {
        VStack(alignment: .leading, spacing: RemindersKit.Spacing.md) {
            Text("Color")
                .font(RemindersTypography.footnote)
                .foregroundColor(RemindersColors.textSecondary)
                .textCase(.uppercase)

            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(ListColor.allCases, id: \.self) { color in
                    ColorCell(
                        color: color,
                        isSelected: selectedColor == color,
                        action: { selectedColor = color }
                    )
                }
            }
        }
        .padding(RemindersKit.Spacing.lg)
        .background(RemindersColors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: RemindersKit.Radius.insetGrouped))
    }
}

// MARK: - Color Cell

private struct ColorCell: View {
    let color: ListColor
    let isSelected: Bool
    let action: () -> Void

    private let size: CGFloat = 44

    var body: some View {
        Button(action: action) {
            ZStack {
                // Color circle
                Circle()
                    .fill(color.color)
                    .frame(width: size, height: size)

                // Selection indicator
                if isSelected {
                    Circle()
                        .stroke(Color.white, lineWidth: 3)
                        .frame(width: size - 8, height: size - 8)

                    Image(systemName: "checkmark")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                }
            }
        }
        .buttonStyle(.plain)
        .animation(RemindersKit.Animation.quick, value: isSelected)
    }
}

// MARK: - Compact Color Picker

/// A more compact horizontal color picker for inline use
struct CompactColorPicker: View {
    @Binding var selectedColor: ListColor
    let colors: [ListColor]

    init(selectedColor: Binding<ListColor>, colors: [ListColor] = ListColor.allCases) {
        self._selectedColor = selectedColor
        self.colors = colors
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: RemindersKit.Spacing.sm) {
                ForEach(colors, id: \.self) { color in
                    CompactColorCell(
                        color: color,
                        isSelected: selectedColor == color,
                        action: { selectedColor = color }
                    )
                }
            }
            .padding(.horizontal, RemindersKit.Spacing.lg)
            .padding(.vertical, RemindersKit.Spacing.sm)
        }
    }
}

// MARK: - Compact Color Cell

private struct CompactColorCell: View {
    let color: ListColor
    let isSelected: Bool
    let action: () -> Void

    private let size: CGFloat = 32

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(color.color)
                .frame(width: size, height: size)
                .overlay(
                    Circle()
                        .stroke(Color.white, lineWidth: isSelected ? 2 : 0)
                        .frame(width: size - 6, height: size - 6)
                )
                .shadow(
                    color: isSelected ? color.color.opacity(0.4) : .clear,
                    radius: 4,
                    x: 0,
                    y: 2
                )
        }
        .buttonStyle(.plain)
        .animation(RemindersKit.Animation.quick, value: isSelected)
    }
}

// MARK: - Preview

#Preview("Grid Picker") {
    struct PreviewWrapper: View {
        @State private var selectedColor: ListColor = .blue

        var body: some View {
            VStack(spacing: 24) {
                // Preview icon with selected color
                ZStack {
                    Circle()
                        .fill(selectedColor.color)
                        .frame(width: 80, height: 80)

                    Image(systemName: "list.bullet")
                        .font(.system(size: 36, weight: .bold))
                        .foregroundColor(.white)
                }
                .padding(.top, 32)

                Text("Selected: \(selectedColor.rawValue.capitalized)")
                    .font(RemindersTypography.headline)
                    .foregroundColor(RemindersColors.textPrimary)

                ListColorPicker(selectedColor: $selectedColor)
                    .padding(.horizontal, RemindersKit.Spacing.lg)

                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RemindersColors.backgroundElevated)
        }
    }

    return PreviewWrapper()
}

#Preview("Compact Picker") {
    struct PreviewWrapper: View {
        @State private var selectedColor: ListColor = .orange

        var body: some View {
            VStack(spacing: 24) {
                // Preview icon with selected color
                ZStack {
                    Circle()
                        .fill(selectedColor.color)
                        .frame(width: 60, height: 60)

                    Image(systemName: "star.fill")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(.white)
                }
                .padding(.top, 32)

                CompactColorPicker(selectedColor: $selectedColor)
                    .background(RemindersColors.backgroundSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: RemindersKit.Radius.lg))
                    .padding(.horizontal, RemindersKit.Spacing.lg)

                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RemindersColors.backgroundElevated)
        }
    }

    return PreviewWrapper()
}
