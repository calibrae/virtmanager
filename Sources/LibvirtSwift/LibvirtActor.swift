import CLibvirt
import Foundation

private let libvirtInitialized: Bool = {
    virInitialize()
    return true
}()

/// Ensures libvirt is initialized before any calls.
func ensureLibvirtInitialized() {
    _ = libvirtInitialized
}
