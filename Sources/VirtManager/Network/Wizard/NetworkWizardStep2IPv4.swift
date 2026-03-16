import SwiftUI
import LibvirtSwift

/// Wizard step 2: IPv4 address and DHCP configuration.
struct NetworkWizardStep2IPv4: View {
    @Bindable var state: NetworkWizardState

    var body: some View {
        Form {
            Section("IPv4 Network") {
                Toggle("Enable IPv4", isOn: $state.enableIPv4)
            }

            if state.enableIPv4 {
                Section("Address") {
                    TextField("Gateway address (e.g. 192.168.122.1)", text: $state.ipv4Address)
                        .textFieldStyle(.roundedBorder)
                    TextField("Netmask (e.g. 255.255.255.0)", text: $state.ipv4Netmask)
                        .textFieldStyle(.roundedBorder)
                }

                Section("DHCPv4") {
                    Toggle("Enable DHCP", isOn: $state.enableDHCPv4)

                    if state.enableDHCPv4 {
                        TextField("Range start", text: $state.dhcpv4Start)
                            .textFieldStyle(.roundedBorder)
                        TextField("Range end", text: $state.dhcpv4End)
                            .textFieldStyle(.roundedBorder)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}
