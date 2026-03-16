import SwiftUI
import LibvirtSwift

public struct BootTab: View {
    @Binding var config: DomainConfig

    public init(config: Binding<DomainConfig>) {
        self._config = config
    }

    public var body: some View {
        Form {
            Section("Boot Order") {
                if config.bootDevices.isEmpty {
                    Text("No boot devices configured")
                        .foregroundStyle(.secondary)
                } else {
                    List {
                        ForEach(Array(config.bootDevices.enumerated()), id: \.offset) { index, device in
                            HStack {
                                Image(systemName: bootDeviceIcon(device))
                                Text(bootDeviceLabel(device))
                                Spacer()
                                Button {
                                    moveUp(index)
                                } label: {
                                    Image(systemName: "arrow.up")
                                }
                                .disabled(index == 0)
                                .buttonStyle(.borderless)

                                Button {
                                    moveDown(index)
                                } label: {
                                    Image(systemName: "arrow.down")
                                }
                                .disabled(index == config.bootDevices.count - 1)
                                .buttonStyle(.borderless)

                                Button(role: .destructive) {
                                    config.bootDevices.remove(at: index)
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                    }
                    .frame(minHeight: 100)
                }

                HStack {
                    Menu("Add Boot Device") {
                        ForEach(availableDevices, id: \.self) { dev in
                            Button(bootDeviceLabel(dev)) {
                                config.bootDevices.append(dev)
                            }
                        }
                    }
                    .disabled(availableDevices.isEmpty)
                }
            }

            Section("Boot Menu") {
                Text("Boot menu is controlled via the boot order above.")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }
        }
        .formStyle(.grouped)
    }

    private var availableDevices: [String] {
        let all = ["hd", "cdrom", "network", "fd"]
        return all.filter { !config.bootDevices.contains($0) }
    }

    private func moveUp(_ index: Int) {
        guard index > 0 else { return }
        config.bootDevices.swapAt(index, index - 1)
    }

    private func moveDown(_ index: Int) {
        guard index < config.bootDevices.count - 1 else { return }
        config.bootDevices.swapAt(index, index + 1)
    }

    private func bootDeviceIcon(_ device: String) -> String {
        switch device {
        case "hd": return "internaldrive"
        case "cdrom": return "opticaldisc"
        case "network": return "network"
        case "fd": return "doc"
        default: return "questionmark.circle"
        }
    }

    private func bootDeviceLabel(_ device: String) -> String {
        switch device {
        case "hd": return "Hard Disk"
        case "cdrom": return "CD-ROM"
        case "network": return "Network (PXE)"
        case "fd": return "Floppy"
        default: return device
        }
    }
}
