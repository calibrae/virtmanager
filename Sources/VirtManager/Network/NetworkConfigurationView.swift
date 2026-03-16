import SwiftUI
import LibvirtSwift
import VirtManagerCore

/// Tabbed network configuration editor, mirroring VMConfigurationView.
public struct NetworkConfigurationView: View {
    public let networkName: String
    public let connectionID: UUID

    @State private var config: NetworkConfig?
    @State private var originalXML: String = ""
    @State private var xmlText: String = ""
    @State private var validationIssues: [ValidationIssue] = []
    @State private var isLoading = true
    @State private var hasChanges = false
    @State private var errorMessage: String?
    @State private var selectedTab = 0

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    public init(networkName: String, connectionID: UUID) {
        self.networkName = networkName
        self.connectionID = connectionID
    }

    public var body: some View {
        VStack(spacing: 0) {
            if isLoading {
                Spacer()
                ProgressView("Loading configuration...")
                Spacer()
            } else if let error = errorMessage, config == nil {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundStyle(.red)
                    Text(error)
                        .foregroundStyle(.secondary)
                    Button("Retry") { loadConfig() }
                }
                Spacer()
            } else if config != nil {
                configEditor
            }
        }
        .frame(minWidth: 700, minHeight: 500)
        .onAppear { loadConfig() }
    }

    // MARK: - Config Editor

    @ViewBuilder
    private var configEditor: some View {
        // Toolbar
        HStack {
            Text("Network: \(networkName)")
                .font(.headline)
            Spacer()

            validationSummary

            Button("Revert") { loadConfig() }
                .disabled(!hasChanges)

            Button("Apply") { applyConfig() }
                .disabled(validationIssues.contains { $0.severity == .error })
                .buttonStyle(.borderedProminent)

            Button("Done") { dismiss() }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)

        Divider()

        if !validationIssues.isEmpty {
            validationBanner
        }

        if let error = errorMessage {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                Text(error)
                    .font(.callout)
                Spacer()
                Button("Dismiss") { errorMessage = nil }
                    .buttonStyle(.borderless)
            }
            .padding(.horizontal)
            .padding(.vertical, 4)
            .background(.red.opacity(0.08))
        }

        // Tab view
        tabView
    }

    @ViewBuilder
    private var validationSummary: some View {
        let errorCount = validationIssues.filter { $0.severity == .error }.count
        let warningCount = validationIssues.filter { $0.severity == .warning }.count
        if errorCount > 0 {
            Label("\(errorCount) error(s)", systemImage: "xmark.circle.fill")
                .foregroundStyle(.red)
                .font(.callout)
        }
        if warningCount > 0 {
            Label("\(warningCount) warning(s)", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
                .font(.callout)
        }
    }

    private var validationBanner: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(validationIssues.enumerated()), id: \.offset) { _, issue in
                    HStack(spacing: 4) {
                        Image(systemName: issueIcon(issue.severity))
                            .foregroundStyle(issueColor(issue.severity))
                        Text(issue.message)
                            .font(.caption)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(issueColor(issue.severity).opacity(0.1), in: RoundedRectangle(cornerRadius: 4))
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private var tabView: some View {
        let mode = config?.forward.mode ?? .isolated

        TabView(selection: $selectedTab) {
            NetworkOverviewTab(config: configBinding)
                .tabItem { Label("Overview", systemImage: "info.circle") }
                .tag(0)

            if mode.supportsIPConfig {
                IPv4Tab(config: configBinding)
                    .tabItem { Label("IPv4", systemImage: "4.circle") }
                    .tag(1)

                IPv6Tab(config: configBinding)
                    .tabItem { Label("IPv6", systemImage: "6.circle") }
                    .tag(2)

                DNSTab(config: configBinding)
                    .tabItem { Label("DNS", systemImage: "globe") }
                    .tag(3)

                DHCPTab(config: configBinding, networkName: networkName, connectionID: connectionID)
                    .tabItem { Label("DHCP", systemImage: "arrow.left.arrow.right") }
                    .tag(4)
            }

            if mode.supportsPortForwarding {
                PortForwardingTab(config: configBinding)
                    .tabItem { Label("Port Forwarding", systemImage: "arrow.right.arrow.left.square") }
                    .tag(5)
            }

            QoSTab(config: configBinding)
                .tabItem { Label("QoS", systemImage: "speedometer") }
                .tag(6)

            NetworkXMLEditorTab(xmlText: $xmlText)
                .tabItem { Label("XML", systemImage: "chevron.left.forwardslash.chevron.right") }
                .tag(7)
        }
        .onChange(of: selectedTab) { oldVal, newVal in
            if newVal == 7 {
                syncConfigToXML()
            } else if oldVal == 7 {
                syncXMLToConfig()
            }
        }
        .onChange(of: xmlText) { _, _ in
            if selectedTab == 7 { hasChanges = true }
        }
    }

    // MARK: - Bindings & Helpers

    private var configBinding: Binding<NetworkConfig> {
        Binding(
            get: { config! },
            set: { newValue in
                config = newValue
                hasChanges = true
                validate()
            }
        )
    }

    private func validate() {
        guard let config = config else { return }
        validationIssues = ConfigValidator.validate(config)
    }

    private func syncConfigToXML() {
        guard let config = config else { return }
        xmlText = config.toXMLString()
    }

    private func syncXMLToConfig() {
        do {
            let newConfig = try NetworkConfig(xmlString: xmlText)
            config = newConfig
            validate()
        } catch {
            errorMessage = "Invalid XML: \(error.localizedDescription)"
        }
    }

    // MARK: - Load / Apply

    private func loadConfig() {
        isLoading = true
        errorMessage = nil
        Task {
            do {
                let xml = try await appState.getNetworkXML(name: networkName, connectionID: connectionID)
                let parsed = try NetworkConfig(xmlString: xml)
                config = parsed
                originalXML = xml
                xmlText = xml
                hasChanges = false
                validate()
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }

    private func applyConfig() {
        Task {
            do {
                let xmlToApply: String
                if selectedTab == 7 {
                    xmlToApply = xmlText
                } else {
                    guard let config = config else { return }
                    xmlToApply = config.toXMLString()
                }
                try await appState.defineNetwork(xml: xmlToApply, connectionID: connectionID)
                originalXML = xmlToApply
                hasChanges = false
                loadConfig()
            } catch {
                errorMessage = "Apply failed: \(error.localizedDescription)"
            }
        }
    }

    private func issueIcon(_ severity: ValidationIssue.Severity) -> String {
        switch severity {
        case .error: return "xmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .info: return "info.circle.fill"
        }
    }

    private func issueColor(_ severity: ValidationIssue.Severity) -> Color {
        switch severity {
        case .error: return .red
        case .warning: return .yellow
        case .info: return .blue
        }
    }
}
