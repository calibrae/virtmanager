import Foundation
import CSpice

/// Handles the SPICE inputs channel: keyboard and mouse input forwarding.
public final class SpiceInput: @unchecked Sendable {
    private let channel: UnsafeMutableRawPointer // gpointer to SpiceInputsChannel

    /// Tracks which mouse buttons are currently pressed (as a bitmask).
    private var buttonState: gint = 0

    init(channel: UnsafeMutableRawPointer) {
        self.channel = channel
    }

    // MARK: - Keyboard

    /// Sends a key press event with the given PC AT scancode (set 1).
    public func keyPress(scancode: UInt32) {
        let inputsChannel = cspice_to_inputs_channel(channel)
        spice_inputs_channel_key_press(inputsChannel, guint(scancode))
    }

    /// Sends a key release event with the given PC AT scancode (set 1).
    public func keyRelease(scancode: UInt32) {
        let inputsChannel = cspice_to_inputs_channel(channel)
        spice_inputs_channel_key_release(inputsChannel, guint(scancode))
    }

    // MARK: - Mouse

    /// Sends an absolute mouse position event.
    public func mousePosition(x: Int, y: Int, display: Int = 0) {
        let inputsChannel = cspice_to_inputs_channel(channel)
        spice_inputs_channel_position(inputsChannel, gint(x), gint(y), gint(display), buttonState)
    }

    /// Sends a mouse button press event.
    public func mouseButtonPress(button: Int, maskBit: Int) {
        buttonState |= gint(maskBit)
        let inputsChannel = cspice_to_inputs_channel(channel)
        spice_inputs_channel_button_press(inputsChannel, gint(button), buttonState)
    }

    /// Sends a mouse button release event.
    public func mouseButtonRelease(button: Int, maskBit: Int) {
        buttonState &= ~gint(maskBit)
        let inputsChannel = cspice_to_inputs_channel(channel)
        spice_inputs_channel_button_release(inputsChannel, gint(button), buttonState)
    }
}
