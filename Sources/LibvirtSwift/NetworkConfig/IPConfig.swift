import Foundation

/// Address family for IP configuration.
public enum AddressFamily: String, Sendable {
    case ipv4 = "ipv4"
    case ipv6 = "ipv6"
}

/// A DHCP range (start - end).
public struct DHCPRange: Identifiable, Sendable {
    public var id = UUID()
    public var start: String
    public var end: String

    public init(start: String = "", end: String = "") {
        self.start = start
        self.end = end
    }
}

/// A static DHCP host entry (MAC → IP, optional hostname).
public struct DHCPHost: Identifiable, Sendable {
    public var id = UUID()
    public var mac: String?       // required for IPv4, optional for IPv6
    public var name: String?      // hostname
    public var ip: String
    public var duid: String?      // for IPv6 DUID-based entries

    public init(mac: String? = nil, name: String? = nil, ip: String = "", duid: String? = nil) {
        self.mac = mac
        self.name = name
        self.ip = ip
        self.duid = duid
    }
}

/// BOOTP/PXE configuration inside DHCP.
public struct BOOTPConfig: Sendable {
    public var file: String?
    public var server: String?

    public init(file: String? = nil, server: String? = nil) {
        self.file = file
        self.server = server
    }
}

/// Parsed `<ip>` element from network XML. Supports both IPv4 and IPv6.
public struct IPConfig: Identifiable, Sendable {
    public var id = UUID()
    public var family: AddressFamily
    public var address: String
    public var netmask: String?      // IPv4 only (dotted notation)
    public var prefix: Int?          // CIDR prefix (IPv6 always, IPv4 optionally)
    public var dhcpEnabled: Bool
    public var dhcpRanges: [DHCPRange]
    public var dhcpHosts: [DHCPHost]
    public var bootp: BOOTPConfig?
    public var tftpRoot: String?     // <tftp root='...'/> on the <ip> element's parent

    public init(
        family: AddressFamily = .ipv4,
        address: String = "",
        netmask: String? = nil,
        prefix: Int? = nil,
        dhcpEnabled: Bool = false,
        dhcpRanges: [DHCPRange] = [],
        dhcpHosts: [DHCPHost] = [],
        bootp: BOOTPConfig? = nil,
        tftpRoot: String? = nil
    ) {
        self.family = family
        self.address = address
        self.netmask = netmask
        self.prefix = prefix
        self.dhcpEnabled = dhcpEnabled
        self.dhcpRanges = dhcpRanges
        self.dhcpHosts = dhcpHosts
        self.bootp = bootp
        self.tftpRoot = tftpRoot
    }

    // MARK: - XML Parsing

    init?(from element: XMLElement) {
        let familyStr = element.attribute(forName: "family")?.stringValue
        // If family is explicitly "ipv6" or address contains ":", it's IPv6
        let addr = element.attribute(forName: "address")?.stringValue ?? ""
        if familyStr == "ipv6" || addr.contains(":") {
            self.family = .ipv6
        } else {
            self.family = .ipv4
        }

        self.address = addr
        self.netmask = element.attribute(forName: "netmask")?.stringValue
        self.prefix = element.attribute(forName: "prefix")?.stringValue.flatMap { Int($0) }

        // Parse DHCP
        let dhcpEl = element.elements(forName: "dhcp").first
        self.dhcpEnabled = dhcpEl != nil

        self.dhcpRanges = dhcpEl?.elements(forName: "range").map { rangeEl in
            DHCPRange(
                start: rangeEl.attribute(forName: "start")?.stringValue ?? "",
                end: rangeEl.attribute(forName: "end")?.stringValue ?? ""
            )
        } ?? []

        self.dhcpHosts = dhcpEl?.elements(forName: "host").map { hostEl in
            DHCPHost(
                mac: hostEl.attribute(forName: "mac")?.stringValue,
                name: hostEl.attribute(forName: "name")?.stringValue,
                ip: hostEl.attribute(forName: "ip")?.stringValue ?? "",
                duid: hostEl.attribute(forName: "id")?.stringValue
            )
        } ?? []

        // BOOTP
        let bootpEl = dhcpEl?.elements(forName: "bootp").first
        if let bp = bootpEl {
            self.bootp = BOOTPConfig(
                file: bp.attribute(forName: "file")?.stringValue,
                server: bp.attribute(forName: "server")?.stringValue
            )
        }

        // TFTP (on parent <network> or sibling)
        self.tftpRoot = nil // parsed at NetworkConfig level
    }

    // MARK: - XML Serialization

    func toXML() -> XMLElement {
        let ip = XMLElement(name: "ip")
        ip.addAttribute(XMLNode.attribute(withName: "address", stringValue: address) as! XMLNode)

        if family == .ipv6 {
            ip.addAttribute(XMLNode.attribute(withName: "family", stringValue: "ipv6") as! XMLNode)
        }

        if let nm = netmask, family == .ipv4 {
            ip.addAttribute(XMLNode.attribute(withName: "netmask", stringValue: nm) as! XMLNode)
        }

        if let p = prefix {
            ip.addAttribute(XMLNode.attribute(withName: "prefix", stringValue: String(p)) as! XMLNode)
        }

        if dhcpEnabled && (!dhcpRanges.isEmpty || !dhcpHosts.isEmpty || bootp != nil) {
            let dhcp = XMLElement(name: "dhcp")

            for range in dhcpRanges {
                let rangeEl = XMLElement(name: "range")
                rangeEl.addAttribute(XMLNode.attribute(withName: "start", stringValue: range.start) as! XMLNode)
                rangeEl.addAttribute(XMLNode.attribute(withName: "end", stringValue: range.end) as! XMLNode)
                dhcp.addChild(rangeEl)
            }

            for host in dhcpHosts {
                let hostEl = XMLElement(name: "host")
                if let mac = host.mac, !mac.isEmpty {
                    hostEl.addAttribute(XMLNode.attribute(withName: "mac", stringValue: mac) as! XMLNode)
                }
                if let name = host.name, !name.isEmpty {
                    hostEl.addAttribute(XMLNode.attribute(withName: "name", stringValue: name) as! XMLNode)
                }
                hostEl.addAttribute(XMLNode.attribute(withName: "ip", stringValue: host.ip) as! XMLNode)
                if let duid = host.duid, !duid.isEmpty {
                    hostEl.addAttribute(XMLNode.attribute(withName: "id", stringValue: duid) as! XMLNode)
                }
                dhcp.addChild(hostEl)
            }

            if let bp = bootp {
                let bootpEl = XMLElement(name: "bootp")
                if let file = bp.file {
                    bootpEl.addAttribute(XMLNode.attribute(withName: "file", stringValue: file) as! XMLNode)
                }
                if let server = bp.server {
                    bootpEl.addAttribute(XMLNode.attribute(withName: "server", stringValue: server) as! XMLNode)
                }
                dhcp.addChild(bootpEl)
            }

            ip.addChild(dhcp)
        }

        return ip
    }
}
