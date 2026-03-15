import Foundation
#if canImport(CommonCrypto)
import CommonCrypto
#endif

/// Handles RFB security type negotiation and authentication.
public enum RFBSecurity: Sendable {

    /// Selects the best security type from the offered list.
    /// Prefers None (1) over VNC Authentication (2).
    public static func selectSecurityType(from offered: [UInt8]) -> RFBSecurityType? {
        // Prefer no-auth for simplicity; fall back to VNC auth
        if offered.contains(RFBSecurityType.none.rawValue) {
            return RFBSecurityType.none
        }
        if offered.contains(RFBSecurityType.vncAuthentication.rawValue) {
            return .vncAuthentication
        }
        return nil
    }

    /// Performs VNC DES challenge-response authentication.
    ///
    /// The VNC auth flow:
    /// 1. Server sends 16-byte challenge
    /// 2. Client encrypts challenge with DES using password as key
    /// 3. Client sends 16-byte response
    ///
    /// Note: VNC uses a non-standard DES key derivation where each byte's bits are reversed.
    public static func vncAuthResponse(challenge: [UInt8], password: String) -> [UInt8] {
        precondition(challenge.count == 16, "VNC challenge must be 16 bytes")

        // Prepare the key: take first 8 bytes of password, pad with zeros
        var keyBytes = [UInt8](repeating: 0, count: 8)
        let passwordBytes = Array(password.utf8)
        for i in 0..<min(8, passwordBytes.count) {
            keyBytes[i] = passwordBytes[i]
        }

        // VNC reverses the bits in each byte of the key
        for i in 0..<8 {
            keyBytes[i] = reverseBits(keyBytes[i])
        }

        // DES-encrypt the 16-byte challenge in two 8-byte blocks
        var response = [UInt8](repeating: 0, count: 16)

        #if canImport(CommonCrypto)
        var cryptor: CCCryptorRef?
        CCCryptorCreate(
            CCOperation(kCCEncrypt),
            CCAlgorithm(kCCAlgorithmDES),
            CCOptions(kCCOptionECBMode),
            &keyBytes,
            kCCKeySizeDES,
            nil,
            &cryptor
        )

        if let cryptor {
            var bytesOut: Int = 0

            // Encrypt first 8 bytes
            var block1 = Array(challenge[0..<8])
            CCCryptorUpdate(cryptor, &block1, 8, &response, 8, &bytesOut)

            // Encrypt second 8 bytes
            var block2 = Array(challenge[8..<16])
            var response2 = [UInt8](repeating: 0, count: 8)
            CCCryptorUpdate(cryptor, &block2, 8, &response2, 8, &bytesOut)
            response[8..<16] = response2[0..<8]

            CCCryptorRelease(cryptor)
        }
        #endif

        return response
    }

    /// Reverses the bits in a byte (VNC's non-standard DES key derivation).
    private static func reverseBits(_ byte: UInt8) -> UInt8 {
        var result: UInt8 = 0
        var b = byte
        for _ in 0..<8 {
            result = (result << 1) | (b & 1)
            b >>= 1
        }
        return result
    }
}
