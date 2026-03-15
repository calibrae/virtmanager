import AppKit
import SwiftTerm
import LibvirtSwift
import VirtManagerCore

/// Serial console using SwiftTerm — a full VT100/xterm terminal emulator.
/// Connects to the VM via a libvirt console stream and pipes I/O through SwiftTerm.
public final class SerialConsoleViewController: NSViewController, @preconcurrency TerminalViewDelegate {
    private let vm: VMInfo
    private let connectionID: UUID
    private var stream: LibvirtStream?
    private var terminalView: TerminalView!
    private var readThread: Thread?
    private var connected = false

    public init(vm: VMInfo, connectionID: UUID) {
        self.vm = vm
        self.connectionID = connectionID
        super.init(nibName: nil, bundle: nil)
        self.title = "\(vm.name) — Serial Console"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    public override func loadView() {
        let tv = TerminalView(frame: NSRect(x: 0, y: 0, width: 800, height: 500))
        tv.terminalDelegate = self
        tv.autoresizingMask = [.width, .height]

        // Configure appearance
        tv.font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        tv.nativeForegroundColor = NSColor(red: 0.9, green: 0.9, blue: 0.9, alpha: 1.0)
        tv.nativeBackgroundColor = NSColor(red: 0.1, green: 0.1, blue: 0.12, alpha: 1.0)
        tv.caretColor = NSColor(red: 0.9, green: 0.9, blue: 0.9, alpha: 1.0)

        self.terminalView = tv
        self.view = tv
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        terminalView.feed(text: "Connecting to serial console for \(vm.name)...\r\n")
    }

    public override func viewWillDisappear() {
        super.viewWillDisappear()
        disconnect()
    }

    // MARK: - Connection

    public func connect(using libvirtStream: LibvirtStream) {
        self.stream = libvirtStream
        self.connected = true
        terminalView.feed(text: "Connected.\r\n\r\n")
        startReading()
    }

    public func disconnect() {
        connected = false
        readThread?.cancel()
        readThread = nil
        stream?.close()
        stream = nil
    }

    public func showError(_ message: String) {
        terminalView.feed(text: "\r\n[Error: \(message)]\r\n")
    }

    // MARK: - Stream I/O

    private func startReading() {
        let thread = Thread { [weak self] in
            self?.readLoop()
        }
        thread.name = "SerialConsole-\(vm.name)"
        thread.qualityOfService = .userInitiated
        readThread = thread
        thread.start()
    }

    private func readLoop() {
        while connected, let stream = self.stream, !Thread.current.isCancelled {
            do {
                let data = try stream.recv()
                if data.isEmpty { break } // EOF
                // Feed raw bytes to SwiftTerm — it handles all escape sequences
                let bytes = ArraySlice(data)
                DispatchQueue.main.async { [weak self] in
                    self?.terminalView.feed(byteArray: bytes)
                }
            } catch {
                DispatchQueue.main.async { [weak self] in
                    self?.terminalView.feed(text: "\r\n[Stream error: \(error.localizedDescription)]\r\n")
                    self?.connected = false
                }
                break
            }
        }
    }

    private func sendToStream(_ data: Data) {
        guard let stream, connected else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try stream.send(data)
            } catch {
                DispatchQueue.main.async { [weak self] in
                    self?.terminalView.feed(text: "\r\n[Send error: \(error.localizedDescription)]\r\n")
                }
            }
        }
    }

    // MARK: - TerminalViewDelegate

    /// Called by SwiftTerm when the user types — send to the VM
    public func send(source: TerminalView, data: ArraySlice<UInt8>) {
        sendToStream(Data(data))
    }

    public func scrolled(source: TerminalView, position: Double) {}
    public func setTerminalTitle(source: TerminalView, title: String) {
        DispatchQueue.main.async { [weak self] in
            self?.view.window?.title = title
        }
    }
    public func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {}
    public func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
    public func requestOpenLink(source: TerminalView, link: String, params: [String : String]) {}
    public func clipboardCopy(source: TerminalView, content: Data) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setData(content, forType: .string)
    }
    public func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
}
