import Foundation

/// Helpers for parsing libvirt domain XML.
/// Uses simple string matching to avoid XMLDocument dependency issues.
public enum XMLHelpers {

    /// Extracts the graphics type (vnc or spice) from domain XML.
    public static func extractGraphicsType(from xml: String) -> String? {
        // Look for <graphics type="vnc" ...> or <graphics type="spice" ...>
        let pattern = #"<graphics\s+type=["\'](\w+)["\']"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: xml, range: NSRange(xml.startIndex..., in: xml)),
              let range = Range(match.range(at: 1), in: xml)
        else {
            return nil
        }
        return String(xml[range])
    }

    /// Checks if the domain XML contains a serial console.
    public static func hasSerialConsole(in xml: String) -> Bool {
        xml.contains("<serial type=") || xml.contains("<console type=")
    }

    /// Extracts the VNC port from domain XML, if available.
    public static func extractVNCPort(from xml: String) -> Int? {
        let pattern = #"<graphics\s+type=["\']vnc["\'].*?port=["\'](\d+)["\']"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .dotMatchesLineSeparators),
              let match = regex.firstMatch(in: xml, range: NSRange(xml.startIndex..., in: xml)),
              let range = Range(match.range(at: 1), in: xml)
        else {
            return nil
        }
        return Int(xml[range])
    }

    /// Extracts the VNC listen address from domain XML, if available.
    public static func extractVNCListenAddress(from xml: String) -> String? {
        let pattern = #"<graphics\s+type=["\']vnc["\'].*?listen=["\']([^"\']+)["\']"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .dotMatchesLineSeparators),
              let match = regex.firstMatch(in: xml, range: NSRange(xml.startIndex..., in: xml)),
              let range = Range(match.range(at: 1), in: xml)
        else {
            return nil
        }
        return String(xml[range])
    }

    /// Extracts the SPICE port from domain XML, if available.
    public static func extractSPICEPort(from xml: String) -> Int? {
        let pattern = #"<graphics\s+type=["\']spice["\'].*?port=["\'](\d+)["\']"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .dotMatchesLineSeparators),
              let match = regex.firstMatch(in: xml, range: NSRange(xml.startIndex..., in: xml)),
              let range = Range(match.range(at: 1), in: xml)
        else {
            return nil
        }
        return Int(xml[range])
    }
}
