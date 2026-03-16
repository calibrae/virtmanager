import Foundation

public struct ControllerDevice: Identifiable, Sendable {
    public var id = UUID()
    public var type: String     // "pci", "scsi", "usb", "virtio-serial", "sata", "ide"
    public var model: String?   // "pcie-root", "pcie-root-port", "virtio-scsi", etc
    public var index: Int?

    public init(
        type: String = "pci",
        model: String? = nil,
        index: Int? = nil
    ) {
        self.type = type
        self.model = model
        self.index = index
    }

    public init(from element: XMLElement) {
        self.type = element.attribute(forName: "type")?.stringValue ?? "pci"
        self.model = element.attribute(forName: "model")?.stringValue
        if let indexStr = element.attribute(forName: "index")?.stringValue {
            self.index = Int(indexStr)
        }
    }

    public func toXML() -> String {
        var attrs = "type=\"\(XMLHelpers.escapeXML(type))\""
        if let model = model {
            attrs += " model=\"\(XMLHelpers.escapeXML(model))\""
        }
        if let index = index {
            attrs += " index=\"\(index)\""
        }
        return "<controller \(attrs)/>"
    }
}
