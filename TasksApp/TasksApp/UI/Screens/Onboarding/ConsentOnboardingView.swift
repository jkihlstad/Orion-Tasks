//
//  ConsentOnboardingView.swift
//  TasksApp
//
//  Multi-step consent onboarding flow for collecting user preferences
//  and required consents before using app features
//

import SwiftUI

// MARK: - Consent Onboarding View

struct ConsentOnboardingView: View {

    // MARK: - Environment

    @Environment(\.dismiss) private var dismiss

    // MARK: - State

    @StateObject private var viewModel = ConsentOnboardingViewModel()
    @State private var currentStep: OnboardingStep = .welcome

    // MARK: - Callbacks

    var onComplete: ((ConsentPreferences) -> Void)?
    var onSkip: (() -> Void)?

    // MARK: - Body

    var body: some View {
        ZStack {
            // Background
            RemindersColors.background
                .ignoresSafeArea()

            // Content
            VStack(spacing: 0) {
                // Progress indicator
                if currentStep != .welcome {
                    progressIndicator
                        .padding(.top, RemindersKit.Spacing.lg)
                }

                // Step content
                TabView(selection: $currentStep) {
                    welcomeStep
                        .tag(OnboardingStep.welcome)

                    purposeStep
                        .tag(OnboardingStep.purpose)

                    scopeSelectionStep
                        .tag(OnboardingStep.scopeSelection)

                    preferencesStep
                        .tag(OnboardingStep.preferences)

                    intelligenceLevelStep
                        .tag(OnboardingStep.intelligenceLevel)

                    reviewStep
                        .tag(OnboardingStep.review)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(RemindersKit.Animation.smooth, value: currentStep)
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Progress Indicator

    private var progressIndicator: some View {
        HStack(spacing: RemindersKit.Spacing.sm) {
            ForEach(OnboardingStep.allCases.filter { $0 != .welcome }, id: \.self) { step in
                Circle()
                    .fill(step.rawValue <= currentStep.rawValue
                          ? RemindersColors.accentBlue
                          : RemindersColors.fillTertiary)
                    .frame(width: 8, height: 8)
                    .animation(RemindersKit.Animation.quick, value: currentStep)
            }
        }
        .padding(.bottom, RemindersKit.Spacing.md)
    }

    // MARK: - Welcome Step

    private var welcomeStep: some View {
        VStack(spacing: RemindersKit.Spacing.xxl) {
            Spacer()

            // App icon
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 80))
                .foregroundStyle(
                    LinearGradient(
                        colors: [RemindersColors.accentBlue, RemindersColors.accentCyan],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            // Welcome text
            VStack(spacing: RemindersKit.Spacing.md) {
                Text("Welcome to Tasks")
                    .font(RemindersTypography.largeTitle)
                    .foregroundColor(RemindersColors.textPrimary)

                Text("Your intelligent task manager that respects your privacy and works the way you want.")
                    .font(RemindersTypography.body)
                    .foregroundColor(RemindersColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, RemindersKit.Spacing.xxl)
            }

            Spacer()

            // Get started button
            VStack(spacing: RemindersKit.Spacing.md) {
                PrimaryButton("Get Started", icon: "arrow.right") {
                    withAnimation {
                        currentStep = .purpose
                    }
                }

                Text("We'll guide you through a few quick choices to personalize your experience.")
                    .font(RemindersTypography.caption1)
                    .foregroundColor(RemindersColors.textTertiary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, RemindersKit.Spacing.xl)
            .padding(.bottom, RemindersKit.Spacing.xxxl)
        }
    }

    // MARK: - Purpose Step

    private var purposeStep: some View {
        ScrollView {
            VStack(spacing: RemindersKit.Spacing.xxl) {
                // Header
                stepHeader(
                    icon: "lightbulb.fill",
                    title: "How We Help You",
                    subtitle: "Tasks uses intelligent features to help you stay organized and focused."
                )

                // Feature cards
                VStack(spacing: RemindersKit.Spacing.md) {
                    purposeCard(
                        icon: "sparkles",
                        title: "Smart Suggestions",
                        description: "AI-powered task prioritization and scheduling recommendations."
                    )

                    purposeCard(
                        icon: "calendar",
                        title: "Calendar Integration",
                        description: "Sync with your calendar to see all your commitments in one place."
                    )

                    purposeCard(
                        icon: "mic.fill",
                        title: "Voice Input",
                        description: "Create tasks hands-free using natural speech."
                    )

                    purposeCard(
                        icon: "bell.badge.fill",
                        title: "Smart Reminders",
                        description: "Get notified at the right time based on your habits and location."
                    )
                }
                .padding(.horizontal, RemindersKit.Spacing.lg)

                // Privacy note
                HStack(spacing: RemindersKit.Spacing.sm) {
                    Image(systemName: "lock.shield.fill")
                        .foregroundColor(RemindersColors.accentGreen)

                    Text("Your data stays on your device by default. You choose what to share.")
                        .font(RemindersTypography.footnote)
                        .foregroundColor(RemindersColors.textSecondary)
                }
                .padding(.horizontal, RemindersKit.Spacing.lg)

                Spacer(minLength: RemindersKit.Spacing.huge)

                // Navigation
                navigationButtons(
                    backAction: { currentStep = .welcome },
                    nextAction: { currentStep = .scopeSelection }
                )
            }
            .padding(.top, RemindersKit.Spacing.xl)
        }
    }

    // MARK: - Scope Selection Step

    private var scopeSelectionStep: some View {
        ScrollView {
            VStack(spacing: RemindersKit.Spacing.xxl) {
                // Header
                stepHeader(
                    icon: "checkmark.shield.fill",
                    title: "Choose Your Features",
                    subtitle: "Select which features you'd like to enable. You can change these anytime."
                )

                // Scope toggles
                VStack(spacing: RemindersKit.Spacing.md) {
                    ForEach(ConsentScope.allCases, id: \.self) { scope in
                        scopeToggleCard(scope: scope)
                    }
                }
                .padding(.horizontal, RemindersKit.Spacing.lg)

                // Info text
                Text("Core task functionality is always enabled. Additional features require your explicit consent.")
                    .font(RemindersTypography.footnote)
                    .foregroundColor(RemindersColors.textTertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, RemindersKit.Spacing.xxl)

                Spacer(minLength: RemindersKit.Spacing.huge)

                // Navigation
                navigationButtons(
                    backAction: { currentStep = .purpose },
                    nextAction: { currentStep = .preferences }
                )
            }
            .padding(.top, RemindersKit.Spacing.xl)
        }
    }

    // MARK: - Preferences Step

    private var preferencesStep: some View {
        ScrollView {
            VStack(spacing: RemindersKit.Spacing.xxl) {
                // Header
                stepHeader(
                    icon: "slider.horizontal.3",
                    title: "Your Preferences",
                    subtitle: "Fine-tune how the app works for you."
                )

                // Preference options
                VStack(spacing: RemindersKit.Spacing.md) {
                    // AI Suggestions toggle
                    if viewModel.preferences.hasAIConsent {
                        preferenceToggle(
                            icon: "sparkles",
                            title: "Show AI Suggestions",
                            description: "Display smart suggestions while creating tasks.",
                            isOn: $viewModel.showAISuggestions
                        )

                        preferenceToggle(
                            icon: "brain.head.profile",
                            title: "Learn From My Habits",
                            description: "Improve suggestions based on how you use the app.",
                            isOn: $viewModel.learnFromHabits
                        )
                    }

                    // Red Beacon toggle
                    preferenceToggle(
                        icon: "exclamationmark.circle.fill",
                        iconColor: RemindersColors.accentRed,
                        title: "Red Beacon Alerts",
                        description: "Highlight overdue and high-priority tasks.",
                        isOn: $viewModel.redBeaconEnabled
                    )

                    // Notifications
                    preferenceToggle(
                        icon: "bell.badge.fill",
                        title: "Smart Notifications",
                        description: "Get reminded at optimal times based on context.",
                        isOn: $viewModel.smartNotifications
                    )
                }
                .padding(.horizontal, RemindersKit.Spacing.lg)

                Spacer(minLength: RemindersKit.Spacing.huge)

                // Navigation
                navigationButtons(
                    backAction: { currentStep = .scopeSelection },
                    nextAction: {
                        if viewModel.preferences.hasAIConsent {
                            currentStep = .intelligenceLevel
                        } else {
                            currentStep = .review
                        }
                    }
                )
            }
            .padding(.top, RemindersKit.Spacing.xl)
        }
    }

    // MARK: - Intelligence Level Step

    private var intelligenceLevelStep: some View {
        ScrollView {
            VStack(spacing: RemindersKit.Spacing.xxl) {
                // Header
                stepHeader(
                    icon: "cpu",
                    title: "AI Intelligence Level",
                    subtitle: "Choose how much AI assistance you'd like."
                )

                // Intelligence level options
                VStack(spacing: RemindersKit.Spacing.md) {
                    ForEach(IntelligenceLevel.allCases, id: \.self) { level in
                        intelligenceLevelCard(level: level)
                    }
                }
                .padding(.horizontal, RemindersKit.Spacing.lg)

                // Cloud processing note
                if viewModel.selectedIntelligenceLevel.usesCloudProcessing {
                    HStack(spacing: RemindersKit.Spacing.sm) {
                        Image(systemName: "cloud.fill")
                            .foregroundColor(RemindersColors.accentBlue)

                        Text("This level uses cloud processing for enhanced capabilities. Your data is encrypted and not used for training.")
                            .font(RemindersTypography.footnote)
                            .foregroundColor(RemindersColors.textSecondary)
                    }
                    .padding(RemindersKit.Spacing.md)
                    .background(RemindersColors.backgroundTertiary)
                    .cornerRadius(RemindersKit.Radius.md)
                    .padding(.horizontal, RemindersKit.Spacing.lg)
                }

                Spacer(minLength: RemindersKit.Spacing.huge)

                // Navigation
                navigationButtons(
                    backAction: { currentStep = .preferences },
                    nextAction: { currentStep = .review }
                )
            }
            .padding(.top, RemindersKit.Spacing.xl)
        }
    }

    // MARK: - Review Step

    private var reviewStep: some View {
        ScrollView {
            VStack(spacing: RemindersKit.Spacing.xxl) {
                // Header
                stepHeader(
                    icon: "doc.text.fill",
                    title: "Review & Accept",
                    subtitle: "Please review your choices before continuing."
                )

                // Summary
                VStack(spacing: RemindersKit.Spacing.lg) {
                    // Enabled features
                    reviewSection(title: "Enabled Features") {
                        ForEach(viewModel.preferences.grantedScopes, id: \.self) { scope in
                            HStack(spacing: RemindersKit.Spacing.sm) {
                                Image(systemName: scope.symbolName)
                                    .foregroundColor(RemindersColors.accentGreen)
                                    .frame(width: 24)

                                Text(scope.displayName)
                                    .font(RemindersTypography.body)
                                    .foregroundColor(RemindersColors.textPrimary)

                                Spacer()

                                Image(systemName: "checkmark")
                                    .foregroundColor(RemindersColors.accentGreen)
                            }
                        }
                    }

                    // Intelligence level
                    if viewModel.preferences.hasAIConsent {
                        reviewSection(title: "AI Intelligence") {
                            HStack {
                                Text(viewModel.selectedIntelligenceLevel.displayName)
                                    .font(RemindersTypography.body)
                                    .foregroundColor(RemindersColors.textPrimary)

                                Spacer()

                                Text(viewModel.selectedIntelligenceLevel.usesCloudProcessing ? "Cloud" : "On-Device")
                                    .font(RemindersTypography.footnote)
                                    .foregroundColor(RemindersColors.textSecondary)
                            }
                        }
                    }

                    // Preferences summary
                    reviewSection(title: "Preferences") {
                        VStack(spacing: RemindersKit.Spacing.xs) {
                            reviewRow("Red Beacon Alerts", enabled: viewModel.redBeaconEnabled)
                            reviewRow("Smart Notifications", enabled: viewModel.smartNotifications)
                            if viewModel.preferences.hasAIConsent {
                                reviewRow("AI Suggestions", enabled: viewModel.showAISuggestions)
                                reviewRow("Habit Learning", enabled: viewModel.learnFromHabits)
                            }
                        }
                    }
                }
                .padding(.horizontal, RemindersKit.Spacing.lg)

                // Legal text
                VStack(spacing: RemindersKit.Spacing.sm) {
                    Text("By continuing, you agree to our")
                        .font(RemindersTypography.footnote)
                        .foregroundColor(RemindersColors.textSecondary)

                    HStack(spacing: RemindersKit.Spacing.xxs) {
                        Button("Terms of Service") {
                            // Open terms
                        }
                        .font(RemindersTypography.footnoteBold)
                        .foregroundColor(RemindersColors.accentBlue)

                        Text("and")
                            .font(RemindersTypography.footnote)
                            .foregroundColor(RemindersColors.textSecondary)

                        Button("Privacy Policy") {
                            // Open privacy policy
                        }
                        .font(RemindersTypography.footnoteBold)
                        .foregroundColor(RemindersColors.accentBlue)
                    }
                }
                .multilineTextAlignment(.center)

                Spacer(minLength: RemindersKit.Spacing.huge)

                // Accept button
                VStack(spacing: RemindersKit.Spacing.md) {
                    PrimaryButton("Accept & Continue", icon: "checkmark.circle.fill") {
                        completeOnboarding()
                    }

                    Button("Go Back") {
                        withAnimation {
                            if viewModel.preferences.hasAIConsent {
                                currentStep = .intelligenceLevel
                            } else {
                                currentStep = .preferences
                            }
                        }
                    }
                    .font(RemindersTypography.button)
                    .foregroundColor(RemindersColors.textSecondary)
                }
                .padding(.horizontal, RemindersKit.Spacing.xl)
                .padding(.bottom, RemindersKit.Spacing.xxxl)
            }
            .padding(.top, RemindersKit.Spacing.xl)
        }
    }

    // MARK: - Helper Views

    private func stepHeader(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: RemindersKit.Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 44))
                .foregroundColor(RemindersColors.accentBlue)

            Text(title)
                .font(RemindersTypography.title1)
                .foregroundColor(RemindersColors.textPrimary)

            Text(subtitle)
                .font(RemindersTypography.body)
                .foregroundColor(RemindersColors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, RemindersKit.Spacing.xl)
        }
    }

    private func purposeCard(icon: String, title: String, description: String) -> some View {
        HStack(spacing: RemindersKit.Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundColor(RemindersColors.accentBlue)
                .frame(width: 44, height: 44)
                .background(RemindersColors.accentBlue.opacity(0.15))
                .cornerRadius(RemindersKit.Radius.md)

            VStack(alignment: .leading, spacing: RemindersKit.Spacing.xxs) {
                Text(title)
                    .font(RemindersTypography.headline)
                    .foregroundColor(RemindersColors.textPrimary)

                Text(description)
                    .font(RemindersTypography.subheadline)
                    .foregroundColor(RemindersColors.textSecondary)
            }

            Spacer()
        }
        .padding(RemindersKit.Spacing.md)
        .background(RemindersColors.backgroundSecondary)
        .cornerRadius(RemindersKit.Radius.lg)
    }

    private func scopeToggleCard(scope: ConsentScope) -> some View {
        let isEnabled = Binding(
            get: { viewModel.preferences.isGranted(scope) },
            set: { viewModel.setConsent(for: scope, granted: $0) }
        )

        return HStack(spacing: RemindersKit.Spacing.md) {
            Image(systemName: scope.symbolName)
                .font(.system(size: 20))
                .foregroundColor(isEnabled.wrappedValue ? RemindersColors.accentBlue : RemindersColors.textTertiary)
                .frame(width: 40, height: 40)
                .background(
                    isEnabled.wrappedValue
                    ? RemindersColors.accentBlue.opacity(0.15)
                    : RemindersColors.fillTertiary
                )
                .cornerRadius(RemindersKit.Radius.md)

            VStack(alignment: .leading, spacing: RemindersKit.Spacing.xxs) {
                Text(scope.displayName)
                    .font(RemindersTypography.headline)
                    .foregroundColor(RemindersColors.textPrimary)

                Text(scope.description)
                    .font(RemindersTypography.footnote)
                    .foregroundColor(RemindersColors.textSecondary)
                    .lineLimit(2)
            }

            Spacer()

            Toggle("", isOn: isEnabled)
                .labelsHidden()
                .tint(RemindersColors.accentBlue)
                .disabled(!scope.requiresExplicitOptIn)
        }
        .padding(RemindersKit.Spacing.md)
        .background(RemindersColors.backgroundSecondary)
        .cornerRadius(RemindersKit.Radius.lg)
        .opacity(scope.requiresExplicitOptIn ? 1 : 0.7)
    }

    private func preferenceToggle(
        icon: String,
        iconColor: Color = RemindersColors.accentBlue,
        title: String,
        description: String,
        isOn: Binding<Bool>
    ) -> some View {
        HStack(spacing: RemindersKit.Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(iconColor)
                .frame(width: 40, height: 40)
                .background(iconColor.opacity(0.15))
                .cornerRadius(RemindersKit.Radius.md)

            VStack(alignment: .leading, spacing: RemindersKit.Spacing.xxs) {
                Text(title)
                    .font(RemindersTypography.headline)
                    .foregroundColor(RemindersColors.textPrimary)

                Text(description)
                    .font(RemindersTypography.footnote)
                    .foregroundColor(RemindersColors.textSecondary)
            }

            Spacer()

            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(RemindersColors.accentBlue)
        }
        .padding(RemindersKit.Spacing.md)
        .background(RemindersColors.backgroundSecondary)
        .cornerRadius(RemindersKit.Radius.lg)
    }

    private func intelligenceLevelCard(level: IntelligenceLevel) -> some View {
        let isSelected = viewModel.selectedIntelligenceLevel == level

        return Button {
            withAnimation(RemindersKit.Animation.quick) {
                viewModel.selectedIntelligenceLevel = level
            }
        } label: {
            VStack(alignment: .leading, spacing: RemindersKit.Spacing.sm) {
                HStack {
                    Text(level.displayName)
                        .font(RemindersTypography.headline)
                        .foregroundColor(RemindersColors.textPrimary)

                    Spacer()

                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(RemindersColors.accentBlue)
                    } else {
                        Circle()
                            .stroke(RemindersColors.fillTertiary, lineWidth: 2)
                            .frame(width: 24, height: 24)
                    }
                }

                Text(level.description)
                    .font(RemindersTypography.footnote)
                    .foregroundColor(RemindersColors.textSecondary)
                    .multilineTextAlignment(.leading)

                if !level.enabledFeatures.isEmpty {
                    FlowLayout(spacing: RemindersKit.Spacing.xs) {
                        ForEach(level.enabledFeatures, id: \.self) { feature in
                            Text(feature)
                                .font(RemindersTypography.caption2)
                                .foregroundColor(RemindersColors.textSecondary)
                                .padding(.horizontal, RemindersKit.Spacing.sm)
                                .padding(.vertical, RemindersKit.Spacing.xxs)
                                .background(RemindersColors.fillTertiary)
                                .cornerRadius(RemindersKit.Radius.xs)
                        }
                    }
                }
            }
            .padding(RemindersKit.Spacing.md)
            .background(
                isSelected
                ? RemindersColors.accentBlue.opacity(0.1)
                : RemindersColors.backgroundSecondary
            )
            .cornerRadius(RemindersKit.Radius.lg)
            .overlay(
                RoundedRectangle(cornerRadius: RemindersKit.Radius.lg)
                    .stroke(
                        isSelected ? RemindersColors.accentBlue : Color.clear,
                        lineWidth: 2
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private func reviewSection(title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: RemindersKit.Spacing.sm) {
            Text(title)
                .font(RemindersTypography.footnote)
                .foregroundColor(RemindersColors.textSecondary)
                .textCase(.uppercase)

            VStack(spacing: RemindersKit.Spacing.sm) {
                content()
            }
            .padding(RemindersKit.Spacing.md)
            .background(RemindersColors.backgroundSecondary)
            .cornerRadius(RemindersKit.Radius.lg)
        }
    }

    private func reviewRow(_ title: String, enabled: Bool) -> some View {
        HStack {
            Text(title)
                .font(RemindersTypography.subheadline)
                .foregroundColor(RemindersColors.textPrimary)

            Spacer()

            Text(enabled ? "On" : "Off")
                .font(RemindersTypography.subheadline)
                .foregroundColor(enabled ? RemindersColors.accentGreen : RemindersColors.textTertiary)
        }
    }

    private func navigationButtons(backAction: @escaping () -> Void, nextAction: @escaping () -> Void) -> some View {
        HStack(spacing: RemindersKit.Spacing.md) {
            Button {
                withAnimation {
                    backAction()
                }
            } label: {
                HStack(spacing: RemindersKit.Spacing.xs) {
                    Image(systemName: "chevron.left")
                    Text("Back")
                }
                .font(RemindersTypography.button)
                .foregroundColor(RemindersColors.textSecondary)
            }

            Spacer()

            PrimaryButton("Continue", icon: "arrow.right", size: .medium) {
                withAnimation {
                    nextAction()
                }
            }
            .frame(width: 160)
        }
        .padding(.horizontal, RemindersKit.Spacing.xl)
        .padding(.bottom, RemindersKit.Spacing.xxxl)
    }

    // MARK: - Actions

    private func completeOnboarding() {
        // Finalize preferences
        viewModel.preferences.setIntelligenceLevel(viewModel.selectedIntelligenceLevel)
        viewModel.preferences.completeOnboarding()

        // Log consent event
        Logger.shared.logConsent(
            event: "Onboarding completed",
            details: "Scopes: \(viewModel.preferences.grantedScopes.map(\.displayName).joined(separator: ", ")), Intelligence: \(viewModel.selectedIntelligenceLevel.displayName)"
        )

        // Call completion handler
        onComplete?(viewModel.preferences)
    }
}

// MARK: - Onboarding Step

enum OnboardingStep: Int, CaseIterable {
    case welcome = 0
    case purpose = 1
    case scopeSelection = 2
    case preferences = 3
    case intelligenceLevel = 4
    case review = 5
}

// MARK: - View Model

@MainActor
final class ConsentOnboardingViewModel: ObservableObject {

    @Published var preferences = ConsentPreferences()
    @Published var selectedIntelligenceLevel: IntelligenceLevel = .basic

    // Preferences
    @Published var showAISuggestions: Bool = true
    @Published var learnFromHabits: Bool = false
    @Published var redBeaconEnabled: Bool = true
    @Published var smartNotifications: Bool = true

    func setConsent(for scope: ConsentScope, granted: Bool) {
        preferences.setConsent(for: scope, granted: granted)

        // If AI is disabled, reset intelligence level
        if scope == .ai && !granted {
            selectedIntelligenceLevel = .none
        }
    }
}

// MARK: - Flow Layout

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(
            in: proposal.replacingUnspecifiedDimensions().width,
            subviews: subviews,
            spacing: spacing
        )
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(
            in: bounds.width,
            subviews: subviews,
            spacing: spacing
        )

        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.positions[index].x,
                                      y: bounds.minY + result.positions[index].y),
                          proposal: .unspecified)
        }
    }

    struct FlowResult {
        var size: CGSize = .zero
        var positions: [CGPoint] = []

        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var currentX: CGFloat = 0
            var currentY: CGFloat = 0
            var lineHeight: CGFloat = 0

            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)

                if currentX + size.width > maxWidth && currentX > 0 {
                    currentX = 0
                    currentY += lineHeight + spacing
                    lineHeight = 0
                }

                positions.append(CGPoint(x: currentX, y: currentY))
                lineHeight = max(lineHeight, size.height)
                currentX += size.width + spacing
                self.size.width = max(self.size.width, currentX)
            }

            self.size.height = currentY + lineHeight
        }
    }
}

// MARK: - Preview

#Preview {
    ConsentOnboardingView { preferences in
        print("Completed with: \(preferences)")
    }
}
