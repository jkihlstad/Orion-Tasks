//
//  MediaUploadClient.swift
//  TasksApp
//
//  Media upload client for attachments
//  Supports progress tracking, resumable uploads, and background uploads
//

import Foundation
import Combine
import CoreData
import UIKit

// MARK: - Upload State

/// State of an upload operation
enum UploadState: Equatable, Sendable {
    case pending
    case preparing
    case uploading(progress: Double)
    case processing
    case completed(remoteUrl: String)
    case failed(UploadError)
    case cancelled

    var isActive: Bool {
        switch self {
        case .preparing, .uploading, .processing:
            return true
        default:
            return false
        }
    }

    var isCompleted: Bool {
        if case .completed = self {
            return true
        }
        return false
    }

    static func == (lhs: UploadState, rhs: UploadState) -> Bool {
        switch (lhs, rhs) {
        case (.pending, .pending),
             (.preparing, .preparing),
             (.processing, .processing),
             (.cancelled, .cancelled):
            return true
        case (.uploading(let p1), .uploading(let p2)):
            return p1 == p2
        case (.completed(let u1), .completed(let u2)):
            return u1 == u2
        case (.failed(let e1), .failed(let e2)):
            return e1.localizedDescription == e2.localizedDescription
        default:
            return false
        }
    }
}

// MARK: - Upload Error

/// Errors during upload operations
enum UploadError: LocalizedError, Equatable {
    case fileNotFound
    case fileTooLarge(maxSize: Int64)
    case unsupportedFileType
    case networkError(String)
    case serverError(Int, String)
    case authenticationRequired
    case uploadUrlExpired
    case cancelled
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .fileNotFound:
            return "File not found"
        case .fileTooLarge(let maxSize):
            let formatter = ByteCountFormatter()
            formatter.countStyle = .file
            return "File too large. Maximum size: \(formatter.string(fromByteCount: maxSize))"
        case .unsupportedFileType:
            return "Unsupported file type"
        case .networkError(let message):
            return "Network error: \(message)"
        case .serverError(let code, let message):
            return "Server error (\(code)): \(message)"
        case .authenticationRequired:
            return "Authentication required"
        case .uploadUrlExpired:
            return "Upload URL expired"
        case .cancelled:
            return "Upload cancelled"
        case .unknown(let message):
            return message
        }
    }

    static func == (lhs: UploadError, rhs: UploadError) -> Bool {
        lhs.errorDescription == rhs.errorDescription
    }
}

// MARK: - Upload Task Info

/// Information about an upload task
struct UploadTaskInfo: Identifiable, Sendable {
    let id: String
    let attachmentId: String
    let taskId: String
    let fileName: String
    let fileSize: Int64
    let mimeType: String
    var state: UploadState
    var progress: Double
    var startedAt: Date?
    var completedAt: Date?
    var error: UploadError?

    var isActive: Bool {
        state.isActive
    }
}

// MARK: - Upload Configuration

/// Configuration for the upload client
struct UploadConfiguration: Sendable {
    /// Maximum file size in bytes
    let maxFileSize: Int64

    /// Chunk size for large uploads (bytes)
    let chunkSize: Int64

    /// Maximum concurrent uploads
    let maxConcurrentUploads: Int

    /// Retry attempts for failed uploads
    let maxRetryAttempts: Int

    /// Base delay for retry backoff
    let baseRetryDelay: TimeInterval

    /// Supported MIME types
    let supportedMimeTypes: Set<String>

    static let `default` = UploadConfiguration(
        maxFileSize: 100 * 1024 * 1024, // 100 MB
        chunkSize: 5 * 1024 * 1024, // 5 MB chunks
        maxConcurrentUploads: 3,
        maxRetryAttempts: 3,
        baseRetryDelay: 1.0,
        supportedMimeTypes: [
            "image/jpeg", "image/png", "image/gif", "image/heic", "image/heif", "image/webp",
            "video/mp4", "video/quicktime", "video/x-m4v",
            "audio/mpeg", "audio/mp4", "audio/x-m4a", "audio/wav",
            "application/pdf",
            "text/plain", "text/rtf",
            "application/msword",
            "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
        ]
    )
}

// MARK: - Media Upload Client

/// Client for uploading media attachments
final class MediaUploadClientImpl: NSObject, @unchecked Sendable {

    // MARK: - Properties

    private let configuration: UploadConfiguration
    private let tasksAPI: TasksAPI
    private let persistenceController: PersistenceController
    private var session: URLSession!

    // Active uploads
    private var activeUploads: [String: UploadTaskInfo] = [:]
    private var uploadTasks: [String: URLSessionUploadTask] = [:]
    private let uploadsLock = NSLock()

    // Combine publishers
    private let uploadProgressSubject = PassthroughSubject<(String, Double), Never>()
    private let uploadCompletedSubject = PassthroughSubject<(String, String), Never>()
    private let uploadFailedSubject = PassthroughSubject<(String, UploadError), Never>()

    var uploadProgress: AnyPublisher<(String, Double), Never> {
        uploadProgressSubject.eraseToAnyPublisher()
    }

    var uploadCompleted: AnyPublisher<(String, String), Never> {
        uploadCompletedSubject.eraseToAnyPublisher()
    }

    var uploadFailed: AnyPublisher<(String, UploadError), Never> {
        uploadFailedSubject.eraseToAnyPublisher()
    }

    // MARK: - Initialization

    init(
        configuration: UploadConfiguration = .default,
        tasksAPI: TasksAPI,
        persistenceController: PersistenceController = .shared
    ) {
        self.configuration = configuration
        self.tasksAPI = tasksAPI
        self.persistenceController = persistenceController

        super.init()

        // Configure URL session for uploads
        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.timeoutIntervalForRequest = 300
        sessionConfig.timeoutIntervalForResource = 600
        sessionConfig.waitsForConnectivity = true
        sessionConfig.allowsCellularAccess = true

        self.session = URLSession(
            configuration: sessionConfig,
            delegate: self,
            delegateQueue: nil
        )
    }

    // MARK: - Public Methods

    /// Uploads a file attachment
    @discardableResult
    func uploadAttachment(
        taskId: String,
        fileUrl: URL,
        fileName: String? = nil,
        mimeType: String? = nil
    ) async throws -> String {
        // Validate file exists
        guard FileManager.default.fileExists(atPath: fileUrl.path) else {
            throw UploadError.fileNotFound
        }

        // Get file attributes
        let attributes = try FileManager.default.attributesOfItem(atPath: fileUrl.path)
        let fileSize = attributes[.size] as? Int64 ?? 0

        // Validate file size
        guard fileSize <= configuration.maxFileSize else {
            throw UploadError.fileTooLarge(maxSize: configuration.maxFileSize)
        }

        // Determine MIME type
        let detectedMimeType = mimeType ?? detectMimeType(for: fileUrl)
        guard configuration.supportedMimeTypes.contains(detectedMimeType) else {
            throw UploadError.unsupportedFileType
        }

        let finalFileName = fileName ?? fileUrl.lastPathComponent
        let attachmentId = UUID().uuidString

        // Create upload task info
        var uploadInfo = UploadTaskInfo(
            id: UUID().uuidString,
            attachmentId: attachmentId,
            taskId: taskId,
            fileName: finalFileName,
            fileSize: fileSize,
            mimeType: detectedMimeType,
            state: .preparing,
            progress: 0,
            startedAt: Date()
        )

        registerUpload(uploadInfo)

        do {
            // Get upload URL from server
            let uploadUrlResponse = try await tasksAPI.getUploadUrl(
                taskId: taskId,
                fileName: finalFileName,
                mimeType: detectedMimeType,
                fileSize: fileSize
            )

            // Read file data
            let fileData = try Data(contentsOf: fileUrl)

            // Update state
            uploadInfo.state = .uploading(progress: 0)
            updateUpload(uploadInfo)

            // Perform upload
            let remoteUrl = try await performUpload(
                data: fileData,
                uploadUrl: uploadUrlResponse.uploadUrl,
                attachmentId: uploadUrlResponse.attachmentId,
                uploadInfo: &uploadInfo
            )

            // Register attachment with server
            _ = try await tasksAPI.addAttachment(
                taskId: taskId,
                attachmentId: uploadUrlResponse.attachmentId,
                fileName: finalFileName,
                mimeType: detectedMimeType,
                fileSize: fileSize,
                remoteUrl: remoteUrl
            )

            // Update local CoreData
            updateLocalAttachment(
                attachmentId: uploadUrlResponse.attachmentId,
                taskId: taskId,
                remoteUrl: remoteUrl,
                status: .completed
            )

            // Complete upload
            uploadInfo.state = .completed(remoteUrl: remoteUrl)
            uploadInfo.completedAt = Date()
            updateUpload(uploadInfo)

            uploadCompletedSubject.send((uploadInfo.attachmentId, remoteUrl))

            return remoteUrl

        } catch {
            let uploadError: UploadError
            if let ue = error as? UploadError {
                uploadError = ue
            } else {
                uploadError = .unknown(error.localizedDescription)
            }

            uploadInfo.state = .failed(uploadError)
            uploadInfo.error = uploadError
            updateUpload(uploadInfo)

            updateLocalAttachment(
                attachmentId: attachmentId,
                taskId: taskId,
                remoteUrl: nil,
                status: .failed
            )

            uploadFailedSubject.send((uploadInfo.attachmentId, uploadError))

            throw uploadError
        }
    }

    /// Uploads pending attachments (for background sync)
    func uploadPendingAttachments() async throws -> Int {
        let pendingAttachments = fetchPendingAttachments()
        var uploadedCount = 0

        for attachment in pendingAttachments {
            guard let localPath = attachment.localPath,
                  let localUrl = getLocalFileUrl(path: localPath) else {
                continue
            }

            do {
                _ = try await uploadAttachment(
                    taskId: attachment.taskId,
                    fileUrl: localUrl,
                    fileName: attachment.fileName,
                    mimeType: attachment.mimeType
                )
                uploadedCount += 1
            } catch {
                print("[MediaUpload] Failed to upload \(attachment.id): \(error)")
            }
        }

        return uploadedCount
    }

    /// Cancels an upload
    func cancelUpload(attachmentId: String) {
        uploadsLock.lock()
        defer { uploadsLock.unlock() }

        if let task = uploadTasks[attachmentId] {
            task.cancel()
            uploadTasks.removeValue(forKey: attachmentId)
        }

        if var uploadInfo = activeUploads[attachmentId] {
            uploadInfo.state = .cancelled
            activeUploads[attachmentId] = uploadInfo
        }

        updateLocalAttachment(
            attachmentId: attachmentId,
            taskId: "",
            remoteUrl: nil,
            status: .pending
        )
    }

    /// Cancels all active uploads
    func cancelAllUploads() {
        uploadsLock.lock()
        let attachmentIds = Array(uploadTasks.keys)
        uploadsLock.unlock()

        for attachmentId in attachmentIds {
            cancelUpload(attachmentId: attachmentId)
        }
    }

    /// Gets current upload info
    func getUploadInfo(attachmentId: String) -> UploadTaskInfo? {
        uploadsLock.lock()
        defer { uploadsLock.unlock() }
        return activeUploads[attachmentId]
    }

    /// Gets all active uploads
    func getActiveUploads() -> [UploadTaskInfo] {
        uploadsLock.lock()
        defer { uploadsLock.unlock() }
        return Array(activeUploads.values.filter { $0.isActive })
    }

    // MARK: - Private Methods

    private func performUpload(
        data: Data,
        uploadUrl: String,
        attachmentId: String,
        uploadInfo: inout UploadTaskInfo
    ) async throws -> String {
        guard let url = URL(string: uploadUrl) else {
            throw UploadError.unknown("Invalid upload URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue(uploadInfo.mimeType, forHTTPHeaderField: "Content-Type")
        request.setValue(String(data.count), forHTTPHeaderField: "Content-Length")

        return try await withCheckedThrowingContinuation { continuation in
            let task = session.uploadTask(with: request, from: data) { [weak self] data, response, error in
                if let error = error {
                    if (error as NSError).code == NSURLErrorCancelled {
                        continuation.resume(throwing: UploadError.cancelled)
                    } else {
                        continuation.resume(throwing: UploadError.networkError(error.localizedDescription))
                    }
                    return
                }

                guard let httpResponse = response as? HTTPURLResponse else {
                    continuation.resume(throwing: UploadError.unknown("Invalid response"))
                    return
                }

                switch httpResponse.statusCode {
                case 200..<300:
                    // Success - construct the remote URL
                    // This depends on your storage provider's response format
                    let remoteUrl = self?.extractRemoteUrl(from: data, response: httpResponse, uploadUrl: uploadUrl)
                        ?? uploadUrl
                    continuation.resume(returning: remoteUrl)

                case 401, 403:
                    continuation.resume(throwing: UploadError.authenticationRequired)

                default:
                    let errorMessage = data.flatMap { String(data: $0, encoding: .utf8) } ?? "Upload failed"
                    continuation.resume(throwing: UploadError.serverError(httpResponse.statusCode, errorMessage))
                }
            }

            // Store task reference for progress tracking
            uploadsLock.lock()
            uploadTasks[attachmentId] = task
            uploadsLock.unlock()

            task.resume()
        }
    }

    private func extractRemoteUrl(from data: Data?, response: HTTPURLResponse, uploadUrl: String) -> String {
        // Try to extract URL from response headers (common for S3-like storage)
        if let location = response.value(forHTTPHeaderField: "Location") {
            return location
        }

        // Try to extract from response body
        if let data = data,
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let url = json["url"] as? String ?? json["publicUrl"] as? String {
            return url
        }

        // Fall back to upload URL (may need to be transformed)
        // Remove query parameters for the final URL
        if let urlComponents = URLComponents(string: uploadUrl) {
            var cleanComponents = urlComponents
            cleanComponents.queryItems = nil
            return cleanComponents.url?.absoluteString ?? uploadUrl
        }

        return uploadUrl
    }

    private func registerUpload(_ info: UploadTaskInfo) {
        uploadsLock.lock()
        activeUploads[info.attachmentId] = info
        uploadsLock.unlock()
    }

    private func updateUpload(_ info: UploadTaskInfo) {
        uploadsLock.lock()
        activeUploads[info.attachmentId] = info
        uploadsLock.unlock()

        if case .uploading(let progress) = info.state {
            uploadProgressSubject.send((info.attachmentId, progress))
        }
    }

    private func detectMimeType(for url: URL) -> String {
        let pathExtension = url.pathExtension.lowercased()

        let mimeTypes: [String: String] = [
            "jpg": "image/jpeg",
            "jpeg": "image/jpeg",
            "png": "image/png",
            "gif": "image/gif",
            "heic": "image/heic",
            "heif": "image/heif",
            "webp": "image/webp",
            "mp4": "video/mp4",
            "mov": "video/quicktime",
            "m4v": "video/x-m4v",
            "mp3": "audio/mpeg",
            "m4a": "audio/mp4",
            "wav": "audio/wav",
            "pdf": "application/pdf",
            "txt": "text/plain",
            "rtf": "text/rtf",
            "doc": "application/msword",
            "docx": "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
        ]

        return mimeTypes[pathExtension] ?? "application/octet-stream"
    }

    private func getLocalFileUrl(path: String) -> URL? {
        let documentsDirectory = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first

        return documentsDirectory?.appendingPathComponent(path)
    }

    private func fetchPendingAttachments() -> [CDAttachmentRef] {
        let context = persistenceController.viewContext
        var results: [CDAttachmentRef] = []

        context.performAndWait {
            let request = CDAttachmentRef.fetchRequest()
            request.predicate = NSPredicate(
                format: "uploadStatus == %d AND localPath != nil",
                UploadStatus.pending.rawValue
            )
            request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]

            results = (try? context.fetch(request)) ?? []
        }

        return results
    }

    private func updateLocalAttachment(
        attachmentId: String,
        taskId: String,
        remoteUrl: String?,
        status: UploadStatus
    ) {
        let context = persistenceController.newBackgroundContext()

        context.performAndWait {
            let request = CDAttachmentRef.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", attachmentId)
            request.fetchLimit = 1

            if let attachment = try? context.fetch(request).first {
                attachment.uploadStatus = status.rawValue
                if let url = remoteUrl {
                    attachment.remoteURL = url
                }
                try? context.save()
            }
        }
    }
}

// MARK: - URLSession Delegate

extension MediaUploadClientImpl: URLSessionTaskDelegate {

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didSendBodyData bytesSent: Int64,
        totalBytesSent: Int64,
        totalBytesExpectedToSend: Int64
    ) {
        // Find the attachment ID for this task
        uploadsLock.lock()
        let attachmentId = uploadTasks.first { $0.value == task as? URLSessionUploadTask }?.key
        uploadsLock.unlock()

        guard let attachmentId = attachmentId else { return }

        let progress = Double(totalBytesSent) / Double(totalBytesExpectedToSend)

        uploadsLock.lock()
        if var info = activeUploads[attachmentId] {
            info.progress = progress
            info.state = .uploading(progress: progress)
            activeUploads[attachmentId] = info
        }
        uploadsLock.unlock()

        uploadProgressSubject.send((attachmentId, progress))
    }
}

// MARK: - Image Compression

extension MediaUploadClientImpl {

    /// Compresses an image for upload
    func compressImage(
        at url: URL,
        maxDimension: CGFloat = 2048,
        quality: CGFloat = 0.8
    ) throws -> Data {
        guard let image = UIImage(contentsOfFile: url.path) else {
            throw UploadError.fileNotFound
        }

        // Calculate new size maintaining aspect ratio
        let size = image.size
        var newSize = size

        if size.width > maxDimension || size.height > maxDimension {
            let ratio = min(maxDimension / size.width, maxDimension / size.height)
            newSize = CGSize(
                width: size.width * ratio,
                height: size.height * ratio
            )
        }

        // Resize image
        UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
        image.draw(in: CGRect(origin: .zero, size: newSize))
        let resizedImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        // Compress to JPEG
        guard let data = resizedImage?.jpegData(compressionQuality: quality) else {
            throw UploadError.unknown("Failed to compress image")
        }

        return data
    }

    /// Creates a thumbnail for an image
    func createThumbnail(
        for url: URL,
        maxDimension: CGFloat = 300
    ) throws -> Data {
        return try compressImage(at: url, maxDimension: maxDimension, quality: 0.7)
    }
}

// MARK: - Video Compression (Placeholder)

extension MediaUploadClientImpl {

    /// Compresses a video for upload (placeholder - requires AVFoundation)
    func compressVideo(at url: URL) async throws -> URL {
        // This would require AVFoundation implementation
        // For now, return the original URL
        return url
    }
}
