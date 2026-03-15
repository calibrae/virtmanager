import Foundation
import CoreGraphics
import CSpice

/// Handles the SPICE display channel: receives surface data and converts it to CGImage.
public final class SpiceDisplay: @unchecked Sendable {
    private let channel: UnsafeMutableRawPointer // gpointer to SpiceDisplayChannel
    private var surfaceData: UnsafeMutablePointer<UInt8>?
    private var surfaceWidth: Int = 0
    private var surfaceHeight: Int = 0
    private var surfaceStride: Int = 0
    private var hasPrimary: Bool = false

    /// Called on the main thread when a new frame is available.
    public var onFrameUpdate: ((CGImage) -> Void)?

    init(channel: UnsafeMutableRawPointer) {
        self.channel = channel

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        // Connect "display-primary-create" signal
        _ = cspice_signal_connect(
            channel,
            "display-primary-create",
            unsafeBitCast(displayPrimaryCreateCallback, to: GCallback.self),
            selfPtr
        )

        // Connect "display-invalidate" signal
        _ = cspice_signal_connect(
            channel,
            "display-invalidate",
            unsafeBitCast(displayInvalidateCallback, to: GCallback.self),
            selfPtr
        )

        // Connect "display-primary-destroy" signal
        _ = cspice_signal_connect(
            channel,
            "display-primary-destroy",
            unsafeBitCast(displayPrimaryDestroyCallback, to: GCallback.self),
            selfPtr
        )

        // Try to get the primary surface if it already exists
        fetchPrimary()
    }

    /// Attempts to read the primary surface from the display channel.
    private func fetchPrimary() {
        var primary = SpiceDisplayPrimary()
        let spiceChannel = cspice_to_channel(channel)
        let ok = spice_display_channel_get_primary(spiceChannel, 0, &primary)
        if ok != 0 {
            updateSurface(
                data: primary.data,
                width: Int(primary.width),
                height: Int(primary.height),
                stride: Int(primary.stride)
            )
        }
    }

    fileprivate func updateSurface(data: UnsafeMutablePointer<UInt8>?, width: Int, height: Int, stride: Int) {
        surfaceData = data
        surfaceWidth = width
        surfaceHeight = height
        surfaceStride = stride
        hasPrimary = true
    }

    fileprivate func destroySurface() {
        surfaceData = nil
        hasPrimary = false
    }

    /// Creates a CGImage from the current surface data.
    fileprivate func makeCGImage() -> CGImage? {
        guard hasPrimary, let data = surfaceData, surfaceWidth > 0, surfaceHeight > 0 else {
            return nil
        }

        // SPICE surface format is 32-bit xRGB (BGRX in memory on little-endian)
        // which maps to CGImage's 32-bit BGRA with noneSkipFirst (xRGB)
        let bitsPerComponent = 8
        let bytesPerRow = abs(surfaceStride)

        // If stride is negative, data points to the last row
        let actualData: UnsafeMutablePointer<UInt8>
        if surfaceStride < 0 {
            actualData = data.advanced(by: surfaceStride * (surfaceHeight - 1))
        } else {
            actualData = data
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: actualData,
            width: surfaceWidth,
            height: surfaceHeight,
            bitsPerComponent: bitsPerComponent,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else {
            return nil
        }

        return context.makeImage()
    }
}

// MARK: - C Callbacks

private func displayPrimaryCreateCallback(
    _ channel: UnsafeMutableRawPointer?,
    _ format: gint,
    _ width: gint,
    _ height: gint,
    _ stride: gint,
    _ shmid: gint,
    _ data: gpointer?,
    _ userData: gpointer?
) {
    guard let userData else { return }
    let display = Unmanaged<SpiceDisplay>.fromOpaque(userData).takeUnretainedValue()
    display.updateSurface(
        data: data?.assumingMemoryBound(to: UInt8.self),
        width: Int(width),
        height: Int(height),
        stride: Int(stride)
    )
}

private func displayInvalidateCallback(
    _ channel: UnsafeMutableRawPointer?,
    _ x: gint,
    _ y: gint,
    _ w: gint,
    _ h: gint,
    _ userData: gpointer?
) {
    guard let userData else { return }
    let display = Unmanaged<SpiceDisplay>.fromOpaque(userData).takeUnretainedValue()

    // Create a CGImage from the current surface
    guard let image = display.makeCGImage() else { return }

    let handler = display.onFrameUpdate
    DispatchQueue.main.async {
        handler?(image)
    }
}

private func displayPrimaryDestroyCallback(
    _ channel: UnsafeMutableRawPointer?,
    _ userData: gpointer?
) {
    guard let userData else { return }
    let display = Unmanaged<SpiceDisplay>.fromOpaque(userData).takeUnretainedValue()
    display.destroySurface()
}
