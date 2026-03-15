import SwiftUI
import VirtManagerCore

/// SwiftUI Settings view with tabs for General, Console, and Connections preferences.
public struct PreferencesView: View {
    public init() {}

    public var body: some View {
        TabView {
            GeneralPreferencesTab()
                .tabItem {
                    Label("General", systemImage: "gear")
                }

            ConsolePreferencesTab()
                .tabItem {
                    Label("Console", systemImage: "rectangle.on.rectangle")
                }

            ConnectionsPreferencesTab()
                .tabItem {
                    Label("Connections", systemImage: "network")
                }
        }
        .frame(width: 480, height: 320)
    }
}

// MARK: - General Tab

private struct GeneralPreferencesTab: View {
    @AppStorage("autoReconnect") private var autoReconnect = true
    @AppStorage("refreshInterval") private var refreshInterval = 30.0
    @AppStorage("showStatusBar") private var showStatusBar = true

    var body: some View {
        Form {
            Toggle("Automatically reconnect on launch", isOn: $autoReconnect)

            Picker("VM list refresh interval", selection: $refreshInterval) {
                Text("10 seconds").tag(10.0)
                Text("30 seconds").tag(30.0)
                Text("60 seconds").tag(60.0)
                Text("Manual only").tag(0.0)
            }

            Toggle("Show status bar", isOn: $showStatusBar)
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Console Tab

private struct ConsolePreferencesTab: View {
    @AppStorage("vncScalingMode") private var scalingMode = "fit"
    @AppStorage("vncClipboardSync") private var clipboardSync = true
    @AppStorage("serialFontSize") private var serialFontSize = 13.0

    var body: some View {
        Form {
            Section("VNC Console") {
                Picker("Scaling mode", selection: $scalingMode) {
                    Text("Fit to window").tag("fit")
                    Text("Scroll (native resolution)").tag("scroll")
                }

                Toggle("Sync clipboard with VNC server", isOn: $clipboardSync)
            }

            Section("Serial Console") {
                Slider(value: $serialFontSize, in: 9...24, step: 1) {
                    Text("Font size: \(Int(serialFontSize))pt")
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Connections Tab

private struct ConnectionsPreferencesTab: View {
    @AppStorage("sshTimeout") private var sshTimeout = 30.0
    @AppStorage("keepAliveInterval") private var keepAliveInterval = 60.0

    var body: some View {
        Form {
            Section("SSH") {
                Slider(value: $sshTimeout, in: 5...120, step: 5) {
                    Text("Connection timeout: \(Int(sshTimeout))s")
                }

                Slider(value: $keepAliveInterval, in: 0...300, step: 15) {
                    Text("Keep-alive interval: \(Int(keepAliveInterval))s")
                }
            }

            Section("Advanced") {
                Text("Additional connection settings will be available in future releases.")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
