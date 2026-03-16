import Foundation

/// Typed representation of a libvirt network XML document.
/// Mirrors DomainConfig pattern: parses into typed properties, preserves full XMLDocument for round-trip fidelity.
public final class NetworkConfig: @unchecked Sendable {

    /// The underlying XML document, preserved for round-trip fidelity.
    private var xmlDoc: XMLDocument
    private var root: XMLElement

    // MARK: - Core Properties

    public var name: String {
        get { textContent("name") ?? "" }
        set { setTextContent("name", value: newValue) }
    }

    public var uuid: String {
        get { textContent("uuid") ?? "" }
        set { setTextContent("uuid", value: newValue) }
    }

    public var ipv6Enabled: Bool {
        get { root.attribute(forName: "ipv6")?.stringValue == "yes" }
        set {
            root.removeAttribute(forName: "ipv6")
            if newValue {
                root.addAttribute(XMLNode.attribute(withName: "ipv6", stringValue: "yes") as! XMLNode)
            }
        }
    }

    public var domain: String? {
        get { root.elements(forName: "domain").first?.attribute(forName: "name")?.stringValue }
        set {
            root.elements(forName: "domain").reversed().forEach { root.removeChild(at: $0.index) }
            if let d = newValue, !d.isEmpty {
                let el = XMLElement(name: "domain")
                el.addAttribute(XMLNode.attribute(withName: "name", stringValue: d) as! XMLNode)
                root.addChild(el)
            }
        }
    }

    // MARK: - Forward Configuration

    public var forward: ForwardConfig {
        get { ForwardConfig(networkElement: root) }
        set { newValue.applyTo(root) }
    }

    // MARK: - IP Configurations (can have multiple: one IPv4, one IPv6)

    public var ipConfigs: [IPConfig] {
        get {
            root.elements(forName: "ip").compactMap { IPConfig(from: $0) }
        }
        set {
            root.elements(forName: "ip").reversed().forEach { root.removeChild(at: $0.index) }
            for config in newValue {
                root.addChild(config.toXML())
            }
        }
    }

    /// Convenience: first IPv4 config (most networks have exactly one).
    public var ipv4Config: IPConfig? {
        get { ipConfigs.first { $0.family == .ipv4 } }
        set {
            var configs = ipConfigs.filter { $0.family != .ipv4 }
            if let v4 = newValue { configs.insert(v4, at: 0) }
            ipConfigs = configs
        }
    }

    /// Convenience: first IPv6 config.
    public var ipv6Config: IPConfig? {
        get { ipConfigs.first { $0.family == .ipv6 } }
        set {
            var configs = ipConfigs.filter { $0.family != .ipv6 }
            if let v6 = newValue { configs.append(v6) }
            ipConfigs = configs
        }
    }

    // MARK: - DNS Configuration

    public var dns: DNSConfig? {
        get {
            root.elements(forName: "dns").first.flatMap { DNSConfig(from: $0) }
        }
        set {
            root.elements(forName: "dns").reversed().forEach { root.removeChild(at: $0.index) }
            if let d = newValue {
                root.addChild(d.toXML())
            }
        }
    }

    // MARK: - Port Forwarding

    public var portForwarding: PortForwardConfig {
        get { PortForwardConfig(from: root.elements(forName: "portForward")) }
        set {
            root.elements(forName: "portForward").reversed().forEach { root.removeChild(at: $0.index) }
            for el in newValue.toXMLElements() {
                root.addChild(el)
            }
        }
    }

    // MARK: - Bandwidth / QoS

    public var bandwidth: BandwidthConfig? {
        get {
            root.elements(forName: "bandwidth").first.flatMap { BandwidthConfig(from: $0) }
        }
        set {
            root.elements(forName: "bandwidth").reversed().forEach { root.removeChild(at: $0.index) }
            if let bw = newValue, !bw.isEmpty {
                root.addChild(bw.toXML())
            }
        }
    }

    // MARK: - Initialization

    /// Parse from XML string.
    public init(xmlString: String) throws {
        self.xmlDoc = try XMLDocument(xmlString: xmlString, options: [.nodePreserveWhitespace])
        guard let r = xmlDoc.rootElement(), r.name == "network" else {
            throw NetworkConfigError.invalidXML("Root element must be <network>")
        }
        self.root = r
    }

    /// Create a new empty network config.
    public init(name: String, forwardMode: ForwardMode = .isolated) {
        let xmlStr = "<network><name>\(XMLHelpers.escapeXML(name))</name></network>"
        self.xmlDoc = try! XMLDocument(xmlString: xmlStr, options: [])
        self.root = xmlDoc.rootElement()!
        if forwardMode != .isolated {
            var fwd = ForwardConfig(mode: forwardMode)
            fwd.applyTo(root)
        }
    }

    // MARK: - Serialization

    /// Serialize back to XML string, preserving unknown elements.
    public func toXMLString() -> String {
        xmlDoc.xmlString(options: [.nodePrettyPrint])
    }

    // MARK: - Private Helpers

    private func textContent(_ elementName: String) -> String? {
        root.elements(forName: elementName).first?.stringValue
    }

    private func setTextContent(_ elementName: String, value: String) {
        if let existing = root.elements(forName: elementName).first {
            existing.stringValue = value
        } else {
            let el = XMLElement(name: elementName, stringValue: value)
            // Insert name/uuid at the beginning
            if elementName == "name" || elementName == "uuid" {
                root.insertChild(el, at: 0)
            } else {
                root.addChild(el)
            }
        }
    }
}

// MARK: - Errors

public enum NetworkConfigError: Error, Sendable {
    case invalidXML(String)
}
