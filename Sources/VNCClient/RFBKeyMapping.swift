import Foundation

/// Maps macOS virtual keycodes (from NSEvent.keyCode) to X11 keysyms
/// used by the RFB protocol.
public enum RFBKeyMapping {

    /// X11 keysym constants for common keys.
    public enum KeySym {
        // Function keys
        public static let backspace: UInt32 = 0xFF08
        public static let tab: UInt32 = 0xFF09
        public static let `return`: UInt32 = 0xFF0D
        public static let escape: UInt32 = 0xFF1B
        public static let insert: UInt32 = 0xFF63
        public static let delete: UInt32 = 0xFFFF
        public static let home: UInt32 = 0xFF50
        public static let end: UInt32 = 0xFF57
        public static let pageUp: UInt32 = 0xFF55
        public static let pageDown: UInt32 = 0xFF56
        public static let left: UInt32 = 0xFF51
        public static let up: UInt32 = 0xFF52
        public static let right: UInt32 = 0xFF53
        public static let down: UInt32 = 0xFF54

        // Modifiers
        public static let shiftLeft: UInt32 = 0xFFE1
        public static let shiftRight: UInt32 = 0xFFE2
        public static let controlLeft: UInt32 = 0xFFE3
        public static let controlRight: UInt32 = 0xFFE4
        public static let metaLeft: UInt32 = 0xFFE7   // Command key
        public static let metaRight: UInt32 = 0xFFE8
        public static let altLeft: UInt32 = 0xFFE9
        public static let altRight: UInt32 = 0xFFEA
        public static let capsLock: UInt32 = 0xFFE5

        // F-keys
        public static let f1: UInt32 = 0xFFBE
        public static let f2: UInt32 = 0xFFBF
        public static let f3: UInt32 = 0xFFC0
        public static let f4: UInt32 = 0xFFC1
        public static let f5: UInt32 = 0xFFC2
        public static let f6: UInt32 = 0xFFC3
        public static let f7: UInt32 = 0xFFC4
        public static let f8: UInt32 = 0xFFC5
        public static let f9: UInt32 = 0xFFC6
        public static let f10: UInt32 = 0xFFC7
        public static let f11: UInt32 = 0xFFC8
        public static let f12: UInt32 = 0xFFC9
    }

    /// Maps a macOS virtual keycode (NSEvent.keyCode) to an X11 keysym.
    /// Returns nil if no mapping is found (caller should try using the character instead).
    public static func keysymForKeyCode(_ keyCode: UInt16) -> UInt32? {
        return macKeyCodeToKeySym[keyCode]
    }

    /// Maps a Unicode character to an X11 keysym.
    /// For ASCII characters, the keysym is the same as the Unicode code point.
    /// For Latin-1 characters (0x00A0-0x00FF), the keysym is the same as the code point.
    public static func keysymForCharacter(_ character: Character) -> UInt32? {
        guard let scalar = character.unicodeScalars.first else { return nil }
        let code = scalar.value

        // ASCII range: keysym == code point
        if code >= 0x20 && code <= 0x7E {
            return code
        }
        // Latin-1 supplement
        if code >= 0x00A0 && code <= 0x00FF {
            return code
        }
        return nil
    }

    // MARK: - macOS keyCode -> X11 keysym mapping

    /// Mapping from macOS virtual keycodes to X11 keysyms for non-character keys.
    private static let macKeyCodeToKeySym: [UInt16: UInt32] = [
        // Arrow keys
        123: KeySym.left,
        124: KeySym.right,
        125: KeySym.down,
        126: KeySym.up,

        // Navigation
        115: KeySym.home,
        119: KeySym.end,
        116: KeySym.pageUp,
        121: KeySym.pageDown,

        // Editing
        36: KeySym.return,
        48: KeySym.tab,
        51: KeySym.backspace,
        53: KeySym.escape,
        117: KeySym.delete,

        // Modifiers
        56: KeySym.shiftLeft,
        60: KeySym.shiftRight,
        59: KeySym.controlLeft,
        62: KeySym.controlRight,
        55: KeySym.metaLeft,     // Left Command
        54: KeySym.metaRight,    // Right Command
        58: KeySym.altLeft,      // Left Option
        61: KeySym.altRight,     // Right Option
        57: KeySym.capsLock,

        // F-keys
        122: KeySym.f1,
        120: KeySym.f2,
        99: KeySym.f3,
        118: KeySym.f4,
        96: KeySym.f5,
        97: KeySym.f6,
        98: KeySym.f7,
        100: KeySym.f8,
        101: KeySym.f9,
        109: KeySym.f10,
        103: KeySym.f11,
        111: KeySym.f12,
    ]
}
