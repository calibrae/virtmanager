import Foundation

/// Information about a libvirt storage pool.
public struct StoragePoolInfo: Sendable {
    public let name: String
    public let uuid: String
    public let isActive: Bool
    public let capacity: UInt64
    public let allocation: UInt64
    public let available: UInt64

    public init(name: String, uuid: String, isActive: Bool, capacity: UInt64, allocation: UInt64, available: UInt64) {
        self.name = name
        self.uuid = uuid
        self.isActive = isActive
        self.capacity = capacity
        self.allocation = allocation
        self.available = available
    }
}

/// Information about a libvirt storage volume.
public struct StorageVolumeInfo: Sendable {
    public let name: String
    public let path: String
    public let capacity: UInt64
    public let allocation: UInt64
    public let format: String

    public init(name: String, path: String, capacity: UInt64, allocation: UInt64, format: String) {
        self.name = name
        self.path = path
        self.capacity = capacity
        self.allocation = allocation
        self.format = format
    }
}
