import Foundation

public struct VideoDevice: Identifiable, Sendable {
    public var id = UUID()
    public var modelType: String  // "virtio", "qxl", "vga", "cirrus", "bochs"
    public var vram: Int?         // in KiB
    public var heads: Int?

    public init(
        modelType: String = "virtio",
        vram: Int? = nil,
        heads: Int? = nil
    ) {
        self.modelType = modelType
        self.vram = vram
        self.heads = heads
    }

    public init(from element: XMLElement) {
        let modelEl = element.elements(forName: "model").first
        self.modelType = modelEl?.attribute(forName: "type")?.stringValue ?? "virtio"
        if let vramStr = modelEl?.attribute(forName: "vram")?.stringValue {
            self.vram = Int(vramStr)
        }
        if let headsStr = modelEl?.attribute(forName: "heads")?.stringValue {
            self.heads = Int(headsStr)
        }
    }

    public func toXML() -> String {
        var modelAttrs = "type=\"\(XMLHelpers.escapeXML(modelType))\""
        if let vram = vram {
            modelAttrs += " vram=\"\(vram)\""
        }
        if let heads = heads {
            modelAttrs += " heads=\"\(heads)\""
        }
        return "<video>\n  <model \(modelAttrs)/>\n</video>"
    }
}
