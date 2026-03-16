import SwiftUI
import LibvirtSwift

/// IPv4 configuration tab: address, netmask, DHCP toggle with ranges/hosts.
public struct IPv4Tab: View {
    @Binding var config: NetworkConfig
    @State private var hasIPv4: Bool = false

    public init(config: Binding<NetworkConfig>) {
        self._config = config
    }

    public var body: some View {
        Form {
            Section("IPv4 Configuration") {
                Toggle("Enable IPv4", isOn: $hasIPv4)
                    .onChange(of: hasIPv4) { _, enabled in
                        if enabled && config.ipv4Config == nil {
                            config.ipv4Config = IPConfig(
                                family: .ipv4,
                                address: "192.168.122.1",
                                netmask: "255.255.255.0"
                            )
                        } else if !enabled {
                            config.ipv4Config = nil
                        }
                    }
            }

            if let ipv4 = config.ipv4Config {
                Section("Address") {
                    TextField("IP Address", text: addressBinding)
                    TextField("Netmask", text: netmaskBinding)
                        .help("Dotted notation, e.g. 255.255.255.0")
                }

                Section("DHCP") {
                    Toggle("Enable DHCP", isOn: dhcpEnabledBinding)

                    if ipv4.dhcpEnabled {
                        ForEach(Array(ipv4.dhcpRanges.enumerated()), id: \.element.id) { index, range in
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

                if ipv4.dhcpEnabled {
                    Section("Static Hosts") {
                        ForEach(Array(ipv4.dhcpHosts.enumerated()), id: \.element.id) { index, host in
                            HStack {
                                TextField("MAC", text: hostMACBinding(index))
                                    .frame(width: 140)
                                TextField("IP", text: hostIPBinding(index))
                                    .frame(width: 120)
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

                    Section("BOOTP / PXE") {
                        TextField("Boot File", text: bootpFileBinding)
                            .help("PXE boot filename (e.g., pxelinux.0)")
                        TextField("TFTP Server", text: bootpServerBinding)
                            .help("TFTP server IP address")
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            hasIPv4 = config.ipv4Config != nil
        }
    }

    // MARK: - Address Bindings

    private var addressBinding: Binding<String> {
        Binding(
            get: { config.ipv4Config?.address ?? "" },
            set: {
                var ip = config.ipv4Config ?? IPConfig(family: .ipv4)
                ip.address = $0
                config.ipv4Config = ip
            }
        )
    }

    private var netmaskBinding: Binding<String> {
        Binding(
            get: { config.ipv4Config?.netmask ?? "" },
            set: {
                var ip = config.ipv4Config ?? IPConfig(family: .ipv4)
                ip.netmask = $0.isEmpty ? nil : $0
                config.ipv4Config = ip
            }
        )
    }

    private var dhcpEnabledBinding: Binding<Bool> {
        Binding(
            get: { config.ipv4Config?.dhcpEnabled ?? false },
            set: {
                var ip = config.ipv4Config ?? IPConfig(family: .ipv4)
                ip.dhcpEnabled = $0
                if $0 && ip.dhcpRanges.isEmpty {
                    ip.dhcpRanges = [DHCPRange(start: "192.168.122.2", end: "192.168.122.254")]
                }
                config.ipv4Config = ip
            }
        )
    }

    // MARK: - Range Bindings

    private func rangeStartBinding(_ index: Int) -> Binding<String> {
        Binding(
            get: { config.ipv4Config?.dhcpRanges[safe: index]?.start ?? "" },
            set: {
                var ip = config.ipv4Config!
                ip.dhcpRanges[index].start = $0
                config.ipv4Config = ip
            }
        )
    }

    private func rangeEndBinding(_ index: Int) -> Binding<String> {
        Binding(
            get: { config.ipv4Config?.dhcpRanges[safe: index]?.end ?? "" },
            set: {
                var ip = config.ipv4Config!
                ip.dhcpRanges[index].end = $0
                config.ipv4Config = ip
            }
        )
    }

    private func addRange() {
        var ip = config.ipv4Config!
        ip.dhcpRanges.append(DHCPRange())
        config.ipv4Config = ip
    }

    private func removeRange(at index: Int) {
        var ip = config.ipv4Config!
        ip.dhcpRanges.remove(at: index)
        config.ipv4Config = ip
    }

    // MARK: - Host Bindings

    private func hostMACBinding(_ index: Int) -> Binding<String> {
        Binding(
            get: { config.ipv4Config?.dhcpHosts[safe: index]?.mac ?? "" },
            set: {
                var ip = config.ipv4Config!
                ip.dhcpHosts[index].mac = $0.isEmpty ? nil : $0
                config.ipv4Config = ip
            }
        )
    }

    private func hostIPBinding(_ index: Int) -> Binding<String> {
        Binding(
            get: { config.ipv4Config?.dhcpHosts[safe: index]?.ip ?? "" },
            set: {
                var ip = config.ipv4Config!
                ip.dhcpHosts[index].ip = $0
                config.ipv4Config = ip
            }
        )
    }

    private func hostNameBinding(_ index: Int) -> Binding<String> {
        Binding(
            get: { config.ipv4Config?.dhcpHosts[safe: index]?.name ?? "" },
            set: {
                var ip = config.ipv4Config!
                ip.dhcpHosts[index].name = $0.isEmpty ? nil : $0
                config.ipv4Config = ip
            }
        )
    }

    private func addHost() {
        var ip = config.ipv4Config!
        ip.dhcpHosts.append(DHCPHost())
        config.ipv4Config = ip
    }

    private func removeHost(at index: Int) {
        var ip = config.ipv4Config!
        ip.dhcpHosts.remove(at: index)
        config.ipv4Config = ip
    }

    // MARK: - BOOTP Bindings

    private var bootpFileBinding: Binding<String> {
        Binding(
            get: { config.ipv4Config?.bootp?.file ?? "" },
            set: {
                var ip = config.ipv4Config!
                if $0.isEmpty && (ip.bootp?.server ?? "").isEmpty {
                    ip.bootp = nil
                } else {
                    var bp = ip.bootp ?? BOOTPConfig()
                    bp.file = $0.isEmpty ? nil : $0
                    ip.bootp = bp
                }
                config.ipv4Config = ip
            }
        )
    }

    private var bootpServerBinding: Binding<String> {
        Binding(
            get: { config.ipv4Config?.bootp?.server ?? "" },
            set: {
                var ip = config.ipv4Config!
                if $0.isEmpty && (ip.bootp?.file ?? "").isEmpty {
                    ip.bootp = nil
                } else {
                    var bp = ip.bootp ?? BOOTPConfig()
                    bp.server = $0.isEmpty ? nil : $0
                    ip.bootp = bp
                }
                config.ipv4Config = ip
            }
        )
    }
}

// Safe array subscript used across tabs
extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
