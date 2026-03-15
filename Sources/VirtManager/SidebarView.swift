import SwiftUI
import VirtManagerCore

public struct SidebarView: View {
    @Environment(AppState.self) private var appState

    public init() {}

    public var body: some View {
        @Bindable var state = appState

        List(selection: $state.selectedVMID) {
            if appState.savedConnections.isEmpty {
                ContentUnavailableView(
                    "No Connections",
                    systemImage: "network",
                    description: Text("Click + to add a connection to a libvirt host.")
                )
            } else {
                ForEach(appState.savedConnections) { connection in
                    Section {
                        connectionRow(connection)
                        vmRows(for: connection)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("VirtManager")
    }

    @ViewBuilder
    private func connectionRow(_ connection: SavedConnection) -> some View {
        HStack {
            connectionStateIcon(for: connection.id)
            VStack(alignment: .leading) {
                Text(connection.displayName)
                    .font(.headline)
                Text(connection.uri)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .contextMenu {
            connectionContextMenu(connection)
        }
    }

    @ViewBuilder
    private func vmRows(for connection: SavedConnection) -> some View {
        let vms = appState.connectionVMs[connection.id] ?? []
        ForEach(vms) { vm in
            HStack {
                VMStateBadge(state: vm.state)
                Text(vm.name)
            }
            .tag(vm.id)
        }

        if appState.connectionStates[connection.id] == .connected && vms.isEmpty {
            Text("No virtual machines")
                .foregroundStyle(.secondary)
                .font(.caption)
        }
    }

    private func connectionStateIcon(for id: UUID) -> some View {
        let state = appState.connectionStates[id] ?? .disconnected
        let (icon, color): (String, Color) = switch state {
        case .disconnected: ("circle", .secondary)
        case .connecting: ("circle.dotted", .orange)
        case .connected: ("circle.fill", .green)
        case .disconnecting: ("circle.dotted", .orange)
        case .error: ("exclamationmark.circle.fill", .red)
        }
        return Image(systemName: icon)
            .foregroundStyle(color)
    }

    @ViewBuilder
    private func connectionContextMenu(_ connection: SavedConnection) -> some View {
        let state = appState.connectionStates[connection.id] ?? .disconnected

        if state == .connected {
            Button("Disconnect") {
                appState.disconnect(from: connection.id)
            }
            Button("Refresh VMs") {
                appState.refreshVMs(for: connection.id)
            }
        } else if state == .connecting || state == .disconnecting {
            // No connect/disconnect actions while transitioning
        } else {
            Button("Connect") {
                appState.connect(to: connection)
            }
        }

        Divider()

        Button("Edit...") {
            appState.editingConnection = connection
            appState.isShowingConnectionSheet = true
        }

        Button("Remove", role: .destructive) {
            appState.removeConnection(connection)
        }
    }
}
