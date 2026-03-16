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

/// Result of checking a hostname against ~/.ssh/known_hosts.
public enum HostKeyStatus {
    case known
    case unknown
    case changed
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

    /// The current SCP upload process, if any. Stored so it can be killed on cancel.
    public var currentUploadProcess: Process?

    private let connectionStore = ConnectionStore()
    nonisolated(unsafe) private var libvirtConnections: [UUID: LibvirtConnection] = [:]

    private var pollTimer: Timer?

    public init() {
        if CommandLine.arguments.contains("--reset-connections") {
            connectionStore.save([])
            savedConnections = []
        } else {
            savedConnections = connectionStore.load()
        }
        startPolling()
    }

    /// Polls connected hypervisors every 5 seconds for VM state changes.
    private func startPolling() {
        pollTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            for (connID, state) in self.connectionStates {
                if state == .connected {
                    self.refreshVMs(for: connID)
                }
            }
        }
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
            // Best-effort SSH host key check before connecting
            let hostname = Self.extractHost(from: uri)
            if hostname != "localhost" && hostname != "127.0.0.1" {
                let keyStatus = await Self.checkHostKey(hostname: hostname)
                switch keyStatus {
                case .unknown:
                    let shouldConnect = await Self.showHostKeyAlert(
                        hostname: hostname,
                        title: "Unknown Host",
                        message: "The host key for \(hostname) is not in your known_hosts file. Do you want to connect anyway? The key will be added automatically.",
                        style: .informational
                    )
                    if !shouldConnect {
                        connectionStates[connID] = .disconnected
                        statusMessage = "Connection cancelled"
                        return
                    }
                case .changed:
                    let shouldConnect = await Self.showHostKeyAlert(
                        hostname: hostname,
                        title: "Host Key Changed",
                        message: "WARNING: The host key for \(hostname) has changed! This could indicate a man-in-the-middle attack, or the server may have been reinstalled. Do you want to connect anyway?",
                        style: .critical
                    )
                    if !shouldConnect {
                        connectionStates[connID] = .disconnected
                        statusMessage = "Connection cancelled — host key mismatch"
                        return
                    }
                case .known:
                    break // Host is known, proceed normally
                }
            }

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

    // MARK: - SSH Host Key Verification

    /// Checks whether the given hostname exists in ~/.ssh/known_hosts using ssh-keygen -F.
    private static func checkHostKey(hostname: String) async -> HostKeyStatus {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh-keygen")
                process.arguments = ["-F", hostname]

                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = Pipe()

                do {
                    try process.run()
                    process.waitUntilExit()

                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let output = String(data: data, encoding: .utf8) ?? ""

                    if process.terminationStatus == 0 && !output.isEmpty {
                        continuation.resume(returning: .known)
                    } else {
                        continuation.resume(returning: .unknown)
                    }
                } catch {
                    // If ssh-keygen fails, assume unknown (best-effort)
                    continuation.resume(returning: .unknown)
                }
            }
        }
    }

    /// Shows a host key verification alert and returns whether the user chose to connect.
    @MainActor
    private static func showHostKeyAlert(hostname: String, title: String, message: String, style: NSAlert.Style) async -> Bool {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = style
        alert.addButton(withTitle: "Connect")
        alert.addButton(withTitle: "Cancel")
        let response = alert.runModal()
        return response == .alertFirstButtonReturn
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
                let newVMs = domains.map { $0.toVMInfo() }
                let existing = connectionVMs[connectionID] ?? []

                // Preserve existing UUIDs by matching on VM name
                // so SwiftUI selection doesn't reset on refresh
                let merged = newVMs.map { newVM -> VMInfo in
                    if let old = existing.first(where: { $0.name == newVM.name }) {
                        return VMInfo(
                            id: old.id,
                            name: newVM.name,
                            uuid: newVM.uuid,
                            state: newVM.state,
                            vcpus: newVM.vcpus,
                            memoryMB: newVM.memoryMB,
                            graphicsType: newVM.graphicsType,
                            hasSerial: newVM.hasSerial
                        )
                    }
                    return newVM
                }
                connectionVMs[connectionID] = merged
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

    /// Opens VNC console, always tunneled through SSH for security.
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
        } catch {
            statusMessage = "Failed to open console: \(error.localizedDescription)"
        }
    }

    /// Opens a SPICE VM console using the native SPICE client.
    /// Sets up an SSH tunnel if needed, then opens the built-in SPICE console window.
    private func openSPICEViaTunnel(vm: VMInfo, conn: LibvirtConnection, saved: SavedConnection, connectionID: UUID) async {
        let vmName = vm.name
        print("[APP] openSPICEViaTunnel for \(vmName)")
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
                statusMessage = "SSH tunnel failed for SPICE on \(vmName)"
            }
        } catch {
            statusMessage = "Failed to open SPICE console: \(error.localizedDescription)"
        }
    }

    /// Sanitizes an SSH component (user or host) to prevent option injection.
    /// Only allows alphanumeric characters, dots, hyphens, and underscores.
    nonisolated private static func sanitizeSSHComponent(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-_"))
        return String(value.unicodeScalars.filter { allowed.contains($0) })
    }

    /// Shell-escapes a string for safe use inside remote SSH commands.
    /// Wraps in single quotes, escaping any existing single quotes.
    nonisolated private static func shellEscape(_ str: String) -> String {
        "'" + str.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Extracts hostname from a libvirt URI like qemu+ssh://user@host/system
    nonisolated private static func extractHost(from uri: String) -> String {
        // Parse: qemu+ssh://user@host/system or qemu+ssh://host/system
        guard let url = URL(string: uri.replacingOccurrences(of: "qemu+ssh://", with: "ssh://")) else {
            return "localhost"
        }
        return sanitizeSSHComponent(url.host ?? "localhost")
    }

    /// Extracts username from a libvirt URI
    nonisolated private static func extractUser(from uri: String) -> String {
        guard let url = URL(string: uri.replacingOccurrences(of: "qemu+ssh://", with: "ssh://")) else {
            return "root"
        }
        return sanitizeSSHComponent(url.user ?? "root")
    }

    /// Sets up an SSH tunnel. Reuses existing tunnel if the port is already bound.
    private static func setupSSHTunnel(localPort: UInt16, remotePort: UInt16, host: String, user: String) async -> Bool {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                // Check if tunnel already exists (port already listening)
                let checkProcess = Process()
                checkProcess.executableURL = URL(fileURLWithPath: "/usr/bin/lsof")
                checkProcess.arguments = ["-i", ":\(localPort)", "-sTCP:LISTEN"]
                checkProcess.standardOutput = Pipe()
                checkProcess.standardError = Pipe()
                if let _ = try? checkProcess.run() {
                    checkProcess.waitUntilExit()
                    if checkProcess.terminationStatus == 0 {
                        // Port already listening — tunnel exists
                        continuation.resume(returning: true)
                        return
                    }
                }

                // Create new tunnel
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
                process.arguments = [
                    "-f", "-N", "-L",
                    "\(localPort):127.0.0.1:\(remotePort)",
                    "\(user)@\(host)",
                    "-o", "StrictHostKeyChecking=accept-new",
                    "-o", "ExitOnForwardFailure=yes",
                    "-o", "ServerAliveInterval=30",
                    "-o", "BatchMode=yes",
                ]
                do {
                    try process.run()
                    Thread.sleep(forTimeInterval: 1.5)
                    continuation.resume(returning: true)
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

    // MARK: - Storage & ISO Management

    /// Lists all storage pools with their volumes for the given connection.
    public func listStoragePoolsWithVolumes(connectionID: UUID) async throws -> [PoolWithVolumes] {
        guard let conn = libvirtConnections[connectionID] else {
            throw LibvirtError.notConnected
        }
        return try await runBlocking {
            let pools = try conn.listStoragePools()
            return try pools.map { pool in
                let volumes = try conn.listVolumes(poolName: pool.name)
                return PoolWithVolumes(
                    id: pool.uuid,
                    name: pool.name,
                    isActive: pool.isActive,
                    capacity: pool.capacity,
                    allocation: pool.allocation,
                    volumes: volumes.map { vol in
                        VolumeEntry(
                            id: vol.path,
                            name: vol.name,
                            path: vol.path,
                            capacity: vol.capacity,
                            format: vol.format
                        )
                    }
                )
            }
        }
    }

    /// Lists ISO volumes across all storage pools.
    public func listISOVolumes(connectionID: UUID) async throws -> [StoragePoolEntry] {
        guard let conn = libvirtConnections[connectionID] else {
            throw LibvirtError.notConnected
        }
        return try await runBlocking {
            let pools = try conn.listStoragePools()
            return try pools.compactMap { pool -> StoragePoolEntry? in
                let volumes = try conn.listVolumes(poolName: pool.name)
                let isoVols = volumes.filter { $0.name.hasSuffix(".iso") }
                guard !isoVols.isEmpty else { return nil }
                return StoragePoolEntry(
                    id: pool.uuid,
                    name: pool.name,
                    isoVolumes: isoVols.map { vol in
                        ISOVolumeEntry(
                            id: vol.path,
                            name: vol.name,
                            path: vol.path,
                            capacity: vol.capacity
                        )
                    }
                )
            }
        }
    }

    /// Uploads a local ISO file to the hypervisor via SCP (much faster than libvirt streams).
    /// Creates the `virtmanager-iso` pool if it does not exist. Returns the remote volume path.
    public func uploadISO(
        fileURL: URL,
        connectionID: UUID,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws -> String {
        guard let conn = libvirtConnections[connectionID] else {
            throw LibvirtError.notConnected
        }
        guard let saved = savedConnections.first(where: { $0.id == connectionID }) else {
            throw LibvirtError.notConnected
        }

        // Sanitize filename: strip path traversal and shell metacharacters
        let rawName = fileURL.lastPathComponent
        let safeFileName = rawName.replacingOccurrences(of: "..", with: "_")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "`", with: "_")
            .replacingOccurrences(of: "$", with: "_")
            .replacingOccurrences(of: ";", with: "_")
            .replacingOccurrences(of: "|", with: "_")
            .replacingOccurrences(of: "&", with: "_")
        let fileSize = try FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? UInt64 ?? 0

        let host = Self.extractHost(from: saved.uri)
        let user = Self.extractUser(from: saved.uri)
        let remoteDir = "/var/lib/libvirt/images/virtmanager-iso"
        let remotePath = "\(remoteDir)/\(safeFileName)"

        // 1. Ensure the virtmanager-iso pool exists and the remote directory is created
        try await runBlocking {
            let pools = try conn.listStoragePools()
            if !pools.contains(where: { $0.name == "virtmanager-iso" }) {
                // Create directory on the remote host first
                let mkdirProcess = Process()
                mkdirProcess.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
                mkdirProcess.arguments = [
                    "-o", "StrictHostKeyChecking=accept-new",
                    "-o", "BatchMode=yes",
                    "\(user)@\(host)",
                    "mkdir -p \(Self.shellEscape(remoteDir))",
                ]
                mkdirProcess.standardOutput = Pipe()
                mkdirProcess.standardError = Pipe()
                try mkdirProcess.run()
                mkdirProcess.waitUntilExit()

                let poolXML = """
                <pool type='dir'>
                  <name>virtmanager-iso</name>
                  <target>
                    <path>\(LibvirtSwift.XMLHelpers.escapeXML(remoteDir))</path>
                  </target>
                </pool>
                """
                try conn.createPool(xml: poolXML)
            }
        }

        // 2. Upload via SCP subprocess — much faster than libvirt streams over SSH
        let scpProcess = Process()
        scpProcess.executableURL = URL(fileURLWithPath: "/usr/bin/scp")
        scpProcess.arguments = [
            "-o", "StrictHostKeyChecking=accept-new",
            "-o", "BatchMode=yes",
            fileURL.path,
            "\(user)@\(host):\(remotePath)",
        ]
        scpProcess.standardOutput = Pipe()
        scpProcess.standardError = Pipe()

        // Store the process so it can be killed on cancel
        currentUploadProcess = scpProcess

        // 3. Run SCP in background and poll remote file size for progress
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                do {
                    try scpProcess.run()
                } catch {
                    DispatchQueue.main.async { self?.currentUploadProcess = nil }
                    continuation.resume(throwing: error)
                    return
                }

                // Poll progress by checking remote file size
                let pollInterval: TimeInterval = 1.0
                while scpProcess.isRunning {
                    Thread.sleep(forTimeInterval: pollInterval)

                    guard fileSize > 0 else { continue }
                    let statProcess = Process()
                    statProcess.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
                    statProcess.arguments = [
                        "-o", "StrictHostKeyChecking=accept-new",
                        "-o", "BatchMode=yes",
                        "-o", "ConnectTimeout=5",
                        "\(user)@\(host)",
                        "stat --printf=%s \(Self.shellEscape(remotePath))",
                    ]
                    let statPipe = Pipe()
                    statProcess.standardOutput = statPipe
                    statProcess.standardError = Pipe()

                    do {
                        try statProcess.run()
                        statProcess.waitUntilExit()
                        let data = statPipe.fileHandleForReading.readDataToEndOfFile()
                        if let sizeStr = String(data: data, encoding: .utf8),
                           let remoteSize = UInt64(sizeStr.trimmingCharacters(in: .whitespacesAndNewlines)) {
                            let progress = Double(remoteSize) / Double(fileSize)
                            onProgress(min(progress, 0.99))
                        }
                    } catch {
                        // Ignore stat failures — progress just won't update this tick
                    }
                }

                DispatchQueue.main.async { self?.currentUploadProcess = nil }

                if scpProcess.terminationStatus != 0 {
                    let errPipe = scpProcess.standardError as? Pipe
                    let errData = errPipe?.fileHandleForReading.readDataToEndOfFile() ?? Data()
                    let errMsg = String(data: errData, encoding: .utf8) ?? "Unknown error"
                    continuation.resume(throwing: LibvirtError.operationFailed(
                        operation: "uploadISO/scp",
                        reason: errMsg.isEmpty ? "SCP exited with status \(scpProcess.terminationStatus)" : errMsg
                    ))
                    return
                }

                onProgress(1.0)
                continuation.resume()
            }
        }

        // 4. Refresh the storage pool so libvirt sees the new file
        try await runBlocking {
            try conn.refreshPool(name: "virtmanager-iso")
        }

        return remotePath
    }

    /// Cancels the current ISO upload and cleans up the partial file on the remote host.
    public func cancelUpload(connectionID: UUID) {
        guard let process = currentUploadProcess else { return }
        process.terminate()
        currentUploadProcess = nil

        // Best-effort cleanup of partial file on remote
        guard let saved = savedConnections.first(where: { $0.id == connectionID }) else { return }
        let host = Self.extractHost(from: saved.uri)
        let user = Self.extractUser(from: saved.uri)

        Task {
            await runBlockingVoid {
                let cleanup = Process()
                cleanup.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
                cleanup.arguments = [
                    "-o", "StrictHostKeyChecking=accept-new",
                    "-o", "BatchMode=yes",
                    "\(user)@\(host)",
                    "rm -f \(Self.shellEscape("/var/lib/libvirt/images/virtmanager-iso/*~"))",
                ]
                cleanup.standardOutput = Pipe()
                cleanup.standardError = Pipe()
                try? cleanup.run()
                cleanup.waitUntilExit()
            }
        }
    }

    // MARK: - Network Management

    /// Lists all virtual networks on the hypervisor.
    public func listNetworks(connectionID: UUID) async throws -> [NetworkInfo] {
        guard let conn = libvirtConnections[connectionID] else {
            throw LibvirtError.notConnected
        }
        return try await runBlocking {
            try conn.listNetworks()
        }
    }

    /// Starts an inactive virtual network.
    public func startNetwork(name: String, connectionID: UUID) async throws {
        guard let conn = libvirtConnections[connectionID] else {
            throw LibvirtError.notConnected
        }
        try await runBlocking { try conn.startNetwork(name: name) }
    }

    /// Stops an active virtual network.
    public func stopNetwork(name: String, connectionID: UUID) async throws {
        guard let conn = libvirtConnections[connectionID] else {
            throw LibvirtError.notConnected
        }
        try await runBlocking { try conn.stopNetwork(name: name) }
    }

    /// Defines and starts a new virtual network from XML.
    public func createNetwork(xml: String, connectionID: UUID) async throws {
        guard let conn = libvirtConnections[connectionID] else {
            throw LibvirtError.notConnected
        }
        try await runBlocking { try conn.createNetwork(xml: xml) }
    }

    /// Undefines and destroys a virtual network.
    public func deleteNetwork(name: String, connectionID: UUID) async throws {
        guard let conn = libvirtConnections[connectionID] else {
            throw LibvirtError.notConnected
        }
        try await runBlocking { try conn.deleteNetwork(name: name) }
    }

    // MARK: - Storage Pool Lifecycle

    /// Starts an inactive storage pool.
    public func startPool(name: String, connectionID: UUID) async throws {
        guard let conn = libvirtConnections[connectionID] else {
            throw LibvirtError.notConnected
        }
        try await runBlocking { try conn.startPool(name: name) }
    }

    /// Stops an active storage pool.
    public func stopPool(name: String, connectionID: UUID) async throws {
        guard let conn = libvirtConnections[connectionID] else {
            throw LibvirtError.notConnected
        }
        try await runBlocking { try conn.stopPool(name: name) }
    }

    /// Defines, builds, and starts a new storage pool from XML.
    public func createPool(xml: String, connectionID: UUID) async throws {
        guard let conn = libvirtConnections[connectionID] else {
            throw LibvirtError.notConnected
        }
        try await runBlocking { try conn.createPool(xml: xml) }
    }

    /// Undefines and destroys a storage pool.
    public func deletePool(name: String, connectionID: UUID) async throws {
        guard let conn = libvirtConnections[connectionID] else {
            throw LibvirtError.notConnected
        }
        try await runBlocking { try conn.deletePool(name: name) }
    }

    /// Refreshes a storage pool.
    public func refreshPool(name: String, connectionID: UUID) async throws {
        guard let conn = libvirtConnections[connectionID] else {
            throw LibvirtError.notConnected
        }
        try await runBlocking { try conn.refreshPool(name: name) }
    }

    // MARK: - Remote Filesystem Browsing

    /// Lists entries in a remote directory via SSH. Returns (name, isDirectory) pairs.
    public func listRemoteDirectory(
        path: String,
        connectionID: UUID
    ) async throws -> [(name: String, isDirectory: Bool)] {
        guard let saved = savedConnections.first(where: { $0.id == connectionID }) else {
            throw LibvirtError.notConnected
        }
        let host = Self.extractHost(from: saved.uri)
        let user = Self.extractUser(from: saved.uri)

        return try await runBlocking {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
            process.arguments = [
                "-o", "StrictHostKeyChecking=accept-new",
                "-o", "BatchMode=yes",
                "-o", "ConnectTimeout=10",
                "\(user)@\(host)",
                "ls -la \(Self.shellEscape(path))",
            ]
            let outPipe = Pipe()
            let errPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError = errPipe

            try process.run()
            process.waitUntilExit()

            let data = outPipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""

            var entries: [(name: String, isDirectory: Bool)] = []
            for line in output.components(separatedBy: "\n") {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty, !trimmed.hasPrefix("total") else { continue }

                // ls -la format: drwxr-xr-x ... name
                let parts = trimmed.split(separator: " ", maxSplits: 8, omittingEmptySubsequences: true)
                guard parts.count >= 9 else { continue }
                let name = String(parts[8])
                guard name != "." && name != ".." else { continue }

                let isDir = trimmed.hasPrefix("d")
                let isISO = name.lowercased().hasSuffix(".iso")

                // Only show directories and .iso files
                if isDir || isISO {
                    entries.append((name: name, isDirectory: isDir))
                }
            }

            // Sort: directories first, then alphabetically
            entries.sort { lhs, rhs in
                if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
            return entries
        }
    }

    /// Lists available bridges on the remote hypervisor via SSH.
    public func listRemoteBridges(connectionID: UUID) async throws -> [String] {
        guard let saved = savedConnections.first(where: { $0.id == connectionID }) else {
            throw LibvirtError.notConnected
        }
        let host = Self.extractHost(from: saved.uri)
        let user = Self.extractUser(from: saved.uri)

        return try await runBlocking {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
            process.arguments = [
                "-o", "StrictHostKeyChecking=accept-new",
                "-o", "BatchMode=yes",
                "-o", "ConnectTimeout=10",
                "\(user)@\(host)",
                "ip", "-br", "link", "show", "type", "bridge",
            ]
            let outPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError = Pipe()

            try process.run()
            process.waitUntilExit()

            let data = outPipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""

            return output.components(separatedBy: "\n").compactMap { line -> String? in
                let parts = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
                guard let name = parts.first else { return nil }
                return String(name)
            }
        }
    }

    /// Mounts a CDROM ISO on a running VM by updating its CDROM device.
    public func mountCDROM(vmName: String, isoPath: String, connectionID: UUID) async throws {
        guard let conn = libvirtConnections[connectionID] else {
            throw LibvirtError.notConnected
        }
        let deviceXML = """
        <disk type='file' device='cdrom'>
          <driver name='qemu' type='raw'/>
          <source file='\(LibvirtSwift.XMLHelpers.escapeXML(isoPath))'/>
          <target dev='sda' bus='sata'/>
          <readonly/>
        </disk>
        """
        try await runBlocking {
            try conn.updateDevice(domainName: vmName, deviceXML: deviceXML, live: true, config: true)
        }
    }

    /// Ejects the CDROM on a running VM by updating it with an empty source.
    public func ejectCDROM(vmName: String, connectionID: UUID) async throws {
        guard let conn = libvirtConnections[connectionID] else {
            throw LibvirtError.notConnected
        }
        let deviceXML = """
        <disk type='file' device='cdrom'>
          <driver name='qemu' type='raw'/>
          <target dev='sda' bus='sata'/>
          <readonly/>
        </disk>
        """
        try await runBlocking {
            try conn.updateDevice(domainName: vmName, deviceXML: deviceXML, live: true, config: true)
        }
    }

    // MARK: - VM Creation

    /// Creates a new VM from the wizard state.
    /// Handles ISO upload, disk creation, domain definition, and optional start.
    public func createVM(
        state: VMCreationState,
        connectionID: UUID,
        onUploadProgress: @escaping @Sendable (Double) -> Void
    ) async throws {
        guard let conn = libvirtConnections[connectionID] else {
            throw LibvirtError.notConnected
        }
        let vmName = state.name

        statusMessage = "Creating VM \(vmName)..."

        // 1. Handle ISO upload if local
        var isoPath: String?
        switch state.installSource {
        case .localISO(let url):
            statusMessage = "Uploading ISO \(url.lastPathComponent)..."
            isoPath = try await uploadISO(
                fileURL: url,
                connectionID: connectionID,
                onProgress: onUploadProgress
            )
        case .remoteISO(let path):
            isoPath = path
        case .networkURL:
            // Network install doesn't use a CDROM path in the same way;
            // for simplicity we skip it (user can configure post-creation).
            isoPath = nil
        case .none:
            isoPath = nil
        }

        // 2. Create disk volume if needed
        // Capture state values for Sendable closures
        let diskFormat = state.diskFormat
        let diskSizeGB = state.diskSizeGB
        let storagePool = state.storagePool
        let createNewDisk = state.createNewDisk
        let existingVolumePath = state.existingVolumePath
        let startAfterCreation = state.startAfterCreation

        var diskPath: String?
        if createNewDisk {
            statusMessage = "Creating disk for \(vmName)..."
            let diskName = "\(vmName).\(diskFormat)"
            let capacityBytes = UInt64(diskSizeGB) * 1_073_741_824

            diskPath = try await runBlocking {
                let volXML = """
                <volume>
                  <name>\(LibvirtSwift.XMLHelpers.escapeXML(diskName))</name>
                  <capacity unit='bytes'>\(capacityBytes)</capacity>
                  <target>
                    <format type='\(LibvirtSwift.XMLHelpers.escapeXML(diskFormat))'/>
                  </target>
                </volume>
                """
                return try conn.createVolume(poolName: storagePool, volumeXML: volXML)
            }
        } else if !existingVolumePath.isEmpty {
            diskPath = existingVolumePath
        }

        // 3. Generate and define domain XML
        statusMessage = "Defining VM \(vmName)..."
        let domainXML = state.generateDomainXML(diskPath: diskPath, isoPath: isoPath)

        try await runBlocking {
            try conn.defineDomainXML(domainXML)
        }

        // 4. Optionally start the VM
        if startAfterCreation {
            statusMessage = "Starting VM \(vmName)..."
            try await runBlocking {
                try conn.startDomain(name: vmName)
            }
        }

        // 5. Refresh VM list
        statusMessage = "VM \(vmName) created successfully"
        refreshVMs(for: connectionID)
    }

    // MARK: - Configuration

    /// Fetches the domain XML for the named VM.
    public func getDomainXML(vmName: String, connectionID: UUID, inactive: Bool = false) async throws -> String {
        guard let conn = libvirtConnections[connectionID] else {
            throw LibvirtError.notConnected
        }
        let name = vmName
        let inact = inactive
        return try await runBlocking {
            try conn.getDomainXML(name: name, inactive: inact)
        }
    }

    /// Applies (defines) a domain XML configuration on the hypervisor.
    public func applyConfiguration(vmName: String, xml: String, connectionID: UUID) async throws {
        guard let conn = libvirtConnections[connectionID] else {
            throw LibvirtError.notConnected
        }
        let xmlStr = xml
        try await runBlocking {
            try conn.defineDomainXML(xmlStr)
        }
        statusMessage = "Configuration applied for \(vmName)"
        refreshVMs(for: connectionID)
    }

    /// Opens a configuration editor window for the given VM.
    public func openConfiguration(for vm: VMInfo, connectionID: UUID) {
        WindowManager.shared.openConfigurationWindow(for: vm, connectionID: connectionID, appState: self)
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
