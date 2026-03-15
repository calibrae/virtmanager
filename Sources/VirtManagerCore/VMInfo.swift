import Foundation

public struct VMInfo: Identifiable, Sendable {
    public let id: UUID
    public let name: String
    public let uuid: String
    public var state: VMState
    public let vcpus: Int
    public let memoryMB: Int
    public let graphicsType: GraphicsType?
    public let hasSerial: Bool

    public enum VMState: String, Sendable, CaseIterable {
        case running, paused, shutOff, crashed, suspended, unknown

        public var displayName: String {
            switch self {
            case .running: "Running"
            case .paused: "Paused"
            case .shutOff: "Shut Off"
            case .crashed: "Crashed"
            case .suspended: "Suspended"
            case .unknown: "Unknown"
            }
        }

        public var sfSymbol: String {
            switch self {
            case .running: "circle.fill"
            case .paused: "pause.circle.fill"
            case .shutOff: "circle.fill"
            case .crashed: "exclamationmark.circle.fill"
            case .suspended: "moon.circle.fill"
            case .unknown: "questionmark.circle.fill"
            }
        }

        public var isRunning: Bool { self == .running }
        public var canStart: Bool { self == .shutOff || self == .crashed }
        public var canShutdown: Bool { self == .running }
        public var canForceOff: Bool { self == .running || self == .paused || self == .crashed || self == .suspended }
        public var canPause: Bool { self == .running }
        public var canResume: Bool { self == .paused || self == .suspended }
        public var canReboot: Bool { self == .running }
        public var canOpenConsole: Bool { self == .running }
    }

    public enum GraphicsType: String, Sendable {
        case vnc, spice
    }

    public init(
        id: UUID = UUID(),
        name: String,
        uuid: String,
        state: VMState,
        vcpus: Int,
        memoryMB: Int,
        graphicsType: GraphicsType?,
        hasSerial: Bool
    ) {
        self.id = id
        self.name = name
        self.uuid = uuid
        self.state = state
        self.vcpus = vcpus
        self.memoryMB = memoryMB
        self.graphicsType = graphicsType
        self.hasSerial = hasSerial
    }
}
