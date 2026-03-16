import Foundation

/// Information about a libvirt virtual network, extended for Phase 3.
public struct NetworkInfo: Identifiable, Sendable {
    public var id: String { uuid }
    public let name: String
    public let uuid: String
    public let isActive: Bool
    public let isPersistent: Bool
    public let bridge: String?
    public let autostart: Bool
    public let forwardMode: String    // "nat", "route", "bridge", "isolated", etc.
    public let ipv4Summary: String?   // e.g., "192.168.122.0/24"
    public let ipv6Summary: String?   // e.g., "fd00:cafe::/64"
    public let connectedVMCount: Int

    public init(
        name: String,
        uuid: String,
        isActive: Bool,
        isPersistent: Bool = true,
        bridge: String?,
        autostart: Bool,
        forwardMode: String = "isolated",
        ipv4Summary: String? = nil,
        ipv6Summary: String? = nil,
        connectedVMCount: Int = 0
    ) {
        self.name = name
        self.uuid = uuid
        self.isActive = isActive
        self.isPersistent = isPersistent
        self.bridge = bridge
        self.autostart = autostart
        self.forwardMode = forwardMode
        self.ipv4Summary = ipv4Summary
        self.ipv6Summary = ipv6Summary
        self.connectedVMCount = connectedVMCount
    }
}
