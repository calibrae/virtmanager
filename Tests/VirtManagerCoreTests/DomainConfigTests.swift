import Foundation
import Testing
@testable import LibvirtSwift

// A realistic libvirt domain XML for testing
private let sampleDomainXML = """
<domain type="kvm">
  <name>ubuntu-22.04</name>
  <uuid>a1b2c3d4-e5f6-7890-abcd-ef1234567890</uuid>
  <title>Ubuntu 22.04 Server</title>
  <description>Development VM</description>
  <memory unit="GiB">4</memory>
  <currentMemory unit="GiB">4</currentMemory>
  <vcpu placement="static">4</vcpu>
  <cpu mode="host-passthrough">
    <topology sockets="1" cores="2" threads="2"/>
  </cpu>
  <os firmware="efi">
    <type arch="x86_64" machine="pc-q35-8.1">hvm</type>
    <boot dev="hd"/>
    <boot dev="cdrom"/>
  </os>
  <features>
    <acpi/>
    <apic/>
  </features>
  <devices>
    <disk type="file" device="disk">
      <driver name="qemu" type="qcow2"/>
      <source file="/var/lib/libvirt/images/ubuntu.qcow2"/>
      <target dev="vda" bus="virtio"/>
    </disk>
    <disk type="file" device="cdrom">
      <driver name="qemu" type="raw"/>
      <source file="/var/lib/libvirt/images/ubuntu-22.04.iso"/>
      <target dev="sda" bus="sata"/>
      <readonly/>
    </disk>
    <interface type="network">
      <mac address="52:54:00:ab:cd:ef"/>
      <source network="default"/>
      <model type="virtio"/>
    </interface>
    <graphics type="vnc" port="-1" autoport="yes" listen="127.0.0.1"/>
    <video>
      <model type="virtio" vram="16384" heads="1"/>
    </video>
    <input type="tablet" bus="usb"/>
    <input type="keyboard" bus="virtio"/>
    <sound model="ich9"/>
    <controller type="pci" model="pcie-root" index="0"/>
    <controller type="usb" model="qemu-xhci" index="0"/>
    <serial type="pty">
      <target type="isa-serial" port="0"/>
    </serial>
    <console type="pty">
      <target type="serial" port="0"/>
    </console>
    <memballoon model="virtio"/>
  </devices>
</domain>
"""

@Suite("DomainConfig Parsing Tests")
struct DomainConfigParsingTests {

    @Test("Parse basic domain properties")
    func parseBasicProperties() throws {
        let config = try DomainConfig(xml: sampleDomainXML)

        #expect(config.name == "ubuntu-22.04")
        #expect(config.uuid == "a1b2c3d4-e5f6-7890-abcd-ef1234567890")
        #expect(config.title == "Ubuntu 22.04 Server")
        #expect(config.description == "Development VM")
    }

    @Test("Parse CPU configuration")
    func parseCPU() throws {
        let config = try DomainConfig(xml: sampleDomainXML)

        #expect(config.vcpus == 4)
        #expect(config.cpuMode == "host-passthrough")
        #expect(config.topologySockets == 1)
        #expect(config.topologyCores == 2)
        #expect(config.topologyThreads == 2)
    }

    @Test("Parse memory configuration")
    func parseMemory() throws {
        let config = try DomainConfig(xml: sampleDomainXML)

        // 4 GiB = 4 * 1024 * 1024 KiB = 4194304 KiB
        #expect(config.memoryKiB == 4_194_304)
        #expect(config.currentMemoryKiB == 4_194_304)
    }

    @Test("Parse OS and boot config")
    func parseOSBoot() throws {
        let config = try DomainConfig(xml: sampleDomainXML)

        #expect(config.machineType == "pc-q35-8.1")
        #expect(config.arch == "x86_64")
        #expect(config.firmware == "efi")
        #expect(config.bootDevices == ["hd", "cdrom"])
    }

    @Test("Parse disk devices")
    func parseDisks() throws {
        let config = try DomainConfig(xml: sampleDomainXML)

        #expect(config.disks.count == 2)

        let disk0 = config.disks[0]
        #expect(disk0.type == "file")
        #expect(disk0.device == "disk")
        #expect(disk0.driver == "qemu")
        #expect(disk0.format == "qcow2")
        #expect(disk0.sourcePath == "/var/lib/libvirt/images/ubuntu.qcow2")
        #expect(disk0.targetDev == "vda")
        #expect(disk0.bus == .virtio)
        #expect(disk0.isReadonly == false)

        let disk1 = config.disks[1]
        #expect(disk1.device == "cdrom")
        #expect(disk1.bus == .sata)
        #expect(disk1.isReadonly == true)
    }

    @Test("Parse network interfaces")
    func parseNetworkInterfaces() throws {
        let config = try DomainConfig(xml: sampleDomainXML)

        #expect(config.networkInterfaces.count == 1)
        let nic = config.networkInterfaces[0]
        #expect(nic.type == "network")
        #expect(nic.sourceName == "default")
        #expect(nic.macAddress == "52:54:00:ab:cd:ef")
        #expect(nic.model == .virtio)
    }

    @Test("Parse graphics devices")
    func parseGraphics() throws {
        let config = try DomainConfig(xml: sampleDomainXML)

        #expect(config.graphics.count == 1)
        let gfx = config.graphics[0]
        #expect(gfx.type == "vnc")
        #expect(gfx.port == -1)
        #expect(gfx.autoport == true)
        #expect(gfx.listenAddress == "127.0.0.1")
    }

    @Test("Parse video devices")
    func parseVideoDevices() throws {
        let config = try DomainConfig(xml: sampleDomainXML)

        #expect(config.videoDevices.count == 1)
        #expect(config.videoDevices[0].modelType == "virtio")
        #expect(config.videoDevices[0].vram == 16384)
        #expect(config.videoDevices[0].heads == 1)
    }

    @Test("Parse input devices")
    func parseInputDevices() throws {
        let config = try DomainConfig(xml: sampleDomainXML)

        #expect(config.inputDevices.count == 2)
        #expect(config.inputDevices[0].type == "tablet")
        #expect(config.inputDevices[0].bus == "usb")
        #expect(config.inputDevices[1].type == "keyboard")
        #expect(config.inputDevices[1].bus == "virtio")
    }

    @Test("Parse sound devices")
    func parseSoundDevices() throws {
        let config = try DomainConfig(xml: sampleDomainXML)

        #expect(config.soundDevices.count == 1)
        #expect(config.soundDevices[0].model == "ich9")
    }

    @Test("Parse controllers")
    func parseControllers() throws {
        let config = try DomainConfig(xml: sampleDomainXML)

        #expect(config.controllers.count == 2)
        #expect(config.controllers[0].type == "pci")
        #expect(config.controllers[0].model == "pcie-root")
        #expect(config.controllers[0].index == 0)
        #expect(config.controllers[1].type == "usb")
    }

    @Test("Parse serial ports")
    func parseSerialPorts() throws {
        let config = try DomainConfig(xml: sampleDomainXML)

        #expect(config.serialPorts.count == 1)
        #expect(config.serialPorts[0].type == "pty")
        #expect(config.serialPorts[0].targetType == "isa-serial")
        #expect(config.serialPorts[0].targetPort == 0)
    }
}

@Suite("DomainConfig Round-Trip Tests")
struct DomainConfigRoundTripTests {

    @Test("Round-trip preserves basic properties")
    func roundTripBasicProperties() throws {
        let config = try DomainConfig(xml: sampleDomainXML)
        let outputXML = try config.toXML()
        let config2 = try DomainConfig(xml: outputXML)

        #expect(config2.name == config.name)
        #expect(config2.uuid == config.uuid)
        #expect(config2.title == config.title)
        #expect(config2.description == config.description)
        #expect(config2.vcpus == config.vcpus)
        #expect(config2.memoryKiB == config.memoryKiB)
        #expect(config2.machineType == config.machineType)
        #expect(config2.arch == config.arch)
        #expect(config2.bootDevices == config.bootDevices)
    }

    @Test("Round-trip preserves devices")
    func roundTripDevices() throws {
        let config = try DomainConfig(xml: sampleDomainXML)
        let outputXML = try config.toXML()
        let config2 = try DomainConfig(xml: outputXML)

        #expect(config2.disks.count == config.disks.count)
        #expect(config2.networkInterfaces.count == config.networkInterfaces.count)
        #expect(config2.graphics.count == config.graphics.count)
        #expect(config2.videoDevices.count == config.videoDevices.count)
        #expect(config2.inputDevices.count == config.inputDevices.count)
        #expect(config2.soundDevices.count == config.soundDevices.count)
        #expect(config2.controllers.count == config.controllers.count)
        #expect(config2.serialPorts.count == config.serialPorts.count)
    }

    @Test("Round-trip preserves unknown elements")
    func roundTripPreservesUnknownElements() throws {
        let config = try DomainConfig(xml: sampleDomainXML)
        let outputXML = try config.toXML()

        // <features>, <acpi/>, <apic/>, <console>, and <memballoon> are not
        // parsed into typed properties but must survive the round-trip
        #expect(outputXML.contains("features"))
        #expect(outputXML.contains("acpi"))
        #expect(outputXML.contains("apic"))
        #expect(outputXML.contains("console"))
        #expect(outputXML.contains("memballoon"))
    }

    @Test("Modifications are reflected in output XML")
    func modificationsReflected() throws {
        let config = try DomainConfig(xml: sampleDomainXML)
        config.name = "modified-vm"
        config.vcpus = 8
        config.memoryKiB = 8_388_608 // 8 GiB

        let outputXML = try config.toXML()
        let config2 = try DomainConfig(xml: outputXML)

        #expect(config2.name == "modified-vm")
        #expect(config2.vcpus == 8)
        #expect(config2.memoryKiB == 8_388_608)
    }
}

@Suite("ConfigValidator Tests")
struct ConfigValidatorTests {

    @Test("Valid config produces no errors")
    func validConfigNoErrors() throws {
        let config = try DomainConfig(xml: sampleDomainXML)
        let issues = ConfigValidator.validate(config)
        let errors = issues.filter { $0.severity == .error }
        #expect(errors.isEmpty)
    }

    @Test("CPU topology mismatch produces error")
    func cpuTopologyMismatch() throws {
        let config = try DomainConfig(xml: sampleDomainXML)
        // vcpus = 4, topology = 1 * 2 * 2 = 4 -- currently valid
        // Change vcpus to 6 to create mismatch
        config.vcpus = 6
        let issues = ConfigValidator.validate(config)
        let topoErrors = issues.filter { $0.field == "cpu.topology" && $0.severity == .error }
        #expect(!topoErrors.isEmpty)
    }

    @Test("Zero memory produces error")
    func zeroMemory() throws {
        let config = try DomainConfig(xml: sampleDomainXML)
        config.memoryKiB = 0
        let issues = ConfigValidator.validate(config)
        let memErrors = issues.filter { $0.field == "memory" && $0.severity == .error }
        #expect(!memErrors.isEmpty)
    }

    @Test("currentMemory exceeding memory produces error")
    func currentMemoryExceedsMemory() throws {
        let config = try DomainConfig(xml: sampleDomainXML)
        config.currentMemoryKiB = config.memoryKiB + 1024
        let issues = ConfigValidator.validate(config)
        let curMemErrors = issues.filter { $0.field == "currentMemory" && $0.severity == .error }
        #expect(!curMemErrors.isEmpty)
    }

    @Test("IDE on Q35 produces error")
    func ideOnQ35() throws {
        let config = try DomainConfig(xml: sampleDomainXML)
        // Machine is already Q35, add an IDE disk
        config.disks.append(DiskDevice(
            type: "file",
            device: "disk",
            targetDev: "hda",
            bus: .ide
        ))
        let issues = ConfigValidator.validate(config)
        let ideErrors = issues.filter { $0.message.contains("IDE") && $0.severity == .error }
        #expect(!ideErrors.isEmpty)
    }

    @Test("Invalid target device naming produces warning")
    func invalidTargetDevNaming() throws {
        let config = try DomainConfig(xml: sampleDomainXML)
        // First disk is virtio with targetDev "vda" - correct
        // Change it to "sda" which is wrong for virtio
        config.disks[0].targetDev = "sda"
        let issues = ConfigValidator.validate(config)
        let namingWarnings = issues.filter {
            $0.field.contains("targetDev") && $0.severity == .warning
        }
        #expect(!namingWarnings.isEmpty)
    }

    @Test("Invalid MAC address produces error")
    func invalidMACAddress() throws {
        let config = try DomainConfig(xml: sampleDomainXML)
        config.networkInterfaces[0].macAddress = "not-a-mac"
        let issues = ConfigValidator.validate(config)
        let macErrors = issues.filter { $0.field.contains("macAddress") && $0.severity == .error }
        #expect(!macErrors.isEmpty)
    }

    @Test("Valid MAC address produces no error")
    func validMACAddress() throws {
        let config = try DomainConfig(xml: sampleDomainXML)
        config.networkInterfaces[0].macAddress = "52:54:00:AB:CD:EF"
        let issues = ConfigValidator.validate(config)
        let macErrors = issues.filter { $0.field.contains("macAddress") && $0.severity == .error }
        #expect(macErrors.isEmpty)
    }

    @Test("Boot device with no matching disk produces warning")
    func bootDeviceNoMatchingDisk() throws {
        let config = try DomainConfig(xml: sampleDomainXML)
        // Remove all disks but keep boot order referencing hd
        config.disks.removeAll()
        let issues = ConfigValidator.validate(config)
        let bootWarnings = issues.filter { $0.field == "bootDevices" && $0.severity == .warning }
        #expect(!bootWarnings.isEmpty)
    }

    @Test("Memory below minimum produces error")
    func memoryBelowMinimum() throws {
        let config = try DomainConfig(xml: sampleDomainXML)
        config.memoryKiB = 64 // below 128 KiB minimum
        let issues = ConfigValidator.validate(config)
        let memErrors = issues.filter { $0.field == "memory" && $0.severity == .error }
        #expect(!memErrors.isEmpty)
    }
}
