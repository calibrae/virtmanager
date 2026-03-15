import Foundation
import CoreGraphics
import CSpice

/// Connection state for the SPICE session.
public enum SpiceConnectionState: Sendable {
    case disconnected
    case connecting
    case connected
    case error(String)
}

/// Main SPICE session wrapper.
public final class SpiceConnection: @unchecked Sendable {
    private let glibBridge = GLibBridge()
    private var session: UnsafeMutablePointer<SpiceSession>?

    public internal(set) var display: SpiceDisplay?
    public internal(set) var input: SpiceInput?

    public var onStateChange: ((SpiceConnectionState) -> Void)?
    public var onFrameUpdate: ((CGImage) -> Void)?

    private var state: SpiceConnectionState = .disconnected {
        didSet {
            let handler = onStateChange
            let newState = state
            DispatchQueue.main.async { handler?(newState) }
        }
    }

    public init() {}

    deinit { disconnect() }

    public func connect(host: String, port: UInt16) {
        state = .connecting
        glibBridge.start()

        glibBridge.schedule { [weak self] in
            guard let self else { return }

            guard let session = spice_session_new() else {
                DispatchQueue.main.async { self.state = .error("Failed to create SPICE session") }
                return
            }
            self.session = session

            let uri = "spice://\(host):\(port)"
            let sessionObj = UnsafeMutableRawPointer(session)
            cspice_set_string_property(sessionObj, "uri", uri)

            let selfPtr = Unmanaged.passUnretained(self).toOpaque()

            // Connect "channel-new" signal with a C-convention closure
            let channelNewCB: @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> Void = { _, channelRaw, userData in
                guard let userData, let channelRaw else { return }
                let conn = Unmanaged<SpiceConnection>.fromOpaque(userData).takeUnretainedValue()
                let channel = channelRaw.assumingMemoryBound(to: SpiceChannel.self)
                conn.handleNewChannel(channel)
            }
            cspice_signal_connect(sessionObj, "channel-new",
                                  unsafeBitCast(channelNewCB, to: GCallback.self), selfPtr)

            // Connect "disconnected" signal
            let disconnectedCB: @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> Void = { _, userData in
                guard let userData else { return }
                let conn = Unmanaged<SpiceConnection>.fromOpaque(userData).takeUnretainedValue()
                DispatchQueue.main.async { conn.state = .disconnected }
            }
            cspice_signal_connect(sessionObj, "disconnected",
                                  unsafeBitCast(disconnectedCB, to: GCallback.self), selfPtr)

            let ok = spice_session_connect(session)
            if ok == 0 {
                DispatchQueue.main.async { self.state = .error("spice_session_connect failed") }
            }
        }
    }

    public func disconnect() {
        glibBridge.schedule { [weak self] in
            guard let self, let session = self.session else { return }
            spice_session_disconnect(session)
            g_object_unref(UnsafeMutableRawPointer(session))
            self.session = nil
        }
        display = nil
        input = nil
        state = .disconnected
        glibBridge.stop()
    }

    // MARK: - Channel handling (called on GLib thread)

    fileprivate func handleNewChannel(_ channel: UnsafeMutablePointer<SpiceChannel>) {
        let channelType = cspice_channel_get_channel_type(channel)

        if channelType == gint(SPICE_CHANNEL_DISPLAY) {
            let display = SpiceDisplay(channel: UnsafeMutableRawPointer(channel))
            self.display = display
            display.onFrameUpdate = { [weak self] image in
                self?.onFrameUpdate?(image)
            }

            // Listen for channel-event to detect connected state
            let selfPtr = Unmanaged.passUnretained(self).toOpaque()
            let eventCB: @convention(c) (UnsafeMutableRawPointer?, gint, UnsafeMutableRawPointer?) -> Void = { _, eventRaw, userData in
                guard let userData else { return }
                let conn = Unmanaged<SpiceConnection>.fromOpaque(userData).takeUnretainedValue()
                let event = SpiceChannelEvent(UInt32(eventRaw))
                conn.handleChannelEvent(event)
            }
            cspice_signal_connect(UnsafeMutableRawPointer(channel), "channel-event",
                                  unsafeBitCast(eventCB, to: GCallback.self), selfPtr)

        } else if channelType == gint(SPICE_CHANNEL_INPUTS) {
            let input = SpiceInput(channel: UnsafeMutableRawPointer(channel))
            self.input = input
        }
    }

    fileprivate func handleChannelEvent(_ event: SpiceChannelEvent) {
        switch event {
        case SPICE_CHANNEL_OPENED:
            DispatchQueue.main.async { self.state = .connected }
        case SPICE_CHANNEL_CLOSED:
            DispatchQueue.main.async { self.state = .disconnected }
        case SPICE_CHANNEL_ERROR_CONNECT, SPICE_CHANNEL_ERROR_TLS,
             SPICE_CHANNEL_ERROR_LINK, SPICE_CHANNEL_ERROR_AUTH,
             SPICE_CHANNEL_ERROR_IO:
            DispatchQueue.main.async { self.state = .error("Channel error: \(event.rawValue)") }
        default:
            break
        }
    }
}
