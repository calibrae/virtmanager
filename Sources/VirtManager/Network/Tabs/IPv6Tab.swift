import SwiftUI
import LibvirtSwift

/// IPv6 configuration tab: address, prefix, DHCPv6 with ranges/hosts.
public struct IPv6Tab: View {
    @Binding var config: NetworkConfig
    @State private var hasIPv6: Bool = false

    public init(config: Binding<NetworkConfig>) {
        self._config = config
    }

    public var body: some View {
        Form {
            Section("IPv6 Configuration") {
                Toggle("Enable IPv6 Address", isOn: $hasIPv6)
                    .onChange(of: hasIPv6) { _, enabled in
                        if enabled && config.ipv6Config == nil {
                            config.ipv6Config = IPConfig(
                                family: .ipv6,
                                address: "fd00::1",
                                prefix: 64
                            )
                        } else if !enabled {
                            config.ipv6Config = nil
                        }
                    }
            }

            if let ipv6 = config.ipv6Config {
                Section("Address") {
                    TextField("IPv6 Address", text: addressBinding)
                        .help("e.g. fd00::1 or 2001:db8::1")
                    TextField("Prefix Length", text: prefixBinding)
                        .help("CIDR prefix length, e.g. 64")
                }

                Section("DHCPv6") {
                    Toggle("Enable DHCPv6", isOn: dhcpEnabledBinding)

                    if ipv6.dhcpEnabled {
                        ForEach(Array(ipv6.dhcpRanges.enumerated()), id: \.element.id) { index, _ in
                            HStack {
                                TextField("Start", text: rangeStartBinding(index))
                                TextField("End", text: rangeEndBinding(index))
                                Button(role: .destructive) {
                                    removeRange(at: index)
                                } label: {
                                    Image(systemName: "minus.circle")
                                }
                                .buttonStyle(.borderless)
                            }
                        }

                        Button("Add Range") {
                            addRange()
                        }
                    }
                }

                if ipv6.dhcpEnabled {
                    Section("Static Hosts") {
                        ForEach(Array(ipv6.dhcpHosts.enumerated()), id: \.element.id) { index, _ in
                            HStack {
                                TextField("DUID", text: hostDUIDBinding(index))
                                    .frame(width: 160)
                                TextField("IP", text: hostIPBinding(index))
                                    .frame(width: 160)
                                TextField("Name", text: hostNameBinding(index))
                                    .frame(width: 100)
                                Button(role: .destructive) {
                                    removeHost(at: index)
                                } label: {
                                    Image(systemName: "minus.circle")
                                }
                                .buttonStyle(.borderless)
                            }
                        }

                        Button("Add Host") {
                            addHost()
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            hasIPv6 = config.ipv6Config != nil
        }
    }

    // MARK: - Address Bindings

    private var addressBinding: Binding<String> {
        Binding(
            get: { config.ipv6Config?.address ?? "" },
            set: {
                var ip = config.ipv6Config ?? IPConfig(family: .ipv6)
                ip.address = $0
                config.ipv6Config = ip
            }
        )
    }

    private var prefixBinding: Binding<String> {
        Binding(
            get: { config.ipv6Config?.prefix.map { String($0) } ?? "" },
            set: {
                var ip = config.ipv6Config ?? IPConfig(family: .ipv6)
                ip.prefix = Int($0)
                config.ipv6Config = ip
            }
        )
    }

    private var dhcpEnabledBinding: Binding<Bool> {
        Binding(
            get: { config.ipv6Config?.dhcpEnabled ?? false },
            set: {
                var ip = config.ipv6Config ?? IPConfig(family: .ipv6)
                ip.dhcpEnabled = $0
                if $0 && ip.dhcpRanges.isEmpty {
                    ip.dhcpRanges = [DHCPRange(start: "fd00::100", end: "fd00::1ff")]
                }
                config.ipv6Config = ip
            }
        )
    }

    // MARK: - Range Bindings

    private func rangeStartBinding(_ index: Int) -> Binding<String> {
        Binding(
            get: { config.ipv6Config?.dhcpRanges[safe: index]?.start ?? "" },
            set: {
                var ip = config.ipv6Config!
                ip.dhcpRanges[index].start = $0
                config.ipv6Config = ip
            }
        )
    }

    private func rangeEndBinding(_ index: Int) -> Binding<String> {
        Binding(
            get: { config.ipv6Config?.dhcpRanges[safe: index]?.end ?? "" },
            set: {
                var ip = config.ipv6Config!
                ip.dhcpRanges[index].end = $0
                config.ipv6Config = ip
            }
        )
    }

    private func addRange() {
        var ip = config.ipv6Config!
        ip.dhcpRanges.append(DHCPRange())
        config.ipv6Config = ip
    }

    private func removeRange(at index: Int) {
        var ip = config.ipv6Config!
        ip.dhcpRanges.remove(at: index)
        config.ipv6Config = ip
    }

    // MARK: - Host Bindings

    private func hostDUIDBinding(_ index: Int) -> Binding<String> {
        Binding(
            get: { config.ipv6Config?.dhcpHosts[safe: index]?.duid ?? "" },
            set: {
                var ip = config.ipv6Config!
                ip.dhcpHosts[index].duid = $0.isEmpty ? nil : $0
                config.ipv6Config = ip
            }
        )
    }

    private func hostIPBinding(_ index: Int) -> Binding<String> {
        Binding(
            get: { config.ipv6Config?.dhcpHosts[safe: index]?.ip ?? "" },
            set: {
                var ip = config.ipv6Config!
                ip.dhcpHosts[index].ip = $0
                config.ipv6Config = ip
            }
        )
    }

    private func hostNameBinding(_ index: Int) -> Binding<String> {
        Binding(
            get: { config.ipv6Config?.dhcpHosts[safe: index]?.name ?? "" },
            set: {
                var ip = config.ipv6Config!
                ip.dhcpHosts[index].name = $0.isEmpty ? nil : $0
                config.ipv6Config = ip
            }
        )
    }

    private func addHost() {
        var ip = config.ipv6Config!
        ip.dhcpHosts.append(DHCPHost())
        config.ipv6Config = ip
    }

    private func removeHost(at index: Int) {
        var ip = config.ipv6Config!
        ip.dhcpHosts.remove(at: index)
        config.ipv6Config = ip
    }
}
