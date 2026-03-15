import AppKit
import VNCClient
import SpiceClient
import VirtManagerCore

/// Window controller for VNC, SPICE, and serial console windows.
/// Each console window is managed independently with its own toolbar.
final class ConsoleWindowController: NSWindowController, NSWindowDelegate, NSToolbarDelegate {
    private let vm: VMInfo
    private let connectionID: UUID
    private var vncConnection: RFBConnection?
    private var vncConsoleView: VNCConsoleView?
    private var spiceConnection: SpiceConnection?
    private var spiceConsoleView: SpiceConsoleView?

    /// Toolbar item identifiers
    private enum ToolbarItemID {
        static let sendCtrlAltDel = NSToolbarItem.Identifier("sendCtrlAltDel")
        static let screenshot = NSToolbarItem.Identifier("screenshot")
        static let fullscreen = NSToolbarItem.Identifier("fullscreen")
        static let disconnect = NSToolbarItem.Identifier("disconnect")
    }

    init(vm: VMInfo, connectionID: UUID) {
        self.vm = vm
        self.connectionID = connectionID

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1024, height: 768),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "\(vm.name) — VNC Console"
        window.minSize = NSSize(width: 640, height: 480)
        window.center()

        super.init(window: window)
        window.delegate = self

        setupToolbar()
        setupContentView()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    // MARK: - Setup

    private func setupToolbar() {
        let toolbar = NSToolbar(identifier: "ConsoleToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        window?.toolbar = toolbar
    }

    private func setupContentView() {
        let consoleView = VNCConsoleView(frame: .zero)
        consoleView.autoresizingMask = [.width, .height]
        window?.contentView = consoleView
        vncConsoleView = consoleView
    }

    // MARK: - Connection

    /// Connects to the VNC server at the given host and port.
    func connectVNC(host: String, port: UInt16, password: String? = nil) {
        let connection = RFBConnection(host: host, port: port, password: password)
        self.vncConnection = connection

        connection.onStateChange = { [weak self] state in
            DispatchQueue.main.async {
                self?.handleConnectionStateChange(state)
            }
        }

        connection.onServerName = { [weak self] name in
            DispatchQueue.main.async {
                self?.window?.title = "\(self?.vm.name ?? "VM") — \(name)"
            }
        }

        vncConsoleView?.attach(connection: connection)

        Task {
            do {
                try await connection.connect()
            } catch {
                DispatchQueue.main.async { [weak self] in
                    self?.showConnectionError(error)
                }
            }
        }
    }

    /// Connects to VNC via a file descriptor from virDomainOpenGraphicsFD.
    func connectVNCWithFD(fd: Int32) {
        let connection = RFBConnection(fileDescriptor: fd)
        self.vncConnection = connection

        connection.onStateChange = { [weak self] state in
            DispatchQueue.main.async {
                self?.handleConnectionStateChange(state)
            }
        }

        connection.onServerName = { [weak self] name in
            DispatchQueue.main.async {
                self?.window?.title = "\(self?.vm.name ?? "VM") — \(name)"
            }
        }

        vncConsoleView?.attach(connection: connection)

        Task {
            do {
                try await connection.connect()
            } catch {
                DispatchQueue.main.async { [weak self] in
                    self?.showConnectionError(error)
                }
            }
        }
    }

    /// Connects to a SPICE server at the given host and port.
    func connectSPICE(host: String, port: UInt16) {
        // Replace content view with a SPICE console view
        let consoleView = SpiceConsoleView(frame: .zero)
        consoleView.autoresizingMask = [.width, .height]
        window?.contentView = consoleView
        spiceConsoleView = consoleView

        let connection = SpiceConnection()
        self.spiceConnection = connection

        connection.onStateChange = { [weak self] state in
            DispatchQueue.main.async {
                self?.handleSPICEStateChange(state)
            }
        }

        consoleView.attach(connection: connection)
        window?.title = "\(vm.name) — SPICE Console"
        window?.subtitle = "Connecting..."

        connection.connect(host: host, port: port)
    }

    private func handleSPICEStateChange(_ state: SpiceConnectionState) {
        switch state {
        case .connected:
            window?.subtitle = "Connected"
        case .connecting:
            window?.subtitle = "Connecting..."
        case .disconnected:
            window?.subtitle = "Disconnected"
        case .error(let msg):
            window?.subtitle = "Error: \(msg)"
        }
    }

    private func handleConnectionStateChange(_ state: RFBConnectionState) {
        switch state {
        case .connected:
            window?.subtitle = "Connected"
        case .connecting, .handshaking, .authenticating, .initializing:
            window?.subtitle = "Connecting..."
        case .disconnected:
            window?.subtitle = "Disconnected"
        case .error(let msg):
            window?.subtitle = "Error: \(msg)"
        }
    }

    private func showConnectionError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "VNC Connection Failed"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .critical
        alert.addButton(withTitle: "OK")
        if let window {
            alert.beginSheetModal(for: window)
        }
    }

    // MARK: - Actions

    @objc private func sendCtrlAltDel(_ sender: Any?) {
        guard let conn = vncConnection else { return }
        // Send Ctrl+Alt+Delete sequence
        conn.sendKeyEvent(down: true, keySym: RFBKeyMapping.KeySym.controlLeft)
        conn.sendKeyEvent(down: true, keySym: RFBKeyMapping.KeySym.altLeft)
        conn.sendKeyEvent(down: true, keySym: RFBKeyMapping.KeySym.delete)
        conn.sendKeyEvent(down: false, keySym: RFBKeyMapping.KeySym.delete)
        conn.sendKeyEvent(down: false, keySym: RFBKeyMapping.KeySym.altLeft)
        conn.sendKeyEvent(down: false, keySym: RFBKeyMapping.KeySym.controlLeft)
    }

    @objc private func takeScreenshot(_ sender: Any?) {
        // TODO: Implement screenshot saving
    }

    @objc private func toggleFullscreen(_ sender: Any?) {
        window?.toggleFullScreen(nil)
    }

    @objc private func disconnectAction(_ sender: Any?) {
        vncConsoleView?.detach()
        vncConnection?.disconnect()
        vncConnection = nil
        spiceConsoleView?.detach()
        spiceConnection?.disconnect()
        spiceConnection = nil
        window?.subtitle = "Disconnected"
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        vncConsoleView?.detach()
        vncConnection?.disconnect()
        vncConnection = nil
        spiceConsoleView?.detach()
        spiceConnection?.disconnect()
        spiceConnection = nil
        WindowManager.shared.consoleWindowClosed(vmID: vm.id)
    }

    // MARK: - NSToolbarDelegate

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        switch itemIdentifier {
        case ToolbarItemID.sendCtrlAltDel:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = "Ctrl+Alt+Del"
            item.toolTip = "Send Ctrl+Alt+Delete"
            item.image = NSImage(systemSymbolName: "keyboard", accessibilityDescription: "Send Ctrl+Alt+Del")
            item.action = #selector(sendCtrlAltDel(_:))
            item.target = self
            return item

        case ToolbarItemID.screenshot:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = "Screenshot"
            item.toolTip = "Take screenshot"
            item.image = NSImage(systemSymbolName: "camera", accessibilityDescription: "Screenshot")
            item.action = #selector(takeScreenshot(_:))
            item.target = self
            return item

        case ToolbarItemID.fullscreen:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = "Fullscreen"
            item.toolTip = "Toggle fullscreen"
            item.image = NSImage(systemSymbolName: "arrow.up.left.and.arrow.down.right", accessibilityDescription: "Fullscreen")
            item.action = #selector(toggleFullscreen(_:))
            item.target = self
            return item

        case ToolbarItemID.disconnect:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = "Disconnect"
            item.toolTip = "Disconnect console"
            item.image = NSImage(systemSymbolName: "xmark.circle", accessibilityDescription: "Disconnect")
            item.action = #selector(disconnectAction(_:))
            item.target = self
            return item

        default:
            return nil
        }
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [
            ToolbarItemID.sendCtrlAltDel,
            .flexibleSpace,
            ToolbarItemID.screenshot,
            ToolbarItemID.fullscreen,
            ToolbarItemID.disconnect,
        ]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }
}
