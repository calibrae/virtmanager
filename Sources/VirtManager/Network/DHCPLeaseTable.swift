import SwiftUI
import LibvirtSwift

/// Table view showing active DHCP leases for a network.
/// Used as a sub-component in the DHCP tab of the network configuration editor.
public struct DHCPLeaseTable: View {
    @Environment(AppState.self) private var appState

    public let networkName: String
    public let connectionID: UUID

    @State private var leases: [DHCPLease] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    public init(networkName: String, connectionID: UUID) {
        self.networkName = networkName
        self.connectionID = connectionID
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Active DHCP Leases")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                }
                Button {
                    loadLeases()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Refresh Leases")
            }

            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            } else if leases.isEmpty && !isLoading {
                Text("No active leases")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            } else {
                Table(leases) {
                    TableColumn("MAC") { lease in
                        Text(lease.mac ?? "—")
                            .font(.system(.caption, design: .monospaced))
                    }
                    .width(min: 120, ideal: 140)

                    TableColumn("IP Address") { lease in
                        Text(lease.ipAddress)
                            .font(.system(.caption, design: .monospaced))
                    }
                    .width(min: 100, ideal: 130)

                    TableColumn("Hostname") { lease in
                        Text(lease.hostname ?? "—")
                            .font(.caption)
                    }
                    .width(min: 80, ideal: 120)

                    TableColumn("Expiry") { lease in
                        Text(lease.expiryString)
                            .font(.caption)
                    }
                    .width(min: 100, ideal: 140)

                    TableColumn("Type") { lease in
                        Text(lease.isIPv6 ? "IPv6" : "IPv4")
                            .font(.caption)
                    }
                    .width(40)
                }
                .frame(minHeight: 100, maxHeight: 250)
            }
        }
        .onAppear { loadLeases() }
    }

    private func loadLeases() {
        isLoading = true
        errorMessage = nil
        Task {
            do {
                leases = try await appState.getNetworkDHCPLeases(
                    name: networkName,
                    connectionID: connectionID
                )
            } catch {
                errorMessage = "Failed to load leases: \(error.localizedDescription)"
            }
            isLoading = false
        }
    }
}
