//
//  AISuggestionsViewModel.swift
//  TasksApp
//
//  View model for AI-powered task suggestions
//  Handles task breakdown, scheduling suggestions, and applying AI recommendations
//

import Foundation
import Combine
import SwiftUI

// MARK: - Suggestion Type

/// Types of AI suggestions
enum SuggestionType: String, CaseIterable, Sendable {
    case breakdown = "breakdown"
    case schedule = "schedule"

    var displayName: String {
        switch self {
        case .breakdown: return "Break Down Task"
        case .schedule: return "Suggest Schedule"
        }
    }

    var icon: String {
        switch self {
        case .breakdown: return "list.bullet.indent"
        case .schedule: return "calendar.badge.clock"
        }
    }

    var description: String {
        switch self {
        case .breakdown: return "Get AI suggestions for breaking this task into smaller subtasks"
        case .schedule: return "Get AI suggestions for when to schedule this task"
        }
    }
}

// MARK: - Suggestion State

/// State of suggestion loading
enum SuggestionState: Equatable {
    case idle
    case loading(SuggestionType)
    case loaded(SuggestionType)
    case applying
    case applied
    case failed(String)

    var isLoading: Bool {
        if case .loading = self {
            return true
        }
        return false
    }
}

// MARK: - AI Suggestions View Model

/// View model for managing AI suggestions for tasks
@MainActor
final class AISuggestionsViewModel: ObservableObject {

    // MARK: - Published Properties

    @Published private(set) var state: SuggestionState = .idle
    @Published private(set) var breakdownSuggestion: SuggestBreakdownResponse?
    @Published private(set) var scheduleSuggestion: SuggestScheduleResponse?
    @Published private(set) var error: String?

    @Published var selectedSubtasks: Set<String> = []
    @Published var selectedSchedule: ScheduleSuggestion?

    // MARK: - Properties

    private let brainClient: BrainClientProtocol
    private let consentManager: ConsentManager
    private let taskId: String
    private var currentTask: Task<Void, Never>?

    // MARK: - Computed Properties

    /// Whether AI features are available based on consent
    var isAIAvailable: Bool {
        consentManager.hasAIConsent && consentManager.intelligenceLevel != .none
    }

    /// Whether breakdown suggestions are loaded
    var hasBreakdownSuggestion: Bool {
        breakdownSuggestion != nil
    }

    /// Whether schedule suggestions are loaded
    var hasScheduleSuggestion: Bool {
        scheduleSuggestion != nil
    }

    /// All suggested subtasks
    var suggestedSubtasks: [SuggestedSubtask] {
        breakdownSuggestion?.subtasks ?? []
    }

    /// Selected subtasks for applying
    var subtasksToApply: [SuggestedSubtask] {
        suggestedSubtasks.filter { selectedSubtasks.contains($0.id) }
    }

    /// Whether all subtasks are selected
    var allSubtasksSelected: Bool {
        !suggestedSubtasks.isEmpty && selectedSubtasks.count == suggestedSubtasks.count
    }

    /// Total estimated time for selected subtasks
    var selectedEstimatedMinutes: Int {
        subtasksToApply.compactMap { $0.estimatedMinutes }.reduce(0, +)
    }

    // MARK: - Initialization

    init(
        taskId: String,
        brainClient: BrainClientProtocol,
        consentManager: ConsentManager
    ) {
        self.taskId = taskId
        self.brainClient = brainClient
        self.consentManager = consentManager
    }

    // MARK: - Suggestion Loading

    /// Fetch task breakdown suggestions
    func fetchBreakdownSuggestions() async {
        guard isAIAvailable else {
            error = "AI consent required for suggestions"
            return
        }

        currentTask?.cancel()

        currentTask = Task { [weak self] in
            guard let self = self else { return }

            await MainActor.run {
                self.state = .loading(.breakdown)
                self.error = nil
            }

            do {
                guard let snapshot = self.consentManager.createSnapshot(reason: .preOperation) else {
                    throw BrainError.noConsent
                }

                let request = SuggestBreakdownRequest(
                    taskId: self.taskId,
                    consentSnapshotId: snapshot.id,
                    maxSubtasks: 10,
                    includeTimeEstimates: true
                )

                let response = try await self.brainClient.suggestBreakdown(request)

                await MainActor.run {
                    self.breakdownSuggestion = response
                    self.selectedSubtasks = Set(response.subtasks.filter { !$0.isOptional }.map { $0.id })
                    self.state = .loaded(.breakdown)
                }

            } catch {
                await MainActor.run {
                    self.error = error.localizedDescription
                    self.state = .failed(error.localizedDescription)
                }
            }
        }
    }

    /// Fetch scheduling suggestions
    func fetchScheduleSuggestions(calendarEventIds: [String]? = nil) async {
        guard isAIAvailable else {
            error = "AI consent required for suggestions"
            return
        }

        currentTask?.cancel()

        currentTask = Task { [weak self] in
            guard let self = self else { return }

            await MainActor.run {
                self.state = .loading(.schedule)
                self.error = nil
            }

            do {
                guard let snapshot = self.consentManager.createSnapshot(reason: .preOperation) else {
                    throw BrainError.noConsent
                }

                let request = SuggestScheduleRequest(
                    taskId: self.taskId,
                    consentSnapshotId: snapshot.id,
                    calendarEventIds: calendarEventIds
                )

                let response = try await self.brainClient.suggestSchedule(request)

                await MainActor.run {
                    self.scheduleSuggestion = response
                    self.selectedSchedule = response.primarySuggestion
                    self.state = .loaded(.schedule)
                }

            } catch {
                await MainActor.run {
                    self.error = error.localizedDescription
                    self.state = .failed(error.localizedDescription)
                }
            }
        }
    }

    // MARK: - Selection Management

    /// Toggle selection of a subtask
    func toggleSubtaskSelection(_ subtaskId: String) {
        if selectedSubtasks.contains(subtaskId) {
            selectedSubtasks.remove(subtaskId)
        } else {
            selectedSubtasks.insert(subtaskId)
        }
    }

    /// Select all subtasks
    func selectAllSubtasks() {
        selectedSubtasks = Set(suggestedSubtasks.map { $0.id })
    }

    /// Deselect all subtasks
    func deselectAllSubtasks() {
        selectedSubtasks.removeAll()
    }

    /// Select a schedule suggestion
    func selectSchedule(_ schedule: ScheduleSuggestion) {
        selectedSchedule = schedule
    }

    // MARK: - Applying Suggestions

    /// Apply selected subtask suggestions
    /// Returns the subtasks that should be created
    func applyBreakdownSuggestion() -> [SuggestedSubtask] {
        state = .applying

        let toApply = subtasksToApply
        state = .applied

        return toApply
    }

    /// Apply selected schedule suggestion
    /// Returns the schedule that should be applied
    func applyScheduleSuggestion() -> ScheduleSuggestion? {
        guard let schedule = selectedSchedule else { return nil }

        state = .applying
        state = .applied

        return schedule
    }

    // MARK: - Reset

    /// Reset all suggestions
    func reset() {
        currentTask?.cancel()
        currentTask = nil

        state = .idle
        breakdownSuggestion = nil
        scheduleSuggestion = nil
        selectedSubtasks.removeAll()
        selectedSchedule = nil
        error = nil
    }

    /// Clear breakdown suggestions
    func clearBreakdownSuggestions() {
        breakdownSuggestion = nil
        selectedSubtasks.removeAll()
        if case .loaded(.breakdown) = state {
            state = .idle
        }
    }

    /// Clear schedule suggestions
    func clearScheduleSuggestions() {
        scheduleSuggestion = nil
        selectedSchedule = nil
        if case .loaded(.schedule) = state {
            state = .idle
        }
    }
}

// MARK: - AI Suggestions Card View

/// Card displaying AI suggestion options
struct AISuggestionsCard: View {

    @ObservedObject var viewModel: AISuggestionsViewModel
    let onApplyBreakdown: ([SuggestedSubtask]) -> Void
    let onApplySchedule: (ScheduleSuggestion) -> Void

    @State private var selectedType: SuggestionType = .breakdown

    var body: some View {
        VStack(alignment: .leading, spacing: RemindersKit.Spacing.lg) {
            // Header
            HStack {
                Image(systemName: "sparkles")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(RemindersColors.accentPurple)

                Text("AI Suggestions")
                    .font(RemindersTypography.headline)
                    .foregroundColor(RemindersColors.textPrimary)

                Spacer()

                if !viewModel.isAIAvailable {
                    InlineBadge("Consent Required", color: RemindersColors.accentOrange, style: .subtle)
                }
            }

            if viewModel.isAIAvailable {
                // Suggestion type picker
                Picker("Suggestion Type", selection: $selectedType) {
                    ForEach(SuggestionType.allCases, id: \.self) { type in
                        Label(type.displayName, systemImage: type.icon)
                            .tag(type)
                    }
                }
                .pickerStyle(.segmented)

                // Content based on type and state
                switch selectedType {
                case .breakdown:
                    breakdownContent
                case .schedule:
                    scheduleContent
                }
            } else {
                // Consent prompt
                VStack(spacing: RemindersKit.Spacing.md) {
                    Text("Enable AI features in Settings to get intelligent suggestions for your tasks.")
                        .font(RemindersTypography.subheadline)
                        .foregroundColor(RemindersColors.textSecondary)
                        .multilineTextAlignment(.center)

                    PrimaryButton("Enable AI Features", icon: "sparkles", style: .secondary, size: .small) {
                        // Navigate to settings
                    }
                }
                .padding(.vertical, RemindersKit.Spacing.md)
            }

            // Error message
            if let error = viewModel.error {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(RemindersColors.accentOrange)

                    Text(error)
                        .font(RemindersTypography.footnote)
                        .foregroundColor(RemindersColors.textSecondary)
                }
            }
        }
        .padding(RemindersKit.Spacing.lg)
        .background(RemindersColors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: RemindersKit.Radius.lg))
    }

    // MARK: - Breakdown Content

    @ViewBuilder
    private var breakdownContent: some View {
        if viewModel.state.isLoading {
            loadingView(for: .breakdown)
        } else if viewModel.hasBreakdownSuggestion {
            breakdownResultsView
        } else {
            breakdownPromptView
        }
    }

    @ViewBuilder
    private var breakdownPromptView: some View {
        VStack(spacing: RemindersKit.Spacing.md) {
            Text(SuggestionType.breakdown.description)
                .font(RemindersTypography.subheadline)
                .foregroundColor(RemindersColors.textSecondary)

            PrimaryButton("Generate Subtasks", icon: "list.bullet.indent") {
                Task {
                    await viewModel.fetchBreakdownSuggestions()
                }
            }
        }
    }

    @ViewBuilder
    private var breakdownResultsView: some View {
        VStack(alignment: .leading, spacing: RemindersKit.Spacing.md) {
            // Subtasks list
            ForEach(viewModel.suggestedSubtasks) { subtask in
                SubtaskSuggestionRow(
                    subtask: subtask,
                    isSelected: viewModel.selectedSubtasks.contains(subtask.id),
                    onToggle: { viewModel.toggleSubtaskSelection(subtask.id) }
                )
            }

            // Summary
            if !viewModel.selectedSubtasks.isEmpty {
                HStack {
                    Text("\(viewModel.selectedSubtasks.count) subtasks selected")
                        .font(RemindersTypography.footnote)
                        .foregroundColor(RemindersColors.textSecondary)

                    if viewModel.selectedEstimatedMinutes > 0 {
                        Text("(\(viewModel.selectedEstimatedMinutes) min)")
                            .font(RemindersTypography.footnote)
                            .foregroundColor(RemindersColors.textTertiary)
                    }

                    Spacer()

                    Button(viewModel.allSubtasksSelected ? "Deselect All" : "Select All") {
                        if viewModel.allSubtasksSelected {
                            viewModel.deselectAllSubtasks()
                        } else {
                            viewModel.selectAllSubtasks()
                        }
                    }
                    .font(RemindersTypography.footnote)
                    .foregroundColor(RemindersColors.accentBlue)
                }
            }

            // Actions
            HStack(spacing: RemindersKit.Spacing.md) {
                PrimaryButton("Apply", style: .primary, size: .small) {
                    let subtasks = viewModel.applyBreakdownSuggestion()
                    onApplyBreakdown(subtasks)
                }
                .disabled(viewModel.selectedSubtasks.isEmpty)

                PrimaryButton("Regenerate", icon: "arrow.clockwise", style: .secondary, size: .small) {
                    viewModel.clearBreakdownSuggestions()
                    Task {
                        await viewModel.fetchBreakdownSuggestions()
                    }
                }
            }

            // Confidence indicator
            if let confidence = viewModel.breakdownSuggestion?.confidence {
                confidenceIndicator(confidence)
            }
        }
    }

    // MARK: - Schedule Content

    @ViewBuilder
    private var scheduleContent: some View {
        if viewModel.state.isLoading {
            loadingView(for: .schedule)
        } else if viewModel.hasScheduleSuggestion {
            scheduleResultsView
        } else {
            schedulePromptView
        }
    }

    @ViewBuilder
    private var schedulePromptView: some View {
        VStack(spacing: RemindersKit.Spacing.md) {
            Text(SuggestionType.schedule.description)
                .font(RemindersTypography.subheadline)
                .foregroundColor(RemindersColors.textSecondary)

            PrimaryButton("Suggest Schedule", icon: "calendar.badge.clock") {
                Task {
                    await viewModel.fetchScheduleSuggestions()
                }
            }
        }
    }

    @ViewBuilder
    private var scheduleResultsView: some View {
        VStack(alignment: .leading, spacing: RemindersKit.Spacing.md) {
            // Primary suggestion
            if let primary = viewModel.scheduleSuggestion?.primarySuggestion {
                ScheduleSuggestionRow(
                    suggestion: primary,
                    isSelected: viewModel.selectedSchedule?.id == primary.id,
                    isPrimary: true,
                    onSelect: { viewModel.selectSchedule(primary) }
                )
            }

            // Alternatives
            if let alternatives = viewModel.scheduleSuggestion?.alternatives, !alternatives.isEmpty {
                Text("Alternatives")
                    .font(RemindersTypography.footnoteBold)
                    .foregroundColor(RemindersColors.textSecondary)
                    .padding(.top, RemindersKit.Spacing.xs)

                ForEach(alternatives) { suggestion in
                    ScheduleSuggestionRow(
                        suggestion: suggestion,
                        isSelected: viewModel.selectedSchedule?.id == suggestion.id,
                        isPrimary: false,
                        onSelect: { viewModel.selectSchedule(suggestion) }
                    )
                }
            }

            // Actions
            HStack(spacing: RemindersKit.Spacing.md) {
                PrimaryButton("Apply", style: .primary, size: .small) {
                    if let schedule = viewModel.applyScheduleSuggestion() {
                        onApplySchedule(schedule)
                    }
                }
                .disabled(viewModel.selectedSchedule == nil)

                PrimaryButton("Regenerate", icon: "arrow.clockwise", style: .secondary, size: .small) {
                    viewModel.clearScheduleSuggestions()
                    Task {
                        await viewModel.fetchScheduleSuggestions()
                    }
                }
            }

            // Confidence indicator
            if let confidence = viewModel.scheduleSuggestion?.confidence {
                confidenceIndicator(confidence)
            }
        }
    }

    // MARK: - Helper Views

    @ViewBuilder
    private func loadingView(for type: SuggestionType) -> some View {
        HStack(spacing: RemindersKit.Spacing.md) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: RemindersColors.accentPurple))

            Text("Generating \(type.displayName.lowercased())...")
                .font(RemindersTypography.subheadline)
                .foregroundColor(RemindersColors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, RemindersKit.Spacing.xl)
    }

    @ViewBuilder
    private func confidenceIndicator(_ confidence: Double) -> some View {
        HStack(spacing: RemindersKit.Spacing.xs) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 12))
                .foregroundColor(RemindersColors.textTertiary)

            Text("Confidence: \(Int(confidence * 100))%")
                .font(RemindersTypography.caption2)
                .foregroundColor(RemindersColors.textTertiary)
        }
    }
}

// MARK: - Subtask Suggestion Row

struct SubtaskSuggestionRow: View {

    let subtask: SuggestedSubtask
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: RemindersKit.Spacing.md) {
                // Selection checkbox
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundColor(isSelected ? RemindersColors.accentBlue : RemindersColors.textTertiary)

                VStack(alignment: .leading, spacing: RemindersKit.Spacing.xxs) {
                    HStack {
                        Text(subtask.title)
                            .font(RemindersTypography.body)
                            .foregroundColor(RemindersColors.textPrimary)

                        if subtask.isOptional {
                            Text("Optional")
                                .font(RemindersTypography.caption2)
                                .foregroundColor(RemindersColors.textTertiary)
                                .padding(.horizontal, RemindersKit.Spacing.xs)
                                .padding(.vertical, 2)
                                .background(RemindersColors.fillTertiary)
                                .clipShape(Capsule())
                        }
                    }

                    if let minutes = subtask.estimatedMinutes {
                        Text("\(minutes) min")
                            .font(RemindersTypography.caption1)
                            .foregroundColor(RemindersColors.textSecondary)
                    }
                }

                Spacer()
            }
            .padding(.vertical, RemindersKit.Spacing.sm)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Schedule Suggestion Row

struct ScheduleSuggestionRow: View {

    let suggestion: ScheduleSuggestion
    let isSelected: Bool
    let isPrimary: Bool
    let onSelect: () -> Void

    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter
    }

    private var timeFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: RemindersKit.Spacing.md) {
                // Selection indicator
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 20))
                    .foregroundColor(isSelected ? RemindersColors.accentBlue : RemindersColors.textTertiary)

                VStack(alignment: .leading, spacing: RemindersKit.Spacing.xxs) {
                    HStack {
                        Text(dateFormatter.string(from: suggestion.suggestedDueDate))
                            .font(RemindersTypography.body)
                            .foregroundColor(RemindersColors.textPrimary)

                        if let time = suggestion.suggestedDueTime {
                            Text("at \(timeFormatter.string(from: time))")
                                .font(RemindersTypography.body)
                                .foregroundColor(RemindersColors.textSecondary)
                        }

                        if isPrimary {
                            InlineBadge("Recommended", color: RemindersColors.accentGreen, style: .subtle)
                        }
                    }

                    Text(suggestion.explanation)
                        .font(RemindersTypography.caption1)
                        .foregroundColor(RemindersColors.textSecondary)
                        .lineLimit(2)
                }

                Spacer()
            }
            .padding(.vertical, RemindersKit.Spacing.sm)
            .padding(.horizontal, RemindersKit.Spacing.sm)
            .background(isSelected ? RemindersColors.accentBlue.opacity(0.1) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: RemindersKit.Radius.sm))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#Preview {
    struct PreviewWrapper: View {
        @StateObject var viewModel: AISuggestionsViewModel

        init() {
            let brainClient = MockBrainClient()
            let consentManager = DefaultConsentManager(preferences: .fullConsent)
            _viewModel = StateObject(wrappedValue: AISuggestionsViewModel(
                taskId: "task-123",
                brainClient: brainClient,
                consentManager: consentManager
            ))
        }

        var body: some View {
            ScrollView {
                AISuggestionsCard(
                    viewModel: viewModel,
                    onApplyBreakdown: { subtasks in
                        print("Apply \(subtasks.count) subtasks")
                    },
                    onApplySchedule: { schedule in
                        print("Apply schedule: \(schedule.suggestedDueDate)")
                    }
                )
                .padding()
            }
            .background(RemindersColors.background)
        }
    }

    return PreviewWrapper()
}
