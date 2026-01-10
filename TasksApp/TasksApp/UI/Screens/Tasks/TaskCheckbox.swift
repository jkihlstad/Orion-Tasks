//
//  TaskCheckbox.swift
//  TasksApp
//
//  Animated checkbox component matching Apple Reminders style
//

import SwiftUI

// MARK: - Task Checkbox

struct TaskCheckbox: View {

    // MARK: - Properties

    @Binding var isChecked: Bool
    let color: Color
    let size: CheckboxSize
    let onToggle: (() -> Void)?

    // MARK: - Animation State

    @State private var checkmarkScale: CGFloat = 0
    @State private var fillScale: CGFloat = 0
    @State private var borderOpacity: Double = 1
    @State private var isAnimating = false

    // MARK: - Initialization

    init(
        isChecked: Binding<Bool>,
        color: Color = RemindersColors.accentBlue,
        size: CheckboxSize = .standard,
        onToggle: (() -> Void)? = nil
    ) {
        self._isChecked = isChecked
        self.color = color
        self.size = size
        self.onToggle = onToggle
    }

    // MARK: - Body

    var body: some View {
        Button(action: toggle) {
            ZStack {
                // Outer circle (border)
                Circle()
                    .stroke(borderColor, lineWidth: size.borderWidth)
                    .frame(width: size.diameter, height: size.diameter)
                    .opacity(borderOpacity)

                // Fill circle (appears on check)
                Circle()
                    .fill(color)
                    .frame(width: size.diameter, height: size.diameter)
                    .scaleEffect(fillScale)

                // Checkmark
                Image(systemName: "checkmark")
                    .font(.system(size: size.checkmarkSize, weight: .bold))
                    .foregroundColor(.white)
                    .scaleEffect(checkmarkScale)
            }
        }
        .buttonStyle(.plain)
        .frame(width: size.touchTarget, height: size.touchTarget)
        .contentShape(Rectangle())
        .onAppear {
            // Set initial state without animation
            if isChecked {
                checkmarkScale = 1
                fillScale = 1
                borderOpacity = 0
            }
        }
        .onChange(of: isChecked) { _, newValue in
            animateCheckbox(to: newValue)
        }
    }

    // MARK: - Computed Properties

    private var borderColor: Color {
        isChecked ? color : RemindersColors.checkboxBorder
    }

    // MARK: - Actions

    private func toggle() {
        guard !isAnimating else { return }

        // Haptic feedback
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()

        isChecked.toggle()
        onToggle?()
    }

    // MARK: - Animation

    private func animateCheckbox(to checked: Bool) {
        isAnimating = true

        if checked {
            // Animate to checked state
            withAnimation(RemindersKit.Animation.completion) {
                fillScale = 1
                borderOpacity = 0
            }

            // Checkmark appears with slight delay and bounce
            withAnimation(
                .spring(response: 0.3, dampingFraction: 0.5)
                .delay(0.05)
            ) {
                checkmarkScale = 1
            }
        } else {
            // Animate to unchecked state
            withAnimation(RemindersKit.Animation.quick) {
                checkmarkScale = 0
            }

            withAnimation(RemindersKit.Animation.quick.delay(0.1)) {
                fillScale = 0
                borderOpacity = 1
            }
        }

        // Reset animating flag
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            isAnimating = false
        }
    }
}

// MARK: - Checkbox Size

enum CheckboxSize {
    case small
    case standard
    case large

    var diameter: CGFloat {
        switch self {
        case .small: return 18
        case .standard: return 22
        case .large: return 28
        }
    }

    var borderWidth: CGFloat {
        switch self {
        case .small: return 1.5
        case .standard: return 2
        case .large: return 2.5
        }
    }

    var checkmarkSize: CGFloat {
        switch self {
        case .small: return 10
        case .standard: return 12
        case .large: return 16
        }
    }

    var touchTarget: CGFloat {
        switch self {
        case .small: return 36
        case .standard: return 44
        case .large: return 48
        }
    }
}

// MARK: - Priority Checkbox

/// Checkbox that shows priority with exclamation marks
struct PriorityCheckbox: View {
    @Binding var isChecked: Bool
    let priority: Priority
    let listColor: Color
    let onToggle: (() -> Void)?

    init(
        isChecked: Binding<Bool>,
        priority: Priority = .none,
        listColor: Color = RemindersColors.accentBlue,
        onToggle: (() -> Void)? = nil
    ) {
        self._isChecked = isChecked
        self.priority = priority
        self.listColor = listColor
        self.onToggle = onToggle
    }

    var body: some View {
        HStack(spacing: 2) {
            // Priority indicators (exclamation marks)
            if priority != .none && !isChecked {
                ForEach(0..<priority.rawValue, id: \.self) { _ in
                    Text("!")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(priorityColor)
                }
            }

            TaskCheckbox(
                isChecked: $isChecked,
                color: checkboxColor,
                onToggle: onToggle
            )
        }
    }

    private var checkboxColor: Color {
        if isChecked {
            return listColor
        }
        switch priority {
        case .none: return listColor
        case .low: return RemindersColors.priorityLow
        case .medium: return RemindersColors.priorityMedium
        case .high: return RemindersColors.priorityHigh
        }
    }

    private var priorityColor: Color {
        switch priority {
        case .none: return .clear
        case .low: return RemindersColors.priorityLow
        case .medium: return RemindersColors.priorityMedium
        case .high: return RemindersColors.priorityHigh
        }
    }
}

// MARK: - Subtask Checkbox

/// Smaller checkbox for subtasks
struct SubtaskCheckbox: View {
    @Binding var isChecked: Bool
    let color: Color
    let onToggle: (() -> Void)?

    init(
        isChecked: Binding<Bool>,
        color: Color = RemindersColors.accentBlue,
        onToggle: (() -> Void)? = nil
    ) {
        self._isChecked = isChecked
        self.color = color
        self.onToggle = onToggle
    }

    var body: some View {
        TaskCheckbox(
            isChecked: $isChecked,
            color: color,
            size: .small,
            onToggle: onToggle
        )
    }
}

// MARK: - Preview

#Preview("Task Checkbox") {
    struct PreviewWrapper: View {
        @State private var checked1 = false
        @State private var checked2 = true
        @State private var checked3 = false
        @State private var checked4 = false
        @State private var checked5 = false

        var body: some View {
            VStack(spacing: 32) {
                // Standard checkboxes
                Group {
                    Text("Standard Checkbox")
                        .font(RemindersTypography.headline)
                        .foregroundColor(RemindersColors.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    HStack(spacing: 24) {
                        VStack {
                            TaskCheckbox(isChecked: $checked1)
                            Text("Unchecked")
                                .font(RemindersTypography.caption2)
                                .foregroundColor(RemindersColors.textSecondary)
                        }

                        VStack {
                            TaskCheckbox(isChecked: $checked2)
                            Text("Checked")
                                .font(RemindersTypography.caption2)
                                .foregroundColor(RemindersColors.textSecondary)
                        }
                    }
                }

                // Sizes
                Group {
                    Text("Sizes")
                        .font(RemindersTypography.headline)
                        .foregroundColor(RemindersColors.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    HStack(spacing: 24) {
                        VStack {
                            TaskCheckbox(isChecked: $checked3, size: .small)
                            Text("Small")
                                .font(RemindersTypography.caption2)
                                .foregroundColor(RemindersColors.textSecondary)
                        }

                        VStack {
                            TaskCheckbox(isChecked: $checked4, size: .standard)
                            Text("Standard")
                                .font(RemindersTypography.caption2)
                                .foregroundColor(RemindersColors.textSecondary)
                        }

                        VStack {
                            TaskCheckbox(isChecked: $checked5, size: .large)
                            Text("Large")
                                .font(RemindersTypography.caption2)
                                .foregroundColor(RemindersColors.textSecondary)
                        }
                    }
                }

                // Colors
                Group {
                    Text("Colors")
                        .font(RemindersTypography.headline)
                        .foregroundColor(RemindersColors.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    HStack(spacing: 24) {
                        TaskCheckbox(isChecked: .constant(true), color: RemindersColors.accentBlue)
                        TaskCheckbox(isChecked: .constant(true), color: RemindersColors.accentRed)
                        TaskCheckbox(isChecked: .constant(true), color: RemindersColors.accentOrange)
                        TaskCheckbox(isChecked: .constant(true), color: RemindersColors.accentGreen)
                        TaskCheckbox(isChecked: .constant(true), color: RemindersColors.accentPurple)
                    }
                }

                // Priority checkboxes
                Group {
                    Text("Priority Checkboxes")
                        .font(RemindersTypography.headline)
                        .foregroundColor(RemindersColors.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    HStack(spacing: 24) {
                        PriorityCheckbox(isChecked: .constant(false), priority: .none)
                        PriorityCheckbox(isChecked: .constant(false), priority: .low)
                        PriorityCheckbox(isChecked: .constant(false), priority: .medium)
                        PriorityCheckbox(isChecked: .constant(false), priority: .high)
                    }
                }

                Spacer()
            }
            .padding()
            .background(RemindersColors.background)
        }
    }

    return PreviewWrapper()
}
