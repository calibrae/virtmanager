import SwiftUI

/// Wizard step 2: CPU and memory configuration.
public struct WizardStep2CPUMemory: View {
    @Bindable var state: VMCreationState

    public init(state: VMCreationState) {
        self.state = state
    }

    public var body: some View {
        Form {
            Section("CPU") {
                Stepper("vCPUs: \(state.vcpus)", value: $state.vcpus, in: 1...64)
            }

            Section("Memory") {
                HStack {
                    Text("Memory: \(state.memoryMB) MB")
                    Spacer()
                    Text(formatMemory(state.memoryMB))
                        .foregroundStyle(.secondary)
                }
                Slider(
                    value: Binding(
                        get: { Double(state.memoryMB) },
                        set: { state.memoryMB = Int($0) }
                    ),
                    in: 256...65536,
                    step: 256
                )
                HStack {
                    ForEach([1024, 2048, 4096, 8192, 16384], id: \.self) { preset in
                        Button("\(preset / 1024) GB") {
                            state.memoryMB = preset
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func formatMemory(_ mb: Int) -> String {
        if mb >= 1024 {
            let gb = Double(mb) / 1024.0
            return String(format: "%.1f GB", gb)
        }
        return "\(mb) MB"
    }
}
