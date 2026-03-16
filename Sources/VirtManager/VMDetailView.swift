import SwiftUI
import VirtManagerCore

public struct VMDetailView: View {
    @Environment(AppState.self) private var appState
    public let vm: VMInfo

    public init(vm: VMInfo) {
        self.vm = vm
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            headerSection

            Divider()

            // Info grid
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    infoSection
                    actionsSection
                    configurationSection
                    consoleSection
                }
                .padding()
            }
        }
        .navigationTitle(vm.name)
    }

    private var headerSection: some View {
        HStack {
            VMStateBadge(state: vm.state)
                .font(.title2)
            VStack(alignment: .leading) {
                Text(vm.name)
                    .font(.title2)
                    .fontWeight(.semibold)
                Text(vm.state.displayName)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding()
    }

    private var infoSection: some View {
        GroupBox("Information") {
            Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 8) {
                GridRow {
                    Text("UUID").fontWeight(.medium)
                    Text(vm.uuid).textSelection(.enabled)
                }
                GridRow {
                    Text("vCPUs").fontWeight(.medium)
                    Text("\(vm.vcpus)")
                }
                GridRow {
                    Text("Memory").fontWeight(.medium)
                    Text("\(vm.memoryMB) MB")
                }
                GridRow {
                    Text("Graphics").fontWeight(.medium)
                    Text(vm.graphicsType?.rawValue.uppercased() ?? "None")
                }
                GridRow {
                    Text("Serial Console").fontWeight(.medium)
                    Text(vm.hasSerial ? "Available" : "Not configured")
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var actionsSection: some View {
        GroupBox("Actions") {
            HStack(spacing: 12) {
                if vm.state.canStart {
                    actionButton("Start", systemImage: "play.fill", color: .green) {
                        if let connID = appState.connectionID(for: vm.id) {
                            appState.startVM(vm, connectionID: connID)
                        }
                    }
                }
                if vm.state.canShutdown {
                    actionButton("Shutdown", systemImage: "power", color: .orange) {
                        if let connID = appState.connectionID(for: vm.id) {
                            appState.shutdownVM(vm, connectionID: connID)
                        }
                    }
                }
                if vm.state.canPause {
                    actionButton("Pause", systemImage: "pause.fill", color: .yellow) {
                        if let connID = appState.connectionID(for: vm.id) {
                            appState.pauseVM(vm, connectionID: connID)
                        }
                    }
                }
                if vm.state.canResume {
                    actionButton("Resume", systemImage: "play.fill", color: .green) {
                        if let connID = appState.connectionID(for: vm.id) {
                            appState.resumeVM(vm, connectionID: connID)
                        }
                    }
                }
                if vm.state.canReboot {
                    actionButton("Reboot", systemImage: "arrow.clockwise", color: .blue) {
                        if let connID = appState.connectionID(for: vm.id) {
                            appState.rebootVM(vm, connectionID: connID)
                        }
                    }
                }
                if vm.state.canForceOff {
                    actionButton("Force Off", systemImage: "bolt.fill", color: .red) {
                        if let connID = appState.connectionID(for: vm.id) {
                            appState.forceOffVM(vm, connectionID: connID)
                        }
                    }
                }

                Spacer()
            }
            .padding(.vertical, 4)
        }
    }

    private var configurationSection: some View {
        GroupBox("Configuration") {
            HStack(spacing: 12) {
                actionButton("Configuration", systemImage: "gearshape", color: .accentColor) {
                    if let connID = appState.connectionID(for: vm.id) {
                        appState.openConfiguration(for: vm, connectionID: connID)
                    }
                }
                Text("Edit VM hardware and settings")
                    .foregroundStyle(.secondary)
                    .font(.callout)
                Spacer()
            }
            .padding(.vertical, 4)
        }
    }

    private var consoleSection: some View {
        GroupBox("Console") {
            HStack(spacing: 12) {
                if vm.state.canOpenConsole && vm.graphicsType != nil {
                    actionButton("Open Console", systemImage: "rectangle.on.rectangle", color: .accentColor) {
                        if let connID = appState.connectionID(for: vm.id) {
                            appState.openConsole(for: vm, connectionID: connID)
                        }
                    }
                }
                if vm.state.canOpenConsole && vm.hasSerial {
                    actionButton("Open Serial Console", systemImage: "terminal", color: .accentColor) {
                        if let connID = appState.connectionID(for: vm.id) {
                            appState.openSerialConsole(for: vm, connectionID: connID)
                        }
                    }
                }
                if !vm.state.canOpenConsole {
                    Text("Console available when VM is running")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                }
                Spacer()
            }
            .padding(.vertical, 4)
        }
    }

    private func actionButton(_ title: String, systemImage: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
        }
        .tint(color)
        .buttonStyle(.bordered)
    }
}
