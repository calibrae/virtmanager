import SwiftUI
import VirtManagerCore

public struct VMStateBadge: View {
    public let state: VMInfo.VMState

    public init(state: VMInfo.VMState) {
        self.state = state
    }

    public var body: some View {
        Image(systemName: state.sfSymbol)
            .foregroundStyle(color)
    }

    private var color: Color {
        switch state {
        case .running: .green
        case .paused: .yellow
        case .shutOff: .secondary
        case .crashed: .red
        case .suspended: .purple
        case .unknown: .secondary
        }
    }
}
