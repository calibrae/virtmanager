import Foundation

/// A single port forwarding range rule.
public struct PortForwardRange: Identifiable, Sendable {
    public var id = UUID()
    public var start: UInt16       // host port start
    public var end: UInt16?        // host port end (nil = single port)
    public var to: UInt16?         // guest port (nil = same as host)
    public var toAddr: String?     // guest IP address

    public init(start: UInt16 = 0, end: UInt16? = nil, to: UInt16? = nil, toAddr: String? = nil) {
        self.start = start
        self.end = end
        self.to = to
        self.toAddr = toAddr
    }
}

/// A `<portForward>` element (libvirt 9.4+).
public struct PortForwardRule: Identifiable, Sendable {
    public var id = UUID()
    public var proto: String       // "tcp" or "udp"
    public var address: String?    // host address to listen on (optional)
    public var ranges: [PortForwardRange]

    public init(proto: String = "tcp", address: String? = nil, ranges: [PortForwardRange] = []) {
        self.proto = proto
        self.address = address
        self.ranges = ranges
    }
}

/// Collection of port forwarding rules for a network.
public struct PortForwardConfig: Sendable {
    public var rules: [PortForwardRule]

    public init(rules: [PortForwardRule] = []) {
        self.rules = rules
    }

    // MARK: - XML Parsing

    init(from elements: [XMLElement]) {
        self.rules = elements.map { pf in
            let proto = pf.attribute(forName: "proto")?.stringValue ?? "tcp"
            let address = pf.attribute(forName: "address")?.stringValue

            let ranges = pf.elements(forName: "range").map { rangeEl in
                PortForwardRange(
                    start: rangeEl.attribute(forName: "start")?.stringValue.flatMap { UInt16($0) } ?? 0,
                    end: rangeEl.attribute(forName: "end")?.stringValue.flatMap { UInt16($0) },
                    to: rangeEl.attribute(forName: "to")?.stringValue.flatMap { UInt16($0) },
                    toAddr: rangeEl.attribute(forName: "toAddr")?.stringValue
                )
            }

            return PortForwardRule(proto: proto, address: address, ranges: ranges)
        }
    }

    // MARK: - XML Serialization

    func toXMLElements() -> [XMLElement] {
        rules.map { rule in
            let pf = XMLElement(name: "portForward")
            pf.addAttribute(XMLNode.attribute(withName: "proto", stringValue: rule.proto) as! XMLNode)
            if let addr = rule.address {
                pf.addAttribute(XMLNode.attribute(withName: "address", stringValue: addr) as! XMLNode)
            }
            for range in rule.ranges {
                let rangeEl = XMLElement(name: "range")
                rangeEl.addAttribute(XMLNode.attribute(withName: "start", stringValue: String(range.start)) as! XMLNode)
                if let end = range.end {
                    rangeEl.addAttribute(XMLNode.attribute(withName: "end", stringValue: String(end)) as! XMLNode)
                }
                if let to = range.to {
                    rangeEl.addAttribute(XMLNode.attribute(withName: "to", stringValue: String(to)) as! XMLNode)
                }
                if let toAddr = range.toAddr {
                    rangeEl.addAttribute(XMLNode.attribute(withName: "toAddr", stringValue: toAddr) as! XMLNode)
                }
                pf.addChild(rangeEl)
            }
            return pf
        }
    }
}
