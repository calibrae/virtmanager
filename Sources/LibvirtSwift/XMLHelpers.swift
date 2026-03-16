import Foundation

/// Helpers for parsing libvirt domain XML.
public enum XMLHelpers {

    /// Extracts the graphics type (vnc or spice) from domain XML.
    public static func extractGraphicsType(from xml: String) -> String? {
        let pattern = #"<graphics\s+type=.(\w+)."#
        return firstMatch(pattern: pattern, in: xml)
    }

    /// Checks if the domain XML contains a serial console.
    public static func hasSerialConsole(in xml: String) -> Bool {
        xml.contains("<serial type=") || xml.contains("<console type=")
    }

    /// Extracts the VNC port from domain XML.
    public static func extractVNCPort(from xml: String) -> Int? {
        let pattern = #"<graphics\s+type=.vnc.\s[^>]*port=.(\d+)."#
        return firstMatch(pattern: pattern, in: xml).flatMap { Int($0) }
    }

    /// Extracts the VNC listen address from domain XML.
    public static func extractVNCListenAddress(from xml: String) -> String? {
        let pattern = #"<graphics\s+type=.vnc.\s[^>]*listen=.([^"']+)."#
        return firstMatch(pattern: pattern, in: xml)
    }

    /// Extracts the SPICE port from domain XML.
    public static func extractSPICEPort(from xml: String) -> Int? {
        let pattern = #"<graphics\s+type=.spice.\s[^>]*port=.(\d+)."#
        return firstMatch(pattern: pattern, in: xml).flatMap { Int($0) }
    }

    /// Escapes a string for safe interpolation into XML attribute values and text content.
    public static func escapeXML(_ str: String) -> String {
        str.replacingOccurrences(of: "&", with: "&amp;")
           .replacingOccurrences(of: "<", with: "&lt;")
           .replacingOccurrences(of: ">", with: "&gt;")
           .replacingOccurrences(of: "\"", with: "&quot;")
           .replacingOccurrences(of: "'", with: "&apos;")
    }

    // MARK: - Private

    private static func firstMatch(pattern: String, in string: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .dotMatchesLineSeparators),
              let match = regex.firstMatch(in: string, range: NSRange(string.startIndex..., in: string)),
              let range = Range(match.range(at: 1), in: string)
        else {
            return nil
        }
        return String(string[range])
    }
}
