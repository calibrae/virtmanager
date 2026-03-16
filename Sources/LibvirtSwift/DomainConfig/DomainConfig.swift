import Foundation

/// Root model representing a libvirt domain configuration parsed from XML.
///
/// The parser extracts known elements into typed properties while preserving
/// the full XMLDocument for round-trip fidelity. Unknown elements are never stripped.
public final class DomainConfig: @unchecked Sendable {
    public var name: String
    public var uuid: String
    public var title: String?
    public var description: String?

    // CPU
    public var vcpus: Int
    public var cpuMode: String?         // host-passthrough, host-model, custom
    public var cpuModel: String?
    public var topologySockets: Int?
    public var topologyCores: Int?
    public var topologyThreads: Int?

    // Memory (in KiB)
    public var memoryKiB: UInt64
    public var currentMemoryKiB: UInt64?

    // OS / Boot
    public var machineType: String?     // pc-q35-8.1, pc-i440fx-6.2, etc
    public var arch: String?            // x86_64, aarch64
    public var firmware: String?        // bios, efi
    public var bootDevices: [String]    // ["hd", "cdrom", "network"]

    // Devices
    public var disks: [DiskDevice]
    public var networkInterfaces: [NetworkDevice]
    public var graphics: [GraphicsDevice]
    public var videoDevices: [VideoDevice]
    public var inputDevices: [InputDevice]
    public var soundDevices: [SoundDevice]
    public var controllers: [ControllerDevice]
    public var serialPorts: [SerialDevice]

    /// The raw XMLDocument, kept for round-trip fidelity.
    public let xmlDocument: XMLDocument

    // MARK: - Parsing

    /// Parse a DomainConfig from a libvirt domain XML string.
    public init(xml: String) throws {
        let doc = try XMLDocument(xmlString: xml, options: [.nodePreserveWhitespace, .nodeLoadExternalEntitiesNever])
        self.xmlDocument = doc

        guard let root = doc.rootElement(), root.name == "domain" else {
            throw DomainConfigError.missingRootElement
        }

        // Basic identity
        self.name = root.elements(forName: "name").first?.stringValue ?? ""
        self.uuid = root.elements(forName: "uuid").first?.stringValue ?? ""
        self.title = root.elements(forName: "title").first?.stringValue
        self.description = root.elements(forName: "description").first?.stringValue

        // vCPUs
        let vcpuStr = root.elements(forName: "vcpu").first?.stringValue ?? "1"
        self.vcpus = Int(vcpuStr) ?? 1

        // CPU mode / model / topology
        if let cpuEl = root.elements(forName: "cpu").first {
            self.cpuMode = cpuEl.attribute(forName: "mode")?.stringValue
            self.cpuModel = cpuEl.elements(forName: "model").first?.stringValue
            if let topoEl = cpuEl.elements(forName: "topology").first {
                self.topologySockets = Int(topoEl.attribute(forName: "sockets")?.stringValue ?? "")
                self.topologyCores = Int(topoEl.attribute(forName: "cores")?.stringValue ?? "")
                self.topologyThreads = Int(topoEl.attribute(forName: "threads")?.stringValue ?? "")
            }
        }

        // Memory
        let memEl = root.elements(forName: "memory").first
        let memUnit = memEl?.attribute(forName: "unit")?.stringValue ?? "KiB"
        let memValue = UInt64(memEl?.stringValue ?? "0") ?? 0
        self.memoryKiB = DomainConfig.toKiB(memValue, unit: memUnit)

        if let curMemEl = root.elements(forName: "currentMemory").first {
            let curUnit = curMemEl.attribute(forName: "unit")?.stringValue ?? "KiB"
            let curValue = UInt64(curMemEl.stringValue ?? "0") ?? 0
            self.currentMemoryKiB = DomainConfig.toKiB(curValue, unit: curUnit)
        }

        // OS / Boot
        let osEl = root.elements(forName: "os").first
        let bootConfig = BootConfig(from: osEl ?? XMLElement(name: "os"),
                                     domainElement: root)
        self.machineType = bootConfig.machineType
        self.arch = bootConfig.arch
        self.firmware = bootConfig.firmware
        self.bootDevices = bootConfig.bootDevices

        // Devices
        let devicesEl = root.elements(forName: "devices").first
        self.disks = devicesEl?.elements(forName: "disk").map { DiskDevice(from: $0) } ?? []
        self.networkInterfaces = devicesEl?.elements(forName: "interface").map { NetworkDevice(from: $0) } ?? []
        self.graphics = devicesEl?.elements(forName: "graphics").map { GraphicsDevice(from: $0) } ?? []
        self.videoDevices = devicesEl?.elements(forName: "video").map { VideoDevice(from: $0) } ?? []
        self.inputDevices = devicesEl?.elements(forName: "input").map { InputDevice(from: $0) } ?? []
        self.soundDevices = devicesEl?.elements(forName: "sound").map { SoundDevice(from: $0) } ?? []
        self.controllers = devicesEl?.elements(forName: "controller").map { ControllerDevice(from: $0) } ?? []
        self.serialPorts = devicesEl?.elements(forName: "serial").map { SerialDevice(from: $0) } ?? []
    }

    // MARK: - XML Generation (round-trip)

    /// Generate XML string from the current state. Patches known properties back
    /// into the preserved XMLDocument so that unknown elements are never lost.
    public func toXML() throws -> String {
        guard let root = xmlDocument.rootElement() else {
            throw DomainConfigError.missingRootElement
        }

        // Patch basic identity
        setElementText(in: root, name: "name", value: name)
        setElementText(in: root, name: "uuid", value: uuid)
        setOptionalElementText(in: root, name: "title", value: title)
        setOptionalElementText(in: root, name: "description", value: description)

        // Patch vcpu
        setElementText(in: root, name: "vcpu", value: "\(vcpus)")

        // Patch CPU mode/model/topology
        patchCPU(in: root)

        // Patch memory
        patchMemory(in: root)

        // Patch OS / boot
        patchOS(in: root)

        // Patch devices
        patchDevices(in: root)

        return xmlDocument.xmlString(options: [.nodePrettyPrint])
    }

    // MARK: - Private Helpers

    private func setElementText(in parent: XMLElement, name: String, value: String) {
        if let el = parent.elements(forName: name).first {
            el.stringValue = value
        } else {
            parent.addChild(XMLElement(name: name, stringValue: value))
        }
    }

    private func setOptionalElementText(in parent: XMLElement, name: String, value: String?) {
        let existing = parent.elements(forName: name)
        if let value = value {
            if let el = existing.first {
                el.stringValue = value
            } else {
                parent.addChild(XMLElement(name: name, stringValue: value))
            }
        } else {
            for el in existing {
                parent.removeChild(at: el.index)
            }
        }
    }

    private func patchCPU(in root: XMLElement) {
        if cpuMode != nil || cpuModel != nil || topologySockets != nil {
            var cpuEl = root.elements(forName: "cpu").first
            if cpuEl == nil {
                cpuEl = XMLElement(name: "cpu")
                root.addChild(cpuEl!)
            }
            if let mode = cpuMode {
                if let existing = cpuEl!.attribute(forName: "mode") {
                    existing.stringValue = mode
                } else {
                    cpuEl!.addAttribute(XMLNode.attribute(withName: "mode", stringValue: mode) as! XMLNode)
                }
            }
            if let model = cpuModel {
                setElementText(in: cpuEl!, name: "model", value: model)
            }
            if let sockets = topologySockets, let cores = topologyCores, let threads = topologyThreads {
                // Remove existing topology
                for topo in cpuEl!.elements(forName: "topology") {
                    cpuEl!.removeChild(at: topo.index)
                }
                let topoEl = XMLElement(name: "topology")
                topoEl.addAttribute(XMLNode.attribute(withName: "sockets", stringValue: "\(sockets)") as! XMLNode)
                topoEl.addAttribute(XMLNode.attribute(withName: "cores", stringValue: "\(cores)") as! XMLNode)
                topoEl.addAttribute(XMLNode.attribute(withName: "threads", stringValue: "\(threads)") as! XMLNode)
                cpuEl!.addChild(topoEl)
            }
        }
    }

    private func patchMemory(in root: XMLElement) {
        if let memEl = root.elements(forName: "memory").first {
            memEl.stringValue = "\(memoryKiB)"
            if let unitAttr = memEl.attribute(forName: "unit") {
                unitAttr.stringValue = "KiB"
            } else {
                memEl.addAttribute(XMLNode.attribute(withName: "unit", stringValue: "KiB") as! XMLNode)
            }
        } else {
            let memEl = XMLElement(name: "memory", stringValue: "\(memoryKiB)")
            memEl.addAttribute(XMLNode.attribute(withName: "unit", stringValue: "KiB") as! XMLNode)
            root.addChild(memEl)
        }

        if let curMem = currentMemoryKiB {
            if let curEl = root.elements(forName: "currentMemory").first {
                curEl.stringValue = "\(curMem)"
                if let unitAttr = curEl.attribute(forName: "unit") {
                    unitAttr.stringValue = "KiB"
                } else {
                    curEl.addAttribute(XMLNode.attribute(withName: "unit", stringValue: "KiB") as! XMLNode)
                }
            } else {
                let curEl = XMLElement(name: "currentMemory", stringValue: "\(curMem)")
                curEl.addAttribute(XMLNode.attribute(withName: "unit", stringValue: "KiB") as! XMLNode)
                root.addChild(curEl)
            }
        }
    }

    private func patchOS(in root: XMLElement) {
        var osEl = root.elements(forName: "os").first
        if osEl == nil {
            osEl = XMLElement(name: "os")
            root.addChild(osEl!)
        }
        let boot = BootConfig(
            machineType: machineType,
            arch: arch,
            firmware: firmware,
            bootDevices: bootDevices
        )
        boot.apply(to: osEl!)
    }

    private func patchDevices(in root: XMLElement) {
        var devicesEl = root.elements(forName: "devices").first
        if devicesEl == nil {
            devicesEl = XMLElement(name: "devices")
            root.addChild(devicesEl!)
        }

        replaceDeviceElements(in: devicesEl!, named: "disk", with: disks.map { $0.toXML() })
        replaceDeviceElements(in: devicesEl!, named: "interface", with: networkInterfaces.map { $0.toXML() })
        replaceDeviceElements(in: devicesEl!, named: "graphics", with: graphics.map { $0.toXML() })
        replaceDeviceElements(in: devicesEl!, named: "video", with: videoDevices.map { $0.toXML() })
        replaceDeviceElements(in: devicesEl!, named: "input", with: inputDevices.map { $0.toXML() })
        replaceDeviceElements(in: devicesEl!, named: "sound", with: soundDevices.map { $0.toXML() })
        replaceDeviceElements(in: devicesEl!, named: "controller", with: controllers.map { $0.toXML() })
        replaceDeviceElements(in: devicesEl!, named: "serial", with: serialPorts.map { $0.toXML() })
    }

    private func replaceDeviceElements(in parent: XMLElement, named name: String, with xmlStrings: [String]) {
        // Remove existing elements of this type
        let existing = parent.elements(forName: name)
        // Remove in reverse order to maintain indices
        for el in existing.reversed() {
            parent.removeChild(at: el.index)
        }

        // Add new elements
        for xmlStr in xmlStrings {
            if let newDoc = try? XMLDocument(xmlString: xmlStr, options: [.nodeLoadExternalEntitiesNever]),
               let newEl = newDoc.rootElement() {
                newEl.detach()
                parent.addChild(newEl)
            }
        }
    }

    /// Convert a memory value to KiB given its unit string.
    static func toKiB(_ value: UInt64, unit: String) -> UInt64 {
        switch unit.lowercased() {
        case "b", "bytes":
            return value / 1024
        case "kb":
            return value * 1000 / 1024
        case "kib", "k":
            return value
        case "mb":
            return value * 1000 * 1000 / 1024
        case "mib", "m":
            return value * 1024
        case "gb":
            return value * 1000 * 1000 * 1000 / 1024
        case "gib", "g":
            return value * 1024 * 1024
        case "tb":
            return value * 1000 * 1000 * 1000 * 1000 / 1024
        case "tib", "t":
            return value * 1024 * 1024 * 1024
        default:
            return value
        }
    }
}

public enum DomainConfigError: Error, Sendable {
    case missingRootElement
    case invalidXML(String)
}
