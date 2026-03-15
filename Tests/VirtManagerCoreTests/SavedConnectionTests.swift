import Foundation
import Testing
@testable import VirtManagerCore

@Suite("SavedConnection Tests")
struct SavedConnectionTests {

    @Test("Codable round-trip preserves all fields")
    func codableRoundTrip() throws {
        let original = SavedConnection(
            displayName: "Test Server",
            uri: "qemu+ssh://user@host/system",
            authType: .sshKey,
            lastConnected: Date(timeIntervalSince1970: 1_700_000_000)
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SavedConnection.self, from: data)

        #expect(decoded.id == original.id)
        #expect(decoded.displayName == original.displayName)
        #expect(decoded.uri == original.uri)
        #expect(decoded.authType == original.authType)
        #expect(decoded.lastConnected == original.lastConnected)
    }

    @Test("Codable round-trip with nil lastConnected")
    func codableRoundTripNilDate() throws {
        let original = SavedConnection(
            displayName: "Local",
            uri: "qemu:///system",
            authType: .password,
            lastConnected: nil
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SavedConnection.self, from: data)

        #expect(decoded.lastConnected == nil)
        #expect(decoded.authType == .password)
    }

    @Test("All AuthType cases encode correctly")
    func authTypeCoding() throws {
        for authType in SavedConnection.AuthType.allCases {
            let conn = SavedConnection(
                displayName: "Test",
                uri: "test://",
                authType: authType
            )
            let data = try JSONEncoder().encode(conn)
            let decoded = try JSONDecoder().decode(SavedConnection.self, from: data)
            #expect(decoded.authType == authType)
        }
    }

    @Test("Encoding array of connections")
    func arrayEncoding() throws {
        let connections = [
            SavedConnection(displayName: "Server 1", uri: "qemu+ssh://a@b/system", authType: .sshKey),
            SavedConnection(displayName: "Server 2", uri: "qemu+ssh://c@d/system", authType: .sshAgent),
        ]

        let data = try JSONEncoder().encode(connections)
        let decoded = try JSONDecoder().decode([SavedConnection].self, from: data)

        #expect(decoded.count == 2)
        #expect(decoded[0].displayName == "Server 1")
        #expect(decoded[1].displayName == "Server 2")
    }
}
