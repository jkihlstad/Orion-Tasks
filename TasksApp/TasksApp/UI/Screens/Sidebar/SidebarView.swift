//
//  SidebarView.swift
//  TasksApp
//
//  Main sidebar navigation view matching Apple Reminders style
//

import SwiftUI

// MARK: - Smart List Type

/// Represents the built-in smart lists in the sidebar
enum SmartListType: String, CaseIterable, Identifiable {
    case today
    case scheduled
    case all
    case flagged
    case completed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: return "Today"
        case .scheduled: return "Scheduled"
        case .all: return "All"
        case .flagged: return "Flagged"
        case .completed: return "Completed"
        }
    }

    var icon: String {
        switch self {
        case .today: return "calendar"
        case .scheduled: return "calendar.badge.clock"
        case .all: return "tray.fill"
        case .flagged: return "flag.fill"
        case .completed: return "checkmark.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .today: return RemindersColors.accentBlue
        case .scheduled: return RemindersColors.accentRed
        case .all: return RemindersColors.textSecondary
        case .flagged: return RemindersColors.accentOrange
        case .completed: return RemindersColors.accentGreen
        }
    }
}

// MARK: - Sidebar Selection

/// Represents the current sidebar selection
enum SidebarSelection: Hashable {
    case smartList(SmartListType)
    case userList(TaskList)

    var title: String {
        switch self {
        case .smartList(let type): return type.title
        case .userList(let list): return list.name
        }
    }
}

// MARK: - Sidebar View Model

@MainActor
final class SidebarViewModel: ObservableObject {
    // MARK: - Published Properties

    @Published var userLists: [TaskList] = TaskList.sampleLists
    @Published var searchText: String = ""
    @Published var isEditMode: Bool = false
    @Published var showingAddList: Bool = false

    // MARK: - Task Counts

    @Published var todayCount: Int = 5
    @Published var scheduledCount: Int = 12
    @Published var allCount: Int = 23
    @Published var flaggedCount: Int = 3
    @Published var completedCount: Int = 47

    // Task counts per list (listId -> count)
    @Published var listTaskCounts: [String: Int] = [
        "inbox": 8,
        "work": 5,
        "personal": 3,
        "shopping": 4,
        "health": 3
    ]

    // MARK: - Computed Properties

    var filteredLists: [TaskList] {
        if searchText.isEmpty {
            return userLists.sorted { $0.sortOrder < $1.sortOrder }
        }
        return userLists
            .filter { $0.name.localizedCaseInsensitiveContains(searchText) }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    // MARK: - Methods

    func smartListCount(for type: SmartListType) -> Int {
        switch type {
        case .today: return todayCount
        case .scheduled: return scheduledCount
        case .all: return allCount
        case .flagged: return flaggedCount
        case .completed: return completedCount
        }
    }

    func taskCount(for list: TaskList) -> Int {
        listTaskCounts[list.id] ?? 0
    }

    func deleteList(_ list: TaskList) {
        userLists.removeAll { $0.id == list.id }
    }

    func moveList(from source: IndexSet, to destination: Int) {
        var lists = filteredLists
        lists.move(fromOffsets: source, toOffset: destination)

        // Update sort orders
        for (index, var list) in lists.enumerated() {
            list.setSortOrder(index)
            if let originalIndex = userLists.firstIndex(where: { $0.id == list.id }) {
                userLists[originalIndex] = list
            }
        }
    }

    func addList(name: String, color: ListColor, icon: ListIcon) {
        let newList = TaskList(
            name: name,
            color: color,
            icon: icon,
            sortOrder: userLists.count
        )
        userLists.append(newList)
    }
}

// MARK: - Sidebar View

struct SidebarView: View {
    @StateObject private var viewModel = SidebarViewModel()
    @Binding var selection: SidebarSelection?

    var body: some View {
        List(selection: $selection) {
            // Search field
            searchField

            // Smart Lists Section
            smartListsSection

            // My Lists Section
            myListsSection
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(RemindersColors.background)
        .navigationTitle("Reminders")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                editButton
            }
        }
        .sheet(isPresented: $viewModel.showingAddList) {
            AddListSheet(viewModel: viewModel)
        }
        .environment(\.editMode, viewModel.isEditMode ? .constant(.active) : .constant(.inactive))
    }

    // MARK: - Search Field

    private var searchField: some View {
        Section {
            HStack(spacing: RemindersKit.Spacing.sm) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(RemindersColors.textTertiary)

                TextField("Search", text: $viewModel.searchText)
                    .font(RemindersTypography.body)
                    .foregroundColor(RemindersColors.textPrimary)

                if !viewModel.searchText.isEmpty {
                    Button {
                        viewModel.searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundColor(RemindersColors.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, RemindersKit.Spacing.md)
            .padding(.vertical, RemindersKit.Spacing.sm)
            .background(RemindersColors.backgroundTertiary)
            .clipShape(RoundedRectangle(cornerRadius: RemindersKit.Radius.searchBar))
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(
                top: RemindersKit.Spacing.sm,
                leading: RemindersKit.Spacing.lg,
                bottom: RemindersKit.Spacing.sm,
                trailing: RemindersKit.Spacing.lg
            ))
        }
    }

    // MARK: - Smart Lists Section

    private var smartListsSection: some View {
        Section {
            ForEach(SmartListType.allCases) { smartList in
                SmartListRow(
                    type: smartList,
                    count: viewModel.smartListCount(for: smartList)
                )
                .tag(SidebarSelection.smartList(smartList))
                .listRowBackground(
                    selection == .smartList(smartList)
                        ? RemindersColors.backgroundTertiary
                        : Color.clear
                )
            }
        } header: {
            Text("")
        }
        .listRowInsets(EdgeInsets(
            top: RemindersKit.Spacing.xs,
            leading: RemindersKit.Spacing.lg,
            bottom: RemindersKit.Spacing.xs,
            trailing: RemindersKit.Spacing.lg
        ))
    }

    // MARK: - My Lists Section

    private var myListsSection: some View {
        Section {
            ForEach(viewModel.filteredLists) { list in
                SidebarListRow(
                    list: list,
                    taskCount: viewModel.taskCount(for: list),
                    onDelete: {
                        viewModel.deleteList(list)
                    },
                    onEdit: {
                        // Handle edit action
                    }
                )
                .tag(SidebarSelection.userList(list))
                .listRowBackground(
                    selection == .userList(list)
                        ? RemindersColors.backgroundTertiary
                        : Color.clear
                )
            }
            .onDelete { indexSet in
                for index in indexSet {
                    let list = viewModel.filteredLists[index]
                    viewModel.deleteList(list)
                }
            }
            .onMove { source, destination in
                viewModel.moveList(from: source, to: destination)
            }

            // Add List Button
            addListButton
        } header: {
            HStack {
                Text("My Lists")
                    .font(RemindersTypography.footnote)
                    .foregroundColor(RemindersColors.textSecondary)
                    .textCase(.uppercase)

                Spacer()

                Text("\(viewModel.filteredLists.count)")
                    .font(RemindersTypography.footnote)
                    .foregroundColor(RemindersColors.textTertiary)
            }
            .padding(.top, RemindersKit.Spacing.md)
        }
        .listRowInsets(EdgeInsets(
            top: RemindersKit.Spacing.xs,
            leading: RemindersKit.Spacing.lg,
            bottom: RemindersKit.Spacing.xs,
            trailing: RemindersKit.Spacing.lg
        ))
    }

    // MARK: - Add List Button

    private var addListButton: some View {
        Button {
            viewModel.showingAddList = true
        } label: {
            HStack(spacing: RemindersKit.Spacing.md) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundColor(RemindersColors.accentBlue)

                Text("Add List")
                    .font(RemindersTypography.body)
                    .foregroundColor(RemindersColors.accentBlue)
            }
        }
        .listRowBackground(Color.clear)
    }

    // MARK: - Edit Button

    private var editButton: some View {
        Button {
            withAnimation(RemindersKit.Animation.standard) {
                viewModel.isEditMode.toggle()
            }
        } label: {
            Text(viewModel.isEditMode ? "Done" : "Edit")
                .font(RemindersTypography.body)
                .foregroundColor(RemindersColors.accentBlue)
        }
    }
}

// MARK: - Smart List Row

struct SmartListRow: View {
    let type: SmartListType
    let count: Int

    var body: some View {
        HStack(spacing: RemindersKit.Spacing.md) {
            // Icon
            ZStack {
                Circle()
                    .fill(type.color)
                    .frame(width: RemindersKit.Size.listIcon, height: RemindersKit.Size.listIcon)

                Image(systemName: type.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
            }

            // Title
            Text(type.title)
                .font(RemindersTypography.body)
                .foregroundColor(RemindersColors.textPrimary)

            Spacer()

            // Count
            if count > 0 {
                Text("\(count)")
                    .font(RemindersTypography.badge)
                    .foregroundColor(RemindersColors.textSecondary)
            }
        }
        .padding(.vertical, RemindersKit.Spacing.xxs)
        .contentShape(Rectangle())
    }
}

// MARK: - Add List Sheet

struct AddListSheet: View {
    @ObservedObject var viewModel: SidebarViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var listName: String = ""
    @State private var selectedColor: ListColor = .blue
    @State private var selectedIcon: ListIcon = .list

    var body: some View {
        NavigationStack {
            Form {
                // Name Section
                Section {
                    TextField("List Name", text: $listName)
                        .font(RemindersTypography.body)
                        .foregroundColor(RemindersColors.textPrimary)
                } header: {
                    Text("Name")
                        .font(RemindersTypography.footnote)
                        .foregroundColor(RemindersColors.textSecondary)
                }
                .listRowBackground(RemindersColors.backgroundSecondary)

                // Color Section
                Section {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 12) {
                        ForEach(ListColor.allCases, id: \.self) { color in
                            colorButton(color)
                        }
                    }
                    .padding(.vertical, RemindersKit.Spacing.sm)
                } header: {
                    Text("Color")
                        .font(RemindersTypography.footnote)
                        .foregroundColor(RemindersColors.textSecondary)
                }
                .listRowBackground(RemindersColors.backgroundSecondary)

                // Icon Section
                Section {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 12) {
                        ForEach(Array(ListIcon.allCases.prefix(24)), id: \.self) { icon in
                            iconButton(icon)
                        }
                    }
                    .padding(.vertical, RemindersKit.Spacing.sm)
                } header: {
                    Text("Icon")
                        .font(RemindersTypography.footnote)
                        .foregroundColor(RemindersColors.textSecondary)
                }
                .listRowBackground(RemindersColors.backgroundSecondary)
            }
            .scrollContentBackground(.hidden)
            .background(RemindersColors.background)
            .navigationTitle("New List")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(RemindersColors.accentBlue)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        viewModel.addList(
                            name: listName.isEmpty ? "New List" : listName,
                            color: selectedColor,
                            icon: selectedIcon
                        )
                        dismiss()
                    }
                    .font(RemindersTypography.bodyBold)
                    .foregroundColor(RemindersColors.accentBlue)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(RemindersColors.backgroundElevated)
    }

    private func colorButton(_ color: ListColor) -> some View {
        Button {
            selectedColor = color
        } label: {
            Circle()
                .fill(color.color)
                .frame(width: 36, height: 36)
                .overlay {
                    if selectedColor == color {
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
        }
    }

    private func iconButton(_ icon: ListIcon) -> some View {
        Button {
            selectedIcon = icon
        } label: {
            ZStack {
                Circle()
                    .fill(selectedIcon == icon ? selectedColor.color : RemindersColors.backgroundTertiary)
                    .frame(width: 36, height: 36)

                Image(systemName: icon.rawValue)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(selectedIcon == icon ? .white : RemindersColors.textSecondary)
            }
        }
    }
}

// MARK: - Preview

#Preview("Sidebar") {
    NavigationStack {
        SidebarView(selection: .constant(nil))
    }
    .preferredColorScheme(.dark)
}

#Preview("Sidebar with Selection") {
    NavigationStack {
        SidebarView(selection: .constant(.smartList(.today)))
    }
    .preferredColorScheme(.dark)
}

#Preview("Add List Sheet") {
    AddListSheet(viewModel: SidebarViewModel())
        .preferredColorScheme(.dark)
}
