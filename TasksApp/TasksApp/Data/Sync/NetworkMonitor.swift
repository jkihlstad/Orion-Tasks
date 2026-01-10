//
//  NetworkMonitor.swift
//  TasksApp
//
//  Network connectivity monitoring using NWPathMonitor
//  Provides reactive updates on connection state and type
//

import Foundation
import Network
import Combine

// MARK: - Connection Type

/// Represents the type of network connection
enum ConnectionType: String, Sendable {
    case wifi = "wifi"
    case cellular = "cellular"
    case wiredEthernet = "ethernet"
    case loopback = "loopback"
    case other = "other"
    case none = "none"

    /// Whether this connection type is considered expensive (data usage)
    var isExpensive: Bool {
        switch self {
        case .cellular:
            return true
        case .wifi, .wiredEthernet, .loopback, .other, .none:
            return false
        }
    }

    /// Human-readable description
    var displayName: String {
        switch self {
        case .wifi: return "Wi-Fi"
        case .cellular: return "Cellular"
        case .wiredEthernet: return "Ethernet"
        case .loopback: return "Local"
        case .other: return "Other"
        case .none: return "No Connection"
        }
    }
}

// MARK: - Network Status

/// Comprehensive network status information
struct NetworkStatus: Equatable, Sendable {
    /// Whether the network is connected
    let isConnected: Bool

    /// The type of connection
    let connectionType: ConnectionType

    /// Whether the connection is expensive (e.g., cellular)
    let isExpensive: Bool

    /// Whether the connection is constrained (e.g., Low Data Mode)
    let isConstrained: Bool

    /// Whether DNS is available
    let isDNSAvailable: Bool

    /// Timestamp when this status was captured
    let timestamp: Date

    /// Default disconnected status
    static let disconnected = NetworkStatus(
        isConnected: false,
        connectionType: .none,
        isExpensive: false,
        isConstrained: false,
        isDNSAvailable: false,
        timestamp: Date()
    )

    /// Whether sync should proceed based on current conditions
    var shouldSync: Bool {
        isConnected && !isConstrained
    }

    /// Whether large uploads should proceed (avoid on expensive connections)
    var shouldUploadLargeFiles: Bool {
        isConnected && !isExpensive && !isConstrained
    }
}

// MARK: - Network Monitor

/// Monitors network connectivity using NWPathMonitor
/// Thread-safe wrapper providing Combine publishers for reactive updates
final class NetworkStatusMonitor: ObservableObject, @unchecked Sendable {

    // MARK: - Published Properties

    /// Whether the network is currently connected
    @Published private(set) var isConnected: Bool = false

    /// The current connection type
    @Published private(set) var connectionType: ConnectionType = .none

    /// Whether the current connection is expensive (cellular)
    @Published private(set) var isExpensive: Bool = false

    /// Whether the connection is constrained (Low Data Mode)
    @Published private(set) var isConstrained: Bool = false

    /// Comprehensive network status
    @Published private(set) var status: NetworkStatus = .disconnected

    // MARK: - Combine Publishers

    /// Publisher that emits when connectivity changes
    var connectivityChanged: AnyPublisher<Bool, Never> {
        $isConnected
            .removeDuplicates()
            .eraseToAnyPublisher()
    }

    /// Publisher that emits when the connection type changes
    var connectionTypeChanged: AnyPublisher<ConnectionType, Never> {
        $connectionType
            .removeDuplicates()
            .eraseToAnyPublisher()
    }

    /// Publisher that emits comprehensive status updates
    var statusChanged: AnyPublisher<NetworkStatus, Never> {
        $status
            .removeDuplicates()
            .eraseToAnyPublisher()
    }

    /// Publisher that emits when connection becomes available
    var connectionBecameAvailable: AnyPublisher<Void, Never> {
        $isConnected
            .removeDuplicates()
            .filter { $0 }
            .map { _ in () }
            .eraseToAnyPublisher()
    }

    /// Publisher that emits when connection is lost
    var connectionLost: AnyPublisher<Void, Never> {
        $isConnected
            .removeDuplicates()
            .filter { !$0 }
            .dropFirst() // Ignore initial false value
            .map { _ in () }
            .eraseToAnyPublisher()
    }

    // MARK: - Private Properties

    private let monitor: NWPathMonitor
    private let monitorQueue: DispatchQueue
    private var isMonitoring: Bool = false
    private let lock = NSLock()

    // MARK: - Initialization

    /// Creates a new network monitor
    /// - Parameter requiredInterfaceType: Optional interface type to monitor (nil monitors all)
    init(requiredInterfaceType: NWInterface.InterfaceType? = nil) {
        if let interfaceType = requiredInterfaceType {
            self.monitor = NWPathMonitor(requiredInterfaceType: interfaceType)
        } else {
            self.monitor = NWPathMonitor()
        }

        self.monitorQueue = DispatchQueue(
            label: "com.orion.tasks.networkmonitor",
            qos: .utility
        )
    }

    deinit {
        stop()
    }

    // MARK: - Public Methods

    /// Starts monitoring network connectivity
    func start() {
        lock.lock()
        defer { lock.unlock() }

        guard !isMonitoring else { return }

        monitor.pathUpdateHandler = { [weak self] path in
            self?.handlePathUpdate(path)
        }

        monitor.start(queue: monitorQueue)
        isMonitoring = true
    }

    /// Stops monitoring network connectivity
    func stop() {
        lock.lock()
        defer { lock.unlock() }

        guard isMonitoring else { return }

        monitor.cancel()
        isMonitoring = false
    }

    /// Forces an immediate status check
    func checkConnectivity() -> NetworkStatus {
        let path = monitor.currentPath
        return createStatus(from: path)
    }

    /// Waits for network connectivity with timeout
    /// - Parameter timeout: Maximum time to wait
    /// - Returns: True if connected within timeout, false otherwise
    func waitForConnectivity(timeout: TimeInterval = 30) async -> Bool {
        guard !isConnected else { return true }

        return await withCheckedContinuation { continuation in
            var cancellable: AnyCancellable?
            var timeoutTask: Task<Void, Never>?

            // Set up timeout
            timeoutTask = Task {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                cancellable?.cancel()
                continuation.resume(returning: false)
            }

            // Listen for connectivity
            cancellable = connectionBecameAvailable
                .first()
                .sink { _ in
                    timeoutTask?.cancel()
                    continuation.resume(returning: true)
                }
        }
    }

    // MARK: - Private Methods

    private func handlePathUpdate(_ path: NWPath) {
        let newStatus = createStatus(from: path)

        DispatchQueue.main.async { [weak self] in
            self?.updatePublishedProperties(with: newStatus)
        }
    }

    private func createStatus(from path: NWPath) -> NetworkStatus {
        let isConnected = path.status == .satisfied
        let connectionType = determineConnectionType(from: path)

        return NetworkStatus(
            isConnected: isConnected,
            connectionType: connectionType,
            isExpensive: path.isExpensive,
            isConstrained: path.isConstrained,
            isDNSAvailable: path.status == .satisfied,
            timestamp: Date()
        )
    }

    private func determineConnectionType(from path: NWPath) -> ConnectionType {
        guard path.status == .satisfied else {
            return .none
        }

        if path.usesInterfaceType(.wifi) {
            return .wifi
        } else if path.usesInterfaceType(.cellular) {
            return .cellular
        } else if path.usesInterfaceType(.wiredEthernet) {
            return .wiredEthernet
        } else if path.usesInterfaceType(.loopback) {
            return .loopback
        } else {
            return .other
        }
    }

    private func updatePublishedProperties(with status: NetworkStatus) {
        self.isConnected = status.isConnected
        self.connectionType = status.connectionType
        self.isExpensive = status.isExpensive
        self.isConstrained = status.isConstrained
        self.status = status
    }
}

// MARK: - Network Reachability Checker

/// Utility for checking reachability to specific hosts
final class NetworkReachabilityChecker: @unchecked Sendable {

    // MARK: - Properties

    private let host: String
    private let port: UInt16
    private var connection: NWConnection?
    private let queue: DispatchQueue

    // MARK: - Initialization

    /// Creates a reachability checker for a specific host
    /// - Parameters:
    ///   - host: The hostname to check
    ///   - port: The port to check (default 443 for HTTPS)
    init(host: String, port: UInt16 = 443) {
        self.host = host
        self.port = port
        self.queue = DispatchQueue(
            label: "com.orion.tasks.reachability.\(host)",
            qos: .utility
        )
    }

    deinit {
        connection?.cancel()
    }

    // MARK: - Public Methods

    /// Checks if the host is reachable
    /// - Parameter timeout: Timeout for the check
    /// - Returns: True if reachable, false otherwise
    func isReachable(timeout: TimeInterval = 5) async -> Bool {
        await withCheckedContinuation { continuation in
            let endpoint = NWEndpoint.hostPort(
                host: NWEndpoint.Host(host),
                port: NWEndpoint.Port(rawValue: port)!
            )

            let connection = NWConnection(to: endpoint, using: .tcp)
            self.connection = connection

            var hasResumed = false
            let lock = NSLock()

            func safeResume(with value: Bool) {
                lock.lock()
                defer { lock.unlock() }
                guard !hasResumed else { return }
                hasResumed = true
                connection.cancel()
                continuation.resume(returning: value)
            }

            // Set up timeout
            queue.asyncAfter(deadline: .now() + timeout) {
                safeResume(with: false)
            }

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    safeResume(with: true)
                case .failed, .cancelled:
                    safeResume(with: false)
                default:
                    break
                }
            }

            connection.start(queue: queue)
        }
    }

    /// Cancels any ongoing reachability check
    func cancel() {
        connection?.cancel()
        connection = nil
    }
}

// MARK: - WiFi Info (requires entitlement)

/// Provides WiFi network information when available
/// Note: Requires the "Access WiFi Information" entitlement
struct WiFiInfo {
    let ssid: String?
    let bssid: String?

    /// Attempts to get current WiFi information
    /// Returns nil if not on WiFi or if entitlement is missing
    static func current() -> WiFiInfo? {
        // Note: Getting WiFi info requires:
        // 1. Access WiFi Information entitlement
        // 2. Location permission (iOS 13+)
        // 3. CNCopyCurrentNetworkInfo API

        // For now, return nil as this requires additional setup
        return nil
    }
}

// MARK: - Extensions

extension NWPath.Status: CustomStringConvertible {
    public var description: String {
        switch self {
        case .satisfied:
            return "Connected"
        case .unsatisfied:
            return "Disconnected"
        case .requiresConnection:
            return "Requires Connection"
        @unknown default:
            return "Unknown"
        }
    }
}
