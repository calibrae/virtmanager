import Foundation
import CSpice

/// Manages GLib event processing on a dedicated background thread.
/// Uses blocking g_main_context_iteration for zero-latency event delivery.
final class GLibBridge: @unchecked Sendable {
    private var thread: Thread?
    private var _isRunning = false
    private let readySemaphore = DispatchSemaphore(value: 0)
    private(set) var context: OpaquePointer?

    init() {}
    deinit { stop() }

    func start() {
        guard !_isRunning else { return }
        _isRunning = true

        let bgThread = Thread { [weak self] in
            guard let self else { return }
            let ctx = g_main_context_default()!
            self.context = ctx
            guard g_main_context_acquire(ctx) != 0 else {
                self._isRunning = false
                self.readySemaphore.signal()
                return
            }
            self.readySemaphore.signal()

            // Blocking iteration — processes events immediately as they arrive
            // No sleep, no polling delay. GLib wakes the thread when events are ready.
            while self._isRunning {
                g_main_context_iteration(ctx, 1) // 1 = may_block = TRUE
            }
            g_main_context_release(ctx)
        }
        bgThread.name = "GLibBridge"
        bgThread.qualityOfService = .userInteractive // highest priority for display
        bgThread.start()
        self.thread = bgThread
        readySemaphore.wait()
        Thread.sleep(forTimeInterval: 0.02)
    }

    func stop() {
        _isRunning = false
        if let ctx = context { g_main_context_wakeup(ctx) }
        Thread.sleep(forTimeInterval: 0.1)
        context = nil
    }

    func schedule(_ block: @escaping () -> Void) {
        guard let ctx = context else { return }
        let boxed = Unmanaged.passRetained(BlockBox(block)).toOpaque()
        let source = g_idle_source_new()
        g_source_set_callback(source, { userData -> gboolean in
            guard let userData else { return 0 }
            Unmanaged<BlockBox>.fromOpaque(userData).takeRetainedValue().block()
            return 0
        }, boxed, nil)
        g_source_attach(source, ctx)
        g_source_unref(source)
    }
}

private final class BlockBox {
    let block: () -> Void
    init(_ block: @escaping () -> Void) { self.block = block }
}
