import AppKit
import CoreGraphics
import SpiceClient

/// Mouse input mode for the SPICE console.
enum SpiceMouseMode {
    case absolute   // Default: map host cursor position directly to guest
    case relative   // Captured: send deltas, hide host cursor
}

/// NSView subclass that renders SPICE display output as CGImages
/// and forwards keyboard/mouse events via the SPICE inputs channel.
final class SpiceConsoleView: NSView {
    private var connection: SpiceConnection?
    private var currentImage: CGImage?
    private var trackingArea: NSTrackingArea?

    /// Whether this view should capture keyboard input.
    var isCapturingInput: Bool = true

    /// Current mouse input mode (absolute or relative).
    var mouseMode: SpiceMouseMode = .absolute

    /// Whether the mouse is currently grabbed in relative mode.
    private(set) var isMouseGrabbed: Bool = false

    override var acceptsFirstResponder: Bool { true }
    override var canBecomeKeyView: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    private func setupView() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.isOpaque = true
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext,
              let image = currentImage else { return }

        let imageSize = CGSize(width: image.width, height: image.height)
        let viewSize = bounds.size
        let scale = min(viewSize.width / imageSize.width, viewSize.height / imageSize.height)
        let drawSize = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        let drawOrigin = CGPoint(
            x: (viewSize.width - drawSize.width) / 2,
            y: (viewSize.height - drawSize.height) / 2
        )

        // Fill black bars
        context.setFillColor(NSColor.black.cgColor)
        context.fill(bounds)

        // Draw the image — Core Graphics reads directly from the SPICE surface memory
        context.interpolationQuality = .none
        context.draw(image, in: CGRect(origin: drawOrigin, size: drawSize))
    }

    // MARK: - Public API

    /// Attaches a SPICE connection and begins rendering frames.
    func attach(connection: SpiceConnection) {
        self.connection = connection

        connection.onFrameUpdate = { [weak self] image, dirtyRect in
            guard let self else { return }
            self.currentImage = image

            // Map the SPICE dirty rect to view coordinates and repaint only that region
            let imageW = CGFloat(image.width)
            let imageH = CGFloat(image.height)
            let viewSize = self.bounds.size
            guard imageW > 0, imageH > 0 else { return }

            let scale = min(viewSize.width / imageW, viewSize.height / imageH)
            let drawOriginX = (viewSize.width - imageW * scale) / 2
            let drawOriginY = (viewSize.height - imageH * scale) / 2

            // Convert SPICE coordinates (top-left origin) to NSView (bottom-left origin)
            let viewX = drawOriginX + CGFloat(dirtyRect.x) * scale
            let viewY = drawOriginY + (imageH - CGFloat(dirtyRect.y) - CGFloat(dirtyRect.height)) * scale
            let viewW = CGFloat(dirtyRect.width) * scale
            let viewH = CGFloat(dirtyRect.height) * scale

            let nsRect = NSRect(x: viewX, y: viewY, width: viewW, height: viewH)
            self.setNeedsDisplay(nsRect)
        }
    }

    /// Detaches the current connection.
    func detach() {
        ungrabMouse()
        connection?.onFrameUpdate = nil
        connection = nil
        currentImage = nil
        needsDisplay = true
    }

    /// Sets the mouse mode. Call when the SPICE server indicates a mode change.
    func setMouseMode(_ mode: SpiceMouseMode) {
        if mouseMode != mode {
            mouseMode = mode
            if mode == .absolute && isMouseGrabbed {
                ungrabMouse()
            }
        }
    }

    /// Grabs the mouse for relative mode: hides cursor and disassociates cursor movement.
    func grabMouse() {
        guard !isMouseGrabbed else { return }
        isMouseGrabbed = true
        NSCursor.hide()
        CGEvent(source: nil)?.post(tap: .cghidEventTap) // Ensure events flow
    }

    /// Releases the mouse grab: shows cursor and restores normal behavior.
    func ungrabMouse() {
        guard isMouseGrabbed else { return }
        isMouseGrabbed = false
        NSCursor.unhide()
    }

    // MARK: - Coordinate Mapping

    /// Maps a view point to guest display coordinates.
    private func mapToDisplay(_ point: NSPoint) -> (Int, Int)? {
        guard let image = currentImage else { return nil }

        let imageSize = CGSize(width: image.width, height: image.height)
        let viewSize = bounds.size
        let scale = min(viewSize.width / imageSize.width, viewSize.height / imageSize.height)
        let drawSize = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        let drawOrigin = CGPoint(
            x: (viewSize.width - drawSize.width) / 2,
            y: (viewSize.height - drawSize.height) / 2
        )

        let fbX = (point.x - drawOrigin.x) / scale
        // Flip Y: NSView has origin at bottom-left, guest display has origin at top-left
        let fbY = CGFloat(image.height) - (point.y - drawOrigin.y) / scale

        guard fbX >= 0, fbX < CGFloat(image.width), fbY >= 0, fbY < CGFloat(image.height) else {
            return nil
        }
        return (Int(fbX), Int(fbY))
    }

    // MARK: - Keyboard Events

    override func keyDown(with event: NSEvent) {
        guard isCapturingInput, let input = connection?.input else {
            super.keyDown(with: event)
            return
        }
        if let scancode = SpiceKeyMapping.scancodeForKeyCode(event.keyCode) {
            input.keyPress(scancode: scancode)
        }
    }

    override func keyUp(with event: NSEvent) {
        guard isCapturingInput, let input = connection?.input else {
            super.keyUp(with: event)
            return
        }
        if let scancode = SpiceKeyMapping.scancodeForKeyCode(event.keyCode) {
            input.keyRelease(scancode: scancode)
        }
    }

    override func flagsChanged(with event: NSEvent) {
        guard isCapturingInput, let input = connection?.input else {
            super.flagsChanged(with: event)
            return
        }

        // Handle modifier key press/release
        struct ModifierMapping {
            let keyCode: UInt16
            let flag: NSEvent.ModifierFlags
            let scancode: UInt32
        }

        let modifiers: [ModifierMapping] = [
            ModifierMapping(keyCode: 0x38, flag: .shift, scancode: SpiceKeyMapping.scLeftShift),
            ModifierMapping(keyCode: 0x3C, flag: .shift, scancode: SpiceKeyMapping.scRightShift),
            ModifierMapping(keyCode: 0x3B, flag: .control, scancode: SpiceKeyMapping.scLeftControl),
            ModifierMapping(keyCode: 0x3E, flag: .control, scancode: SpiceKeyMapping.scRightControl),
            ModifierMapping(keyCode: 0x3A, flag: .option, scancode: SpiceKeyMapping.scLeftAlt),
            ModifierMapping(keyCode: 0x3D, flag: .option, scancode: SpiceKeyMapping.scRightAlt),
            ModifierMapping(keyCode: 0x37, flag: .command, scancode: SpiceKeyMapping.scLeftMeta),
            ModifierMapping(keyCode: 0x36, flag: .command, scancode: SpiceKeyMapping.scRightMeta),
        ]

        for mapping in modifiers {
            if event.keyCode == mapping.keyCode {
                let isDown = event.modifierFlags.contains(mapping.flag)
                if isDown {
                    input.keyPress(scancode: mapping.scancode)
                } else {
                    input.keyRelease(scancode: mapping.scancode)
                }
                return
            }
        }
    }

    // MARK: - Mouse Events

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    // SPICE mouse button constants (from spice/enums.h)
    private static let spiceMouseButtonLeft = 1
    private static let spiceMouseButtonMiddle = 2
    private static let spiceMouseButtonRight = 3
    private static let spiceMouseButtonUp = 4
    private static let spiceMouseButtonDown = 5

    private static let spiceMouseButtonMaskLeft = 1 << 0
    private static let spiceMouseButtonMaskMiddle = 1 << 1
    private static let spiceMouseButtonMaskRight = 1 << 2

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        guard isCapturingInput, let input = connection?.input else {
            super.mouseDown(with: event)
            return
        }
        if mouseMode == .relative && !isMouseGrabbed {
            grabMouse()
        }
        let point = convert(event.locationInWindow, from: nil)
        if mouseMode == .relative && isMouseGrabbed {
            input.mouseButtonPress(
                button: Self.spiceMouseButtonLeft,
                maskBit: Self.spiceMouseButtonMaskLeft
            )
        } else if let (x, y) = mapToDisplay(point) {
            input.mousePosition(x: x, y: y)
            input.mouseButtonPress(
                button: Self.spiceMouseButtonLeft,
                maskBit: Self.spiceMouseButtonMaskLeft
            )
        }
    }

    override func mouseUp(with event: NSEvent) {
        guard isCapturingInput, let input = connection?.input else {
            super.mouseUp(with: event)
            return
        }
        if mouseMode == .relative && isMouseGrabbed {
            input.mouseButtonRelease(
                button: Self.spiceMouseButtonLeft,
                maskBit: Self.spiceMouseButtonMaskLeft
            )
        } else {
            let point = convert(event.locationInWindow, from: nil)
            if let (x, y) = mapToDisplay(point) {
                input.mousePosition(x: x, y: y)
                input.mouseButtonRelease(
                    button: Self.spiceMouseButtonLeft,
                    maskBit: Self.spiceMouseButtonMaskLeft
                )
            }
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        guard isCapturingInput, let input = connection?.input else {
            super.rightMouseDown(with: event)
            return
        }
        if mouseMode == .relative && isMouseGrabbed {
            input.mouseButtonPress(
                button: Self.spiceMouseButtonRight,
                maskBit: Self.spiceMouseButtonMaskRight
            )
        } else {
            let point = convert(event.locationInWindow, from: nil)
            if let (x, y) = mapToDisplay(point) {
                input.mousePosition(x: x, y: y)
                input.mouseButtonPress(
                    button: Self.spiceMouseButtonRight,
                    maskBit: Self.spiceMouseButtonMaskRight
                )
            }
        }
    }

    override func rightMouseUp(with event: NSEvent) {
        guard isCapturingInput, let input = connection?.input else {
            super.rightMouseUp(with: event)
            return
        }
        if mouseMode == .relative && isMouseGrabbed {
            input.mouseButtonRelease(
                button: Self.spiceMouseButtonRight,
                maskBit: Self.spiceMouseButtonMaskRight
            )
        } else {
            let point = convert(event.locationInWindow, from: nil)
            if let (x, y) = mapToDisplay(point) {
                input.mousePosition(x: x, y: y)
                input.mouseButtonRelease(
                    button: Self.spiceMouseButtonRight,
                    maskBit: Self.spiceMouseButtonMaskRight
                )
            }
        }
    }

    override func mouseMoved(with event: NSEvent) {
        guard isCapturingInput, let input = connection?.input else {
            super.mouseMoved(with: event)
            return
        }
        if mouseMode == .relative && isMouseGrabbed {
            let dx = Int(event.deltaX)
            let dy = Int(event.deltaY)
            input.mouseMotion(dx: dx, dy: dy)
        } else {
            let point = convert(event.locationInWindow, from: nil)
            if let (x, y) = mapToDisplay(point) {
                input.mousePosition(x: x, y: y)
            }
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard isCapturingInput, let input = connection?.input else {
            super.mouseDragged(with: event)
            return
        }
        if mouseMode == .relative && isMouseGrabbed {
            let dx = Int(event.deltaX)
            let dy = Int(event.deltaY)
            input.mouseMotion(dx: dx, dy: dy)
        } else {
            let point = convert(event.locationInWindow, from: nil)
            if let (x, y) = mapToDisplay(point) {
                input.mousePosition(x: x, y: y)
            }
        }
    }

    override func scrollWheel(with event: NSEvent) {
        guard isCapturingInput, let input = connection?.input else {
            super.scrollWheel(with: event)
            return
        }
        let point = convert(event.locationInWindow, from: nil)
        if let (x, y) = mapToDisplay(point) {
            input.mousePosition(x: x, y: y)
            if event.scrollingDeltaY > 0 {
                input.mouseButtonPress(button: Self.spiceMouseButtonUp, maskBit: 1 << 3)
                input.mouseButtonRelease(button: Self.spiceMouseButtonUp, maskBit: 1 << 3)
            } else if event.scrollingDeltaY < 0 {
                input.mouseButtonPress(button: Self.spiceMouseButtonDown, maskBit: 1 << 4)
                input.mouseButtonRelease(button: Self.spiceMouseButtonDown, maskBit: 1 << 4)
            }
        }
    }
}
