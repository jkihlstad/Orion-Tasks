//
//  Tag.swift
//  TasksApp
//
//  Domain model for Tag entity
//

import Foundation
import SwiftUI

// MARK: - TagColor

/// Predefined colors for tags
enum TagColor: String, Codable, Hashable, CaseIterable, Sendable {
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

    /// Creates a TagColor from a hex string
    static func from(hex: String) -> TagColor? {
        allCases.first { $0.hexString.lowercased() == hex.lowercased() }
    }

    /// Background color with opacity for tag chips
    var backgroundColor: Color {
        color.opacity(0.15)
    }
}

// MARK: - Tag

/// Core Tag model for categorizing tasks
struct Tag: Identifiable, Codable, Hashable, Sendable {

    // MARK: - Properties

    /// Unique identifier for the tag
    let id: String

    /// Display name of the tag
    var name: String

    /// Color for the tag
    var color: TagColor

    // MARK: - Initialization

    /// Creates a new tag
    init(
        id: String = UUID().uuidString,
        name: String,
        color: TagColor = .blue
    ) {
        self.id = id
        self.name = name
        self.color = color
    }

    // MARK: - Computed Properties

    /// Normalized name for searching (lowercase, trimmed)
    var normalizedName: String {
        name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Hash tag representation (e.g., "#work")
    var hashTagName: String {
        "#\(name)"
    }

    // MARK: - Mutating Methods

    /// Renames the tag
    mutating func rename(to newName: String) {
        name = newName
    }

    /// Changes the tag color
    mutating func setColor(_ newColor: TagColor) {
        color = newColor
    }
}

// MARK: - Tag Hashable

extension Tag {
    static func == (lhs: Tag, rhs: Tag) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - Tag Collection Extensions

extension Array where Element == Tag {
    /// Finds a tag by name (case-insensitive)
    func find(byName name: String) -> Tag? {
        let normalizedSearchName = name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return first { $0.normalizedName == normalizedSearchName }
    }

    /// Filters tags matching search text
    func filter(matching searchText: String) -> [Tag] {
        guard !searchText.isEmpty else { return self }
        let normalizedSearch = searchText.lowercased()
        return filter { $0.normalizedName.contains(normalizedSearch) }
    }

    /// Sorts tags alphabetically by name
    func sortedByName() -> [Tag] {
        sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

// MARK: - Sample Data

extension Tag {
    /// Sample tag for previews and testing
    static let sample = Tag(
        id: "sample-tag-1",
        name: "Work",
        color: .blue
    )

    /// Sample tags for previews
    static let sampleTags: [Tag] = [
        Tag(id: "work", name: "Work", color: .blue),
        Tag(id: "personal", name: "Personal", color: .orange),
        Tag(id: "urgent", name: "Urgent", color: .red),
        Tag(id: "important", name: "Important", color: .purple),
        Tag(id: "waiting", name: "Waiting", color: .yellow),
        Tag(id: "someday", name: "Someday", color: .gray),
        Tag(id: "home", name: "Home", color: .green),
        Tag(id: "errands", name: "Errands", color: .teal)
    ]
}
