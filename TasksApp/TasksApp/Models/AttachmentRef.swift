//
//  AttachmentRef.swift
//  TasksApp
//
//  Domain model for AttachmentRef entity - references to media attachments
//

import Foundation
import UniformTypeIdentifiers

// MARK: - MediaType

/// Types of media that can be attached to tasks
enum MediaType: String, Codable, Hashable, CaseIterable, Sendable {
    case image
    case video
    case audio
    case document
    case pdf
    case url
    case other

    /// Common file extensions for this media type
    var fileExtensions: [String] {
        switch self {
        case .image:
            return ["jpg", "jpeg", "png", "gif", "heic", "heif", "webp", "tiff", "bmp"]
        case .video:
            return ["mp4", "mov", "m4v", "avi", "mkv", "webm"]
        case .audio:
            return ["mp3", "m4a", "wav", "aac", "flac", "aiff"]
        case .document:
            return ["doc", "docx", "txt", "rtf", "pages", "xls", "xlsx", "numbers", "ppt", "pptx", "keynote"]
        case .pdf:
            return ["pdf"]
        case .url:
            return []
        case .other:
            return []
        }
    }

    /// UTType identifiers for this media type
    var utTypes: [UTType] {
        switch self {
        case .image:
            return [.image, .jpeg, .png, .gif, .heic, .heif, .webP, .tiff, .bmp]
        case .video:
            return [.movie, .video, .mpeg4Movie, .quickTimeMovie, .avi]
        case .audio:
            return [.audio, .mp3, .wav, .aiff, .mpeg4Audio]
        case .document:
            return [.plainText, .rtf, .spreadsheet, .presentation]
        case .pdf:
            return [.pdf]
        case .url:
            return [.url]
        case .other:
            return [.data, .item]
        }
    }

    /// SF Symbol name for the media type
    var symbolName: String {
        switch self {
        case .image: return "photo.fill"
        case .video: return "video.fill"
        case .audio: return "waveform"
        case .document: return "doc.fill"
        case .pdf: return "doc.text.fill"
        case .url: return "link"
        case .other: return "paperclip"
        }
    }

    /// Detects media type from file extension
    static func from(fileExtension: String) -> MediaType {
        let ext = fileExtension.lowercased()
        for type in allCases {
            if type.fileExtensions.contains(ext) {
                return type
            }
        }
        return .other
    }

    /// Detects media type from UTType
    static func from(utType: UTType) -> MediaType {
        for type in allCases {
            for supportedType in type.utTypes {
                if utType.conforms(to: supportedType) {
                    return type
                }
            }
        }
        return .other
    }

    /// Detects media type from MIME type string
    static func from(mimeType: String) -> MediaType {
        let mime = mimeType.lowercased()
        if mime.hasPrefix("image/") { return .image }
        if mime.hasPrefix("video/") { return .video }
        if mime.hasPrefix("audio/") { return .audio }
        if mime == "application/pdf" { return .pdf }
        if mime.hasPrefix("text/") || mime.contains("document") { return .document }
        return .other
    }
}

// MARK: - UploadStatus

/// Status of attachment upload to cloud storage
enum UploadStatus: String, Codable, Hashable, Sendable {
    /// Not yet uploaded, only exists locally
    case pending

    /// Currently being uploaded
    case uploading

    /// Successfully uploaded to cloud
    case uploaded

    /// Upload failed, needs retry
    case failed

    /// Only exists remotely, not downloaded locally
    case remoteOnly

    /// Display name for the status
    var displayName: String {
        switch self {
        case .pending: return "Pending"
        case .uploading: return "Uploading"
        case .uploaded: return "Uploaded"
        case .failed: return "Failed"
        case .remoteOnly: return "Remote"
        }
    }

    /// SF Symbol name for the status
    var symbolName: String {
        switch self {
        case .pending: return "clock"
        case .uploading: return "arrow.up.circle"
        case .uploaded: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        case .remoteOnly: return "icloud"
        }
    }

    /// Whether the attachment is available locally
    var isLocallyAvailable: Bool {
        switch self {
        case .pending, .uploading, .uploaded, .failed:
            return true
        case .remoteOnly:
            return false
        }
    }

    /// Whether the attachment needs to be synced
    var needsSync: Bool {
        switch self {
        case .pending, .failed:
            return true
        case .uploading, .uploaded, .remoteOnly:
            return false
        }
    }
}

// MARK: - AttachmentRef

/// Reference to a media attachment associated with a task
struct AttachmentRef: Identifiable, Codable, Hashable, Sendable {

    // MARK: - Properties

    /// Unique identifier for the attachment
    let id: String

    /// Type of media
    let mediaType: MediaType

    /// Local file path relative to app's documents directory
    var localPath: String?

    /// Remote URL for cloud-synced attachments
    var remoteUrl: String?

    /// Current upload/sync status
    var uploadStatus: UploadStatus

    /// Original filename (for display purposes)
    var originalFilename: String?

    /// File size in bytes
    var fileSize: Int64?

    /// MIME type of the file
    var mimeType: String?

    /// Thumbnail path for images/videos
    var thumbnailPath: String?

    /// When the attachment was created
    let createdAt: Date

    /// When the attachment was last modified
    var updatedAt: Date

    // MARK: - Initialization

    /// Creates a new attachment reference
    init(
        id: String = UUID().uuidString,
        mediaType: MediaType,
        localPath: String? = nil,
        remoteUrl: String? = nil,
        uploadStatus: UploadStatus = .pending,
        originalFilename: String? = nil,
        fileSize: Int64? = nil,
        mimeType: String? = nil,
        thumbnailPath: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.mediaType = mediaType
        self.localPath = localPath
        self.remoteUrl = remoteUrl
        self.uploadStatus = uploadStatus
        self.originalFilename = originalFilename
        self.fileSize = fileSize
        self.mimeType = mimeType
        self.thumbnailPath = thumbnailPath
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    // MARK: - Computed Properties

    /// Whether the attachment has a local file
    var hasLocalFile: Bool {
        localPath != nil && uploadStatus.isLocallyAvailable
    }

    /// Whether the attachment has a remote URL
    var hasRemoteUrl: Bool {
        remoteUrl != nil
    }

    /// File extension from the original filename or local path
    var fileExtension: String? {
        if let filename = originalFilename {
            return URL(fileURLWithPath: filename).pathExtension
        }
        if let path = localPath {
            return URL(fileURLWithPath: path).pathExtension
        }
        return nil
    }

    /// Formatted file size string
    var formattedFileSize: String? {
        guard let size = fileSize else { return nil }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }

    /// Full local URL (resolved from documents directory)
    var localUrl: URL? {
        guard let path = localPath else { return nil }
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        return documentsDirectory?.appendingPathComponent(path)
    }

    /// Remote URL object
    var remoteURL: URL? {
        guard let urlString = remoteUrl else { return nil }
        return URL(string: urlString)
    }

    /// Best available URL (prefers local)
    var bestAvailableUrl: URL? {
        if hasLocalFile, let url = localUrl {
            return url
        }
        return remoteURL
    }

    // MARK: - Mutating Methods

    /// Updates the upload status
    mutating func setUploadStatus(_ status: UploadStatus) {
        uploadStatus = status
        updatedAt = Date()
    }

    /// Sets the remote URL after successful upload
    mutating func setRemoteUrl(_ url: String) {
        remoteUrl = url
        uploadStatus = .uploaded
        updatedAt = Date()
    }

    /// Marks the upload as failed
    mutating func markUploadFailed() {
        uploadStatus = .failed
        updatedAt = Date()
    }

    /// Updates the local path
    mutating func setLocalPath(_ path: String) {
        localPath = path
        if uploadStatus == .remoteOnly {
            uploadStatus = .uploaded
        }
        updatedAt = Date()
    }

    /// Removes the local file reference (for cleanup)
    mutating func clearLocalPath() {
        localPath = nil
        thumbnailPath = nil
        if uploadStatus != .remoteOnly && hasRemoteUrl {
            uploadStatus = .remoteOnly
        }
        updatedAt = Date()
    }
}

// MARK: - AttachmentRef Hashable

extension AttachmentRef {
    static func == (lhs: AttachmentRef, rhs: AttachmentRef) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - AttachmentRef Factory Methods

extension AttachmentRef {
    /// Creates an attachment reference for a local image
    static func localImage(path: String, filename: String? = nil, fileSize: Int64? = nil) -> AttachmentRef {
        AttachmentRef(
            mediaType: .image,
            localPath: path,
            uploadStatus: .pending,
            originalFilename: filename,
            fileSize: fileSize,
            mimeType: "image/jpeg"
        )
    }

    /// Creates an attachment reference for a URL
    static func url(_ urlString: String) -> AttachmentRef {
        AttachmentRef(
            mediaType: .url,
            remoteUrl: urlString,
            uploadStatus: .uploaded,
            originalFilename: nil
        )
    }

    /// Creates an attachment reference for a PDF document
    static func pdf(path: String, filename: String, fileSize: Int64? = nil) -> AttachmentRef {
        AttachmentRef(
            mediaType: .pdf,
            localPath: path,
            uploadStatus: .pending,
            originalFilename: filename,
            fileSize: fileSize,
            mimeType: "application/pdf"
        )
    }
}

// MARK: - Sample Data

extension AttachmentRef {
    /// Sample attachment for previews and testing
    static let sample = AttachmentRef(
        id: "sample-attachment-1",
        mediaType: .image,
        localPath: "attachments/photo1.jpg",
        uploadStatus: .uploaded,
        originalFilename: "Meeting Notes.jpg",
        fileSize: 1_250_000
    )

    /// Sample attachments for previews
    static let sampleAttachments: [AttachmentRef] = [
        AttachmentRef(
            id: "attachment-1",
            mediaType: .image,
            localPath: "attachments/photo1.jpg",
            remoteUrl: "https://example.com/photo1.jpg",
            uploadStatus: .uploaded,
            originalFilename: "Project Screenshot.jpg",
            fileSize: 2_500_000
        ),
        AttachmentRef(
            id: "attachment-2",
            mediaType: .pdf,
            localPath: "attachments/document.pdf",
            uploadStatus: .pending,
            originalFilename: "Requirements.pdf",
            fileSize: 150_000
        ),
        AttachmentRef(
            id: "attachment-3",
            mediaType: .url,
            remoteUrl: "https://example.com/reference",
            uploadStatus: .uploaded,
            originalFilename: "Reference Link"
        )
    ]
}
