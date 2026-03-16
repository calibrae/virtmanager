import Foundation
import CSpice

/// Information about a USB device available for redirection.
public struct USBDeviceInfo: Identifiable, @unchecked Sendable {
    public let id: String
    public let description: String
    public let isConnected: Bool
    /// Opaque pointer to the SpiceUsbDevice (boxed copy, must be freed via cspice_usb_device_free)
    let devicePtr: UnsafeMutableRawPointer

    init(id: String, description: String, isConnected: Bool, devicePtr: UnsafeMutableRawPointer) {
        self.id = id
        self.description = description
        self.isConnected = isConnected
        self.devicePtr = devicePtr
    }
}

/// Manages USB device redirection over a SPICE session.
/// All GLib interactions happen on the GLib thread via `glibBridge.schedule`.
public final class SpiceUSBManager: @unchecked Sendable {
    private var manager: UnsafeMutableRawPointer? // SpiceUsbDeviceManager* as gpointer
    private let glibBridge: GLibBridge

    // Callbacks (called on main thread)
    public var onDeviceAdded: ((USBDeviceInfo) -> Void)?
    public var onDeviceRemoved: ((USBDeviceInfo) -> Void)?
    public var onDeviceListChanged: (() -> Void)?
    public var onError: ((String) -> Void)?

    init(session: UnsafeMutablePointer<SpiceSession>, glibBridge: GLibBridge) {
        self.glibBridge = glibBridge

        glibBridge.schedule { [weak self] in
            guard let self else { return }

            guard let mgr = cspice_usb_device_manager_get(session) else {
                let handler = self.onError
                DispatchQueue.main.async { handler?("Failed to get USB device manager") }
                return
            }
            self.manager = mgr

            let selfPtr = Unmanaged.passUnretained(self).toOpaque()

            cspice_signal_connect(mgr, "device-added",
                unsafeBitCast(usbDeviceAdded as @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> Void, to: GCallback.self), selfPtr)

            cspice_signal_connect(mgr, "device-removed",
                unsafeBitCast(usbDeviceRemoved as @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> Void, to: GCallback.self), selfPtr)

            cspice_signal_connect(mgr, "auto-connect-failed",
                unsafeBitCast(usbAutoConnectFailed as @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> Void, to: GCallback.self), selfPtr)

            cspice_signal_connect(mgr, "device-error",
                unsafeBitCast(usbDeviceError as @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> Void, to: GCallback.self), selfPtr)
        }
    }

    /// Returns all USB devices visible to the SPICE session.
    public func listDevices(completion: @Sendable @escaping ([USBDeviceInfo]) -> Void) {
        glibBridge.schedule { [weak self] in
            guard let self, let mgr = self.manager else {
                DispatchQueue.main.async { completion([]) }
                return
            }

            guard let array = cspice_usb_device_manager_get_devices(mgr) else {
                DispatchQueue.main.async { completion([]) }
                return
            }

            var devices: [USBDeviceInfo] = []
            let count = array.pointee.len
            for i in 0..<count {
                guard let deviceRaw = cspice_g_ptr_array_index(array, i) else { continue }

                let descC = cspice_usb_device_get_description(deviceRaw)
                let desc = descC.map { String(cString: $0) } ?? "Unknown USB Device"
                if let descC { g_free(gpointer(mutating: descC)) }

                let connected = cspice_usb_device_manager_is_connected(mgr, deviceRaw) != 0

                // Make a boxed copy so the pointer survives after the array is freed
                guard let copy = cspice_usb_device_copy(deviceRaw) else { continue }

                let info = USBDeviceInfo(
                    id: "\(i)",
                    description: desc,
                    isConnected: connected,
                    devicePtr: copy
                )
                devices.append(info)
            }

            g_ptr_array_unref(array)
            DispatchQueue.main.async { completion(devices) }
        }
    }

    /// Check if a device can be redirected to the VM.
    public func canRedirect(device: USBDeviceInfo, completion: @Sendable @escaping (Bool) -> Void) {
        glibBridge.schedule { [weak self] in
            guard let self, let mgr = self.manager else {
                DispatchQueue.main.async { completion(false) }
                return
            }
            let result = cspice_usb_device_manager_can_redirect(mgr, device.devicePtr) != 0
            DispatchQueue.main.async { completion(result) }
        }
    }

    /// Redirect a USB device to the VM.
    public func connectDevice(device: USBDeviceInfo, completion: @Sendable @escaping (Bool, String?) -> Void) {
        glibBridge.schedule { [weak self] in
            guard let self, let mgr = self.manager else {
                DispatchQueue.main.async { completion(false, "Manager not available") }
                return
            }

            let ctx = USBAsyncContext(completion: completion, manager: self)
            let ctxPtr = Unmanaged.passRetained(ctx).toOpaque()

            cspice_usb_device_manager_connect_device_async(
                mgr, device.devicePtr, nil,
                unsafeBitCast(usbConnectFinished as @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> Void, to: GAsyncReadyCallback.self),
                ctxPtr
            )
        }
    }

    /// Stop redirecting a USB device.
    public func disconnectDevice(device: USBDeviceInfo, completion: @Sendable @escaping (Bool, String?) -> Void) {
        glibBridge.schedule { [weak self] in
            guard let self, let mgr = self.manager else {
                DispatchQueue.main.async { completion(false, "Manager not available") }
                return
            }

            let ctx = USBAsyncContext(completion: completion, manager: self)
            let ctxPtr = Unmanaged.passRetained(ctx).toOpaque()

            cspice_usb_device_manager_disconnect_device_async(
                mgr, device.devicePtr, nil,
                unsafeBitCast(usbDisconnectFinished as @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> Void, to: GAsyncReadyCallback.self),
                ctxPtr
            )
        }
    }

    /// Check if a device is currently redirected.
    public func isDeviceConnected(device: USBDeviceInfo, completion: @Sendable @escaping (Bool) -> Void) {
        glibBridge.schedule { [weak self] in
            guard let self, let mgr = self.manager else {
                DispatchQueue.main.async { completion(false) }
                return
            }
            let result = cspice_usb_device_manager_is_connected(mgr, device.devicePtr) != 0
            DispatchQueue.main.async { completion(result) }
        }
    }

    // MARK: - Shared CD (Virtual USB CD-ROM)

    /// Creates a virtual USB CD-ROM device from a local ISO/IMG file and shares it with the VM.
    /// The file appears as a USB CD drive inside the guest.
    public func shareCD(filePath: String, completion: @Sendable @escaping (Bool, String?) -> Void) {
        glibBridge.schedule { [weak self] in
            guard let self, let mgr = self.manager else {
                DispatchQueue.main.async { completion(false, "Manager not available") }
                return
            }
            let ok = cspice_usb_create_shared_cd(mgr, filePath)
            if ok != 0 {
                DispatchQueue.main.async { completion(true, nil) }
            } else {
                DispatchQueue.main.async { completion(false, "Failed to share CD from \(filePath)") }
            }
        }
    }

    /// Checks if a device is a shared CD.
    public func isSharedCD(device: USBDeviceInfo) -> Bool {
        guard let mgr = manager else { return false }
        return cspice_usb_is_shared_cd(mgr, device.devicePtr) != 0
    }

    // MARK: - Internal signal handlers

    fileprivate func handleDeviceAdded(_ deviceRaw: UnsafeMutableRawPointer) {
        let descC = cspice_usb_device_get_description(deviceRaw)
        let desc = descC.map { String(cString: $0) } ?? "Unknown USB Device"
        if let descC { g_free(gpointer(mutating: descC)) }

        guard let mgr = manager else { return }
        let connected = cspice_usb_device_manager_is_connected(mgr, deviceRaw) != 0

        guard let copy = cspice_usb_device_copy(deviceRaw) else { return }

        let info = USBDeviceInfo(
            id: desc,
            description: desc,
            isConnected: connected,
            devicePtr: copy
        )

        let addedHandler = onDeviceAdded
        let listHandler = onDeviceListChanged
        DispatchQueue.main.async {
            addedHandler?(info)
            listHandler?()
        }
    }

    fileprivate func handleDeviceRemoved(_ deviceRaw: UnsafeMutableRawPointer) {
        let descC = cspice_usb_device_get_description(deviceRaw)
        let desc = descC.map { String(cString: $0) } ?? "Unknown USB Device"
        if let descC { g_free(gpointer(mutating: descC)) }

        let info = USBDeviceInfo(
            id: desc,
            description: desc,
            isConnected: false,
            devicePtr: deviceRaw
        )

        let removedHandler = onDeviceRemoved
        let listHandler = onDeviceListChanged
        DispatchQueue.main.async {
            removedHandler?(info)
            listHandler?()
        }
    }

    fileprivate func handleError(_ errorRaw: UnsafeMutableRawPointer?) {
        var msg = "USB device error"
        if let errorRaw {
            let gerror = errorRaw.assumingMemoryBound(to: GError.self)
            if let message = gerror.pointee.message {
                msg = String(cString: message)
            }
        }
        let handler = onError
        DispatchQueue.main.async { handler?(msg) }
    }

    fileprivate func finishConnect(source: UnsafeMutableRawPointer, result: UnsafeMutableRawPointer, ctx: USBAsyncContext) {
        var error: UnsafeMutablePointer<GError>?
        let ok = cspice_usb_device_manager_connect_device_finish(source, OpaquePointer(result), &error)

        var errMsg: String?
        if ok == 0, let error {
            errMsg = String(cString: error.pointee.message)
            g_error_free(error)
        }
        let success = ok != 0
        let completion = ctx.completion
        let listHandler = onDeviceListChanged
        DispatchQueue.main.async {
            completion(success, errMsg)
            listHandler?()
        }
    }

    fileprivate func finishDisconnect(source: UnsafeMutableRawPointer, result: UnsafeMutableRawPointer, ctx: USBAsyncContext) {
        var error: UnsafeMutablePointer<GError>?
        let ok = cspice_usb_device_manager_disconnect_device_finish(source, OpaquePointer(result), &error)

        var errMsg: String?
        if ok == 0, let error {
            errMsg = String(cString: error.pointee.message)
            g_error_free(error)
        }
        let success = ok != 0
        let completion = ctx.completion
        let listHandler = onDeviceListChanged
        DispatchQueue.main.async {
            completion(success, errMsg)
            listHandler?()
        }
    }
}

// MARK: - Async callback context

private final class USBAsyncContext: @unchecked Sendable {
    let completion: @Sendable (Bool, String?) -> Void
    weak var manager: SpiceUSBManager?

    init(completion: @Sendable @escaping (Bool, String?) -> Void, manager: SpiceUSBManager) {
        self.completion = completion
        self.manager = manager
    }
}

// MARK: - Top-level C callbacks

private func usbDeviceAdded(
    _ managerRaw: UnsafeMutableRawPointer?,
    _ deviceRaw: UnsafeMutableRawPointer?,
    _ userData: UnsafeMutableRawPointer?
) {
    guard let userData, let deviceRaw else { return }
    Unmanaged<SpiceUSBManager>.fromOpaque(userData).takeUnretainedValue()
        .handleDeviceAdded(deviceRaw)
}

private func usbDeviceRemoved(
    _ managerRaw: UnsafeMutableRawPointer?,
    _ deviceRaw: UnsafeMutableRawPointer?,
    _ userData: UnsafeMutableRawPointer?
) {
    guard let userData, let deviceRaw else { return }
    Unmanaged<SpiceUSBManager>.fromOpaque(userData).takeUnretainedValue()
        .handleDeviceRemoved(deviceRaw)
}

private func usbAutoConnectFailed(
    _ managerRaw: UnsafeMutableRawPointer?,
    _ deviceRaw: UnsafeMutableRawPointer?,
    _ errorRaw: UnsafeMutableRawPointer?,
    _ userData: UnsafeMutableRawPointer?
) {
    guard let userData else { return }
    Unmanaged<SpiceUSBManager>.fromOpaque(userData).takeUnretainedValue()
        .handleError(errorRaw)
}

private func usbDeviceError(
    _ managerRaw: UnsafeMutableRawPointer?,
    _ deviceRaw: UnsafeMutableRawPointer?,
    _ errorRaw: UnsafeMutableRawPointer?,
    _ userData: UnsafeMutableRawPointer?
) {
    guard let userData else { return }
    Unmanaged<SpiceUSBManager>.fromOpaque(userData).takeUnretainedValue()
        .handleError(errorRaw)
}

private func usbConnectFinished(
    _ source: UnsafeMutableRawPointer?,
    _ result: UnsafeMutableRawPointer?,
    _ userData: UnsafeMutableRawPointer?
) {
    guard let userData, let source, let result else { return }
    let ctx = Unmanaged<USBAsyncContext>.fromOpaque(userData).takeRetainedValue()
    ctx.manager?.finishConnect(source: source, result: result, ctx: ctx)
}

private func usbDisconnectFinished(
    _ source: UnsafeMutableRawPointer?,
    _ result: UnsafeMutableRawPointer?,
    _ userData: UnsafeMutableRawPointer?
) {
    guard let userData, let source, let result else { return }
    let ctx = Unmanaged<USBAsyncContext>.fromOpaque(userData).takeRetainedValue()
    ctx.manager?.finishDisconnect(source: source, result: result, ctx: ctx)
}
