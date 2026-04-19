import Foundation
@preconcurrency import FamilyControls
@preconcurrency import ManagedSettings
@testable import Intentions

/// Records every apply() call for test assertions.
final class FakeShieldApplier: ShieldApplying, @unchecked Sendable {
    private(set) var calls: [ShieldConfig] = []
    private(set) var lastKnownApps: Set<ApplicationToken> = []
    private(set) var lastKnownDomains: Set<WebDomainToken> = []
    private let lock = NSLock()

    func apply(_ config: ShieldConfig, knownApps: Set<ApplicationToken>, knownDomains: Set<WebDomainToken>) {
        lock.lock(); defer { lock.unlock() }
        calls.append(config)
        lastKnownApps = knownApps
        lastKnownDomains = knownDomains
    }

    func reset() {
        lock.lock(); defer { lock.unlock() }
        calls.removeAll(keepingCapacity: false)
    }
}
