import Foundation

/// A DNS forwarder entry.
public struct DNSForwarder: Identifiable, Sendable {
    public var id = UUID()
    public var address: String?   // IP address to forward to
    public var domain: String?    // domain-specific forwarding (optional)

    public init(address: String? = nil, domain: String? = nil) {
        self.address = address
        self.domain = domain
    }
}

/// A DNS host record (IP → hostnames).
public struct DNSHostRecord: Identifiable, Sendable {
    public var id = UUID()
    public var ip: String
    public var hostnames: [String]

    public init(ip: String = "", hostnames: [String] = []) {
        self.ip = ip
        self.hostnames = hostnames
    }
}

/// A DNS TXT record.
public struct DNSTXTRecord: Identifiable, Sendable {
    public var id = UUID()
    public var name: String
    public var value: String

    public init(name: String = "", value: String = "") {
        self.name = name
        self.value = value
    }
}

/// A DNS SRV record.
public struct DNSSRVRecord: Identifiable, Sendable {
    public var id = UUID()
    public var service: String
    public var `protocol`: String
    public var domain: String?
    public var target: String?
    public var port: UInt16?
    public var priority: UInt16?
    public var weight: UInt16?

    public init(
        service: String = "",
        protocol: String = "",
        domain: String? = nil,
        target: String? = nil,
        port: UInt16? = nil,
        priority: UInt16? = nil,
        weight: UInt16? = nil
    ) {
        self.service = service
        self.protocol = `protocol`
        self.domain = domain
        self.target = target
        self.port = port
        self.priority = priority
        self.weight = weight
    }
}

/// Parsed `<dns>` element from network XML.
public struct DNSConfig: Sendable {
    public var enabled: Bool         // dns enable='no' → false
    public var forwardPlainNames: Bool?  // dns forwardPlainNames='yes'
    public var forwarders: [DNSForwarder]
    public var hostRecords: [DNSHostRecord]
    public var txtRecords: [DNSTXTRecord]
    public var srvRecords: [DNSSRVRecord]

    public init(
        enabled: Bool = true,
        forwardPlainNames: Bool? = nil,
        forwarders: [DNSForwarder] = [],
        hostRecords: [DNSHostRecord] = [],
        txtRecords: [DNSTXTRecord] = [],
        srvRecords: [DNSSRVRecord] = []
    ) {
        self.enabled = enabled
        self.forwardPlainNames = forwardPlainNames
        self.forwarders = forwarders
        self.hostRecords = hostRecords
        self.txtRecords = txtRecords
        self.srvRecords = srvRecords
    }

    // MARK: - XML Parsing

    init?(from element: XMLElement) {
        let enableAttr = element.attribute(forName: "enable")?.stringValue
        self.enabled = enableAttr != "no"

        let fpn = element.attribute(forName: "forwardPlainNames")?.stringValue
        self.forwardPlainNames = fpn == "yes" ? true : fpn == "no" ? false : nil

        self.forwarders = element.elements(forName: "forwarder").map { el in
            DNSForwarder(
                address: el.attribute(forName: "addr")?.stringValue,
                domain: el.attribute(forName: "domain")?.stringValue
            )
        }

        self.hostRecords = element.elements(forName: "host").map { el in
            DNSHostRecord(
                ip: el.attribute(forName: "ip")?.stringValue ?? "",
                hostnames: el.elements(forName: "hostname").compactMap { $0.stringValue }
            )
        }

        self.txtRecords = element.elements(forName: "txt").map { el in
            DNSTXTRecord(
                name: el.attribute(forName: "name")?.stringValue ?? "",
                value: el.attribute(forName: "value")?.stringValue ?? ""
            )
        }

        self.srvRecords = element.elements(forName: "srv").map { el in
            DNSSRVRecord(
                service: el.attribute(forName: "service")?.stringValue ?? "",
                protocol: el.attribute(forName: "protocol")?.stringValue ?? "",
                domain: el.attribute(forName: "domain")?.stringValue,
                target: el.attribute(forName: "target")?.stringValue,
                port: el.attribute(forName: "port")?.stringValue.flatMap { UInt16($0) },
                priority: el.attribute(forName: "priority")?.stringValue.flatMap { UInt16($0) },
                weight: el.attribute(forName: "weight")?.stringValue.flatMap { UInt16($0) }
            )
        }
    }

    // MARK: - XML Serialization

    func toXML() -> XMLElement {
        let dns = XMLElement(name: "dns")

        if !enabled {
            dns.addAttribute(XMLNode.attribute(withName: "enable", stringValue: "no") as! XMLNode)
        }
        if let fpn = forwardPlainNames {
            dns.addAttribute(XMLNode.attribute(withName: "forwardPlainNames", stringValue: fpn ? "yes" : "no") as! XMLNode)
        }

        for fwd in forwarders {
            let el = XMLElement(name: "forwarder")
            if let addr = fwd.address {
                el.addAttribute(XMLNode.attribute(withName: "addr", stringValue: addr) as! XMLNode)
            }
            if let domain = fwd.domain {
                el.addAttribute(XMLNode.attribute(withName: "domain", stringValue: domain) as! XMLNode)
            }
            dns.addChild(el)
        }

        for host in hostRecords {
            let el = XMLElement(name: "host")
            el.addAttribute(XMLNode.attribute(withName: "ip", stringValue: host.ip) as! XMLNode)
            for hostname in host.hostnames {
                let hn = XMLElement(name: "hostname", stringValue: hostname)
                el.addChild(hn)
            }
            dns.addChild(el)
        }

        for txt in txtRecords {
            let el = XMLElement(name: "txt")
            el.addAttribute(XMLNode.attribute(withName: "name", stringValue: txt.name) as! XMLNode)
            el.addAttribute(XMLNode.attribute(withName: "value", stringValue: txt.value) as! XMLNode)
            dns.addChild(el)
        }

        for srv in srvRecords {
            let el = XMLElement(name: "srv")
            el.addAttribute(XMLNode.attribute(withName: "service", stringValue: srv.service) as! XMLNode)
            el.addAttribute(XMLNode.attribute(withName: "protocol", stringValue: srv.protocol) as! XMLNode)
            if let d = srv.domain { el.addAttribute(XMLNode.attribute(withName: "domain", stringValue: d) as! XMLNode) }
            if let t = srv.target { el.addAttribute(XMLNode.attribute(withName: "target", stringValue: t) as! XMLNode) }
            if let p = srv.port { el.addAttribute(XMLNode.attribute(withName: "port", stringValue: String(p)) as! XMLNode) }
            if let pr = srv.priority { el.addAttribute(XMLNode.attribute(withName: "priority", stringValue: String(pr)) as! XMLNode) }
            if let w = srv.weight { el.addAttribute(XMLNode.attribute(withName: "weight", stringValue: String(w)) as! XMLNode) }
            dns.addChild(el)
        }

        return dns
    }
}
