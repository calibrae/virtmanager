import Foundation

/// All libvirt network forward modes.
public enum ForwardMode: String, CaseIterable, Sendable {
    case nat = "nat"
    case route = "route"
    case open = "open"
    case bridge = "bridge"
    case `private` = "private"
    case vepa = "vepa"
    case passthrough = "passthrough"
    case hostdev = "hostdev"
    case isolated = "isolated" // no <forward> element

    /// Whether this mode supports IP/DHCP/DNS configuration.
    public var supportsIPConfig: Bool {
        switch self {
        case .nat, .route, .isolated, .open: return true
        case .bridge, .private, .vepa, .passthrough, .hostdev: return false
        }
    }

    /// Whether this mode supports port forwarding.
    public var supportsPortForwarding: Bool { self == .nat }

    /// Whether this mode requires a bridge device name.
    public var requiresBridgeName: Bool { self == .bridge }

    /// Whether this mode requires a physical interface.
    public var requiresPhysicalDevice: Bool {
        switch self {
        case .private, .vepa, .passthrough, .hostdev: return true
        default: return false
        }
    }

    /// Whether this mode uses macvtap.
    public var isMacvtap: Bool {
        switch self {
        case .private, .vepa, .passthrough, .bridge: return false
        // macvtap modes are vepa, private, passthrough, bridge (when used with dev=)
        default: return false
        }
    }
}

/// Parsed `<forward>` and `<bridge>` elements from network XML.
public struct ForwardConfig: Sendable {
    public var mode: ForwardMode
    public var dev: String?           // physical device for macvtap/passthrough
    public var bridgeName: String?    // <bridge name='...'/> or <bridge name='...'/> for OVS
    public var interfaces: [String]   // <interface dev='...'/> children
    public var natAddressStart: String?
    public var natAddressEnd: String?
    public var natPortStart: UInt16?
    public var natPortEnd: UInt16?
    public var isOVS: Bool            // <virtualport type='openvswitch'/>

    public init(
        mode: ForwardMode = .isolated,
        dev: String? = nil,
        bridgeName: String? = nil,
        interfaces: [String] = [],
        natAddressStart: String? = nil,
        natAddressEnd: String? = nil,
        natPortStart: UInt16? = nil,
        natPortEnd: UInt16? = nil,
        isOVS: Bool = false
    ) {
        self.mode = mode
        self.dev = dev
        self.bridgeName = bridgeName
        self.interfaces = interfaces
        self.natAddressStart = natAddressStart
        self.natAddressEnd = natAddressEnd
        self.natPortStart = natPortStart
        self.natPortEnd = natPortEnd
        self.isOVS = isOVS
    }

    // MARK: - XML Parsing

    init(networkElement: XMLElement) {
        let forwardEl = networkElement.elements(forName: "forward").first
        let bridgeEl = networkElement.elements(forName: "bridge").first

        self.bridgeName = bridgeEl?.attribute(forName: "name")?.stringValue

        guard let fwd = forwardEl else {
            // No <forward> → isolated
            self.mode = .isolated
            self.dev = nil
            self.interfaces = []
            self.natAddressStart = nil
            self.natAddressEnd = nil
            self.natPortStart = nil
            self.natPortEnd = nil
            self.isOVS = false
            return
        }

        let modeStr = fwd.attribute(forName: "mode")?.stringValue ?? "nat"
        self.dev = fwd.attribute(forName: "dev")?.stringValue

        // Check for OVS virtualport
        let virtualPort = networkElement.elements(forName: "virtualport").first
            ?? fwd.elements(forName: "virtualport").first
        self.isOVS = virtualPort?.attribute(forName: "type")?.stringValue == "openvswitch"

        // Parse <interface> children
        self.interfaces = fwd.elements(forName: "interface").compactMap {
            $0.attribute(forName: "dev")?.stringValue
        }

        // Parse NAT config
        let natEl = fwd.elements(forName: "nat").first
        let natAddr = natEl?.elements(forName: "address").first
        self.natAddressStart = natAddr?.attribute(forName: "start")?.stringValue
        self.natAddressEnd = natAddr?.attribute(forName: "end")?.stringValue
        let natPort = natEl?.elements(forName: "port").first
        self.natPortStart = natPort?.attribute(forName: "start")?.stringValue.flatMap { UInt16($0) }
        self.natPortEnd = natPort?.attribute(forName: "end")?.stringValue.flatMap { UInt16($0) }

        self.mode = ForwardMode(rawValue: modeStr) ?? .nat
    }

    // MARK: - XML Serialization

    func applyTo(_ root: XMLElement) {
        // Remove existing forward/bridge/virtualport
        root.elements(forName: "forward").reversed().forEach { root.removeChild(at: $0.index) }
        root.elements(forName: "bridge").reversed().forEach { root.removeChild(at: $0.index) }
        root.elements(forName: "virtualport").reversed().forEach { root.removeChild(at: $0.index) }

        if mode == .isolated {
            // No <forward> element for isolated networks
            if let bn = bridgeName, !bn.isEmpty {
                let bridgeEl = XMLElement(name: "bridge")
                bridgeEl.addAttribute(XMLNode.attribute(withName: "name", stringValue: bn) as! XMLNode)
                root.addChild(bridgeEl)
            }
            return
        }

        let fwd = XMLElement(name: "forward")
        fwd.addAttribute(XMLNode.attribute(withName: "mode", stringValue: mode.rawValue) as! XMLNode)

        if let d = dev, !d.isEmpty {
            fwd.addAttribute(XMLNode.attribute(withName: "dev", stringValue: d) as! XMLNode)
        }

        // NAT sub-elements
        if mode == .nat {
            let hasNatConfig = natAddressStart != nil || natPortStart != nil
            if hasNatConfig {
                let natEl = XMLElement(name: "nat")
                if let start = natAddressStart, let end = natAddressEnd {
                    let addr = XMLElement(name: "address")
                    addr.addAttribute(XMLNode.attribute(withName: "start", stringValue: start) as! XMLNode)
                    addr.addAttribute(XMLNode.attribute(withName: "end", stringValue: end) as! XMLNode)
                    natEl.addChild(addr)
                }
                if let start = natPortStart, let end = natPortEnd {
                    let port = XMLElement(name: "port")
                    port.addAttribute(XMLNode.attribute(withName: "start", stringValue: String(start)) as! XMLNode)
                    port.addAttribute(XMLNode.attribute(withName: "end", stringValue: String(end)) as! XMLNode)
                    natEl.addChild(port)
                }
                fwd.addChild(natEl)
            }
        }

        // Interface children for macvtap modes
        for iface in interfaces {
            let ifEl = XMLElement(name: "interface")
            ifEl.addAttribute(XMLNode.attribute(withName: "dev", stringValue: iface) as! XMLNode)
            fwd.addChild(ifEl)
        }

        root.addChild(fwd)

        // Bridge element
        if let bn = bridgeName, !bn.isEmpty {
            let bridgeEl = XMLElement(name: "bridge")
            bridgeEl.addAttribute(XMLNode.attribute(withName: "name", stringValue: bn) as! XMLNode)
            root.addChild(bridgeEl)
        }

        // OVS virtualport
        if isOVS {
            let vp = XMLElement(name: "virtualport")
            vp.addAttribute(XMLNode.attribute(withName: "type", stringValue: "openvswitch") as! XMLNode)
            root.addChild(vp)
        }
    }
}
