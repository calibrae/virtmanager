import AppKit
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
