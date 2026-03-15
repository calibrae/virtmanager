import Foundation
import CSpice

/// Manages a GLib main loop running on a dedicated background thread.
/// All GLib/SPICE operations must run on this thread.
final class GLibBridge: @unchecked Sendable {
    private var mainLoop: OpaquePointer? // GMainLoop*
    private var mainContext: OpaquePointer? // GMainContext*
    private var thread: Thread?
    private var _isRunning: Bool = false

    init() {}

    deinit {
        stop()
    }

    /// Starts the GLib main loop on a background thread.
    func start() {
        guard !_isRunning else { return }
        _isRunning = true

        mainContext = g_main_context_new()
        mainLoop = g_main_loop_new(mainContext, 0)

        let loop = mainLoop!
        let ctx = mainContext!

        let bgThread = Thread { [weak self] in
            g_main_context_push_thread_default(ctx)
            g_main_loop_run(loop)
            g_main_context_pop_thread_default(ctx)
            self?._isRunning = false
        }
        bgThread.name = "GLibMainLoop"
        bgThread.qualityOfService = .userInitiated
        bgThread.start()
        self.thread = bgThread
    }

    /// Stops the GLib main loop.
    func stop() {
        guard _isRunning, let loop = mainLoop else { return }
        schedule {
            g_main_loop_quit(loop)
        }
        // Wait briefly for the loop to exit
        Thread.sleep(forTimeInterval: 0.1)

        if let loop = mainLoop {
            g_main_loop_unref(loop)
            mainLoop = nil
        }
        if let ctx = mainContext {
            g_main_context_unref(ctx)
            mainContext = nil
        }
        _isRunning = false
    }

    /// Schedules a closure to run on the GLib main loop thread.
    func schedule(_ block: @escaping () -> Void) {
        guard let ctx = mainContext else { return }

        let boxed = Unmanaged.passRetained(BlockBox(block)).toOpaque()

        let source = g_idle_source_new()
        g_source_set_callback(source, { userData -> gboolean in
            guard let userData else { return 0 }
            let box = Unmanaged<BlockBox>.fromOpaque(userData).takeRetainedValue()
            box.block()
            return 0 // G_SOURCE_REMOVE
        }, boxed, nil)
        g_source_attach(source, ctx)
        g_source_unref(source)
    }

    /// Returns the main context for attaching sources.
    var context: OpaquePointer? {
        return mainContext
    }
}

/// Box for passing Swift closures through C callbacks.
private final class BlockBox {
    let block: () -> Void
    init(_ block: @escaping () -> Void) {
        self.block = block
    }
}
