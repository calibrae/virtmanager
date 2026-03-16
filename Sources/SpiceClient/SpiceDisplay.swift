import Foundation
import CoreGraphics
import CSpice

public struct SpiceDirtyRect: Sendable {
    public let x: Int, y: Int, width: Int, height: Int
}

public final class SpiceDisplay: @unchecked Sendable {
    let channel: UnsafeMutableRawPointer
    private var surfaceData: UnsafeMutablePointer<UInt8>?
    private var surfaceWidth: Int = 0
    private var surfaceHeight: Int = 0
    private var surfaceStride: Int = 0
    private var hasPrimary: Bool = false
    private var destroyed = false

    /// Persistent CGImage backed by the SPICE surface memory.
    var persistentImage: CGImage?

    /// Signal handler IDs for disconnection on cleanup
    private var signalIDs: [gulong] = []

    public var onFrameUpdate: ((CGImage, SpiceDirtyRect) -> Void)?

    init(channel: UnsafeMutableRawPointer) {
        self.channel = channel
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        let id1 = cspice_signal_connect(channel, "display-primary-create",
            unsafeBitCast(spiceDisplayPrimaryCreate as @convention(c) (UnsafeMutableRawPointer?, gint, gint, gint, gint, gint, UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> Void, to: GCallback.self), selfPtr)

        let id2 = cspice_signal_connect(channel, "display-invalidate",
            unsafeBitCast(spiceDisplayInvalidate as @convention(c) (UnsafeMutableRawPointer?, gint, gint, gint, gint, UnsafeMutableRawPointer?) -> Void, to: GCallback.self), selfPtr)

        let id3 = cspice_signal_connect(channel, "display-primary-destroy",
            unsafeBitCast(spiceDisplayPrimaryDestroy as @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> Void, to: GCallback.self), selfPtr)

        signalIDs = [id1, id2, id3]

        spice_channel_connect(channel.assumingMemoryBound(to: SpiceChannel.self))
        fetchPrimary()
    }

    /// Disconnect all GLib signals so callbacks can't fire after deallocation.
    func cleanup() {
        destroyed = true
        onFrameUpdate = nil
        for sid in signalIDs {
            g_signal_handler_disconnect(channel, sid)
        }
        signalIDs = []
        persistentImage = nil
    }

    private func fetchPrimary() {
        var primary = SpiceDisplayPrimary()
        let success = spice_display_channel_get_primary(
            channel.assumingMemoryBound(to: SpiceChannel.self), 0, &primary)
        if success != 0 {
            createSurface(data: primary.data, width: Int(primary.width),
                         height: Int(primary.height), stride: Int(primary.stride))
        }
    }

    func createSurface(data: UnsafeMutablePointer<UInt8>?, width: Int, height: Int, stride: Int) {
        surfaceData = data
        surfaceWidth = width
        surfaceHeight = height
        surfaceStride = stride
        hasPrimary = (data != nil && width > 0 && height > 0)

        guard hasPrimary, let data else { persistentImage = nil; return }

        let bytesPerRow = abs(stride)
        let totalBytes = bytesPerRow * height
        let actualData = stride < 0 ? data.advanced(by: stride * (height - 1)) : data

        guard let provider = CGDataProvider(dataInfo: nil, data: actualData,
                                            size: totalBytes,
                                            releaseData: { _, _, _ in }) else { return }
        persistentImage = CGImage(
            width: width, height: height,
            bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        )

        if let img = persistentImage {
            let fullRect = SpiceDirtyRect(x: 0, y: 0, width: width, height: height)
            let handler = onFrameUpdate
            DispatchQueue.main.async { handler?(img, fullRect) }
        }
    }

    func handleInvalidate(x: Int, y: Int, w: Int, h: Int) {
        guard !destroyed, hasPrimary, let handler = onFrameUpdate else { return }
        // Must create a fresh CGImage each time because CGImage caches pixel data.
        // CGDataProvider(data:) is zero-copy — just wraps the pointer — so this is cheap.
        guard let img = makeCurrentImage() else { return }
        let rect = SpiceDirtyRect(x: x, y: y, width: w, height: h)
        DispatchQueue.main.async { handler(img, rect) }
    }

    private func makeCurrentImage() -> CGImage? {
        guard let data = surfaceData, surfaceWidth > 0, surfaceHeight > 0 else { return nil }
        let bytesPerRow = abs(surfaceStride)
        let totalBytes = bytesPerRow * surfaceHeight
        let actualData = surfaceStride < 0 ? data.advanced(by: surfaceStride * (surfaceHeight - 1)) : data
        guard let provider = CGDataProvider(dataInfo: nil, data: actualData,
                                            size: totalBytes,
                                            releaseData: { _, _, _ in }) else { return nil }
        return CGImage(
            width: surfaceWidth, height: surfaceHeight,
            bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        )
    }

    func handlePrimaryDestroy() {
        hasPrimary = false
        surfaceData = nil
        persistentImage = nil
    }
}

// MARK: - Top-level C callbacks

private func spiceDisplayPrimaryCreate(
    _ channel: UnsafeMutableRawPointer?, _ format: gint,
    _ width: gint, _ height: gint, _ stride: gint, _ shmid: gint,
    _ data: UnsafeMutableRawPointer?, _ userData: UnsafeMutableRawPointer?
) {
    guard let userData else { return }
    Unmanaged<SpiceDisplay>.fromOpaque(userData).takeUnretainedValue()
        .createSurface(data: data?.assumingMemoryBound(to: UInt8.self),
                      width: Int(width), height: Int(height), stride: Int(stride))
}

private func spiceDisplayInvalidate(
    _ channel: UnsafeMutableRawPointer?, _ x: gint, _ y: gint,
    _ w: gint, _ h: gint, _ userData: UnsafeMutableRawPointer?
) {
    guard let userData else { return }
    Unmanaged<SpiceDisplay>.fromOpaque(userData).takeUnretainedValue()
        .handleInvalidate(x: Int(x), y: Int(y), w: Int(w), h: Int(h))
}

private func spiceDisplayPrimaryDestroy(
    _ channel: UnsafeMutableRawPointer?, _ userData: UnsafeMutableRawPointer?
) {
    guard let userData else { return }
    Unmanaged<SpiceDisplay>.fromOpaque(userData).takeUnretainedValue()
        .handlePrimaryDestroy()
}
