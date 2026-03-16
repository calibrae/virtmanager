import Foundation
import LibvirtSwift
import VirtManagerCore

/// A node in the network topology graph.
public enum TopologyNode: Identifiable {
    case network(NetworkInfo)
    case vm(VMInfo)

    public var id: String {
        switch self {
        case .network(let info): return "net-\(info.uuid)"
        case .vm(let info): return "vm-\(info.id)"
        }
    }

    public var name: String {
        switch self {
        case .network(let info): return info.name
        case .vm(let info): return info.name
        }
    }

    public var isNetwork: Bool {
        if case .network = self { return true }
        return false
    }
}

/// An edge connecting a VM to a network via a NIC.
public struct TopologyEdge: Identifiable {
    public let id = UUID()
    public let vmID: String           // VM node ID
    public let networkID: String      // Network node ID
    public let macAddress: String?
    public let nicModel: String?

    public init(vmID: String, networkID: String, macAddress: String? = nil, nicModel: String? = nil) {
        self.vmID = vmID
        self.networkID = networkID
        self.macAddress = macAddress
        self.nicModel = nicModel
    }
}

/// Positioned node for rendering.
public struct PositionedNode: Identifiable {
    public let node: TopologyNode
    public var x: Double
    public var y: Double

    public var id: String { node.id }

    public init(node: TopologyNode, x: Double, y: Double) {
        self.node = node
        self.x = x
        self.y = y
    }
}

/// The complete topology graph.
@Observable
public final class TopologyGraph {
    public var nodes: [PositionedNode] = []
    public var edges: [TopologyEdge] = []

    public init() {}

    /// Build the topology from network and VM data.
    public func build(networks: [NetworkInfo], vms: [VMInfo], vmConfigs: [String: [String]]) {
        // vmConfigs maps vm.id.uuidString → [network source names from NIC configs]
        var positionedNodes: [PositionedNode] = []
        var allEdges: [TopologyEdge] = []

        // Layout: networks across the top, VMs below
        let networkSpacing = 200.0
        let vmSpacing = 150.0
        let networkY = 80.0
        let vmY = 300.0

        // Position networks
        let networkStartX = max(0, (Double(networks.count) - 1) * networkSpacing / 2)
        for (i, net) in networks.enumerated() {
            let x = Double(i) * networkSpacing - networkStartX + 400
            positionedNodes.append(PositionedNode(
                node: .network(net),
                x: x,
                y: networkY
            ))
        }

        // Position VMs
        let vmStartX = max(0, (Double(vms.count) - 1) * vmSpacing / 2)
        for (i, vm) in vms.enumerated() {
            let x = Double(i) * vmSpacing - vmStartX + 400
            positionedNodes.append(PositionedNode(
                node: .vm(vm),
                x: x,
                y: vmY
            ))

            // Create edges from VM NIC configs
            if let nicNetworks = vmConfigs[vm.id.uuidString] {
                for netName in nicNetworks {
                    if let net = networks.first(where: { $0.name == netName }) {
                        allEdges.append(TopologyEdge(
                            vmID: "vm-\(vm.id)",
                            networkID: "net-\(net.uuid)"
                        ))
                    }
                }
            }
        }

        self.nodes = positionedNodes
        self.edges = allEdges
    }

    /// Find a node by ID.
    public func node(id: String) -> PositionedNode? {
        nodes.first { $0.id == id }
    }

    /// Apply simple force-directed layout iterations.
    public func applyForceLayout(iterations: Int = 50) {
        guard nodes.count > 1 else { return }

        let repulsion = 5000.0
        let attraction = 0.01
        let damping = 0.9

        var velocities = [String: (dx: Double, dy: Double)]()
        for node in nodes {
            velocities[node.id] = (0, 0)
        }

        for _ in 0..<iterations {
            // Repulsion between all nodes
            for i in 0..<nodes.count {
                for j in (i + 1)..<nodes.count {
                    let dx = nodes[i].x - nodes[j].x
                    let dy = nodes[i].y - nodes[j].y
                    let dist = max(sqrt(dx * dx + dy * dy), 1.0)
                    let force = repulsion / (dist * dist)
                    let fx = (dx / dist) * force
                    let fy = (dy / dist) * force

                    velocities[nodes[i].id]!.dx += fx
                    velocities[nodes[i].id]!.dy += fy
                    velocities[nodes[j].id]!.dx -= fx
                    velocities[nodes[j].id]!.dy -= fy
                }
            }

            // Attraction along edges
            for edge in edges {
                guard let ni = nodes.firstIndex(where: { $0.id == edge.vmID }),
                      let nj = nodes.firstIndex(where: { $0.id == edge.networkID }) else { continue }
                let dx = nodes[ni].x - nodes[nj].x
                let dy = nodes[ni].y - nodes[nj].y
                let fx = -attraction * dx
                let fy = -attraction * dy

                velocities[nodes[ni].id]!.dx += fx
                velocities[nodes[ni].id]!.dy += fy
                velocities[nodes[nj].id]!.dx -= fx
                velocities[nodes[nj].id]!.dy -= fy
            }

            // Apply velocities
            for i in 0..<nodes.count {
                let id = nodes[i].id
                nodes[i].x += velocities[id]!.dx * damping
                nodes[i].y += velocities[id]!.dy * damping
                velocities[id] = (velocities[id]!.dx * damping, velocities[id]!.dy * damping)
            }
        }
    }
}
