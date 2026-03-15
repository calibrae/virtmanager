import CLibvirt
import Darwin
import Foundation
import VirtManagerCore

/// Swift wrapper around a libvirt connection (virConnectPtr).
/// Methods are synchronous and blocking — call from a background thread.
/// Thread safety is ensured by a lock protecting the connection pointer.
public final class LibvirtConnection: @unchecked Sendable {
    private let lock = NSLock()
    private var _connection: virConnectPtr?

    public init() {
        ensureLibvirtInitialized()
    }

    private func withConnection<T>(_ body: (virConnectPtr) throws -> T) throws -> T {
        lock.lock()
        guard let conn = _connection else {
            lock.unlock()
            throw LibvirtError.notConnected
        }
        lock.unlock()
        // Connection pointer is stable once set; only cleared by close()/deinit
        return try body(conn)
    }

    /// Returns the raw connection pointer for use by LibvirtStream.
    /// The caller must not free or close this pointer.
    public func rawConnectionPtr() throws -> virConnectPtr {
        lock.lock()
        defer { lock.unlock() }
        guard let conn = _connection else { throw LibvirtError.notConnected }
        return conn
    }

    /// Opens a graphics FD for the given domain. Returns a file descriptor
    /// that speaks the VNC protocol, regardless of whether the VM uses VNC or SPICE.
    /// This is the libvirt equivalent of what virt-viewer uses.
    public func openGraphicsFD(name: String) throws -> Int32 {
        return try withConnection { conn in
            guard let domain = virDomainLookupByName(conn, name) else {
                throw LibvirtError.domainNotFound(name: name)
            }
            defer { virDomainFree(domain) }
            let fd = virDomainOpenGraphicsFD(domain, 0, 0)
            if fd < 0 {
                let err = virGetLastErrorMessage().flatMap { String(cString: $0) } ?? "Unknown"
                throw LibvirtError.operationFailed(operation: "openGraphicsFD", reason: err)
            }
            return fd
        }
    }

    /// Opens a connection to the given libvirt URI. Blocking.
    public func open(uri: String) throws {
        Log.libvirt.info("Opening connection to \(uri)")
        guard let conn = virConnectOpen(uri) else {
            let err = virGetLastErrorMessage().flatMap { String(cString: $0) } ?? "Unknown error"
            Log.libvirt.error("Connection failed: \(err)")
            throw ConnectionError.connectionFailed(host: uri, reason: err)
        }
        lock.lock()
        _connection = conn
        lock.unlock()
        Log.libvirt.info("Connected successfully")
    }

    /// Closes the connection.
    public func close() {
        lock.lock()
        guard let conn = _connection else {
            lock.unlock()
            return
        }
        _connection = nil
        lock.unlock()
        Log.libvirt.info("Closing connection")
        virConnectClose(conn)
    }

    public var isConnected: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _connection != nil
    }

    public func hostname() throws -> String {
        try withConnection { conn in
            guard let name = virConnectGetHostname(conn) else {
                throw LibvirtError.operationFailed(operation: "getHostname", reason: "Failed")
            }
            let result = String(cString: name)
            free(name)
            return result
        }
    }

    public func listAllDomains() throws -> [VMDomainInfo] {
        try withConnection { conn in
            var domainsPtr: UnsafeMutablePointer<virDomainPtr?>?
            let count = virConnectListAllDomains(conn, &domainsPtr, 0)
            guard count >= 0, let domains = domainsPtr else {
                throw LibvirtError.operationFailed(operation: "listAllDomains", reason: "Failed")
            }
            defer {
                for i in 0..<Int(count) {
                    if let d = domains[i] { virDomainFree(d) }
                }
                free(domains)
            }
            var results: [VMDomainInfo] = []
            for i in 0..<Int(count) {
                guard let d = domains[i] else { continue }
                if let info = parseDomain(d) { results.append(info) }
            }
            return results
        }
    }

    public func startDomain(name: String) throws {
        try domainOp(name: name, "start") { virDomainCreate($0) }
    }

    public func shutdownDomain(name: String) throws {
        try domainOp(name: name, "shutdown") { virDomainShutdown($0) }
    }

    public func destroyDomain(name: String) throws {
        try domainOp(name: name, "destroy") { virDomainDestroy($0) }
    }

    public func suspendDomain(name: String) throws {
        try domainOp(name: name, "suspend") { virDomainSuspend($0) }
    }

    public func resumeDomain(name: String) throws {
        try domainOp(name: name, "resume") { virDomainResume($0) }
    }

    public func rebootDomain(name: String) throws {
        try domainOp(name: name, "reboot") { virDomainReboot($0, 0) }
    }

    public func getDomainXML(name: String) throws -> String {
        try withConnection { conn in
            guard let domain = virDomainLookupByName(conn, name) else {
                throw LibvirtError.domainNotFound(name: name)
            }
            defer { virDomainFree(domain) }
            guard let xmlPtr = virDomainGetXMLDesc(domain, 0) else {
                throw LibvirtError.xmlParsingFailed(reason: "Failed to get XML")
            }
            let result = String(cString: xmlPtr)
            free(xmlPtr)
            return result
        }
    }

    // MARK: - Private

    private func domainOp(name: String, _ opName: String, _ op: (virDomainPtr) -> Int32) throws {
        try withConnection { conn in
            guard let domain = virDomainLookupByName(conn, name) else {
                throw LibvirtError.domainNotFound(name: name)
            }
            defer { virDomainFree(domain) }
            if op(domain) < 0 {
                let err = virGetLastErrorMessage().flatMap { String(cString: $0) } ?? "Unknown"
                throw LibvirtError.operationFailed(operation: opName, reason: err)
            }
        }
    }

    private func parseDomain(_ domain: virDomainPtr) -> VMDomainInfo? {
        guard let namePtr = virDomainGetName(domain) else { return nil }
        let name = String(cString: namePtr)
        // namePtr is owned by libvirt — do not free

        var uuidBuf = [CChar](repeating: 0, count: Int(VIR_UUID_STRING_BUFLEN))
        virDomainGetUUIDString(domain, &uuidBuf)
        let uuid = String(cString: uuidBuf)

        var info = virDomainInfo()
        virDomainGetInfo(domain, &info)

        var graphicsType: String?
        var hasSerial = false
        if let xmlPtr = virDomainGetXMLDesc(domain, 0) {
            let xml = String(cString: xmlPtr)
            free(xmlPtr)
            graphicsType = XMLHelpers.extractGraphicsType(from: xml)
            hasSerial = XMLHelpers.hasSerialConsole(in: xml)
        }

        return VMDomainInfo(
            name: name, uuid: uuid,
            state: VMDomainInfo.stateFromLibvirt(Int32(info.state)),
            vcpus: Int(info.nrVirtCpu), memoryKB: Int(info.memory),
            graphicsType: graphicsType, hasSerial: hasSerial
        )
    }

    deinit {
        if let conn = _connection {
            virConnectClose(conn)
        }
    }
}
