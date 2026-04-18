import Foundation
@preconcurrency import FamilyControls
@preconcurrency import ManagedSettings

/// Write surface for applying a ShieldConfig. Abstracted so we can fake it in tests.
protocol ShieldApplying: Sendable {
    func apply(_ config: ShieldConfig)
}

/// Production implementation that writes directly to ManagedSettingsStore.
///
/// Never calls clearAllSettings() — the empty state between clear and re-apply
/// is a real state that produces a visible shield-drop flash.
struct ManagedSettingsShieldApplier: ShieldApplying {
    private let store = ManagedSettingsStore()

    func apply(_ config: ShieldConfig) {
        switch config {
        case .none:
            store.shield.applications = nil
            store.shield.applicationCategories = nil
            store.shield.webDomains = nil
            store.shield.webDomainCategories = nil

        case .all:
            store.shield.applications = nil
            store.shield.applicationCategories = .all()
            store.shield.webDomains = nil
            store.shield.webDomainCategories = .all()

        case .allExcept(let selection):
            store.shield.applications = nil
            store.shield.applicationCategories = .all(except: selection.applicationTokens)
            store.shield.webDomains = nil
            store.shield.webDomainCategories = .all(except: selection.webDomainTokens)
        }
    }
}
