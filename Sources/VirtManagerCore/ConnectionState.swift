public enum ConnectionState: Sendable, Equatable {
    case disconnected
    case connecting
    case connected
    case disconnecting
    case error(String)
}
