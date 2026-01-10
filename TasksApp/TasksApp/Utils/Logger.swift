//
//  Logger.swift
//  TasksApp
//
//  Centralized logging utility with category-based filtering,
//  configurable log levels, and timestamp formatting
//

import Foundation
import os.log

// MARK: - Log Level

/// Log severity levels in ascending order of importance
enum LogLevel: Int, Comparable, Sendable {
    case debug = 0
    case info = 1
    case warning = 2
    case error = 3

    var prefix: String {
        switch self {
        case .debug: return "[DEBUG]"
        case .info: return "[INFO]"
        case .warning: return "[WARNING]"
        case .error: return "[ERROR]"
        }
    }

    var osLogType: OSLogType {
        switch self {
        case .debug: return .debug
        case .info: return .info
        case .warning: return .default
        case .error: return .error
        }
    }

    static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

// MARK: - Log Category

/// Categories for organizing log messages
enum LogCategory: String, Sendable {
    // Core
    case app = "App"
    case auth = "Auth"
    case sync = "Sync"
    case network = "Network"
    case data = "Data"

    // Features
    case tasks = "Tasks"
    case lists = "Lists"
    case calendar = "Calendar"
    case notifications = "Notifications"
    case ai = "AI"
    case voice = "Voice"

    // System
    case ui = "UI"
    case performance = "Performance"
    case consent = "Consent"
    case analytics = "Analytics"

    var osLog: OSLog {
        OSLog(subsystem: Logger.subsystem, category: rawValue)
    }
}

// MARK: - Logger Configuration

/// Configuration for the logging system
struct LoggerConfiguration: Sendable {
    /// Minimum log level to output (logs below this level are ignored)
    let minimumLevel: LogLevel

    /// Whether to include timestamps in output
    let includeTimestamps: Bool

    /// Whether to include file and line information
    let includeFileInfo: Bool

    /// Whether to use os.log (Unified Logging) in addition to print
    let useOSLog: Bool

    /// Categories to enable (nil means all categories)
    let enabledCategories: Set<LogCategory>?

    /// Default development configuration
    static let development = LoggerConfiguration(
        minimumLevel: .debug,
        includeTimestamps: true,
        includeFileInfo: true,
        useOSLog: true,
        enabledCategories: nil
    )

    /// Default production configuration
    static let production = LoggerConfiguration(
        minimumLevel: .warning,
        includeTimestamps: false,
        includeFileInfo: false,
        useOSLog: true,
        enabledCategories: nil
    )

    /// Silent configuration (no logging)
    static let silent = LoggerConfiguration(
        minimumLevel: .error,
        includeTimestamps: false,
        includeFileInfo: false,
        useOSLog: false,
        enabledCategories: Set()
    )
}

// MARK: - Logger

/// Centralized logging utility for the Tasks app
final class Logger: @unchecked Sendable {

    // MARK: - Static Properties

    /// Bundle identifier used as subsystem for os.log
    static let subsystem = Bundle.main.bundleIdentifier ?? "com.orion.tasksapp"

    /// Shared logger instance
    static let shared = Logger()

    /// Date formatter for timestamps
    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()

    // MARK: - Properties

    /// Current configuration
    private var configuration: LoggerConfiguration

    /// Queue for thread-safe logging
    private let queue = DispatchQueue(label: "com.orion.tasksapp.logger", qos: .utility)

    // MARK: - Initialization

    init(configuration: LoggerConfiguration? = nil) {
        #if DEBUG
        self.configuration = configuration ?? .development
        #else
        self.configuration = configuration ?? .production
        #endif
    }

    // MARK: - Configuration

    /// Updates the logger configuration
    func configure(_ configuration: LoggerConfiguration) {
        queue.sync {
            self.configuration = configuration
        }
    }

    /// Sets the minimum log level
    func setMinimumLevel(_ level: LogLevel) {
        queue.sync {
            self.configuration = LoggerConfiguration(
                minimumLevel: level,
                includeTimestamps: configuration.includeTimestamps,
                includeFileInfo: configuration.includeFileInfo,
                useOSLog: configuration.useOSLog,
                enabledCategories: configuration.enabledCategories
            )
        }
    }

    // MARK: - Logging Methods

    /// Logs a debug message
    func debug(
        _ message: @autoclosure () -> String,
        category: LogCategory = .app,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        log(level: .debug, message: message(), category: category, file: file, function: function, line: line)
    }

    /// Logs an info message
    func info(
        _ message: @autoclosure () -> String,
        category: LogCategory = .app,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        log(level: .info, message: message(), category: category, file: file, function: function, line: line)
    }

    /// Logs a warning message
    func warning(
        _ message: @autoclosure () -> String,
        category: LogCategory = .app,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        log(level: .warning, message: message(), category: category, file: file, function: function, line: line)
    }

    /// Logs an error message
    func error(
        _ message: @autoclosure () -> String,
        category: LogCategory = .app,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        log(level: .error, message: message(), category: category, file: file, function: function, line: line)
    }

    /// Logs an error with the associated Error object
    func error(
        _ error: Error,
        message: String? = nil,
        category: LogCategory = .app,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        let errorMessage = message.map { "\($0): \(error.localizedDescription)" } ?? error.localizedDescription
        log(level: .error, message: errorMessage, category: category, file: file, function: function, line: line)
    }

    // MARK: - Private Methods

    private func log(
        level: LogLevel,
        message: String,
        category: LogCategory,
        file: String,
        function: String,
        line: Int
    ) {
        // Check if level meets minimum threshold
        guard level >= configuration.minimumLevel else { return }

        // Check if category is enabled
        if let enabledCategories = configuration.enabledCategories {
            guard enabledCategories.contains(category) else { return }
        }

        // Build log message
        let formattedMessage = formatMessage(
            level: level,
            message: message,
            category: category,
            file: file,
            function: function,
            line: line
        )

        queue.async { [weak self] in
            guard let self = self else { return }

            // Print to console
            #if DEBUG
            print(formattedMessage)
            #endif

            // Log to os.log if enabled
            if self.configuration.useOSLog {
                os_log("%{public}@", log: category.osLog, type: level.osLogType, message)
            }
        }
    }

    private func formatMessage(
        level: LogLevel,
        message: String,
        category: LogCategory,
        file: String,
        function: String,
        line: Int
    ) -> String {
        var components: [String] = []

        // Timestamp
        if configuration.includeTimestamps {
            let timestamp = Self.timestampFormatter.string(from: Date())
            components.append(timestamp)
        }

        // Level prefix
        components.append(level.prefix)

        // Category
        components.append("[\(category.rawValue)]")

        // File info
        if configuration.includeFileInfo {
            let fileName = (file as NSString).lastPathComponent
            components.append("\(fileName):\(line)")
        }

        // Message
        components.append(message)

        return components.joined(separator: " ")
    }
}

// MARK: - Convenience Extensions

extension Logger {

    /// Logs entry into a function (debug level)
    func trace(
        function: String = #function,
        file: String = #file,
        line: Int = #line
    ) {
        debug("Entering \(function)", category: .performance, file: file, function: function, line: line)
    }

    /// Logs a network request
    func logRequest(
        _ method: String,
        url: String,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        debug("\(method) \(url)", category: .network, file: file, function: function, line: line)
    }

    /// Logs a network response
    func logResponse(
        statusCode: Int,
        url: String,
        duration: TimeInterval,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        let durationMs = Int(duration * 1000)
        let level: LogLevel = statusCode >= 400 ? .error : .debug
        log(
            level: level,
            message: "Response \(statusCode) from \(url) (\(durationMs)ms)",
            category: .network,
            file: file,
            function: function,
            line: line
        )
    }

    /// Logs a sync operation
    func logSync(
        operation: String,
        details: String? = nil,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        let message = details.map { "\(operation): \($0)" } ?? operation
        info(message, category: .sync, file: file, function: function, line: line)
    }

    /// Logs a consent event
    func logConsent(
        event: String,
        details: String? = nil,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        let message = details.map { "\(event): \($0)" } ?? event
        info(message, category: .consent, file: file, function: function, line: line)
    }

    /// Logs authentication events
    func logAuth(
        event: String,
        userId: String? = nil,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        let message = userId.map { "\(event) (user: \($0))" } ?? event
        info(message, category: .auth, file: file, function: function, line: line)
    }

    /// Measures and logs execution time of a block
    func measure<T>(
        _ name: String,
        category: LogCategory = .performance,
        block: () throws -> T
    ) rethrows -> T {
        let start = CFAbsoluteTimeGetCurrent()
        let result = try block()
        let duration = CFAbsoluteTimeGetCurrent() - start
        let durationMs = Int(duration * 1000)
        debug("\(name) completed in \(durationMs)ms", category: category)
        return result
    }

    /// Measures and logs execution time of an async block
    func measureAsync<T>(
        _ name: String,
        category: LogCategory = .performance,
        block: () async throws -> T
    ) async rethrows -> T {
        let start = CFAbsoluteTimeGetCurrent()
        let result = try await block()
        let duration = CFAbsoluteTimeGetCurrent() - start
        let durationMs = Int(duration * 1000)
        debug("\(name) completed in \(durationMs)ms", category: category)
        return result
    }
}

// MARK: - Global Convenience Functions

/// Quick debug log
func logDebug(_ message: @autoclosure () -> String, category: LogCategory = .app) {
    Logger.shared.debug(message(), category: category)
}

/// Quick info log
func logInfo(_ message: @autoclosure () -> String, category: LogCategory = .app) {
    Logger.shared.info(message(), category: category)
}

/// Quick warning log
func logWarning(_ message: @autoclosure () -> String, category: LogCategory = .app) {
    Logger.shared.warning(message(), category: category)
}

/// Quick error log
func logError(_ message: @autoclosure () -> String, category: LogCategory = .app) {
    Logger.shared.error(message(), category: category)
}

/// Quick error log with Error object
func logError(_ error: Error, message: String? = nil, category: LogCategory = .app) {
    Logger.shared.error(error, message: message, category: category)
}
