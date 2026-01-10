//
//  TaskList.swift
//  TasksApp
//
//  Domain model for TaskList entity
//

import Foundation
import SwiftUI

// MARK: - ListColor

/// Predefined colors for task lists
enum ListColor: String, Codable, Hashable, CaseIterable, Sendable {
    case red
    case orange
    case yellow
    case green
    case mint
    case teal
    case cyan
    case blue
    case indigo
    case purple
    case pink
    case brown
    case gray

    /// SwiftUI Color representation
    var color: Color {
        switch self {
        case .red: return .red
        case .orange: return .orange
        case .yellow: return .yellow
        case .green: return .green
        case .mint: return .mint
        case .teal: return .teal
        case .cyan: return .cyan
        case .blue: return .blue
        case .indigo: return .indigo
        case .purple: return .purple
        case .pink: return .pink
        case .brown: return .brown
        case .gray: return .gray
        }
    }

    /// Hex color string for storage/sync
    var hexString: String {
        switch self {
        case .red: return "#FF3B30"
        case .orange: return "#FF9500"
        case .yellow: return "#FFCC00"
        case .green: return "#34C759"
        case .mint: return "#00C7BE"
        case .teal: return "#30B0C7"
        case .cyan: return "#32ADE6"
        case .blue: return "#007AFF"
        case .indigo: return "#5856D6"
        case .purple: return "#AF52DE"
        case .pink: return "#FF2D55"
        case .brown: return "#A2845E"
        case .gray: return "#8E8E93"
        }
    }

    /// Creates a ListColor from a hex string (for sync/import)
    static func from(hex: String) -> ListColor? {
        allCases.first { $0.hexString.lowercased() == hex.lowercased() }
    }
}

// MARK: - ListIcon

/// Predefined icons for task lists using SF Symbols
enum ListIcon: String, Codable, Hashable, CaseIterable, Sendable {
    case list = "list.bullet"
    case checklist = "checklist"
    case calendar = "calendar"
    case clock = "clock"
    case star = "star.fill"
    case heart = "heart.fill"
    case bookmark = "bookmark.fill"
    case folder = "folder.fill"
    case tray = "tray.fill"
    case archiveBox = "archivebox.fill"
    case doc = "doc.fill"
    case book = "book.fill"
    case graduationCap = "graduationcap.fill"
    case briefcase = "briefcase.fill"
    case house = "house.fill"
    case building = "building.2.fill"
    case cart = "cart.fill"
    case gift = "gift.fill"
    case airplane = "airplane"
    case car = "car.fill"
    case bicycle = "bicycle"
    case figure = "figure.walk"
    case dumbbell = "dumbbell.fill"
    case sportscourt = "sportscourt.fill"
    case music = "music.note"
    case gamecontroller = "gamecontroller.fill"
    case film = "film.fill"
    case camera = "camera.fill"
    case paintbrush = "paintbrush.fill"
    case wrench = "wrench.and.screwdriver.fill"
    case hammer = "hammer.fill"
    case leaf = "leaf.fill"
    case pawprint = "pawprint.fill"
    case person = "person.fill"
    case person2 = "person.2.fill"
    case person3 = "person.3.fill"
    case phone = "phone.fill"
    case envelope = "envelope.fill"
    case bubble = "bubble.left.fill"
    case bell = "bell.fill"
    case flag = "flag.fill"
    case mappin = "mappin"
    case location = "location.fill"
    case globe = "globe"
    case sun = "sun.max.fill"
    case moon = "moon.fill"
    case cloud = "cloud.fill"
    case bolt = "bolt.fill"
    case drop = "drop.fill"
    case flame = "flame.fill"
    case sparkles = "sparkles"
    case wand = "wand.and.stars"
    case lightbulb = "lightbulb.fill"
    case battery = "battery.100"
    case wifi = "wifi"
    case lock = "lock.fill"
    case key = "key.fill"
    case creditCard = "creditcard.fill"
    case banknote = "banknote.fill"
    case chart = "chart.bar.fill"
    case percent = "percent"
    case medical = "cross.fill"
    case pill = "pills.fill"
    case brain = "brain"
    case eyes = "eyes"
    case ear = "ear.fill"
    case hand = "hand.raised.fill"

    /// Display name for the icon
    var displayName: String {
        switch self {
        case .list: return "List"
        case .checklist: return "Checklist"
        case .calendar: return "Calendar"
        case .clock: return "Clock"
        case .star: return "Star"
        case .heart: return "Heart"
        case .bookmark: return "Bookmark"
        case .folder: return "Folder"
        case .tray: return "Tray"
        case .archiveBox: return "Archive"
        case .doc: return "Document"
        case .book: return "Book"
        case .graduationCap: return "Education"
        case .briefcase: return "Work"
        case .house: return "Home"
        case .building: return "Building"
        case .cart: return "Shopping"
        case .gift: return "Gift"
        case .airplane: return "Travel"
        case .car: return "Car"
        case .bicycle: return "Bicycle"
        case .figure: return "Walk"
        case .dumbbell: return "Fitness"
        case .sportscourt: return "Sports"
        case .music: return "Music"
        case .gamecontroller: return "Games"
        case .film: return "Movies"
        case .camera: return "Photos"
        case .paintbrush: return "Art"
        case .wrench: return "Tools"
        case .hammer: return "Build"
        case .leaf: return "Nature"
        case .pawprint: return "Pets"
        case .person: return "Person"
        case .person2: return "People"
        case .person3: return "Group"
        case .phone: return "Phone"
        case .envelope: return "Mail"
        case .bubble: return "Chat"
        case .bell: return "Notifications"
        case .flag: return "Flag"
        case .mappin: return "Location"
        case .location: return "GPS"
        case .globe: return "Web"
        case .sun: return "Sun"
        case .moon: return "Moon"
        case .cloud: return "Cloud"
        case .bolt: return "Energy"
        case .drop: return "Water"
        case .flame: return "Fire"
        case .sparkles: return "Magic"
        case .wand: return "Wizard"
        case .lightbulb: return "Ideas"
        case .battery: return "Battery"
        case .wifi: return "WiFi"
        case .lock: return "Security"
        case .key: return "Key"
        case .creditCard: return "Payment"
        case .banknote: return "Money"
        case .chart: return "Charts"
        case .percent: return "Discount"
        case .medical: return "Medical"
        case .pill: return "Medicine"
        case .brain: return "Brain"
        case .eyes: return "Vision"
        case .ear: return "Hearing"
        case .hand: return "Hand"
        }
    }
}

// MARK: - TaskList

/// Core TaskList model representing a collection of tasks
struct TaskList: Identifiable, Codable, Hashable, Sendable {

    // MARK: - Properties

    /// Unique identifier for the list
    let id: String

    /// Display name of the list
    var name: String

    /// Color theme for the list
    var color: ListColor

    /// Icon for the list
    var icon: ListIcon

    /// Sort order for manual ordering of lists
    var sortOrder: Int

    /// When the list was created
    let createdAt: Date

    /// When the list was last modified
    var updatedAt: Date

    // MARK: - Computed Properties

    /// Whether this is the default inbox list
    var isInbox: Bool {
        name.lowercased() == "inbox" || id == "inbox"
    }

    // MARK: - Initialization

    /// Creates a new task list
    init(
        id: String = UUID().uuidString,
        name: String,
        color: ListColor = .blue,
        icon: ListIcon = .list,
        sortOrder: Int = 0,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.color = color
        self.icon = icon
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    // MARK: - Mutating Methods

    /// Updates the list name
    mutating func rename(to newName: String) {
        name = newName
        updatedAt = Date()
    }

    /// Updates the list color
    mutating func setColor(_ newColor: ListColor) {
        color = newColor
        updatedAt = Date()
    }

    /// Updates the list icon
    mutating func setIcon(_ newIcon: ListIcon) {
        icon = newIcon
        updatedAt = Date()
    }

    /// Updates the sort order
    mutating func setSortOrder(_ order: Int) {
        sortOrder = order
        updatedAt = Date()
    }
}

// MARK: - TaskList Hashable

extension TaskList {
    static func == (lhs: TaskList, rhs: TaskList) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - Sample Data

extension TaskList {
    /// Sample list for previews and testing
    static let sample = TaskList(
        id: "sample-list-1",
        name: "Personal",
        color: .blue,
        icon: .list
    )

    /// Default inbox list
    static let inbox = TaskList(
        id: "inbox",
        name: "Inbox",
        color: .gray,
        icon: .tray
    )

    /// Sample lists for previews
    static let sampleLists: [TaskList] = [
        TaskList(id: "inbox", name: "Inbox", color: .gray, icon: .tray, sortOrder: 0),
        TaskList(id: "work", name: "Work", color: .blue, icon: .briefcase, sortOrder: 1),
        TaskList(id: "personal", name: "Personal", color: .orange, icon: .person, sortOrder: 2),
        TaskList(id: "shopping", name: "Shopping", color: .green, icon: .cart, sortOrder: 3),
        TaskList(id: "health", name: "Health", color: .red, icon: .medical, sortOrder: 4)
    ]
}
