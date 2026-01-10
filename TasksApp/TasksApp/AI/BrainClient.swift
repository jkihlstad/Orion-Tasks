//
//  BrainClient.swift
//  TasksApp
//
//  Brain AI platform API client for tasks intelligence
//  Provides voice parsing, task breakdown, scheduling, and TTS
//

import Foundation
import Combine

// MARK: - Brain Configuration

/// Configuration for Brain API
struct BrainConfiguration: Sendable {
    /// Brain API base URL
    let baseURL: URL

    /// Request timeout in seconds
    let timeout: TimeInterval

    /// Maximum retry attempts
    let maxRetries: Int

    /// Retry delay multiplier for exponential backoff
    let retryDelayMultiplier: TimeInterval

    static let development = BrainConfiguration(
        baseURL: URL(string: "https://brain.dev.orion-tasks.com")!,
        timeout: 30,
        maxRetries: 3,
        retryDelayMultiplier: 1.5
    )

    static let production = BrainConfiguration(
        baseURL: URL(string: "https://brain.orion-tasks.com")!,
        timeout: 30,
        maxRetries: 3,
        retryDelayMultiplier: 1.5
    )

    static var current: BrainConfiguration {
        #if DEBUG
        return .development
        #else
        return .production
        #endif
    }
}

// MARK: - Brain Error

/// Errors from Brain API operations
enum BrainError: LocalizedError, Equatable {
    case notConfigured
    case noConsent
    case authenticationRequired
    case invalidRequest(String)
    case networkError(String)
    case serverError(Int, String)
    case decodingError(String)
    case rateLimited(retryAfter: TimeInterval?)
    case serviceUnavailable
    case timeout
    case cancelled
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Brain client not configured"
        case .noConsent:
            return "AI consent required for this operation"
        case .authenticationRequired:
            return "Authentication required"
        case .invalidRequest(let message):
            return "Invalid request: \(message)"
        case .networkError(let message):
            return "Network error: \(message)"
        case .serverError(let code, let message):
            return "Server error (\(code)): \(message)"
        case .decodingError(let message):
            return "Failed to decode response: \(message)"
        case .rateLimited(let retryAfter):
            if let seconds = retryAfter {
                return "Rate limited. Retry after \(Int(seconds)) seconds"
            }
            return "Rate limited. Please try again later"
        case .serviceUnavailable:
            return "AI service temporarily unavailable"
        case .timeout:
            return "Request timed out"
        case .cancelled:
            return "Request cancelled"
        case .unknown(let message):
            return message
        }
    }

    static func == (lhs: BrainError, rhs: BrainError) -> Bool {
        lhs.errorDescription == rhs.errorDescription
    }
}

// MARK: - Request Models

/// Request to parse voice transcription into task
struct ParseVoiceTaskRequest: Codable, Sendable {
    /// The voice transcription text to parse
    let transcription: String

    /// Optional task list context for better parsing
    let listId: String?

    /// User's timezone for date parsing
    let timezone: String

    /// User's locale for language understanding
    let locale: String

    /// Consent snapshot ID for audit trail
    let consentSnapshotId: String

    /// Optional existing task IDs for context
    let contextTaskIds: [String]?

    init(
        transcription: String,
        listId: String? = nil,
        timezone: String = TimeZone.current.identifier,
        locale: String = Locale.current.identifier,
        consentSnapshotId: String,
        contextTaskIds: [String]? = nil
    ) {
        self.transcription = transcription
        self.listId = listId
        self.timezone = timezone
        self.locale = locale
        self.consentSnapshotId = consentSnapshotId
        self.contextTaskIds = contextTaskIds
    }
}

/// Request to suggest task breakdown into subtasks
struct SuggestBreakdownRequest: Codable, Sendable {
    /// The task ID to break down
    let taskId: String

    /// Consent snapshot ID for audit trail
    let consentSnapshotId: String

    /// Maximum number of subtasks to suggest
    let maxSubtasks: Int

    /// Whether to include time estimates
    let includeTimeEstimates: Bool

    /// Optional user preferences for breakdown style
    let preferences: BreakdownPreferences?

    init(
        taskId: String,
        consentSnapshotId: String,
        maxSubtasks: Int = 10,
        includeTimeEstimates: Bool = true,
        preferences: BreakdownPreferences? = nil
    ) {
        self.taskId = taskId
        self.consentSnapshotId = consentSnapshotId
        self.maxSubtasks = maxSubtasks
        self.includeTimeEstimates = includeTimeEstimates
        self.preferences = preferences
    }
}

/// Preferences for task breakdown
struct BreakdownPreferences: Codable, Sendable {
    /// Preferred granularity of subtasks
    let granularity: Granularity

    /// Whether to include dependencies between subtasks
    let includeDependencies: Bool

    /// Preferred ordering style
    let orderingStyle: OrderingStyle

    enum Granularity: String, Codable, Sendable {
        case coarse   // Fewer, larger subtasks
        case medium   // Balanced breakdown
        case fine     // Many small subtasks
    }

    enum OrderingStyle: String, Codable, Sendable {
        case sequential   // Tasks must be done in order
        case parallel     // Tasks can be done in any order
        case mixed        // Some sequential, some parallel
    }
}

/// Request to suggest scheduling for a task
struct SuggestScheduleRequest: Codable, Sendable {
    /// The task ID to schedule
    let taskId: String

    /// Consent snapshot ID for audit trail
    let consentSnapshotId: String

    /// Optional calendar event IDs for context (existing commitments)
    let calendarEventIds: [String]?

    /// User's available hours per day
    let availableHoursPerDay: Int?

    /// User's preferred working hours
    let preferredTimeRange: TimeRange?

    /// Whether weekends should be included
    let includeWeekends: Bool

    init(
        taskId: String,
        consentSnapshotId: String,
        calendarEventIds: [String]? = nil,
        availableHoursPerDay: Int? = nil,
        preferredTimeRange: TimeRange? = nil,
        includeWeekends: Bool = false
    ) {
        self.taskId = taskId
        self.consentSnapshotId = consentSnapshotId
        self.calendarEventIds = calendarEventIds
        self.availableHoursPerDay = availableHoursPerDay
        self.preferredTimeRange = preferredTimeRange
        self.includeWeekends = includeWeekends
    }
}

/// Time range for scheduling preferences
struct TimeRange: Codable, Sendable {
    /// Start hour (0-23)
    let startHour: Int

    /// End hour (0-23)
    let endHour: Int
}

/// Request for text-to-speech synthesis
struct TTSRequest: Codable, Sendable {
    /// Text to synthesize
    let text: String

    /// Consent snapshot ID for audit trail
    let consentSnapshotId: String

    /// Preferred voice style
    let voiceStyle: VoiceStyle

    /// Speech rate (0.5 - 2.0, 1.0 is normal)
    let rate: Double

    /// Output audio format
    let format: AudioFormat

    init(
        text: String,
        consentSnapshotId: String,
        voiceStyle: VoiceStyle = .natural,
        rate: Double = 1.0,
        format: AudioFormat = .mp3
    ) {
        self.text = text
        self.consentSnapshotId = consentSnapshotId
        self.voiceStyle = voiceStyle
        self.rate = rate
        self.format = format
    }

    enum VoiceStyle: String, Codable, Sendable {
        case natural
        case friendly
        case professional
        case calm
    }

    enum AudioFormat: String, Codable, Sendable {
        case mp3
        case aac
        case wav
    }
}

/// Request to upload audio for transcription
struct TranscribeAudioRequest: Codable, Sendable {
    /// Reference to uploaded audio file
    let mediaRef: String

    /// Consent snapshot ID for audit trail
    let consentSnapshotId: String

    /// Language hint for transcription
    let languageHint: String?

    /// Whether to include timestamps
    let includeTimestamps: Bool

    init(
        mediaRef: String,
        consentSnapshotId: String,
        languageHint: String? = nil,
        includeTimestamps: Bool = false
    ) {
        self.mediaRef = mediaRef
        self.consentSnapshotId = consentSnapshotId
        self.languageHint = languageHint
        self.includeTimestamps = includeTimestamps
    }
}

// MARK: - Response Models

/// Response from parsing voice transcription
struct ParseVoiceTaskResponse: Codable, Sendable {
    /// Parsed task title
    let title: String

    /// Extracted notes/description
    let notes: String?

    /// Parsed due date (ISO 8601)
    let dueDate: Date?

    /// Parsed due time (ISO 8601)
    let dueTime: Date?

    /// Detected priority (0-3)
    let priority: Int?

    /// Suggested list ID based on content
    let suggestedListId: String?

    /// Detected repeat rule
    let repeatRule: ParsedRepeatRule?

    /// Extracted tags
    let tags: [String]?

    /// Confidence score (0.0 - 1.0)
    let confidence: Double

    /// Alternative interpretations
    let alternatives: [AlternativeInterpretation]?
}

/// Alternative interpretation of voice input
struct AlternativeInterpretation: Codable, Sendable {
    let title: String
    let notes: String?
    let dueDate: Date?
    let confidence: Double
}

/// Parsed repeat rule from voice input
struct ParsedRepeatRule: Codable, Sendable {
    let frequency: String  // daily, weekly, monthly, yearly
    let interval: Int
    let weekDays: [Int]?   // 0 = Sunday, 6 = Saturday
    let dayOfMonth: Int?
    let endDate: Date?
}

/// Response from task breakdown suggestion
struct SuggestBreakdownResponse: Codable, Sendable {
    /// Suggested subtasks
    let subtasks: [SuggestedSubtask]

    /// Overall estimated time for all subtasks
    let totalEstimatedMinutes: Int?

    /// Breakdown reasoning/explanation
    let reasoning: String?

    /// Confidence score (0.0 - 1.0)
    let confidence: Double
}

/// A suggested subtask
struct SuggestedSubtask: Codable, Sendable, Identifiable {
    /// Unique identifier for this suggestion
    let id: String

    /// Subtask title
    let title: String

    /// Optional notes
    let notes: String?

    /// Estimated time in minutes
    let estimatedMinutes: Int?

    /// Order in the sequence
    let order: Int

    /// IDs of subtasks this depends on
    let dependsOn: [String]?

    /// Whether this subtask is optional
    let isOptional: Bool
}

/// Response from scheduling suggestion
struct SuggestScheduleResponse: Codable, Sendable {
    /// Primary suggested schedule
    let primarySuggestion: ScheduleSuggestion

    /// Alternative scheduling options
    let alternatives: [ScheduleSuggestion]?

    /// Reasoning for the suggestion
    let reasoning: String?

    /// Confidence score (0.0 - 1.0)
    let confidence: Double
}

/// A suggested schedule for a task
struct ScheduleSuggestion: Codable, Sendable, Identifiable {
    let id: String

    /// Suggested due date
    let suggestedDueDate: Date

    /// Suggested due time
    let suggestedDueTime: Date?

    /// Suggested reminder date/time
    let suggestedReminderDate: Date?

    /// Estimated duration in minutes
    let estimatedDurationMinutes: Int?

    /// Brief explanation for this suggestion
    let explanation: String
}

/// Response from TTS request
struct TTSResponse: Codable, Sendable {
    /// URL to the generated audio file
    let audioUrl: String

    /// Duration of the audio in seconds
    let durationSeconds: Double

    /// Audio format
    let format: String

    /// File size in bytes
    let fileSizeBytes: Int
}

/// Response from audio transcription
struct TranscribeAudioResponse: Codable, Sendable {
    /// The transcribed text
    let transcription: String

    /// Detected language
    let detectedLanguage: String?

    /// Word-level timestamps if requested
    let wordTimestamps: [WordTimestamp]?

    /// Confidence score (0.0 - 1.0)
    let confidence: Double
}

/// Word-level timestamp for transcription
struct WordTimestamp: Codable, Sendable {
    let word: String
    let startTime: Double
    let endTime: Double
}

// MARK: - Brain Client Protocol

/// Protocol for Brain AI client
protocol BrainClientProtocol: Sendable {
    /// Parse voice transcription into task fields
    func parseVoiceTask(_ request: ParseVoiceTaskRequest) async throws -> ParseVoiceTaskResponse

    /// Suggest task breakdown into subtasks
    func suggestBreakdown(_ request: SuggestBreakdownRequest) async throws -> SuggestBreakdownResponse

    /// Suggest scheduling for a task
    func suggestSchedule(_ request: SuggestScheduleRequest) async throws -> SuggestScheduleResponse

    /// Generate text-to-speech audio
    func textToSpeech(_ request: TTSRequest) async throws -> TTSResponse

    /// Transcribe audio to text
    func transcribeAudio(_ request: TranscribeAudioRequest) async throws -> TranscribeAudioResponse
}

// MARK: - Auth Token Provider Protocol

/// Protocol for providing authentication tokens
protocol AuthTokenProvider: Sendable {
    /// Get the current authentication token
    func getToken() async throws -> String?

    /// Refresh the authentication token
    func refreshToken() async throws -> String

    /// Whether the user is currently authenticated
    var isAuthenticatedSync: Bool { get }
}

// MARK: - Brain Client Implementation

/// Implementation of Brain AI client
final class BrainClient: BrainClientProtocol, @unchecked Sendable {

    // MARK: - Properties

    private let configuration: BrainConfiguration
    private let authProvider: AuthTokenProvider
    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    // MARK: - Initialization

    init(
        configuration: BrainConfiguration = .current,
        authProvider: AuthTokenProvider
    ) {
        self.configuration = configuration
        self.authProvider = authProvider

        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.timeoutIntervalForRequest = configuration.timeout
        sessionConfig.timeoutIntervalForResource = configuration.timeout * 2
        sessionConfig.waitsForConnectivity = true
        self.session = URLSession(configuration: sessionConfig)

        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601

        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601
    }

    // MARK: - Public Methods

    func parseVoiceTask(_ request: ParseVoiceTaskRequest) async throws -> ParseVoiceTaskResponse {
        try await performRequest(
            endpoint: "/brain/tasks/parseVoiceTask",
            body: request
        )
    }

    func suggestBreakdown(_ request: SuggestBreakdownRequest) async throws -> SuggestBreakdownResponse {
        try await performRequest(
            endpoint: "/brain/tasks/suggestBreakdown",
            body: request
        )
    }

    func suggestSchedule(_ request: SuggestScheduleRequest) async throws -> SuggestScheduleResponse {
        try await performRequest(
            endpoint: "/brain/tasks/suggestSchedule",
            body: request
        )
    }

    func textToSpeech(_ request: TTSRequest) async throws -> TTSResponse {
        try await performRequest(
            endpoint: "/brain/tasks/tts",
            body: request
        )
    }

    func transcribeAudio(_ request: TranscribeAudioRequest) async throws -> TranscribeAudioResponse {
        try await performRequest(
            endpoint: "/brain/tasks/transcribe",
            body: request
        )
    }

    // MARK: - Private Methods

    private func performRequest<T: Encodable, R: Decodable>(
        endpoint: String,
        body: T,
        retryCount: Int = 0
    ) async throws -> R {
        // Get authentication token
        guard let token = try await authProvider.getToken() else {
            throw BrainError.authenticationRequired
        }

        // Build request
        guard let url = URL(string: endpoint, relativeTo: configuration.baseURL) else {
            throw BrainError.invalidRequest("Invalid endpoint URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("TasksApp/iOS", forHTTPHeaderField: "X-Client-ID")

        do {
            request.httpBody = try encoder.encode(body)
        } catch {
            throw BrainError.invalidRequest("Failed to encode request body")
        }

        do {
            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw BrainError.unknown("Invalid response type")
            }

            switch httpResponse.statusCode {
            case 200..<300:
                do {
                    return try decoder.decode(R.self, from: data)
                } catch {
                    throw BrainError.decodingError(error.localizedDescription)
                }

            case 401:
                // Token expired, try to refresh and retry
                if retryCount < 1 {
                    _ = try await authProvider.refreshToken()
                    return try await performRequest(endpoint: endpoint, body: body, retryCount: retryCount + 1)
                }
                throw BrainError.authenticationRequired

            case 403:
                throw BrainError.noConsent

            case 422:
                let errorMessage = parseErrorMessage(from: data)
                throw BrainError.invalidRequest(errorMessage)

            case 429:
                let retryAfter = parseRetryAfter(from: httpResponse)

                // Retry with exponential backoff if within retry limit
                if retryCount < configuration.maxRetries {
                    let delay = retryAfter ?? (configuration.retryDelayMultiplier * Double(retryCount + 1))
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    return try await performRequest(endpoint: endpoint, body: body, retryCount: retryCount + 1)
                }
                throw BrainError.rateLimited(retryAfter: retryAfter)

            case 500..<600:
                let errorMessage = parseErrorMessage(from: data)

                // Retry server errors with backoff
                if retryCount < configuration.maxRetries {
                    let delay = configuration.retryDelayMultiplier * Double(retryCount + 1)
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    return try await performRequest(endpoint: endpoint, body: body, retryCount: retryCount + 1)
                }
                throw BrainError.serverError(httpResponse.statusCode, errorMessage)

            case 503:
                throw BrainError.serviceUnavailable

            default:
                let errorMessage = parseErrorMessage(from: data)
                throw BrainError.serverError(httpResponse.statusCode, errorMessage)
            }

        } catch let error as BrainError {
            throw error
        } catch let error as URLError {
            switch error.code {
            case .timedOut:
                throw BrainError.timeout
            case .cancelled:
                throw BrainError.cancelled
            case .notConnectedToInternet, .networkConnectionLost:
                throw BrainError.networkError("No internet connection")
            default:
                throw BrainError.networkError(error.localizedDescription)
            }
        } catch {
            throw BrainError.unknown(error.localizedDescription)
        }
    }

    private func parseErrorMessage(from data: Data) -> String {
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let message = json["message"] as? String {
                return message
            }
            if let error = json["error"] as? String {
                return error
            }
            if let errors = json["errors"] as? [[String: Any]],
               let firstError = errors.first,
               let message = firstError["message"] as? String {
                return message
            }
        }
        return String(data: data, encoding: .utf8) ?? "Unknown error"
    }

    private func parseRetryAfter(from response: HTTPURLResponse) -> TimeInterval? {
        if let retryAfterString = response.value(forHTTPHeaderField: "Retry-After"),
           let seconds = TimeInterval(retryAfterString) {
            return seconds
        }
        return nil
    }
}

// MARK: - Mock Brain Client for Testing

#if DEBUG
/// Mock implementation for testing and previews
final class MockBrainClient: BrainClientProtocol, @unchecked Sendable {

    var shouldFail = false
    var delay: TimeInterval = 0.5

    func parseVoiceTask(_ request: ParseVoiceTaskRequest) async throws -> ParseVoiceTaskResponse {
        try await simulateDelay()
        if shouldFail { throw BrainError.serviceUnavailable }

        return ParseVoiceTaskResponse(
            title: "Buy groceries tomorrow at 5pm",
            notes: "Including milk and bread",
            dueDate: Calendar.current.date(byAdding: .day, value: 1, to: Date()),
            dueTime: Calendar.current.date(bySettingHour: 17, minute: 0, second: 0, of: Date()),
            priority: 2,
            suggestedListId: nil,
            repeatRule: nil,
            tags: ["shopping", "errands"],
            confidence: 0.92,
            alternatives: nil
        )
    }

    func suggestBreakdown(_ request: SuggestBreakdownRequest) async throws -> SuggestBreakdownResponse {
        try await simulateDelay()
        if shouldFail { throw BrainError.serviceUnavailable }

        return SuggestBreakdownResponse(
            subtasks: [
                SuggestedSubtask(id: "1", title: "Make a list of items needed", notes: nil, estimatedMinutes: 5, order: 1, dependsOn: nil, isOptional: false),
                SuggestedSubtask(id: "2", title: "Check pantry for existing items", notes: nil, estimatedMinutes: 10, order: 2, dependsOn: ["1"], isOptional: true),
                SuggestedSubtask(id: "3", title: "Go to store", notes: nil, estimatedMinutes: 30, order: 3, dependsOn: ["1"], isOptional: false),
                SuggestedSubtask(id: "4", title: "Put groceries away", notes: nil, estimatedMinutes: 10, order: 4, dependsOn: ["3"], isOptional: false)
            ],
            totalEstimatedMinutes: 55,
            reasoning: "Breaking down the grocery shopping task into planning, shopping, and organizing phases.",
            confidence: 0.88
        )
    }

    func suggestSchedule(_ request: SuggestScheduleRequest) async throws -> SuggestScheduleResponse {
        try await simulateDelay()
        if shouldFail { throw BrainError.serviceUnavailable }

        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
        let suggestedTime = Calendar.current.date(bySettingHour: 14, minute: 0, second: 0, of: tomorrow)!

        return SuggestScheduleResponse(
            primarySuggestion: ScheduleSuggestion(
                id: "1",
                suggestedDueDate: tomorrow,
                suggestedDueTime: suggestedTime,
                suggestedReminderDate: Calendar.current.date(byAdding: .hour, value: -1, to: suggestedTime),
                estimatedDurationMinutes: 60,
                explanation: "Tomorrow afternoon is typically a good time for errands based on your schedule."
            ),
            alternatives: [
                ScheduleSuggestion(
                    id: "2",
                    suggestedDueDate: Calendar.current.date(byAdding: .day, value: 2, to: Date())!,
                    suggestedDueTime: Calendar.current.date(bySettingHour: 10, minute: 0, second: 0, of: Calendar.current.date(byAdding: .day, value: 2, to: Date())!)!,
                    suggestedReminderDate: nil,
                    estimatedDurationMinutes: 60,
                    explanation: "Weekend morning option for a more relaxed shopping experience."
                )
            ],
            reasoning: "Based on typical task completion patterns and available time slots.",
            confidence: 0.85
        )
    }

    func textToSpeech(_ request: TTSRequest) async throws -> TTSResponse {
        try await simulateDelay()
        if shouldFail { throw BrainError.serviceUnavailable }

        return TTSResponse(
            audioUrl: "https://brain.orion-tasks.com/tts/audio-12345.mp3",
            durationSeconds: 2.5,
            format: request.format.rawValue,
            fileSizeBytes: 45000
        )
    }

    func transcribeAudio(_ request: TranscribeAudioRequest) async throws -> TranscribeAudioResponse {
        try await simulateDelay()
        if shouldFail { throw BrainError.serviceUnavailable }

        return TranscribeAudioResponse(
            transcription: "Buy groceries tomorrow at five PM",
            detectedLanguage: "en",
            wordTimestamps: nil,
            confidence: 0.95
        )
    }

    private func simulateDelay() async throws {
        try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
    }
}
#endif
