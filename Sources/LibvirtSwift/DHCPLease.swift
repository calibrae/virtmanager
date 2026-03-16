import Foundation

/// Active DHCP lease information from `virNetworkGetDHCPLeases`.
public struct DHCPLease: Identifiable, Sendable {
    public var id: String { "\(mac ?? "")-\(ipAddress)" }
    public let interface: String?   // bridge interface (e.g., "virbr0")
    public let expiry: Date
    public let type: Int            // 0 = IPv4, 6 = IPv6
    public let mac: String?
    public let ipAddress: String
    public let prefix: UInt32
    public let hostname: String?
    public let clientID: String?    // DUID for IPv6

    public var isIPv6: Bool { type == 6 }

    public var expiryString: String {
        if expiry.timeIntervalSince1970 == 0 { return "Never" }
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .medium
        return formatter.string(from: expiry)
    }

    public init(
        interface: String? = nil,
        expiry: Date = Date(),
        type: Int = 0,
        mac: String? = nil,
        ipAddress: String = "",
        prefix: UInt32 = 24,
        hostname: String? = nil,
        clientID: String? = nil
    ) {
        self.interface = interface
        self.expiry = expiry
        self.type = type
        self.mac = mac
        self.ipAddress = ipAddress
        self.prefix = prefix
        self.hostname = hostname
        self.clientID = clientID
    }
}
