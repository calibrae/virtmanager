import SwiftUI

/// Wizard step 3: Storage configuration.
public struct WizardStep3Storage: View {
    @Environment(AppState.self) private var appState
    @Bindable var state: VMCreationState
    let connectionID: UUID

    @State private var poolNames: [String] = ["default"]
    @State private var showVolumeBrowser = false

    public init(state: VMCreationState, connectionID: UUID) {
        self.state = state
        self.connectionID = connectionID
    }

    public var body: some View {
        Form {
            Section("Disk") {
                Toggle("Create new disk", isOn: $state.createNewDisk)

                if state.createNewDisk {
                    Stepper("Size: \(state.diskSizeGB) GB", value: $state.diskSizeGB, in: 1...2000)

                    Picker("Format", selection: $state.diskFormat) {
                        Text("qcow2").tag("qcow2")
                        Text("raw").tag("raw")
                    }

                    Picker("Storage Pool", selection: $state.storagePool) {
                        ForEach(poolNames, id: \.self) { name in
                            Text(name).tag(name)
                        }
                    }
                } else {
                    HStack {
                        TextField("Volume path", text: $state.existingVolumePath)
                            .textFieldStyle(.roundedBorder)
                        Button("Browse...") {
                            showVolumeBrowser = true
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { loadPools() }
        .sheet(isPresented: $showVolumeBrowser) {
            StoragePoolBrowserView(connectionID: connectionID) { path in
                state.existingVolumePath = path
            }
        }
    }

    private func loadPools() {
        Task {
            do {
                let pools = try await appState.listStoragePoolsWithVolumes(connectionID: connectionID)
                poolNames = pools.map { $0.name }
                if !poolNames.contains(state.storagePool), let first = poolNames.first {
                    state.storagePool = first
                }
            } catch {
                // Keep default
            }
        }
    }
}
