import Foundation

/// Overload that accepts a TimeInterval, so `sleep(0.5)` compiles in test code.
/// Uses @_disfavoredOverload so that integer literals still resolve to Darwin.sleep.
@_disfavoredOverload
func sleep(_ interval: TimeInterval) {
    Thread.sleep(forTimeInterval: interval)
}
