import SwiftUI

public struct StatusBar: View {
    @Environment(AppState.self) private var appState

    public init() {}

    public var body: some View {
        HStack {
            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)
            Text(appState.statusMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
        .background(.bar)
        .allowsHitTesting(false)
    }
}
