import Foundation

/// Maps macOS virtual keycodes to PC AT set 1 scancodes used by SPICE.
///
/// PC AT set 1 scancodes are what SPICE expects for keyboard input.
/// Extended scancodes (0xE0 prefix) are encoded as 0x100 | scancode.
public enum SpiceKeyMapping {
    // MARK: - Scancode Constants

    // Standard keys
    public static let scEscape: UInt32        = 0x01
    public static let sc1: UInt32             = 0x02
    public static let sc2: UInt32             = 0x03
    public static let sc3: UInt32             = 0x04
    public static let sc4: UInt32             = 0x05
    public static let sc5: UInt32             = 0x06
    public static let sc6: UInt32             = 0x07
    public static let sc7: UInt32             = 0x08
    public static let sc8: UInt32             = 0x09
    public static let sc9: UInt32             = 0x0A
    public static let sc0: UInt32             = 0x0B
    public static let scMinus: UInt32         = 0x0C
    public static let scEqual: UInt32         = 0x0D
    public static let scBackspace: UInt32     = 0x0E
    public static let scTab: UInt32           = 0x0F
    public static let scQ: UInt32             = 0x10
    public static let scW: UInt32             = 0x11
    public static let scE: UInt32             = 0x12
    public static let scR: UInt32             = 0x13
    public static let scT: UInt32             = 0x14
    public static let scY: UInt32             = 0x15
    public static let scU: UInt32             = 0x16
    public static let scI: UInt32             = 0x17
    public static let scO: UInt32             = 0x18
    public static let scP: UInt32             = 0x19
    public static let scLeftBracket: UInt32   = 0x1A
    public static let scRightBracket: UInt32  = 0x1B
    public static let scReturn: UInt32        = 0x1C
    public static let scLeftControl: UInt32   = 0x1D
    public static let scA: UInt32             = 0x1E
    public static let scS: UInt32             = 0x1F
    public static let scD: UInt32             = 0x20
    public static let scF: UInt32             = 0x21
    public static let scG: UInt32             = 0x22
    public static let scH: UInt32             = 0x23
    public static let scJ: UInt32             = 0x24
    public static let scK: UInt32             = 0x25
    public static let scL: UInt32             = 0x26
    public static let scSemicolon: UInt32     = 0x27
    public static let scQuote: UInt32         = 0x28
    public static let scGrave: UInt32         = 0x29
    public static let scLeftShift: UInt32     = 0x2A
    public static let scBackslash: UInt32     = 0x2B
    public static let scZ: UInt32             = 0x2C
    public static let scX: UInt32             = 0x2D
    public static let scC: UInt32             = 0x2E
    public static let scV: UInt32             = 0x2F
    public static let scB: UInt32             = 0x30
    public static let scN: UInt32             = 0x31
    public static let scM: UInt32             = 0x32
    public static let scComma: UInt32         = 0x33
    public static let scPeriod: UInt32        = 0x34
    public static let scSlash: UInt32         = 0x35
    public static let scRightShift: UInt32    = 0x36
    public static let scKeypadMultiply: UInt32 = 0x37
    public static let scLeftAlt: UInt32       = 0x38
    public static let scSpace: UInt32         = 0x39
    public static let scCapsLock: UInt32      = 0x3A

    // Function keys
    public static let scF1: UInt32            = 0x3B
    public static let scF2: UInt32            = 0x3C
    public static let scF3: UInt32            = 0x3D
    public static let scF4: UInt32            = 0x3E
    public static let scF5: UInt32            = 0x3F
    public static let scF6: UInt32            = 0x40
    public static let scF7: UInt32            = 0x41
    public static let scF8: UInt32            = 0x42
    public static let scF9: UInt32            = 0x43
    public static let scF10: UInt32           = 0x44
    public static let scNumLock: UInt32       = 0x45
    public static let scScrollLock: UInt32    = 0x46
    public static let scF11: UInt32           = 0x57
    public static let scF12: UInt32           = 0x58

    // Keypad
    public static let scKeypad7: UInt32       = 0x47
    public static let scKeypad8: UInt32       = 0x48
    public static let scKeypad9: UInt32       = 0x49
    public static let scKeypadMinus: UInt32   = 0x4A
    public static let scKeypad4: UInt32       = 0x4B
    public static let scKeypad5: UInt32       = 0x4C
    public static let scKeypad6: UInt32       = 0x4D
    public static let scKeypadPlus: UInt32    = 0x4E
    public static let scKeypad1: UInt32       = 0x4F
    public static let scKeypad2: UInt32       = 0x50
    public static let scKeypad3: UInt32       = 0x51
    public static let scKeypad0: UInt32       = 0x52
    public static let scKeypadDecimal: UInt32 = 0x53

    // Extended keys (0xE0 prefix, encoded as 0x100 | code)
    public static let scKeypadEnter: UInt32   = 0x100 | 0x1C
    public static let scRightControl: UInt32  = 0x100 | 0x1D
    public static let scKeypadDivide: UInt32  = 0x100 | 0x35
    public static let scRightAlt: UInt32      = 0x100 | 0x38
    public static let scHome: UInt32          = 0x100 | 0x47
    public static let scUp: UInt32            = 0x100 | 0x48
    public static let scPageUp: UInt32        = 0x100 | 0x49
    public static let scLeft: UInt32          = 0x100 | 0x4B
    public static let scRight: UInt32         = 0x100 | 0x4D
    public static let scEnd: UInt32           = 0x100 | 0x4F
    public static let scDown: UInt32          = 0x100 | 0x50
    public static let scPageDown: UInt32      = 0x100 | 0x51
    public static let scInsert: UInt32        = 0x100 | 0x52
    public static let scDelete: UInt32        = 0x100 | 0x53
    public static let scLeftMeta: UInt32      = 0x100 | 0x5B
    public static let scRightMeta: UInt32     = 0x100 | 0x5C
    public static let scMenu: UInt32          = 0x100 | 0x5D

    // MARK: - macOS keyCode to scancode mapping

    /// Maps a macOS virtual keycode (NSEvent.keyCode) to a PC AT set 1 scancode.
    /// Returns nil if the keycode is not mapped.
    public static func scancodeForKeyCode(_ keyCode: UInt16) -> UInt32? {
        return macToScancode[keyCode]
    }

    /// macOS keycode -> PC AT set 1 scancode
    private static let macToScancode: [UInt16: UInt32] = [
        // Letters
        0x00: scA,
        0x01: scS,
        0x02: scD,
        0x03: scF,
        0x04: scH,
        0x05: scG,
        0x06: scZ,
        0x07: scX,
        0x08: scC,
        0x09: scV,
        0x0B: scB,
        0x0C: scQ,
        0x0D: scW,
        0x0E: scE,
        0x0F: scR,
        0x10: scY,
        0x11: scT,
        0x12: sc1,
        0x13: sc2,
        0x14: sc3,
        0x15: sc4,
        0x16: sc6,
        0x17: sc5,
        0x18: scEqual,
        0x19: sc9,
        0x1A: sc7,
        0x1B: scMinus,
        0x1C: sc8,
        0x1D: sc0,
        0x1E: scRightBracket,
        0x1F: scO,
        0x20: scU,
        0x21: scLeftBracket,
        0x22: scI,
        0x23: scP,
        0x24: scReturn,
        0x25: scL,
        0x26: scJ,
        0x27: scQuote,
        0x28: scK,
        0x29: scSemicolon,
        0x2A: scBackslash,
        0x2B: scComma,
        0x2C: scSlash,
        0x2D: scN,
        0x2E: scM,
        0x2F: scPeriod,
        0x30: scTab,
        0x31: scSpace,
        0x32: scGrave,
        0x33: scBackspace,
        0x35: scEscape,

        // Modifiers
        0x36: scRightMeta,     // Right Command
        0x37: scLeftMeta,      // Left Command
        0x38: scLeftShift,
        0x39: scCapsLock,
        0x3A: scLeftAlt,       // Left Option
        0x3B: scLeftControl,
        0x3C: scRightShift,
        0x3D: scRightAlt,      // Right Option
        0x3E: scRightControl,

        // Function keys
        0x7A: scF1,
        0x78: scF2,
        0x63: scF3,
        0x76: scF4,
        0x60: scF5,
        0x61: scF6,
        0x62: scF7,
        0x64: scF8,
        0x65: scF9,
        0x6D: scF10,
        0x67: scF11,
        0x6F: scF12,

        // Navigation
        0x73: scHome,
        0x77: scEnd,
        0x74: scPageUp,
        0x79: scPageDown,
        0x7B: scLeft,
        0x7C: scRight,
        0x7D: scDown,
        0x7E: scUp,
        0x75: scDelete,        // Forward delete

        // Keypad
        0x41: scKeypadDecimal,
        0x43: scKeypadMultiply,
        0x45: scKeypadPlus,
        0x47: scNumLock,       // Clear on Mac keyboard
        0x4B: scKeypadDivide,
        0x4C: scKeypadEnter,
        0x4E: scKeypadMinus,
        0x51: scKeypad0 + 0x100,  // Keypad equals - not standard, map to something
        0x52: scKeypad0,
        0x53: scKeypad1,
        0x54: scKeypad2,
        0x55: scKeypad3,
        0x56: scKeypad4,
        0x57: scKeypad5,
        0x58: scKeypad6,
        0x59: scKeypad7,
        0x5B: scKeypad8,
        0x5C: scKeypad9,
    ]
}
