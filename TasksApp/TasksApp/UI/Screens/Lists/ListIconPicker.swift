//
//  ListIconPicker.swift
//  TasksApp
//
//  Icon selection grid for task lists matching Apple Reminders
//

import SwiftUI

// MARK: - List Icon Picker

struct ListIconPicker: View {
    @Binding var selectedIcon: ListIcon
    let accentColor: Color

    // Grid configuration - 6 columns like Apple Reminders
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 6)

    // Grouped icons for better organization
    private let iconGroups: [(String, [ListIcon])] = [
        ("General", [.list, .checklist, .calendar, .clock, .star, .heart, .bookmark, .flag, .bell]),
        ("Files", [.folder, .tray, .archiveBox, .doc, .book]),
        ("Work", [.graduationCap, .briefcase, .house, .building, .chart, .lightbulb]),
        ("Shopping", [.cart, .gift, .creditCard, .banknote, .percent]),
        ("Travel", [.airplane, .car, .bicycle, .figure, .mappin, .location, .globe]),
        ("Fitness", [.dumbbell, .sportscourt, .medical, .pill, .brain]),
        ("Entertainment", [.music, .gamecontroller, .film, .camera, .paintbrush]),
        ("Tools", [.wrench, .hammer, .wand, .sparkles]),
        ("Nature", [.leaf, .pawprint, .sun, .moon, .cloud, .bolt, .drop, .flame]),
        ("People", [.person, .person2, .person3, .phone, .envelope, .bubble]),
        ("Tech", [.battery, .wifi, .lock, .key]),
        ("Body", [.eyes, .ear, .hand])
    ]

    init(selectedIcon: Binding<ListIcon>, accentColor: Color = RemindersColors.accentBlue) {
        self._selectedIcon = selectedIcon
        self.accentColor = accentColor
    }

    var body: some View {
        VStack(alignment: .leading, spacing: RemindersKit.Spacing.md) {
            Text("Icon")
                .font(RemindersTypography.footnote)
                .foregroundColor(RemindersColors.textSecondary)
                .textCase(.uppercase)

            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(ListIcon.allCases, id: \.self) { icon in
                        IconCell(
                            icon: icon,
                            isSelected: selectedIcon == icon,
                            accentColor: accentColor,
                            action: { selectedIcon = icon }
                        )
                    }
                }
            }
            .frame(maxHeight: 280)
        }
        .padding(RemindersKit.Spacing.lg)
        .background(RemindersColors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: RemindersKit.Radius.insetGrouped))
    }
}

// MARK: - Icon Cell

private struct IconCell: View {
    let icon: ListIcon
    let isSelected: Bool
    let accentColor: Color
    let action: () -> Void

    private let size: CGFloat = 44

    var body: some View {
        Button(action: action) {
            ZStack {
                // Background circle
                Circle()
                    .fill(isSelected ? accentColor : RemindersColors.fillTertiary)
                    .frame(width: size, height: size)

                // Icon
                Image(systemName: icon.rawValue)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(isSelected ? .white : RemindersColors.textSecondary)
            }
        }
        .buttonStyle(.plain)
        .animation(RemindersKit.Animation.quick, value: isSelected)
    }
}

// MARK: - Grouped Icon Picker

/// An icon picker with section headers for better organization
struct GroupedIconPicker: View {
    @Binding var selectedIcon: ListIcon
    let accentColor: Color

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 6)

    private let iconGroups: [(String, [ListIcon])] = [
        ("General", [.list, .checklist, .calendar, .clock, .star, .heart, .bookmark, .flag, .bell]),
        ("Files", [.folder, .tray, .archiveBox, .doc, .book]),
        ("Work", [.graduationCap, .briefcase, .house, .building, .chart, .lightbulb]),
        ("Shopping", [.cart, .gift, .creditCard, .banknote, .percent]),
        ("Travel", [.airplane, .car, .bicycle, .figure, .mappin, .location, .globe]),
        ("Health", [.dumbbell, .sportscourt, .medical, .pill, .brain]),
        ("Entertainment", [.music, .gamecontroller, .film, .camera, .paintbrush]),
        ("Tools", [.wrench, .hammer, .wand, .sparkles]),
        ("Nature", [.leaf, .pawprint, .sun, .moon, .cloud, .bolt, .drop, .flame]),
        ("People", [.person, .person2, .person3, .phone, .envelope, .bubble]),
        ("Tech", [.battery, .wifi, .lock, .key]),
        ("Body", [.eyes, .ear, .hand])
    ]

    init(selectedIcon: Binding<ListIcon>, accentColor: Color = RemindersColors.accentBlue) {
        self._selectedIcon = selectedIcon
        self.accentColor = accentColor
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: RemindersKit.Spacing.xl) {
                ForEach(iconGroups, id: \.0) { group in
                    VStack(alignment: .leading, spacing: RemindersKit.Spacing.sm) {
                        Text(group.0)
                            .font(RemindersTypography.caption1Bold)
                            .foregroundColor(RemindersColors.textTertiary)
                            .textCase(.uppercase)

                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(group.1, id: \.self) { icon in
                                IconCell(
                                    icon: icon,
                                    isSelected: selectedIcon == icon,
                                    accentColor: accentColor,
                                    action: { selectedIcon = icon }
                                )
                            }
                        }
                    }
                }
            }
            .padding(RemindersKit.Spacing.lg)
        }
        .background(RemindersColors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: RemindersKit.Radius.insetGrouped))
    }
}

// MARK: - Compact Icon Picker

/// A compact horizontal scrolling icon picker
struct CompactIconPicker: View {
    @Binding var selectedIcon: ListIcon
    let accentColor: Color
    let icons: [ListIcon]

    init(
        selectedIcon: Binding<ListIcon>,
        accentColor: Color = RemindersColors.accentBlue,
        icons: [ListIcon] = Array(ListIcon.allCases.prefix(12))
    ) {
        self._selectedIcon = selectedIcon
        self.accentColor = accentColor
        self.icons = icons
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: RemindersKit.Spacing.sm) {
                ForEach(icons, id: \.self) { icon in
                    CompactIconCell(
                        icon: icon,
                        isSelected: selectedIcon == icon,
                        accentColor: accentColor,
                        action: { selectedIcon = icon }
                    )
                }
            }
            .padding(.horizontal, RemindersKit.Spacing.lg)
            .padding(.vertical, RemindersKit.Spacing.sm)
        }
    }
}

// MARK: - Compact Icon Cell

private struct CompactIconCell: View {
    let icon: ListIcon
    let isSelected: Bool
    let accentColor: Color
    let action: () -> Void

    private let size: CGFloat = 36

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(isSelected ? accentColor : RemindersColors.fillTertiary)
                    .frame(width: size, height: size)

                Image(systemName: icon.rawValue)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(isSelected ? .white : RemindersColors.textSecondary)
            }
        }
        .buttonStyle(.plain)
        .animation(RemindersKit.Animation.quick, value: isSelected)
    }
}

// MARK: - Preview

#Preview("Grid Picker") {
    struct PreviewWrapper: View {
        @State private var selectedIcon: ListIcon = .list
        @State private var selectedColor: ListColor = .blue

        var body: some View {
            VStack(spacing: 24) {
                // Preview icon with selected color
                ZStack {
                    Circle()
                        .fill(selectedColor.color)
                        .frame(width: 80, height: 80)

                    Image(systemName: selectedIcon.rawValue)
                        .font(.system(size: 36, weight: .bold))
                        .foregroundColor(.white)
                }
                .padding(.top, 32)

                Text(selectedIcon.displayName)
                    .font(RemindersTypography.headline)
                    .foregroundColor(RemindersColors.textPrimary)

                ListIconPicker(selectedIcon: $selectedIcon, accentColor: selectedColor.color)
                    .padding(.horizontal, RemindersKit.Spacing.lg)

                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RemindersColors.backgroundElevated)
        }
    }

    return PreviewWrapper()
}

#Preview("Grouped Picker") {
    struct PreviewWrapper: View {
        @State private var selectedIcon: ListIcon = .briefcase

        var body: some View {
            VStack(spacing: 16) {
                // Preview
                ZStack {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 60, height: 60)

                    Image(systemName: selectedIcon.rawValue)
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(.white)
                }
                .padding(.top, 24)

                GroupedIconPicker(selectedIcon: $selectedIcon, accentColor: .orange)
                    .frame(maxHeight: 400)
                    .padding(.horizontal, RemindersKit.Spacing.lg)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RemindersColors.backgroundElevated)
        }
    }

    return PreviewWrapper()
}

#Preview("Compact Picker") {
    struct PreviewWrapper: View {
        @State private var selectedIcon: ListIcon = .star

        var body: some View {
            VStack(spacing: 24) {
                ZStack {
                    Circle()
                        .fill(Color.purple)
                        .frame(width: 60, height: 60)

                    Image(systemName: selectedIcon.rawValue)
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(.white)
                }
                .padding(.top, 32)

                CompactIconPicker(selectedIcon: $selectedIcon, accentColor: .purple)
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
