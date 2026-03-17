import Darwin
import Foundation

// MARK: - Network Validation

extension ConfigValidator {

    /// Validate a NetworkConfig and return all issues found.
    public static func validate(_ config: NetworkConfig) -> [ValidationIssue] {
        var issues = [ValidationIssue]()

        issues.append(contentsOf: validateNetworkName(config))
        issues.append(contentsOf: validateForwardMode(config))
        issues.append(contentsOf: validateIPConfigs(config))
        issues.append(contentsOf: validateDNS(config))
        issues.append(contentsOf: validatePortForwarding(config))

        return issues
    }

    // MARK: - Network Name

    nonisolated(unsafe) private static let namePattern = /^[a-zA-Z0-9._-]{1,50}$/
    nonisolated(unsafe) private static let devicePattern = /^[a-zA-Z0-9._-]{1,15}$/

    private static func validateNetworkName(_ config: NetworkConfig) -> [ValidationIssue] {
        var issues = [ValidationIssue]()

        let name = config.name.trimmingCharacters(in: .whitespaces)
        if name.isEmpty {
            issues.append(ValidationIssue(
                severity: .error,
                field: "name",
                message: "Network name must not be empty"
            ))
        } else if name.wholeMatch(of: namePattern) == nil {
            issues.append(ValidationIssue(
                severity: .error,
                field: "name",
                message: "Network name must be 1-50 characters: letters, digits, hyphens, underscores, dots"
            ))
        }

        return issues
    }

    // MARK: - Forward Mode

    private static func validateForwardMode(_ config: NetworkConfig) -> [ValidationIssue] {
        var issues = [ValidationIssue]()
        let forward = config.forward

        // Bridge mode: bridge name required and format-checked
        if forward.mode.requiresBridgeName {
            let bn = forward.bridgeName?.trimmingCharacters(in: .whitespaces) ?? ""
            if bn.isEmpty {
                issues.append(ValidationIssue(
                    severity: .error,
                    field: "forward.bridgeName",
                    message: "Bridge mode requires a bridge device name"
                ))
            } else if bn.wholeMatch(of: devicePattern) == nil {
                issues.append(ValidationIssue(
                    severity: .error,
                    field: "forward.bridgeName",
                    message: "Bridge name must be 1-15 characters: letters, digits, hyphens, underscores, dots"
                ))
            }
        }

        // Macvtap modes: physical device required and format-checked
        if forward.mode.requiresPhysicalDevice {
            let dev = forward.dev?.trimmingCharacters(in: .whitespaces) ?? ""
            let hasInterfaces = !forward.interfaces.isEmpty
            if dev.isEmpty && !hasInterfaces {
                issues.append(ValidationIssue(
                    severity: .error,
                    field: "forward.dev",
                    message: "\(forward.mode.rawValue) mode requires a physical device or interface list"
                ))
            } else if !dev.isEmpty, dev.wholeMatch(of: devicePattern) == nil {
                issues.append(ValidationIssue(
                    severity: .error,
                    field: "forward.dev",
                    message: "Device name must be 1-15 characters: letters, digits, hyphens, underscores, dots"
                ))
            }
        }

        // Isolated mode: no port forwarding allowed
        if forward.mode == .isolated && !config.portForwarding.rules.isEmpty {
            issues.append(ValidationIssue(
                severity: .error,
                field: "portForwarding",
                message: "Port forwarding is not supported in isolated mode"
            ))
        }

        // At least one IP config for modes that support it
        if forward.mode.supportsIPConfig && config.ipConfigs.isEmpty {
            issues.append(ValidationIssue(
                severity: .warning,
                field: "ipConfigs",
                message: "No IP configuration defined; most \(forward.mode.rawValue) networks need at least one"
            ))
        }

        return issues
    }

    // MARK: - IP Configs

    private static func validateIPConfigs(_ config: NetworkConfig) -> [ValidationIssue] {
        var issues = [ValidationIssue]()

        for (i, ip) in config.ipConfigs.enumerated() {
            let field = "ipConfigs[\(i)]"

            switch ip.family {
            case .ipv4:
                issues.append(contentsOf: validateIPv4Config(ip, field: field))
            case .ipv6:
                issues.append(contentsOf: validateIPv6Config(ip, field: field))
            }

            // DHCP validation (common to both families)
            if ip.dhcpEnabled {
                issues.append(contentsOf: validateDHCP(ip, field: field))
            }
        }

        return issues
    }

    private static func validateIPv4Config(_ ip: IPConfig, field: String) -> [ValidationIssue] {
        var issues = [ValidationIssue]()

        // Validate address format
        if !ip.address.isEmpty && !isValidIPv4(ip.address) {
            issues.append(ValidationIssue(
                severity: .error,
                field: "\(field).address",
                message: "Invalid IPv4 address: '\(ip.address)'"
            ))
        }

        // Validate netmask / prefix
        if let netmask = ip.netmask {
            if !isValidIPv4(netmask) {
                issues.append(ValidationIssue(
                    severity: .error,
                    field: "\(field).netmask",
                    message: "Invalid IPv4 netmask: '\(netmask)'"
                ))
            }
        }

        if let prefix = ip.prefix {
            if prefix < 1 || prefix > 32 {
                issues.append(ValidationIssue(
                    severity: .error,
                    field: "\(field).prefix",
                    message: "IPv4 prefix must be between 1 and 32, got \(prefix)"
                ))
            }
        }

        return issues
    }

    private static func validateIPv6Config(_ ip: IPConfig, field: String) -> [ValidationIssue] {
        var issues = [ValidationIssue]()

        if !ip.address.isEmpty && !isValidIPv6(ip.address) {
            issues.append(ValidationIssue(
                severity: .error,
                field: "\(field).address",
                message: "Invalid IPv6 address: '\(ip.address)'"
            ))
        }

        if let prefix = ip.prefix {
            if prefix < 1 || prefix > 128 {
                issues.append(ValidationIssue(
                    severity: .error,
                    field: "\(field).prefix",
                    message: "IPv6 prefix must be between 1 and 128, got \(prefix)"
                ))
            }
        }

        return issues
    }

    // MARK: - DHCP Validation

    private static func validateDHCP(_ ip: IPConfig, field: String) -> [ValidationIssue] {
        var issues = [ValidationIssue]()
        let isV4 = ip.family == .ipv4

        // Compute subnet info for containment checks
        let subnetInfo: (network: UInt32, mask: UInt32)? = {
            guard isV4, !ip.address.isEmpty, isValidIPv4(ip.address) else { return nil }
            let prefixLen: Int
            if let p = ip.prefix {
                prefixLen = p
            } else if let nm = ip.netmask, let maskVal = ipv4ToUInt32(nm) {
                prefixLen = netmaskToPrefixLength(maskVal)
            } else {
                return nil
            }
            guard let addr = ipv4ToUInt32(ip.address) else { return nil }
            let mask = prefixLen == 0 ? UInt32(0) : ~UInt32(0) << (32 - prefixLen)
            return (addr & mask, mask)
        }()

        // Validate DHCP ranges
        for (j, range) in ip.dhcpRanges.enumerated() {
            let rField = "\(field).dhcpRanges[\(j)]"

            let startValid: Bool
            let endValid: Bool

            if isV4 {
                startValid = isValidIPv4(range.start)
                endValid = isValidIPv4(range.end)

                if !range.start.isEmpty && !startValid {
                    issues.append(ValidationIssue(
                        severity: .error,
                        field: "\(rField).start",
                        message: "Invalid IPv4 address for DHCP range start: '\(range.start)'"
                    ))
                }
                if !range.end.isEmpty && !endValid {
                    issues.append(ValidationIssue(
                        severity: .error,
                        field: "\(rField).end",
                        message: "Invalid IPv4 address for DHCP range end: '\(range.end)'"
                    ))
                }

                // start <= end
                if startValid && endValid,
                   let s = ipv4ToUInt32(range.start),
                   let e = ipv4ToUInt32(range.end) {
                    if s > e {
                        issues.append(ValidationIssue(
                            severity: .error,
                            field: rField,
                            message: "DHCP range start (\(range.start)) is greater than end (\(range.end))"
                        ))
                    }

                    // Within subnet
                    if let info = subnetInfo {
                        if (s & info.mask) != info.network {
                            issues.append(ValidationIssue(
                                severity: .error,
                                field: "\(rField).start",
                                message: "DHCP range start (\(range.start)) is not within the configured subnet"
                            ))
                        }
                        if (e & info.mask) != info.network {
                            issues.append(ValidationIssue(
                                severity: .error,
                                field: "\(rField).end",
                                message: "DHCP range end (\(range.end)) is not within the configured subnet"
                            ))
                        }
                    }
                }
            } else {
                startValid = isValidIPv6(range.start)
                endValid = isValidIPv6(range.end)

                if !range.start.isEmpty && !startValid {
                    issues.append(ValidationIssue(
                        severity: .error,
                        field: "\(rField).start",
                        message: "Invalid IPv6 address for DHCP range start: '\(range.start)'"
                    ))
                }
                if !range.end.isEmpty && !endValid {
                    issues.append(ValidationIssue(
                        severity: .error,
                        field: "\(rField).end",
                        message: "Invalid IPv6 address for DHCP range end: '\(range.end)'"
                    ))
                }
            }
        }

        // Validate static hosts
        for (j, host) in ip.dhcpHosts.enumerated() {
            let hField = "\(field).dhcpHosts[\(j)]"

            // MAC address format (required for IPv4)
            if isV4 {
                if let mac = host.mac, !mac.isEmpty {
                    if !isValidMACAddress(mac) {
                        issues.append(ValidationIssue(
                            severity: .error,
                            field: "\(hField).mac",
                            message: "Invalid MAC address format: '\(mac)'. Expected XX:XX:XX:XX:XX:XX"
                        ))
                    }
                }
            }

            // Validate host IP
            let hostIPValid: Bool
            if isV4 {
                hostIPValid = isValidIPv4(host.ip)
                if !host.ip.isEmpty && !hostIPValid {
                    issues.append(ValidationIssue(
                        severity: .error,
                        field: "\(hField).ip",
                        message: "Invalid IPv4 address for static host: '\(host.ip)'"
                    ))
                }
            } else {
                hostIPValid = isValidIPv6(host.ip)
                if !host.ip.isEmpty && !hostIPValid {
                    issues.append(ValidationIssue(
                        severity: .error,
                        field: "\(hField).ip",
                        message: "Invalid IPv6 address for static host: '\(host.ip)'"
                    ))
                }
            }

            // Static host IP within subnet (IPv4)
            if isV4 && hostIPValid && !host.ip.isEmpty,
               let hostAddr = ipv4ToUInt32(host.ip),
               let info = subnetInfo {
                if (hostAddr & info.mask) != info.network {
                    issues.append(ValidationIssue(
                        severity: .error,
                        field: "\(hField).ip",
                        message: "Static host IP (\(host.ip)) is not within the configured subnet"
                    ))
                }

                // Warn if static host IP overlaps a DHCP range
                for (k, range) in ip.dhcpRanges.enumerated() {
                    if let s = ipv4ToUInt32(range.start),
                       let e = ipv4ToUInt32(range.end),
                       hostAddr >= s && hostAddr <= e {
                        issues.append(ValidationIssue(
                            severity: .warning,
                            field: "\(hField).ip",
                            message: "Static host IP (\(host.ip)) overlaps with DHCP range[\(k)] (\(range.start) - \(range.end))"
                        ))
                    }
                }
            }
        }

        // Gateway within subnet consistency
        if isV4 && !ip.address.isEmpty && isValidIPv4(ip.address) {
            if let addr = ipv4ToUInt32(ip.address), let info = subnetInfo {
                if (addr & info.mask) != info.network {
                    issues.append(ValidationIssue(
                        severity: .error,
                        field: "\(field).address",
                        message: "Gateway address (\(ip.address)) is not within its own subnet"
                    ))
                }
            }
        }

        return issues
    }

    // MARK: - DNS Validation

    private static func validateDNS(_ config: NetworkConfig) -> [ValidationIssue] {
        var issues = [ValidationIssue]()
        guard let dns = config.dns else { return issues }

        // Forwarder addresses
        for (i, fwd) in dns.forwarders.enumerated() {
            let field = "dns.forwarders[\(i)]"
            if let addr = fwd.address, !addr.isEmpty {
                if !isValidIPv4(addr) && !isValidIPv6(addr) {
                    issues.append(ValidationIssue(
                        severity: .error,
                        field: "\(field).address",
                        message: "Invalid IP address for DNS forwarder: '\(addr)'"
                    ))
                }
            }
        }

        // Host records
        for (i, host) in dns.hostRecords.enumerated() {
            let field = "dns.hostRecords[\(i)]"

            if !host.ip.isEmpty && !isValidIPv4(host.ip) && !isValidIPv6(host.ip) {
                issues.append(ValidationIssue(
                    severity: .error,
                    field: "\(field).ip",
                    message: "Invalid IP address for DNS host record: '\(host.ip)'"
                ))
            }

            if host.hostnames.isEmpty || host.hostnames.allSatisfy({ $0.trimmingCharacters(in: .whitespaces).isEmpty }) {
                issues.append(ValidationIssue(
                    severity: .error,
                    field: "\(field).hostnames",
                    message: "DNS host record must have at least one non-empty hostname"
                ))
            }
        }

        // SRV records: port 0-65535 (UInt16 enforces 0-65535 at the type level,
        // but we still validate for completeness in case raw values are used)
        // Note: port is already UInt16? so 0-65535 is enforced by the type system.
        // We validate that service and protocol are non-empty.
        for (i, srv) in dns.srvRecords.enumerated() {
            let field = "dns.srvRecords[\(i)]"

            if srv.service.trimmingCharacters(in: .whitespaces).isEmpty {
                issues.append(ValidationIssue(
                    severity: .error,
                    field: "\(field).service",
                    message: "SRV record service must not be empty"
                ))
            }
            if srv.protocol.trimmingCharacters(in: .whitespaces).isEmpty {
                issues.append(ValidationIssue(
                    severity: .error,
                    field: "\(field).protocol",
                    message: "SRV record protocol must not be empty"
                ))
            }
        }

        return issues
    }

    // MARK: - Port Forwarding Validation

    private static func validatePortForwarding(_ config: NetworkConfig) -> [ValidationIssue] {
        var issues = [ValidationIssue]()
        let rules = config.portForwarding.rules
        guard !rules.isEmpty else { return issues }

        // Port forwarding only valid with NAT
        if config.forward.mode != .nat {
            issues.append(ValidationIssue(
                severity: .error,
                field: "portForwarding",
                message: "Port forwarding is only supported in NAT mode, current mode is \(config.forward.mode.rawValue)"
            ))
            // Still validate individual rules for completeness
        }

        // Collect all host port ranges to check for overlaps
        struct HostRange {
            let proto: String
            let start: UInt16
            let end: UInt16
            let ruleIndex: Int
            let rangeIndex: Int
        }
        var hostRanges = [HostRange]()

        for (i, rule) in rules.enumerated() {
            let rField = "portForwarding.rules[\(i)]"

            for (j, range) in rule.ranges.enumerated() {
                let field = "\(rField).ranges[\(j)]"

                // Port ranges: 1-65535
                if range.start == 0 {
                    issues.append(ValidationIssue(
                        severity: .error,
                        field: "\(field).start",
                        message: "Port must be between 1 and 65535, got 0"
                    ))
                }

                if let end = range.end {
                    if end == 0 {
                        issues.append(ValidationIssue(
                            severity: .error,
                            field: "\(field).end",
                            message: "Port must be between 1 and 65535, got 0"
                        ))
                    }
                    if end < range.start {
                        issues.append(ValidationIssue(
                            severity: .error,
                            field: field,
                            message: "Port range end (\(end)) is less than start (\(range.start))"
                        ))
                    }
                }

                if let to = range.to, to == 0 {
                    issues.append(ValidationIssue(
                        severity: .error,
                        field: "\(field).to",
                        message: "Guest port must be between 1 and 65535, got 0"
                    ))
                }

                // Guest IP must be valid
                if let toAddr = range.toAddr, !toAddr.isEmpty {
                    if !isValidIPv4(toAddr) && !isValidIPv6(toAddr) {
                        issues.append(ValidationIssue(
                            severity: .error,
                            field: "\(field).toAddr",
                            message: "Invalid guest IP address: '\(toAddr)'"
                        ))
                    }
                }

                // Track for overlap detection
                let effectiveEnd = range.end ?? range.start
                if range.start > 0 {
                    hostRanges.append(HostRange(
                        proto: rule.proto,
                        start: range.start,
                        end: effectiveEnd,
                        ruleIndex: i,
                        rangeIndex: j
                    ))
                }
            }
        }

        // Check for overlapping host port ranges (same protocol)
        for a in 0..<hostRanges.count {
            for b in (a + 1)..<hostRanges.count {
                let ra = hostRanges[a]
                let rb = hostRanges[b]
                guard ra.proto == rb.proto else { continue }

                if ra.start <= rb.end && rb.start <= ra.end {
                    issues.append(ValidationIssue(
                        severity: .error,
                        field: "portForwarding.rules[\(rb.ruleIndex)].ranges[\(rb.rangeIndex)]",
                        message: "Host port range \(rb.start)-\(rb.end) (\(rb.proto)) overlaps with rules[\(ra.ruleIndex)].ranges[\(ra.rangeIndex)] \(ra.start)-\(ra.end)"
                    ))
                }
            }
        }

        return issues
    }

    // MARK: - IP Address Helpers

    /// Validate an IPv4 address using `inet_pton`.
    private static func isValidIPv4(_ address: String) -> Bool {
        var addr = in_addr()
        return address.withCString { cStr in
            inet_pton(AF_INET, cStr, &addr) == 1
        }
    }

    /// Validate an IPv6 address using `inet_pton`.
    private static func isValidIPv6(_ address: String) -> Bool {
        var addr = in6_addr()
        return address.withCString { cStr in
            inet_pton(AF_INET6, cStr, &addr) == 1
        }
    }

    /// Convert an IPv4 address string to a UInt32 in host byte order.
    private static func ipv4ToUInt32(_ address: String) -> UInt32? {
        var addr = in_addr()
        guard address.withCString({ inet_pton(AF_INET, $0, &addr) }) == 1 else {
            return nil
        }
        return UInt32(bigEndian: addr.s_addr)
    }

    /// Convert a netmask value to a prefix length (count of leading 1-bits).
    private static func netmaskToPrefixLength(_ mask: UInt32) -> Int {
        return mask.nonzeroBitCount
    }

    /// Validate a MAC address (XX:XX:XX:XX:XX:XX, case insensitive).
    private static func isValidMACAddress(_ mac: String) -> Bool {
        let pattern = "^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$"
        return mac.range(of: pattern, options: .regularExpression) != nil
    }
}
