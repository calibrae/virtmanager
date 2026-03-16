import Foundation

/// Bandwidth limit for one direction (inbound or outbound).
public struct BandwidthLimit: Sendable, Equatable {
    public var average: UInt64     // KB/s
    public var peak: UInt64?       // KB/s (optional)
    public var burst: UInt64?      // KB (optional)

    public init(average: UInt64, peak: UInt64? = nil, burst: UInt64? = nil) {
        self.average = average
        self.peak = peak
        self.burst = burst
    }

    /// Human-readable string (e.g., "1.0 MB/s", "500 KB/s", "1.2 Gbps").
    public var displayString: String {
        formatBandwidth(average)
    }

    private func formatBandwidth(_ kbps: UInt64) -> String {
        if kbps >= 1_000_000 {
            return String(format: "%.1f GB/s", Double(kbps) / 1_000_000.0)
        } else if kbps >= 1_000 {
            return String(format: "%.1f MB/s", Double(kbps) / 1_000.0)
        } else {
            return "\(kbps) KB/s"
        }
    }
}

/// Parsed `<bandwidth>` element from network XML.
public struct BandwidthConfig: Sendable, Equatable {
    public var inbound: BandwidthLimit?
    public var outbound: BandwidthLimit?

    public var isEmpty: Bool { inbound == nil && outbound == nil }

    public init(inbound: BandwidthLimit? = nil, outbound: BandwidthLimit? = nil) {
        self.inbound = inbound
        self.outbound = outbound
    }

    // MARK: - XML Parsing

    init?(from element: XMLElement) {
        let inEl = element.elements(forName: "inbound").first
        let outEl = element.elements(forName: "outbound").first

        if inEl == nil && outEl == nil { return nil }

        self.inbound = inEl.flatMap { Self.parseLimit($0) }
        self.outbound = outEl.flatMap { Self.parseLimit($0) }
    }

    private static func parseLimit(_ el: XMLElement) -> BandwidthLimit? {
        guard let avg = el.attribute(forName: "average")?.stringValue.flatMap({ UInt64($0) }) else {
            return nil
        }
        return BandwidthLimit(
            average: avg,
            peak: el.attribute(forName: "peak")?.stringValue.flatMap { UInt64($0) },
            burst: el.attribute(forName: "burst")?.stringValue.flatMap { UInt64($0) }
        )
    }

    // MARK: - XML Serialization

    func toXML() -> XMLElement {
        let bw = XMLElement(name: "bandwidth")

        if let inb = inbound {
            let el = XMLElement(name: "inbound")
            el.addAttribute(XMLNode.attribute(withName: "average", stringValue: String(inb.average)) as! XMLNode)
            if let peak = inb.peak {
                el.addAttribute(XMLNode.attribute(withName: "peak", stringValue: String(peak)) as! XMLNode)
            }
            if let burst = inb.burst {
                el.addAttribute(XMLNode.attribute(withName: "burst", stringValue: String(burst)) as! XMLNode)
            }
            bw.addChild(el)
        }

        if let out = outbound {
            let el = XMLElement(name: "outbound")
            el.addAttribute(XMLNode.attribute(withName: "average", stringValue: String(out.average)) as! XMLNode)
            if let peak = out.peak {
                el.addAttribute(XMLNode.attribute(withName: "peak", stringValue: String(peak)) as! XMLNode)
            }
            if let burst = out.burst {
                el.addAttribute(XMLNode.attribute(withName: "burst", stringValue: String(burst)) as! XMLNode)
            }
            bw.addChild(el)
        }

        return bw
    }
}
