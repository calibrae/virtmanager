import SwiftUI
import VirtManagerCore

public struct MainContentView: View {
    @Environment(AppState.self) private var appState

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
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    appState.editingConnection = nil
                    appState.isShowingConnectionSheet = true
                } label: {
                    Label("Add Connection", systemImage: "plus")
                }
            }
        }
        .overlay(alignment: .bottom) {
            StatusBar()
        }
    }
}
