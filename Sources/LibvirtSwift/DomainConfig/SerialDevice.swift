import Foundation

public struct SerialDevice: Identifiable, Sendable {
    public var id = UUID()
    public var type: String       // "pty", "tcp", "unix", "file"
    public var targetPort: Int?
    public var targetType: String? // "isa-serial", "pci-serial"

    public init(
        type: String = "pty",
        targetPort: Int? = nil,
        targetType: String? = nil
    ) {
        self.type = type
        self.targetPort = targetPort
        self.targetType = targetType
    }

    public init(from element: XMLElement) {
        self.type = element.attribute(forName: "type")?.stringValue ?? "pty"
        let targetEl = element.elements(forName: "target").first
        if let portStr = targetEl?.attribute(forName: "port")?.stringValue {
            self.targetPort = Int(portStr)
        }
        self.targetType = targetEl?.attribute(forName: "type")?.stringValue
    }

    public func toXML() -> String {
        var xml = "<serial type=\"\(XMLHelpers.escapeXML(type))\">\n"
        var targetAttrs = [String]()
        if let targetType = targetType {
            targetAttrs.append("type=\"\(XMLHelpers.escapeXML(targetType))\"")
        }
        if let port = targetPort {
            targetAttrs.append("port=\"\(port)\"")
        }
        if !targetAttrs.isEmpty {
            xml += "  <target \(targetAttrs.joined(separator: " "))/>\n"
        }
        xml += "</serial>"
        return xml
    }
}
