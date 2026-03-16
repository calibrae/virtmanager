import Foundation

public struct GraphicsDevice: Identifiable, Sendable {
    public var id = UUID()
    public var type: String       // "vnc", "spice"
    public var port: Int?         // -1 = auto-allocate
    public var listenAddress: String?
    public var autoport: Bool

    public init(
        type: String = "vnc",
        port: Int? = nil,
        listenAddress: String? = nil,
        autoport: Bool = true
    ) {
        self.type = type
        self.port = port
        self.listenAddress = listenAddress
        self.autoport = autoport
    }

    public init(from element: XMLElement) {
        self.type = element.attribute(forName: "type")?.stringValue ?? "vnc"
        if let portStr = element.attribute(forName: "port")?.stringValue {
            self.port = Int(portStr)
        }
        self.listenAddress = element.attribute(forName: "listen")?.stringValue
        self.autoport = element.attribute(forName: "autoport")?.stringValue == "yes"
    }

    public func toXML() -> String {
        var attrs = "type=\"\(XMLHelpers.escapeXML(type))\""
        if let port = port {
            attrs += " port=\"\(port)\""
        }
        if autoport {
            attrs += " autoport=\"yes\""
        }
        if let listen = listenAddress {
            attrs += " listen=\"\(XMLHelpers.escapeXML(listen))\""
        }
        return "<graphics \(attrs)/>"
    }
}
