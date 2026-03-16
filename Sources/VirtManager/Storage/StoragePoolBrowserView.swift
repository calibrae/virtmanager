import SwiftUI
import VirtManagerCore
import LibvirtSwift

/// A SwiftUI view for browsing storage pools and their volumes.
/// Allows the user to expand a pool to see volumes, and select a volume path.
public struct StoragePoolBrowserView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    public let connectionID: UUID
    public let onSelect: (String) -> Void

    @State private var pools: [PoolWithVolumes] = []
    @State private var isLoading = false
    @State private var expandedPools: Set<String> = []
    @State private var selectedVolumePath: String?
    @State private var errorMessage: String?

    public init(connectionID: UUID, onSelect: @escaping (String) -> Void) {
        self.connectionID = connectionID
        self.onSelect = onSelect
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Storage Browser")
                    .font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding()

            Divider()

            if isLoading {
                Spacer()
                ProgressView("Loading storage pools...")
                Spacer()
            } else if let error = errorMessage {
                Spacer()
                Text(error)
                    .foregroundStyle(.red)
                Spacer()
            } else if pools.isEmpty {
                Spacer()
                Text("No storage pools found.")
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                List(selection: $selectedVolumePath) {
                    ForEach(pools) { pool in
                        DisclosureGroup(isExpanded: binding(for: pool.name)) {
                            ForEach(pool.volumes) { vol in
                                HStack {
                                    Image(systemName: iconForFormat(vol.format))
                                    VStack(alignment: .leading) {
                                        Text(vol.name)
                                        Text(vol.path)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text(formatBytes(vol.capacity))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .tag(vol.path)
                            }
                        } label: {
                            HStack {
                                Image(systemName: "externaldrive.fill")
                                VStack(alignment: .leading) {
                                    Text(pool.name)
                                        .fontWeight(.medium)
                                    Text("\(formatBytes(pool.allocation)) / \(formatBytes(pool.capacity))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if pool.isActive {
                                    Text("Active")
                                        .font(.caption2)
                                        .foregroundStyle(.green)
                                }
                            }
                        }
                    }
                }
                .listStyle(.inset)
            }

            HStack {
                Button("Refresh") { loadPools() }
                Spacer()
                Button("Select") {
                    if let path = selectedVolumePath {
                        onSelect(path)
                        dismiss()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedVolumePath == nil)
            }
            .padding()
        }
        .frame(width: 550, height: 450)
        .onAppear { loadPools() }
    }

    // MARK: - Helpers

    private func binding(for poolName: String) -> Binding<Bool> {
        Binding(
            get: { expandedPools.contains(poolName) },
            set: { isExpanded in
                if isExpanded {
                    expandedPools.insert(poolName)
                } else {
                    expandedPools.remove(poolName)
                }
            }
        )
    }

    private func loadPools() {
        isLoading = true
        errorMessage = nil
        Task {
            do {
                pools = try await appState.listStoragePoolsWithVolumes(connectionID: connectionID)
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }

    private func iconForFormat(_ format: String) -> String {
        switch format {
        case "iso": return "opticaldisc"
        case "qcow2": return "internaldrive"
        default: return "doc"
        }
    }

    private func formatBytes(_ bytes: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
}

// MARK: - Supporting Types

/// A pool with its volumes loaded for display.
public struct PoolWithVolumes: Identifiable, Sendable {
    public let id: String
    public let name: String
    public let isActive: Bool
    public let capacity: UInt64
    public let allocation: UInt64
    public let volumes: [VolumeEntry]
}

/// A volume entry for display in the pool browser.
public struct VolumeEntry: Identifiable, Sendable {
    public let id: String
    public let name: String
    public let path: String
    public let capacity: UInt64
    public let format: String
}
