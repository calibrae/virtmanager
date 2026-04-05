import SwiftUI
import LibvirtSwift

public struct PCIePassthroughTab: View {
    @Binding var config: DomainConfig
    @State private var showAddDevice = false
    @State private var deviceToRemove: HostDevice?

    public init(config: Binding<DomainConfig>) {
        self._config = config
    }

    private var pciDevices: [HostDevice] {
        config.hostDevices.filter { $0.type == .pci }
    }

    public var body: some View {
        VStack(spacing: 0) {
            List {
                if pciDevices.isEmpty {
                    Text("No PCI passthrough devices configured")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(pciDevices) { device in
                        pciDeviceRow(device)
                    }
                }

                Section {
                    Label("PCI passthrough requires IOMMU/VFIO on the host. Changes require a VM restart.",
                          systemImage: "info.circle")
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    Label("GPU passthrough may make the host display unavailable. Ensure you have an alternative access method.",
                          systemImage: "exclamationmark.triangle")
                        .font(.callout)
                        .foregroundStyle(.orange)
                }
            }

            Divider()

            HStack {
                Button("Add PCI Device") { showAddDevice = true }
                Spacer()
                Text("\(pciDevices.count) device(s)")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }
            .padding(8)
        }
        .sheet(isPresented: $showAddDevice) {
            AddPCIDeviceSheet(config: $config, isPresented: $showAddDevice)
        }
        .alert("Remove PCI Device", isPresented: .init(
            get: { deviceToRemove != nil },
            set: { if !$0 { deviceToRemove = nil } }
        )) {
            Button("Cancel", role: .cancel) { deviceToRemove = nil }
            Button("Remove", role: .destructive) {
                if let device = deviceToRemove {
                    config.hostDevices.removeAll { $0.id == device.id }
                    deviceToRemove = nil
                }
            }
        } message: {
            Text("Remove this PCI passthrough device?")
        }
    }

    @ViewBuilder
    private func pciDeviceRow(_ device: HostDevice) -> some View {
        let addr = "\(device.pciDomain ?? "0000"):\(device.pciBus ?? "00"):\(device.pciSlot ?? "00").\(device.pciFunction ?? "0")"
        HStack {
            Image(systemName: "square.grid.3x3.topleft.filled")
            VStack(alignment: .leading, spacing: 2) {
                Text(addr)
                    .fontWeight(.medium)
                    .font(.system(.body, design: .monospaced))
                Text(device.managed ? "Managed" : "Unmanaged")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(role: .destructive) {
                deviceToRemove = device
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 2)
    }
}

private struct AddPCIDeviceSheet: View {
    @Binding var config: DomainConfig
    @Binding var isPresented: Bool
    @State private var domain = "0x0000"
    @State private var bus = ""
    @State private var slot = "0x00"
    @State private var function = "0x0"
    @State private var managed = true

    private static let hexPattern = /^0x[0-9a-fA-F]{1,4}$/
    private static let hexShort = /^0x[0-9a-fA-F]$/

    private var isValid: Bool {
        domain.wholeMatch(of: Self.hexPattern) != nil
            && bus.wholeMatch(of: Self.hexPattern) != nil
            && slot.wholeMatch(of: Self.hexPattern) != nil
            && function.wholeMatch(of: Self.hexShort) != nil
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("Add PCI Passthrough Device")
                .font(.headline)

            Form {
                TextField("Domain (e.g. 0x0000)", text: $domain)
                TextField("Bus (e.g. 0x03)", text: $bus)
                TextField("Slot (e.g. 0x00)", text: $slot)
                TextField("Function (e.g. 0x0)", text: $function)
                Toggle("Managed", isOn: $managed)
            }

            if !bus.isEmpty && !isValid {
                Text("All fields must be hex format (0x prefix). Function is a single hex digit.")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Button("Cancel") { isPresented = false }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Add") {
                    let device = HostDevice(
                        type: .pci,
                        managed: managed,
                        pciDomain: domain,
                        pciBus: bus,
                        pciSlot: slot,
                        pciFunction: function
                    )
                    config.hostDevices.append(device)
                    isPresented = false
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!isValid)
            }
        }
        .padding()
        .frame(width: 380)
    }
}
