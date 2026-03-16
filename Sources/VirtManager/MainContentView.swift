import SwiftUI
import VirtManagerCore

public struct MainContentView: View {
    @Environment(AppState.self) private var appState
    @State private var isShowingCreationWizard = false

    public init() {}

    public var body: some View {
        @Bindable var state = appState

        NavigationSplitView {
            SidebarView()
        } detail: {
            if let vm = appState.selectedVM() {
                VMDetailView(vm: vm)
            } else {
                ContentUnavailableView(
                    "No VM Selected",
                    systemImage: "desktopcomputer",
                    description: Text("Select a virtual machine from the sidebar, or add a connection to get started.")
                )
            }
        }
        .sheet(isPresented: $state.isShowingConnectionSheet) {
            ConnectionSheet(existingConnection: appState.editingConnection)
        }
        .sheet(isPresented: $isShowingCreationWizard) {
            if let connID = appState.selectedConnectionID ?? appState.savedConnections.first(where: { appState.connectionStates[$0.id] == .connected })?.id {
                VMCreationWizard(connectionID: connID)
            } else {
                VStack(spacing: 12) {
                    Text("No active connection")
                        .font(.headline)
                    Text("Connect to a hypervisor before creating a VM.")
                        .foregroundStyle(.secondary)
                    Button("OK") { isShowingCreationWizard = false }
                        .buttonStyle(.borderedProminent)
                }
                .padding(40)
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    appState.editingConnection = nil
                    appState.isShowingConnectionSheet = true
                } label: {
                    Label("Add Connection", systemImage: "plus")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isShowingCreationWizard = true
                } label: {
                    Label("New VM", systemImage: "desktopcomputer.and.arrow.down")
                }
                .disabled(!hasConnectedConnection)
            }
        }
        .overlay(alignment: .bottom) {
            StatusBar()
        }
    }

    private var hasConnectedConnection: Bool {
        appState.savedConnections.contains { conn in
            appState.connectionStates[conn.id] == .connected
        }
    }
}
