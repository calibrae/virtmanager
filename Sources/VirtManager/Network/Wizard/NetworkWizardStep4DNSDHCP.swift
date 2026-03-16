import SwiftUI
import LibvirtSwift

/// Wizard step 4: DNS settings and DHCP summary.
struct NetworkWizardStep4DNSDHCP: View {
    @Bindable var state: NetworkWizardState

    var body: some View {
        Form {
            Section("DNS") {
                Toggle("Enable DNS", isOn: $state.enableDNS)

                if state.enableDNS {
                    TextField("DNS forwarder (optional, e.g. 8.8.8.8)", text: $state.dnsForwarder)
                        .textFieldStyle(.roundedBorder)
                    Text("Leave empty to use the host's DNS resolver.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("DHCP Summary") {
                if state.enableIPv4 && state.enableDHCPv4 {
                    LabeledContent("DHCPv4 Range") {
                        Text("\(state.dhcpv4Start) - \(state.dhcpv4End)")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("DHCPv4 disabled")
                        .foregroundStyle(.secondary)
                }

                if state.enableIPv6 && state.enableDHCPv6 {
                    LabeledContent("DHCPv6 Range") {
                        Text("\(state.dhcpv6Start) - \(state.dhcpv6End)")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("DHCPv6 disabled")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }
}
