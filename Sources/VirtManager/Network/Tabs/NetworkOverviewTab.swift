import SwiftUI
import LibvirtSwift

/// Overview tab for network configuration: name, UUID, forward mode, bridge, domain.
public struct NetworkOverviewTab: View {
    @Binding var config: NetworkConfig

    public init(config: Binding<NetworkConfig>) {
        self._config = config
    }

    public var body: some View {
        Form {
            Section("Identity") {
                TextField("Name", text: nameBinding)
                LabeledContent("UUID", value: config.uuid.isEmpty ? "(auto-generated)" : config.uuid)
                    .textSelection(.enabled)
            }

            Section("Forward Mode") {
                Picker("Mode", selection: forwardModeBinding) {
                    ForEach(ForwardMode.allCases, id: \.self) { mode in
                        Text(modeLabel(mode)).tag(mode)
                    }
                }

                if config.forward.mode == .nat {
                    TextField("NAT Address Start", text: natAddrStartBinding)
                    TextField("NAT Address End", text: natAddrEndBinding)
                    TextField("NAT Port Start", text: natPortStartBinding)
                    TextField("NAT Port End", text: natPortEndBinding)
                }

                if config.forward.mode.requiresPhysicalDevice || config.forward.mode == .nat || config.forward.mode == .route {
                    TextField("Physical Device", text: devBinding)
                        .help("Host network interface (e.g., eth0, eno1)")
                }

                if config.forward.mode.requiresBridgeName || config.forward.mode == .isolated || config.forward.mode == .nat || config.forward.mode == .route {
                    TextField("Bridge Name", text: bridgeBinding)
                        .help("Bridge device name (e.g., virbr0)")
                }
            }

            Section("Domain") {
                TextField("DNS Domain", text: domainBinding)
                    .help("Local domain for this network (e.g., example.lan)")
            }

            Section("Options") {
                Toggle("Enable IPv6", isOn: ipv6EnabledBinding)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Bindings

    private var nameBinding: Binding<String> {
        Binding(
            get: { config.name },
            set: { config.name = $0 }
        )
    }

    private var forwardModeBinding: Binding<ForwardMode> {
        Binding(
            get: { config.forward.mode },
            set: {
                var fwd = config.forward
                fwd.mode = $0
                config.forward = fwd
            }
        )
    }

    private var devBinding: Binding<String> {
        Binding(
            get: { config.forward.dev ?? "" },
            set: {
                var fwd = config.forward
                fwd.dev = $0.isEmpty ? nil : $0
                config.forward = fwd
            }
        )
    }

    private var bridgeBinding: Binding<String> {
        Binding(
            get: { config.forward.bridgeName ?? "" },
            set: {
                var fwd = config.forward
                fwd.bridgeName = $0.isEmpty ? nil : $0
                config.forward = fwd
            }
        )
    }

    private var domainBinding: Binding<String> {
        Binding(
            get: { config.domain ?? "" },
            set: { config.domain = $0.isEmpty ? nil : $0 }
        )
    }

    private var ipv6EnabledBinding: Binding<Bool> {
        Binding(
            get: { config.ipv6Enabled },
            set: { config.ipv6Enabled = $0 }
        )
    }

    private var natAddrStartBinding: Binding<String> {
        Binding(
            get: { config.forward.natAddressStart ?? "" },
            set: { var f = config.forward; f.natAddressStart = $0.isEmpty ? nil : $0; config.forward = f }
        )
    }

    private var natAddrEndBinding: Binding<String> {
        Binding(
            get: { config.forward.natAddressEnd ?? "" },
            set: { var f = config.forward; f.natAddressEnd = $0.isEmpty ? nil : $0; config.forward = f }
        )
    }

    private var natPortStartBinding: Binding<String> {
        Binding(
            get: { config.forward.natPortStart.map { String($0) } ?? "" },
            set: { var f = config.forward; f.natPortStart = UInt16($0); config.forward = f }
        )
    }

    private var natPortEndBinding: Binding<String> {
        Binding(
            get: { config.forward.natPortEnd.map { String($0) } ?? "" },
            set: { var f = config.forward; f.natPortEnd = UInt16($0); config.forward = f }
        )
    }

    // MARK: - Helpers

    private func modeLabel(_ mode: ForwardMode) -> String {
        switch mode {
        case .nat: return "NAT"
        case .route: return "Routed"
        case .open: return "Open"
        case .bridge: return "Bridge"
        case .private: return "Private (macvtap)"
        case .vepa: return "VEPA (macvtap)"
        case .passthrough: return "Passthrough (macvtap)"
        case .hostdev: return "Host Device (SR-IOV)"
        case .isolated: return "Isolated (no forwarding)"
        }
    }
}
