import SwiftUI
import LibvirtSwift

/// DNS configuration tab: forwarders, host records, TXT records, SRV records.
public struct DNSTab: View {
    @Binding var config: NetworkConfig

    public init(config: Binding<NetworkConfig>) {
        self._config = config
    }

    private var dns: DNSConfig {
        config.dns ?? DNSConfig()
    }

    private func update(_ mutate: (inout DNSConfig) -> Void) {
        var d = config.dns ?? DNSConfig()
        mutate(&d)
        config.dns = d
    }

    public var body: some View {
        Form {
            Section("DNS Service") {
                Toggle("Enable DNS", isOn: Binding(
                    get: { dns.enabled },
                    set: { val in update { d in d.enabled = val } }
                ))
            }

            if dns.enabled {
                forwardersSection
                hostRecordsSection
                txtRecordsSection
                srvRecordsSection
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Forwarders

    private var forwardersSection: some View {
        Section("Forwarders") {
            ForEach(Array(dns.forwarders.enumerated()), id: \.element.id) { index, fwd in
                HStack {
                    TextField("Address", text: Binding(
                        get: { fwd.address ?? "" },
                        set: { val in update { d in d.forwarders[index].address = val.isEmpty ? nil : val } }
                    ))
                    .frame(width: 160)
                    TextField("Domain (optional)", text: Binding(
                        get: { fwd.domain ?? "" },
                        set: { val in update { d in d.forwarders[index].domain = val.isEmpty ? nil : val } }
                    ))
                    Button(role: .destructive) {
                        update { d in d.forwarders.remove(at: index) }
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                }
            }
            Button("Add Forwarder") {
                update { d in d.forwarders.append(DNSForwarder()) }
            }
        }
    }

    // MARK: - Host Records

    private var hostRecordsSection: some View {
        Section("Host Records") {
            ForEach(Array(dns.hostRecords.enumerated()), id: \.element.id) { index, record in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        TextField("IP", text: Binding(
                            get: { record.ip },
                            set: { val in update { d in d.hostRecords[index].ip = val } }
                        ))
                        .frame(width: 160)
                        Spacer()
                        Button(role: .destructive) {
                            update { d in d.hostRecords.remove(at: index) }
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                    }
                    TextField("Hostnames (comma-separated)", text: Binding(
                        get: { record.hostnames.joined(separator: ", ") },
                        set: { val in
                            let names = val.split(separator: ",").map { String($0.trimmingCharacters(in: .whitespaces)) }
                            update { d in d.hostRecords[index].hostnames = names }
                        }
                    ))
                    .font(.callout)
                }
                .padding(.vertical, 2)
            }
            Button("Add Host Record") {
                update { d in d.hostRecords.append(DNSHostRecord()) }
            }
        }
    }

    // MARK: - TXT Records

    private var txtRecordsSection: some View {
        Section("TXT Records") {
            ForEach(Array(dns.txtRecords.enumerated()), id: \.element.id) { index, record in
                HStack {
                    TextField("Name", text: Binding(
                        get: { record.name },
                        set: { val in update { d in d.txtRecords[index].name = val } }
                    ))
                    TextField("Value", text: Binding(
                        get: { record.value },
                        set: { val in update { d in d.txtRecords[index].value = val } }
                    ))
                    Button(role: .destructive) {
                        update { d in d.txtRecords.remove(at: index) }
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                }
            }
            Button("Add TXT Record") {
                update { d in d.txtRecords.append(DNSTXTRecord()) }
            }
        }
    }

    // MARK: - SRV Records

    private var srvRecordsSection: some View {
        Section("SRV Records") {
            ForEach(Array(dns.srvRecords.enumerated()), id: \.element.id) { index, record in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        TextField("Service", text: Binding(
                            get: { record.service },
                            set: { val in update { d in d.srvRecords[index].service = val } }
                        ))
                        .frame(width: 100)
                        TextField("Protocol", text: Binding(
                            get: { record.protocol },
                            set: { val in update { d in d.srvRecords[index].protocol = val } }
                        ))
                        .frame(width: 80)
                        TextField("Domain", text: Binding(
                            get: { record.domain ?? "" },
                            set: { val in update { d in d.srvRecords[index].domain = val.isEmpty ? nil : val } }
                        ))
                        Spacer()
                        Button(role: .destructive) {
                            update { d in d.srvRecords.remove(at: index) }
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                    }
                    HStack {
                        TextField("Target", text: Binding(
                            get: { record.target ?? "" },
                            set: { val in update { d in d.srvRecords[index].target = val.isEmpty ? nil : val } }
                        ))
                        TextField("Port", text: Binding(
                            get: { record.port.map { String($0) } ?? "" },
                            set: { val in update { d in d.srvRecords[index].port = UInt16(val) } }
                        ))
                        .frame(width: 70)
                        TextField("Priority", text: Binding(
                            get: { record.priority.map { String($0) } ?? "" },
                            set: { val in update { d in d.srvRecords[index].priority = UInt16(val) } }
                        ))
                        .frame(width: 70)
                        TextField("Weight", text: Binding(
                            get: { record.weight.map { String($0) } ?? "" },
                            set: { val in update { d in d.srvRecords[index].weight = UInt16(val) } }
                        ))
                        .frame(width: 70)
                    }
                    .font(.callout)
                }
                .padding(.vertical, 2)
            }
            Button("Add SRV Record") {
                update { d in d.srvRecords.append(DNSSRVRecord()) }
            }
        }
    }
}
