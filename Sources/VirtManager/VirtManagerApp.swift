import SwiftUI
import VirtManagerCore

public struct VirtManagerAppView: App {
    @State private var appState = AppState()

    public init() {}

    public var body: some Scene {
        WindowGroup {
            MainContentView()
                .environment(appState)
        }
        .defaultSize(width: 1000, height: 700)

        Settings {
            PreferencesView()
        }
    }
}
