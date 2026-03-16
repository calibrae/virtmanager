import Foundation

/// Represents the `<os>` section of a libvirt domain XML.
public struct BootConfig: Sendable {
    public var machineType: String?  // pc-q35-8.1, pc-i440fx-6.2, etc
    public var arch: String?         // x86_64, aarch64
    public var firmware: String?     // bios, efi
    public var bootDevices: [String] // ["hd", "cdrom", "network"]

    // Kernel boot (optional, for direct kernel boot)
    public var kernel: String?
    public var initrd: String?
    public var cmdline: String?

    public init(
        machineType: String? = nil,
        arch: String? = nil,
        firmware: String? = nil,
        bootDevices: [String] = ["hd"],
        kernel: String? = nil,
        initrd: String? = nil,
        cmdline: String? = nil
    ) {
        self.machineType = machineType
        self.arch = arch
        self.firmware = firmware
        self.bootDevices = bootDevices
        self.kernel = kernel
        self.initrd = initrd
        self.cmdline = cmdline
    }

    public init(from osElement: XMLElement, domainElement: XMLElement) {
        let typeEl = osElement.elements(forName: "type").first
        self.machineType = typeEl?.attribute(forName: "machine")?.stringValue
        self.arch = typeEl?.attribute(forName: "arch")?.stringValue

        // Firmware can come from <os firmware="efi"> or from <loader> presence
        if let fw = osElement.attribute(forName: "firmware")?.stringValue {
            self.firmware = fw
        } else if osElement.elements(forName: "loader").first != nil {
            self.firmware = "efi"
        } else {
            self.firmware = "bios"
        }

        self.bootDevices = osElement.elements(forName: "boot").compactMap {
            $0.attribute(forName: "dev")?.stringValue
        }

        self.kernel = osElement.elements(forName: "kernel").first?.stringValue
        self.initrd = osElement.elements(forName: "initrd").first?.stringValue
        self.cmdline = osElement.elements(forName: "cmdline").first?.stringValue
    }

    /// Applies this boot config back to the given `<os>` XMLElement, patching in place.
    public func apply(to osElement: XMLElement) {
        // Update <type> element attributes
        if let typeEl = osElement.elements(forName: "type").first {
            if let machine = machineType {
                typeEl.setAttributesWith(["machine": machine])
                // Preserve existing arch if we have one
                if let arch = arch {
                    if let existingArch = typeEl.attribute(forName: "arch") {
                        existingArch.stringValue = arch
                    } else {
                        typeEl.addAttribute(XMLNode.attribute(withName: "arch", stringValue: arch) as! XMLNode)
                    }
                }
                if let existingMachine = typeEl.attribute(forName: "machine") {
                    existingMachine.stringValue = machine
                }
            }
            if let arch = arch {
                if let existingArch = typeEl.attribute(forName: "arch") {
                    existingArch.stringValue = arch
                }
            }
        }

        // Update firmware attribute on <os>
        if let fw = firmware, fw == "efi" {
            if let existingFw = osElement.attribute(forName: "firmware") {
                existingFw.stringValue = fw
            } else {
                osElement.addAttribute(XMLNode.attribute(withName: "firmware", stringValue: fw) as! XMLNode)
            }
        } else {
            osElement.removeAttribute(forName: "firmware")
        }

        // Update boot devices: remove existing <boot> elements and re-add
        let existingBoots = osElement.elements(forName: "boot")
        for boot in existingBoots {
            osElement.removeChild(at: boot.index)
        }
        for dev in bootDevices {
            let bootEl = XMLElement(name: "boot")
            bootEl.addAttribute(XMLNode.attribute(withName: "dev", stringValue: dev) as! XMLNode)
            osElement.addChild(bootEl)
        }

        // Kernel boot elements
        updateOrRemoveChild(of: osElement, named: "kernel", value: kernel)
        updateOrRemoveChild(of: osElement, named: "initrd", value: initrd)
        updateOrRemoveChild(of: osElement, named: "cmdline", value: cmdline)
    }

    private func updateOrRemoveChild(of parent: XMLElement, named name: String, value: String?) {
        let existing = parent.elements(forName: name)
        for el in existing {
            parent.removeChild(at: el.index)
        }
        if let value = value {
            let el = XMLElement(name: name, stringValue: value)
            parent.addChild(el)
        }
    }
}
