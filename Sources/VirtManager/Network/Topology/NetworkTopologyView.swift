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
    @State private var offset: CGSize = .zero
    @State private var dragOffset: CGSize = .zero

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

            // Zoom controls
            Button {
                withAnimation { scale = max(0.3, scale - 0.2) }
            } label: {
                Image(systemName: "minus.magnifyingglass")
            }
            .buttonStyle(.borderless)

            Text("\(Int(scale * 100))%")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 40)

            Button {
                withAnimation { scale = min(3.0, scale + 0.2) }
            } label: {
                Image(systemName: "plus.magnifyingglass")
            }
            .buttonStyle(.borderless)

            Button {
                withAnimation { scale = 1.0; offset = .zero }
            } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
            }
            .buttonStyle(.borderless)
            .help("Reset Zoom")

            Divider().frame(height: 16)

            Button {
                loadTopology()
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    // MARK: - Canvas

    private var topologyCanvas: some View {
        GeometryReader { geometry in
            // Use revision + scale as Canvas dependencies so it redraws
            let _ = graph.revision
            let _ = scale
            let _ = selectedNodeID

            Canvas { context, size in
                // Apply transform
                let totalOffset = CGSize(
                    width: offset.width + dragOffset.width,
                    height: offset.height + dragOffset.height
                )
                context.translateBy(x: totalOffset.width, y: totalOffset.height)
                context.scaleBy(x: scale, y: scale)

                // Draw edges
                for edge in graph.edges {
                    guard let fromNode = graph.node(id: edge.vmID),
                          let toNode = graph.node(id: edge.networkID) else { continue }

                    var path = Path()
                    path.move(to: CGPoint(x: fromNode.x, y: fromNode.y))
                    path.addLine(to: CGPoint(x: toNode.x, y: toNode.y))
                    context.stroke(path, with: .color(.secondary.opacity(0.4)), lineWidth: 1.5)
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
            .frame(width: geometry.size.width, height: geometry.size.height)
            .background(Color(nsColor: .controlBackgroundColor))
            .gesture(
                DragGesture()
                    .onChanged { value in
                        dragOffset = value.translation
                    }
                    .onEnded { value in
                        offset = CGSize(
                            width: offset.width + value.translation.width,
                            height: offset.height + value.translation.height
                        )
                        dragOffset = .zero
                    }
            )
            .gesture(
                MagnifyGesture()
                    .onChanged { value in
                        scale = max(0.3, min(3.0, value.magnification))
                    }
            )
            .onTapGesture { location in
                handleTap(at: location)
            }
            .onAppear {
                // Re-layout when the geometry is known
                if !graph.nodes.isEmpty {
                    graph.applyForceLayout(
                        iterations: 80,
                        fitSize: CGSize(width: geometry.size.width, height: geometry.size.height)
                    )
                }
            }
        }
    }

    // MARK: - Node Drawing

    private func drawNetworkNode(context: GraphicsContext, center: CGPoint, info: NetworkInfo, selected: Bool) {
        let size = CGSize(width: 160, height: 56)
        let rect = CGRect(
            x: center.x - size.width / 2,
            y: center.y - size.height / 2,
            width: size.width,
            height: size.height
        )

        let bgColor: Color = info.isActive ? .blue.opacity(0.12) : .gray.opacity(0.08)
        let borderColor: Color = selected ? .accentColor : (info.isActive ? .blue.opacity(0.6) : .gray.opacity(0.4))
        context.fill(RoundedRectangle(cornerRadius: 10).path(in: rect), with: .color(bgColor))
        context.stroke(RoundedRectangle(cornerRadius: 10).path(in: rect), with: .color(borderColor), lineWidth: selected ? 2.5 : 1.5)

        // Name
        context.draw(
            Text(info.name).font(.system(size: 11, weight: .semibold)),
            at: CGPoint(x: center.x, y: center.y - 10),
            anchor: .center
        )

        // Mode + subnet
        let subtitle = "\(info.forwardMode)\(info.ipv4Summary.map { " · \($0)" } ?? "")"
        context.draw(
            Text(subtitle).font(.system(size: 9)).foregroundStyle(.secondary),
            at: CGPoint(x: center.x, y: center.y + 10),
            anchor: .center
        )
    }

    private func drawVMNode(context: GraphicsContext, center: CGPoint, info: VMInfo, selected: Bool) {
        let radius: CGFloat = 26
        let rect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)

        let stateColor: Color = info.state == .running ? .green.opacity(0.12) : .gray.opacity(0.08)
        let borderColor: Color = selected ? .accentColor : (info.state == .running ? .green.opacity(0.6) : .gray.opacity(0.4))
        context.fill(Circle().path(in: rect), with: .color(stateColor))
        context.stroke(Circle().path(in: rect), with: .color(borderColor), lineWidth: selected ? 2.5 : 1.5)

        // Icon
        context.draw(
            Image(systemName: "desktopcomputer"),
            in: CGRect(x: center.x - 8, y: center.y - 8, width: 16, height: 16)
        )

        // Name below
        context.draw(
            Text(info.name).font(.system(size: 9)),
            at: CGPoint(x: center.x, y: center.y + radius + 10),
            anchor: .center
        )
    }

    // MARK: - Interaction

    private func handleTap(at location: CGPoint) {
        // Convert screen location to graph coordinates
        let totalOffset = CGSize(
            width: offset.width + dragOffset.width,
            height: offset.height + dragOffset.height
        )
        let graphX = (location.x - totalOffset.width) / scale
        let graphY = (location.y - totalOffset.height) / scale

        let hitRadius: CGFloat = 40
        for node in graph.nodes {
            let dx = CGFloat(node.x) - graphX
            let dy = CGFloat(node.y) - graphY
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
