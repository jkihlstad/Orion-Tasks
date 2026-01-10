//
//  RepeatRulePicker.swift
//  TasksApp
//
//  Repeat rule configuration component matching Apple Reminders style
//

import SwiftUI

// MARK: - Repeat Rule Picker

struct RepeatRulePicker: View {

    // MARK: - Properties

    @Binding var repeatRule: RepeatRule?
    @Binding var isEnabled: Bool

    // MARK: - State

    @State private var selectedFrequency: RepeatRule.Frequency = .daily
    @State private var interval: Int = 1
    @State private var selectedWeekDays: RepeatRule.WeekDay = .allDays
    @State private var endDate: Date? = nil
    @State private var hasEndDate = false
    @State private var isExpanded = false

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Main toggle row
            toggleRow

            // Expanded configuration
            if isEnabled && isExpanded {
                Divider()
                    .background(RemindersColors.separator)

                configurationSection
            }
        }
        .background(RemindersColors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: RemindersKit.Radius.lg))
        .onAppear {
            loadFromRepeatRule()
        }
    }

    // MARK: - Toggle Row

    private var toggleRow: some View {
        Button {
            withAnimation(RemindersKit.Animation.standard) {
                if isEnabled {
                    isExpanded.toggle()
                } else {
                    isEnabled = true
                    isExpanded = true
                    updateRepeatRule()
                }
            }
        } label: {
            HStack {
                ZStack {
                    RoundedRectangle(cornerRadius: RemindersKit.Radius.sm)
                        .fill(RemindersColors.accentGreen)
                        .frame(width: 30, height: 30)

                    Image(systemName: "repeat")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                }

                Text("Repeat")
                    .font(RemindersTypography.body)
                    .foregroundColor(RemindersColors.textPrimary)

                Spacer()

                if isEnabled {
                    Text(repeatRule?.displayDescription ?? "Never")
                        .font(RemindersTypography.body)
                        .foregroundColor(RemindersColors.accentBlue)

                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(RemindersColors.textTertiary)
                } else {
                    Toggle("", isOn: $isEnabled)
                        .labelsHidden()
                        .tint(RemindersColors.accentBlue)
                        .onChange(of: isEnabled) { _, newValue in
                            if newValue {
                                isExpanded = true
                                updateRepeatRule()
                            } else {
                                repeatRule = nil
                                isExpanded = false
                            }
                        }
                }
            }
            .padding(RemindersKit.Spacing.md)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Configuration Section

    private var configurationSection: some View {
        VStack(spacing: 0) {
            // Frequency picker
            frequencySection

            Divider()
                .background(RemindersColors.separator)
                .padding(.leading, 54)

            // Interval picker
            intervalSection

            // Week days picker (for weekly frequency)
            if selectedFrequency == .weekly {
                Divider()
                    .background(RemindersColors.separator)
                    .padding(.leading, 54)

                weekDaysSection
            }

            Divider()
                .background(RemindersColors.separator)
                .padding(.leading, 54)

            // End date
            endDateSection

            // Clear button
            Button {
                withAnimation(RemindersKit.Animation.quick) {
                    isEnabled = false
                    repeatRule = nil
                    isExpanded = false
                }
            } label: {
                Text("Don't Repeat")
                    .font(RemindersTypography.body)
                    .foregroundColor(RemindersColors.accentRed)
            }
            .padding(.vertical, RemindersKit.Spacing.md)
        }
    }

    // MARK: - Frequency Section

    private var frequencySection: some View {
        HStack {
            Text("Frequency")
                .font(RemindersTypography.body)
                .foregroundColor(RemindersColors.textPrimary)

            Spacer()

            Menu {
                ForEach([RepeatRule.Frequency.daily, .weekly, .monthly, .yearly], id: \.self) { frequency in
                    Button {
                        selectedFrequency = frequency
                        updateRepeatRule()
                    } label: {
                        HStack {
                            Text(frequency.displayName)
                            if selectedFrequency == frequency {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: RemindersKit.Spacing.xs) {
                    Text(selectedFrequency.displayName)
                        .font(RemindersTypography.body)
                        .foregroundColor(RemindersColors.accentBlue)

                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(RemindersColors.textSecondary)
                }
            }
        }
        .padding(RemindersKit.Spacing.md)
        .padding(.leading, 42)
    }

    // MARK: - Interval Section

    private var intervalSection: some View {
        HStack {
            Text("Every")
                .font(RemindersTypography.body)
                .foregroundColor(RemindersColors.textPrimary)

            Spacer()

            Stepper(value: $interval, in: 1...365) {
                Text("\(interval) \(intervalUnit)")
                    .font(RemindersTypography.body)
                    .foregroundColor(RemindersColors.accentBlue)
            }
            .onChange(of: interval) { _, _ in
                updateRepeatRule()
            }
        }
        .padding(RemindersKit.Spacing.md)
        .padding(.leading, 42)
    }

    private var intervalUnit: String {
        let unit: String
        switch selectedFrequency {
        case .daily: unit = "day"
        case .weekly: unit = "week"
        case .monthly: unit = "month"
        case .yearly: unit = "year"
        case .custom: unit = "time"
        }
        return interval == 1 ? unit : "\(unit)s"
    }

    // MARK: - Week Days Section

    private var weekDaysSection: some View {
        VStack(alignment: .leading, spacing: RemindersKit.Spacing.sm) {
            Text("On")
                .font(RemindersTypography.body)
                .foregroundColor(RemindersColors.textPrimary)
                .padding(.leading, 54)

            HStack(spacing: RemindersKit.Spacing.xs) {
                ForEach(weekDayOptions, id: \.day) { option in
                    WeekDayButton(
                        day: option.shortName,
                        isSelected: selectedWeekDays.contains(option.day)
                    ) {
                        if selectedWeekDays.contains(option.day) {
                            selectedWeekDays.remove(option.day)
                        } else {
                            selectedWeekDays.insert(option.day)
                        }
                        updateRepeatRule()
                    }
                }
            }
            .padding(.horizontal, RemindersKit.Spacing.md)
            .padding(.leading, 42)
        }
        .padding(.vertical, RemindersKit.Spacing.md)
    }

    private var weekDayOptions: [(day: RepeatRule.WeekDay, shortName: String)] {
        [
            (.sunday, "S"),
            (.monday, "M"),
            (.tuesday, "T"),
            (.wednesday, "W"),
            (.thursday, "T"),
            (.friday, "F"),
            (.saturday, "S")
        ]
    }

    // MARK: - End Date Section

    private var endDateSection: some View {
        VStack(spacing: 0) {
            HStack {
                Text("End Repeat")
                    .font(RemindersTypography.body)
                    .foregroundColor(RemindersColors.textPrimary)

                Spacer()

                if hasEndDate {
                    Menu {
                        Button("Never") {
                            hasEndDate = false
                            endDate = nil
                            updateRepeatRule()
                        }
                        Button("On Date...") {
                            // Keep hasEndDate true
                        }
                    } label: {
                        Text(formattedEndDate)
                            .font(RemindersTypography.body)
                            .foregroundColor(RemindersColors.accentBlue)
                    }
                } else {
                    Menu {
                        Button("Never") {
                            hasEndDate = false
                            endDate = nil
                        }
                        Button("On Date...") {
                            hasEndDate = true
                            endDate = Calendar.current.date(byAdding: .month, value: 1, to: Date())
                            updateRepeatRule()
                        }
                    } label: {
                        HStack(spacing: RemindersKit.Spacing.xs) {
                            Text("Never")
                                .font(RemindersTypography.body)
                                .foregroundColor(RemindersColors.textSecondary)

                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(RemindersColors.textSecondary)
                        }
                    }
                }
            }
            .padding(RemindersKit.Spacing.md)
            .padding(.leading, 42)

            if hasEndDate {
                DatePicker(
                    "End Date",
                    selection: Binding(
                        get: { endDate ?? Date() },
                        set: { newValue in
                            endDate = newValue
                            updateRepeatRule()
                        }
                    ),
                    in: Date()...,
                    displayedComponents: .date
                )
                .datePickerStyle(.graphical)
                .tint(RemindersColors.accentBlue)
                .padding(.horizontal, RemindersKit.Spacing.md)
                .padding(.leading, 42)
            }
        }
    }

    private var formattedEndDate: String {
        guard let date = endDate else { return "Never" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }

    // MARK: - Helper Methods

    private func loadFromRepeatRule() {
        guard let rule = repeatRule else { return }

        selectedFrequency = rule.frequency
        interval = rule.interval
        if let weekDays = rule.weekDays {
            selectedWeekDays = weekDays
        }
        endDate = rule.endDate
        hasEndDate = rule.endDate != nil
    }

    private func updateRepeatRule() {
        switch selectedFrequency {
        case .daily:
            repeatRule = .daily(interval: interval, endDate: endDate)
        case .weekly:
            repeatRule = .weekly(interval: interval, on: selectedWeekDays, endDate: endDate)
        case .monthly:
            repeatRule = .monthly(interval: interval, dayOfMonth: Calendar.current.component(.day, from: Date()), endDate: endDate)
        case .yearly:
            let today = Date()
            let calendar = Calendar.current
            repeatRule = .yearly(
                interval: interval,
                month: calendar.component(.month, from: today),
                day: calendar.component(.day, from: today),
                endDate: endDate
            )
        case .custom:
            repeatRule = .daily(interval: interval, endDate: endDate)
        }
    }
}

// MARK: - Frequency Extension

extension RepeatRule.Frequency {
    var displayName: String {
        switch self {
        case .daily: return "Daily"
        case .weekly: return "Weekly"
        case .monthly: return "Monthly"
        case .yearly: return "Yearly"
        case .custom: return "Custom"
        }
    }
}

// MARK: - Week Day Button

private struct WeekDayButton: View {
    let day: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(day)
                .font(RemindersTypography.caption1Bold)
                .foregroundColor(isSelected ? .white : RemindersColors.textSecondary)
                .frame(width: 36, height: 36)
                .background(isSelected ? RemindersColors.accentBlue : RemindersColors.backgroundTertiary)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Compact Repeat Display

struct RepeatDisplay: View {
    let repeatRule: RepeatRule?

    var body: some View {
        if let rule = repeatRule {
            HStack(spacing: RemindersKit.Spacing.xxs) {
                Image(systemName: "repeat")
                    .font(.system(size: 11, weight: .medium))

                Text(rule.displayDescription)
                    .font(RemindersTypography.caption1)
            }
            .foregroundColor(RemindersColors.accentGreen)
            .padding(.horizontal, RemindersKit.Spacing.sm)
            .padding(.vertical, RemindersKit.Spacing.xxs)
            .background(RemindersColors.accentGreen.opacity(0.12))
            .clipShape(Capsule())
        }
    }
}

// MARK: - Preview

#Preview("Repeat Rule Picker") {
    struct PreviewWrapper: View {
        @State private var repeatRule: RepeatRule? = nil
        @State private var isEnabled = false

        var body: some View {
            ScrollView {
                VStack(spacing: 24) {
                    // Full picker
                    Group {
                        Text("Repeat Rule Picker")
                            .font(RemindersTypography.headline)
                            .foregroundColor(RemindersColors.textPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        RepeatRulePicker(
                            repeatRule: $repeatRule,
                            isEnabled: $isEnabled
                        )
                    }

                    // Display examples
                    Group {
                        Text("Repeat Displays")
                            .font(RemindersTypography.headline)
                            .foregroundColor(RemindersColors.textPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        VStack(alignment: .leading, spacing: 12) {
                            RepeatDisplay(repeatRule: .daily())
                            RepeatDisplay(repeatRule: .weekly())
                            RepeatDisplay(repeatRule: .monthly(dayOfMonth: 15))
                            RepeatDisplay(repeatRule: .yearly(month: 6, day: 15))
                        }
                    }

                    Spacer()
                }
                .padding()
            }
            .background(RemindersColors.background)
        }
    }

    return PreviewWrapper()
}
