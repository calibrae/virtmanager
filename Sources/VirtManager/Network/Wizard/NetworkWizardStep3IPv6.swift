import SwiftUI
import LibvirtSwift

/// Wizard step 3: IPv6 address and DHCPv6 configuration.
struct NetworkWizardStep3IPv6: View {
    @Bindable var state: NetworkWizardState

    var body: some View {
        Form {
            Section("IPv6 Network") {
                Toggle("Enable IPv6", isOn: $state.enableIPv6)
            }

            if state.enableIPv6 {
                Section("Address") {
                    TextField("Address (e.g. fd00::1)", text: $state.ipv6Address)
                        .textFieldStyle(.roundedBorder)
                    Stepper("Prefix length: /\(state.ipv6Prefix)", value: $state.ipv6Prefix, in: 8...128)
                }

                Section("DHCPv6") {
                    Toggle("Enable DHCPv6", isOn: $state.enableDHCPv6)

                    if state.enableDHCPv6 {
                        TextField("Range start", text: $state.dhcpv6Start)
                            .textFieldStyle(.roundedBorder)
                        TextField("Range end", text: $state.dhcpv6End)
                            .textFieldStyle(.roundedBorder)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}
