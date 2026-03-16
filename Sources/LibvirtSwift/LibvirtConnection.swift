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

    internal func withConnection<T>(_ body: (virConnectPtr) throws -> T) throws -> T {
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

    public func getDomainXML(name: String, inactive: Bool = false) throws -> String {
        try withConnection { conn in
            guard let domain = virDomainLookupByName(conn, name) else {
                throw LibvirtError.domainNotFound(name: name)
            }
            defer { virDomainFree(domain) }
            let flags: UInt32 = inactive ? UInt32(VIR_DOMAIN_XML_INACTIVE.rawValue) : 0
            guard let xmlPtr = virDomainGetXMLDesc(domain, flags) else {
                throw LibvirtError.xmlParsingFailed(reason: "Failed to get XML")
            }
            let result = String(cString: xmlPtr)
            free(xmlPtr)
            return result
        }
    }

    // MARK: - Domain Configuration

    /// Defines or updates a domain from an XML description.
    public func defineDomainXML(_ xml: String) throws {
        try withConnection { conn in
            guard let domain = virDomainDefineXML(conn, xml) else {
                let err = virGetLastErrorMessage().flatMap { String(cString: $0) } ?? "Unknown"
                throw LibvirtError.operationFailed(operation: "defineDomainXML", reason: err)
            }
            virDomainFree(domain)
        }
    }

    /// Undefines (removes the persistent configuration of) the named domain.
    public func undefineDomain(name: String) throws {
        try domainOp(name: name, "undefineDomain") { virDomainUndefine($0) }
    }

    // MARK: - Device Hot-Plug

    /// Attaches a device described by XML to a running and/or persistent domain.
    public func attachDevice(domainName: String, deviceXML: String, live: Bool, config: Bool) throws {
        try withConnection { conn in
            guard let domain = virDomainLookupByName(conn, domainName) else {
                throw LibvirtError.domainNotFound(name: domainName)
            }
            defer { virDomainFree(domain) }
            let flags = deviceFlags(live: live, config: config)
            if virDomainAttachDeviceFlags(domain, deviceXML, flags) < 0 {
                let err = virGetLastErrorMessage().flatMap { String(cString: $0) } ?? "Unknown"
                throw LibvirtError.operationFailed(operation: "attachDevice", reason: err)
            }
        }
    }

    /// Detaches a device described by XML from a running and/or persistent domain.
    public func detachDevice(domainName: String, deviceXML: String, live: Bool, config: Bool) throws {
        try withConnection { conn in
            guard let domain = virDomainLookupByName(conn, domainName) else {
                throw LibvirtError.domainNotFound(name: domainName)
            }
            defer { virDomainFree(domain) }
            let flags = deviceFlags(live: live, config: config)
            if virDomainDetachDeviceFlags(domain, deviceXML, flags) < 0 {
                let err = virGetLastErrorMessage().flatMap { String(cString: $0) } ?? "Unknown"
                throw LibvirtError.operationFailed(operation: "detachDevice", reason: err)
            }
        }
    }

    /// Updates a device described by XML (e.g. CDROM media change).
    public func updateDevice(domainName: String, deviceXML: String, live: Bool, config: Bool) throws {
        try withConnection { conn in
            guard let domain = virDomainLookupByName(conn, domainName) else {
                throw LibvirtError.domainNotFound(name: domainName)
            }
            defer { virDomainFree(domain) }
            let flags = deviceFlags(live: live, config: config)
            if virDomainUpdateDeviceFlags(domain, deviceXML, flags) < 0 {
                let err = virGetLastErrorMessage().flatMap { String(cString: $0) } ?? "Unknown"
                throw LibvirtError.operationFailed(operation: "updateDevice", reason: err)
            }
        }
    }

    // MARK: - Live Resource Changes

    /// Sets the memory (in KB) for a domain.
    public func setMemory(domainName: String, memoryKB: UInt64, live: Bool, config: Bool) throws {
        try withConnection { conn in
            guard let domain = virDomainLookupByName(conn, domainName) else {
                throw LibvirtError.domainNotFound(name: domainName)
            }
            defer { virDomainFree(domain) }
            let flags = deviceFlags(live: live, config: config)
            if virDomainSetMemoryFlags(domain, UInt(memoryKB), flags) < 0 {
                let err = virGetLastErrorMessage().flatMap { String(cString: $0) } ?? "Unknown"
                throw LibvirtError.operationFailed(operation: "setMemory", reason: err)
            }
        }
    }

    /// Sets the number of virtual CPUs for a domain.
    public func setVcpus(domainName: String, count: UInt32, live: Bool, config: Bool) throws {
        try withConnection { conn in
            guard let domain = virDomainLookupByName(conn, domainName) else {
                throw LibvirtError.domainNotFound(name: domainName)
            }
            defer { virDomainFree(domain) }
            let flags = deviceFlags(live: live, config: config)
            if virDomainSetVcpusFlags(domain, UInt32(count), flags) < 0 {
                let err = virGetLastErrorMessage().flatMap { String(cString: $0) } ?? "Unknown"
                throw LibvirtError.operationFailed(operation: "setVcpus", reason: err)
            }
        }
    }

    // MARK: - Storage Pool Management

    /// Lists all storage pools on the hypervisor.
    public func listStoragePools() throws -> [StoragePoolInfo] {
        try withConnection { conn in
            var poolsPtr: UnsafeMutablePointer<virStoragePoolPtr?>?
            let count = virConnectListAllStoragePools(conn, &poolsPtr, 0)
            guard count >= 0, let pools = poolsPtr else {
                let err = virGetLastErrorMessage().flatMap { String(cString: $0) } ?? "Unknown"
                throw LibvirtError.operationFailed(operation: "listStoragePools", reason: err)
            }
            defer {
                for i in 0..<Int(count) {
                    if let p = pools[i] { virStoragePoolFree(p) }
                }
                free(pools)
            }
            var results: [StoragePoolInfo] = []
            for i in 0..<Int(count) {
                guard let pool = pools[i] else { continue }
                guard let namePtr = virStoragePoolGetName(pool) else { continue }
                let name = String(cString: namePtr)

                var uuidBuf = [CChar](repeating: 0, count: Int(VIR_UUID_STRING_BUFLEN))
                virStoragePoolGetUUIDString(pool, &uuidBuf)
                let uuid = String(cString: uuidBuf)

                let isActive = virStoragePoolIsActive(pool) == 1

                var info = virStoragePoolInfo()
                virStoragePoolGetInfo(pool, &info)

                results.append(StoragePoolInfo(
                    name: name,
                    uuid: uuid,
                    isActive: isActive,
                    capacity: info.capacity,
                    allocation: info.allocation,
                    available: info.available
                ))
            }
            return results
        }
    }

    /// Lists all volumes in the named storage pool.
    public func listVolumes(poolName: String) throws -> [StorageVolumeInfo] {
        try withConnection { conn in
            guard let pool = virStoragePoolLookupByName(conn, poolName) else {
                let err = virGetLastErrorMessage().flatMap { String(cString: $0) } ?? "Unknown"
                throw LibvirtError.operationFailed(operation: "listVolumes", reason: err)
            }
            defer { virStoragePoolFree(pool) }

            var volsPtr: UnsafeMutablePointer<virStorageVolPtr?>?
            let count = virStoragePoolListAllVolumes(pool, &volsPtr, 0)
            guard count >= 0, let vols = volsPtr else {
                let err = virGetLastErrorMessage().flatMap { String(cString: $0) } ?? "Unknown"
                throw LibvirtError.operationFailed(operation: "listVolumes", reason: err)
            }
            defer {
                for i in 0..<Int(count) {
                    if let v = vols[i] { virStorageVolFree(v) }
                }
                free(vols)
            }
            var results: [StorageVolumeInfo] = []
            for i in 0..<Int(count) {
                guard let vol = vols[i] else { continue }
                guard let namePtr = virStorageVolGetName(vol) else { continue }
                let name = String(cString: namePtr)

                var volPath: String = ""
                if let pathPtr = virStorageVolGetPath(vol) {
                    volPath = String(cString: pathPtr)
                    free(pathPtr)
                }

                var info = virStorageVolInfo()
                virStorageVolGetInfo(vol, &info)

                let format: String
                switch info.type {
                case Int32(VIR_STORAGE_VOL_FILE.rawValue):
                    // Try to detect format from name extension
                    if name.hasSuffix(".qcow2") {
                        format = "qcow2"
                    } else if name.hasSuffix(".iso") {
                        format = "iso"
                    } else {
                        format = "raw"
                    }
                default:
                    format = "raw"
                }

                results.append(StorageVolumeInfo(
                    name: name,
                    path: volPath,
                    capacity: info.capacity,
                    allocation: info.allocation,
                    format: format
                ))
            }
            return results
        }
    }

    /// Creates a volume in the named pool from an XML description. Returns the volume path.
    public func createVolume(poolName: String, volumeXML: String) throws -> String {
        try withConnection { conn in
            guard let pool = virStoragePoolLookupByName(conn, poolName) else {
                let err = virGetLastErrorMessage().flatMap { String(cString: $0) } ?? "Unknown"
                throw LibvirtError.operationFailed(operation: "createVolume", reason: err)
            }
            defer { virStoragePoolFree(pool) }

            guard let vol = virStorageVolCreateXML(pool, volumeXML, 0) else {
                let err = virGetLastErrorMessage().flatMap { String(cString: $0) } ?? "Unknown"
                throw LibvirtError.operationFailed(operation: "createVolume", reason: err)
            }
            defer { virStorageVolFree(vol) }

            guard let pathPtr = virStorageVolGetPath(vol) else {
                let err = virGetLastErrorMessage().flatMap { String(cString: $0) } ?? "Unknown"
                throw LibvirtError.operationFailed(operation: "createVolume/getPath", reason: err)
            }
            let path = String(cString: pathPtr)
            free(pathPtr)
            return path
        }
    }

    /// Deletes a storage volume by its path.
    public func deleteVolume(path: String) throws {
        try withConnection { conn in
            guard let vol = virStorageVolLookupByPath(conn, path) else {
                let err = virGetLastErrorMessage().flatMap { String(cString: $0) } ?? "Unknown"
                throw LibvirtError.operationFailed(operation: "deleteVolume", reason: err)
            }
            defer { virStorageVolFree(vol) }
            if virStorageVolDelete(vol, 0) < 0 {
                let err = virGetLastErrorMessage().flatMap { String(cString: $0) } ?? "Unknown"
                throw LibvirtError.operationFailed(operation: "deleteVolume", reason: err)
            }
        }
    }

    /// Resizes a storage volume to the given capacity in bytes.
    public func resizeVolume(path: String, capacityBytes: UInt64) throws {
        try withConnection { conn in
            guard let vol = virStorageVolLookupByPath(conn, path) else {
                let err = virGetLastErrorMessage().flatMap { String(cString: $0) } ?? "Unknown"
                throw LibvirtError.operationFailed(operation: "resizeVolume", reason: err)
            }
            defer { virStorageVolFree(vol) }
            if virStorageVolResize(vol, CUnsignedLongLong(capacityBytes), 0) < 0 {
                let err = virGetLastErrorMessage().flatMap { String(cString: $0) } ?? "Unknown"
                throw LibvirtError.operationFailed(operation: "resizeVolume", reason: err)
            }
        }
    }

    /// Refreshes a storage pool to discover new/changed volumes.
    public func refreshPool(name: String) throws {
        try withConnection { conn in
            guard let pool = virStoragePoolLookupByName(conn, name) else {
                let err = virGetLastErrorMessage().flatMap { String(cString: $0) } ?? "Unknown"
                throw LibvirtError.operationFailed(operation: "refreshPool", reason: err)
            }
            defer { virStoragePoolFree(pool) }
            if virStoragePoolRefresh(pool, 0) < 0 {
                let err = virGetLastErrorMessage().flatMap { String(cString: $0) } ?? "Unknown"
                throw LibvirtError.operationFailed(operation: "refreshPool", reason: err)
            }
        }
    }

    /// Defines, builds, and starts a storage pool from XML.
    public func createPool(xml: String) throws {
        try withConnection { conn in
            guard let pool = virStoragePoolDefineXML(conn, xml, 0) else {
                let err = virGetLastErrorMessage().flatMap { String(cString: $0) } ?? "Unknown"
                throw LibvirtError.operationFailed(operation: "createPool/define", reason: err)
            }
            defer { virStoragePoolFree(pool) }
            // Build may fail for some pool types (e.g. already exists), so we ignore errors
            _ = virStoragePoolBuild(pool, 0)
            if virStoragePoolCreate(pool, 0) < 0 {
                let err = virGetLastErrorMessage().flatMap { String(cString: $0) } ?? "Unknown"
                throw LibvirtError.operationFailed(operation: "createPool/start", reason: err)
            }
        }
    }

    /// Returns the path of a volume by pool name and volume name.
    public func getVolumePath(poolName: String, volumeName: String) throws -> String {
        try withConnection { conn in
            guard let pool = virStoragePoolLookupByName(conn, poolName) else {
                let err = virGetLastErrorMessage().flatMap { String(cString: $0) } ?? "Unknown"
                throw LibvirtError.operationFailed(operation: "getVolumePath", reason: err)
            }
            defer { virStoragePoolFree(pool) }

            guard let vol = virStorageVolLookupByName(pool, volumeName) else {
                let err = virGetLastErrorMessage().flatMap { String(cString: $0) } ?? "Unknown"
                throw LibvirtError.operationFailed(operation: "getVolumePath", reason: err)
            }
            defer { virStorageVolFree(vol) }

            guard let pathPtr = virStorageVolGetPath(vol) else {
                let err = virGetLastErrorMessage().flatMap { String(cString: $0) } ?? "Unknown"
                throw LibvirtError.operationFailed(operation: "getVolumePath", reason: err)
            }
            let path = String(cString: pathPtr)
            free(pathPtr)
            return path
        }
    }

    // MARK: - Network Management

    /// Lists all virtual networks on the hypervisor.
    public func listNetworks() throws -> [NetworkInfo] {
        try withConnection { conn in
            var netsPtr: UnsafeMutablePointer<virNetworkPtr?>?
            let count = virConnectListAllNetworks(conn, &netsPtr, 0)
            guard count >= 0, let nets = netsPtr else {
                let err = virGetLastErrorMessage().flatMap { String(cString: $0) } ?? "Unknown"
                throw LibvirtError.operationFailed(operation: "listNetworks", reason: err)
            }
            defer {
                for i in 0..<Int(count) {
                    if let n = nets[i] { virNetworkFree(n) }
                }
                free(nets)
            }
            var results: [NetworkInfo] = []
            for i in 0..<Int(count) {
                guard let net = nets[i] else { continue }
                guard let namePtr = virNetworkGetName(net) else { continue }
                let name = String(cString: namePtr)

                var uuidBuf = [CChar](repeating: 0, count: Int(VIR_UUID_STRING_BUFLEN))
                virNetworkGetUUIDString(net, &uuidBuf)
                let uuid = String(cString: uuidBuf)

                let isActive = virNetworkIsActive(net) == 1

                var bridgeName: String?
                if let bridgePtr = virNetworkGetBridgeName(net) {
                    bridgeName = String(cString: bridgePtr)
                }

                var autostartVal: Int32 = 0
                virNetworkGetAutostart(net, &autostartVal)

                results.append(NetworkInfo(
                    name: name,
                    uuid: uuid,
                    isActive: isActive,
                    bridge: bridgeName,
                    autostart: autostartVal != 0
                ))
            }
            return results
        }
    }

    /// Starts an inactive virtual network.
    public func startNetwork(name: String) throws {
        try withConnection { conn in
            guard let net = virNetworkLookupByName(conn, name) else {
                let err = virGetLastErrorMessage().flatMap { String(cString: $0) } ?? "Unknown"
                throw LibvirtError.operationFailed(operation: "startNetwork", reason: err)
            }
            defer { virNetworkFree(net) }
            if virNetworkCreate(net) < 0 {
                let err = virGetLastErrorMessage().flatMap { String(cString: $0) } ?? "Unknown"
                throw LibvirtError.operationFailed(operation: "startNetwork", reason: err)
            }
        }
    }

    /// Stops an active virtual network.
    public func stopNetwork(name: String) throws {
        try withConnection { conn in
            guard let net = virNetworkLookupByName(conn, name) else {
                let err = virGetLastErrorMessage().flatMap { String(cString: $0) } ?? "Unknown"
                throw LibvirtError.operationFailed(operation: "stopNetwork", reason: err)
            }
            defer { virNetworkFree(net) }
            if virNetworkDestroy(net) < 0 {
                let err = virGetLastErrorMessage().flatMap { String(cString: $0) } ?? "Unknown"
                throw LibvirtError.operationFailed(operation: "stopNetwork", reason: err)
            }
        }
    }

    /// Defines a new virtual network from an XML description.
    public func createNetwork(xml: String) throws {
        try withConnection { conn in
            guard let net = virNetworkDefineXML(conn, xml) else {
                let err = virGetLastErrorMessage().flatMap { String(cString: $0) } ?? "Unknown"
                throw LibvirtError.operationFailed(operation: "createNetwork", reason: err)
            }
            defer { virNetworkFree(net) }
            if virNetworkCreate(net) < 0 {
                let err = virGetLastErrorMessage().flatMap { String(cString: $0) } ?? "Unknown"
                throw LibvirtError.operationFailed(operation: "createNetwork/start", reason: err)
            }
        }
    }

    /// Undefines and destroys a virtual network.
    public func deleteNetwork(name: String) throws {
        try withConnection { conn in
            guard let net = virNetworkLookupByName(conn, name) else {
                let err = virGetLastErrorMessage().flatMap { String(cString: $0) } ?? "Unknown"
                throw LibvirtError.operationFailed(operation: "deleteNetwork", reason: err)
            }
            defer { virNetworkFree(net) }
            // Stop it if active
            if virNetworkIsActive(net) == 1 {
                _ = virNetworkDestroy(net)
            }
            if virNetworkUndefine(net) < 0 {
                let err = virGetLastErrorMessage().flatMap { String(cString: $0) } ?? "Unknown"
                throw LibvirtError.operationFailed(operation: "deleteNetwork", reason: err)
            }
        }
    }

    // MARK: - Storage Pool Lifecycle

    /// Starts an inactive storage pool.
    public func startPool(name: String) throws {
        try withConnection { conn in
            guard let pool = virStoragePoolLookupByName(conn, name) else {
                let err = virGetLastErrorMessage().flatMap { String(cString: $0) } ?? "Unknown"
                throw LibvirtError.operationFailed(operation: "startPool", reason: err)
            }
            defer { virStoragePoolFree(pool) }
            if virStoragePoolCreate(pool, 0) < 0 {
                let err = virGetLastErrorMessage().flatMap { String(cString: $0) } ?? "Unknown"
                throw LibvirtError.operationFailed(operation: "startPool", reason: err)
            }
        }
    }

    /// Stops an active storage pool.
    public func stopPool(name: String) throws {
        try withConnection { conn in
            guard let pool = virStoragePoolLookupByName(conn, name) else {
                let err = virGetLastErrorMessage().flatMap { String(cString: $0) } ?? "Unknown"
                throw LibvirtError.operationFailed(operation: "stopPool", reason: err)
            }
            defer { virStoragePoolFree(pool) }
            if virStoragePoolDestroy(pool) < 0 {
                let err = virGetLastErrorMessage().flatMap { String(cString: $0) } ?? "Unknown"
                throw LibvirtError.operationFailed(operation: "stopPool", reason: err)
            }
        }
    }

    /// Undefines and destroys a storage pool.
    public func deletePool(name: String) throws {
        try withConnection { conn in
            guard let pool = virStoragePoolLookupByName(conn, name) else {
                let err = virGetLastErrorMessage().flatMap { String(cString: $0) } ?? "Unknown"
                throw LibvirtError.operationFailed(operation: "deletePool", reason: err)
            }
            defer { virStoragePoolFree(pool) }
            if virStoragePoolIsActive(pool) == 1 {
                _ = virStoragePoolDestroy(pool)
            }
            if virStoragePoolUndefine(pool) < 0 {
                let err = virGetLastErrorMessage().flatMap { String(cString: $0) } ?? "Unknown"
                throw LibvirtError.operationFailed(operation: "deletePool", reason: err)
            }
        }
    }

    /// Returns the XML description for a storage pool.
    public func getPoolXML(name: String) throws -> String {
        try withConnection { conn in
            guard let pool = virStoragePoolLookupByName(conn, name) else {
                let err = virGetLastErrorMessage().flatMap { String(cString: $0) } ?? "Unknown"
                throw LibvirtError.operationFailed(operation: "getPoolXML", reason: err)
            }
            defer { virStoragePoolFree(pool) }
            guard let xmlPtr = virStoragePoolGetXMLDesc(pool, 0) else {
                let err = virGetLastErrorMessage().flatMap { String(cString: $0) } ?? "Unknown"
                throw LibvirtError.operationFailed(operation: "getPoolXML", reason: err)
            }
            let result = String(cString: xmlPtr)
            free(xmlPtr)
            return result
        }
    }

    // MARK: - Private

    private func deviceFlags(live: Bool, config: Bool) -> UInt32 {
        var flags: UInt32 = 0
        if live { flags |= UInt32(VIR_DOMAIN_AFFECT_LIVE.rawValue) }
        if config { flags |= UInt32(VIR_DOMAIN_AFFECT_CONFIG.rawValue) }
        return flags
    }

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
