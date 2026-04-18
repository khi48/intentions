import Foundation

protocol IntentLogStoring: Sendable {
    func load() -> IntentLog
    func save(_ log: IntentLog)
}

/// Reads and writes the IntentLog to an App Group UserDefaults suite.
/// Uses a fresh UserDefaults instance per call to avoid stale per-process caches
/// that bite cross-process readers (main app vs. DAM extension).
struct IntentLogStore: IntentLogStoring, Sendable {
    static let storageKey = "shieldstate.intentlog.v1"

    /// Literal App Group id. Kept local so this file compiles as a standalone
    /// member of the DAM extension target without depending on SharedConstants.
    static let defaultSuiteName = "group.oh.Intent"

    private let suiteName: String

    init(suiteName: String = Self.defaultSuiteName) {
        self.suiteName = suiteName
    }

    func load() -> IntentLog {
        guard let defaults = UserDefaults(suiteName: suiteName),
              let data = defaults.data(forKey: Self.storageKey)
        else { return .empty }

        do {
            return try JSONDecoder().decode(IntentLog.self, from: data)
        } catch {
            return .empty
        }
    }

    func save(_ log: IntentLog) {
        guard let defaults = UserDefaults(suiteName: suiteName) else { return }
        let data = (try? JSONEncoder().encode(log)) ?? Data()
        defaults.set(data, forKey: Self.storageKey)
    }
}
