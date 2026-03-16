import Foundation
import LibvirtSwift

/// Holds all state for the network creation wizard.
@Observable
public class NetworkWizardState {
    // Step 1: Name & Mode
    public var name: String = ""
    public var forwardMode: ForwardMode = .nat
    public var bridgeName: String = ""
    public var physicalDevice: String = ""
    public var isOVS: Bool = false

    // Step 2: IPv4
    public var enableIPv4: Bool = true
    public var ipv4Address: String = "192.168.122.1"
    public var ipv4Netmask: String = "255.255.255.0"
    public var enableDHCPv4: Bool = true
    public var dhcpv4Start: String = "192.168.122.2"
    public var dhcpv4End: String = "192.168.122.254"

    // Step 3: IPv6
    public var enableIPv6: Bool = false
    public var ipv6Address: String = "fd00::1"
    public var ipv6Prefix: Int = 64
    public var enableDHCPv6: Bool = false
    public var dhcpv6Start: String = "fd00::100"
    public var dhcpv6End: String = "fd00::1ff"

    // Step 4: DNS
    public var enableDNS: Bool = true
    public var dnsForwarder: String = ""

    // Options
    public var startAfterCreation: Bool = true

    public init() {}

    /// The visible steps for the current forward mode.
    public var visibleSteps: [WizardStepKind] {
        var steps: [WizardStepKind] = [.nameMode]
        if forwardMode.supportsIPConfig {
            steps.append(contentsOf: [.ipv4, .ipv6, .dnsDhcp])
        }
        steps.append(.review)
        return steps
    }

    /// Apply smart defaults when the forward mode changes.
    public func applyModeDefaults() {
        switch forwardMode {
        case .nat:
            ipv4Address = "192.168.122.1"
            ipv4Netmask = "255.255.255.0"
            dhcpv4Start = "192.168.122.2"
            dhcpv4End = "192.168.122.254"
            enableIPv4 = true
            enableDHCPv4 = true
            enableDNS = true
        case .route:
            ipv4Address = "192.168.100.1"
            ipv4Netmask = "255.255.255.0"
            dhcpv4Start = "192.168.100.2"
            dhcpv4End = "192.168.100.254"
            enableIPv4 = true
            enableDHCPv4 = true
            enableDNS = true
        case .isolated:
            ipv4Address = "192.168.200.1"
            ipv4Netmask = "255.255.255.0"
            dhcpv4Start = "192.168.200.2"
            dhcpv4End = "192.168.200.254"
            enableIPv4 = true
            enableDHCPv4 = true
            enableDNS = true
        case .open:
            ipv4Address = "192.168.150.1"
            ipv4Netmask = "255.255.255.0"
            dhcpv4Start = "192.168.150.2"
            dhcpv4End = "192.168.150.254"
            enableIPv4 = true
            enableDHCPv4 = true
            enableDNS = true
        default:
            // Bridge, macvtap, OVS modes: no IP config
            enableIPv4 = false
            enableDHCPv4 = false
            enableIPv6 = false
            enableDHCPv6 = false
            enableDNS = false
        }
    }

    /// Generates valid libvirt network XML from the current state.
    public func generateNetworkXML() -> String {
        var xml = "<network>\n"
        xml += "  <name>\(escapeXML(name))</name>\n"

        // Forward mode
        if forwardMode != .isolated {
            var fwdAttrs = "mode='\(forwardMode.rawValue)'"
            if forwardMode.requiresPhysicalDevice && !physicalDevice.isEmpty {
                fwdAttrs += " dev='\(escapeXML(physicalDevice))'"
            }
            xml += "  <forward \(fwdAttrs)/>\n"
        }

        // Bridge name
        if !bridgeName.isEmpty {
            xml += "  <bridge name='\(escapeXML(bridgeName))'/>\n"
        }

        // OVS virtualport
        if isOVS {
            xml += "  <virtualport type='openvswitch'/>\n"
        }

        // DNS
        if forwardMode.supportsIPConfig && enableDNS {
            if !dnsForwarder.isEmpty {
                xml += "  <dns>\n"
                xml += "    <forwarder addr='\(escapeXML(dnsForwarder))'/>\n"
                xml += "  </dns>\n"
            }
        } else if forwardMode.supportsIPConfig && !enableDNS {
            xml += "  <dns enable='no'/>\n"
        }

        // IPv4
        if forwardMode.supportsIPConfig && enableIPv4 {
            xml += "  <ip address='\(escapeXML(ipv4Address))' netmask='\(escapeXML(ipv4Netmask))'>\n"
            if enableDHCPv4 {
                xml += "    <dhcp>\n"
                xml += "      <range start='\(escapeXML(dhcpv4Start))' end='\(escapeXML(dhcpv4End))'/>\n"
                xml += "    </dhcp>\n"
            }
            xml += "  </ip>\n"
        }

        // IPv6
        if forwardMode.supportsIPConfig && enableIPv6 {
            xml += "  <ip family='ipv6' address='\(escapeXML(ipv6Address))' prefix='\(ipv6Prefix)'>\n"
            if enableDHCPv6 {
                xml += "    <dhcp>\n"
                xml += "      <range start='\(escapeXML(dhcpv6Start))' end='\(escapeXML(dhcpv6End))'/>\n"
                xml += "    </dhcp>\n"
            }
            xml += "  </ip>\n"
        }

        xml += "</network>"
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

/// Identifies each wizard step.
public enum WizardStepKind: String, CaseIterable {
    case nameMode = "Name & Mode"
    case ipv4 = "IPv4"
    case ipv6 = "IPv6"
    case dnsDhcp = "DNS & DHCP"
    case review = "Review"
}
