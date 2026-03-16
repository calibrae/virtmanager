import SwiftUI
import VirtManagerCore

/// A sheet for browsing and uploading ISO images.
/// "Local" tab: pick a .iso from the Mac via NSOpenPanel.
/// "Remote" tab: list ISOs already on the hypervisor storage pools.
public struct ISOBrowserView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    public let connectionID: UUID
    public let onSelect: (ISOSelection) -> Void

    @State private var selectedTab = 0
    @State private var localFileURL: URL?
    @State private var uploadProgress: Double = 0
    @State private var isUploading = false
    @State private var uploadError: String?

    // Remote tab state
    @State private var remotePools: [StoragePoolEntry] = []
    @State private var isLoadingRemote = false
    @State private var selectedRemotePath: String?

    public init(connectionID: UUID, onSelect: @escaping (ISOSelection) -> Void) {
        self.connectionID = connectionID
        self.onSelect = onSelect
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Title
            HStack {
                Text("Select ISO Image")
                    .font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding()

            Divider()

            Picker("Source", selection: $selectedTab) {
                Text("Local").tag(0)
                Text("Remote Pool").tag(1)
                Text("Remote Filesystem").tag(2)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.top, 8)

            if selectedTab == 0 {
                localTabContent
            } else if selectedTab == 1 {
                remoteTabContent
            } else {
                RemoteFileBrowser(connectionID: connectionID) { remotePath in
                    onSelect(.remote(remotePath))
                    dismiss()
                }
            }
        }
        .frame(width: 500, height: 400)
    }

    // MARK: - Local Tab

    @ViewBuilder
    private var localTabContent: some View {
        VStack(spacing: 16) {
            Spacer()

            if let url = localFileURL {
                VStack(spacing: 8) {
                    Image(systemName: "opticaldisc.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)
                    Text(url.lastPathComponent)
                        .font(.headline)
                    Text(url.path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "doc.badge.plus")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)
                    Text("No ISO selected")
                        .foregroundStyle(.secondary)
                }
            }

            if isUploading {
                VStack(spacing: 4) {
                    ProgressView(value: uploadProgress)
                    Text("\(Int(uploadProgress * 100))% uploaded")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 40)
            }

            if let error = uploadError {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.caption)
            }

            Spacer()

            HStack {
                Button("Browse...") {
                    pickLocalISO()
                }

                Spacer()

                Button("Upload & Select") {
                    uploadAndSelect()
                }
                .buttonStyle(.borderedProminent)
                .disabled(localFileURL == nil || isUploading)
            }
            .padding()
        }
    }

    // MARK: - Remote Tab

    @ViewBuilder
    private var remoteTabContent: some View {
        VStack(spacing: 0) {
            if isLoadingRemote {
                Spacer()
                ProgressView("Loading storage pools...")
                Spacer()
            } else if remotePools.isEmpty {
                Spacer()
                Text("No ISO volumes found on remote pools.")
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                List(selection: $selectedRemotePath) {
                    ForEach(remotePools) { pool in
                        Section(pool.name) {
                            ForEach(pool.isoVolumes) { vol in
                                HStack {
                                    Image(systemName: "opticaldisc")
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
                        }
                    }
                }
                .listStyle(.inset)
            }

            HStack {
                Button("Refresh") { loadRemotePools() }
                Spacer()
                Button("Select") {
                    if let path = selectedRemotePath {
                        onSelect(.remote(path))
                        dismiss()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedRemotePath == nil)
            }
            .padding()
        }
        .onAppear { loadRemotePools() }
    }

    // MARK: - Helpers

    private func pickLocalISO() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.init(filenameExtension: "iso")!]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Select an ISO image to upload"
        if panel.runModal() == .OK {
            localFileURL = panel.url
        }
    }

    private func uploadAndSelect() {
        guard let url = localFileURL else { return }
        isUploading = true
        uploadError = nil
        uploadProgress = 0

        Task {
            do {
                let remotePath = try await appState.uploadISO(
                    fileURL: url,
                    connectionID: connectionID,
                    onProgress: { progress in
                        Task { @MainActor in
                            uploadProgress = progress
                        }
                    }
                )
                isUploading = false
                onSelect(.remote(remotePath))
                dismiss()
            } catch {
                isUploading = false
                uploadError = error.localizedDescription
            }
        }
    }

    private func loadRemotePools() {
        isLoadingRemote = true
        Task {
            do {
                let entries = try await appState.listISOVolumes(connectionID: connectionID)
                remotePools = entries
            } catch {
                remotePools = []
            }
            isLoadingRemote = false
        }
    }

    private func formatBytes(_ bytes: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
}

// MARK: - Supporting Types

/// Represents a user's ISO selection.
public enum ISOSelection {
    case remote(String) // path on the hypervisor
}

/// A storage pool entry with its ISO volumes for display.
public struct StoragePoolEntry: Identifiable, Sendable {
    public let id: String
    public let name: String
    public let isoVolumes: [ISOVolumeEntry]
}

/// An ISO volume entry for display.
public struct ISOVolumeEntry: Identifiable, Sendable {
    public let id: String
    public let name: String
    public let path: String
    public let capacity: UInt64
}
