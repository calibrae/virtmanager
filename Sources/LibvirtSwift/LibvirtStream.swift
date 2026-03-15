import CLibvirt
import Foundation
import VirtManagerCore

/// Swift wrapper around virStreamPtr for serial console I/O.
/// Used to send/receive data over a libvirt stream (e.g., `virDomainOpenConsole`).
public final class LibvirtStream: @unchecked Sendable {
    nonisolated(unsafe) private var _stream: virStreamPtr?
    nonisolated(unsafe) private var _connection: virConnectPtr?

    public init() {}

    /// Opens a console stream for the given domain using a LibvirtConnection.
    public func open(connection: LibvirtConnection, domainName: String, devName: String? = nil) throws {
        let rawConn = try connection.rawConnectionPtr()
        try open(rawConnection: rawConn, domainName: domainName, devName: devName)
    }

    /// Opens a console stream for the given domain.
    /// - Parameters:
    ///   - rawConnection: The libvirt connection pointer.
    ///   - domainName: The name of the domain.
    ///   - devName: Optional device name (e.g., "serial0"). Pass nil for the default console.
    public func open(rawConnection connection: virConnectPtr, domainName: String, devName: String? = nil) throws {
        _connection = connection

        guard let stream = virStreamNew(connection, 0) else {
            throw LibvirtError.operationFailed(operation: "streamNew", reason: lastError())
        }
        _stream = stream

        guard let domain = virDomainLookupByName(connection, domainName) else {
            virStreamFree(stream)
            _stream = nil
            throw LibvirtError.domainNotFound(name: domainName)
        }
        defer { virDomainFree(domain) }

        let flags = UInt32(VIR_DOMAIN_CONSOLE_FORCE.rawValue)
        let result = virDomainOpenConsole(domain, devName, stream, flags)
        if result < 0 {
            virStreamFree(stream)
            _stream = nil
            throw LibvirtError.operationFailed(
                operation: "openConsole",
                reason: lastError()
            )
        }
        Log.serial.info("Opened console stream for domain '\(domainName)'")
    }

    /// Reads data from the stream. Blocks until data is available.
    public func recv(maxBytes: Int = 4096) throws -> Data {
        guard let stream = _stream else {
            throw LibvirtError.operationFailed(operation: "streamRecv", reason: "Stream not open")
        }

        var buffer = [CChar](repeating: 0, count: maxBytes)
        let bytesRead = virStreamRecv(stream, &buffer, maxBytes)

        if bytesRead == 0 || bytesRead == -2 {
            // EOF or would-block
            return Data()
        } else if bytesRead < 0 {
            throw LibvirtError.operationFailed(operation: "streamRecv", reason: lastError())
        }

        let count = min(Int(bytesRead), maxBytes)
        return Data(bytes: buffer, count: count)
    }

    /// Sends data to the stream.
    /// Returns the number of bytes actually sent.
    @discardableResult
    public func send(_ data: Data) throws -> Int {
        guard let stream = _stream else {
            throw LibvirtError.operationFailed(operation: "streamSend", reason: "Stream not open")
        }

        let bytesSent = data.withUnsafeBytes { (ptr: UnsafeRawBufferPointer) -> Int in
            guard let baseAddress = ptr.baseAddress else { return -1 }
            return Int(virStreamSend(stream, baseAddress.assumingMemoryBound(to: CChar.self), data.count))
        }

        if bytesSent == -2 {
            // Would block
            return 0
        } else if bytesSent < 0 {
            throw LibvirtError.operationFailed(operation: "streamSend", reason: lastError())
        }

        return Int(bytesSent)
    }

    /// Closes and frees the stream.
    public func close() {
        guard let stream = _stream else { return }
        _stream = nil
        virStreamFinish(stream)
        virStreamFree(stream)
        Log.serial.info("Closed console stream")
    }

    deinit {
        if let stream = _stream {
            virStreamFinish(stream)
            virStreamFree(stream)
        }
    }

    // MARK: - Private

    private func lastError() -> String {
        virGetLastErrorMessage().flatMap { String(cString: $0) } ?? "Unknown error"
    }
}
