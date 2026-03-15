import SwiftUI
import VirtManager

@main
struct AppEntry: App {
    @State private var appState = AppState()

    var body: some Scene {
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
