import Foundation
import CoreGraphics
import CSpice

public enum SpiceConnectionState: Sendable {
    case disconnected, connecting, connected
    case error(String)
}

public final class SpiceConnection: @unchecked Sendable {
    private let glibBridge = GLibBridge()
    private var session: UnsafeMutablePointer<SpiceSession>?
    var isDisconnecting = false

    public internal(set) var display: SpiceDisplay?
    public internal(set) var input: SpiceInput?
    public internal(set) var usbManager: SpiceUSBManager?
    public var onStateChange: ((SpiceConnectionState) -> Void)?
    public var onFrameUpdate: ((CGImage, SpiceDirtyRect) -> Void)?

    public private(set) var state: SpiceConnectionState = .disconnected

    private func setState(_ newState: SpiceConnectionState) {
        guard !isDisconnecting else { return }
        state = newState
        let handler = onStateChange
        DispatchQueue.main.async { handler?(newState) }
    }

    public init() {}

    deinit {
        onStateChange = nil
        onFrameUpdate = nil
    }

    public func connect(host: String, port: UInt16) {
        isDisconnecting = false
        setState(.connecting)
        glibBridge.start()

        glibBridge.schedule { [weak self] in
            guard let self else { return }

            guard let session = spice_session_new() else {
                self.setState(.error("spice_session_new failed"))
                return
            }
            self.session = session

            let uri = "spice://\(host):\(port)"
            cspice_set_string_property(UnsafeMutableRawPointer(session), "uri", uri)

            let selfPtr = Unmanaged.passUnretained(self).toOpaque()

            cspice_signal_connect(UnsafeMutableRawPointer(session), "channel-new",
                unsafeBitCast(spiceChannelNew as @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> Void, to: GCallback.self), selfPtr)

            cspice_signal_connect(UnsafeMutableRawPointer(session), "disconnected",
                unsafeBitCast(spiceSessionDisconnected as @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> Void, to: GCallback.self), selfPtr)

            let ok = spice_session_connect(session)
            if ok == 0 {
                self.setState(.error("spice_session_connect failed"))
            } else {
                self.usbManager = SpiceUSBManager(session: session, glibBridge: self.glibBridge)
            }
        }
    }

    public func disconnect() {
        // Mark as disconnecting first to suppress any further state callbacks
        isDisconnecting = true
        onStateChange = nil
        onFrameUpdate = nil

        // Cleanup display signals on GLib thread
        let disp = display
        display = nil
        input = nil
        usbManager = nil

        glibBridge.schedule { [weak self] in
            disp?.cleanup()
            guard let self, let session = self.session else { return }
            spice_session_disconnect(session)
            g_object_unref(UnsafeMutableRawPointer(session))
            self.session = nil
        }

        state = .disconnected
        // Give GLib thread time to process before stopping
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.glibBridge.stop()
        }
    }

    fileprivate func handleNewChannel(_ channel: UnsafeMutablePointer<SpiceChannel>) {
        guard !isDisconnecting else { return }
        let channelType = cspice_channel_get_channel_type(channel)

        if channelType == gint(SPICE_CHANNEL_DISPLAY) {
            let display = SpiceDisplay(channel: UnsafeMutableRawPointer(channel))
            self.display = display
            display.onFrameUpdate = { [weak self] image, dirtyRect in
                guard let self, !self.isDisconnecting else { return }
                self.onFrameUpdate?(image, dirtyRect)
            }

            let selfPtr = Unmanaged.passUnretained(self).toOpaque()
            cspice_signal_connect(UnsafeMutableRawPointer(channel), "channel-event",
                unsafeBitCast(spiceChannelEvent as @convention(c) (UnsafeMutableRawPointer?, gint, UnsafeMutableRawPointer?) -> Void, to: GCallback.self), selfPtr)

        } else if channelType == gint(SPICE_CHANNEL_INPUTS) {
            self.input = SpiceInput(channel: UnsafeMutableRawPointer(channel), glibBridge: glibBridge)
        }
    }

    fileprivate func handleChannelEvent(_ event: SpiceChannelEvent) {
        guard !isDisconnecting else { return }
        switch event {
        case SPICE_CHANNEL_OPENED:
            setState(.connected)
        case SPICE_CHANNEL_CLOSED:
            setState(.disconnected)
        case SPICE_CHANNEL_ERROR_CONNECT, SPICE_CHANNEL_ERROR_TLS,
             SPICE_CHANNEL_ERROR_LINK, SPICE_CHANNEL_ERROR_AUTH, SPICE_CHANNEL_ERROR_IO:
            setState(.error("Channel error: \(event.rawValue)"))
        default: break
        }
    }
}

// MARK: - Top-level C callbacks

private func spiceChannelNew(_ session: UnsafeMutableRawPointer?, _ channelRaw: UnsafeMutableRawPointer?, _ userData: UnsafeMutableRawPointer?) {
    guard let userData, let channelRaw else { return }
    Unmanaged<SpiceConnection>.fromOpaque(userData).takeUnretainedValue()
        .handleNewChannel(channelRaw.assumingMemoryBound(to: SpiceChannel.self))
}

private func spiceSessionDisconnected(_ session: UnsafeMutableRawPointer?, _ userData: UnsafeMutableRawPointer?) {
    guard let userData else { return }
    let conn = Unmanaged<SpiceConnection>.fromOpaque(userData).takeUnretainedValue()
    guard !conn.isDisconnecting else { return }
    conn.handleChannelEvent(SPICE_CHANNEL_CLOSED)
}

private func spiceChannelEvent(_ channel: UnsafeMutableRawPointer?, _ eventRaw: gint, _ userData: UnsafeMutableRawPointer?) {
    guard let userData else { return }
    let conn = Unmanaged<SpiceConnection>.fromOpaque(userData).takeUnretainedValue()
    guard !conn.isDisconnecting else { return }
    conn.handleChannelEvent(SpiceChannelEvent(UInt32(eventRaw)))
}
