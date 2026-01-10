//
//  BeaconBadge.swift
//  TasksApp
//
//  Red beacon indicator badge matching Apple Reminders style
//

import SwiftUI

// MARK: - Beacon Badge Size

enum BeaconBadgeSize {
    case small      // 8pt - Minimal indicator
    case medium     // 12pt - Standard badge
    case large      // 16pt - Prominent indicator

    var diameter: CGFloat {
        switch self {
        case .small: return 8
        case .medium: return 12
        case .large: return 16
        }
    }

    var fontSize: CGFloat {
        switch self {
        case .small: return 0   // Too small for text
        case .medium: return 9
        case .large: return 11
        }
    }

    var borderWidth: CGFloat {
        switch self {
        case .small: return 1.5
        case .medium: return 2
        case .large: return 2.5
        }
    }
}

// MARK: - Beacon Badge

struct BeaconBadge: View {
    let count: Int?
    let size: BeaconBadgeSize
    let color: Color
    let showBorder: Bool
    let isAnimated: Bool

    @State private var isPulsing = false

    init(
        count: Int? = nil,
        size: BeaconBadgeSize = .medium,
        color: Color = RemindersColors.accentRed,
        showBorder: Bool = true,
        isAnimated: Bool = false
    ) {
        self.count = count
        self.size = size
        self.color = color
        self.showBorder = showBorder
        self.isAnimated = isAnimated
    }

    var body: some View {
        ZStack {
            // Pulse animation layer
            if isAnimated {
                Circle()
                    .fill(color.opacity(0.3))
                    .frame(width: badgeWidth * 1.5, height: badgeWidth * 1.5)
                    .scaleEffect(isPulsing ? 1.2 : 0.8)
                    .opacity(isPulsing ? 0 : 0.6)
            }

            // Main badge
            if let count = count, count > 0, size != .small {
                // Badge with count
                Text(displayCount)
                    .font(.system(size: size.fontSize, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .frame(minWidth: badgeWidth, minHeight: size.diameter)
                    .padding(.horizontal, count > 9 ? 4 : 0)
                    .background(
                        Capsule()
                            .fill(color)
                    )
                    .overlay(
                        Capsule()
                            .stroke(borderColor, lineWidth: showBorder ? size.borderWidth : 0)
                    )
            } else {
                // Simple dot indicator
                Circle()
                    .fill(color)
                    .frame(width: size.diameter, height: size.diameter)
                    .overlay(
                        Circle()
                            .stroke(borderColor, lineWidth: showBorder ? size.borderWidth : 0)
                    )
            }
        }
        .onAppear {
            if isAnimated {
                startPulseAnimation()
            }
        }
    }

    // MARK: - Computed Properties

    private var displayCount: String {
        guard let count = count else { return "" }
        if count > 99 {
            return "99+"
        }
        return "\(count)"
    }

    private var badgeWidth: CGFloat {
        guard let count = count else { return size.diameter }
        if count > 99 {
            return size.diameter * 2.2
        } else if count > 9 {
            return size.diameter * 1.5
        }
        return size.diameter
    }

    private var borderColor: Color {
        RemindersColors.background
    }

    // MARK: - Animation

    private func startPulseAnimation() {
        withAnimation(
            .easeInOut(duration: 1.5)
            .repeatForever(autoreverses: false)
        ) {
            isPulsing = true
        }
    }
}

// MARK: - Beacon Badge Modifier

struct BeaconBadgeModifier: ViewModifier {
    let count: Int?
    let size: BeaconBadgeSize
    let color: Color
    let alignment: Alignment
    let offset: CGPoint

    init(
        count: Int? = nil,
        size: BeaconBadgeSize = .medium,
        color: Color = RemindersColors.accentRed,
        alignment: Alignment = .topTrailing,
        offset: CGPoint = CGPoint(x: 4, y: -4)
    ) {
        self.count = count
        self.size = size
        self.color = color
        self.alignment = alignment
        self.offset = offset
    }

    func body(content: Content) -> some View {
        content
            .overlay(alignment: alignment) {
                if shouldShowBadge {
                    BeaconBadge(count: count, size: size, color: color)
                        .offset(x: offset.x, y: offset.y)
                }
            }
    }

    private var shouldShowBadge: Bool {
        if let count = count {
            return count > 0
        }
        return true
    }
}

extension View {
    /// Add a beacon badge overlay
    func beaconBadge(
        count: Int? = nil,
        size: BeaconBadgeSize = .medium,
        color: Color = RemindersColors.accentRed,
        alignment: Alignment = .topTrailing,
        offset: CGPoint = CGPoint(x: 4, y: -4)
    ) -> some View {
        modifier(BeaconBadgeModifier(
            count: count,
            size: size,
            color: color,
            alignment: alignment,
            offset: offset
        ))
    }

    /// Add a simple dot indicator
    func dotIndicator(
        isVisible: Bool = true,
        color: Color = RemindersColors.accentRed,
        size: BeaconBadgeSize = .small
    ) -> some View {
        overlay(alignment: .topTrailing) {
            if isVisible {
                BeaconBadge(size: size, color: color, showBorder: false)
                    .offset(x: 2, y: -2)
            }
        }
    }
}

// MARK: - Inline Badge

struct InlineBadge: View {
    let text: String
    let color: Color
    let style: InlineBadgeStyle

    enum InlineBadgeStyle {
        case filled
        case outlined
        case subtle
    }

    init(
        _ text: String,
        color: Color = RemindersColors.accentBlue,
        style: InlineBadgeStyle = .filled
    ) {
        self.text = text
        self.color = color
        self.style = style
    }

    var body: some View {
        Text(text)
            .font(RemindersTypography.caption1Bold)
            .foregroundColor(foregroundColor)
            .padding(.horizontal, RemindersKit.Spacing.sm)
            .padding(.vertical, RemindersKit.Spacing.xxs)
            .background(backgroundColor)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(strokeColor, lineWidth: style == .outlined ? 1 : 0)
            )
    }

    private var foregroundColor: Color {
        switch style {
        case .filled:
            return .white
        case .outlined:
            return color
        case .subtle:
            return color
        }
    }

    private var backgroundColor: Color {
        switch style {
        case .filled:
            return color
        case .outlined:
            return .clear
        case .subtle:
            return color.opacity(0.15)
        }
    }

    private var strokeColor: Color {
        switch style {
        case .outlined:
            return color
        default:
            return .clear
        }
    }
}

// MARK: - Count Badge (for list counts)

struct CountBadge: View {
    let count: Int
    let color: Color

    init(_ count: Int, color: Color = RemindersColors.textSecondary) {
        self.count = count
        self.color = color
    }

    var body: some View {
        Text("\(count)")
            .font(RemindersTypography.badge)
            .foregroundColor(color)
    }
}

// MARK: - Preview

#Preview {
    ScrollView {
        VStack(spacing: 32) {
            // Beacon sizes
            Group {
                Text("Beacon Badge Sizes")
                    .font(RemindersTypography.headline)
                    .foregroundColor(RemindersColors.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 24) {
                    VStack {
                        BeaconBadge(size: .small)
                        Text("Small")
                            .font(RemindersTypography.caption2)
                            .foregroundColor(RemindersColors.textSecondary)
                    }

                    VStack {
                        BeaconBadge(size: .medium)
                        Text("Medium")
                            .font(RemindersTypography.caption2)
                            .foregroundColor(RemindersColors.textSecondary)
                    }

                    VStack {
                        BeaconBadge(size: .large)
                        Text("Large")
                            .font(RemindersTypography.caption2)
                            .foregroundColor(RemindersColors.textSecondary)
                    }
                }
            }

            // With counts
            Group {
                Text("With Counts")
                    .font(RemindersTypography.headline)
                    .foregroundColor(RemindersColors.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 24) {
                    BeaconBadge(count: 1, size: .medium)
                    BeaconBadge(count: 9, size: .medium)
                    BeaconBadge(count: 42, size: .medium)
                    BeaconBadge(count: 99, size: .medium)
                    BeaconBadge(count: 150, size: .medium)
                }
            }

            // Colors
            Group {
                Text("Colors")
                    .font(RemindersTypography.headline)
                    .foregroundColor(RemindersColors.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 24) {
                    BeaconBadge(count: 5, color: RemindersColors.accentRed)
                    BeaconBadge(count: 5, color: RemindersColors.accentOrange)
                    BeaconBadge(count: 5, color: RemindersColors.accentBlue)
                    BeaconBadge(count: 5, color: RemindersColors.accentGreen)
                    BeaconBadge(count: 5, color: RemindersColors.accentPurple)
                }
            }

            // Animated beacon
            Group {
                Text("Animated")
                    .font(RemindersTypography.headline)
                    .foregroundColor(RemindersColors.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                BeaconBadge(size: .large, isAnimated: true)
            }

            // On icons
            Group {
                Text("On Icons")
                    .font(RemindersTypography.headline)
                    .foregroundColor(RemindersColors.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 32) {
                    Image(systemName: "bell.fill")
                        .font(.system(size: 28))
                        .foregroundColor(RemindersColors.textPrimary)
                        .beaconBadge(count: 3)

                    Image(systemName: "tray.fill")
                        .font(.system(size: 28))
                        .foregroundColor(RemindersColors.textPrimary)
                        .beaconBadge()

                    Image(systemName: "calendar")
                        .font(.system(size: 28))
                        .foregroundColor(RemindersColors.textPrimary)
                        .dotIndicator()
                }
            }

            // Inline badges
            Group {
                Text("Inline Badges")
                    .font(RemindersTypography.headline)
                    .foregroundColor(RemindersColors.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 12) {
                    InlineBadge("New", style: .filled)
                    InlineBadge("Beta", color: RemindersColors.accentOrange, style: .outlined)
                    InlineBadge("Soon", color: RemindersColors.accentPurple, style: .subtle)
                }
            }

            // Count badges
            Group {
                Text("Count Badges (for lists)")
                    .font(RemindersTypography.headline)
                    .foregroundColor(RemindersColors.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                VStack(spacing: 12) {
                    HStack {
                        Image(systemName: "list.bullet")
                            .foregroundColor(RemindersColors.accentBlue)
                        Text("My List")
                            .font(RemindersTypography.body)
                            .foregroundColor(RemindersColors.textPrimary)
                        Spacer()
                        CountBadge(12)
                    }
                    .padding()
                    .background(RemindersColors.backgroundSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: RemindersKit.Radius.md))

                    HStack {
                        Image(systemName: "calendar")
                            .foregroundColor(RemindersColors.accentRed)
                        Text("Scheduled")
                            .font(RemindersTypography.body)
                            .foregroundColor(RemindersColors.textPrimary)
                        Spacer()
                        CountBadge(3, color: RemindersColors.accentRed)
                    }
                    .padding()
                    .background(RemindersColors.backgroundSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: RemindersKit.Radius.md))
                }
            }
        }
        .padding()
    }
    .background(RemindersColors.background)
}
