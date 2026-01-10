//
//  VoiceCapture.swift
//  TasksApp
//
//  Voice recording and audio capture for task creation
//  Supports real-time audio level monitoring for UI feedback
//

import Foundation
import AVFoundation
import Combine

// MARK: - Recording State

/// Current state of voice recording
enum RecordingState: Equatable, Sendable {
    case idle
    case preparing
    case recording
    case paused
    case stopping
    case finished(URL)
    case failed(RecordingError)

    var isRecording: Bool {
        self == .recording
    }

    var canStart: Bool {
        self == .idle || self == .failed(.unknown(""))
    }

    var canStop: Bool {
        self == .recording || self == .paused
    }
}

// MARK: - Recording Error

/// Errors during voice recording
enum RecordingError: LocalizedError, Equatable {
    case permissionDenied
    case permissionRestricted
    case audioSessionFailed(String)
    case recorderInitFailed(String)
    case recordingFailed(String)
    case fileNotFound
    case encodingFailed
    case interruptedBySystem
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Microphone access denied. Please enable in Settings."
        case .permissionRestricted:
            return "Microphone access is restricted on this device."
        case .audioSessionFailed(let message):
            return "Audio session error: \(message)"
        case .recorderInitFailed(let message):
            return "Failed to initialize recorder: \(message)"
        case .recordingFailed(let message):
            return "Recording failed: \(message)"
        case .fileNotFound:
            return "Recording file not found"
        case .encodingFailed:
            return "Failed to encode audio"
        case .interruptedBySystem:
            return "Recording was interrupted by another app"
        case .unknown(let message):
            return message
        }
    }

    static func == (lhs: RecordingError, rhs: RecordingError) -> Bool {
        lhs.errorDescription == rhs.errorDescription
    }
}

// MARK: - Recording Configuration

/// Configuration for voice recording
struct RecordingConfiguration: Sendable {
    /// Audio format
    let format: AudioFormat

    /// Sample rate in Hz
    let sampleRate: Double

    /// Number of channels (1 = mono, 2 = stereo)
    let numberOfChannels: Int

    /// Audio quality
    let quality: AudioQuality

    /// Maximum recording duration in seconds (0 = unlimited)
    let maxDuration: TimeInterval

    /// Enable audio level metering for UI
    let enableMetering: Bool

    /// Metering update interval in seconds
    let meteringInterval: TimeInterval

    enum AudioFormat: Sendable {
        case aac
        case mp4
        case wav
        case m4a

        var formatID: AudioFormatID {
            switch self {
            case .aac, .mp4, .m4a:
                return kAudioFormatMPEG4AAC
            case .wav:
                return kAudioFormatLinearPCM
            }
        }

        var fileExtension: String {
            switch self {
            case .aac: return "aac"
            case .mp4: return "mp4"
            case .wav: return "wav"
            case .m4a: return "m4a"
            }
        }
    }

    enum AudioQuality: Int, Sendable {
        case low = 0      // ~32 kbps
        case medium = 64  // ~64 kbps
        case high = 96    // ~96 kbps
        case max = 127    // ~128 kbps
    }

    static let `default` = RecordingConfiguration(
        format: .m4a,
        sampleRate: 44100.0,
        numberOfChannels: 1,
        quality: .high,
        maxDuration: 120, // 2 minutes
        enableMetering: true,
        meteringInterval: 0.05 // 50ms updates
    )

    static let voiceTask = RecordingConfiguration(
        format: .m4a,
        sampleRate: 22050.0, // Lower sample rate for voice
        numberOfChannels: 1,
        quality: .medium,
        maxDuration: 60, // 1 minute max for voice tasks
        enableMetering: true,
        meteringInterval: 0.05
    )
}

// MARK: - Audio Level

/// Represents current audio input level
struct AudioLevel: Sendable {
    /// Average power level in decibels (-160 to 0)
    let averagePower: Float

    /// Peak power level in decibels
    let peakPower: Float

    /// Normalized level (0.0 to 1.0) for UI display
    var normalizedLevel: Float {
        // Convert dB to linear scale
        // -60 dB or lower = 0, 0 dB = 1
        let minDb: Float = -60.0
        let level = max(0, (averagePower - minDb) / (-minDb))
        return min(1.0, level)
    }

    /// Whether the audio is considered "silent"
    var isSilent: Bool {
        averagePower < -50.0
    }

    static let zero = AudioLevel(averagePower: -160, peakPower: -160)
}

// MARK: - Voice Capture Delegate

/// Delegate protocol for voice capture events
protocol VoiceCaptureDelegate: AnyObject {
    func voiceCapture(_ capture: VoiceCapture, didChangeState state: RecordingState)
    func voiceCapture(_ capture: VoiceCapture, didUpdateAudioLevel level: AudioLevel)
    func voiceCapture(_ capture: VoiceCapture, didReachMaxDuration duration: TimeInterval)
    func voiceCapture(_ capture: VoiceCapture, didFinishWithURL url: URL)
    func voiceCapture(_ capture: VoiceCapture, didFailWithError error: RecordingError)
}

// MARK: - Voice Capture

/// Voice capture manager for recording audio
@MainActor
final class VoiceCapture: NSObject, ObservableObject {

    // MARK: - Published Properties

    @Published private(set) var state: RecordingState = .idle
    @Published private(set) var audioLevel: AudioLevel = .zero
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var recordingURL: URL?

    // MARK: - Properties

    weak var delegate: VoiceCaptureDelegate?

    private let configuration: RecordingConfiguration
    private var audioRecorder: AVAudioRecorder?
    private var audioSession: AVAudioSession { AVAudioSession.sharedInstance() }
    private var meteringTimer: Timer?
    private var durationTimer: Timer?
    private var startTime: Date?

    // MARK: - Initialization

    init(configuration: RecordingConfiguration = .voiceTask) {
        self.configuration = configuration
        super.init()
    }

    deinit {
        stopTimers()
        audioRecorder?.stop()
    }

    // MARK: - Permission

    /// Check current microphone permission status
    var permissionStatus: AVAudioSession.RecordPermission {
        audioSession.recordPermission
    }

    /// Request microphone permission
    func requestPermission() async -> Bool {
        return await withCheckedContinuation { continuation in
            audioSession.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    // MARK: - Recording Control

    /// Start recording
    func startRecording() async throws {
        guard state.canStart else { return }

        setState(.preparing)

        // Check permission
        switch audioSession.recordPermission {
        case .denied:
            throw RecordingError.permissionDenied
        case .undetermined:
            let granted = await requestPermission()
            if !granted {
                throw RecordingError.permissionDenied
            }
        case .granted:
            break
        @unknown default:
            break
        }

        // Configure audio session
        do {
            try audioSession.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            throw RecordingError.audioSessionFailed(error.localizedDescription)
        }

        // Create recording URL
        let url = generateRecordingURL()

        // Configure recorder settings
        let settings = recorderSettings()

        // Initialize recorder
        do {
            audioRecorder = try AVAudioRecorder(url: url, settings: settings)
            audioRecorder?.delegate = self
            audioRecorder?.isMeteringEnabled = configuration.enableMetering
        } catch {
            throw RecordingError.recorderInitFailed(error.localizedDescription)
        }

        // Prepare and start recording
        guard let recorder = audioRecorder else {
            throw RecordingError.recorderInitFailed("Recorder not initialized")
        }

        recorder.prepareToRecord()

        if recorder.record() {
            recordingURL = url
            startTime = Date()
            duration = 0
            startTimers()
            setState(.recording)
        } else {
            throw RecordingError.recordingFailed("Failed to start recording")
        }
    }

    /// Pause recording
    func pauseRecording() {
        guard state == .recording else { return }

        audioRecorder?.pause()
        stopTimers()
        setState(.paused)
    }

    /// Resume recording
    func resumeRecording() {
        guard state == .paused else { return }

        if audioRecorder?.record() == true {
            startTimers()
            setState(.recording)
        }
    }

    /// Stop recording and finalize
    func stopRecording() async throws -> URL {
        guard state.canStop else {
            throw RecordingError.unknown("Cannot stop recording in current state")
        }

        setState(.stopping)
        stopTimers()

        audioRecorder?.stop()

        // Deactivate audio session
        try? audioSession.setActive(false, options: .notifyOthersOnDeactivation)

        guard let url = recordingURL else {
            throw RecordingError.fileNotFound
        }

        // Verify file exists
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw RecordingError.fileNotFound
        }

        setState(.finished(url))
        delegate?.voiceCapture(self, didFinishWithURL: url)

        return url
    }

    /// Cancel recording and delete file
    func cancelRecording() {
        stopTimers()
        audioRecorder?.stop()

        // Delete recording file
        if let url = recordingURL {
            try? FileManager.default.removeItem(at: url)
        }

        recordingURL = nil
        duration = 0
        audioLevel = .zero

        try? audioSession.setActive(false, options: .notifyOthersOnDeactivation)

        setState(.idle)
    }

    /// Delete a recording file
    func deleteRecording(at url: URL) {
        try? FileManager.default.removeItem(at: url)

        if recordingURL == url {
            recordingURL = nil
            setState(.idle)
        }
    }

    // MARK: - Private Methods

    private func setState(_ newState: RecordingState) {
        state = newState
        delegate?.voiceCapture(self, didChangeState: newState)

        if case .failed(let error) = newState {
            delegate?.voiceCapture(self, didFailWithError: error)
        }
    }

    private func generateRecordingURL() -> URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let recordingsPath = documentsPath.appendingPathComponent("VoiceRecordings", isDirectory: true)

        // Create directory if needed
        try? FileManager.default.createDirectory(at: recordingsPath, withIntermediateDirectories: true)

        let fileName = "voice_\(Date().timeIntervalSince1970).\(configuration.format.fileExtension)"
        return recordingsPath.appendingPathComponent(fileName)
    }

    private func recorderSettings() -> [String: Any] {
        var settings: [String: Any] = [
            AVFormatIDKey: configuration.format.formatID,
            AVSampleRateKey: configuration.sampleRate,
            AVNumberOfChannelsKey: configuration.numberOfChannels,
            AVEncoderAudioQualityKey: configuration.quality.rawValue
        ]

        // Add bit rate for compressed formats
        if configuration.format != .wav {
            let bitRate = configuration.quality.rawValue * 1000
            settings[AVEncoderBitRateKey] = bitRate
        }

        return settings
    }

    private func startTimers() {
        // Metering timer
        if configuration.enableMetering {
            meteringTimer = Timer.scheduledTimer(
                withTimeInterval: configuration.meteringInterval,
                repeats: true
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.updateMetering()
                }
            }
        }

        // Duration timer
        durationTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateDuration()
            }
        }
    }

    private func stopTimers() {
        meteringTimer?.invalidate()
        meteringTimer = nil
        durationTimer?.invalidate()
        durationTimer = nil
    }

    private func updateMetering() {
        guard let recorder = audioRecorder, recorder.isRecording else { return }

        recorder.updateMeters()

        let level = AudioLevel(
            averagePower: recorder.averagePower(forChannel: 0),
            peakPower: recorder.peakPower(forChannel: 0)
        )

        audioLevel = level
        delegate?.voiceCapture(self, didUpdateAudioLevel: level)
    }

    private func updateDuration() {
        guard let start = startTime, state == .recording else { return }

        duration = Date().timeIntervalSince(start)

        // Check max duration
        if configuration.maxDuration > 0 && duration >= configuration.maxDuration {
            delegate?.voiceCapture(self, didReachMaxDuration: duration)
            Task {
                _ = try? await stopRecording()
            }
        }
    }
}

// MARK: - AVAudioRecorderDelegate

extension VoiceCapture: AVAudioRecorderDelegate {

    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        Task { @MainActor in
            if !flag && state == .recording {
                setState(.failed(.recordingFailed("Recording finished unsuccessfully")))
            }
        }
    }

    nonisolated func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        Task { @MainActor in
            setState(.failed(.encodingFailed))
        }
    }

    nonisolated func audioRecorderBeginInterruption(_ recorder: AVAudioRecorder) {
        Task { @MainActor in
            if state == .recording {
                pauseRecording()
            }
        }
    }

    nonisolated func audioRecorderEndInterruption(_ recorder: AVAudioRecorder, withOptions flags: Int) {
        Task { @MainActor in
            if state == .paused && flags == Int(AVAudioSession.InterruptionOptions.shouldResume.rawValue) {
                resumeRecording()
            }
        }
    }
}

// MARK: - Audio Level View Model

/// View model for audio level visualization
@MainActor
final class AudioLevelViewModel: ObservableObject {

    @Published var levels: [Float] = []
    @Published var currentLevel: Float = 0

    private let maxLevels: Int
    private var smoothingFactor: Float = 0.3

    init(maxLevels: Int = 50) {
        self.maxLevels = maxLevels
        self.levels = Array(repeating: 0, count: maxLevels)
    }

    func update(with audioLevel: AudioLevel) {
        // Smooth the level
        let targetLevel = audioLevel.normalizedLevel
        currentLevel = currentLevel + (targetLevel - currentLevel) * smoothingFactor

        // Add to history
        levels.removeFirst()
        levels.append(currentLevel)
    }

    func reset() {
        currentLevel = 0
        levels = Array(repeating: 0, count: maxLevels)
    }
}

// MARK: - Duration Formatter

extension VoiceCapture {

    /// Format duration as MM:SS
    static func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    /// Formatted current duration
    var formattedDuration: String {
        Self.formatDuration(duration)
    }
}
