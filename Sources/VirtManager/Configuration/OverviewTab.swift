import SwiftUI
import LibvirtSwift

public struct OverviewTab: View {
    @Binding var config: DomainConfig

    public init(config: Binding<DomainConfig>) {
        self._config = config
    }

    public var body: some View {
        Form {
            Section("Identity") {
                TextField("Name", text: $config.name)
                TextField("Title", text: optionalBinding($config.title))
                TextField("Description", text: optionalBinding($config.description))
            }

            Section("Machine") {
                TextField("Machine Type", text: optionalBinding($config.machineType))
                    .help("e.g. pc-q35-8.1, pc-i440fx-6.2")
                TextField("Architecture", text: optionalBinding($config.arch))
                    .help("e.g. x86_64, aarch64")
                Picker("Firmware", selection: firmwareBinding) {
                    Text("BIOS").tag("bios")
                    Text("EFI / UEFI").tag("efi")
                }
            }

            Section("Info") {
                LabeledContent("UUID", value: config.uuid)
                    .textSelection(.enabled)
            }
        }
        .formStyle(.grouped)
    }

    private var firmwareBinding: Binding<String> {
        Binding(
            get: { config.firmware ?? "bios" },
            set: { config.firmware = $0 }
        )
    }

    private func optionalBinding(_ binding: Binding<String?>) -> Binding<String> {
        Binding(
            get: { binding.wrappedValue ?? "" },
            set: { binding.wrappedValue = $0.isEmpty ? nil : $0 }
        )
    }
}
