import Foundation

@MainActor
public final class ConnectionStore {
    private let key = "com.virtmanager.savedConnections"

    public init() {}

    public func load() -> [SavedConnection] {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([SavedConnection].self, from: data)) ?? []
    }

    public func save(_ connections: [SavedConnection]) {
        let data = try? JSONEncoder().encode(connections)
        UserDefaults.standard.set(data, forKey: key)
    }
}
