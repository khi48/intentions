import Foundation
@preconcurrency import FamilyControls
@preconcurrency import ManagedSettings

/// Write surface for applying a ShieldConfig. Abstracted so we can fake it in tests.
protocol ShieldApplying: Sendable {
    func apply(_ config: ShieldConfig, knownApps: Set<ApplicationToken>, knownDomains: Set<WebDomainToken>)
}

/// Production implementation that writes directly to ManagedSettingsStore.
///
/// Spec §4.2 originally said "never call clearAllSettings()" to avoid a
/// visible shield-drop flash. On-device testing 2026-04-19 found that
/// direct-overwrite did not reliably transition from .all(except: X) to
/// .all() or .none in the patterns we tested — Family Controls held the
/// stale except-set. Switching to nil-every-property + clearAllSettings()
/// + set-target restored reliable transitions in those scenarios. There
/// may be other patterns that avoid the flash AND transition cleanly;
/// haven't found one yet.
struct ManagedSettingsShieldApplier: ShieldApplying {
    private let store = ManagedSettingsStore()

    func apply(_ config: ShieldConfig, knownApps: Set<ApplicationToken>, knownDomains: Set<WebDomainToken>) {
        DebugBreadcrumbs.record(.mainAppApplied, note: "\(config) known=\(knownApps.count)a/\(knownDomains.count)d")
        switch config {
        case .none:
            flush()

        case .all:
            // Direct overwrites — matches pre-rewrite blockAllApps that worked
            // through iOS 26.5 testing. clearAllSettings() detaches the
            // ShieldConfiguration extension binding for a brief window which
            // can leave apps unshielded after the transition. Explicit per-key
            // writes are atomic from the system's perspective.
            store.shield.applications = knownApps.isEmpty ? nil : knownApps
            store.shield.applicationCategories = .all()
            store.shield.webDomains = knownDomains.isEmpty ? nil : knownDomains
            store.shield.webDomainCategories = nil
            store.webContent.blockedByFilter = .all()

        case .allExcept(let selection):
            // Shield categories except session's picks; shield every known
            // app token except session's picks so the gap-plugging doesn't
            // re-shield the user's currently-unlocked apps.
            let shieldApps = knownApps.subtracting(selection.applicationTokens)
            let shieldDomains = knownDomains.subtracting(selection.webDomainTokens)
            store.shield.applications = shieldApps.isEmpty ? nil : shieldApps
            store.shield.applicationCategories = .all(except: selection.applicationTokens)
            store.shield.webDomains = shieldDomains.isEmpty ? nil : shieldDomains
            store.shield.webDomainCategories = nil
            store.webContent.blockedByFilter = .all()
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

/// Additive applier used by the DAM extension. Same semantics as
/// `ManagedSettingsShieldApplier` EXCEPT no `clearAllSettings()` / nil-flush.
///
/// Background: this codebase's on-device testing on iOS 26 has not found a
/// reliable extension-process pattern that drops the shield (the obvious
/// nil-everything + `clearAllSettings()` from the extension updates the
/// store but has not been observed re-rendering the springboard cache).
/// Additive policy writes (`.all()`, `.all(except:)`) render fine from the
/// extension. So the current strategy is: extension writes target-state
/// additively, main app separately runs a full flush via
/// `ManagedSettingsShieldApplier` woken by DarwinWake / BGTask / scenePhase.
///
/// Other Family Controls apps (Opal, Jomo, etc.) reportedly do unshield
/// from the extension — there is presumably a pattern that works that we
/// haven't found yet. Worth revisiting before assuming the main-app
/// hand-off is permanent.
struct AdditiveShieldApplier: ShieldApplying {
    private let store = ManagedSettingsStore()

    func apply(_ config: ShieldConfig, knownApps: Set<ApplicationToken>, knownDomains: Set<WebDomainToken>) {
        DebugBreadcrumbs.record(.extensionApplied, note: "additive \(config) known=\(knownApps.count)a/\(knownDomains.count)d")
        switch config {
        case .none:
            // Additive "no shield" = explicit nil. No clearAllSettings.
            store.shield.applications = nil
            store.shield.applicationCategories = nil
            store.shield.webDomains = nil
            store.shield.webDomainCategories = nil
            store.webContent.blockedByFilter = nil

        case .all:
            store.shield.applications = knownApps.isEmpty ? nil : knownApps
            store.shield.applicationCategories = .all()
            store.shield.webDomains = knownDomains.isEmpty ? nil : knownDomains
            store.shield.webDomainCategories = nil
            store.webContent.blockedByFilter = .all()

        case .allExcept(let selection):
            let shieldApps = knownApps.subtracting(selection.applicationTokens)
            let shieldDomains = knownDomains.subtracting(selection.webDomainTokens)
            store.shield.applications = shieldApps.isEmpty ? nil : shieldApps
            store.shield.applicationCategories = .all(except: selection.applicationTokens)
            store.shield.webDomains = shieldDomains.isEmpty ? nil : shieldDomains
            store.shield.webDomainCategories = nil
            store.webContent.blockedByFilter = .all()
        }
    }
}
