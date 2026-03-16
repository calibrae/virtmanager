import Foundation

public struct SoundDevice: Identifiable, Sendable {
    public var id = UUID()
    public var model: String  // "ich9", "ich6", "ac97", "es1370", "sb16"

    public init(model: String = "ich9") {
        self.model = model
    }

    public init(from element: XMLElement) {
        self.model = element.attribute(forName: "model")?.stringValue ?? "ich9"
    }

    public func toXML() -> String {
        "<sound model=\"\(XMLHelpers.escapeXML(model))\"/>"
    }
}
