import Foundation
@preconcurrency import FamilyControls
@preconcurrency import ManagedSettings

/// Write surface for applying a ShieldConfig. Abstracted so we can fake it in tests.
protocol ShieldApplying: Sendable {
    func apply(_ config: ShieldConfig)
}

/// Production implementation that writes directly to ManagedSettingsStore.
///
/// Spec §4.2 originally said "never call clearAllSettings()" to avoid a
/// visible shield-drop flash. On-device testing 2026-04-19 proved that
/// direct-overwrite does NOT reliably transition from .all(except: X) to
/// .all() or .none — Family Controls retains the stale except-set. The
/// working pattern from the pre-rewrite codebase was: nil every shield
/// property + clearAllSettings() + set target. Brief empty-shield window
/// is the lesser regression vs. cache staleness that leaves apps unshielded
/// after session expiry. Spec to be amended.
struct ManagedSettingsShieldApplier: ShieldApplying {
    private let store = ManagedSettingsStore()

    func apply(_ config: ShieldConfig) {
        DebugBreadcrumbs.record(.applierApply, note: "\(config)")
        switch config {
        case .none:
            flush()

        case .all:
            flush()
            store.shield.applicationCategories = .all()
            store.shield.webDomainCategories = .all()
            store.webContent.blockedByFilter = .all()

        case .allExcept(let selection):
            // Direct overwrite is safe here — we're only transitioning
            // between selection sets within a single "allExcept" regime,
            // or arriving fresh from the app-launch `.all` state.
            store.shield.applications = nil
            store.shield.applicationCategories = .all(except: selection.applicationTokens)
            store.shield.webDomains = nil
            store.shield.webDomainCategories = .all(except: selection.webDomainTokens)
        }
    }

    /// Nil every shield property + clearAllSettings() so the next write
    /// sees a clean cache. The brief empty-shield window is the tradeoff.
    private func flush() {
        store.shield.applications = nil
        store.shield.applicationCategories = nil
        store.shield.webDomains = nil
        store.shield.webDomainCategories = nil
        store.webContent.blockedByFilter = nil
        store.clearAllSettings()
    }
}
