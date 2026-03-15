import Foundation
import Network

/// Thread-safe wrapper to ensure a continuation is only resumed once.
private final class ContinuationGuard: Sendable {
    private let lock = NSLock()
    nonisolated(unsafe) private var _continuation: CheckedContinuation<Void, Error>?

    init(continuation: CheckedContinuation<Void, Error>) {
        self._continuation = continuation
    }

    func resumeOnce(_ block: (CheckedContinuation<Void, Error>) -> Void) {
        lock.lock()
        guard let cont = _continuation else {
            lock.unlock()
            return
        }
        _continuation = nil
        lock.unlock()
        block(cont)
    }
}

/// Manages a VNC connection using either TCP (NWConnection) or a file descriptor.
/// Implements the full RFB 3.8 handshake, security negotiation, and framebuffer updates.
public final class RFBConnection: @unchecked Sendable {
    private let host: String
    private let port: UInt16
    private let password: String?
    private let protocolHandler: RFBProtocolHandler

    private var nwConnection: NWConnection?
    private var fdHandle: FileHandle?
    private let queue = DispatchQueue(label: "com.virtmanager.vnc.connection")

    public private(set) var state: RFBConnectionState = .disconnected
    public private(set) var serverInit: RFBServerInit?
    public private(set) var framebuffer: RFBFramebuffer?

    public var onStateChange: (@Sendable (RFBConnectionState) -> Void)?
    public var onFramebufferUpdate: (@Sendable (UInt64) -> Void)?
    public var onServerName: (@Sendable (String) -> Void)?

    /// Create a connection to a VNC server at host:port.
    public init(host: String, port: UInt16, password: String? = nil) {
        self.host = host
        self.port = port
        self.password = password
        self.protocolHandler = RFBProtocolHandler()
    }

    /// Create a connection from an existing file descriptor (e.g., from virDomainOpenGraphicsFD).
    public init(fileDescriptor: Int32, password: String? = nil) {
        self.host = "fd"
        self.port = 0
        self.password = password
        self.protocolHandler = RFBProtocolHandler()
        self.fdHandle = FileHandle(fileDescriptor: fileDescriptor, closeOnDealloc: true)
    }

    // MARK: - Public API

    /// Connects to the VNC server and performs the full handshake.
    public func connect() async throws {
        setState(.connecting)

        if fdHandle != nil {
            // Already have an FD — go straight to handshake
            try await performHandshake()
            return
        }

        let nwHost = NWEndpoint.Host(host)
        let nwPort = NWEndpoint.Port(rawValue: port)!
        let connection = NWConnection(host: nwHost, port: nwPort, using: .tcp)
        self.nwConnection = connection

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let guard_ = ContinuationGuard(continuation: continuation)
            connection.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    guard_.resumeOnce { $0.resume() }
                case .failed(let error):
                    guard_.resumeOnce {
                        self?.setState(.error(error.localizedDescription))
                        $0.resume(throwing: VNCError.connectionFailed(error.localizedDescription))
                    }
                case .cancelled:
                    guard_.resumeOnce { $0.resume(throwing: VNCError.disconnected) }
                default:
                    break
                }
            }
            connection.start(queue: queue)
        }

        try await performHandshake()
    }

    /// Disconnects from the VNC server.
    public func disconnect() {
        nwConnection?.cancel()
        nwConnection = nil
        fdHandle = nil
        setState(.disconnected)
    }

    public func sendKeyEvent(down: Bool, keySym: UInt32) {
        let data = protocolHandler.makeKeyEvent(downFlag: down, keySym: keySym)
        send(data)
    }

    public func sendPointerEvent(buttonMask: UInt8, x: UInt16, y: UInt16) {
        let data = protocolHandler.makePointerEvent(buttonMask: buttonMask, x: x, y: y)
        send(data)
    }

    public func requestFullUpdate() {
        guard let si = serverInit else { return }
        send(protocolHandler.makeFramebufferUpdateRequest(
            incremental: false, x: 0, y: 0, width: si.width, height: si.height))
    }

    public func requestIncrementalUpdate() {
        guard let si = serverInit else { return }
        send(protocolHandler.makeFramebufferUpdateRequest(
            incremental: true, x: 0, y: 0, width: si.width, height: si.height))
    }

    // MARK: - Handshake

    private func performHandshake() async throws {
        setState(.handshaking)

        // Step 1: Server version (12 bytes)
        let versionData = try await receive(exactly: 12)
        let versionResponse = try protocolHandler.parseServerVersion(versionData)
        try await sendAndWait(versionResponse)

        // Step 2: Security type negotiation
        setState(.authenticating)
        let secTypeByte = try await receive(exactly: 1)
        let numSecTypes = Int(secTypeByte[0])

        if numSecTypes == 0 {
            let errLenData = try await receive(exactly: 4)
            let errLen = Int(UInt32(errLenData[0]) << 24 | UInt32(errLenData[1]) << 16 |
                             UInt32(errLenData[2]) << 8 | UInt32(errLenData[3]))
            let errMsgData = try await receive(exactly: errLen)
            throw VNCError.connectionFailed(String(data: errMsgData, encoding: .utf8) ?? "Unknown")
        }

        let secTypesData = try await receive(exactly: numSecTypes)
        let allSecData = [UInt8(numSecTypes)] + Array(secTypesData)
        let (selectedType, responseData) = try protocolHandler.parseSecurityTypes(allSecData)
        try await sendAndWait(responseData)

        // Step 3: Handle security type
        switch selectedType {
        case .none:
            let secResult = try await receive(exactly: 4)
            try protocolHandler.parseSecurityResult(Array(secResult))
        case .vncAuthentication:
            guard let password = password, !password.isEmpty else {
                throw VNCError.authenticationRequired
            }
            let challenge = try await receive(exactly: 16)
            let response = RFBSecurity.vncAuthResponse(challenge: Array(challenge), password: password)
            try await sendAndWait(Data(response))
            let secResult = try await receive(exactly: 4)
            try protocolHandler.parseSecurityResult(Array(secResult))
        default:
            throw VNCError.unsupportedSecurityType
        }

        // Step 4: Client/Server Init
        setState(.initializing)
        try await sendAndWait(protocolHandler.makeClientInit(shared: true))

        let serverInitBase = try await receive(exactly: 24)
        let serverInitBytes = Array(serverInitBase)
        let nameLen = Int(UInt32(serverInitBytes[20]) << 24 | UInt32(serverInitBytes[21]) << 16 |
                          UInt32(serverInitBytes[22]) << 8 | UInt32(serverInitBytes[23]))

        var fullServerInit = serverInitBytes
        if nameLen > 0 {
            let nameData = try await receive(exactly: nameLen)
            fullServerInit.append(contentsOf: nameData)
        }

        let si = try protocolHandler.parseServerInit(fullServerInit)
        self.serverInit = si
        self.framebuffer = RFBFramebuffer(width: Int(si.width), height: Int(si.height))
        onServerName?(si.name)

        // Step 5: Set pixel format and encodings
        send(protocolHandler.makeSetPixelFormat())
        send(protocolHandler.makeSetEncodings([.copyRect, .raw]))

        // Step 6: Request initial full framebuffer update
        send(protocolHandler.makeFramebufferUpdateRequest(
            incremental: false, x: 0, y: 0, width: si.width, height: si.height))

        setState(.connected)

        Task { [weak self] in
            await self?.readLoop()
        }
    }

    // MARK: - Message Read Loop

    private func readLoop() async {
        while state == .connected {
            do {
                let typeData = try await receive(exactly: 1)
                switch typeData[0] {
                case RFBServerMessageType.framebufferUpdate.rawValue:
                    try await handleFramebufferUpdate()
                case RFBServerMessageType.setColorMapEntries.rawValue:
                    try await handleSetColorMapEntries()
                case RFBServerMessageType.bell.rawValue:
                    break
                case RFBServerMessageType.serverCutText.rawValue:
                    try await handleServerCutText()
                default:
                    throw VNCError.protocolError("Unknown message type: \(typeData[0])")
                }
            } catch {
                if state == .connected {
                    setState(.error(error.localizedDescription))
                }
                break
            }
        }
    }

    private func handleFramebufferUpdate() async throws {
        let headerData = try await receive(exactly: 3)
        let numRects = Int(UInt16(headerData[1]) << 8 | UInt16(headerData[2]))

        for _ in 0..<numRects {
            let rectData = try await receive(exactly: 12)
            let rect = try protocolHandler.parseRectHeader(Array(rectData))

            switch rect.encoding {
            case RFBEncodingType.raw.rawValue:
                let bpp = Int(protocolHandler.requestedPixelFormat.bitsPerPixel) / 8
                let dataLen = Int(rect.width) * Int(rect.height) * bpp
                if dataLen > 0 {
                    let pixelData = try await receive(exactly: dataLen)
                    framebuffer?.applyRawRect(rect, data: Array(pixelData)[...])
                }
            case RFBEncodingType.copyRect.rawValue:
                let srcData = try await receive(exactly: 4)
                let srcX = UInt16(srcData[0]) << 8 | UInt16(srcData[1])
                let srcY = UInt16(srcData[2]) << 8 | UInt16(srcData[3])
                framebuffer?.applyCopyRect(rect, srcX: srcX, srcY: srcY)
            default:
                throw VNCError.protocolError("Unsupported encoding: \(rect.encoding)")
            }
        }

        if let gen = framebuffer?.generation { onFramebufferUpdate?(gen) }
        requestIncrementalUpdate()
    }

    private func handleSetColorMapEntries() async throws {
        let header = try await receive(exactly: 5)
        let numColors = Int(UInt16(header[3]) << 8 | UInt16(header[4]))
        _ = try await receive(exactly: numColors * 6)
    }

    private func handleServerCutText() async throws {
        let header = try await receive(exactly: 7)
        let length = Int(UInt32(header[3]) << 24 | UInt32(header[4]) << 16 |
                         UInt32(header[5]) << 8 | UInt32(header[6]))
        if length > 0 { _ = try await receive(exactly: length) }
    }

    // MARK: - Network I/O (dual transport: NWConnection or FileHandle)

    private func send(_ data: Data) {
        if let fd = fdHandle {
            queue.async { fd.write(data) }
        } else {
            nwConnection?.send(content: data, completion: .contentProcessed { _ in })
        }
    }

    private func sendAndWait(_ data: Data) async throws {
        if let fd = fdHandle {
            return try await withCheckedThrowingContinuation { continuation in
                queue.async {
                    fd.write(data)
                    continuation.resume()
                }
            }
        }

        guard let conn = nwConnection else { throw VNCError.disconnected }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            conn.send(content: data, completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: VNCError.connectionFailed(error.localizedDescription))
                } else {
                    continuation.resume()
                }
            })
        }
    }

    private func receive(exactly count: Int) async throws -> Data {
        if fdHandle != nil {
            return try await receiveFD(exactly: count)
        }

        guard let conn = nwConnection else { throw VNCError.disconnected }
        return try await withCheckedThrowingContinuation { continuation in
            conn.receive(minimumIncompleteLength: count, maximumLength: count) { content, _, isComplete, error in
                if let error {
                    continuation.resume(throwing: VNCError.connectionFailed(error.localizedDescription))
                } else if let content, content.count == count {
                    continuation.resume(returning: content)
                } else if isComplete {
                    continuation.resume(throwing: VNCError.disconnected)
                } else if let content {
                    continuation.resume(returning: content)
                } else {
                    continuation.resume(throwing: VNCError.disconnected)
                }
            }
        }
    }

    private func receiveFD(exactly count: Int) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [weak self] in
                guard let fd = self?.fdHandle else {
                    continuation.resume(throwing: VNCError.disconnected)
                    return
                }
                var buffer = Data()
                while buffer.count < count {
                    let chunk = fd.readData(ofLength: count - buffer.count)
                    if chunk.isEmpty {
                        continuation.resume(throwing: VNCError.disconnected)
                        return
                    }
                    buffer.append(chunk)
                }
                continuation.resume(returning: buffer)
            }
        }
    }

    private func setState(_ newState: RFBConnectionState) {
        state = newState
        onStateChange?(newState)
    }
}
