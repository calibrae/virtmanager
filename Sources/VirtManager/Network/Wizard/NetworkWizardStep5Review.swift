import SwiftUI
import LibvirtSwift

/// Wizard step 5: Read-only summary before creation.
struct NetworkWizardStep5Review: View {
    var state: NetworkWizardState

    var body: some View {
        Form {
            Section("General") {
                LabeledContent("Name", value: state.name)
                LabeledContent("Forward Mode", value: state.forwardMode.rawValue)

                if state.forwardMode.requiresBridgeName || !state.bridgeName.isEmpty {
                    LabeledContent("Bridge", value: state.bridgeName)
                }
                if state.forwardMode.requiresPhysicalDevice {
                    LabeledContent("Physical Device", value: state.physicalDevice)
                }
                if state.isOVS {
                    LabeledContent("Open vSwitch", value: "Yes")
                }
            }

            if state.forwardMode.supportsIPConfig {
                Section("IPv4") {
                    if state.enableIPv4 {
                        LabeledContent("Address", value: "\(state.ipv4Address)/\(state.ipv4Netmask)")
                        if state.enableDHCPv4 {
                            LabeledContent("DHCP Range", value: "\(state.dhcpv4Start) - \(state.dhcpv4End)")
                        } else {
                            LabeledContent("DHCP", value: "Disabled")
                        }
                    } else {
                        Text("IPv4 disabled").foregroundStyle(.secondary)
                    }
                }

                Section("IPv6") {
                    if state.enableIPv6 {
                        LabeledContent("Address", value: "\(state.ipv6Address)/\(state.ipv6Prefix)")
                        if state.enableDHCPv6 {
                            LabeledContent("DHCPv6 Range", value: "\(state.dhcpv6Start) - \(state.dhcpv6End)")
                        } else {
                            LabeledContent("DHCPv6", value: "Disabled")
                        }
                    } else {
                        Text("IPv6 disabled").foregroundStyle(.secondary)
                    }
                }

                Section("DNS") {
                    LabeledContent("DNS", value: state.enableDNS ? "Enabled" : "Disabled")
                    if state.enableDNS && !state.dnsForwarder.isEmpty {
                        LabeledContent("Forwarder", value: state.dnsForwarder)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}
