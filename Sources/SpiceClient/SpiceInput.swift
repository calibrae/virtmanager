import Foundation
import CSpice

/// Handles the SPICE inputs channel: keyboard and mouse input forwarding.
/// All SPICE calls are dispatched to the GLib thread for thread safety.
public final class SpiceInput: @unchecked Sendable {
    private let channel: UnsafeMutableRawPointer
    private let glibBridge: GLibBridge
    private var buttonState: gint = 0

    init(channel: UnsafeMutableRawPointer, glibBridge: GLibBridge) {
        self.channel = channel
        self.glibBridge = glibBridge
        // Explicitly connect the inputs channel
        spice_channel_connect(channel.assumingMemoryBound(to: SpiceChannel.self))
    }

    // MARK: - Keyboard

    public func keyPress(scancode: UInt32) {
        let ch = channel
        glibBridge.schedule {
            spice_inputs_channel_key_press(cspice_to_inputs_channel(ch), guint(scancode))
        }
    }

    public func keyRelease(scancode: UInt32) {
        let ch = channel
        glibBridge.schedule {
            spice_inputs_channel_key_release(cspice_to_inputs_channel(ch), guint(scancode))
        }
    }

    // MARK: - Mouse

    public func mousePosition(x: Int, y: Int, display: Int = 0) {
        let ch = channel; let bs = buttonState
        glibBridge.schedule {
            spice_inputs_channel_position(cspice_to_inputs_channel(ch), gint(x), gint(y), gint(display), bs)
        }
    }

    public func mouseMotion(dx: Int, dy: Int) {
        let ch = channel; let bs = buttonState
        glibBridge.schedule {
            spice_inputs_channel_motion(cspice_to_inputs_channel(ch), gint(dx), gint(dy), bs)
        }
    }

    public func mouseButtonPress(button: Int, maskBit: Int) {
        buttonState |= gint(maskBit)
        let ch = channel; let bs = buttonState
        glibBridge.schedule {
            spice_inputs_channel_button_press(cspice_to_inputs_channel(ch), gint(button), bs)
        }
    }

    public func mouseButtonRelease(button: Int, maskBit: Int) {
        buttonState &= ~gint(maskBit)
        let ch = channel; let bs = buttonState
        glibBridge.schedule {
            spice_inputs_channel_button_release(cspice_to_inputs_channel(ch), gint(button), bs)
        }
    }
}
