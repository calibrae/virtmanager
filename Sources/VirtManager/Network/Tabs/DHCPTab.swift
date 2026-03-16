import SwiftUI
import LibvirtSwift

/// Combined DHCP tab: DHCPv4/v6 configuration summaries, static hosts, and active lease table.
public struct DHCPTab: View {
    @Binding var config: NetworkConfig
    public let networkName: String
    public let connectionID: UUID

    public init(config: Binding<NetworkConfig>, networkName: String, connectionID: UUID) {
        self._config = config
        self.networkName = networkName
        self.connectionID = connectionID
    }

    public var body: some View {
        VStack(spacing: 0) {
            Form {
                if let ipv4 = config.ipv4Config, ipv4.dhcpEnabled {
                    Section("DHCPv4") {
                        LabeledContent("Network", value: "\(ipv4.address)/\(ipv4.netmask ?? "")")
                        ForEach(Array(ipv4.dhcpRanges.enumerated()), id: \.element.id) { _, range in
                            LabeledContent("Range", value: "\(range.start) - \(range.end)")
                        }
                        LabeledContent("Static Hosts", value: "\(ipv4.dhcpHosts.count)")
                    }

                    Section("DHCPv4 Static Hosts") {
                        ForEach(Array(ipv4.dhcpHosts.enumerated()), id: \.element.id) { index, _ in
                            HStack {
                                TextField("MAC", text: ipv4HostMACBinding(index))
                                    .frame(width: 160)
                                TextField("IP", text: ipv4HostIPBinding(index))
                                    .frame(width: 140)
                                TextField("Name", text: ipv4HostNameBinding(index))
                                    .frame(width: 100)
                                Button(role: .destructive) {
                                    removeIPv4Host(at: index)
                                } label: {
                                    Image(systemName: "minus.circle")
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                        Button("Add Host") { addIPv4Host() }
                    }
                } else {
                    Section("DHCPv4") {
                        Text("DHCPv4 is not enabled. Enable it in the IPv4 tab.")
                            .foregroundStyle(.secondary)
                    }
                }

                if let ipv6 = config.ipv6Config, ipv6.dhcpEnabled {
                    Section("DHCPv6") {
                        LabeledContent("Network", value: "\(ipv6.address)/\(ipv6.prefix ?? 64)")
                        ForEach(Array(ipv6.dhcpRanges.enumerated()), id: \.element.id) { _, range in
                            LabeledContent("Range", value: "\(range.start) - \(range.end)")
                        }
                        LabeledContent("Static Hosts", value: "\(ipv6.dhcpHosts.count)")
                    }

                    Section("DHCPv6 Static Hosts") {
                        ForEach(Array(ipv6.dhcpHosts.enumerated()), id: \.element.id) { index, _ in
                            HStack {
                                TextField("DUID", text: ipv6HostDUIDBinding(index))
                                    .frame(width: 160)
                                TextField("IP", text: ipv6HostIPBinding(index))
                                    .frame(width: 140)
                                TextField("Name", text: ipv6HostNameBinding(index))
                                    .frame(width: 100)
                                Button(role: .destructive) {
                                    removeIPv6Host(at: index)
                                } label: {
                                    Image(systemName: "minus.circle")
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                        Button("Add Host") { addIPv6Host() }
                    }
                } else {
                    Section("DHCPv6") {
                        Text("DHCPv6 is not enabled. Enable it in the IPv6 tab.")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)

            Divider()

            DHCPLeaseTable(networkName: networkName, connectionID: connectionID)
                .padding()
        }
    }

    // MARK: - IPv4 Host Bindings

    private func ipv4HostMACBinding(_ index: Int) -> Binding<String> {
        Binding(
            get: { config.ipv4Config?.dhcpHosts[safe: index]?.mac ?? "" },
            set: {
                var ip = config.ipv4Config!
                ip.dhcpHosts[index].mac = $0.isEmpty ? nil : $0
                config.ipv4Config = ip
            }
        )
    }

    private func ipv4HostIPBinding(_ index: Int) -> Binding<String> {
        Binding(
            get: { config.ipv4Config?.dhcpHosts[safe: index]?.ip ?? "" },
            set: {
                var ip = config.ipv4Config!
                ip.dhcpHosts[index].ip = $0
                config.ipv4Config = ip
            }
        )
    }

    private func ipv4HostNameBinding(_ index: Int) -> Binding<String> {
        Binding(
            get: { config.ipv4Config?.dhcpHosts[safe: index]?.name ?? "" },
            set: {
                var ip = config.ipv4Config!
                ip.dhcpHosts[index].name = $0.isEmpty ? nil : $0
                config.ipv4Config = ip
            }
        )
    }

    private func addIPv4Host() {
        var ip = config.ipv4Config!
        ip.dhcpHosts.append(DHCPHost())
        config.ipv4Config = ip
    }

    private func removeIPv4Host(at index: Int) {
        var ip = config.ipv4Config!
        ip.dhcpHosts.remove(at: index)
        config.ipv4Config = ip
    }

    // MARK: - IPv6 Host Bindings

    private func ipv6HostDUIDBinding(_ index: Int) -> Binding<String> {
        Binding(
            get: { config.ipv6Config?.dhcpHosts[safe: index]?.duid ?? "" },
            set: {
                var ip = config.ipv6Config!
                ip.dhcpHosts[index].duid = $0.isEmpty ? nil : $0
                config.ipv6Config = ip
            }
        )
    }

    private func ipv6HostIPBinding(_ index: Int) -> Binding<String> {
        Binding(
            get: { config.ipv6Config?.dhcpHosts[safe: index]?.ip ?? "" },
            set: {
                var ip = config.ipv6Config!
                ip.dhcpHosts[index].ip = $0
                config.ipv6Config = ip
            }
        )
    }

    private func ipv6HostNameBinding(_ index: Int) -> Binding<String> {
        Binding(
            get: { config.ipv6Config?.dhcpHosts[safe: index]?.name ?? "" },
            set: {
                var ip = config.ipv6Config!
                ip.dhcpHosts[index].name = $0.isEmpty ? nil : $0
                config.ipv6Config = ip
            }
        )
    }

    private func addIPv6Host() {
        var ip = config.ipv6Config!
        ip.dhcpHosts.append(DHCPHost())
        config.ipv6Config = ip
    }

    private func removeIPv6Host(at index: Int) {
        var ip = config.ipv6Config!
        ip.dhcpHosts.remove(at: index)
        config.ipv6Config = ip
    }
}
