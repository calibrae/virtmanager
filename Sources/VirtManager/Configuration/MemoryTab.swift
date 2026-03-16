import SwiftUI
import LibvirtSwift

public struct MemoryTab: View {
    @Binding var config: DomainConfig

    public init(config: Binding<DomainConfig>) {
        self._config = config
    }

    public var body: some View {
        Form {
            Section("Maximum Memory") {
                HStack {
                    TextField("Memory (MB)", value: memoryMBBinding, format: .number)
                        .frame(width: 120)
                    Text("MB")
                    Spacer()
                    Text("(\(config.memoryKiB) KiB)")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }

                Slider(value: memorySliderBinding, in: 64...65536, step: 64) {
                    Text("Memory")
                } minimumValueLabel: {
                    Text("64")
                } maximumValueLabel: {
                    Text("64 GB")
                }

                if memoryMB > 32768 {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.yellow)
                        Text("Memory exceeds 32 GB. Ensure the host has sufficient RAM.")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Current Memory (Balloon)") {
                Toggle("Set current memory", isOn: currentMemoryEnabled)

                if config.currentMemoryKiB != nil {
                    HStack {
                        TextField("Current Memory (MB)", value: currentMemoryMBBinding, format: .number)
                            .frame(width: 120)
                        Text("MB")
                    }

                    if let cur = config.currentMemoryKiB, cur > config.memoryKiB {
                        HStack {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.red)
                            Text("Current memory cannot exceed maximum memory.")
                                .foregroundStyle(.red)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private var memoryMB: UInt64 {
        config.memoryKiB / 1024
    }

    private var memoryMBBinding: Binding<UInt64> {
        Binding(
            get: { config.memoryKiB / 1024 },
            set: { config.memoryKiB = $0 * 1024 }
        )
    }

    private var memorySliderBinding: Binding<Double> {
        Binding(
            get: { Double(config.memoryKiB / 1024) },
            set: { config.memoryKiB = UInt64($0) * 1024 }
        )
    }

    private var currentMemoryEnabled: Binding<Bool> {
        Binding(
            get: { config.currentMemoryKiB != nil },
            set: { enabled in
                if enabled {
                    config.currentMemoryKiB = config.memoryKiB
                } else {
                    config.currentMemoryKiB = nil
                }
            }
        )
    }

    private var currentMemoryMBBinding: Binding<UInt64> {
        Binding(
            get: { (config.currentMemoryKiB ?? 0) / 1024 },
            set: { config.currentMemoryKiB = $0 * 1024 }
        )
    }
}
