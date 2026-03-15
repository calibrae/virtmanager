import Foundation

public struct SavedConnection: Codable, Identifiable, Sendable {
    public var id: UUID
    public var displayName: String
    public var uri: String
    public var authType: AuthType
    public var lastConnected: Date?

    public enum AuthType: String, Codable, Sendable, CaseIterable {
        case sshKey = "ssh_key"
        case password = "password"
        case sshAgent = "ssh_agent"
    }

    public init(
        id: UUID = UUID(),
        displayName: String,
        uri: String,
        authType: AuthType,
        lastConnected: Date? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.uri = uri
        self.authType = authType
        self.lastConnected = lastConnected
    }
}
