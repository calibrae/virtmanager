import SwiftUI
import LibvirtSwift

public struct CPUTab: View {
    @Binding var config: DomainConfig

    public init(config: Binding<DomainConfig>) {
        self._config = config
    }

    public var body: some View {
        Form {
            Section("vCPUs") {
                Stepper("vCPU Count: \(config.vcpus)", value: $config.vcpus, in: 1...512)
            }

            Section("CPU Mode") {
                Picker("Mode", selection: cpuModeBinding) {
                    Text("Host Passthrough").tag("host-passthrough")
                    Text("Host Model").tag("host-model")
                    Text("Custom").tag("custom")
                    Text("Default (none)").tag("")
                }

                if config.cpuMode == "custom" {
                    TextField("CPU Model", text: cpuModelBinding)
                }
            }

            Section("Topology") {
                Toggle("Define topology", isOn: topologyEnabled)

                if config.topologySockets != nil {
                    Stepper("Sockets: \(config.topologySockets ?? 1)",
                            value: socketsBinding, in: 1...64)
                    Stepper("Cores: \(config.topologyCores ?? 1)",
                            value: coresBinding, in: 1...256)
                    Stepper("Threads: \(config.topologyThreads ?? 1)",
                            value: threadsBinding, in: 1...4)

                    let product = (config.topologySockets ?? 1) * (config.topologyCores ?? 1) * (config.topologyThreads ?? 1)
                    if product != config.vcpus {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.yellow)
                            Text("Topology (\(product)) does not match vCPU count (\(config.vcpus))")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private var cpuModeBinding: Binding<String> {
        Binding(
            get: { config.cpuMode ?? "" },
            set: { config.cpuMode = $0.isEmpty ? nil : $0 }
        )
    }

    private var cpuModelBinding: Binding<String> {
        Binding(
            get: { config.cpuModel ?? "" },
            set: { config.cpuModel = $0.isEmpty ? nil : $0 }
        )
    }

    private var topologyEnabled: Binding<Bool> {
        Binding(
            get: { config.topologySockets != nil },
            set: { enabled in
                if enabled {
                    config.topologySockets = 1
                    config.topologyCores = config.vcpus
                    config.topologyThreads = 1
                } else {
                    config.topologySockets = nil
                    config.topologyCores = nil
                    config.topologyThreads = nil
                }
            }
        )
    }

    private var socketsBinding: Binding<Int> {
        Binding(get: { config.topologySockets ?? 1 }, set: { config.topologySockets = $0 })
    }
    private var coresBinding: Binding<Int> {
        Binding(get: { config.topologyCores ?? 1 }, set: { config.topologyCores = $0 })
    }
    private var threadsBinding: Binding<Int> {
        Binding(get: { config.topologyThreads ?? 1 }, set: { config.topologyThreads = $0 })
    }
}
