import SwiftUI
import VirtManagerCore
import LibvirtSwift

/// A SwiftUI view for managing storage pools on a hypervisor.
/// Lists all pools with name, state, capacity bar, and path.
/// Pools can be expanded to see volumes. Supports create, delete, start, stop, and refresh.
public struct StoragePoolManager: View {
    @Environment(AppState.self) private var appState

    public let connectionID: UUID

    @State private var pools: [PoolWithVolumes] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var expandedPools: Set<String> = []
    @State private var showCreateSheet = false
    @State private var poolToDelete: String?

    public init(connectionID: UUID) {
        self.connectionID = connectionID
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                Text("Storage Pools")
                    .font(.headline)
                Spacer()
                Button {
                    showCreateSheet = true
                } label: {
                    Label("Create Pool", systemImage: "plus")
                }
                Button {
                    loadPools()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
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
                ContentUnavailableView(
                    "No Storage Pools",
                    systemImage: "externaldrive",
                    description: Text("Create a storage pool to get started.")
                )
                Spacer()
            } else {
                List {
                    ForEach(pools) { pool in
                        DisclosureGroup(isExpanded: expandedBinding(for: pool.name)) {
                            ForEach(pool.volumes) { vol in
                                HStack {
                                    Image(systemName: iconForFormat(vol.format))
                                        .foregroundStyle(.secondary)
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
                            }

                            if pool.volumes.isEmpty {
                                Text("No volumes")
                                    .foregroundStyle(.secondary)
                                    .font(.caption)
                            }
                        } label: {
                            poolRow(pool)
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
        .sheet(isPresented: $showCreateSheet) {
            CreatePoolSheet(connectionID: connectionID, onCreated: { loadPools() })
        }
        .alert("Delete Storage Pool", isPresented: .init(
            get: { poolToDelete != nil },
            set: { if !$0 { poolToDelete = nil } }
        )) {
            Button("Cancel", role: .cancel) { poolToDelete = nil }
            Button("Delete", role: .destructive) {
                if let name = poolToDelete {
                    deletePool(name: name)
                    poolToDelete = nil
                }
            }
        } message: {
            if let name = poolToDelete {
                Text("Are you sure you want to delete pool '\(name)'? This cannot be undone.")
            }
        }
        .onAppear { loadPools() }
    }

    @ViewBuilder
    private func poolRow(_ pool: PoolWithVolumes) -> some View {
        HStack {
            Image(systemName: "externaldrive.fill")
                .foregroundStyle(pool.isActive ? .green : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(pool.name)
                        .fontWeight(.medium)
                    if pool.isActive {
                        Text("Active")
                            .font(.caption2)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(.green.opacity(0.2))
                            .cornerRadius(3)
                    } else {
                        Text("Inactive")
                            .font(.caption2)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(.secondary.opacity(0.2))
                            .cornerRadius(3)
                    }
                }
                if pool.capacity > 0 {
                    HStack(spacing: 4) {
                        ProgressView(value: Double(pool.allocation), total: Double(pool.capacity))
                            .frame(width: 80)
                        Text("\(formatBytes(pool.allocation)) / \(formatBytes(pool.capacity))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()

            // Pool actions
            if pool.isActive {
                Button {
                    stopPool(name: pool.name)
                } label: {
                    Image(systemName: "stop.circle")
                }
                .buttonStyle(.borderless)
                .help("Stop Pool")
            } else {
                Button {
                    startPool(name: pool.name)
                } label: {
                    Image(systemName: "play.circle")
                }
                .buttonStyle(.borderless)
                .help("Start Pool")
            }

            Button {
                refreshPool(name: pool.name)
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("Refresh Pool")

            Button(role: .destructive) {
                poolToDelete = pool.name
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Delete Pool")
        }
    }

    // MARK: - Helpers

    private func expandedBinding(for poolName: String) -> Binding<Bool> {
        Binding(
            get: { expandedPools.contains(poolName) },
            set: { isExpanded in
                if isExpanded { expandedPools.insert(poolName) }
                else { expandedPools.remove(poolName) }
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

    private func startPool(name: String) {
        Task {
            do {
                try await appState.startPool(name: name, connectionID: connectionID)
                loadPools()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func stopPool(name: String) {
        Task {
            do {
                try await appState.stopPool(name: name, connectionID: connectionID)
                loadPools()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func refreshPool(name: String) {
        Task {
            do {
                try await appState.refreshPool(name: name, connectionID: connectionID)
                loadPools()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func deletePool(name: String) {
        Task {
            do {
                try await appState.deletePool(name: name, connectionID: connectionID)
                loadPools()
            } catch {
                errorMessage = error.localizedDescription
            }
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

// MARK: - Create Pool Sheet

struct CreatePoolSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let connectionID: UUID
    let onCreated: () -> Void

    @State private var poolName = ""
    @State private var poolPath = "/var/lib/libvirt/images"
    @State private var isCreating = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 16) {
            Text("Create Storage Pool")
                .font(.headline)

            Form {
                TextField("Pool Name", text: $poolName)
                    .help("A unique name for the storage pool")
                TextField("Path", text: $poolPath)
                    .help("Directory on the hypervisor for this pool")
            }

            if let error = errorMessage {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.caption)
            }

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Create") {
                    createPool()
                }
                .buttonStyle(.borderedProminent)
                .disabled(poolName.isEmpty || poolPath.isEmpty || isCreating)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 400)
    }

    private func createPool() {
        isCreating = true
        errorMessage = nil
        let xml = """
        <pool type='dir'>
          <name>\(LibvirtSwift.XMLHelpers.escapeXML(poolName))</name>
          <target>
            <path>\(LibvirtSwift.XMLHelpers.escapeXML(poolPath))</path>
          </target>
        </pool>
        """
        Task {
            do {
                try await appState.createPool(xml: xml, connectionID: connectionID)
                onCreated()
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                isCreating = false
            }
        }
    }
}
