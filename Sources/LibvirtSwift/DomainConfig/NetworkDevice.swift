import Foundation

public struct NetworkDevice: Identifiable, Sendable {
    public var id = UUID()
    public var type: String         // "bridge", "network", "direct"
    public var sourceName: String?  // bridge name or network name
    public var macAddress: String?
    public var model: NICModel

    public enum NICModel: String, CaseIterable, Sendable {
        case virtio, e1000, e1000e, rtl8139
    }

    public init(
        type: String = "network",
        sourceName: String? = "default",
        macAddress: String? = nil,
        model: NICModel = .virtio
    ) {
        self.type = type
        self.sourceName = sourceName
        self.macAddress = macAddress
        self.model = model
    }

    public init(from element: XMLElement) {
        self.type = element.attribute(forName: "type")?.stringValue ?? "network"

        if let sourceEl = element.elements(forName: "source").first {
            self.sourceName = sourceEl.attribute(forName: "network")?.stringValue
                ?? sourceEl.attribute(forName: "bridge")?.stringValue
                ?? sourceEl.attribute(forName: "dev")?.stringValue
        }

        self.macAddress = element.elements(forName: "mac").first?
            .attribute(forName: "address")?.stringValue

        let modelStr = element.elements(forName: "model").first?
            .attribute(forName: "type")?.stringValue ?? "virtio"
        self.model = NICModel(rawValue: modelStr) ?? .virtio
    }

    public func toXML() -> String {
        var xml = "<interface type=\"\(XMLHelpers.escapeXML(type))\">\n"
        if let mac = macAddress {
            xml += "  <mac address=\"\(XMLHelpers.escapeXML(mac))\"/>\n"
        }
        if let source = sourceName {
            let attr: String
            switch type {
            case "bridge": attr = "bridge"
            case "direct": attr = "dev"
            default: attr = "network"
            }
            xml += "  <source \(attr)=\"\(XMLHelpers.escapeXML(source))\"/>\n"
        }
        xml += "  <model type=\"\(model.rawValue)\"/>\n"
        xml += "</interface>"
        return xml
    }
}
