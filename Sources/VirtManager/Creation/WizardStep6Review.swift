import SwiftUI
import VirtManagerCore

/// Wizard step 6: Review all settings before creation.
public struct WizardStep6Review: View {
    @Bindable var state: VMCreationState

    public init(state: VMCreationState) {
        self.state = state
    }

    public var body: some View {
        Form {
            Section("General") {
                row("Name", state.name.isEmpty ? "(not set)" : state.name)
                row("OS Type", state.osType)
                if !state.osVariant.isEmpty {
                    row("OS Variant", state.osVariant)
                }
            }

            Section("Resources") {
                row("vCPUs", "\(state.vcpus)")
                row("Memory", "\(state.memoryMB) MB (\(String(format: "%.1f", Double(state.memoryMB) / 1024.0)) GB)")
            }

            Section("Storage") {
                if state.createNewDisk {
                    row("Disk", "New \(state.diskSizeGB) GB \(state.diskFormat) disk")
                    row("Storage Pool", state.storagePool)
                } else {
                    row("Disk", state.existingVolumePath.isEmpty ? "(not set)" : state.existingVolumePath)
                }
            }

            Section("Network") {
                row("Type", state.networkType == "bridge" ? "Bridge" : "Virtual Network")
                row("Source", state.networkSource)
                row("NIC Model", state.nicModel)
            }

            Section("Installation") {
                row("Source", state.installSource.displayName)
            }

            Section("Options") {
                Toggle("Start VM after creation", isOn: $state.startAfterCreation)
            }
        }
        .formStyle(.grouped)
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .fontWeight(.medium)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
        }
    }
}
