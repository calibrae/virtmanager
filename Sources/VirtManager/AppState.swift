import Foundation
import SwiftUI
import VirtManagerCore
import LibvirtSwift

/// Runs a blocking operation on a background thread and returns the result.
public func runBlocking<T: Sendable>(_ body: @Sendable @escaping () throws -> T) async throws -> T {
    try await withCheckedThrowingContinuation { continuation in
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let result = try body()
                continuation.resume(returning: result)
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}

public func runBlockingVoid(_ body: @Sendable @escaping () -> Void) async {
    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
        DispatchQueue.global(qos: .userInitiated).async {
            body()
            continuation.resume()
        }
    }
}

/// Main application state, shared across the UI.
@Observable
@MainActor
public final class AppState {
    public var savedConnections: [SavedConnection] = []
    public var connectionStates: [UUID: ConnectionState] = [:]
    public var connectionVMs: [UUID: [VMInfo]] = [:]
    public var selectedConnectionID: UUID?
    public var selectedVMID: UUID?
    public var isShowingConnectionSheet = false
    public var editingConnection: SavedConnection?
    public var statusMessage: String = "Ready"
    public var searchText: String = ""

    private let connectionStore = ConnectionStore()
    nonisolated(unsafe) private var libvirtConnections: [UUID: LibvirtConnection] = [:]

    public init() {
        savedConnections = connectionStore.load()
    }

    // MARK: - Connection Actions

    public func addConnection(_ connection: SavedConnection) {
        savedConnections.append(connection)
        connectionStore.save(savedConnections)
    }

    public func updateConnection(_ connection: SavedConnection) {
        if let index = savedConnections.firstIndex(where: { $0.id == connection.id }) {
            savedConnections[index] = connection
            connectionStore.save(savedConnections)
        }
    }

    public func removeConnection(_ connection: SavedConnection) {
        savedConnections.removeAll { $0.id == connection.id }
        connectionStates.removeValue(forKey: connection.id)
        connectionVMs.removeValue(forKey: connection.id)
        libvirtConnections.removeValue(forKey: connection.id)
        connectionStore.save(savedConnections)
    }

    public func connect(to connection: SavedConnection) {
        let connID = connection.id
        let uri = connection.uri
        connectionStates[connID] = .connecting
        statusMessage = "Connecting to \(connection.displayName)..."

        Task {
            do {
                let libvirtConn = LibvirtConnection()
                let domains: [VMDomainInfo] = try await runBlocking {
                    try libvirtConn.open(uri: uri)
                    return try libvirtConn.listAllDomains()
                }
                let vmInfos = domains.map { $0.toVMInfo() }
                libvirtConnections[connID] = libvirtConn
                connectionStates[connID] = .connected
                connectionVMs[connID] = vmInfos
                statusMessage = "Connected to \(connection.displayName)"
                if let index = savedConnections.firstIndex(where: { $0.id == connID }) {
                    savedConnections[index].lastConnected = Date()
                    connectionStore.save(savedConnections)
                }
            } catch {
                connectionStates[connID] = .error(error.localizedDescription)
                statusMessage = "Failed: \(error.localizedDescription)"
            }
        }
    }

    public func disconnect(from connectionID: UUID) {
        connectionStates[connectionID] = .disconnecting
        let conn = libvirtConnections.removeValue(forKey: connectionID)
        connectionVMs.removeValue(forKey: connectionID)

        Task {
            if let conn {
                await runBlockingVoid { conn.close() }
            }
            connectionStates[connectionID] = .disconnected
            statusMessage = "Disconnected"
        }
    }

    public func refreshVMs(for connectionID: UUID) {
        guard let conn = libvirtConnections[connectionID] else { return }
        Task {
            do {
                let domains: [VMDomainInfo] = try await runBlocking {
                    try conn.listAllDomains()
                }
                connectionVMs[connectionID] = domains.map { $0.toVMInfo() }
            } catch {
                statusMessage = "Refresh failed: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - VM Actions

    public func startVM(_ vm: VMInfo, connectionID: UUID) {
        performVMAction(vm: vm, connectionID: connectionID, action: "Starting") { conn in
            try conn.startDomain(name: vm.name)
        }
    }

    public func shutdownVM(_ vm: VMInfo, connectionID: UUID) {
        performVMAction(vm: vm, connectionID: connectionID, action: "Shutting down") { conn in
            try conn.shutdownDomain(name: vm.name)
        }
    }

    public func forceOffVM(_ vm: VMInfo, connectionID: UUID) {
        performVMAction(vm: vm, connectionID: connectionID, action: "Forcing off") { conn in
            try conn.destroyDomain(name: vm.name)
        }
    }

    public func pauseVM(_ vm: VMInfo, connectionID: UUID) {
        performVMAction(vm: vm, connectionID: connectionID, action: "Pausing") { conn in
            try conn.suspendDomain(name: vm.name)
        }
    }

    public func resumeVM(_ vm: VMInfo, connectionID: UUID) {
        performVMAction(vm: vm, connectionID: connectionID, action: "Resuming") { conn in
            try conn.resumeDomain(name: vm.name)
        }
    }

    public func rebootVM(_ vm: VMInfo, connectionID: UUID) {
        performVMAction(vm: vm, connectionID: connectionID, action: "Rebooting") { conn in
            try conn.rebootDomain(name: vm.name)
        }
    }

    private func performVMAction(vm: VMInfo, connectionID: UUID, action: String,
                                  operation: @Sendable @escaping (LibvirtConnection) throws -> Void) {
        guard let conn = libvirtConnections[connectionID] else { return }
        let vmName = vm.name
        statusMessage = "\(action) \(vmName)..."
        Task {
            do {
                let domains: [VMDomainInfo] = try await runBlocking {
                    try operation(conn)
                    return try conn.listAllDomains()
                }
                connectionVMs[connectionID] = domains.map { $0.toVMInfo() }
                statusMessage = "\(vmName) — \(action.lowercased()) complete"
            } catch {
                statusMessage = "Failed: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Console Actions

    /// Opens a graphical console window for the given VM.
    /// Supports both VNC and SPICE VMs. For SPICE, uses virDomainOpenGraphicsFD
    /// which provides a VNC-compatible FD through libvirt.
    public func openConsole(for vm: VMInfo, connectionID: UUID) {
        guard vm.state.canOpenConsole else {
            statusMessage = "Cannot open console: VM is not running"
            return
        }
        guard vm.graphicsType != nil else {
            statusMessage = "No graphics configured for \(vm.name)"
            return
        }
        guard let conn = libvirtConnections[connectionID] else {
            statusMessage = "Not connected"
            return
        }
        guard let saved = savedConnections.first(where: { $0.id == connectionID }) else {
            statusMessage = "Connection not found"
            return
        }

        let vmName = vm.name
        let graphicsType = vm.graphicsType
        statusMessage = "Opening console for \(vmName)..."

        Task {
            if graphicsType == .vnc {
                await openVNCDirectly(vm: vm, conn: conn, saved: saved, connectionID: connectionID)
            } else if graphicsType == .spice {
                await openSPICEViaTunnel(vm: vm, conn: conn, saved: saved, connectionID: connectionID)
            } else {
                statusMessage = "No supported graphics for \(vmName)"
            }
        }
    }

    /// Fallback: connect directly to VNC port on the hypervisor.
    private func openVNCDirectly(vm: VMInfo, conn: LibvirtConnection, saved: SavedConnection, connectionID: UUID) async {
        let vmName = vm.name
        do {
            let xml: String = try await runBlocking {
                try conn.getDomainXML(name: vmName)
            }
            guard let port = LibvirtSwift.XMLHelpers.extractVNCPort(from: xml) else {
                statusMessage = "Could not determine VNC port for \(vmName)"
                return
            }
            let hypervisorHost = Self.extractHost(from: saved.uri)
            let listenAddr = LibvirtSwift.XMLHelpers.extractVNCListenAddress(from: xml)

            if listenAddr == "0.0.0.0" || listenAddr == nil {
                WindowManager.shared.openVNCConsole(
                    for: vm, connectionID: connectionID,
                    host: hypervisorHost, port: UInt16(port)
                )
                statusMessage = "Console opened for \(vmName) → \(hypervisorHost):\(port)"
            } else {
                let sshUser = Self.extractUser(from: saved.uri)
                statusMessage = "Setting up SSH tunnel for \(vmName)..."
                let tunnelOK = await Self.setupSSHTunnel(
                    localPort: UInt16(port), remotePort: UInt16(port),
                    host: hypervisorHost, user: sshUser
                )
                if tunnelOK {
                    WindowManager.shared.openVNCConsole(
                        for: vm, connectionID: connectionID,
                        host: "127.0.0.1", port: UInt16(port)
                    )
                    statusMessage = "Console opened for \(vmName) via SSH tunnel"
                } else {
                    statusMessage = "SSH tunnel failed for \(vmName)"
                }
            }
        } catch {
            statusMessage = "Failed to open console: \(error.localizedDescription)"
        }
    }

    /// Opens a SPICE VM console using the native SPICE client.
    /// Sets up an SSH tunnel if needed, then opens the built-in SPICE console window.
    private func openSPICEViaTunnel(vm: VMInfo, conn: LibvirtConnection, saved: SavedConnection, connectionID: UUID) async {
        let vmName = vm.name
        do {
            let xml: String = try await runBlocking {
                try conn.getDomainXML(name: vmName)
            }
            guard let port = LibvirtSwift.XMLHelpers.extractSPICEPort(from: xml) else {
                statusMessage = "Could not determine SPICE port for \(vmName)"
                return
            }

            let hypervisorHost = Self.extractHost(from: saved.uri)
            let sshUser = Self.extractUser(from: saved.uri)
            let localPort = UInt16(port)

            // SPICE typically listens on localhost, so try SSH tunnel first
            statusMessage = "Setting up SSH tunnel for SPICE on \(vmName)..."
            let tunnelOK = await Self.setupSSHTunnel(
                localPort: localPort, remotePort: UInt16(port),
                host: hypervisorHost, user: sshUser
            )

            if tunnelOK {
                WindowManager.shared.openSPICEConsole(
                    for: vm, connectionID: connectionID,
                    host: "127.0.0.1", port: localPort
                )
                statusMessage = "SPICE console opened for \(vmName) via SSH tunnel"
            } else {
                // Tunnel failed — try direct connection
                WindowManager.shared.openSPICEConsole(
                    for: vm, connectionID: connectionID,
                    host: hypervisorHost, port: UInt16(port)
                )
                statusMessage = "SPICE console opened for \(vmName) → \(hypervisorHost):\(port)"
            }
        } catch {
            statusMessage = "Failed to open SPICE console: \(error.localizedDescription)"
        }
    }

    /// Extracts hostname from a libvirt URI like qemu+ssh://user@host/system
    private static func extractHost(from uri: String) -> String {
        // Parse: qemu+ssh://user@host/system or qemu+ssh://host/system
        guard let url = URL(string: uri.replacingOccurrences(of: "qemu+ssh://", with: "ssh://")) else {
            return "localhost"
        }
        return url.host ?? "localhost"
    }

    /// Extracts username from a libvirt URI
    private static func extractUser(from uri: String) -> String {
        guard let url = URL(string: uri.replacingOccurrences(of: "qemu+ssh://", with: "ssh://")) else {
            return "root"
        }
        return url.user ?? "root"
    }

    /// Sets up an SSH tunnel in the background.
    private static func setupSSHTunnel(localPort: UInt16, remotePort: UInt16, host: String, user: String) async -> Bool {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
                process.arguments = [
                    "-f", "-N", "-L",
                    "\(localPort):127.0.0.1:\(remotePort)",
                    "\(user)@\(host)",
                    "-o", "ExitOnForwardFailure=yes",
                    "-o", "ServerAliveInterval=30",
                ]
                do {
                    try process.run()
                    // Give it a moment to establish
                    Thread.sleep(forTimeInterval: 1.0)
                    continuation.resume(returning: process.isRunning || true)
                } catch {
                    continuation.resume(returning: false)
                }
            }
        }
    }

    /// Opens a serial console window for the given VM.
    public func openSerialConsole(for vm: VMInfo, connectionID: UUID) {
        guard vm.state.canOpenConsole else {
            statusMessage = "Cannot open serial console: VM is not running"
            return
        }
        guard vm.hasSerial else {
            statusMessage = "No serial console configured for \(vm.name)"
            return
        }
        guard let conn = libvirtConnections[connectionID] else {
            statusMessage = "Not connected"
            return
        }

        statusMessage = "Opening serial console for \(vm.name)..."
        WindowManager.shared.openSerialConsole(for: vm, connectionID: connectionID, libvirtConnection: conn)
        statusMessage = "Serial console opened for \(vm.name)"
    }

    // MARK: - Helpers

    public func selectedVM() -> VMInfo? {
        guard let vmID = selectedVMID else { return nil }
        for vms in connectionVMs.values {
            if let vm = vms.first(where: { $0.id == vmID }) { return vm }
        }
        return nil
    }

    public func connectionID(for vmID: UUID) -> UUID? {
        for (connID, vms) in connectionVMs {
            if vms.contains(where: { $0.id == vmID }) { return connID }
        }
        return nil
    }

    public func filteredVMs(for connectionID: UUID) -> [VMInfo] {
        let vms = connectionVMs[connectionID] ?? []
        if searchText.isEmpty { return vms }
        return vms.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }
}
