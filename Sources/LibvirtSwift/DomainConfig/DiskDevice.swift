import Foundation

public struct DiskDevice: Identifiable, Sendable {
    public var id = UUID()
    public var type: String        // "file", "block", "network"
    public var device: String      // "disk", "cdrom", "floppy"
    public var driver: String?     // "qemu"
    public var format: String?     // "qcow2", "raw"
    public var sourcePath: String? // file path or volume path
    public var targetDev: String   // "vda", "sda", "hda"
    public var bus: DiskBus
    public var isReadonly: Bool

    public enum DiskBus: String, CaseIterable, Sendable {
        case virtio, scsi, sata, ide, usb, fdc
    }

    public init(
        type: String = "file",
        device: String = "disk",
        driver: String? = "qemu",
        format: String? = "qcow2",
        sourcePath: String? = nil,
        targetDev: String = "vda",
        bus: DiskBus = .virtio,
        isReadonly: Bool = false
    ) {
        self.type = type
        self.device = device
        self.driver = driver
        self.format = format
        self.sourcePath = sourcePath
        self.targetDev = targetDev
        self.bus = bus
        self.isReadonly = isReadonly
    }

    public init(from element: XMLElement) {
        self.type = element.attribute(forName: "type")?.stringValue ?? "file"
        self.device = element.attribute(forName: "device")?.stringValue ?? "disk"

        if let driverEl = element.elements(forName: "driver").first {
            self.driver = driverEl.attribute(forName: "name")?.stringValue
            self.format = driverEl.attribute(forName: "type")?.stringValue
        }

        if let sourceEl = element.elements(forName: "source").first {
            self.sourcePath = sourceEl.attribute(forName: "file")?.stringValue
                ?? sourceEl.attribute(forName: "dev")?.stringValue
                ?? sourceEl.attribute(forName: "name")?.stringValue
        }

        let targetEl = element.elements(forName: "target").first
        self.targetDev = targetEl?.attribute(forName: "dev")?.stringValue ?? "vda"
        let busStr = targetEl?.attribute(forName: "bus")?.stringValue ?? "virtio"
        self.bus = DiskBus(rawValue: busStr) ?? .virtio

        self.isReadonly = !element.elements(forName: "readonly").isEmpty
    }

    public func toXML() -> String {
        var xml = "<disk type=\"\(XMLHelpers.escapeXML(type))\" device=\"\(XMLHelpers.escapeXML(device))\">\n"
        if let driver = driver {
            let fmt = format.map { " type=\"\(XMLHelpers.escapeXML($0))\"" } ?? ""
            xml += "  <driver name=\"\(XMLHelpers.escapeXML(driver))\"\(fmt)/>\n"
        }
        if let sourcePath = sourcePath {
            let attr = type == "block" ? "dev" : "file"
            xml += "  <source \(attr)=\"\(XMLHelpers.escapeXML(sourcePath))\"/>\n"
        }
        xml += "  <target dev=\"\(XMLHelpers.escapeXML(targetDev))\" bus=\"\(bus.rawValue)\"/>\n"
        if isReadonly {
            xml += "  <readonly/>\n"
        }
        xml += "</disk>"
        return xml
    }
}
