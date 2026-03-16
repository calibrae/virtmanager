import SwiftUI

/// Wizard step 5: Installation source.
public struct WizardStep5Install: View {
    @Bindable var state: VMCreationState
    let connectionID: UUID

    @State private var sourceType: SourceType = .none
    @State private var showISOBrowser = false
    @State private var networkURLText: String = ""

    private enum SourceType: Int {
        case none = 0
        case localISO = 1
        case remoteISO = 2
        case networkURL = 3
    }

    public init(state: VMCreationState, connectionID: UUID) {
        self.state = state
        self.connectionID = connectionID
    }

    public var body: some View {
        Form {
            Section("Installation Source") {
                Picker("Source Type", selection: $sourceType) {
                    Text("None (boot from disk)").tag(SourceType.none)
                    Text("Local ISO (upload from Mac)").tag(SourceType.localISO)
                    Text("Remote ISO (on hypervisor)").tag(SourceType.remoteISO)
                    Text("Network URL").tag(SourceType.networkURL)
                }
                .onChange(of: sourceType) { _, newValue in
                    switch newValue {
                    case .none:
                        state.installSource = .none
                    case .networkURL:
                        state.installSource = .networkURL(networkURLText)
                    default:
                        break
                    }
                }

                switch sourceType {
                case .none:
                    Text("The VM will attempt to boot from the disk.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                case .localISO:
                    HStack {
                        Text("Selected: \(state.installSource.displayName)")
                            .lineLimit(1)
                        Spacer()
                        Button("Browse...") {
                            pickLocalISO()
                        }
                    }

                case .remoteISO:
                    HStack {
                        Text("Selected: \(state.installSource.displayName)")
                            .lineLimit(1)
                        Spacer()
                        Button("Browse...") {
                            showISOBrowser = true
                        }
                    }

                case .networkURL:
                    TextField("URL", text: $networkURLText)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: networkURLText) { _, newValue in
                            state.installSource = .networkURL(newValue)
                        }
                    Text("URL to a network install tree (e.g., http://mirror.example.com/fedora/releases/39/Everything/x86_64/os/)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $showISOBrowser) {
            ISOBrowserView(connectionID: connectionID) { selection in
                switch selection {
                case .remote(let path):
                    state.installSource = .remoteISO(path)
                }
            }
        }
        .onAppear { syncSourceType() }
    }

    private func syncSourceType() {
        switch state.installSource {
        case .none: sourceType = .none
        case .localISO: sourceType = .localISO
        case .remoteISO: sourceType = .remoteISO
        case .networkURL(let url):
            sourceType = .networkURL
            networkURLText = url
        }
    }

    private func pickLocalISO() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.init(filenameExtension: "iso")!]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Select an ISO image"
        if panel.runModal() == .OK, let url = panel.url {
            state.installSource = .localISO(url)
        }
    }
}
