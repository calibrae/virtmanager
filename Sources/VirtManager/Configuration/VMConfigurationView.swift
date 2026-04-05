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

        // Sidebar + content layout (virt-manager style)
        NavigationSplitView {
            List(selection: $selectedTab) {
                Section("General") {
                    sidebarItem(tag: 0, icon: "info.circle", label: "Overview")
                    sidebarItem(tag: 1, icon: "cpu", label: "CPU")
                    sidebarItem(tag: 2, icon: "memorychip", label: "Memory")
                    sidebarItem(tag: 3, icon: "power", label: "Boot")
                }
                Section("Devices") {
                    sidebarItem(tag: 4, icon: "internaldrive", label: "Disks")
                    sidebarItem(tag: 5, icon: "network", label: "Network")
                    sidebarItem(tag: 6, icon: "display", label: "Graphics & Other")
                }
                Section("Passthrough") {
                    sidebarItem(tag: 7, icon: "cable.connector", label: "USB")
                    sidebarItem(tag: 8, icon: "square.grid.3x3.topleft.filled", label: "PCIe")
                }
                Section {
                    sidebarItem(tag: 9, icon: "chevron.left.forwardslash.chevron.right", label: "XML")
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 160, ideal: 180, max: 220)
        } detail: {
            switch selectedTab {
            case 0: OverviewTab(config: configBinding)
            case 1: CPUTab(config: configBinding)
            case 2: MemoryTab(config: configBinding)
            case 3: BootTab(config: configBinding)
            case 4: DisksTab(config: configBinding)
            case 5: NetworkTab(config: configBinding, connectionID: connectionID)
            case 6: GraphicsOtherTab(config: configBinding)
            case 7: USBPassthroughTab(config: configBinding)
            case 8: PCIePassthroughTab(config: configBinding)
            case 9: XMLEditorTab(xmlText: $xmlText)
            default: Text("Select a category")
            }
        }
        .onChange(of: selectedTab) { oldVal, newVal in
            if newVal == 9 {
                // Switching to XML tab: serialize current config
                syncConfigToXML()
            } else if oldVal == 9 {
                // Leaving XML tab: parse XML back to config
                syncXMLToConfig()
            }
        }
        .onChange(of: config?.name) { _, _ in markChanged() }
        .onChange(of: config?.vcpus) { _, _ in markChanged() }
        .onChange(of: config?.memoryKiB) { _, _ in markChanged() }
        .onChange(of: config?.cpuMode) { _, _ in markChanged() }
        .onChange(of: xmlText) { _, _ in
            if selectedTab == 9 { hasChanges = true }
        }
    }

    @ViewBuilder
    private func sidebarItem(tag: Int, icon: String, label: String) -> some View {
        Label(label, systemImage: icon)
            .tag(tag)
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
                if selectedTab == 9 {
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
