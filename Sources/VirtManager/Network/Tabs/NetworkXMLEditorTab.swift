import SwiftUI
import AppKit
import LibvirtSwift

/// Raw XML editor tab for network configuration. Reuses the XMLTextEditor from the VM config editor.
public struct NetworkXMLEditorTab: View {
    @Binding var xmlText: String

    public init(xmlText: Binding<String>) {
        self._xmlText = xmlText
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Raw XML")
                    .font(.headline)
                Spacer()
                Text("\(xmlText.components(separatedBy: "\n").count) lines")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()

            XMLTextEditor(text: $xmlText)
        }
    }
}
