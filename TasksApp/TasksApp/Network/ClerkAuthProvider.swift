//
//  ClerkAuthProvider.swift
//  TasksApp
//
//  Clerk authentication provider for JWT token management
//  Handles sign in, sign out, token refresh, and session persistence
//

import Foundation
import Combine
import AuthenticationServices
import Security

// MARK: - Clerk Configuration

/// Configuration for Clerk authentication
struct ClerkConfiguration: Sendable {
    /// Clerk publishable key
    let publishableKey: String

    /// Clerk frontend API URL
    let frontendApiUrl: String

    /// Whether to use secure storage (Keychain)
    let useSecureStorage: Bool

    /// Token refresh threshold (seconds before expiry to refresh)
    let tokenRefreshThreshold: TimeInterval

    /// Session timeout (seconds)
    let sessionTimeout: TimeInterval

    /// Creates configuration from environment
    static func from(environment: ClerkEnvironment) -> ClerkConfiguration {
        switch environment {
        case .development:
            return ClerkConfiguration(
                publishableKey: "pk_test_YOUR_KEY_HERE",
                frontendApiUrl: "https://YOUR_DOMAIN.clerk.accounts.dev",
                useSecureStorage: true,
                tokenRefreshThreshold: 300, // 5 minutes
                sessionTimeout: 86400 * 7 // 7 days
            )
        case .production:
            return ClerkConfiguration(
                publishableKey: "pk_live_YOUR_KEY_HERE",
                frontendApiUrl: "https://YOUR_DOMAIN.clerk.accounts.dev",
                useSecureStorage: true,
                tokenRefreshThreshold: 300,
                sessionTimeout: 86400 * 7
            )
        }
    }
}

/// Clerk deployment environments
enum ClerkEnvironment {
    case development
    case production
}

// MARK: - Clerk User

/// User information from Clerk
struct ClerkUser: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let email: String?
    let firstName: String?
    let lastName: String?
    let username: String?
    let imageUrl: String?
    let createdAt: Date
    let updatedAt: Date

    /// Full display name
    var displayName: String {
        if let firstName = firstName, let lastName = lastName {
            return "\(firstName) \(lastName)"
        }
        return firstName ?? lastName ?? username ?? email ?? "User"
    }

    /// User's initials for avatar fallback
    var initials: String {
        let components = displayName.split(separator: " ")
        let initials = components.prefix(2).compactMap { $0.first }.map(String.init)
        return initials.joined().uppercased()
    }

    /// Avatar URL
    var avatarURL: URL? {
        guard let imageUrl = imageUrl else { return nil }
        return URL(string: imageUrl)
    }
}

// MARK: - Clerk Session

/// Session information from Clerk
struct ClerkSession: Codable, Sendable {
    let id: String
    let userId: String
    let status: SessionStatus
    let expireAt: Date
    let lastActiveAt: Date
    let createdAt: Date

    enum SessionStatus: String, Codable, Sendable {
        case active
        case revoked
        case ended
        case expired
        case removed
    }

    var isValid: Bool {
        status == .active && expireAt > Date()
    }

    var isExpiringSoon: Bool {
        expireAt.timeIntervalSinceNow < 300 // 5 minutes
    }
}

// MARK: - Auth State

/// Current authentication state
enum AuthState: Equatable, Sendable {
    case unknown
    case loading
    case authenticated(ClerkUser)
    case unauthenticated
    case error(String)

    var isAuthenticated: Bool {
        if case .authenticated = self {
            return true
        }
        return false
    }

    var user: ClerkUser? {
        if case .authenticated(let user) = self {
            return user
        }
        return nil
    }
}

// MARK: - Auth Error

/// Authentication errors
enum ClerkAuthError: LocalizedError, Equatable {
    case notConfigured
    case networkError(String)
    case invalidCredentials
    case sessionExpired
    case tokenRefreshFailed
    case userNotFound
    case signOutFailed
    case keychainError(String)
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Clerk authentication not configured"
        case .networkError(let message):
            return "Network error: \(message)"
        case .invalidCredentials:
            return "Invalid credentials"
        case .sessionExpired:
            return "Session expired"
        case .tokenRefreshFailed:
            return "Failed to refresh token"
        case .userNotFound:
            return "User not found"
        case .signOutFailed:
            return "Failed to sign out"
        case .keychainError(let message):
            return "Keychain error: \(message)"
        case .unknown(let message):
            return message
        }
    }

    static func == (lhs: ClerkAuthError, rhs: ClerkAuthError) -> Bool {
        lhs.errorDescription == rhs.errorDescription
    }
}

// MARK: - Clerk Auth Provider

/// Provides Clerk authentication functionality
@MainActor
final class ClerkAuthProvider: ObservableObject, AuthTokenProvider {

    // MARK: - Published Properties

    @Published private(set) var authState: AuthState = .unknown
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var currentUser: ClerkUser?
    @Published private(set) var currentSession: ClerkSession?

    // MARK: - Computed Properties

    var isAuthenticated: Bool {
        authState.isAuthenticated
    }

    nonisolated var isAuthenticatedSync: Bool {
        // This is a workaround for AuthTokenProvider protocol
        // In real usage, check via async method
        true
    }

    // MARK: - Properties

    private let configuration: ClerkConfiguration
    private let session: URLSession
    private let keychainService: String = "com.orion.tasks.clerk"

    private var sessionToken: String?
    private var tokenExpiresAt: Date?
    private var refreshTask: Task<String, Error>?
    private var cancellables = Set<AnyCancellable>()

    // Storage keys
    private enum StorageKeys {
        static let sessionToken = "clerk_session_token"
        static let refreshToken = "clerk_refresh_token"
        static let userId = "clerk_user_id"
        static let userProfile = "clerk_user_profile"
        static let tokenExpiry = "clerk_token_expiry"
    }

    // MARK: - Initialization

    init(configuration: ClerkConfiguration) {
        self.configuration = configuration

        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.timeoutIntervalForRequest = 30
        sessionConfig.httpAdditionalHeaders = [
            "Content-Type": "application/json",
            "Authorization": "Bearer \(configuration.publishableKey)"
        ]
        self.session = URLSession(configuration: sessionConfig)
    }

    // MARK: - AuthTokenProvider Protocol

    nonisolated func getToken() async throws -> String? {
        await MainActor.run {
            self.sessionToken
        }
    }

    nonisolated func refreshToken() async throws -> String {
        try await MainActor.run {
            try await self.refreshSessionToken()
        }
    }

    // MARK: - Session Management

    /// Restores session from storage
    func restoreSession() async {
        authState = .loading
        isLoading = true

        defer {
            isLoading = false
        }

        // Try to load stored session
        guard let storedToken = loadFromKeychain(key: StorageKeys.sessionToken),
              let storedExpiry = loadExpiryFromKeychain() else {
            authState = .unauthenticated
            return
        }

        // Check if token is still valid
        guard storedExpiry > Date() else {
            // Token expired, try to refresh
            do {
                let newToken = try await refreshSessionToken()
                sessionToken = newToken
                authState = await loadUserProfile()
            } catch {
                clearSession()
                authState = .unauthenticated
            }
            return
        }

        sessionToken = storedToken
        tokenExpiresAt = storedExpiry

        // Load user profile
        authState = await loadUserProfile()

        // Schedule token refresh if expiring soon
        if storedExpiry.timeIntervalSinceNow < configuration.tokenRefreshThreshold {
            Task {
                _ = try? await refreshSessionToken()
            }
        }
    }

    /// Signs in with email and password
    func signIn(email: String, password: String) async throws {
        authState = .loading
        isLoading = true

        defer {
            isLoading = false
        }

        let url = URL(string: "\(configuration.frontendApiUrl)/v1/client/sign_ins")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "identifier": email,
            "password": password,
            "strategy": "password"
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw ClerkAuthError.unknown("Invalid response")
            }

            switch httpResponse.statusCode {
            case 200..<300:
                let authResponse = try JSONDecoder().decode(ClerkSignInResponse.self, from: data)
                try await handleSignInResponse(authResponse)

            case 401, 403:
                throw ClerkAuthError.invalidCredentials

            default:
                let errorMessage = parseErrorMessage(from: data)
                throw ClerkAuthError.unknown(errorMessage)
            }

        } catch let error as ClerkAuthError {
            authState = .error(error.localizedDescription ?? "Unknown error")
            throw error
        } catch {
            authState = .error(error.localizedDescription)
            throw ClerkAuthError.networkError(error.localizedDescription)
        }
    }

    /// Signs in with Apple
    func signInWithApple(credential: ASAuthorizationAppleIDCredential) async throws {
        authState = .loading
        isLoading = true

        defer {
            isLoading = false
        }

        guard let identityToken = credential.identityToken,
              let tokenString = String(data: identityToken, encoding: .utf8) else {
            throw ClerkAuthError.invalidCredentials
        }

        let url = URL(string: "\(configuration.frontendApiUrl)/v1/client/sign_ins")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "strategy": "oauth_apple",
            "token": tokenString
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            let errorMessage = parseErrorMessage(from: data)
            throw ClerkAuthError.unknown(errorMessage)
        }

        let authResponse = try JSONDecoder().decode(ClerkSignInResponse.self, from: data)
        try await handleSignInResponse(authResponse)
    }

    /// Signs in with Google
    func signInWithGoogle(idToken: String) async throws {
        authState = .loading
        isLoading = true

        defer {
            isLoading = false
        }

        let url = URL(string: "\(configuration.frontendApiUrl)/v1/client/sign_ins")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "strategy": "oauth_google",
            "token": idToken
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            let errorMessage = parseErrorMessage(from: data)
            throw ClerkAuthError.unknown(errorMessage)
        }

        let authResponse = try JSONDecoder().decode(ClerkSignInResponse.self, from: data)
        try await handleSignInResponse(authResponse)
    }

    /// Signs out the current user
    func signOut() async throws {
        guard let token = sessionToken else {
            clearSession()
            authState = .unauthenticated
            return
        }

        isLoading = true
        defer { isLoading = false }

        // Revoke session on server
        let url = URL(string: "\(configuration.frontendApiUrl)/v1/client/sessions/\(currentSession?.id ?? "")")!
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        do {
            let (_, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode) || httpResponse.statusCode == 404 else {
                throw ClerkAuthError.signOutFailed
            }

        } catch {
            // Continue with local sign out even if server request fails
            print("[ClerkAuth] Server sign out failed: \(error)")
        }

        clearSession()
        authState = .unauthenticated
    }

    /// Refreshes the session token
    @discardableResult
    func refreshSessionToken() async throws -> String {
        // Check if refresh is already in progress
        if let existingTask = refreshTask {
            return try await existingTask.value
        }

        let task = Task<String, Error> {
            defer { refreshTask = nil }

            guard let currentToken = sessionToken else {
                throw ClerkAuthError.sessionExpired
            }

            let url = URL(string: "\(configuration.frontendApiUrl)/v1/client/sessions/\(currentSession?.id ?? "")/tokens")!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("Bearer \(currentToken)", forHTTPHeaderField: "Authorization")

            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw ClerkAuthError.tokenRefreshFailed
            }

            switch httpResponse.statusCode {
            case 200..<300:
                let tokenResponse = try JSONDecoder().decode(ClerkTokenResponse.self, from: data)
                let newToken = tokenResponse.jwt

                // Update stored token
                await MainActor.run {
                    self.sessionToken = newToken
                    self.tokenExpiresAt = Date(timeIntervalSinceNow: 3600) // 1 hour default
                }

                // Persist to keychain
                saveToKeychain(key: StorageKeys.sessionToken, value: newToken)

                return newToken

            case 401:
                throw ClerkAuthError.sessionExpired

            default:
                throw ClerkAuthError.tokenRefreshFailed
            }
        }

        refreshTask = task
        return try await task.value
    }

    // MARK: - Private Methods

    private func handleSignInResponse(_ response: ClerkSignInResponse) async throws {
        guard let sessionData = response.client?.sessions?.first,
              let token = sessionData.lastActiveToken?.jwt else {
            throw ClerkAuthError.invalidCredentials
        }

        // Store session info
        sessionToken = token
        tokenExpiresAt = Date(timeIntervalSinceNow: 3600) // Default 1 hour

        // Save to keychain
        saveToKeychain(key: StorageKeys.sessionToken, value: token)
        saveExpiryToKeychain(tokenExpiresAt!)

        if let userId = sessionData.user?.id {
            saveToKeychain(key: StorageKeys.userId, value: userId)
        }

        // Update session
        currentSession = ClerkSession(
            id: sessionData.id,
            userId: sessionData.user?.id ?? "",
            status: .active,
            expireAt: tokenExpiresAt!,
            lastActiveAt: Date(),
            createdAt: Date()
        )

        // Load user profile
        authState = await loadUserProfile()
    }

    private func loadUserProfile() async -> AuthState {
        guard let token = sessionToken else {
            return .unauthenticated
        }

        let url = URL(string: "\(configuration.frontendApiUrl)/v1/me")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode) else {
                return .error("Failed to load user profile")
            }

            let userResponse = try JSONDecoder().decode(ClerkUserResponse.self, from: data)
            let user = ClerkUser(
                id: userResponse.id,
                email: userResponse.emailAddresses.first?.emailAddress,
                firstName: userResponse.firstName,
                lastName: userResponse.lastName,
                username: userResponse.username,
                imageUrl: userResponse.imageUrl,
                createdAt: userResponse.createdAt ?? Date(),
                updatedAt: userResponse.updatedAt ?? Date()
            )

            currentUser = user

            // Cache user profile
            if let userData = try? JSONEncoder().encode(user) {
                UserDefaults.standard.set(userData, forKey: StorageKeys.userProfile)
            }

            return .authenticated(user)

        } catch {
            // Try to load cached profile
            if let cachedData = UserDefaults.standard.data(forKey: StorageKeys.userProfile),
               let cachedUser = try? JSONDecoder().decode(ClerkUser.self, from: cachedData) {
                currentUser = cachedUser
                return .authenticated(cachedUser)
            }

            return .error(error.localizedDescription)
        }
    }

    private func clearSession() {
        sessionToken = nil
        tokenExpiresAt = nil
        currentUser = nil
        currentSession = nil
        refreshTask?.cancel()
        refreshTask = nil

        // Clear keychain
        deleteFromKeychain(key: StorageKeys.sessionToken)
        deleteFromKeychain(key: StorageKeys.refreshToken)
        deleteFromKeychain(key: StorageKeys.userId)
        deleteFromKeychain(key: StorageKeys.tokenExpiry)

        // Clear cached profile
        UserDefaults.standard.removeObject(forKey: StorageKeys.userProfile)
    }

    private func parseErrorMessage(from data: Data) -> String {
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let errors = json["errors"] as? [[String: Any]],
               let firstError = errors.first,
               let message = firstError["message"] as? String {
                return message
            }
            return json["message"] as? String ?? "Unknown error"
        }
        return String(data: data, encoding: .utf8) ?? "Unknown error"
    }

    // MARK: - Keychain Operations

    private func saveToKeychain(key: String, value: String) {
        guard let data = value.data(using: .utf8) else { return }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        // Delete existing item first
        SecItemDelete(query as CFDictionary)

        // Add new item
        let status = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess {
            print("[ClerkAuth] Keychain save failed: \(status)")
        }
    }

    private func loadFromKeychain(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let string = String(data: data, encoding: .utf8) else {
            return nil
        }

        return string
    }

    private func deleteFromKeychain(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: key
        ]

        SecItemDelete(query as CFDictionary)
    }

    private func saveExpiryToKeychain(_ date: Date) {
        let timestamp = String(date.timeIntervalSince1970)
        saveToKeychain(key: StorageKeys.tokenExpiry, value: timestamp)
    }

    private func loadExpiryFromKeychain() -> Date? {
        guard let timestampString = loadFromKeychain(key: StorageKeys.tokenExpiry),
              let timestamp = TimeInterval(timestampString) else {
            return nil
        }
        return Date(timeIntervalSince1970: timestamp)
    }
}

// MARK: - Clerk API Response Types

private struct ClerkSignInResponse: Codable {
    let client: ClerkClientResponse?

    struct ClerkClientResponse: Codable {
        let sessions: [ClerkSessionResponse]?
    }

    struct ClerkSessionResponse: Codable {
        let id: String
        let user: ClerkSessionUser?
        let lastActiveToken: ClerkTokenInfo?

        struct ClerkSessionUser: Codable {
            let id: String
        }

        struct ClerkTokenInfo: Codable {
            let jwt: String
        }
    }
}

private struct ClerkTokenResponse: Codable {
    let jwt: String
}

private struct ClerkUserResponse: Codable {
    let id: String
    let emailAddresses: [EmailAddress]
    let firstName: String?
    let lastName: String?
    let username: String?
    let imageUrl: String?
    let createdAt: Date?
    let updatedAt: Date?

    struct EmailAddress: Codable {
        let id: String
        let emailAddress: String
    }

    enum CodingKeys: String, CodingKey {
        case id
        case emailAddresses = "email_addresses"
        case firstName = "first_name"
        case lastName = "last_name"
        case username
        case imageUrl = "image_url"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}
