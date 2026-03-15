import CLibvirt
import Foundation
import VirtManagerCore

/// Parsed domain information from libvirt.
public struct VMDomainInfo: Sendable {
    public let name: String
    public let uuid: String
    public let state: VMInfo.VMState
    public let vcpus: Int
    public let memoryKB: Int
    public let graphicsType: String?
    public let hasSerial: Bool

    public var memoryMB: Int { memoryKB / 1024 }

    /// Converts this raw domain info into a VMInfo model.
    public func toVMInfo() -> VMInfo {
        let gfx: VMInfo.GraphicsType? = graphicsType.flatMap { VMInfo.GraphicsType(rawValue: $0) }
        return VMInfo(
            name: name,
            uuid: uuid,
            state: state,
            vcpus: vcpus,
            memoryMB: memoryMB,
            graphicsType: gfx,
            hasSerial: hasSerial
        )
    }

    /// Maps libvirt domain state constants to VMState.
    public static func stateFromLibvirt(_ state: Int32) -> VMInfo.VMState {
        switch state {
        case Int32(VIR_DOMAIN_RUNNING.rawValue): return .running
        case Int32(VIR_DOMAIN_PAUSED.rawValue): return .paused
        case Int32(VIR_DOMAIN_SHUTOFF.rawValue): return .shutOff
        case Int32(VIR_DOMAIN_CRASHED.rawValue): return .crashed
        case Int32(VIR_DOMAIN_PMSUSPENDED.rawValue): return .suspended
        default: return .unknown
        }
    }
}
