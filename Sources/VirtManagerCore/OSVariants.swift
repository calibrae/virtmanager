import Foundation

/// Recommended defaults for a given OS variant (no libosinfo dependency).
public struct OSVariantDefaults: Sendable {
    public let diskBus: String
    public let nicModel: String
    public let videoModel: String
    public let machineType: String
    public let firmware: String

    public init(diskBus: String, nicModel: String, videoModel: String, machineType: String, firmware: String) {
        self.diskBus = diskBus
        self.nicModel = nicModel
        self.videoModel = videoModel
        self.machineType = machineType
        self.firmware = firmware
    }
}

/// Simple lookup table of common OS variants and their recommended VM defaults.
public enum OSVariants {

    /// All known variant identifiers.
    public static let allVariants: [(id: String, label: String, osType: String)] = [
        ("fedora", "Fedora", "linux"),
        ("ubuntu", "Ubuntu", "linux"),
        ("debian", "Debian", "linux"),
        ("centos", "CentOS", "linux"),
        ("rhel", "Red Hat Enterprise Linux", "linux"),
        ("generic-linux", "Generic Linux", "linux"),
        ("windows10", "Windows 10", "windows"),
        ("windows11", "Windows 11", "windows"),
        ("generic-windows", "Generic Windows", "windows"),
        ("freebsd", "FreeBSD", "bsd"),
    ]

    /// Returns recommended defaults for the given OS variant identifier.
    public static func defaults(for variant: String) -> OSVariantDefaults {
        switch variant {
        case "fedora", "ubuntu", "debian", "centos", "rhel", "generic-linux":
            return OSVariantDefaults(
                diskBus: "virtio",
                nicModel: "virtio",
                videoModel: "virtio",
                machineType: "q35",
                firmware: "bios"
            )
        case "windows10":
            return OSVariantDefaults(
                diskBus: "sata",
                nicModel: "e1000e",
                videoModel: "qxl",
                machineType: "q35",
                firmware: "efi"
            )
        case "windows11":
            return OSVariantDefaults(
                diskBus: "virtio",
                nicModel: "e1000e",
                videoModel: "qxl",
                machineType: "q35",
                firmware: "efi"
            )
        case "generic-windows":
            return OSVariantDefaults(
                diskBus: "sata",
                nicModel: "e1000e",
                videoModel: "qxl",
                machineType: "q35",
                firmware: "efi"
            )
        case "freebsd":
            return OSVariantDefaults(
                diskBus: "virtio",
                nicModel: "virtio",
                videoModel: "virtio",
                machineType: "q35",
                firmware: "bios"
            )
        default:
            return OSVariantDefaults(
                diskBus: "virtio",
                nicModel: "virtio",
                videoModel: "virtio",
                machineType: "q35",
                firmware: "bios"
            )
        }
    }

    /// Returns the variants that match a given OS type string.
    public static func variants(forOSType osType: String) -> [(id: String, label: String)] {
        allVariants
            .filter { $0.osType == osType }
            .map { (id: $0.id, label: $0.label) }
    }
}
