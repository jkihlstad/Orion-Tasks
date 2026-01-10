//
//  DateTimePicker.swift
//  TasksApp
//
//  Combined date/time picker component matching Apple Reminders style
//

import SwiftUI

// MARK: - Date Time Picker

struct DateTimePicker: View {

    // MARK: - Properties

    @Binding var date: Date?
    @Binding var time: Date?
    @Binding var hasDate: Bool
    @Binding var hasTime: Bool

    let showQuickOptions: Bool

    // MARK: - State

    @State private var selectedDate: Date = Date()
    @State private var selectedTime: Date = Date()
    @State private var isDatePickerExpanded = false
    @State private var isTimePickerExpanded = false

    // MARK: - Initialization

    init(
        date: Binding<Date?>,
        time: Binding<Date?>,
        hasDate: Binding<Bool>,
        hasTime: Binding<Bool>,
        showQuickOptions: Bool = true
    ) {
        self._date = date
        self._time = time
        self._hasDate = hasDate
        self._hasTime = hasTime
        self.showQuickOptions = showQuickOptions
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Quick date options
            if showQuickOptions && !hasDate {
                quickDateOptions
            }

            // Date toggle and picker
            dateSection

            // Time toggle and picker (only if date is set)
            if hasDate {
                Divider()
                    .background(RemindersColors.separator)

                timeSection
            }
        }
        .background(RemindersColors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: RemindersKit.Radius.lg))
        .onAppear {
            if let existingDate = date {
                selectedDate = existingDate
            }
            if let existingTime = time {
                selectedTime = existingTime
            }
        }
    }

    // MARK: - Quick Date Options

    private var quickDateOptions: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: RemindersKit.Spacing.sm) {
                QuickDateButton(title: "Today", icon: "sun.max.fill", color: RemindersColors.today) {
                    setQuickDate(.today)
                }

                QuickDateButton(title: "Tomorrow", icon: "sunrise.fill", color: RemindersColors.accentOrange) {
                    setQuickDate(.tomorrow)
                }

                QuickDateButton(title: "This Weekend", icon: "sparkles", color: RemindersColors.accentPurple) {
                    setQuickDate(.thisWeekend)
                }

                QuickDateButton(title: "Next Week", icon: "calendar", color: RemindersColors.accentCyan) {
                    setQuickDate(.nextWeek)
                }
            }
            .padding(RemindersKit.Spacing.md)
        }
    }

    // MARK: - Date Section

    private var dateSection: some View {
        VStack(spacing: 0) {
            // Date toggle row
            Button {
                withAnimation(RemindersKit.Animation.standard) {
                    if hasDate {
                        isDatePickerExpanded.toggle()
                    } else {
                        hasDate = true
                        date = selectedDate
                        isDatePickerExpanded = true
                    }
                }
            } label: {
                HStack {
                    ZStack {
                        RoundedRectangle(cornerRadius: RemindersKit.Radius.sm)
                            .fill(RemindersColors.accentRed)
                            .frame(width: 30, height: 30)

                        Image(systemName: "calendar")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                    }

                    Text("Date")
                        .font(RemindersTypography.body)
                        .foregroundColor(RemindersColors.textPrimary)

                    Spacer()

                    if hasDate {
                        Text(formattedDate)
                            .font(RemindersTypography.body)
                            .foregroundColor(dateTextColor)

                        Image(systemName: isDatePickerExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(RemindersColors.textTertiary)
                    } else {
                        Toggle("", isOn: $hasDate)
                            .labelsHidden()
                            .tint(RemindersColors.accentBlue)
                    }
                }
                .padding(RemindersKit.Spacing.md)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Date picker (expanded)
            if hasDate && isDatePickerExpanded {
                Divider()
                    .background(RemindersColors.separator)
                    .padding(.leading, 54)

                DatePicker(
                    "Select Date",
                    selection: $selectedDate,
                    displayedComponents: .date
                )
                .datePickerStyle(.graphical)
                .tint(RemindersColors.accentBlue)
                .padding(.horizontal, RemindersKit.Spacing.md)
                .onChange(of: selectedDate) { _, newValue in
                    date = newValue
                }

                // Clear date button
                Button {
                    withAnimation(RemindersKit.Animation.quick) {
                        hasDate = false
                        hasTime = false
                        date = nil
                        time = nil
                        isDatePickerExpanded = false
                        isTimePickerExpanded = false
                    }
                } label: {
                    Text("Clear Date")
                        .font(RemindersTypography.body)
                        .foregroundColor(RemindersColors.accentRed)
                }
                .padding(.bottom, RemindersKit.Spacing.md)
            }
        }
    }

    // MARK: - Time Section

    private var timeSection: some View {
        VStack(spacing: 0) {
            // Time toggle row
            Button {
                withAnimation(RemindersKit.Animation.standard) {
                    if hasTime {
                        isTimePickerExpanded.toggle()
                    } else {
                        hasTime = true
                        time = selectedTime
                        isTimePickerExpanded = true
                    }
                }
            } label: {
                HStack {
                    ZStack {
                        RoundedRectangle(cornerRadius: RemindersKit.Radius.sm)
                            .fill(RemindersColors.accentBlue)
                            .frame(width: 30, height: 30)

                        Image(systemName: "clock.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                    }

                    Text("Time")
                        .font(RemindersTypography.body)
                        .foregroundColor(RemindersColors.textPrimary)

                    Spacer()

                    if hasTime {
                        Text(formattedTime)
                            .font(RemindersTypography.body)
                            .foregroundColor(RemindersColors.accentBlue)

                        Image(systemName: isTimePickerExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(RemindersColors.textTertiary)
                    } else {
                        Toggle("", isOn: $hasTime)
                            .labelsHidden()
                            .tint(RemindersColors.accentBlue)
                            .onChange(of: hasTime) { _, newValue in
                                if newValue {
                                    time = selectedTime
                                    isTimePickerExpanded = true
                                } else {
                                    time = nil
                                    isTimePickerExpanded = false
                                }
                            }
                    }
                }
                .padding(RemindersKit.Spacing.md)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Time picker (expanded)
            if hasTime && isTimePickerExpanded {
                Divider()
                    .background(RemindersColors.separator)
                    .padding(.leading, 54)

                DatePicker(
                    "Select Time",
                    selection: $selectedTime,
                    displayedComponents: .hourAndMinute
                )
                .datePickerStyle(.wheel)
                .labelsHidden()
                .tint(RemindersColors.accentBlue)
                .padding(.horizontal, RemindersKit.Spacing.md)
                .onChange(of: selectedTime) { _, newValue in
                    time = newValue
                }

                // Clear time button
                Button {
                    withAnimation(RemindersKit.Animation.quick) {
                        hasTime = false
                        time = nil
                        isTimePickerExpanded = false
                    }
                } label: {
                    Text("Clear Time")
                        .font(RemindersTypography.body)
                        .foregroundColor(RemindersColors.accentRed)
                }
                .padding(.bottom, RemindersKit.Spacing.md)
            }
        }
    }

    // MARK: - Computed Properties

    private var formattedDate: String {
        guard let date = date else { return "" }

        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "Today"
        } else if calendar.isDateInTomorrow(date) {
            return "Tomorrow"
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        }

        let formatter = DateFormatter()
        if calendar.isDate(date, equalTo: Date(), toGranularity: .year) {
            formatter.dateFormat = "EEE, MMM d"
        } else {
            formatter.dateFormat = "EEE, MMM d, yyyy"
        }
        return formatter.string(from: date)
    }

    private var formattedTime: String {
        guard let time = time else { return "" }
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: time)
    }

    private var dateTextColor: Color {
        guard let date = date else { return RemindersColors.textSecondary }

        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return RemindersColors.today
        } else if date < calendar.startOfDay(for: Date()) {
            return RemindersColors.overdue
        }
        return RemindersColors.accentBlue
    }

    // MARK: - Quick Date Actions

    private func setQuickDate(_ option: QuickDateOption) {
        withAnimation(RemindersKit.Animation.quick) {
            hasDate = true
            selectedDate = option.date
            date = option.date
            isDatePickerExpanded = true
        }
    }
}

// MARK: - Quick Date Option

private enum QuickDateOption {
    case today
    case tomorrow
    case thisWeekend
    case nextWeek

    var date: Date {
        let calendar = Calendar.current
        switch self {
        case .today:
            return Date()
        case .tomorrow:
            return calendar.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        case .thisWeekend:
            let weekday = calendar.component(.weekday, from: Date())
            let daysUntilSaturday = (7 - weekday + 7) % 7
            return calendar.date(byAdding: .day, value: daysUntilSaturday == 0 ? 7 : daysUntilSaturday, to: Date()) ?? Date()
        case .nextWeek:
            return calendar.date(byAdding: .day, value: 7, to: Date()) ?? Date()
        }
    }
}

// MARK: - Quick Date Button

private struct QuickDateButton: View {
    let title: String
    let icon: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: RemindersKit.Spacing.xs) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))

                Text(title)
                    .font(RemindersTypography.caption1Bold)
            }
            .foregroundColor(color)
            .padding(.horizontal, RemindersKit.Spacing.md)
            .padding(.vertical, RemindersKit.Spacing.sm)
            .background(color.opacity(0.15))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Compact Date Time Display

struct DateTimeDisplay: View {
    let date: Date?
    let time: Date?
    let showIcon: Bool

    init(date: Date?, time: Date? = nil, showIcon: Bool = true) {
        self.date = date
        self.time = time
        self.showIcon = showIcon
    }

    var body: some View {
        if let date = date {
            HStack(spacing: RemindersKit.Spacing.xxs) {
                if showIcon {
                    Image(systemName: iconName)
                        .font(.system(size: 11, weight: .medium))
                }

                Text(formattedDateTime)
                    .font(RemindersTypography.caption1)
            }
            .foregroundColor(textColor)
            .padding(.horizontal, RemindersKit.Spacing.sm)
            .padding(.vertical, RemindersKit.Spacing.xxs)
            .background(textColor.opacity(0.12))
            .clipShape(Capsule())
        }
    }

    private var iconName: String {
        if time != nil {
            return "clock.fill"
        }
        return "calendar"
    }

    private var formattedDateTime: String {
        guard let date = date else { return "" }

        let calendar = Calendar.current
        var result: String

        if calendar.isDateInToday(date) {
            result = "Today"
        } else if calendar.isDateInTomorrow(date) {
            result = "Tomorrow"
        } else if calendar.isDateInYesterday(date) {
            result = "Yesterday"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d"
            result = formatter.string(from: date)
        }

        if let time = time {
            let timeFormatter = DateFormatter()
            timeFormatter.timeStyle = .short
            result += " \(timeFormatter.string(from: time))"
        }

        return result
    }

    private var textColor: Color {
        guard let date = date else { return RemindersColors.textSecondary }

        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: Date())
        let startOfDate = calendar.startOfDay(for: date)

        if startOfDate < startOfToday {
            return RemindersColors.overdue
        } else if calendar.isDateInToday(date) {
            return RemindersColors.today
        }
        return RemindersColors.scheduled
    }
}

// MARK: - Preview

#Preview("Date Time Picker") {
    struct PreviewWrapper: View {
        @State private var date: Date? = nil
        @State private var time: Date? = nil
        @State private var hasDate = false
        @State private var hasTime = false

        var body: some View {
            ScrollView {
                VStack(spacing: 24) {
                    // Full picker
                    Group {
                        Text("Full Date Time Picker")
                            .font(RemindersTypography.headline)
                            .foregroundColor(RemindersColors.textPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        DateTimePicker(
                            date: $date,
                            time: $time,
                            hasDate: $hasDate,
                            hasTime: $hasTime
                        )
                    }

                    // Date display examples
                    Group {
                        Text("Date Displays")
                            .font(RemindersTypography.headline)
                            .foregroundColor(RemindersColors.textPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        HStack(spacing: 12) {
                            DateTimeDisplay(date: Date()) // Today
                            DateTimeDisplay(date: Calendar.current.date(byAdding: .day, value: 1, to: Date())) // Tomorrow
                            DateTimeDisplay(date: Calendar.current.date(byAdding: .day, value: -1, to: Date())) // Yesterday (overdue)
                        }

                        HStack(spacing: 12) {
                            DateTimeDisplay(date: Date(), time: Date())
                            DateTimeDisplay(date: Calendar.current.date(byAdding: .day, value: 7, to: Date()))
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
