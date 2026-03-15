import Foundation

public protocol VirtManagerError: LocalizedError {
    var recoverySuggestion: String? { get }
}

public enum ConnectionError: Error, VirtManagerError {
    case connectionFailed(host: String, reason: String)
    case authenticationFailed(host: String)
    case timeout(host: String)
    case hostKeyVerificationFailed(host: String)
    case disconnected(reason: String)

    public var errorDescription: String? {
        switch self {
        case .connectionFailed(let host, let reason):
            "Failed to connect to \(host): \(reason)"
        case .authenticationFailed(let host):
            "Authentication failed for \(host)"
        case .timeout(let host):
            "Connection to \(host) timed out"
        case .hostKeyVerificationFailed(let host):
            "SSH host key verification failed for \(host)"
        case .disconnected(let reason):
            "Disconnected: \(reason)"
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .connectionFailed:
            "Check the hostname and ensure the libvirt daemon is running."
        case .authenticationFailed:
            "Verify your credentials and SSH key configuration."
        case .timeout:
            "Check network connectivity and firewall settings."
        case .hostKeyVerificationFailed:
            "Verify the host key fingerprint or remove the old key."
        case .disconnected:
            "Check network connectivity and try reconnecting."
        }
    }
}

public enum LibvirtError: Error, VirtManagerError {
    case notConnected
    case domainNotFound(name: String)
    case operationFailed(operation: String, reason: String)
    case xmlParsingFailed(reason: String)

    public var errorDescription: String? {
        switch self {
        case .notConnected:
            "Not connected to hypervisor"
        case .domainNotFound(let name):
            "VM '\(name)' not found"
        case .operationFailed(let op, let reason):
            "\(op) failed: \(reason)"
        case .xmlParsingFailed(let reason):
            "Failed to parse VM configuration: \(reason)"
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .notConnected:
            "Connect to a hypervisor first."
        case .domainNotFound:
            "Refresh the VM list."
        case .operationFailed:
            "Try the operation again."
        case .xmlParsingFailed:
            "The VM configuration may be corrupted."
        }
    }
}
