import SwiftUI
import VirtManagerCore

public struct ConnectionSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    public var existingConnection: SavedConnection?

    public init(existingConnection: SavedConnection? = nil) {
        self.existingConnection = existingConnection
    }

    @State private var displayName = ""
    @State private var uri = "qemu+ssh://cali@jolyne/system"
    @State private var authType: SavedConnection.AuthType = .sshAgent

    private var isEditing: Bool { existingConnection != nil }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(isEditing ? "Edit Connection" : "New Connection")
                .font(.headline)

            LabeledContent("Display Name") {
                TextField("e.g. Production Server", text: $displayName)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("displayNameField")
            }

            LabeledContent("URI") {
                TextField("qemu+ssh://user@host/system", text: $uri)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .accessibilityIdentifier("uriField")
            }

            LabeledContent("Authentication") {
                Picker("", selection: $authType) {
                    ForEach(SavedConnection.AuthType.allCases, id: \.self) { type in
                        Text(type.displayLabel).tag(type)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
            }

            HStack {
                Button("Cancel", role: .cancel) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button(isEditing ? "Save" : "Add & Connect") {
                    saveConnection()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(displayName.isEmpty || uri.isEmpty)
                .accessibilityIdentifier("addConnectButton")
            }
            .padding(.top, 8)
        }
        .padding(20)
        .frame(width: 480)
        .onAppear {
            if let existing = existingConnection {
                displayName = existing.displayName
                uri = existing.uri
                authType = existing.authType
            }
        }
    }

    private func saveConnection() {
        if var existing = existingConnection {
            existing.displayName = displayName
            existing.uri = uri
            existing.authType = authType
            appState.updateConnection(existing)
        } else {
            let connection = SavedConnection(
                displayName: displayName,
                uri: uri,
                authType: authType
            )
            appState.addConnection(connection)
            appState.connect(to: connection)
        }
    }
}

extension SavedConnection.AuthType {
    var displayLabel: String {
        switch self {
        case .sshKey: "SSH Key"
        case .password: "Password"
        case .sshAgent: "SSH Agent"
        }
    }
}
