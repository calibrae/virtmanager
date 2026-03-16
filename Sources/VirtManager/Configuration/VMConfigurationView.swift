import SwiftUI
import LibvirtSwift
import VirtManagerCore

public struct VMConfigurationView: View {
    public let vmName: String
    public let connectionID: UUID
    @State private var config: DomainConfig?
    @State private var originalXML: String = ""
    @State private var xmlText: String = ""
    @State private var validationIssues: [ValidationIssue] = []
    @State private var isLoading = true
    @State private var hasChanges = false
    @State private var errorMessage: String?
    @State private var selectedTab = 0
    @Environment(AppState.self) private var appState

    public init(vmName: String, connectionID: UUID) {
        self.vmName = vmName
        self.connectionID = connectionID
    }

    public var body: some View {
        VStack(spacing: 0) {
            if isLoading {
                Spacer()
                ProgressView("Loading configuration...")
                Spacer()
            } else if let error = errorMessage {
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

    @ViewBuilder
    private var configEditor: some View {
        // Toolbar
        HStack {
            Text("Configuration: \(vmName)")
                .font(.headline)
            Spacer()

            if !validationIssues.isEmpty {
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

            Button("Revert") { loadConfig() }
                .disabled(!hasChanges)

            Button("Apply") { applyConfig() }
                .disabled(validationIssues.contains { $0.severity == .error })
                .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)

        Divider()

        // Validation issues banner
        if !validationIssues.isEmpty {
            validationBanner
        }

        // Tab view
        TabView(selection: $selectedTab) {
            OverviewTab(config: configBinding)
                .tabItem { Label("Overview", systemImage: "info.circle") }
                .tag(0)
            CPUTab(config: configBinding)
                .tabItem { Label("CPU", systemImage: "cpu") }
                .tag(1)
            MemoryTab(config: configBinding)
                .tabItem { Label("Memory", systemImage: "memorychip") }
                .tag(2)
            BootTab(config: configBinding)
                .tabItem { Label("Boot", systemImage: "power") }
                .tag(3)
            DisksTab(config: configBinding)
                .tabItem { Label("Disks", systemImage: "internaldrive") }
                .tag(4)
            NetworkTab(config: configBinding, connectionID: connectionID)
                .tabItem { Label("Network", systemImage: "network") }
                .tag(5)
            GraphicsOtherTab(config: configBinding)
                .tabItem { Label("Graphics & Other", systemImage: "display") }
                .tag(6)
            XMLEditorTab(xmlText: $xmlText)
                .tabItem { Label("XML", systemImage: "chevron.left.forwardslash.chevron.right") }
                .tag(7)
        }
        .onChange(of: selectedTab) { oldVal, newVal in
            if newVal == 7 {
                // Switching to XML tab: serialize current config
                syncConfigToXML()
            } else if oldVal == 7 {
                // Leaving XML tab: parse XML back to config
                syncXMLToConfig()
            }
        }
        .onChange(of: config?.name) { _, _ in markChanged() }
        .onChange(of: config?.vcpus) { _, _ in markChanged() }
        .onChange(of: config?.memoryKiB) { _, _ in markChanged() }
        .onChange(of: config?.cpuMode) { _, _ in markChanged() }
        .onChange(of: xmlText) { _, _ in
            if selectedTab == 7 { hasChanges = true }
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

    // MARK: - Helpers

    private var configBinding: Binding<DomainConfig> {
        Binding(
            get: { config! },
            set: { newValue in
                config = newValue
                hasChanges = true
                validate()
            }
        )
    }

    private func markChanged() {
        hasChanges = true
        validate()
    }

    private func validate() {
        guard let config = config else { return }
        validationIssues = ConfigValidator.validate(config)
    }

    private func syncConfigToXML() {
        guard let config = config else { return }
        do {
            xmlText = try config.toXML()
        } catch {
            errorMessage = "Failed to serialize XML: \(error.localizedDescription)"
        }
    }

    private func syncXMLToConfig() {
        do {
            let newConfig = try DomainConfig(xml: xmlText)
            config = newConfig
            validate()
        } catch {
            // If XML is invalid, keep the old config and show error
            errorMessage = "Invalid XML: \(error.localizedDescription)"
        }
    }

    private func loadConfig() {
        isLoading = true
        errorMessage = nil
        Task {
            do {
                let xml = try await appState.getDomainXML(vmName: vmName, connectionID: connectionID, inactive: true)
                let parsed = try DomainConfig(xml: xml)
                config = parsed
                originalXML = xml
                xmlText = xml
                hasChanges = false
                validate()
                isLoading = false
            } catch {
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }

    private func applyConfig() {
        Task {
            do {
                let xmlToApply: String
                if selectedTab == 7 {
                    // On XML tab, use the raw XML text
                    xmlToApply = xmlText
                } else {
                    guard let config = config else { return }
                    xmlToApply = try config.toXML()
                }

                try await appState.applyConfiguration(vmName: vmName, xml: xmlToApply, connectionID: connectionID)
                originalXML = xmlToApply
                hasChanges = false
                // Reload to get canonical XML back from libvirt
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
