import Foundation

// MARK: - RFB Protocol Constants

/// RFB protocol version string for version 3.8.
public let rfbProtocolVersion = "RFB 003.008\n"

// MARK: - Security Types

/// Security types supported by the RFB protocol.
public enum RFBSecurityType: UInt8, Sendable {
    case invalid = 0
    case none = 1
    case vncAuthentication = 2
}

// MARK: - Client-to-Server Message Types

public enum RFBClientMessageType: UInt8, Sendable {
    case setPixelFormat = 0
    case setEncodings = 2
    case framebufferUpdateRequest = 3
    case keyEvent = 4
    case pointerEvent = 5
    case clientCutText = 6
}

// MARK: - Server-to-Client Message Types

public enum RFBServerMessageType: UInt8, Sendable {
    case framebufferUpdate = 0
    case setColorMapEntries = 1
    case bell = 2
    case serverCutText = 3
}

// MARK: - Encoding Types

public enum RFBEncodingType: Int32, Sendable {
    case raw = 0
    case copyRect = 1
    case rre = 2
    case hextile = 5
    case zrle = 16
    case cursor = -239       // 0xFFFFFF11
    case desktopSize = -223  // 0xFFFFFF21
}

// MARK: - Pixel Format

/// Describes the pixel format used for framebuffer data.
public struct RFBPixelFormat: Sendable, Equatable {
    public var bitsPerPixel: UInt8
    public var depth: UInt8
    public var bigEndian: Bool
    public var trueColor: Bool
    public var redMax: UInt16
    public var greenMax: UInt16
    public var blueMax: UInt16
    public var redShift: UInt8
    public var greenShift: UInt8
    public var blueShift: UInt8

    /// Standard 32-bit BGRA format (suitable for Core Graphics on macOS).
    public static let bgra32 = RFBPixelFormat(
        bitsPerPixel: 32,
        depth: 24,
        bigEndian: false,
        trueColor: true,
        redMax: 255,
        greenMax: 255,
        blueMax: 255,
        redShift: 16,
        greenShift: 8,
        blueShift: 0
    )

    public init(
        bitsPerPixel: UInt8 = 32,
        depth: UInt8 = 24,
        bigEndian: Bool = false,
        trueColor: Bool = true,
        redMax: UInt16 = 255,
        greenMax: UInt16 = 255,
        blueMax: UInt16 = 255,
        redShift: UInt8 = 16,
        greenShift: UInt8 = 8,
        blueShift: UInt8 = 0
    ) {
        self.bitsPerPixel = bitsPerPixel
        self.depth = depth
        self.bigEndian = bigEndian
        self.trueColor = trueColor
        self.redMax = redMax
        self.greenMax = greenMax
        self.blueMax = blueMax
        self.redShift = redShift
        self.greenShift = greenShift
        self.blueShift = blueShift
    }

    /// Serializes the pixel format to a 16-byte wire representation.
    public func toBytes() -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: 16)
        bytes[0] = bitsPerPixel
        bytes[1] = depth
        bytes[2] = bigEndian ? 1 : 0
        bytes[3] = trueColor ? 1 : 0
        bytes[4] = UInt8(redMax >> 8)
        bytes[5] = UInt8(redMax & 0xFF)
        bytes[6] = UInt8(greenMax >> 8)
        bytes[7] = UInt8(greenMax & 0xFF)
        bytes[8] = UInt8(blueMax >> 8)
        bytes[9] = UInt8(blueMax & 0xFF)
        bytes[10] = redShift
        bytes[11] = greenShift
        bytes[12] = blueShift
        // bytes[13..15] = padding
        return bytes
    }

    /// Parses a pixel format from the wire bytes (16 bytes).
    public static func fromBytes(_ bytes: ArraySlice<UInt8>) -> RFBPixelFormat? {
        guard bytes.count >= 16 else { return nil }
        let base = bytes.startIndex
        return RFBPixelFormat(
            bitsPerPixel: bytes[base],
            depth: bytes[base + 1],
            bigEndian: bytes[base + 2] != 0,
            trueColor: bytes[base + 3] != 0,
            redMax: UInt16(bytes[base + 4]) << 8 | UInt16(bytes[base + 5]),
            greenMax: UInt16(bytes[base + 6]) << 8 | UInt16(bytes[base + 7]),
            blueMax: UInt16(bytes[base + 8]) << 8 | UInt16(bytes[base + 9]),
            redShift: bytes[base + 10],
            greenShift: bytes[base + 11],
            blueShift: bytes[base + 12]
        )
    }
}

// MARK: - Server Init

/// Information received from the server during initialization.
public struct RFBServerInit: Sendable {
    public let width: UInt16
    public let height: UInt16
    public let pixelFormat: RFBPixelFormat
    public let name: String

    public init(width: UInt16, height: UInt16, pixelFormat: RFBPixelFormat, name: String) {
        self.width = width
        self.height = height
        self.pixelFormat = pixelFormat
        self.name = name
    }
}

// MARK: - Framebuffer Update Rectangle

/// A rectangle update received from the server.
public struct RFBRect: Sendable {
    public let x: UInt16
    public let y: UInt16
    public let width: UInt16
    public let height: UInt16
    public let encoding: Int32

    public init(x: UInt16, y: UInt16, width: UInt16, height: UInt16, encoding: Int32) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.encoding = encoding
    }
}

// MARK: - Connection State

/// The state of the RFB protocol connection.
public enum RFBConnectionState: Sendable, Equatable {
    case disconnected
    case connecting
    case handshaking
    case authenticating
    case initializing
    case connected
    case error(String)
}

// MARK: - VNC Error

public enum VNCError: Error, LocalizedError, Sendable {
    case connectionFailed(String)
    case protocolError(String)
    case authenticationFailed
    case authenticationRequired
    case unsupportedSecurityType
    case invalidData(String)
    case disconnected

    public var errorDescription: String? {
        switch self {
        case .connectionFailed(let reason): "VNC connection failed: \(reason)"
        case .protocolError(let reason): "VNC protocol error: \(reason)"
        case .authenticationFailed: "VNC authentication failed"
        case .authenticationRequired: "VNC server requires a password"
        case .unsupportedSecurityType: "VNC server requires an unsupported security type"
        case .invalidData(let reason): "Invalid VNC data: \(reason)"
        case .disconnected: "VNC connection lost"
        }
    }
}
