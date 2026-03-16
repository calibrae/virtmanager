import SwiftUI
import AppKit
import SpiceClient

/// Shows available USB devices and allows redirecting them to a SPICE VM.
/// Also supports sharing a local ISO/IMG as a virtual USB CD-ROM.
struct USBRedirectionView: View {
    let spiceConnection: SpiceConnection

    @State private var devices: [USBDeviceInfo] = []
    @State private var pendingDeviceIDs: Set<String> = []
    @State private var errorMessage: String?
    @State private var isShareCDPending = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Image(systemName: "cable.connector")
                    .foregroundStyle(.secondary)
                Text("USB Devices")
                    .font(.headline)
                Spacer()
                Button { refreshDevices() } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Refresh device list")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider()

            // Share ISO as USB CD button
            Button {
                shareISOAsCD()
            } label: {
                Label("Share ISO as USB CD-ROM...", systemImage: "opticaldisc")
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .disabled(isShareCDPending)

            Divider()

            if devices.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "cable.connector.slash")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("No USB devices found")
                        .foregroundStyle(.secondary)
                    Text("Connect a USB device to your Mac,\nor share an ISO as a virtual USB CD.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, minHeight: 100)
                .padding()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(devices) { device in
                            USBDeviceRow(
                                device: device,
                                isPending: pendingDeviceIDs.contains(device.id),
                                onToggle: { toggleDevice(device) }
                            )
                            Divider().padding(.leading, 40)
                        }
                    }
                }
                .frame(maxHeight: 300)
            }

            if let errorMessage {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }
        }
        .frame(width: 340)
        .onAppear {
            setupCallbacks()
            refreshDevices()
        }
    }

    private func shareISOAsCD() {
        let panel = NSOpenPanel()
        panel.title = "Select ISO or IMG to share as USB CD-ROM"
        panel.allowedContentTypes = [.init(filenameExtension: "iso")!, .init(filenameExtension: "img")!]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let usbManager = spiceConnection.usbManager else {
            errorMessage = "USB manager not available"
            return
        }

        isShareCDPending = true
        errorMessage = nil

        usbManager.shareCD(filePath: url.path) { success, error in
            isShareCDPending = false
            if success {
                refreshDevices()
            } else {
                errorMessage = error ?? "Failed to share CD"
            }
        }
    }

    private func setupCallbacks() {
        guard let usbManager = spiceConnection.usbManager else { return }
        usbManager.onDeviceListChanged = { refreshDevices() }
        usbManager.onError = { msg in errorMessage = msg }
    }

    private func refreshDevices() {
        guard let usbManager = spiceConnection.usbManager else {
            devices = []
            return
        }
        usbManager.listDevices { newDevices in
            devices = newDevices
        }
    }

    private func toggleDevice(_ device: USBDeviceInfo) {
        guard let usbManager = spiceConnection.usbManager else { return }
        pendingDeviceIDs.insert(device.id)
        errorMessage = nil

        if device.isConnected {
            usbManager.disconnectDevice(device: device) { success, error in
                pendingDeviceIDs.remove(device.id)
                if !success { errorMessage = error ?? "Failed to disconnect" }
                refreshDevices()
            }
        } else {
            usbManager.connectDevice(device: device) { success, error in
                pendingDeviceIDs.remove(device.id)
                if !success { errorMessage = error ?? "Failed to redirect" }
                refreshDevices()
            }
        }
    }
}

// MARK: - Device Row

private struct USBDeviceRow: View {
    let device: USBDeviceInfo
    let isPending: Bool
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(isPending ? .orange : device.isConnected ? .green : .gray)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                Text(device.description)
                    .lineLimit(1)
                Text(device.isConnected ? "Redirected to VM" : "Available")
                    .font(.caption)
                    .foregroundStyle(device.isConnected ? .green : .secondary)
            }

            Spacer()

            if isPending {
                ProgressView().controlSize(.small)
            } else {
                Button(device.isConnected ? "Disconnect" : "Redirect") { onToggle() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(device.isConnected ? .red : .accentColor)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}
