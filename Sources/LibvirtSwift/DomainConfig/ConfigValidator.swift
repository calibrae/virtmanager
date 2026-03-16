import Foundation

public struct ValidationIssue: Sendable {
    public enum Severity: Sendable {
        case error, warning, info
    }

    public let severity: Severity
    public let field: String
    public let message: String

    public init(severity: Severity, field: String, message: String) {
        self.severity = severity
        self.field = field
        self.message = message
    }
}

public struct ConfigValidator: Sendable {

    /// Validate a DomainConfig and return all issues found.
    public static func validate(_ config: DomainConfig) -> [ValidationIssue] {
        var issues = [ValidationIssue]()

        issues.append(contentsOf: validateCPUTopology(config))
        issues.append(contentsOf: validateMemory(config))
        issues.append(contentsOf: validateDisks(config))
        issues.append(contentsOf: validateNetworkInterfaces(config))
        issues.append(contentsOf: validateBootDevices(config))
        issues.append(contentsOf: validateMachineType(config))

        return issues
    }

    // MARK: - CPU Topology

    private static func validateCPUTopology(_ config: DomainConfig) -> [ValidationIssue] {
        var issues = [ValidationIssue]()

        if let sockets = config.topologySockets,
           let cores = config.topologyCores,
           let threads = config.topologyThreads {
            let product = sockets * cores * threads
            if product != config.vcpus {
                issues.append(ValidationIssue(
                    severity: .error,
                    field: "cpu.topology",
                    message: "Topology sockets(\(sockets)) x cores(\(cores)) x threads(\(threads)) = \(product), but vcpus = \(config.vcpus)"
                ))
            }
        }

        if config.vcpus <= 0 {
            issues.append(ValidationIssue(
                severity: .error,
                field: "vcpus",
                message: "vCPU count must be greater than zero"
            ))
        }

        return issues
    }

    // MARK: - Memory

    private static func validateMemory(_ config: DomainConfig) -> [ValidationIssue] {
        var issues = [ValidationIssue]()

        if config.memoryKiB == 0 {
            issues.append(ValidationIssue(
                severity: .error,
                field: "memory",
                message: "Memory must be greater than zero"
            ))
        }

        // 128 KiB minimum
        let minMemKiB: UInt64 = 128
        if config.memoryKiB > 0 && config.memoryKiB < minMemKiB {
            issues.append(ValidationIssue(
                severity: .error,
                field: "memory",
                message: "Memory \(config.memoryKiB) KiB is below the minimum of \(minMemKiB) KiB"
            ))
        }

        // 16 TiB upper bound
        let maxMemKiB: UInt64 = 16 * 1024 * 1024 * 1024 // 16 TiB in KiB
        if config.memoryKiB > maxMemKiB {
            issues.append(ValidationIssue(
                severity: .error,
                field: "memory",
                message: "Memory \(config.memoryKiB) KiB exceeds the maximum of 16 TiB"
            ))
        }

        if let curMem = config.currentMemoryKiB {
            if curMem > config.memoryKiB {
                issues.append(ValidationIssue(
                    severity: .error,
                    field: "currentMemory",
                    message: "currentMemory (\(curMem) KiB) must not exceed memory (\(config.memoryKiB) KiB)"
                ))
            }
        }

        return issues
    }

    // MARK: - Disks

    private static func validateDisks(_ config: DomainConfig) -> [ValidationIssue] {
        var issues = [ValidationIssue]()
        let isQ35 = config.machineType?.lowercased().contains("q35") ?? false
        let isI440fx = config.machineType?.lowercased().contains("i440fx") ?? false

        for (i, disk) in config.disks.enumerated() {
            let field = "disks[\(i)]"

            // IDE not supported on Q35
            if disk.bus == .ide && isQ35 {
                issues.append(ValidationIssue(
                    severity: .error,
                    field: "\(field).bus",
                    message: "IDE bus is not supported on Q35 machine types"
                ))
            }

            // Virtio needs guest drivers warning
            if disk.bus == .virtio {
                issues.append(ValidationIssue(
                    severity: .info,
                    field: "\(field).bus",
                    message: "Virtio disk bus requires guest drivers (built-in on Linux, may need manual install on Windows)"
                ))
            }

            // Target device naming conventions
            validateTargetDevNaming(disk: disk, index: i, issues: &issues)
        }

        // Machine type change warnings
        if isQ35 {
            let ideDisks = config.disks.filter { $0.bus == .ide }
            if !ideDisks.isEmpty {
                // Already covered above per-disk
            }
        }
        if isI440fx {
            // i440fx is the legacy type; warn if using PCIe features
            issues.append(ValidationIssue(
                severity: .info,
                field: "machineType",
                message: "i440fx machine type uses legacy PCI; consider Q35 for PCIe support"
            ))
        }

        return issues
    }

    private static func validateTargetDevNaming(disk: DiskDevice, index: Int, issues: inout [ValidationIssue]) {
        let field = "disks[\(index)].targetDev"
        let dev = disk.targetDev

        switch disk.bus {
        case .virtio:
            if !dev.hasPrefix("vd") {
                issues.append(ValidationIssue(
                    severity: .warning,
                    field: field,
                    message: "Virtio disks should use 'vd*' target device names (e.g., vda), got '\(dev)'"
                ))
            }
        case .ide:
            if !dev.hasPrefix("hd") {
                issues.append(ValidationIssue(
                    severity: .warning,
                    field: field,
                    message: "IDE disks should use 'hd*' target device names (e.g., hda), got '\(dev)'"
                ))
            }
        case .scsi, .sata:
            if !dev.hasPrefix("sd") {
                issues.append(ValidationIssue(
                    severity: .warning,
                    field: field,
                    message: "\(disk.bus.rawValue.uppercased()) disks should use 'sd*' target device names (e.g., sda), got '\(dev)'"
                ))
            }
        case .fdc:
            if !dev.hasPrefix("fd") {
                issues.append(ValidationIssue(
                    severity: .warning,
                    field: field,
                    message: "Floppy disks should use 'fd*' target device names (e.g., fda), got '\(dev)'"
                ))
            }
        case .usb:
            break // USB disks typically use sd* but it's flexible
        }
    }

    // MARK: - Network Interfaces

    private static func validateNetworkInterfaces(_ config: DomainConfig) -> [ValidationIssue] {
        var issues = [ValidationIssue]()

        for (i, nic) in config.networkInterfaces.enumerated() {
            let field = "networkInterfaces[\(i)]"

            if let mac = nic.macAddress {
                if !isValidMACAddress(mac) {
                    issues.append(ValidationIssue(
                        severity: .error,
                        field: "\(field).macAddress",
                        message: "Invalid MAC address format: '\(mac)'. Expected XX:XX:XX:XX:XX:XX"
                    ))
                }
            }
        }

        return issues
    }

    private static func isValidMACAddress(_ mac: String) -> Bool {
        let pattern = "^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$"
        return mac.range(of: pattern, options: .regularExpression) != nil
    }

    // MARK: - Boot Devices

    private static func validateBootDevices(_ config: DomainConfig) -> [ValidationIssue] {
        var issues = [ValidationIssue]()

        let validBootDevices = Set(["hd", "cdrom", "network", "fd"])
        for (i, dev) in config.bootDevices.enumerated() {
            if !validBootDevices.contains(dev) {
                issues.append(ValidationIssue(
                    severity: .warning,
                    field: "bootDevices[\(i)]",
                    message: "Unknown boot device type: '\(dev)'"
                ))
            }
        }

        // Check that boot device types have matching disks
        if config.bootDevices.contains("hd") && config.disks.filter({ $0.device == "disk" }).isEmpty {
            issues.append(ValidationIssue(
                severity: .warning,
                field: "bootDevices",
                message: "Boot order includes 'hd' but no disk devices are defined"
            ))
        }

        if config.bootDevices.contains("cdrom") && config.disks.filter({ $0.device == "cdrom" }).isEmpty {
            issues.append(ValidationIssue(
                severity: .warning,
                field: "bootDevices",
                message: "Boot order includes 'cdrom' but no CDROM devices are defined"
            ))
        }

        return issues
    }

    // MARK: - Machine Type

    private static func validateMachineType(_ config: DomainConfig) -> [ValidationIssue] {
        var issues = [ValidationIssue]()

        let isQ35 = config.machineType?.lowercased().contains("q35") ?? false

        // Warn about IDE controllers on Q35
        if isQ35 {
            let ideControllers = config.controllers.filter { $0.type == "ide" }
            if !ideControllers.isEmpty {
                issues.append(ValidationIssue(
                    severity: .warning,
                    field: "controllers",
                    message: "Q35 machine type does not natively support IDE controllers"
                ))
            }
        }

        return issues
    }
}
