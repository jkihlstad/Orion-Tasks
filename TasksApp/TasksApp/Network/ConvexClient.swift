//
//  ConvexClient.swift
//  TasksApp
//
//  HTTP client for Convex backend
//  Handles requests, authentication, and retry logic
//

import Foundation
import Combine

// MARK: - Convex Configuration

/// Configuration for the Convex client
struct ConvexConfiguration: Sendable {
    /// Base URL for the Convex deployment
    let deploymentURL: URL

    /// Project slug (extracted from deployment URL)
    var projectSlug: String {
        deploymentURL.host?.components(separatedBy: ".").first ?? ""
    }

    /// HTTP functions endpoint
    var httpActionsURL: URL {
        deploymentURL.appendingPathComponent("api")
    }

    /// Convex functions endpoint
    var functionsURL: URL {
        deploymentURL.appendingPathComponent("api/query")
    }

    /// Mutations endpoint
    var mutationsURL: URL {
        deploymentURL.appendingPathComponent("api/mutation")
    }

    /// Actions endpoint
    var actionsURL: URL {
        deploymentURL.appendingPathComponent("api/action")
    }

    /// Request timeout interval
    let timeoutInterval: TimeInterval

    /// Maximum retry attempts
    let maxRetries: Int

    /// Base delay for exponential backoff
    let baseRetryDelay: TimeInterval

    /// Creates a configuration from environment
    static func from(environment: ConvexEnvironment) -> ConvexConfiguration {
        ConvexConfiguration(
            deploymentURL: environment.deploymentURL,
            timeoutInterval: 30,
            maxRetries: 3,
            baseRetryDelay: 1.0
        )
    }

    /// Development configuration
    static let development = ConvexConfiguration(
        deploymentURL: URL(string: "https://dev-your-project.convex.cloud")!,
        timeoutInterval: 30,
        maxRetries: 3,
        baseRetryDelay: 1.0
    )

    /// Production configuration
    static let production = ConvexConfiguration(
        deploymentURL: URL(string: "https://your-project.convex.cloud")!,
        timeoutInterval: 30,
        maxRetries: 3,
        baseRetryDelay: 1.0
    )
}

// MARK: - Convex Environment

/// Convex deployment environments
enum ConvexEnvironment: Sendable {
    case development
    case staging
    case production
    case custom(URL)

    var deploymentURL: URL {
        switch self {
        case .development:
            return URL(string: "https://dev-your-project.convex.cloud")!
        case .staging:
            return URL(string: "https://staging-your-project.convex.cloud")!
        case .production:
            return URL(string: "https://your-project.convex.cloud")!
        case .custom(let url):
            return url
        }
    }
}

// MARK: - Convex Error

/// Errors from Convex operations
enum ConvexError: LocalizedError, Equatable {
    case networkError(String)
    case authenticationRequired
    case authenticationFailed(String)
    case invalidRequest(String)
    case serverError(Int, String)
    case decodingError(String)
    case rateLimited(retryAfter: TimeInterval)
    case functionError(String, String) // function name, error message
    case timeout
    case cancelled
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .networkError(let message):
            return "Network error: \(message)"
        case .authenticationRequired:
            return "Authentication required"
        case .authenticationFailed(let message):
            return "Authentication failed: \(message)"
        case .invalidRequest(let message):
            return "Invalid request: \(message)"
        case .serverError(let code, let message):
            return "Server error (\(code)): \(message)"
        case .decodingError(let message):
            return "Failed to decode response: \(message)"
        case .rateLimited(let retryAfter):
            return "Rate limited. Retry after \(Int(retryAfter)) seconds"
        case .functionError(let function, let message):
            return "Function '\(function)' error: \(message)"
        case .timeout:
            return "Request timed out"
        case .cancelled:
            return "Request was cancelled"
        case .unknown(let message):
            return message
        }
    }

    static func == (lhs: ConvexError, rhs: ConvexError) -> Bool {
        lhs.errorDescription == rhs.errorDescription
    }
}

// MARK: - Convex Response

/// Generic response wrapper from Convex
struct ConvexResponse<T: Decodable>: Decodable {
    let status: String?
    let value: T?
    let errorMessage: String?
    let errorData: [String: String]?

    var isSuccess: Bool {
        status == "success" || (errorMessage == nil && value != nil)
    }

    enum CodingKeys: String, CodingKey {
        case status
        case value
        case errorMessage
        case errorData
    }
}

// MARK: - Auth Token Provider Protocol

/// Protocol for providing authentication tokens
protocol AuthTokenProvider: AnyObject, Sendable {
    func getToken() async throws -> String?
    func refreshToken() async throws -> String
    var isAuthenticated: Bool { get }
}

// MARK: - Convex Client

/// HTTP client for interacting with Convex backend
final class ConvexClient: @unchecked Sendable {

    // MARK: - Properties

    private let configuration: ConvexConfiguration
    private let session: URLSession
    private weak var authProvider: AuthTokenProvider?

    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    // Request tracking
    private var activeRequests: Set<UUID> = []
    private let requestsLock = NSLock()

    // Combine support
    private let errorSubject = PassthroughSubject<ConvexError, Never>()
    var errors: AnyPublisher<ConvexError, Never> {
        errorSubject.eraseToAnyPublisher()
    }

    // MARK: - Initialization

    init(
        configuration: ConvexConfiguration,
        authProvider: AuthTokenProvider? = nil
    ) {
        self.configuration = configuration
        self.authProvider = authProvider

        // Configure URL session
        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.timeoutIntervalForRequest = configuration.timeoutInterval
        sessionConfig.timeoutIntervalForResource = configuration.timeoutInterval * 2
        sessionConfig.waitsForConnectivity = true
        sessionConfig.httpAdditionalHeaders = [
            "Content-Type": "application/json",
            "Accept": "application/json",
            "User-Agent": "TasksApp-iOS/1.0"
        ]

        self.session = URLSession(configuration: sessionConfig)

        // Configure JSON coding
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            if let timestamp = try? container.decode(Double.self) {
                return Date(timeIntervalSince1970: timestamp / 1000)
            }
            let dateString = try container.decode(String.self)
            if let date = ISO8601DateFormatter().date(from: dateString) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid date format"
            )
        }

        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(Int64(date.timeIntervalSince1970 * 1000))
        }
    }

    /// Sets the auth provider
    func setAuthProvider(_ provider: AuthTokenProvider) {
        self.authProvider = provider
    }

    // MARK: - Query Methods

    /// Executes a Convex query function
    func query<T: Decodable>(
        _ functionName: String,
        args: [String: Any] = [:],
        responseType: T.Type
    ) async throws -> T {
        let url = configuration.functionsURL
        let body: [String: Any] = [
            "path": functionName,
            "args": args
        ]

        return try await executeRequest(
            url: url,
            method: "POST",
            body: body,
            responseType: responseType,
            functionName: functionName
        )
    }

    /// Executes a Convex query function returning an array
    func queryArray<T: Decodable>(
        _ functionName: String,
        args: [String: Any] = [:],
        elementType: T.Type
    ) async throws -> [T] {
        return try await query(functionName, args: args, responseType: [T].self)
    }

    /// Executes a Convex query function returning optional result
    func queryOptional<T: Decodable>(
        _ functionName: String,
        args: [String: Any] = [:],
        responseType: T.Type
    ) async throws -> T? {
        do {
            return try await query(functionName, args: args, responseType: responseType)
        } catch ConvexError.functionError(_, let message) where message.contains("null") {
            return nil
        }
    }

    // MARK: - Mutation Methods

    /// Executes a Convex mutation function
    @discardableResult
    func mutation<T: Decodable>(
        _ functionName: String,
        args: [String: Any] = [:],
        responseType: T.Type
    ) async throws -> T {
        let url = configuration.mutationsURL
        let body: [String: Any] = [
            "path": functionName,
            "args": args
        ]

        return try await executeRequest(
            url: url,
            method: "POST",
            body: body,
            responseType: responseType,
            functionName: functionName
        )
    }

    /// Executes a Convex mutation that doesn't return a value
    func mutation(
        _ functionName: String,
        args: [String: Any] = [:]
    ) async throws {
        let _: EmptyResponse = try await mutation(functionName, args: args, responseType: EmptyResponse.self)
    }

    // MARK: - Action Methods

    /// Executes a Convex action function
    func action<T: Decodable>(
        _ functionName: String,
        args: [String: Any] = [:],
        responseType: T.Type
    ) async throws -> T {
        let url = configuration.actionsURL
        let body: [String: Any] = [
            "path": functionName,
            "args": args
        ]

        return try await executeRequest(
            url: url,
            method: "POST",
            body: body,
            responseType: responseType,
            functionName: functionName
        )
    }

    // MARK: - HTTP Actions

    /// Executes an HTTP action (custom endpoint)
    func httpAction<T: Decodable>(
        path: String,
        method: String = "POST",
        body: [String: Any]? = nil,
        responseType: T.Type
    ) async throws -> T {
        let url = configuration.httpActionsURL.appendingPathComponent(path)

        return try await executeRequest(
            url: url,
            method: method,
            body: body,
            responseType: responseType,
            functionName: path
        )
    }

    /// Executes an HTTP GET action
    func httpGet<T: Decodable>(
        path: String,
        queryParams: [String: String] = [:],
        responseType: T.Type
    ) async throws -> T {
        var urlComponents = URLComponents(
            url: configuration.httpActionsURL.appendingPathComponent(path),
            resolvingAgainstBaseURL: false
        )!

        if !queryParams.isEmpty {
            urlComponents.queryItems = queryParams.map { URLQueryItem(name: $0.key, value: $0.value) }
        }

        guard let url = urlComponents.url else {
            throw ConvexError.invalidRequest("Invalid URL")
        }

        return try await executeRequest(
            url: url,
            method: "GET",
            body: nil,
            responseType: responseType,
            functionName: path
        )
    }

    // MARK: - Request Execution

    private func executeRequest<T: Decodable>(
        url: URL,
        method: String,
        body: [String: Any]?,
        responseType: T.Type,
        functionName: String,
        retryCount: Int = 0
    ) async throws -> T {
        let requestId = UUID()

        requestsLock.lock()
        activeRequests.insert(requestId)
        requestsLock.unlock()

        defer {
            requestsLock.lock()
            activeRequests.remove(requestId)
            requestsLock.unlock()
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Add auth token if available
        if let token = try await authProvider?.getToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        // Encode body if present
        if let body = body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        do {
            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw ConvexError.unknown("Invalid response type")
            }

            // Handle response based on status code
            switch httpResponse.statusCode {
            case 200..<300:
                return try decodeResponse(data, type: responseType, functionName: functionName)

            case 401:
                // Try to refresh token and retry
                if retryCount == 0, let authProvider = authProvider {
                    _ = try await authProvider.refreshToken()
                    return try await executeRequest(
                        url: url,
                        method: method,
                        body: body,
                        responseType: responseType,
                        functionName: functionName,
                        retryCount: retryCount + 1
                    )
                }
                throw ConvexError.authenticationRequired

            case 429:
                let retryAfter = parseRetryAfter(from: httpResponse)
                throw ConvexError.rateLimited(retryAfter: retryAfter)

            case 400..<500:
                let errorMessage = parseErrorMessage(from: data)
                throw ConvexError.invalidRequest(errorMessage)

            case 500..<600:
                let errorMessage = parseErrorMessage(from: data)
                throw ConvexError.serverError(httpResponse.statusCode, errorMessage)

            default:
                throw ConvexError.unknown("Unexpected status code: \(httpResponse.statusCode)")
            }

        } catch let error as ConvexError {
            errorSubject.send(error)

            // Retry with exponential backoff for certain errors
            if shouldRetry(error: error, retryCount: retryCount) {
                let delay = calculateRetryDelay(retryCount: retryCount)
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                return try await executeRequest(
                    url: url,
                    method: method,
                    body: body,
                    responseType: responseType,
                    functionName: functionName,
                    retryCount: retryCount + 1
                )
            }

            throw error

        } catch is CancellationError {
            throw ConvexError.cancelled

        } catch let error as URLError {
            let convexError: ConvexError
            switch error.code {
            case .timedOut:
                convexError = .timeout
            case .notConnectedToInternet, .networkConnectionLost:
                convexError = .networkError("No internet connection")
            case .cancelled:
                convexError = .cancelled
            default:
                convexError = .networkError(error.localizedDescription)
            }

            errorSubject.send(convexError)

            if shouldRetry(error: convexError, retryCount: retryCount) {
                let delay = calculateRetryDelay(retryCount: retryCount)
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                return try await executeRequest(
                    url: url,
                    method: method,
                    body: body,
                    responseType: responseType,
                    functionName: functionName,
                    retryCount: retryCount + 1
                )
            }

            throw convexError

        } catch {
            let convexError = ConvexError.unknown(error.localizedDescription)
            errorSubject.send(convexError)
            throw convexError
        }
    }

    // MARK: - Response Handling

    private func decodeResponse<T: Decodable>(
        _ data: Data,
        type: T.Type,
        functionName: String
    ) throws -> T {
        // First try to decode as a Convex response wrapper
        if let convexResponse = try? decoder.decode(ConvexResponse<T>.self, from: data) {
            if let error = convexResponse.errorMessage {
                throw ConvexError.functionError(functionName, error)
            }
            if let value = convexResponse.value {
                return value
            }
        }

        // Try direct decoding
        do {
            return try decoder.decode(type, from: data)
        } catch {
            // Provide helpful error message
            let dataString = String(data: data, encoding: .utf8) ?? "Unable to parse response"
            throw ConvexError.decodingError(
                "Failed to decode \(type): \(error.localizedDescription). Response: \(dataString.prefix(500))"
            )
        }
    }

    private func parseErrorMessage(from data: Data) -> String {
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return json["message"] as? String
                ?? json["error"] as? String
                ?? json["errorMessage"] as? String
                ?? "Unknown error"
        }
        return String(data: data, encoding: .utf8) ?? "Unknown error"
    }

    private func parseRetryAfter(from response: HTTPURLResponse) -> TimeInterval {
        if let retryAfterString = response.value(forHTTPHeaderField: "Retry-After"),
           let retryAfter = Double(retryAfterString) {
            return retryAfter
        }
        return 60 // Default to 60 seconds
    }

    // MARK: - Retry Logic

    private func shouldRetry(error: ConvexError, retryCount: Int) -> Bool {
        guard retryCount < configuration.maxRetries else {
            return false
        }

        switch error {
        case .networkError, .timeout, .serverError(500..<600, _):
            return true
        case .rateLimited:
            return true
        default:
            return false
        }
    }

    private func calculateRetryDelay(retryCount: Int) -> TimeInterval {
        let delay = configuration.baseRetryDelay * pow(2.0, Double(retryCount))
        // Add jitter (0-25% of delay)
        let jitter = delay * Double.random(in: 0...0.25)
        return min(delay + jitter, 60) // Cap at 60 seconds
    }

    // MARK: - Cancellation

    /// Cancels all active requests
    func cancelAllRequests() {
        session.getAllTasks { tasks in
            tasks.forEach { $0.cancel() }
        }
    }
}

// MARK: - Empty Response

/// Empty response type for mutations that don't return values
struct EmptyResponse: Decodable {
    init() {}
    init(from decoder: Decoder) throws {}
}

// MARK: - Batch Support

extension ConvexClient {

    /// Executes multiple mutations in a batch
    func batchMutations(_ mutations: [(function: String, args: [String: Any])]) async throws {
        for mutation in mutations {
            try await self.mutation(mutation.function, args: mutation.args)
        }
    }

    /// Executes multiple queries in parallel
    func parallelQueries<T: Decodable>(
        _ queries: [(function: String, args: [String: Any])],
        responseType: T.Type
    ) async throws -> [T] {
        try await withThrowingTaskGroup(of: (Int, T).self) { group in
            for (index, query) in queries.enumerated() {
                group.addTask {
                    let result: T = try await self.query(
                        query.function,
                        args: query.args,
                        responseType: responseType
                    )
                    return (index, result)
                }
            }

            var results: [(Int, T)] = []
            for try await result in group {
                results.append(result)
            }

            return results.sorted { $0.0 < $1.0 }.map { $0.1 }
        }
    }
}
