import Foundation
import VirtManagerCore

/// Holds all state for the VM creation wizard.
@Observable
public class VMCreationState {
    // Step 1: Name & OS
    public var name: String = ""
    public var osType: String = "linux"
    public var osVariant: String = ""

    // Step 2: CPU & Memory
    public var vcpus: Int = 2
    public var memoryMB: Int = 2048

    // Step 3: Storage
    public var createNewDisk: Bool = true
    public var diskSizeGB: Int = 20
    public var diskFormat: String = "qcow2"
    public var storagePool: String = "default"
    public var existingVolumePath: String = ""

    // Step 4: Network
    public var networkType: String = "network"
    public var networkSource: String = "default"
    public var nicModel: String = "virtio"

    // Step 5: Install source
    public var installSource: InstallSource = .none

    public enum InstallSource {
        case none
        case localISO(URL)
        case remoteISO(String)
        case networkURL(String)

        public var displayName: String {
            switch self {
            case .none: return "None"
            case .localISO(let url): return url.lastPathComponent
            case .remoteISO(let path): return (path as NSString).lastPathComponent
            case .networkURL(let url): return url
            }
        }
    }

    // Step 6: Options
    public var startAfterCreation: Bool = true

    public init() {
        applyOSDefaults()
    }

    /// Applies OS variant defaults to relevant fields.
    public func applyOSDefaults() {
        let variant = osVariant.isEmpty ? osType : osVariant
        let defs = OSVariants.defaults(for: variant)
        nicModel = defs.nicModel
    }

    /// Generates the libvirt domain XML for this configuration.
    public func generateDomainXML(diskPath: String?, isoPath: String?) -> String {
        let variant = osVariant.isEmpty ? osType : osVariant
        let defs = OSVariants.defaults(for: variant)
        let memoryKB = memoryMB * 1024

        var xml = """
        <domain type='kvm'>
          <name>\(escapeXML(name))</name>
          <memory unit='KiB'>\(memoryKB)</memory>
          <vcpu placement='static'>\(vcpus)</vcpu>
          <os>
            <type arch='x86_64' machine='\(defs.machineType)'>hvm</type>
        """

        if defs.firmware == "efi" {
            xml += "\n    <loader readonly='yes' type='pflash'>/usr/share/OVMF/OVMF_CODE.fd</loader>"
        }

        // Boot order: CDROM first if installing, then disk
        if isoPath != nil {
            xml += "\n    <boot dev='cdrom'/>"
        }
        xml += "\n    <boot dev='hd'/>"

        xml += """

          </os>
          <features>
            <acpi/>
            <apic/>
          </features>
          <clock offset='utc'>
            <timer name='rtc' tickpolicy='catchup'/>
            <timer name='pit' tickpolicy='delay'/>
            <timer name='hpet' present='no'/>
          </clock>
          <on_poweroff>destroy</on_poweroff>
          <on_reboot>restart</on_reboot>
          <on_crash>destroy</on_crash>
          <devices>
        """

        // Disk
        if let dp = diskPath {
            let diskDriver: String
            if dp.hasSuffix(".qcow2") {
                diskDriver = "qcow2"
            } else {
                diskDriver = "raw"
            }
            xml += """

            <disk type='file' device='disk'>
              <driver name='qemu' type='\(diskDriver)'/>
              <source file='\(escapeXML(dp))'/>
              <target dev='vda' bus='\(defs.diskBus)'/>
            </disk>
        """
        }

        // CDROM
        if let iso = isoPath {
            xml += """

            <disk type='file' device='cdrom'>
              <driver name='qemu' type='raw'/>
              <source file='\(escapeXML(iso))'/>
              <target dev='sda' bus='sata'/>
              <readonly/>
            </disk>
        """
        } else {
            xml += """

            <disk type='file' device='cdrom'>
              <driver name='qemu' type='raw'/>
              <target dev='sda' bus='sata'/>
              <readonly/>
            </disk>
        """
        }

        // Network
        if networkType == "bridge" {
            xml += """

            <interface type='bridge'>
              <source bridge='\(escapeXML(networkSource))'/>
              <model type='\(escapeXML(nicModel))'/>
            </interface>
        """
        } else {
            xml += """

            <interface type='network'>
              <source network='\(escapeXML(networkSource))'/>
              <model type='\(escapeXML(nicModel))'/>
            </interface>
        """
        }

        // Graphics + Video
        xml += """

            <graphics type='vnc' port='-1' autoport='yes' listen='127.0.0.1'>
              <listen type='address' address='127.0.0.1'/>
            </graphics>
            <video>
              <model type='\(defs.videoModel)'/>
            </video>
            <console type='pty'>
              <target type='serial' port='0'/>
            </console>
            <serial type='pty'>
              <target port='0'/>
            </serial>
            <input type='tablet' bus='usb'/>
            <input type='keyboard' bus='usb'/>
            <memballoon model='virtio'/>
          </devices>
        </domain>
        """

        return xml
    }

    private func escapeXML(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
         .replacingOccurrences(of: "<", with: "&lt;")
         .replacingOccurrences(of: ">", with: "&gt;")
         .replacingOccurrences(of: "'", with: "&apos;")
         .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
