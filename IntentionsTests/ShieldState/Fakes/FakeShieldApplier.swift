import Foundation
@testable import Intentions

/// Records every apply() call for test assertions.
final class FakeShieldApplier: ShieldApplying, @unchecked Sendable {
    private(set) var calls: [ShieldConfig] = []
    private let lock = NSLock()

    func apply(_ config: ShieldConfig) {
        lock.lock(); defer { lock.unlock() }
        calls.append(config)
    }
}
