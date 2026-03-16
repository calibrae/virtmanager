import Foundation

/// Information about a libvirt virtual network.
public struct NetworkInfo: Sendable {
    public let name: String
    public let uuid: String
    public let isActive: Bool
    public let bridge: String?
    public let autostart: Bool

    public init(name: String, uuid: String, isActive: Bool, bridge: String?, autostart: Bool) {
        self.name = name
        self.uuid = uuid
        self.isActive = isActive
        self.bridge = bridge
        self.autostart = autostart
    }
}
