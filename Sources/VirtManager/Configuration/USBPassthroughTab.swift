import SwiftUI
import LibvirtSwift

public struct USBPassthroughTab: View {
    @Binding var config: DomainConfig
    @State private var showAddDevice = false
    @State private var deviceToRemove: HostDevice?

    public init(config: Binding<DomainConfig>) {
        self._config = config
    }

    private var usbDevices: [HostDevice] {
        config.hostDevices.filter { $0.type == .usb }
    }

    public var body: some View {
        VStack(spacing: 0) {
            List {
                if usbDevices.isEmpty {
                    Text("No USB passthrough devices configured")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(usbDevices) { device in
                        usbDeviceRow(device)
                    }
                }

                Section {
                    Label("USB passthrough detaches the device from the host. The VM must be restarted for changes to take effect.",
                          systemImage: "info.circle")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            HStack {
                Button("Add USB Device") { showAddDevice = true }
                Spacer()
                Text("\(usbDevices.count) device(s)")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }
            .padding(8)
        }
        .sheet(isPresented: $showAddDevice) {
            AddUSBDeviceSheet(config: $config, isPresented: $showAddDevice)
        }
        .alert("Remove USB Device", isPresented: .init(
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
            Text("Remove this USB passthrough device?")
        }
    }

    @ViewBuilder
    private func usbDeviceRow(_ device: HostDevice) -> some View {
        HStack {
            Image(systemName: "cable.connector")
            VStack(alignment: .leading, spacing: 2) {
                Text("Vendor: \(device.usbVendorID ?? "—")  Product: \(device.usbProductID ?? "—")")
                    .fontWeight(.medium)
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

private struct AddUSBDeviceSheet: View {
    @Binding var config: DomainConfig
    @Binding var isPresented: Bool
    @State private var vendorID = ""
    @State private var productID = ""
    @State private var managed = true

    private var isValidHex: Bool {
        let hexPattern = /^0x[0-9a-fA-F]{1,4}$/
        return vendorID.wholeMatch(of: hexPattern) != nil
            && productID.wholeMatch(of: hexPattern) != nil
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("Add USB Passthrough Device")
                .font(.headline)

            Form {
                TextField("Vendor ID (e.g. 0x1234)", text: $vendorID)
                TextField("Product ID (e.g. 0x5678)", text: $productID)
                Toggle("Managed", isOn: $managed)
            }

            if !vendorID.isEmpty && !isValidHex {
                Text("IDs must be hex format: 0x followed by 1-4 hex digits")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Button("Cancel") { isPresented = false }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Add") {
                    let device = HostDevice(
                        type: .usb,
                        managed: managed,
                        usbVendorID: vendorID,
                        usbProductID: productID
                    )
                    config.hostDevices.append(device)
                    isPresented = false
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!isValidHex)
            }
        }
        .padding()
        .frame(width: 380)
    }
}
