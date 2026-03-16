import Foundation

public struct InputDevice: Identifiable, Sendable {
    public var id = UUID()
    public var type: String   // "tablet", "mouse", "keyboard"
    public var bus: String?   // "usb", "virtio", "ps2"

    public init(
        type: String = "tablet",
        bus: String? = "usb"
    ) {
        self.type = type
        self.bus = bus
    }

    public init(from element: XMLElement) {
        self.type = element.attribute(forName: "type")?.stringValue ?? "tablet"
        self.bus = element.attribute(forName: "bus")?.stringValue
    }

    public func toXML() -> String {
        var attrs = "type=\"\(XMLHelpers.escapeXML(type))\""
        if let bus = bus {
            attrs += " bus=\"\(XMLHelpers.escapeXML(bus))\""
        }
        return "<input \(attrs)/>"
    }
}
