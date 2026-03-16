import SwiftUI
import VirtManagerCore
import LibvirtSwift

/// A SwiftUI view for managing virtual networks on a hypervisor.
/// Lists all networks with name, state, bridge, and provides start/stop/create/delete controls.
public struct NetworkManager: View {
    @Environment(AppState.self) private var appState

    public let connectionID: UUID

    @State private var networks: [NetworkInfo] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showCreateSheet = false
    @State private var networkToDelete: String?

    public init(connectionID: UUID) {
        self.connectionID = connectionID
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                Text("Virtual Networks")
                    .font(.headline)
                Spacer()
                Button {
                    showCreateSheet = true
                } label: {
                    Label("Create Network", systemImage: "plus")
                }
                Button {
                    loadNetworks()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }
            .padding()

            Divider()

            if isLoading {
                Spacer()
                ProgressView("Loading networks...")
                Spacer()
            } else if let error = errorMessage {
                Spacer()
                Text(error)
                    .foregroundStyle(.red)
                Spacer()
            } else if networks.isEmpty {
                Spacer()
                ContentUnavailableView(
                    "No Virtual Networks",
                    systemImage: "network",
                    description: Text("Create a virtual network to get started.")
                )
                Spacer()
            } else {
                List {
                    ForEach(networks, id: \.uuid) { network in
                        networkRow(network)
                    }
                }
                .listStyle(.inset)
            }
        }
        .sheet(isPresented: $showCreateSheet) {
            CreateNetworkSheet(connectionID: connectionID, onCreated: { loadNetworks() })
        }
        .alert("Delete Virtual Network", isPresented: .init(
            get: { networkToDelete != nil },
            set: { if !$0 { networkToDelete = nil } }
        )) {
            Button("Cancel", role: .cancel) { networkToDelete = nil }
            Button("Delete", role: .destructive) {
                if let name = networkToDelete {
                    deleteNetwork(name: name)
                    networkToDelete = nil
                }
            }
        } message: {
            if let name = networkToDelete {
                Text("Are you sure you want to delete network '\(name)'? This cannot be undone.")
            }
        }
        .onAppear { loadNetworks() }
    }

    @ViewBuilder
    private func networkRow(_ network: NetworkInfo) -> some View {
        HStack {
            Image(systemName: "network")
                .foregroundStyle(network.isActive ? .green : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(network.name)
                        .fontWeight(.medium)
                    if network.isActive {
                        Text("Active")
                            .font(.caption2)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(.green.opacity(0.2))
                            .cornerRadius(3)
                    } else {
                        Text("Inactive")
                            .font(.caption2)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(.secondary.opacity(0.2))
                            .cornerRadius(3)
                    }
                    if network.autostart {
                        Text("Autostart")
                            .font(.caption2)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(.blue.opacity(0.2))
                            .cornerRadius(3)
                    }
                }
                HStack(spacing: 12) {
                    if let bridge = network.bridge {
                        HStack(spacing: 2) {
                            Text("Bridge:")
                                .foregroundStyle(.secondary)
                            Text(bridge)
                        }
                        .font(.caption)
                    }
                }
            }
            Spacer()

            // Network actions
            if network.isActive {
                Button {
                    stopNetwork(name: network.name)
                } label: {
                    Image(systemName: "stop.circle")
                }
                .buttonStyle(.borderless)
                .help("Stop Network")
            } else {
                Button {
                    startNetwork(name: network.name)
                } label: {
                    Image(systemName: "play.circle")
                }
                .buttonStyle(.borderless)
                .help("Start Network")
            }

            Button(role: .destructive) {
                networkToDelete = network.name
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Delete Network")
        }
        .padding(.vertical, 4)
    }

    // MARK: - Actions

    private func loadNetworks() {
        isLoading = true
        errorMessage = nil
        Task {
            do {
                networks = try await appState.listNetworks(connectionID: connectionID)
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }

    private func startNetwork(name: String) {
        Task {
            do {
                try await appState.startNetwork(name: name, connectionID: connectionID)
                loadNetworks()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func stopNetwork(name: String) {
        Task {
            do {
                try await appState.stopNetwork(name: name, connectionID: connectionID)
                loadNetworks()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func deleteNetwork(name: String) {
        Task {
            do {
                try await appState.deleteNetwork(name: name, connectionID: connectionID)
                loadNetworks()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

// MARK: - Create Network Sheet

struct CreateNetworkSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let connectionID: UUID
    let onCreated: () -> Void

    @State private var networkName = ""
    @State private var mode = "nat"
    @State private var ipAddress = "192.168.122.1"
    @State private var netmask = "255.255.255.0"
    @State private var dhcpStart = "192.168.122.2"
    @State private var dhcpEnd = "192.168.122.254"
    @State private var isCreating = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 16) {
            Text("Create Virtual Network")
                .font(.headline)

            Form {
                TextField("Network Name", text: $networkName)

                Picker("Mode", selection: $mode) {
                    Text("NAT").tag("nat")
                    Text("Routed").tag("route")
                    Text("Isolated").tag("isolated")
                }

                Section("IP Configuration") {
                    TextField("IP Address", text: $ipAddress)
                    TextField("Netmask", text: $netmask)
                    TextField("DHCP Start", text: $dhcpStart)
                    TextField("DHCP End", text: $dhcpEnd)
                }
            }

            if let error = errorMessage {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.caption)
            }

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Create") {
                    createNetwork()
                }
                .buttonStyle(.borderedProminent)
                .disabled(networkName.isEmpty || isCreating)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 420)
    }

    private func createNetwork() {
        isCreating = true
        errorMessage = nil

        let forwardXML: String
        switch mode {
        case "nat":
            forwardXML = "<forward mode='nat'/>"
        case "route":
            forwardXML = "<forward mode='route'/>"
        default:
            forwardXML = "" // isolated, no forward
        }

        let esc = LibvirtSwift.XMLHelpers.escapeXML
        let xml = """
        <network>
          <name>\(esc(networkName))</name>
          \(forwardXML)
          <ip address='\(esc(ipAddress))' netmask='\(esc(netmask))'>
            <dhcp>
              <range start='\(esc(dhcpStart))' end='\(esc(dhcpEnd))'/>
            </dhcp>
          </ip>
        </network>
        """

        Task {
            do {
                try await appState.createNetwork(xml: xml, connectionID: connectionID)
                onCreated()
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                isCreating = false
            }
        }
    }
}
