import Foundation
@testable import Intentions

/// In-memory equivalent of IntentLogStore for tests. Thread-safe.
final class InMemoryIntentLogStore: IntentLogStoring, @unchecked Sendable {
    private var log: IntentLog = .empty
    private let lock = NSLock()

    func load() -> IntentLog {
        lock.lock(); defer { lock.unlock() }
        return log
    }

    func save(_ newLog: IntentLog) {
        lock.lock(); defer { lock.unlock() }
        log = newLog
    }
}
