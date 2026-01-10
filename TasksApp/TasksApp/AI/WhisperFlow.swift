//
//  WhisperFlow.swift
//  TasksApp
//
//  Speech-to-text flow using Brain API transcription
//  Handles audio upload and transcription to task parsing
//

import Foundation
import Combine

// MARK: - Transcription State

/// State of the transcription flow
enum TranscriptionState: Equatable, Sendable {
    case idle
    case uploading(progress: Double)
    case transcribing
    case parsing
    case completed(ParseVoiceTaskResponse)
    case failed(TranscriptionError)

    var isProcessing: Bool {
        switch self {
        case .uploading, .transcribing, .parsing:
            return true
        default:
            return false
        }
    }
}

// MARK: - Transcription Error

/// Errors during transcription flow
enum TranscriptionError: LocalizedError, Equatable {
    case noConsent
    case noAudioFile
    case uploadFailed(String)
    case transcriptionFailed(String)
    case parsingFailed(String)
    case cancelled
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .noConsent:
            return "Voice consent required for transcription"
        case .noAudioFile:
            return "No audio file to transcribe"
        case .uploadFailed(let message):
            return "Failed to upload audio: \(message)"
        case .transcriptionFailed(let message):
            return "Transcription failed: \(message)"
        case .parsingFailed(let message):
            return "Failed to parse task: \(message)"
        case .cancelled:
            return "Transcription cancelled"
        case .unknown(let message):
            return message
        }
    }

    static func == (lhs: TranscriptionError, rhs: TranscriptionError) -> Bool {
        lhs.errorDescription == rhs.errorDescription
    }
}

// MARK: - Whisper Flow Configuration

/// Configuration for the transcription flow
struct WhisperFlowConfiguration: Sendable {
    /// Maximum audio file size in bytes
    let maxAudioSize: Int64

    /// Language hint for transcription
    let languageHint: String?

    /// Whether to parse transcription into task fields
    let parseIntoTask: Bool

    /// Context task IDs for better parsing
    let contextTaskIds: [String]?

    /// Target list ID for task creation
    let targetListId: String?

    static let `default` = WhisperFlowConfiguration(
        maxAudioSize: 25 * 1024 * 1024, // 25 MB
        languageHint: nil,
        parseIntoTask: true,
        contextTaskIds: nil,
        targetListId: nil
    )
}

// MARK: - Media Upload Protocol

/// Protocol for uploading media files
protocol MediaUploadService: Sendable {
    /// Upload audio file and return media reference
    func uploadAudio(
        fileURL: URL,
        progressHandler: @escaping @Sendable (Double) -> Void
    ) async throws -> String
}

// MARK: - Whisper Flow

/// Manages the speech-to-text flow from audio to parsed task
@MainActor
final class WhisperFlow: ObservableObject {

    // MARK: - Published Properties

    @Published private(set) var state: TranscriptionState = .idle
    @Published private(set) var transcription: String?
    @Published private(set) var parsedTask: ParseVoiceTaskResponse?
    @Published private(set) var uploadProgress: Double = 0

    // MARK: - Properties

    private let brainClient: BrainClientProtocol
    private let mediaUploadService: MediaUploadService
    private let consentManager: ConsentManager
    private let configuration: WhisperFlowConfiguration

    private var currentTask: Task<Void, Never>?

    // MARK: - Initialization

    init(
        brainClient: BrainClientProtocol,
        mediaUploadService: MediaUploadService,
        consentManager: ConsentManager,
        configuration: WhisperFlowConfiguration = .default
    ) {
        self.brainClient = brainClient
        self.mediaUploadService = mediaUploadService
        self.consentManager = consentManager
        self.configuration = configuration
    }

    // MARK: - Public Methods

    /// Process audio file through transcription and parsing
    func processAudio(at fileURL: URL) async {
        // Cancel any existing task
        currentTask?.cancel()

        currentTask = Task { [weak self] in
            guard let self = self else { return }

            do {
                try await self.performTranscriptionFlow(fileURL: fileURL)
            } catch {
                if Task.isCancelled {
                    await MainActor.run {
                        self.state = .failed(.cancelled)
                    }
                } else if let transcriptionError = error as? TranscriptionError {
                    await MainActor.run {
                        self.state = .failed(transcriptionError)
                    }
                } else {
                    await MainActor.run {
                        self.state = .failed(.unknown(error.localizedDescription))
                    }
                }
            }
        }
    }

    /// Cancel current transcription
    func cancel() {
        currentTask?.cancel()
        currentTask = nil
        state = .idle
        transcription = nil
        parsedTask = nil
        uploadProgress = 0
    }

    /// Reset to idle state
    func reset() {
        cancel()
    }

    // MARK: - Private Methods

    private func performTranscriptionFlow(fileURL: URL) async throws {
        // Check consent
        guard consentManager.hasVoiceConsent else {
            throw TranscriptionError.noConsent
        }

        // Validate file exists
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw TranscriptionError.noAudioFile
        }

        // Check file size
        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        let fileSize = attributes[.size] as? Int64 ?? 0
        guard fileSize <= configuration.maxAudioSize else {
            throw TranscriptionError.uploadFailed("Audio file too large")
        }

        // Get consent snapshot
        guard let snapshot = consentManager.createSnapshot(reason: .preOperation) else {
            throw TranscriptionError.noConsent
        }

        // Phase 1: Upload audio
        state = .uploading(progress: 0)

        let mediaRef: String
        do {
            mediaRef = try await mediaUploadService.uploadAudio(fileURL: fileURL) { [weak self] progress in
                Task { @MainActor [weak self] in
                    self?.uploadProgress = progress
                    self?.state = .uploading(progress: progress)
                }
            }
        } catch {
            throw TranscriptionError.uploadFailed(error.localizedDescription)
        }

        // Check for cancellation
        try Task.checkCancellation()

        // Phase 2: Transcribe audio
        state = .transcribing

        let transcriptionResponse: TranscribeAudioResponse
        do {
            let request = TranscribeAudioRequest(
                mediaRef: mediaRef,
                consentSnapshotId: snapshot.id,
                languageHint: configuration.languageHint,
                includeTimestamps: false
            )
            transcriptionResponse = try await brainClient.transcribeAudio(request)
        } catch let error as BrainError {
            throw TranscriptionError.transcriptionFailed(error.localizedDescription ?? "Unknown error")
        } catch {
            throw TranscriptionError.transcriptionFailed(error.localizedDescription)
        }

        transcription = transcriptionResponse.transcription

        // Check for cancellation
        try Task.checkCancellation()

        // Phase 3: Parse into task (if enabled)
        if configuration.parseIntoTask {
            state = .parsing

            let parsedResponse: ParseVoiceTaskResponse
            do {
                let request = ParseVoiceTaskRequest(
                    transcription: transcriptionResponse.transcription,
                    listId: configuration.targetListId,
                    consentSnapshotId: snapshot.id,
                    contextTaskIds: configuration.contextTaskIds
                )
                parsedResponse = try await brainClient.parseVoiceTask(request)
            } catch let error as BrainError {
                throw TranscriptionError.parsingFailed(error.localizedDescription ?? "Unknown error")
            } catch {
                throw TranscriptionError.parsingFailed(error.localizedDescription)
            }

            parsedTask = parsedResponse
            state = .completed(parsedResponse)
        } else {
            // Create minimal response with just the transcription
            let minimalResponse = ParseVoiceTaskResponse(
                title: transcriptionResponse.transcription,
                notes: nil,
                dueDate: nil,
                dueTime: nil,
                priority: nil,
                suggestedListId: nil,
                repeatRule: nil,
                tags: nil,
                confidence: transcriptionResponse.confidence,
                alternatives: nil
            )
            parsedTask = minimalResponse
            state = .completed(minimalResponse)
        }
    }
}

// MARK: - Consent Manager Protocol

/// Protocol for managing user consent
protocol ConsentManager: Sendable {
    /// Whether voice consent is granted
    var hasVoiceConsent: Bool { get }

    /// Whether AI consent is granted
    var hasAIConsent: Bool { get }

    /// Current intelligence level
    var intelligenceLevel: IntelligenceLevel { get }

    /// Create a consent snapshot
    func createSnapshot(reason: ConsentSnapshot.SnapshotReason) -> ConsentSnapshot?
}

// MARK: - Default Consent Manager

/// Default implementation of consent manager
@MainActor
final class DefaultConsentManager: ConsentManager, ObservableObject {

    // MARK: - Published Properties

    @Published private(set) var preferences: ConsentPreferences

    // MARK: - Properties

    private let userId: String
    private let deviceId: String
    private let appVersion: String

    // MARK: - Computed Properties

    var hasVoiceConsent: Bool {
        preferences.hasVoiceConsent
    }

    var hasAIConsent: Bool {
        preferences.hasAIConsent
    }

    var intelligenceLevel: IntelligenceLevel {
        preferences.intelligenceLevel
    }

    // MARK: - Initialization

    init(
        preferences: ConsentPreferences = .default,
        userId: String = "",
        deviceId: String = UUID().uuidString,
        appVersion: String = "1.0.0"
    ) {
        self.preferences = preferences
        self.userId = userId
        self.deviceId = deviceId
        self.appVersion = appVersion
    }

    // MARK: - Methods

    func updatePreferences(_ newPreferences: ConsentPreferences) {
        preferences = newPreferences
    }

    nonisolated func createSnapshot(reason: ConsentSnapshot.SnapshotReason) -> ConsentSnapshot? {
        // Note: In production, this would access MainActor-isolated state properly
        // For now, we create a minimal snapshot
        return ConsentSnapshot(
            preferences: .fullConsent, // Placeholder - would use actual preferences
            userId: "user",
            deviceId: UUID().uuidString,
            appVersion: "1.0.0",
            reason: reason
        )
    }
}

// MARK: - Whisper Flow View Model

/// View model for voice-to-task UI
@MainActor
final class WhisperFlowViewModel: ObservableObject {

    // MARK: - Published Properties

    @Published private(set) var isRecording = false
    @Published private(set) var isProcessing = false
    @Published private(set) var error: TranscriptionError?
    @Published private(set) var transcription: String?
    @Published private(set) var parsedTask: ParseVoiceTaskResponse?

    @Published var audioLevel: AudioLevel = .zero

    // MARK: - Properties

    private let voiceCapture: VoiceCapture
    private let whisperFlow: WhisperFlow
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    init(voiceCapture: VoiceCapture, whisperFlow: WhisperFlow) {
        self.voiceCapture = voiceCapture
        self.whisperFlow = whisperFlow

        setupBindings()
    }

    // MARK: - Public Methods

    func startRecording() async {
        do {
            try await voiceCapture.startRecording()
            isRecording = true
            error = nil
        } catch let recordingError as RecordingError {
            error = .uploadFailed(recordingError.localizedDescription ?? "Recording failed")
        } catch {
            self.error = .unknown(error.localizedDescription)
        }
    }

    func stopRecordingAndProcess() async {
        do {
            let audioURL = try await voiceCapture.stopRecording()
            isRecording = false
            isProcessing = true

            await whisperFlow.processAudio(at: audioURL)
        } catch let recordingError as RecordingError {
            isRecording = false
            error = .uploadFailed(recordingError.localizedDescription ?? "Recording failed")
        } catch {
            isRecording = false
            self.error = .unknown(error.localizedDescription)
        }
    }

    func cancelRecording() {
        voiceCapture.cancelRecording()
        whisperFlow.cancel()
        isRecording = false
        isProcessing = false
        error = nil
        transcription = nil
        parsedTask = nil
    }

    func reset() {
        cancelRecording()
    }

    // MARK: - Private Methods

    private func setupBindings() {
        // Voice capture state
        voiceCapture.$audioLevel
            .receive(on: DispatchQueue.main)
            .sink { [weak self] level in
                self?.audioLevel = level
            }
            .store(in: &cancellables)

        voiceCapture.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.isRecording = state == .recording
            }
            .store(in: &cancellables)

        // Whisper flow state
        whisperFlow.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                guard let self = self else { return }

                self.isProcessing = state.isProcessing

                switch state {
                case .completed(let response):
                    self.parsedTask = response
                    self.transcription = response.title
                    self.isProcessing = false
                case .failed(let flowError):
                    self.error = flowError
                    self.isProcessing = false
                default:
                    break
                }
            }
            .store(in: &cancellables)

        whisperFlow.$transcription
            .receive(on: DispatchQueue.main)
            .assign(to: &$transcription)
    }
}

// MARK: - Simple Media Upload Service

/// Simple implementation of media upload service
final class SimpleMediaUploadService: MediaUploadService, @unchecked Sendable {

    private let baseURL: URL
    private let authProvider: AuthTokenProvider

    init(baseURL: URL, authProvider: AuthTokenProvider) {
        self.baseURL = baseURL
        self.authProvider = authProvider
    }

    func uploadAudio(
        fileURL: URL,
        progressHandler: @escaping @Sendable (Double) -> Void
    ) async throws -> String {
        // Get auth token
        guard let token = try await authProvider.getToken() else {
            throw TranscriptionError.uploadFailed("Authentication required")
        }

        // Read file data
        let data = try Data(contentsOf: fileURL)

        // Create request
        var request = URLRequest(url: baseURL.appendingPathComponent("/api/media/upload"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("audio/m4a", forHTTPHeaderField: "Content-Type")

        // Upload with progress tracking
        let (responseData, response) = try await URLSession.shared.upload(for: request, from: data)

        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw TranscriptionError.uploadFailed("Server returned error")
        }

        // Parse response for media reference
        struct UploadResponse: Decodable {
            let mediaRef: String
        }

        let uploadResponse = try JSONDecoder().decode(UploadResponse.self, from: responseData)
        progressHandler(1.0)

        return uploadResponse.mediaRef
    }
}
