import Foundation
import Testing
@testable import LibvirtSwift
@testable import VirtManagerCore

// MARK: - Mock XML Fixtures

/// Realistic domain XML fixtures for testing parsing, round-trip, and validation
/// without requiring a live libvirt connection.
private enum MockXML {

    static let runningVNCVM = """
    <domain type="kvm">
      <name>web-prod-01</name>
      <uuid>f47ac10b-58cc-4372-a567-0e02b2c3d479</uuid>
      <title>Web Production Server</title>
      <description>Nginx + Rails app server</description>
      <memory unit="GiB">8</memory>
      <currentMemory unit="GiB">8</currentMemory>
      <vcpu placement="static">4</vcpu>
      <cpu mode="host-passthrough">
        <topology sockets="1" cores="2" threads="2"/>
      </cpu>
      <os firmware="efi">
        <type arch="x86_64" machine="pc-q35-8.1">hvm</type>
        <boot dev="hd"/>
      </os>
      <features><acpi/><apic/></features>
      <devices>
        <disk type="file" device="disk">
          <driver name="qemu" type="qcow2"/>
          <source file="/var/lib/libvirt/images/web-prod-01.qcow2"/>
          <target dev="vda" bus="virtio"/>
        </disk>
        <interface type="network">
          <mac address="52:54:00:12:34:56"/>
          <source network="default"/>
          <model type="virtio"/>
        </interface>
        <interface type="bridge">
          <mac address="52:54:00:12:34:57"/>
          <source bridge="br0"/>
          <model type="e1000e"/>
        </interface>
        <graphics type="vnc" port="-1" autoport="yes" listen="127.0.0.1"/>
        <video><model type="qxl" vram="65536" heads="1"/></video>
        <serial type="pty"><target type="isa-serial" port="0"/></serial>
        <console type="pty"><target type="serial" port="0"/></console>
        <input type="tablet" bus="usb"/>
        <sound model="ich9"/>
        <controller type="pci" model="pcie-root" index="0"/>
        <controller type="usb" model="qemu-xhci" index="0"/>
        <controller type="scsi" model="virtio-scsi" index="0"/>
        <memballoon model="virtio"/>
      </devices>
    </domain>
    """

    static let shutOffSPICEVM = """
    <domain type="kvm">
      <name>dev-workstation</name>
      <uuid>550e8400-e29b-41d4-a716-446655440000</uuid>
      <memory unit="GiB">16</memory>
      <currentMemory unit="GiB">16</currentMemory>
      <vcpu placement="static">8</vcpu>
      <cpu mode="host-model"/>
      <os>
        <type arch="x86_64" machine="pc-q35-9.0">hvm</type>
        <boot dev="hd"/>
        <boot dev="cdrom"/>
      </os>
      <features><acpi/><apic/></features>
      <devices>
        <disk type="file" device="disk">
          <driver name="qemu" type="qcow2"/>
          <source file="/var/lib/libvirt/images/dev-workstation.qcow2"/>
          <target dev="vda" bus="virtio"/>
        </disk>
        <disk type="file" device="cdrom">
          <driver name="qemu" type="raw"/>
          <target dev="sda" bus="sata"/>
          <readonly/>
        </disk>
        <interface type="network">
          <mac address="52:54:00:aa:bb:cc"/>
          <source network="default"/>
          <model type="virtio"/>
        </interface>
        <graphics type="spice" port="-1" autoport="yes"/>
        <video><model type="virtio" vram="16384" heads="1"/></video>
        <serial type="pty"><target type="isa-serial" port="0"/></serial>
        <console type="pty"><target type="serial" port="0"/></console>
        <input type="tablet" bus="usb"/>
        <input type="keyboard" bus="virtio"/>
        <memballoon model="virtio"/>
      </devices>
    </domain>
    """

    static let headlessSerialOnlyVM = """
    <domain type="kvm">
      <name>dns-resolver</name>
      <uuid>6ba7b810-9dad-11d1-80b4-00c04fd430c8</uuid>
      <memory unit="MiB">512</memory>
      <currentMemory unit="MiB">512</currentMemory>
      <vcpu placement="static">1</vcpu>
      <os>
        <type arch="x86_64" machine="pc-i440fx-8.1">hvm</type>
        <boot dev="hd"/>
      </os>
      <devices>
        <disk type="file" device="disk">
          <driver name="qemu" type="raw"/>
          <source file="/var/lib/libvirt/images/dns.raw"/>
          <target dev="sda" bus="scsi"/>
        </disk>
        <interface type="bridge">
          <mac address="52:54:00:ff:ee:dd"/>
          <source bridge="br0"/>
          <model type="virtio"/>
        </interface>
        <serial type="pty"><target type="isa-serial" port="0"/></serial>
        <console type="pty"><target type="serial" port="0"/></console>
        <memballoon model="virtio"/>
      </devices>
    </domain>
    """

    static let windowsVM = """
    <domain type="kvm">
      <name>win11-test</name>
      <uuid>7c9e6679-7425-40de-944b-e07fc1f90ae7</uuid>
      <memory unit="GiB">8</memory>
      <currentMemory unit="GiB">8</currentMemory>
      <vcpu placement="static">4</vcpu>
      <cpu mode="host-passthrough">
        <topology sockets="1" cores="4" threads="1"/>
      </cpu>
      <os firmware="efi">
        <type arch="x86_64" machine="pc-q35-9.0">hvm</type>
        <boot dev="hd"/>
        <boot dev="cdrom"/>
      </os>
      <features><acpi/><apic/><hyperv mode="custom"><relaxed state="on"/><vapic state="on"/><spinlocks state="on" retries="8191"/></hyperv></features>
      <devices>
        <disk type="file" device="disk">
          <driver name="qemu" type="qcow2"/>
          <source file="/var/lib/libvirt/images/win11.qcow2"/>
          <target dev="sda" bus="sata"/>
        </disk>
        <disk type="file" device="cdrom">
          <driver name="qemu" type="raw"/>
          <source file="/var/lib/libvirt/images/virtio-win.iso"/>
          <target dev="sdb" bus="sata"/>
          <readonly/>
        </disk>
        <interface type="network">
          <mac address="52:54:00:11:22:33"/>
          <source network="default"/>
          <model type="e1000e"/>
        </interface>
        <graphics type="spice" port="-1" autoport="yes"/>
        <video><model type="qxl" vram="65536" heads="1"/></video>
        <input type="tablet" bus="usb"/>
        <sound model="ich9"/>
        <tpm model="tpm-crb"><backend type="emulator" version="2.0"/></tpm>
        <controller type="pci" model="pcie-root" index="0"/>
        <controller type="usb" model="qemu-xhci" index="0"/>
        <memballoon model="virtio"/>
      </devices>
    </domain>
    """

    /// All mock VMs as (xml, expectedState) pairs
    static let allDomains: [(xml: String, state: VMInfo.VMState)] = [
        (runningVNCVM, .running),
        (shutOffSPICEVM, .shutOff),
        (headlessSerialOnlyVM, .running),
        (windowsVM, .shutOff),
    ]
}

// MARK: - Domain Parsing Tests (replaces live connection tests)

@Suite("Mock Domain Parsing — Multi-VM Fleet")
struct MockDomainFleetTests {

    @Test("Parse all mock VMs without error")
    func parseAllMockVMs() throws {
        for (xml, _) in MockXML.allDomains {
            let config = try DomainConfig(xml: xml)
            #expect(!config.name.isEmpty)
            #expect(!config.uuid.isEmpty)
            #expect(config.vcpus > 0)
            #expect(config.memoryKiB > 0)
        }
    }

    @Test("VNC VM has expected configuration")
    func vncVMConfig() throws {
        let config = try DomainConfig(xml: MockXML.runningVNCVM)

        #expect(config.name == "web-prod-01")
        #expect(config.vcpus == 4)
        #expect(config.memoryKiB == 8_388_608) // 8 GiB
        #expect(config.machineType == "pc-q35-8.1")
        #expect(config.firmware == "efi")
        #expect(config.bootDevices == ["hd"])

        // Graphics
        #expect(config.graphics.count == 1)
        #expect(config.graphics[0].type == "vnc")

        // 2 NICs
        #expect(config.networkInterfaces.count == 2)
        #expect(config.networkInterfaces[0].type == "network")
        #expect(config.networkInterfaces[0].model == .virtio)
        #expect(config.networkInterfaces[1].type == "bridge")
        #expect(config.networkInterfaces[1].model == .e1000e)

        // Serial console present
        #expect(config.serialPorts.count == 1)
    }

    @Test("SPICE VM has expected configuration")
    func spiceVMConfig() throws {
        let config = try DomainConfig(xml: MockXML.shutOffSPICEVM)

        #expect(config.name == "dev-workstation")
        #expect(config.vcpus == 8)
        #expect(config.memoryKiB == 16_777_216) // 16 GiB
        #expect(config.graphics[0].type == "spice")
        #expect(config.bootDevices == ["hd", "cdrom"])

        // Has CDROM
        let cdroms = config.disks.filter { $0.device == "cdrom" }
        #expect(cdroms.count == 1)
        #expect(cdroms[0].isReadonly == true)
    }

    @Test("Headless VM has no graphics")
    func headlessVMNoGraphics() throws {
        let config = try DomainConfig(xml: MockXML.headlessSerialOnlyVM)

        #expect(config.name == "dns-resolver")
        #expect(config.graphics.isEmpty)
        #expect(config.serialPorts.count == 1)
        #expect(config.memoryKiB == 524_288) // 512 MiB
        #expect(config.machineType == "pc-i440fx-8.1")
    }

    @Test("Windows VM has SATA disks and TPM")
    func windowsVMConfig() throws {
        let config = try DomainConfig(xml: MockXML.windowsVM)

        #expect(config.name == "win11-test")
        #expect(config.disks[0].bus == .sata)
        #expect(config.networkInterfaces[0].model == .e1000e)

        // 2 disks (system + virtio-win ISO)
        #expect(config.disks.count == 2)
        #expect(config.disks[1].device == "cdrom")

        // TPM and HyperV features survive round-trip (unknown elements preserved)
        let outputXML = try config.toXML()
        #expect(outputXML.contains("tpm"))
        #expect(outputXML.contains("hyperv"))
    }
}

// MARK: - Round-Trip Fidelity Tests

@Suite("Mock Domain Round-Trip Fidelity")
struct MockRoundTripTests {

    @Test("All mock VMs survive XML round-trip")
    func allVMsRoundTrip() throws {
        for (xml, _) in MockXML.allDomains {
            let config = try DomainConfig(xml: xml)
            let outputXML = try config.toXML()
            let config2 = try DomainConfig(xml: outputXML)

            #expect(config2.name == config.name)
            #expect(config2.uuid == config.uuid)
            #expect(config2.vcpus == config.vcpus)
            #expect(config2.memoryKiB == config.memoryKiB)
            #expect(config2.disks.count == config.disks.count)
            #expect(config2.networkInterfaces.count == config.networkInterfaces.count)
            #expect(config2.graphics.count == config.graphics.count)
            #expect(config2.serialPorts.count == config.serialPorts.count)
        }
    }

    @Test("Unknown XML elements preserved across round-trip")
    func unknownElementsPreserved() throws {
        let config = try DomainConfig(xml: MockXML.runningVNCVM)
        let outputXML = try config.toXML()

        // These elements are not parsed into typed properties
        #expect(outputXML.contains("memballoon"))
        #expect(outputXML.contains("features"))
        #expect(outputXML.contains("acpi"))
        #expect(outputXML.contains("console"))
    }

    @Test("Modifications applied correctly in round-trip")
    func modificationsApplied() throws {
        let config = try DomainConfig(xml: MockXML.runningVNCVM)

        config.name = "web-prod-02"
        config.vcpus = 16
        config.memoryKiB = 33_554_432 // 32 GiB
        config.networkInterfaces[0].macAddress = "52:54:00:99:88:77"

        let outputXML = try config.toXML()
        let config2 = try DomainConfig(xml: outputXML)

        #expect(config2.name == "web-prod-02")
        #expect(config2.vcpus == 16)
        #expect(config2.memoryKiB == 33_554_432)
        #expect(config2.networkInterfaces[0].macAddress == "52:54:00:99:88:77")
    }
}

// MARK: - Validation Tests with Realistic Configs

@Suite("Mock Domain Validation — Realistic Scenarios")
struct MockValidationTests {

    @Test("All mock VMs pass validation with no errors")
    func allMockVMsValid() throws {
        for (xml, _) in MockXML.allDomains {
            let config = try DomainConfig(xml: xml)
            let issues = ConfigValidator.validate(config)
            let errors = issues.filter { $0.severity == .error }
            #expect(errors.isEmpty, "VM '\(config.name)' has validation errors: \(errors)")
        }
    }

    @Test("Dual-NIC VM validates both interfaces")
    func dualNICValidation() throws {
        let config = try DomainConfig(xml: MockXML.runningVNCVM)
        #expect(config.networkInterfaces.count == 2)

        let issues = ConfigValidator.validate(config)
        let macErrors = issues.filter { $0.field.contains("macAddress") && $0.severity == .error }
        #expect(macErrors.isEmpty)
    }

    @Test("Corrupt MAC on second NIC produces error")
    func corruptMACOnSecondNIC() throws {
        let config = try DomainConfig(xml: MockXML.runningVNCVM)
        config.networkInterfaces[1].macAddress = "invalid"

        let issues = ConfigValidator.validate(config)
        let macErrors = issues.filter { $0.field.contains("macAddress") && $0.severity == .error }
        #expect(!macErrors.isEmpty)
    }

    @Test("Windows VM topology is valid")
    func windowsTopologyValid() throws {
        let config = try DomainConfig(xml: MockXML.windowsVM)
        // 4 vcpus, topology 1*4*1 = 4 — should be valid
        #expect(config.vcpus == 4)
        #expect(config.topologySockets == 1)
        #expect(config.topologyCores == 4)
        #expect(config.topologyThreads == 1)

        let issues = ConfigValidator.validate(config)
        let topoErrors = issues.filter { $0.field == "cpu.topology" && $0.severity == .error }
        #expect(topoErrors.isEmpty)
    }

    @Test("SCSI disk on i440fx validates without error")
    func scsiOnI440fx() throws {
        let config = try DomainConfig(xml: MockXML.headlessSerialOnlyVM)
        #expect(config.machineType == "pc-i440fx-8.1")
        #expect(config.disks[0].bus == .scsi)

        let issues = ConfigValidator.validate(config)
        let diskErrors = issues.filter { $0.field.contains("disk") && $0.severity == .error }
        #expect(diskErrors.isEmpty)
    }
}

// MARK: - VMDomainInfo & VMState Tests

@Suite("VMInfo State Machine")
struct VMInfoStateTests {

    @Test("stateFromLibvirt maps all known states")
    func stateMapping() {
        // VIR_DOMAIN_RUNNING = 1
        #expect(VMDomainInfo.stateFromLibvirt(1) == .running)
        // VIR_DOMAIN_PAUSED = 3
        #expect(VMDomainInfo.stateFromLibvirt(3) == .paused)
        // VIR_DOMAIN_SHUTOFF = 5
        #expect(VMDomainInfo.stateFromLibvirt(5) == .shutOff)
        // VIR_DOMAIN_CRASHED = 6
        #expect(VMDomainInfo.stateFromLibvirt(6) == .crashed)
        // VIR_DOMAIN_PMSUSPENDED = 7
        #expect(VMDomainInfo.stateFromLibvirt(7) == .suspended)
        // Unknown states map to .unknown
        #expect(VMDomainInfo.stateFromLibvirt(99) == .unknown)
    }

    @Test("Running VM can shutdown, pause, force off, reboot, open console")
    func runningCapabilities() {
        let state = VMInfo.VMState.running
        #expect(state.canShutdown)
        #expect(state.canPause)
        #expect(state.canForceOff)
        #expect(state.canReboot)
        #expect(state.canOpenConsole)
        #expect(!state.canStart)
        #expect(!state.canResume)
    }

    @Test("Shut off VM can only start")
    func shutOffCapabilities() {
        let state = VMInfo.VMState.shutOff
        #expect(state.canStart)
        #expect(!state.canShutdown)
        #expect(!state.canPause)
        #expect(!state.canForceOff)
        #expect(!state.canReboot)
        #expect(!state.canOpenConsole)
        #expect(!state.canResume)
    }

    @Test("Paused VM can resume and force off")
    func pausedCapabilities() {
        let state = VMInfo.VMState.paused
        #expect(state.canResume)
        #expect(state.canForceOff)
        #expect(!state.canStart)
        #expect(!state.canShutdown)
        #expect(!state.canPause)
    }
}

// MARK: - XMLHelpers Tests

@Suite("XMLHelpers — Graphics & Serial Detection")
struct XMLHelpersTests {

    @Test("Detect VNC graphics type")
    func detectVNC() {
        let gfx = XMLHelpers.extractGraphicsType(from: MockXML.runningVNCVM)
        #expect(gfx == "vnc")
    }

    @Test("Detect SPICE graphics type")
    func detectSPICE() {
        let gfx = XMLHelpers.extractGraphicsType(from: MockXML.shutOffSPICEVM)
        #expect(gfx == "spice")
    }

    @Test("No graphics on headless VM")
    func detectNoGraphics() {
        let gfx = XMLHelpers.extractGraphicsType(from: MockXML.headlessSerialOnlyVM)
        #expect(gfx == nil)
    }

    @Test("Serial console detected on VNC VM")
    func serialOnVNCVM() {
        #expect(XMLHelpers.hasSerialConsole(in: MockXML.runningVNCVM))
    }

    @Test("Serial console detected on headless VM")
    func serialOnHeadless() {
        #expect(XMLHelpers.hasSerialConsole(in: MockXML.headlessSerialOnlyVM))
    }

    @Test("Serial console detected on SPICE VM")
    func serialOnSPICE() {
        #expect(XMLHelpers.hasSerialConsole(in: MockXML.shutOffSPICEVM))
    }
}

// MARK: - NetworkInfo Model Tests

@Suite("NetworkInfo Model")
struct NetworkInfoTests {

    @Test("NetworkInfo init stores all properties")
    func initProperties() {
        let net = NetworkInfo(
            name: "default",
            uuid: "a1b2c3d4-0000-0000-0000-000000000000",
            isActive: true,
            bridge: "virbr0",
            autostart: true
        )

        #expect(net.name == "default")
        #expect(net.uuid == "a1b2c3d4-0000-0000-0000-000000000000")
        #expect(net.isActive == true)
        #expect(net.bridge == "virbr0")
        #expect(net.autostart == true)
    }

    @Test("NetworkInfo with nil bridge")
    func nilBridge() {
        let net = NetworkInfo(
            name: "isolated-net",
            uuid: "00000000-0000-0000-0000-000000000001",
            isActive: false,
            bridge: nil,
            autostart: false
        )

        #expect(net.bridge == nil)
        #expect(net.isActive == false)
    }
}
