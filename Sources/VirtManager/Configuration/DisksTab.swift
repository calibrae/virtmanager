import SwiftUI
import LibvirtSwift

public struct DisksTab: View {
    @Binding var config: DomainConfig
    @State private var showAddDisk = false
    @State private var diskToRemove: DiskDevice?

    public init(config: Binding<DomainConfig>) {
        self._config = config
    }

    public var body: some View {
        VStack(spacing: 0) {
            List {
                ForEach(Array(config.disks.enumerated()), id: \.element.id) { index, disk in
                    diskRow(disk: disk, index: index)
                }
            }

            Divider()

            HStack {
                Button("Add Disk") {
                    showAddDisk = true
                }
                Spacer()
                Text("\(config.disks.count) disk(s)")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }
            .padding(8)
        }
        .sheet(isPresented: $showAddDisk) {
            AddDiskSheet(config: $config, isPresented: $showAddDisk)
        }
        .alert("Remove Disk", isPresented: .init(
            get: { diskToRemove != nil },
            set: { if !$0 { diskToRemove = nil } }
        )) {
            Button("Cancel", role: .cancel) { diskToRemove = nil }
            Button("Remove", role: .destructive) {
                if let disk = diskToRemove {
                    config.disks.removeAll { $0.id == disk.id }
                    diskToRemove = nil
                }
            }
        } message: {
            if let disk = diskToRemove {
                Text("Remove disk \(disk.targetDev)? This cannot be undone.")
            }
        }
    }

    @ViewBuilder
    private func diskRow(disk: DiskDevice, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: disk.device == "cdrom" ? "opticaldisc" : "internaldrive")
                Text(disk.targetDev)
                    .fontWeight(.medium)
                Text("(\(disk.device))")
                    .foregroundStyle(.secondary)
                Spacer()

                if disk.device == "cdrom" {
                    if disk.sourcePath != nil {
                        Button("Eject") {
                            config.disks[index].sourcePath = nil
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    } else {
                        Text("Empty")
                            .foregroundStyle(.secondary)
                            .font(.callout)
                    }
                }

                Button(role: .destructive) {
                    diskToRemove = disk
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
            }

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
                GridRow {
                    Text("Bus").foregroundStyle(.secondary).font(.caption)
                    Picker("", selection: busBinding(index: index)) {
                        ForEach(DiskDevice.DiskBus.allCases, id: \.self) { bus in
                            Text(bus.rawValue).tag(bus)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 100)
                }
                GridRow {
                    Text("Format").foregroundStyle(.secondary).font(.caption)
                    Text(disk.format ?? "—")
                }
                GridRow {
                    Text("Source").foregroundStyle(.secondary).font(.caption)
                    Text(disk.sourcePath ?? "—")
                        .textSelection(.enabled)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .font(.callout)
        }
        .padding(.vertical, 4)
    }

    private func busBinding(index: Int) -> Binding<DiskDevice.DiskBus> {
        Binding(
            get: { config.disks[index].bus },
            set: { config.disks[index].bus = $0 }
        )
    }
}

struct AddDiskSheet: View {
    @Binding var config: DomainConfig
    @Binding var isPresented: Bool

    @State private var device = "disk"
    @State private var bus: DiskDevice.DiskBus = .virtio
    @State private var format = "qcow2"
    @State private var sourcePath = ""
    @State private var targetDev = ""

    var body: some View {
        VStack(spacing: 16) {
            Text("Add Disk")
                .font(.headline)

            Form {
                Picker("Device Type", selection: $device) {
                    Text("Disk").tag("disk")
                    Text("CD-ROM").tag("cdrom")
                }

                Picker("Bus", selection: $bus) {
                    ForEach(DiskDevice.DiskBus.allCases, id: \.self) { b in
                        Text(b.rawValue).tag(b)
                    }
                }

                if device == "disk" {
                    Picker("Format", selection: $format) {
                        Text("qcow2").tag("qcow2")
                        Text("raw").tag("raw")
                        Text("vmdk").tag("vmdk")
                    }
                }

                TextField("Source Path", text: $sourcePath)
                    .help("Full path to the disk image or ISO file")

                TextField("Target Device", text: $targetDev)
                    .help("e.g. vda, sda, hda")
            }

            HStack {
                Button("Cancel") { isPresented = false }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Add") {
                    let disk = DiskDevice(
                        type: "file",
                        device: device,
                        driver: "qemu",
                        format: device == "cdrom" ? "raw" : format,
                        sourcePath: sourcePath.isEmpty ? nil : sourcePath,
                        targetDev: targetDev.isEmpty ? nextTargetDev() : targetDev,
                        bus: bus,
                        isReadonly: device == "cdrom"
                    )
                    config.disks.append(disk)
                    isPresented = false
                }
                .keyboardShortcut(.defaultAction)
                .disabled(targetDev.isEmpty && nextTargetDev().isEmpty)
            }
        }
        .padding()
        .frame(width: 400)
        .onAppear {
            targetDev = nextTargetDev()
        }
    }

    private func nextTargetDev() -> String {
        let prefix: String
        switch bus {
        case .virtio: prefix = "vd"
        case .ide: prefix = "hd"
        case .scsi, .sata, .usb: prefix = "sd"
        case .fdc: prefix = "fd"
        }
        let letters = "abcdefghijklmnopqrstuvwxyz"
        let used = Set(config.disks.map(\.targetDev))
        for letter in letters {
            let candidate = "\(prefix)\(letter)"
            if !used.contains(candidate) {
                return candidate
            }
        }
        return ""
    }
}
