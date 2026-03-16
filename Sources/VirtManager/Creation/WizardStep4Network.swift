import SwiftUI

/// Wizard step 4: Network configuration.
public struct WizardStep4Network: View {
    @Bindable var state: VMCreationState

    public init(state: VMCreationState) {
        self.state = state
    }

    public var body: some View {
        Form {
            Section("Network Interface") {
                Picker("Type", selection: $state.networkType) {
                    Text("Virtual Network (NAT)").tag("network")
                    Text("Bridge").tag("bridge")
                }

                TextField("Source", text: $state.networkSource)
                    .textFieldStyle(.roundedBorder)

                if state.networkType == "network" {
                    Text("Typically \"default\" for the default NAT network.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Enter the bridge name, e.g. \"br0\" or \"virbr0\".")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Picker("NIC Model", selection: $state.nicModel) {
                    Text("virtio").tag("virtio")
                    Text("e1000e").tag("e1000e")
                    Text("e1000").tag("e1000")
                    Text("rtl8139").tag("rtl8139")
                }
            }
        }
        .formStyle(.grouped)
    }
}
