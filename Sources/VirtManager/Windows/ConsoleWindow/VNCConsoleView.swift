import AppKit
import VNCClient

/// NSView subclass that renders a VNC framebuffer using Core Graphics
/// and handles keyboard/mouse input.
final class VNCConsoleView: NSView {
    private var connection: RFBConnection?
    private var currentImage: CGImage?
    private var displayLink: CVDisplayLink?
    private var lastGeneration: UInt64 = 0
    private var trackingArea: NSTrackingArea?

    /// Whether this view should capture keyboard input.
    var isCapturingInput: Bool = true

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
    }

    // MARK: - Public API

    /// Attaches a VNC connection and begins rendering.
    func attach(connection: RFBConnection) {
        self.connection = connection

        connection.onFramebufferUpdate = { [weak self] generation in
            DispatchQueue.main.async {
                self?.updateFramebuffer(generation: generation)
            }
        }

        // Start periodic refresh timer as fallback
        startRefreshTimer()
    }

    /// Detaches the current connection.
    func detach() {
        stopRefreshTimer()
        connection = nil
        currentImage = nil
        needsDisplay = true
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        // Fill background
        context.setFillColor(NSColor.black.cgColor)
        context.fill(bounds)

        guard let image = currentImage else { return }

        // Calculate aspect-fit rect
        let imageSize = CGSize(width: image.width, height: image.height)
        let viewSize = bounds.size
        let scale = min(viewSize.width / imageSize.width, viewSize.height / imageSize.height)
        let drawSize = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        let drawOrigin = CGPoint(
            x: (viewSize.width - drawSize.width) / 2,
            y: (viewSize.height - drawSize.height) / 2
        )
        let drawRect = CGRect(origin: drawOrigin, size: drawSize)

        context.interpolationQuality = .high
        context.draw(image, in: drawRect)
    }

    private func updateFramebuffer(generation: UInt64) {
        guard generation != lastGeneration else { return }
        lastGeneration = generation
        currentImage = connection?.framebuffer?.makeCGImage()
        needsDisplay = true
    }

    // MARK: - Coordinate Mapping

    /// Maps a view point to framebuffer coordinates.
    private func mapToFramebuffer(_ point: NSPoint) -> (UInt16, UInt16)? {
        guard let fb = connection?.framebuffer else { return nil }

        let imageSize = CGSize(width: fb.width, height: fb.height)
        let viewSize = bounds.size
        let scale = min(viewSize.width / imageSize.width, viewSize.height / imageSize.height)
        let drawSize = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        let drawOrigin = CGPoint(
            x: (viewSize.width - drawSize.width) / 2,
            y: (viewSize.height - drawSize.height) / 2
        )

        // Convert from view coordinates to framebuffer coordinates
        let fbX = (point.x - drawOrigin.x) / scale
        // Flip Y since NSView has origin at bottom-left but VNC has origin at top-left
        let fbY = CGFloat(fb.height) - (point.y - drawOrigin.y) / scale

        guard fbX >= 0, fbX < CGFloat(fb.width), fbY >= 0, fbY < CGFloat(fb.height) else {
            return nil
        }
        return (UInt16(fbX), UInt16(fbY))
    }

    // MARK: - Keyboard Events

    override func keyDown(with event: NSEvent) {
        guard isCapturingInput else { super.keyDown(with: event); return }
        if let keySym = keySym(for: event) {
            connection?.sendKeyEvent(down: true, keySym: keySym)
        }
    }

    override func keyUp(with event: NSEvent) {
        guard isCapturingInput else { super.keyUp(with: event); return }
        if let keySym = keySym(for: event) {
            connection?.sendKeyEvent(down: false, keySym: keySym)
        }
    }

    override func flagsChanged(with event: NSEvent) {
        guard isCapturingInput else { super.flagsChanged(with: event); return }

        // Handle modifier key changes
        sendModifierEvent(event: event, keyCode: 56, flag: .shift, keySym: RFBKeyMapping.KeySym.shiftLeft)
        sendModifierEvent(event: event, keyCode: 59, flag: .control, keySym: RFBKeyMapping.KeySym.controlLeft)
        sendModifierEvent(event: event, keyCode: 58, flag: .option, keySym: RFBKeyMapping.KeySym.altLeft)
        sendModifierEvent(event: event, keyCode: 55, flag: .command, keySym: RFBKeyMapping.KeySym.metaLeft)
    }

    private func sendModifierEvent(event: NSEvent, keyCode: UInt16, flag: NSEvent.ModifierFlags, keySym: UInt32) {
        if event.keyCode == keyCode {
            let isDown = event.modifierFlags.contains(flag)
            connection?.sendKeyEvent(down: isDown, keySym: keySym)
        }
    }

    private func keySym(for event: NSEvent) -> UInt32? {
        // First try mapping the keyCode directly (for special keys)
        if let sym = RFBKeyMapping.keysymForKeyCode(event.keyCode) {
            return sym
        }
        // Fall back to character-based mapping
        if let chars = event.characters, let char = chars.first {
            return RFBKeyMapping.keysymForCharacter(char)
        }
        return nil
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

    override func mouseDown(with event: NSEvent) {
        guard isCapturingInput else { super.mouseDown(with: event); return }
        sendMouseEvent(event: event, buttonMask: 1)
    }

    override func mouseUp(with event: NSEvent) {
        guard isCapturingInput else { super.mouseUp(with: event); return }
        sendMouseEvent(event: event, buttonMask: 0)
    }

    override func rightMouseDown(with event: NSEvent) {
        guard isCapturingInput else { super.rightMouseDown(with: event); return }
        sendMouseEvent(event: event, buttonMask: 4)
    }

    override func rightMouseUp(with event: NSEvent) {
        guard isCapturingInput else { super.rightMouseUp(with: event); return }
        sendMouseEvent(event: event, buttonMask: 0)
    }

    override func mouseMoved(with event: NSEvent) {
        guard isCapturingInput else { super.mouseMoved(with: event); return }
        sendMouseEvent(event: event, buttonMask: 0)
    }

    override func mouseDragged(with event: NSEvent) {
        guard isCapturingInput else { super.mouseDragged(with: event); return }
        sendMouseEvent(event: event, buttonMask: 1)
    }

    override func scrollWheel(with event: NSEvent) {
        guard isCapturingInput else { super.scrollWheel(with: event); return }
        // VNC encodes scroll as button 4 (up) and button 5 (down)
        if event.scrollingDeltaY > 0 {
            sendMouseEvent(event: event, buttonMask: 8)  // button 4
            sendMouseEvent(event: event, buttonMask: 0)
        } else if event.scrollingDeltaY < 0 {
            sendMouseEvent(event: event, buttonMask: 16) // button 5
            sendMouseEvent(event: event, buttonMask: 0)
        }
    }

    private func sendMouseEvent(event: NSEvent, buttonMask: UInt8) {
        let point = convert(event.locationInWindow, from: nil)
        guard let (x, y) = mapToFramebuffer(point) else { return }
        connection?.sendPointerEvent(buttonMask: buttonMask, x: x, y: y)
    }

    // MARK: - Refresh Timer

    private var refreshTimer: Timer?

    private func startRefreshTimer() {
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkForUpdates()
            }
        }
    }

    private func stopRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    private func checkForUpdates() {
        guard let fb = connection?.framebuffer else { return }
        if fb.generation != lastGeneration {
            updateFramebuffer(generation: fb.generation)
        }
    }
}
