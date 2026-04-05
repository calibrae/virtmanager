import Foundation

public struct HostDevice: Identifiable, Sendable {
    public var id = UUID()
    public var mode: String
    public var type: HostDeviceType
    public var managed: Bool

    // USB source
    public var usbVendorID: String?
    public var usbProductID: String?

    // PCI source address
    public var pciDomain: String?
    public var pciBus: String?
    public var pciSlot: String?
    public var pciFunction: String?

    public enum HostDeviceType: String, CaseIterable, Sendable {
        case usb = "usb"
        case pci = "pci"
    }

    public init(
        mode: String = "subsystem",
        type: HostDeviceType = .usb,
        managed: Bool = true,
        usbVendorID: String? = nil,
        usbProductID: String? = nil,
        pciDomain: String? = nil,
        pciBus: String? = nil,
        pciSlot: String? = nil,
        pciFunction: String? = nil
    ) {
        self.mode = mode
        self.type = type
        self.managed = managed
        self.usbVendorID = usbVendorID
        self.usbProductID = usbProductID
        self.pciDomain = pciDomain
        self.pciBus = pciBus
        self.pciSlot = pciSlot
        self.pciFunction = pciFunction
    }

    public init(from element: XMLElement) {
        self.mode = element.attribute(forName: "mode")?.stringValue ?? "subsystem"
        let typeStr = element.attribute(forName: "type")?.stringValue ?? "usb"
        self.type = HostDeviceType(rawValue: typeStr) ?? .usb
        self.managed = element.attribute(forName: "managed")?.stringValue == "yes"

        if let sourceEl = element.elements(forName: "source").first {
            switch self.type {
            case .usb:
                self.usbVendorID = sourceEl.elements(forName: "vendor").first?
                    .attribute(forName: "id")?.stringValue
                self.usbProductID = sourceEl.elements(forName: "product").first?
                    .attribute(forName: "id")?.stringValue
            case .pci:
                if let addrEl = sourceEl.elements(forName: "address").first {
                    self.pciDomain = addrEl.attribute(forName: "domain")?.stringValue
                    self.pciBus = addrEl.attribute(forName: "bus")?.stringValue
                    self.pciSlot = addrEl.attribute(forName: "slot")?.stringValue
                    self.pciFunction = addrEl.attribute(forName: "function")?.stringValue
                }
            }
        }
    }

    public func toXML() -> String {
        let managedStr = managed ? "yes" : "no"
        var xml = "<hostdev mode=\"\(XMLHelpers.escapeXML(mode))\" type=\"\(XMLHelpers.escapeXML(type.rawValue))\" managed=\"\(managedStr)\">\n"
        xml += "  <source>\n"

        switch type {
        case .usb:
            if let vendor = usbVendorID {
                xml += "    <vendor id=\"\(XMLHelpers.escapeXML(vendor))\"/>\n"
            }
            if let product = usbProductID {
                xml += "    <product id=\"\(XMLHelpers.escapeXML(product))\"/>\n"
            }
        case .pci:
            let domain = pciDomain ?? "0x0000"
            let bus = pciBus ?? "0x00"
            let slot = pciSlot ?? "0x00"
            let function = pciFunction ?? "0x0"
            xml += "    <address domain=\"\(XMLHelpers.escapeXML(domain))\" bus=\"\(XMLHelpers.escapeXML(bus))\" slot=\"\(XMLHelpers.escapeXML(slot))\" function=\"\(XMLHelpers.escapeXML(function))\"/>\n"
        }

        xml += "  </source>\n"
        xml += "</hostdev>"
        return xml
    }
}
