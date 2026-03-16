import SwiftUI
import VirtManagerCore

/// A SwiftUI view that browses the remote hypervisor's filesystem via SSH.
/// Shows directories and .iso files, allowing the user to navigate and select an ISO.
public struct RemoteFileBrowser: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    public let connectionID: UUID
    public let onSelect: (String) -> Void

    @State private var currentPath: String = "/var/lib/libvirt/images"
    @State private var entries: [(name: String, isDirectory: Bool)] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var selectedFile: String?

    public init(connectionID: UUID, onSelect: @escaping (String) -> Void) {
        self.connectionID = connectionID
        self.onSelect = onSelect
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Path bar
            HStack {
                Button {
                    navigateUp()
                } label: {
                    Image(systemName: "chevron.left")
                }
                .disabled(currentPath == "/")

                Text(currentPath)
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.head)

                Spacer()

                Button {
                    currentPath = "/"
                    loadDirectory()
                } label: {
                    Image(systemName: "house")
                }
                .help("Go to /")

                Button {
                    currentPath = "/var/lib/libvirt/images"
                    loadDirectory()
                } label: {
                    Image(systemName: "externaldrive")
                }
                .help("Go to /var/lib/libvirt/images")
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()

            if isLoading {
                Spacer()
                ProgressView("Loading...")
                Spacer()
            } else if let error = errorMessage {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.title)
                        .foregroundStyle(.secondary)
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.caption)
                        .multilineTextAlignment(.center)
                }
                .padding()
                Spacer()
            } else if entries.isEmpty {
                Spacer()
                Text("No directories or ISO files found.")
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                List(selection: $selectedFile) {
                    ForEach(entries, id: \.name) { entry in
                        HStack {
                            Image(systemName: entry.isDirectory ? "folder.fill" : "opticaldisc")
                                .foregroundStyle(entry.isDirectory ? .blue : .secondary)
                            Text(entry.name)
                            Spacer()
                        }
                        .tag(entry.isDirectory ? nil as String? : fullPath(for: entry.name))
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) {
                            if entry.isDirectory {
                                navigateInto(entry.name)
                            } else {
                                let path = fullPath(for: entry.name)
                                onSelect(path)
                                dismiss()
                            }
                        }
                        .onTapGesture(count: 1) {
                            if !entry.isDirectory {
                                selectedFile = fullPath(for: entry.name)
                            }
                        }
                    }
                }
                .listStyle(.inset)
            }

            HStack {
                Button("Refresh") { loadDirectory() }
                Spacer()
                Button("Select") {
                    if let path = selectedFile {
                        onSelect(path)
                        dismiss()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedFile == nil)
            }
            .padding()
        }
        .onAppear { loadDirectory() }
    }

    // MARK: - Navigation

    private func navigateUp() {
        let parent = (currentPath as NSString).deletingLastPathComponent
        currentPath = parent.isEmpty ? "/" : parent
        selectedFile = nil
        loadDirectory()
    }

    private func navigateInto(_ dirName: String) {
        currentPath = fullPath(for: dirName)
        selectedFile = nil
        loadDirectory()
    }

    private func fullPath(for name: String) -> String {
        if currentPath == "/" {
            return "/\(name)"
        }
        return "\(currentPath)/\(name)"
    }

    private func loadDirectory() {
        isLoading = true
        errorMessage = nil
        entries = []
        Task {
            do {
                let result = try await appState.listRemoteDirectory(
                    path: currentPath,
                    connectionID: connectionID
                )
                entries = result
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }
}
