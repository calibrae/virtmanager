import SwiftUI
import LibvirtSwift
import VirtManagerCore

/// Full-featured network list replacing the basic NetworkManager.
public struct NetworkListView: View {
    @Environment(AppState.self) private var appState

    public let connectionID: UUID

    @State private var networks: [NetworkInfo] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var searchText = ""
    @State private var showCreateSheet = false
    @State private var networkToDelete: String?
    @State private var showConfigEditor = false
    @State private var selectedNetworkName: String = ""

    public init(connectionID: UUID) {
        self.connectionID = connectionID
    }

    private var filteredNetworks: [NetworkInfo] {
        if searchText.isEmpty { return networks }
        return networks.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    public var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()

            if isLoading {
                Spacer()
                ProgressView("Loading networks...")
                Spacer()
            } else if let error = errorMessage {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundStyle(.red)
                    Text(error)
                        .foregroundStyle(.secondary)
                    Button("Retry") { loadNetworks() }
                }
                Spacer()
            } else if filteredNetworks.isEmpty {
                Spacer()
                ContentUnavailableView(
                    searchText.isEmpty ? "No Virtual Networks" : "No Matching Networks",
                    systemImage: "network",
                    description: Text(searchText.isEmpty
                        ? "Create a virtual network to get started."
                        : "No networks match '\(searchText)'.")
                )
                Spacer()
            } else {
                networkList
            }
        }
        .sheet(isPresented: $showCreateSheet) {
            CreateNetworkSheet(connectionID: connectionID, onCreated: { loadNetworks() })
        }
        .sheet(isPresented: $showConfigEditor) {
            NetworkConfigurationView(networkName: selectedNetworkName, connectionID: connectionID)
                .frame(minWidth: 700, minHeight: 500)
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

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack {
            Text("Virtual Networks")
                .font(.headline)
            Spacer()

            TextField("Filter", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 180)

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
    }

    // MARK: - Network List

    private var networkList: some View {
        List {
            ForEach(filteredNetworks, id: \.uuid) { network in
                networkRow(network)
                    .contextMenu { contextMenuItems(for: network) }
            }
        }
        .listStyle(.inset)
    }

    @ViewBuilder
    private func networkRow(_ network: NetworkInfo) -> some View {
        HStack {
            Image(systemName: "network")
                .foregroundStyle(network.isActive ? .green : .secondary)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(network.name)
                        .fontWeight(.medium)

                    modeBadge(network.forwardMode)

                    if network.isActive {
                        badge("Active", color: .green)
                    } else {
                        badge("Inactive", color: .secondary)
                    }

                    if network.autostart {
                        badge("Autostart", color: .blue)
                    }
                }

                HStack(spacing: 12) {
                    if let ipv4 = network.ipv4Summary {
                        HStack(spacing: 2) {
                            Text("IPv4:")
                                .foregroundStyle(.secondary)
                            Text(ipv4)
                        }
                        .font(.caption)
                    }
                    if let ipv6 = network.ipv6Summary {
                        HStack(spacing: 2) {
                            Text("IPv6:")
                                .foregroundStyle(.secondary)
                            Text(ipv6)
                        }
                        .font(.caption)
                    }
                    if network.connectedVMCount > 0 {
                        HStack(spacing: 2) {
                            Image(systemName: "desktopcomputer")
                            Text("\(network.connectedVMCount)")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            // Quick actions
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

            Button {
                selectedNetworkName = network.name
                showConfigEditor = true
            } label: {
                Image(systemName: "slider.horizontal.3")
            }
            .buttonStyle(.borderless)
            .help("Edit Configuration")
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func contextMenuItems(for network: NetworkInfo) -> some View {
        if network.isActive {
            Button("Stop") { stopNetwork(name: network.name) }
        } else {
            Button("Start") { startNetwork(name: network.name) }
        }
        Divider()
        Button("Edit Configuration") {
            selectedNetworkName = network.name
            showConfigEditor = true
        }
        Button("Toggle Autostart") { toggleAutostart(network: network) }
        Divider()
        Button("Delete", role: .destructive) { networkToDelete = network.name }
    }

    // MARK: - Badge Helpers

    private func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(color.opacity(0.2))
            .cornerRadius(3)
    }

    private func modeBadge(_ mode: String) -> some View {
        Text(mode.uppercased())
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(.purple.opacity(0.15))
            .cornerRadius(3)
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

    private func toggleAutostart(network: NetworkInfo) {
        Task {
            do {
                try await appState.setNetworkAutostart(
                    name: network.name,
                    autostart: !network.autostart,
                    connectionID: connectionID
                )
                loadNetworks()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
