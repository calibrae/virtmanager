import Foundation

/// State machine for the RFB 3.8 protocol.
/// Handles parsing of server messages and generation of client messages.
public final class RFBProtocolHandler: Sendable {

    /// The pixel format we request from the server.
    public let requestedPixelFormat: RFBPixelFormat

    public init(pixelFormat: RFBPixelFormat = .bgra32) {
        self.requestedPixelFormat = pixelFormat
    }

    // MARK: - Handshake

    /// Parses the server's protocol version string.
    /// Returns the client's version response string (always 3.8).
    public func parseServerVersion(_ data: Data) throws -> Data {
        guard let version = String(data: data, encoding: .ascii) else {
            throw VNCError.protocolError("Invalid version string")
        }
        // We only support RFB 3.8
        guard version.hasPrefix("RFB 003.00") else {
            throw VNCError.protocolError("Unsupported RFB version: \(version.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
        guard let response = rfbProtocolVersion.data(using: .ascii) else {
            throw VNCError.protocolError("Failed to encode version response")
        }
        return response
    }

    // MARK: - Security

    /// Parses the security types offered by the server.
    /// Returns (selectedType, responseData).
    public func parseSecurityTypes(_ data: [UInt8]) throws -> (RFBSecurityType, Data) {
        guard data.count >= 1 else {
            throw VNCError.protocolError("Empty security types")
        }
        let numTypes = Int(data[0])

        if numTypes == 0 {
            // Server is sending an error message
            let errorMsg = parseErrorMessage(Array(data.dropFirst()))
            throw VNCError.connectionFailed(errorMsg)
        }

        guard data.count >= 1 + numTypes else {
            throw VNCError.protocolError("Truncated security types")
        }

        let types = Array(data[1..<(1 + numTypes)])
        guard let selected = RFBSecurity.selectSecurityType(from: types) else {
            throw VNCError.unsupportedSecurityType
        }

        // Send back the selected security type
        return (selected, Data([selected.rawValue]))
    }

    /// Parses the security result (4 bytes, big-endian UInt32).
    /// 0 = OK, 1 = failed.
    public func parseSecurityResult(_ data: [UInt8]) throws {
        guard data.count >= 4 else {
            throw VNCError.protocolError("Truncated security result")
        }
        let result = UInt32(data[0]) << 24 | UInt32(data[1]) << 16 | UInt32(data[2]) << 8 | UInt32(data[3])
        if result != 0 {
            throw VNCError.authenticationFailed
        }
    }

    // MARK: - Init

    /// Generates the ClientInit message.
    /// `sharedFlag` = 1 means allow other clients.
    public func makeClientInit(shared: Bool = true) -> Data {
        Data([shared ? 1 : 0])
    }

    /// Parses the ServerInit message.
    public func parseServerInit(_ data: [UInt8]) throws -> RFBServerInit {
        guard data.count >= 24 else {
            throw VNCError.protocolError("ServerInit too short (\(data.count) bytes)")
        }

        let width = UInt16(data[0]) << 8 | UInt16(data[1])
        let height = UInt16(data[2]) << 8 | UInt16(data[3])

        guard let pixelFormat = RFBPixelFormat.fromBytes(data[4..<20]) else {
            throw VNCError.protocolError("Invalid pixel format in ServerInit")
        }

        let nameLen = Int(UInt32(data[20]) << 24 | UInt32(data[21]) << 16 | UInt32(data[22]) << 8 | UInt32(data[23]))
        var name = ""
        if nameLen > 0 && data.count >= 24 + nameLen {
            name = String(bytes: data[24..<(24 + nameLen)], encoding: .utf8) ?? ""
        }

        return RFBServerInit(width: width, height: height, pixelFormat: pixelFormat, name: name)
    }

    // MARK: - Client-to-Server Messages

    /// SetPixelFormat message (message type 0).
    public func makeSetPixelFormat() -> Data {
        var bytes: [UInt8] = [RFBClientMessageType.setPixelFormat.rawValue, 0, 0, 0] // type + 3 padding
        bytes.append(contentsOf: requestedPixelFormat.toBytes())
        return Data(bytes)
    }

    /// SetEncodings message (message type 2).
    public func makeSetEncodings(_ encodings: [RFBEncodingType] = [.copyRect, .raw]) -> Data {
        var bytes: [UInt8] = [RFBClientMessageType.setEncodings.rawValue, 0] // type + 1 padding
        let count = UInt16(encodings.count)
        bytes.append(UInt8(count >> 8))
        bytes.append(UInt8(count & 0xFF))

        for enc in encodings {
            let val = enc.rawValue
            bytes.append(UInt8(truncatingIfNeeded: val >> 24))
            bytes.append(UInt8(truncatingIfNeeded: val >> 16))
            bytes.append(UInt8(truncatingIfNeeded: val >> 8))
            bytes.append(UInt8(truncatingIfNeeded: val))
        }
        return Data(bytes)
    }

    /// FramebufferUpdateRequest message (message type 3).
    public func makeFramebufferUpdateRequest(
        incremental: Bool,
        x: UInt16 = 0, y: UInt16 = 0,
        width: UInt16, height: UInt16
    ) -> Data {
        var bytes: [UInt8] = [RFBClientMessageType.framebufferUpdateRequest.rawValue]
        bytes.append(incremental ? 1 : 0)
        bytes.append(UInt8(x >> 8)); bytes.append(UInt8(x & 0xFF))
        bytes.append(UInt8(y >> 8)); bytes.append(UInt8(y & 0xFF))
        bytes.append(UInt8(width >> 8)); bytes.append(UInt8(width & 0xFF))
        bytes.append(UInt8(height >> 8)); bytes.append(UInt8(height & 0xFF))
        return Data(bytes)
    }

    /// KeyEvent message (message type 4).
    public func makeKeyEvent(downFlag: Bool, keySym: UInt32) -> Data {
        var bytes: [UInt8] = [RFBClientMessageType.keyEvent.rawValue]
        bytes.append(downFlag ? 1 : 0)
        bytes.append(0); bytes.append(0) // padding
        bytes.append(UInt8(keySym >> 24))
        bytes.append(UInt8((keySym >> 16) & 0xFF))
        bytes.append(UInt8((keySym >> 8) & 0xFF))
        bytes.append(UInt8(keySym & 0xFF))
        return Data(bytes)
    }

    /// PointerEvent message (message type 5).
    public func makePointerEvent(buttonMask: UInt8, x: UInt16, y: UInt16) -> Data {
        var bytes: [UInt8] = [RFBClientMessageType.pointerEvent.rawValue]
        bytes.append(buttonMask)
        bytes.append(UInt8(x >> 8)); bytes.append(UInt8(x & 0xFF))
        bytes.append(UInt8(y >> 8)); bytes.append(UInt8(y & 0xFF))
        return Data(bytes)
    }

    // MARK: - Server-to-Client Parsing

    /// Parses a FramebufferUpdate header.
    /// Returns the number of rectangles to follow.
    public func parseFramebufferUpdateHeader(_ data: [UInt8]) throws -> Int {
        // message-type(1) + padding(1) + number-of-rectangles(2)
        guard data.count >= 4 else {
            throw VNCError.protocolError("FramebufferUpdate header too short")
        }
        return Int(UInt16(data[2]) << 8 | UInt16(data[3]))
    }

    /// Parses a rectangle header (12 bytes).
    public func parseRectHeader(_ data: [UInt8]) throws -> RFBRect {
        guard data.count >= 12 else {
            throw VNCError.protocolError("Rectangle header too short")
        }
        let x = UInt16(data[0]) << 8 | UInt16(data[1])
        let y = UInt16(data[2]) << 8 | UInt16(data[3])
        let w = UInt16(data[4]) << 8 | UInt16(data[5])
        let h = UInt16(data[6]) << 8 | UInt16(data[7])
        let enc = Int32(bitPattern:
            UInt32(data[8]) << 24 | UInt32(data[9]) << 16 |
            UInt32(data[10]) << 8 | UInt32(data[11])
        )
        return RFBRect(x: x, y: y, width: w, height: h, encoding: enc)
    }

    // MARK: - Helpers

    private func parseErrorMessage(_ data: [UInt8]) -> String {
        if data.count >= 4 {
            let len = Int(UInt32(data[0]) << 24 | UInt32(data[1]) << 16 | UInt32(data[2]) << 8 | UInt32(data[3]))
            if data.count >= 4 + len {
                return String(bytes: data[4..<(4 + len)], encoding: .utf8) ?? "Unknown error"
            }
        }
        return "Connection refused by server"
    }
}
