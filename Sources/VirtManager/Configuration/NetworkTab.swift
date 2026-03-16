import SwiftUI
import LibvirtSwift

public struct NetworkTab: View {
    @Environment(AppState.self) private var appState
    @Binding var config: DomainConfig
    let connectionID: UUID?
    @State private var showAddNIC = false
    @State private var nicToRemove: NetworkDevice?
    @State private var availableNetworks: [String] = ["default"]
    @State private var availableBridges: [String] = []

    public init(config: Binding<DomainConfig>, connectionID: UUID? = nil) {
        self._config = config
        self.connectionID = connectionID
    }

    public var body: some View {
        VStack(spacing: 0) {
            List {
                ForEach(Array(config.networkInterfaces.enumerated()), id: \.element.id) { index, nic in
                    nicRow(nic: nic, index: index)
                }
            }

            Divider()

            HStack {
                Button("Add NIC") {
                    showAddNIC = true
                }
                Spacer()
                Text("\(config.networkInterfaces.count) interface(s)")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }
            .padding(8)
        }
        .sheet(isPresented: $showAddNIC) {
            AddNICSheet(
                config: $config,
                isPresented: $showAddNIC,
                availableNetworks: availableNetworks,
                availableBridges: availableBridges
            )
        }
        .alert("Remove Network Interface", isPresented: .init(
            get: { nicToRemove != nil },
            set: { if !$0 { nicToRemove = nil } }
        )) {
            Button("Cancel", role: .cancel) { nicToRemove = nil }
            Button("Remove", role: .destructive) {
                if let nic = nicToRemove {
                    config.networkInterfaces.removeAll { $0.id == nic.id }
                    nicToRemove = nil
                }
            }
        } message: {
            if let nic = nicToRemove {
                Text("Remove interface \(nic.macAddress ?? nic.sourceName ?? "unknown")?")
            }
        }
        .onAppear { loadAvailableSources() }
    }

    @ViewBuilder
    private func nicRow(nic: NetworkDevice, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "network")
                Text(nic.type)
                    .fontWeight(.medium)
                if let source = nic.sourceName {
                    Text("(\(source))")
                        .foregroundStyle(.secondary)
                }
                Spacer()

                Button(role: .destructive) {
                    nicToRemove = nic
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
            }

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
                GridRow {
                    Text("Source").foregroundStyle(.secondary).font(.caption)
                    sourcePickerForNIC(index: index)
                }
                GridRow {
                    Text("Model").foregroundStyle(.secondary).font(.caption)
                    Picker("", selection: modelBinding(index: index)) {
                        ForEach(NetworkDevice.NICModel.allCases, id: \.self) { model in
                            Text(model.rawValue).tag(model)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 150)
                }
                GridRow {
                    Text("MAC").foregroundStyle(.secondary).font(.caption)
                    HStack {
                        Text(nic.macAddress ?? "Auto-generated")
                            .textSelection(.enabled)
                        Button("Generate") {
                            config.networkInterfaces[index].macAddress = Self.generateMAC()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                    }
                }
            }
            .font(.callout)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func sourcePickerForNIC(index: Int) -> some View {
        let nic = config.networkInterfaces[index]
        if nic.type == "bridge" {
            if availableBridges.isEmpty {
                TextField("Bridge", text: sourceBinding(index: index))
                    .frame(width: 150)
            } else {
                Picker("", selection: sourceBinding(index: index)) {
                    ForEach(availableBridges, id: \.self) { bridge in
                        Text(bridge).tag(bridge)
                    }
                }
                .labelsHidden()
                .frame(width: 150)
            }
        } else if nic.type == "network" {
            if availableNetworks.count <= 1 {
                TextField("Network", text: sourceBinding(index: index))
                    .frame(width: 150)
            } else {
                Picker("", selection: sourceBinding(index: index)) {
                    ForEach(availableNetworks, id: \.self) { net in
                        Text(net).tag(net)
                    }
                }
                .labelsHidden()
                .frame(width: 150)
            }
        } else {
            TextField("Device", text: sourceBinding(index: index))
                .frame(width: 150)
        }
    }

    private func sourceBinding(index: Int) -> Binding<String> {
        Binding(
            get: { config.networkInterfaces[index].sourceName ?? "" },
            set: { config.networkInterfaces[index].sourceName = $0.isEmpty ? nil : $0 }
        )
    }

    private func modelBinding(index: Int) -> Binding<NetworkDevice.NICModel> {
        Binding(
            get: { config.networkInterfaces[index].model },
            set: { config.networkInterfaces[index].model = $0 }
        )
    }

    private func loadAvailableSources() {
        guard let connID = connectionID else { return }
        Task {
            // Load libvirt networks
            if let networks = try? await appState.listNetworks(connectionID: connID) {
                availableNetworks = networks.map(\.name)
                if availableNetworks.isEmpty {
                    availableNetworks = ["default"]
                }
            }
            // Load bridges via SSH
            if let bridges = try? await appState.listRemoteBridges(connectionID: connID) {
                availableBridges = bridges
            }
        }
    }

    /// Generate a random MAC address with the QEMU OUI prefix (52:54:00).
    static func generateMAC() -> String {
        let bytes = (0..<3).map { _ in UInt8.random(in: 0...255) }
        return String(format: "52:54:00:%02x:%02x:%02x", bytes[0], bytes[1], bytes[2])
    }
}

struct AddNICSheet: View {
    @Binding var config: DomainConfig
    @Binding var isPresented: Bool
    let availableNetworks: [String]
    let availableBridges: [String]

    @State private var type = "network"
    @State private var sourceName = "default"
    @State private var model: NetworkDevice.NICModel = .virtio
    @State private var macAddress = ""

    var body: some View {
        VStack(spacing: 16) {
            Text("Add Network Interface")
                .font(.headline)

            Form {
                Picker("Type", selection: $type) {
                    Text("Virtual Network").tag("network")
                    Text("Bridge").tag("bridge")
                    Text("Direct (macvtap)").tag("direct")
                }
                .onChange(of: type) { _, newType in
                    // Set a sensible default source when switching types
                    switch newType {
                    case "network":
                        sourceName = availableNetworks.first ?? "default"
                    case "bridge":
                        sourceName = availableBridges.first ?? ""
                    default:
                        sourceName = ""
                    }
                }

                if type == "network" && availableNetworks.count > 1 {
                    Picker("Source", selection: $sourceName) {
                        ForEach(availableNetworks, id: \.self) { net in
                            Text(net).tag(net)
                        }
                    }
                } else if type == "bridge" && !availableBridges.isEmpty {
                    Picker("Source", selection: $sourceName) {
                        ForEach(availableBridges, id: \.self) { bridge in
                            Text(bridge).tag(bridge)
                        }
                    }
                } else {
                    TextField("Source", text: $sourceName)
                        .help("Network name, bridge device, or host interface")
                }

                Picker("Model", selection: $model) {
                    ForEach(NetworkDevice.NICModel.allCases, id: \.self) { m in
                        Text(m.rawValue).tag(m)
                    }
                }

                HStack {
                    TextField("MAC Address", text: $macAddress)
                        .help("Leave empty for auto-generation")
                    Button("Generate") {
                        macAddress = NetworkTab.generateMAC()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            HStack {
                Button("Cancel") { isPresented = false }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Add") {
                    let nic = NetworkDevice(
                        type: type,
                        sourceName: sourceName.isEmpty ? nil : sourceName,
                        macAddress: macAddress.isEmpty ? nil : macAddress,
                        model: model
                    )
                    config.networkInterfaces.append(nic)
                    isPresented = false
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 400)
    }
}
