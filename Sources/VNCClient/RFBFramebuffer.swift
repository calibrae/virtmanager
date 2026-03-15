import CoreGraphics
import Foundation

/// Manages the pixel buffer for VNC framebuffer data.
/// Thread-safe: all mutations are serialized on an internal queue.
public final class RFBFramebuffer: @unchecked Sendable {
    public private(set) var width: Int
    public private(set) var height: Int
    public private(set) var pixelFormat: RFBPixelFormat

    /// The raw pixel data (BGRA, 4 bytes per pixel).
    private var pixelData: [UInt8]
    private let lock = NSLock()

    /// Incremented on every update for change detection.
    public private(set) var generation: UInt64 = 0

    public init(width: Int, height: Int, pixelFormat: RFBPixelFormat = .bgra32) {
        self.width = width
        self.height = height
        self.pixelFormat = pixelFormat
        self.pixelData = [UInt8](repeating: 0, count: width * height * 4)
    }

    /// Resizes the framebuffer, clearing pixel data.
    public func resize(width: Int, height: Int) {
        lock.lock()
        defer { lock.unlock() }
        self.width = width
        self.height = height
        self.pixelData = [UInt8](repeating: 0, count: width * height * 4)
        generation &+= 1
    }

    /// Applies a Raw encoding rectangle update.
    /// `data` must contain exactly `rect.width * rect.height * bytesPerPixel` bytes.
    public func applyRawRect(_ rect: RFBRect, data: ArraySlice<UInt8>) {
        lock.lock()
        defer { lock.unlock() }

        let bpp = Int(pixelFormat.bitsPerPixel) / 8
        let rw = Int(rect.width)
        let rh = Int(rect.height)
        let rx = Int(rect.x)
        let ry = Int(rect.y)

        guard data.count >= rw * rh * bpp else { return }
        let dataBase = data.startIndex

        for row in 0..<rh {
            let destY = ry + row
            guard destY < height else { continue }
            let destOffset = (destY * width + rx) * 4
            let srcOffset = dataBase + row * rw * bpp

            for col in 0..<rw {
                let destX = rx + col
                guard destX < width else { continue }
                let dIdx = destOffset + col * 4
                let sIdx = srcOffset + col * bpp

                guard dIdx + 3 < pixelData.count, sIdx + bpp - 1 < data.endIndex else { continue }

                if bpp == 4 {
                    // Assume BGRA ordering matching our requested format
                    pixelData[dIdx] = data[sIdx]
                    pixelData[dIdx + 1] = data[sIdx + 1]
                    pixelData[dIdx + 2] = data[sIdx + 2]
                    pixelData[dIdx + 3] = 255
                } else if bpp == 2 {
                    // 16-bit: extract using pixel format shifts
                    let pixel = UInt16(data[sIdx]) | (UInt16(data[sIdx + 1]) << 8)
                    pixelData[dIdx] = extractChannel(pixel, max: pixelFormat.blueMax, shift: pixelFormat.blueShift)
                    pixelData[dIdx + 1] = extractChannel(pixel, max: pixelFormat.greenMax, shift: pixelFormat.greenShift)
                    pixelData[dIdx + 2] = extractChannel(pixel, max: pixelFormat.redMax, shift: pixelFormat.redShift)
                    pixelData[dIdx + 3] = 255
                }
            }
        }
        generation &+= 1
    }

    /// Applies a CopyRect encoding update: copies pixels from (srcX, srcY).
    public func applyCopyRect(_ rect: RFBRect, srcX: UInt16, srcY: UInt16) {
        lock.lock()
        defer { lock.unlock() }

        let rw = Int(rect.width)
        let rh = Int(rect.height)
        let rx = Int(rect.x)
        let ry = Int(rect.y)
        let sx = Int(srcX)
        let sy = Int(srcY)

        // Copy to a temp buffer first to handle overlapping regions
        var temp = [UInt8](repeating: 0, count: rw * rh * 4)
        for row in 0..<rh {
            let srcRow = sy + row
            guard srcRow < height else { continue }
            for col in 0..<rw {
                let srcCol = sx + col
                guard srcCol < width else { continue }
                let srcIdx = (srcRow * width + srcCol) * 4
                let tmpIdx = (row * rw + col) * 4
                temp[tmpIdx] = pixelData[srcIdx]
                temp[tmpIdx + 1] = pixelData[srcIdx + 1]
                temp[tmpIdx + 2] = pixelData[srcIdx + 2]
                temp[tmpIdx + 3] = pixelData[srcIdx + 3]
            }
        }

        // Write temp to destination
        for row in 0..<rh {
            let destRow = ry + row
            guard destRow < height else { continue }
            for col in 0..<rw {
                let destCol = rx + col
                guard destCol < width else { continue }
                let dstIdx = (destRow * width + destCol) * 4
                let tmpIdx = (row * rw + col) * 4
                pixelData[dstIdx] = temp[tmpIdx]
                pixelData[dstIdx + 1] = temp[tmpIdx + 1]
                pixelData[dstIdx + 2] = temp[tmpIdx + 2]
                pixelData[dstIdx + 3] = temp[tmpIdx + 3]
            }
        }
        generation &+= 1
    }

    /// Creates a CGImage from the current framebuffer contents.
    public func makeCGImage() -> CGImage? {
        lock.lock()
        let dataCopy = pixelData
        let w = width
        let h = height
        lock.unlock()

        guard w > 0, h > 0 else { return nil }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)

        guard let provider = CGDataProvider(data: Data(dataCopy) as CFData) else { return nil }

        return CGImage(
            width: w,
            height: h,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: w * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo,
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
    }

    // MARK: - Private

    private func extractChannel(_ pixel: UInt16, max: UInt16, shift: UInt8) -> UInt8 {
        guard max > 0 else { return 0 }
        let value = (pixel >> shift) & max
        return UInt8(Int(value) * 255 / Int(max))
    }
}
