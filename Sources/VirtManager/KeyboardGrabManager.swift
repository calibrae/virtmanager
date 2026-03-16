import AppKit
import CoreGraphics

/// Manages keyboard grab mode for console windows using CGEvent taps.
/// When grabbed, all keyboard events are intercepted and forwarded to the VM console
/// instead of the host OS. Press Ctrl+Alt to release the grab.
@MainActor
public final class KeyboardGrabManager {
    public static let shared = KeyboardGrabManager()

    public private(set) var isGrabbed = false

    /// CGEvent tap and run loop source (created/destroyed on grab/ungrab).
    nonisolated(unsafe) private var eventTap: CFMachPort?
    nonisolated(unsafe) private var runLoopSource: CFRunLoopSource?

    /// Callback invoked for each captured key event while grabbed.
    public var onKeyEvent: ((CGEvent) -> Void)?

    /// Called when grab state changes (for UI updates).
    public var onGrabStateChanged: ((Bool) -> Void)?

    // MARK: - Accessibility

    /// Check if we have accessibility permission (required for CGEvent taps).
    public var hasAccessibilityPermission: Bool {
        AXIsProcessTrusted()
    }

    /// Request accessibility permission — shows the system prompt.
    public func requestAccessibilityPermission() {
        // Use the string literal "AXTrustedCheckOptionPrompt" to avoid Swift 6 concurrency
        // issues with the kAXTrustedCheckOptionPrompt global variable.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    // MARK: - Grab / Ungrab

    /// Activates the keyboard grab. All keyboard events will be intercepted and forwarded
    /// via `onKeyEvent`. Press Ctrl+Alt to release.
    public func grab() {
        guard !isGrabbed else { return }

        if !hasAccessibilityPermission {
            requestAccessibilityPermission()
            return
        }

        let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue) |
                                (1 << CGEventType.keyUp.rawValue) |
                                (1 << CGEventType.flagsChanged.rawValue)

        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passRetained(event) }
            let manager = Unmanaged<KeyboardGrabManager>.fromOpaque(refcon).takeUnretainedValue()

            // If the tap is disabled by the system, re-enable it
            if type == .tapDisabledByUserInput || type == .tapDisabledByTimeout {
                if let tap = manager.eventTap {
                    CGEvent.tapEnable(tap: tap, enable: true)
                }
                return Unmanaged.passRetained(event)
            }

            // Check for release shortcut: both Ctrl and Alt pressed simultaneously
            if type == .flagsChanged {
                let flags = event.flags
                if flags.contains(.maskControl) && flags.contains(.maskAlternate) {
                    DispatchQueue.main.async {
                        manager.ungrab()
                    }
                    return Unmanaged.passRetained(event)
                }
            }

            // Forward to the console via the callback
            manager.onKeyEvent?(event)
            return nil // Consume the event
        }

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: selfPtr
        ) else {
            print("[KeyboardGrab] Failed to create CGEvent tap — accessibility permission needed")
            return
        }

        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        isGrabbed = true
        onGrabStateChanged?(true)
    }

    /// Releases the keyboard grab. Normal keyboard input is restored.
    public func ungrab() {
        guard isGrabbed else { return }
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let source = runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            }
        }
        eventTap = nil
        runLoopSource = nil
        isGrabbed = false
        onKeyEvent = nil
        onGrabStateChanged?(false)
    }
}
