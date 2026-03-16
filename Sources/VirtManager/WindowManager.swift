import AppKit
import SwiftUI
import LibvirtSwift
import VirtManagerCore

/// Tracks open console windows and manages their lifecycle.
/// Ensures only one console window per VM is open at a time.
@MainActor
public final class WindowManager {
    public static let shared = WindowManager()

    /// Tracks open VNC console windows by VM ID.
    private var consoleWindows: [UUID: ConsoleWindowController] = [:]

    /// Tracks open serial console windows by VM ID.
    private var serialWindows: [UUID: NSWindowController] = [:]

    /// Tracks open configuration editor windows by VM ID.
    private var configWindows: [UUID: NSWindowController] = [:]

    /// Tracks open storage manager windows by connection ID.
    private var storageManagerWindows: [UUID: NSWindowController] = [:]

    /// Tracks open network manager windows by connection ID.
    private var networkManagerWindows: [UUID: NSWindowController] = [:]

    private init() {}

    // MARK: - VNC Console

    /// Opens or brings to front a VNC console window for the given VM.
    /// - Parameters:
    ///   - vm: The virtual machine info.
    ///   - connectionID: The connection this VM belongs to.
    ///   - host: The VNC host to connect to.
    ///   - port: The VNC port.
    ///   - password: Optional VNC password.
    func openVNCConsole(
        for vm: VMInfo,
        connectionID: UUID,
        host: String,
        port: UInt16,
        password: String? = nil
    ) {
        // If already open, bring to front
        if let existing = consoleWindows[vm.id] {
            existing.window?.makeKeyAndOrderFront(nil)
            return
        }

        let controller = ConsoleWindowController(vm: vm, connectionID: connectionID)
        consoleWindows[vm.id] = controller
        controller.showWindow(nil)
        controller.connectVNC(host: host, port: port, password: password)
    }

    /// Opens a VNC console window using a file descriptor from virDomainOpenGraphicsFD.
    func openVNCConsoleWithFD(
        for vm: VMInfo,
        connectionID: UUID,
        fd: Int32
    ) {
        if let existing = consoleWindows[vm.id] {
            existing.window?.makeKeyAndOrderFront(nil)
            return
        }

        let controller = ConsoleWindowController(vm: vm, connectionID: connectionID)
        consoleWindows[vm.id] = controller
        controller.showWindow(nil)
        controller.connectVNCWithFD(fd: fd)
    }

    // MARK: - SPICE Console

    /// Opens or brings to front a SPICE console window for the given VM.
    func openSPICEConsole(
        for vm: VMInfo,
        connectionID: UUID,
        host: String,
        port: UInt16
    ) {
        // If already open, bring to front
        if let existing = consoleWindows[vm.id] {
            existing.window?.makeKeyAndOrderFront(nil)
            return
        }

        let controller = ConsoleWindowController(vm: vm, connectionID: connectionID)
        consoleWindows[vm.id] = controller
        controller.showWindow(nil)
        controller.connectSPICE(host: host, port: port)
    }

    /// Opens a serial console window for the given VM.
    func openSerialConsole(
        for vm: VMInfo,
        connectionID: UUID,
        libvirtConnection: LibvirtConnection
    ) {
        // If already open, bring to front
        if let existing = serialWindows[vm.id] {
            existing.window?.makeKeyAndOrderFront(nil)
            return
        }

        let viewController = SerialConsoleViewController(vm: vm, connectionID: connectionID)
        let window = NSWindow(contentViewController: viewController)
        window.title = "\(vm.name) — Serial Console"
        window.setContentSize(NSSize(width: 800, height: 500))
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.minSize = NSSize(width: 400, height: 300)
        window.center()

        let controller = NSWindowController(window: window)
        serialWindows[vm.id] = controller
        controller.showWindow(nil)

        // Connect the stream on a background thread (blocking libvirt call)
        let vmName = vm.name
        let conn = libvirtConnection
        DispatchQueue.global(qos: .userInitiated).async {
            let stream = LibvirtStream()
            do {
                try stream.open(connection: conn, domainName: vmName, devName: nil)
                DispatchQueue.main.async {
                    viewController.connect(using: stream)
                }
            } catch {
                DispatchQueue.main.async {
                    viewController.showError("Failed to open console stream: \(error.localizedDescription)")
                }
            }
        }

        // Set up close notification
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.serialWindowClosed(vmID: vm.id)
            }
        }
    }

    // MARK: - Configuration Editor

    /// Opens or brings to front a configuration editor window for the given VM.
    func openConfigurationWindow(for vm: VMInfo, connectionID: UUID, appState: AppState? = nil) {
        if let existing = configWindows[vm.id] {
            existing.window?.makeKeyAndOrderFront(nil)
            return
        }

        let configView = VMConfigurationView(vmName: vm.name, connectionID: connectionID)
        let rootView: AnyView
        if let appState = appState {
            rootView = AnyView(configView.environment(appState))
        } else {
            rootView = AnyView(configView)
        }
        let hostingView = NSHostingController(rootView: rootView)

        // We need the AppState from the environment; use a workaround by
        // looking it up from the shared app. Since we're @MainActor and the
        // caller passes through AppState, we embed via the shared window approach.
        let window = NSWindow(contentViewController: hostingView)
        window.title = "\(vm.name) — Configuration"
        window.setContentSize(NSSize(width: 750, height: 550))
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.minSize = NSSize(width: 600, height: 400)
        window.center()

        let controller = NSWindowController(window: window)
        configWindows[vm.id] = controller
        controller.showWindow(nil)

        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.configWindowClosed(vmID: vm.id)
            }
        }
    }

    // MARK: - Storage Pool Manager

    /// Opens or brings to front a storage pool manager window for the given connection.
    func openStorageManager(connectionID: UUID, appState: AppState) {
        if let existing = storageManagerWindows[connectionID] {
            existing.window?.makeKeyAndOrderFront(nil)
            return
        }

        let view = StoragePoolManager(connectionID: connectionID)
            .environment(appState)
        let hostingView = NSHostingController(rootView: view)

        let window = NSWindow(contentViewController: hostingView)
        window.title = "Storage Pools"
        window.setContentSize(NSSize(width: 700, height: 500))
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.minSize = NSSize(width: 500, height: 350)
        window.center()

        let controller = NSWindowController(window: window)
        storageManagerWindows[connectionID] = controller
        controller.showWindow(nil)

        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.storageManagerWindows.removeValue(forKey: connectionID)
            }
        }
    }

    // MARK: - Network Manager

    /// Opens or brings to front a network manager window for the given connection.
    func openNetworkManager(connectionID: UUID, appState: AppState) {
        if let existing = networkManagerWindows[connectionID] {
            existing.window?.makeKeyAndOrderFront(nil)
            return
        }

        let view = NetworkListView(connectionID: connectionID)
            .environment(appState)
        let hostingView = NSHostingController(rootView: view)

        let window = NSWindow(contentViewController: hostingView)
        window.title = "Virtual Networks"
        window.setContentSize(NSSize(width: 850, height: 550))
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.minSize = NSSize(width: 450, height: 300)
        window.center()

        let controller = NSWindowController(window: window)
        networkManagerWindows[connectionID] = controller
        controller.showWindow(nil)

        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.networkManagerWindows.removeValue(forKey: connectionID)
            }
        }
    }

    // MARK: - Network Topology

    private var topologyWindows: [UUID: NSWindowController] = [:]

    /// Opens or brings to front a network topology window.
    func openNetworkTopology(connectionID: UUID, appState: AppState) {
        if let existing = topologyWindows[connectionID] {
            existing.window?.makeKeyAndOrderFront(nil)
            return
        }

        let view = NetworkTopologyView(connectionID: connectionID)
            .environment(appState)
        let hostingView = NSHostingController(rootView: view)

        let window = NSWindow(contentViewController: hostingView)
        window.title = "Network Topology"
        window.setContentSize(NSSize(width: 900, height: 600))
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.minSize = NSSize(width: 600, height: 400)
        window.center()

        let controller = NSWindowController(window: window)
        topologyWindows[connectionID] = controller
        controller.showWindow(nil)

        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.topologyWindows.removeValue(forKey: connectionID)
            }
        }
    }

    /// Called when a configuration editor window is closed.
    func configWindowClosed(vmID: UUID) {
        configWindows.removeValue(forKey: vmID)
    }

    /// Returns true if a configuration editor is open for the given VM.
    func hasOpenConfigWindow(vmID: UUID) -> Bool {
        configWindows[vmID] != nil
    }

    /// Called when a VNC console window is closed.
    func consoleWindowClosed(vmID: UUID) {
        consoleWindows.removeValue(forKey: vmID)
    }

    /// Called when a serial console window is closed.
    func serialWindowClosed(vmID: UUID) {
        serialWindows.removeValue(forKey: vmID)
    }

    /// Closes all console windows for a given connection (e.g., on disconnect).
    func closeAllWindows(for connectionID: UUID) {
        // Close console windows
        for (vmID, controller) in consoleWindows {
            controller.window?.close()
            consoleWindows.removeValue(forKey: vmID)
        }
        // Close serial windows
        for (vmID, controller) in serialWindows {
            controller.window?.close()
            serialWindows.removeValue(forKey: vmID)
        }
        // Close config windows
        for (vmID, controller) in configWindows {
            controller.window?.close()
            configWindows.removeValue(forKey: vmID)
        }
    }

    /// Returns true if a VNC console is open for the given VM.
    func hasOpenConsole(vmID: UUID) -> Bool {
        consoleWindows[vmID] != nil
    }

    /// Returns true if a serial console is open for the given VM.
    func hasOpenSerialConsole(vmID: UUID) -> Bool {
        serialWindows[vmID] != nil
    }
}
