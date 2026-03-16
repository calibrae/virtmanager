import SwiftUI
import LibvirtSwift
import VirtManagerCore

/// Interactive network topology visualization showing VMs and networks as a graph.
public struct NetworkTopologyView: View {
    @Environment(AppState.self) private var appState

    public let connectionID: UUID

    @State private var graph = TopologyGraph()
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var selectedNodeID: String?
    @State private var scale: CGFloat = 1.0

    public init(connectionID: UUID) {
        self.connectionID = connectionID
    }

    public var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()

            if isLoading {
                Spacer()
                ProgressView("Building topology...")
                Spacer()
            } else if let error = errorMessage {
                Spacer()
                Text(error).foregroundStyle(.red)
                Spacer()
            } else if graph.nodes.isEmpty {
                Spacer()
                ContentUnavailableView(
                    "No Networks",
                    systemImage: "network",
                    description: Text("No networks or VMs found on this hypervisor.")
                )
                Spacer()
            } else {
                topologyCanvas
            }
        }
        .onAppear { loadTopology() }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack {
            Text("Network Topology")
                .font(.headline)
            Spacer()
            Button {
                loadTopology()
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
        }
        .padding()
    }

    // MARK: - Canvas

    private var topologyCanvas: some View {
        ScrollView([.horizontal, .vertical]) {
            Canvas { context, size in
                // Draw edges
                for edge in graph.edges {
                    guard let fromNode = graph.node(id: edge.vmID),
                          let toNode = graph.node(id: edge.networkID) else { continue }

                    let from = CGPoint(x: fromNode.x, y: fromNode.y)
                    let to = CGPoint(x: toNode.x, y: toNode.y)

                    var path = Path()
                    path.move(to: from)
                    path.addLine(to: to)
                    context.stroke(path, with: .color(.secondary.opacity(0.5)), lineWidth: 1.5)
                }

                // Draw nodes
                for node in graph.nodes {
                    let center = CGPoint(x: node.x, y: node.y)
                    let isSelected = selectedNodeID == node.id

                    switch node.node {
                    case .network(let info):
                        drawNetworkNode(context: context, center: center, info: info, selected: isSelected)
                    case .vm(let info):
                        drawVMNode(context: context, center: center, info: info, selected: isSelected)
                    }
                }
            }
            .frame(minWidth: 800, minHeight: 500)
            .scaleEffect(scale)
            .gesture(MagnifyGesture().onChanged { value in
                scale = max(0.3, min(3.0, value.magnification))
            })
            .onTapGesture { location in
                handleTap(at: location)
            }
        }
    }

    // MARK: - Node Drawing

    private func drawNetworkNode(context: GraphicsContext, center: CGPoint, info: NetworkInfo, selected: Bool) {
        let size = CGSize(width: 140, height: 60)
        let rect = CGRect(
            x: center.x - size.width / 2,
            y: center.y - size.height / 2,
            width: size.width,
            height: size.height
        )

        // Background
        let bgColor: Color = info.isActive ? .blue.opacity(0.15) : .gray.opacity(0.1)
        let borderColor: Color = selected ? .accentColor : (info.isActive ? .blue : .gray)
        context.fill(RoundedRectangle(cornerRadius: 8).path(in: rect), with: .color(bgColor))
        context.stroke(RoundedRectangle(cornerRadius: 8).path(in: rect), with: .color(borderColor), lineWidth: selected ? 3 : 1.5)

        // Network icon
        let iconRect = CGRect(x: rect.minX + 8, y: rect.minY + 8, width: 16, height: 16)
        context.draw(Image(systemName: "network"), in: iconRect)

        // Name text
        context.draw(
            Text(info.name).font(.caption).bold(),
            at: CGPoint(x: center.x + 4, y: center.y - 8),
            anchor: .leading
        )

        // Mode + subnet
        let subtitle = "\(info.forwardMode)\(info.ipv4Summary.map { " · \($0)" } ?? "")"
        context.draw(
            Text(subtitle).font(.caption2).foregroundStyle(.secondary),
            at: CGPoint(x: center.x, y: center.y + 14),
            anchor: .center
        )
    }

    private func drawVMNode(context: GraphicsContext, center: CGPoint, info: VMInfo, selected: Bool) {
        let radius: CGFloat = 28
        let rect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)

        // Background circle
        let stateColor: Color = info.state == .running ? .green.opacity(0.15) : .gray.opacity(0.1)
        let borderColor: Color = selected ? .accentColor : (info.state == .running ? .green : .gray)
        context.fill(Circle().path(in: rect), with: .color(stateColor))
        context.stroke(Circle().path(in: rect), with: .color(borderColor), lineWidth: selected ? 3 : 1.5)

        // VM icon
        let iconRect = CGRect(x: center.x - 8, y: center.y - 8, width: 16, height: 16)
        context.draw(Image(systemName: "desktopcomputer"), in: iconRect)

        // Name below
        context.draw(
            Text(info.name).font(.caption2),
            at: CGPoint(x: center.x, y: center.y + radius + 10),
            anchor: .center
        )
    }

    // MARK: - Interaction

    private func handleTap(at location: CGPoint) {
        let hitRadius: CGFloat = 35
        for node in graph.nodes {
            let dx = CGFloat(node.x) - location.x
            let dy = CGFloat(node.y) - location.y
            if sqrt(dx * dx + dy * dy) < hitRadius {
                selectedNodeID = node.id
                return
            }
        }
        selectedNodeID = nil
    }

    // MARK: - Data Loading

    private func loadTopology() {
        isLoading = true
        errorMessage = nil
        Task {
            do {
                let networks = try await appState.listNetworks(connectionID: connectionID)
                let vms = appState.vmsForConnection(connectionID)

                // Build VM → network mapping from domain XML NIC configs
                var vmConfigs: [String: [String]] = [:]
                for vm in vms {
                    if let xml = try? await appState.getDomainXML(vmName: vm.name, connectionID: connectionID),
                       let config = try? DomainConfig(xml: xml) {
                        let netNames = config.networkInterfaces
                            .filter { $0.type == "network" }
                            .compactMap { $0.sourceName }
                        vmConfigs[vm.id.uuidString] = netNames
                    }
                }

                graph.build(networks: networks, vms: vms, vmConfigs: vmConfigs)
                graph.applyForceLayout(iterations: 80)
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }
}
