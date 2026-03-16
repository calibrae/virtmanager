import SwiftUI
import LibvirtSwift

/// Wizard step 1: Network name and forward mode selection.
struct NetworkWizardStep1NameMode: View {
    @Bindable var state: NetworkWizardState

    private let modeChoices: [(ForwardMode, String)] = [
        (.nat, "NAT"),
        (.route, "Routed"),
        (.open, "Open"),
        (.isolated, "Isolated"),
        (.bridge, "Bridge"),
        (.private, "Private (macvtap)"),
        (.vepa, "VEPA (macvtap)"),
        (.passthrough, "Passthrough (macvtap)"),
    ]

    var body: some View {
        Form {
            Section("Network Name") {
                TextField("Name", text: $state.name)
                    .textFieldStyle(.roundedBorder)
            }

            Section("Forward Mode") {
                Picker("Mode", selection: $state.forwardMode) {
                    ForEach(modeChoices, id: \.0) { mode, label in
                        Text(label).tag(mode)
                    }
                }
                .onChange(of: state.forwardMode) { _, _ in
                    state.applyModeDefaults()
                }

                Text(modeDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if state.forwardMode.requiresBridgeName || state.isOVS {
                Section("Bridge") {
                    TextField("Bridge name (e.g. br0)", text: $state.bridgeName)
                        .textFieldStyle(.roundedBorder)
                    Toggle("Open vSwitch (OVS)", isOn: $state.isOVS)
                }
            }

            if state.forwardMode.requiresPhysicalDevice {
                Section("Physical Device") {
                    TextField("Device (e.g. eth0)", text: $state.physicalDevice)
                        .textFieldStyle(.roundedBorder)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var modeDescription: String {
        switch state.forwardMode {
        case .nat: return "Guests access external network via host NAT. Most common choice."
        case .route: return "Guests use static routes through the host. No address translation."
        case .open: return "Like routed, but no firewall rules are added by libvirt."
        case .isolated: return "Guests can talk to each other and the host, but not external network."
        case .bridge: return "Guests connect directly to a host bridge interface."
        case .private: return "Macvtap private mode: guests isolated from host but reach external network."
        case .vepa: return "Macvtap VEPA mode: all traffic goes through external switch."
        case .passthrough: return "Macvtap passthrough: single guest gets exclusive use of the device."
        case .hostdev: return "Direct device assignment via hostdev."
        }
    }
}
