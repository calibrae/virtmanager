import Foundation
import CoreGraphics
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
    public let vmID: String
    public let networkID: String
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

    /// Revision counter — incremented on every mutation to trigger Canvas redraws.
    public var revision: Int = 0

    public init() {}

    /// Build the topology from network and VM data.
    public func build(networks: [NetworkInfo], vms: [VMInfo], vmConfigs: [String: [String]]) {
        var positionedNodes: [PositionedNode] = []
        var allEdges: [TopologyEdge] = []

        // Initial layout: networks across the top, VMs below
        let networkSpacing = 200.0
        let vmSpacing = 150.0
        let networkY = 100.0
        let vmY = 320.0

        let totalNetworkWidth = Double(max(networks.count - 1, 0)) * networkSpacing
        let totalVMWidth = Double(max(vms.count - 1, 0)) * vmSpacing
        let centerX = max(totalNetworkWidth, totalVMWidth) / 2 + 100

        for (i, net) in networks.enumerated() {
            let x = Double(i) * networkSpacing - totalNetworkWidth / 2 + centerX
            positionedNodes.append(PositionedNode(node: .network(net), x: x, y: networkY))
        }

        for (i, vm) in vms.enumerated() {
            let x = Double(i) * vmSpacing - totalVMWidth / 2 + centerX
            positionedNodes.append(PositionedNode(node: .vm(vm), x: x, y: vmY))

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
        self.revision += 1
    }

    /// Find a node by ID.
    public func node(id: String) -> PositionedNode? {
        nodes.first { $0.id == id }
    }

    /// Apply force-directed layout, then normalize all positions to fit within a padded bounding box.
    public func applyForceLayout(iterations: Int = 50, fitSize: CGSize = CGSize(width: 800, height: 500)) {
        guard nodes.count > 1 else {
            // Single node: center it
            if nodes.count == 1 {
                nodes[0].x = fitSize.width / 2
                nodes[0].y = fitSize.height / 2
            }
            revision += 1
            return
        }

        let repulsion = 8000.0
        let attraction = 0.005
        let damping = 0.85

        var vx = [Double](repeating: 0, count: nodes.count)
        var vy = [Double](repeating: 0, count: nodes.count)

        // Build edge index for fast lookup
        let edgeIndices: [(Int, Int)] = edges.compactMap { edge in
            guard let ni = nodes.firstIndex(where: { $0.id == edge.vmID }),
                  let nj = nodes.firstIndex(where: { $0.id == edge.networkID }) else { return nil }
            return (ni, nj)
        }

        for _ in 0..<iterations {
            // Repulsion between all pairs
            for i in 0..<nodes.count {
                for j in (i + 1)..<nodes.count {
                    let dx = nodes[i].x - nodes[j].x
                    let dy = nodes[i].y - nodes[j].y
                    let dist = max(sqrt(dx * dx + dy * dy), 1.0)
                    let force = repulsion / (dist * dist)
                    let fx = (dx / dist) * force
                    let fy = (dy / dist) * force

                    vx[i] += fx; vy[i] += fy
                    vx[j] -= fx; vy[j] -= fy
                }
            }

            // Attraction along edges
            for (ni, nj) in edgeIndices {
                let dx = nodes[ni].x - nodes[nj].x
                let dy = nodes[ni].y - nodes[nj].y
                let fx = -attraction * dx
                let fy = -attraction * dy

                vx[ni] += fx; vy[ni] += fy
                vx[nj] -= fx; vy[nj] -= fy
            }

            // Apply velocities with damping
            for i in 0..<nodes.count {
                nodes[i].x += vx[i] * damping
                nodes[i].y += vy[i] * damping
                vx[i] *= damping
                vy[i] *= damping
            }
        }

        // Normalize: fit all nodes within the target size with padding
        normalizePositions(fitSize: fitSize, padding: 80)
        revision += 1
    }

    /// Shifts and scales all node positions to fit within the given size with padding.
    private func normalizePositions(fitSize: CGSize, padding: Double) {
        guard !nodes.isEmpty else { return }

        let minX = nodes.map(\.x).min()!
        let maxX = nodes.map(\.x).max()!
        let minY = nodes.map(\.y).min()!
        let maxY = nodes.map(\.y).max()!

        let graphWidth = maxX - minX
        let graphHeight = maxY - minY

        let availableWidth = Double(fitSize.width) - padding * 2
        let availableHeight = Double(fitSize.height) - padding * 2

        // Scale to fit, preserving aspect ratio
        let scaleX = graphWidth > 0 ? availableWidth / graphWidth : 1.0
        let scaleY = graphHeight > 0 ? availableHeight / graphHeight : 1.0
        let fitScale = min(scaleX, scaleY, 1.0) // don't upscale if already fits

        for i in 0..<nodes.count {
            nodes[i].x = (nodes[i].x - minX) * fitScale + padding
            nodes[i].y = (nodes[i].y - minY) * fitScale + padding
        }
    }
}
