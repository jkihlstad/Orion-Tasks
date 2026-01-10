//
//  TTSFlow.swift
//  TasksApp
//
//  Text-to-speech flow using Brain API
//  Provides audio playback of task information
//

import Foundation
import AVFoundation
import Combine

// MARK: - TTS State

/// State of text-to-speech playback
enum TTSState: Equatable, Sendable {
    case idle
    case loading
    case downloading(progress: Double)
    case playing(progress: Double)
    case paused(progress: Double)
    case finished
    case failed(TTSError)

    var isActive: Bool {
        switch self {
        case .loading, .downloading, .playing:
            return true
        default:
            return false
        }
    }

    var isPlaying: Bool {
        if case .playing = self {
            return true
        }
        return false
    }
}

// MARK: - TTS Error

/// Errors during TTS operations
enum TTSError: LocalizedError, Equatable {
    case noConsent
    case emptyText
    case generationFailed(String)
    case downloadFailed(String)
    case playbackFailed(String)
    case audioSessionFailed(String)
    case cancelled
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .noConsent:
            return "AI consent required for text-to-speech"
        case .emptyText:
            return "No text to speak"
        case .generationFailed(let message):
            return "Failed to generate speech: \(message)"
        case .downloadFailed(let message):
            return "Failed to download audio: \(message)"
        case .playbackFailed(let message):
            return "Playback error: \(message)"
        case .audioSessionFailed(let message):
            return "Audio session error: \(message)"
        case .cancelled:
            return "Speech cancelled"
        case .unknown(let message):
            return message
        }
    }

    static func == (lhs: TTSError, rhs: TTSError) -> Bool {
        lhs.errorDescription == rhs.errorDescription
    }
}

// MARK: - TTS Configuration

/// Configuration for TTS flow
struct TTSConfiguration: Sendable {
    /// Preferred voice style
    let voiceStyle: TTSRequest.VoiceStyle

    /// Speech rate (0.5 - 2.0)
    let rate: Double

    /// Audio format
    let format: TTSRequest.AudioFormat

    /// Whether to cache generated audio
    let cacheEnabled: Bool

    /// Maximum cache size in bytes
    let maxCacheSize: Int64

    static let `default` = TTSConfiguration(
        voiceStyle: .natural,
        rate: 1.0,
        format: .mp3,
        cacheEnabled: true,
        maxCacheSize: 50 * 1024 * 1024 // 50 MB
    )

    static let faster = TTSConfiguration(
        voiceStyle: .natural,
        rate: 1.25,
        format: .mp3,
        cacheEnabled: true,
        maxCacheSize: 50 * 1024 * 1024
    )

    static let slower = TTSConfiguration(
        voiceStyle: .calm,
        rate: 0.85,
        format: .mp3,
        cacheEnabled: true,
        maxCacheSize: 50 * 1024 * 1024
    )
}

// MARK: - TTS Flow Delegate

/// Delegate for TTS flow events
protocol TTSFlowDelegate: AnyObject {
    func ttsFlow(_ flow: TTSFlow, didChangeState state: TTSState)
    func ttsFlow(_ flow: TTSFlow, didUpdatePlaybackProgress progress: Double)
    func ttsFlowDidFinishPlaying(_ flow: TTSFlow)
    func ttsFlow(_ flow: TTSFlow, didFailWithError error: TTSError)
}

// MARK: - TTS Flow

/// Manages text-to-speech generation and playback
@MainActor
final class TTSFlow: NSObject, ObservableObject {

    // MARK: - Published Properties

    @Published private(set) var state: TTSState = .idle
    @Published private(set) var currentText: String?
    @Published private(set) var playbackProgress: Double = 0
    @Published private(set) var duration: TimeInterval = 0

    // MARK: - Properties

    weak var delegate: TTSFlowDelegate?

    private let brainClient: BrainClientProtocol
    private let consentManager: ConsentManager
    private let configuration: TTSConfiguration

    private var audioPlayer: AVAudioPlayer?
    private var audioSession: AVAudioSession { AVAudioSession.sharedInstance() }
    private var progressTimer: Timer?
    private var cachedAudioURLs: [String: URL] = [:]
    private var currentTask: Task<Void, Never>?

    // MARK: - Initialization

    init(
        brainClient: BrainClientProtocol,
        consentManager: ConsentManager,
        configuration: TTSConfiguration = .default
    ) {
        self.brainClient = brainClient
        self.consentManager = consentManager
        self.configuration = configuration
        super.init()
    }

    deinit {
        stopProgressTimer()
        audioPlayer?.stop()
    }

    // MARK: - Public Methods

    /// Speak the given text
    func speak(_ text: String) async {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            setState(.failed(.emptyText))
            return
        }

        // Cancel any current operation
        stop()

        currentTask = Task { [weak self] in
            guard let self = self else { return }

            do {
                try await self.performTTSFlow(text: text)
            } catch {
                await MainActor.run {
                    if Task.isCancelled {
                        self.setState(.failed(.cancelled))
                    } else if let ttsError = error as? TTSError {
                        self.setState(.failed(ttsError))
                    } else {
                        self.setState(.failed(.unknown(error.localizedDescription)))
                    }
                }
            }
        }
    }

    /// Speak task information
    func speakTask(_ task: Task) async {
        var text = task.title

        if let notes = task.notes, !notes.isEmpty {
            text += ". \(notes)"
        }

        if task.isDueToday {
            text += ". Due today"
        } else if let dueDate = task.dueDate {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            text += ". Due \(formatter.string(from: dueDate))"
        }

        await speak(text)
    }

    /// Pause playback
    func pause() {
        guard case .playing(let progress) = state else { return }

        audioPlayer?.pause()
        stopProgressTimer()
        setState(.paused(progress: progress))
    }

    /// Resume playback
    func resume() {
        guard case .paused = state else { return }

        if audioPlayer?.play() == true {
            startProgressTimer()
            setState(.playing(progress: playbackProgress))
        }
    }

    /// Toggle play/pause
    func togglePlayback() {
        switch state {
        case .playing:
            pause()
        case .paused:
            resume()
        default:
            break
        }
    }

    /// Stop playback
    func stop() {
        currentTask?.cancel()
        currentTask = nil

        stopProgressTimer()
        audioPlayer?.stop()
        audioPlayer = nil

        currentText = nil
        playbackProgress = 0
        duration = 0

        setState(.idle)
    }

    /// Clear cached audio files
    func clearCache() {
        for (_, url) in cachedAudioURLs {
            try? FileManager.default.removeItem(at: url)
        }
        cachedAudioURLs.removeAll()
    }

    // MARK: - Private Methods

    private func performTTSFlow(text: String) async throws {
        // Check consent
        guard consentManager.hasAIConsent else {
            throw TTSError.noConsent
        }

        currentText = text
        setState(.loading)

        // Check cache
        let cacheKey = generateCacheKey(for: text)
        if let cachedURL = cachedAudioURLs[cacheKey],
           FileManager.default.fileExists(atPath: cachedURL.path) {
            try await playAudio(from: cachedURL)
            return
        }

        // Get consent snapshot
        guard let snapshot = consentManager.createSnapshot(reason: .preOperation) else {
            throw TTSError.noConsent
        }

        // Generate TTS
        let request = TTSRequest(
            text: text,
            consentSnapshotId: snapshot.id,
            voiceStyle: configuration.voiceStyle,
            rate: configuration.rate,
            format: configuration.format
        )

        let response: TTSResponse
        do {
            response = try await brainClient.textToSpeech(request)
        } catch let error as BrainError {
            throw TTSError.generationFailed(error.localizedDescription ?? "Unknown error")
        } catch {
            throw TTSError.generationFailed(error.localizedDescription)
        }

        // Check cancellation
        try Task.checkCancellation()

        // Download audio
        setState(.downloading(progress: 0))

        let localURL: URL
        do {
            localURL = try await downloadAudio(from: response.audioUrl)
        } catch {
            throw TTSError.downloadFailed(error.localizedDescription)
        }

        // Cache the audio
        if configuration.cacheEnabled {
            cachedAudioURLs[cacheKey] = localURL
            cleanupCacheIfNeeded()
        }

        // Check cancellation
        try Task.checkCancellation()

        // Play audio
        try await playAudio(from: localURL)
    }

    private func downloadAudio(from urlString: String) async throws -> URL {
        guard let url = URL(string: urlString) else {
            throw TTSError.downloadFailed("Invalid audio URL")
        }

        let (tempURL, response) = try await URLSession.shared.download(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw TTSError.downloadFailed("Server returned error")
        }

        // Move to permanent location
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let ttsPath = documentsPath.appendingPathComponent("TTSCache", isDirectory: true)

        try? FileManager.default.createDirectory(at: ttsPath, withIntermediateDirectories: true)

        let fileName = "tts_\(UUID().uuidString).\(configuration.format.rawValue)"
        let permanentURL = ttsPath.appendingPathComponent(fileName)

        try FileManager.default.moveItem(at: tempURL, to: permanentURL)

        return permanentURL
    }

    private func playAudio(from url: URL) async throws {
        // Configure audio session
        do {
            try audioSession.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try audioSession.setActive(true)
        } catch {
            throw TTSError.audioSessionFailed(error.localizedDescription)
        }

        // Initialize player
        do {
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.delegate = self
            audioPlayer?.prepareToPlay()
        } catch {
            throw TTSError.playbackFailed(error.localizedDescription)
        }

        guard let player = audioPlayer else {
            throw TTSError.playbackFailed("Failed to create audio player")
        }

        duration = player.duration

        // Start playback
        if player.play() {
            startProgressTimer()
            setState(.playing(progress: 0))
        } else {
            throw TTSError.playbackFailed("Failed to start playback")
        }
    }

    private func startProgressTimer() {
        stopProgressTimer()

        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateProgress()
            }
        }
    }

    private func stopProgressTimer() {
        progressTimer?.invalidate()
        progressTimer = nil
    }

    private func updateProgress() {
        guard let player = audioPlayer, player.isPlaying else { return }

        let progress = player.duration > 0 ? player.currentTime / player.duration : 0
        playbackProgress = progress
        setState(.playing(progress: progress))
        delegate?.ttsFlow(self, didUpdatePlaybackProgress: progress)
    }

    private func setState(_ newState: TTSState) {
        state = newState
        delegate?.ttsFlow(self, didChangeState: newState)

        if case .failed(let error) = newState {
            delegate?.ttsFlow(self, didFailWithError: error)
        }
    }

    private func generateCacheKey(for text: String) -> String {
        // Create a hash-based key from text and configuration
        let configString = "\(configuration.voiceStyle.rawValue)_\(configuration.rate)_\(configuration.format.rawValue)"
        let combined = "\(text)_\(configString)"
        return String(combined.hashValue)
    }

    private func cleanupCacheIfNeeded() {
        // Calculate total cache size
        var totalSize: Int64 = 0
        var fileURLsWithDates: [(URL, Date)] = []

        for (_, url) in cachedAudioURLs {
            if let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) {
                let size = attributes[.size] as? Int64 ?? 0
                let date = attributes[.modificationDate] as? Date ?? Date.distantPast
                totalSize += size
                fileURLsWithDates.append((url, date))
            }
        }

        // Remove oldest files if over limit
        guard totalSize > configuration.maxCacheSize else { return }

        let sorted = fileURLsWithDates.sorted { $0.1 < $1.1 }

        for (url, _) in sorted {
            guard totalSize > configuration.maxCacheSize else { break }

            if let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
               let size = attributes[.size] as? Int64 {
                try? FileManager.default.removeItem(at: url)
                totalSize -= size

                // Remove from cache dictionary
                cachedAudioURLs = cachedAudioURLs.filter { $0.value != url }
            }
        }
    }
}

// MARK: - AVAudioPlayerDelegate

extension TTSFlow: AVAudioPlayerDelegate {

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            stopProgressTimer()
            playbackProgress = 1.0

            try? audioSession.setActive(false, options: .notifyOthersOnDeactivation)

            if flag {
                setState(.finished)
                delegate?.ttsFlowDidFinishPlaying(self)
            } else {
                setState(.failed(.playbackFailed("Playback ended unexpectedly")))
            }
        }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        Task { @MainActor in
            stopProgressTimer()
            setState(.failed(.playbackFailed(error?.localizedDescription ?? "Decode error")))
        }
    }

    nonisolated func audioPlayerBeginInterruption(_ player: AVAudioPlayer) {
        Task { @MainActor in
            if case .playing(let progress) = state {
                stopProgressTimer()
                setState(.paused(progress: progress))
            }
        }
    }

    nonisolated func audioPlayerEndInterruption(_ player: AVAudioPlayer, withOptions flags: Int) {
        Task { @MainActor in
            if case .paused = state {
                if flags == Int(AVAudioSession.InterruptionOptions.shouldResume.rawValue) {
                    resume()
                }
            }
        }
    }
}

// MARK: - TTS View Model

/// View model for TTS UI components
@MainActor
final class TTSViewModel: ObservableObject {

    // MARK: - Published Properties

    @Published private(set) var isLoading = false
    @Published private(set) var isPlaying = false
    @Published private(set) var progress: Double = 0
    @Published private(set) var error: TTSError?

    // MARK: - Properties

    private let ttsFlow: TTSFlow
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Computed Properties

    var canPlay: Bool {
        !isLoading && !isPlaying
    }

    // MARK: - Initialization

    init(ttsFlow: TTSFlow) {
        self.ttsFlow = ttsFlow
        setupBindings()
    }

    // MARK: - Public Methods

    func speak(_ text: String) {
        error = nil
        Task {
            await ttsFlow.speak(text)
        }
    }

    func speakTask(_ task: Task) {
        error = nil
        Task {
            await ttsFlow.speakTask(task)
        }
    }

    func togglePlayback() {
        ttsFlow.togglePlayback()
    }

    func stop() {
        ttsFlow.stop()
    }

    // MARK: - Private Methods

    private func setupBindings() {
        ttsFlow.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                guard let self = self else { return }

                switch state {
                case .idle:
                    self.isLoading = false
                    self.isPlaying = false
                    self.progress = 0
                case .loading, .downloading:
                    self.isLoading = true
                    self.isPlaying = false
                case .playing(let progressValue):
                    self.isLoading = false
                    self.isPlaying = true
                    self.progress = progressValue
                case .paused(let progressValue):
                    self.isLoading = false
                    self.isPlaying = false
                    self.progress = progressValue
                case .finished:
                    self.isLoading = false
                    self.isPlaying = false
                    self.progress = 1.0
                case .failed(let ttsError):
                    self.isLoading = false
                    self.isPlaying = false
                    self.error = ttsError
                }
            }
            .store(in: &cancellables)

        ttsFlow.$playbackProgress
            .receive(on: DispatchQueue.main)
            .assign(to: &$progress)
    }
}
