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
/// visible shield-drop flash. On-device testing 2026-04-19 proved that
/// direct-overwrite does NOT reliably transition from .all(except: X) to
/// .all() or .none — Family Controls retains the stale except-set. The
/// working pattern from the pre-rewrite codebase was: nil every shield
/// property + clearAllSettings() + set target. Brief empty-shield window
/// is the lesser regression vs. cache staleness that leaves apps unshielded
/// after session expiry. Spec to be amended.
struct ManagedSettingsShieldApplier: ShieldApplying {
    private let store = ManagedSettingsStore()

    func apply(_ config: ShieldConfig, knownApps: Set<ApplicationToken>, knownDomains: Set<WebDomainToken>) {
        DebugBreadcrumbs.record(.applierApply, note: "\(config) known=\(knownApps.count)a/\(knownDomains.count)d")
        switch config {
        case .none:
            flush()

        case .all:
            flush()
            store.shield.applicationCategories = .all()
            store.shield.webDomainCategories = .all()
            store.webContent.blockedByFilter = .all()
            // Belt-and-suspenders: category-policy .all() does NOT reliably
            // shield every app (iOS 26 Family Controls gap; notably browsers
            // and previously-session-unlocked apps slip through). Explicit
            // token list plugs the gap.
            if !knownApps.isEmpty { store.shield.applications = knownApps }
            if !knownDomains.isEmpty { store.shield.webDomains = knownDomains }

        case .allExcept(let selection):
            // Shield categories except session's picks; shield every known
            // app token except session's picks so the gap-plugging doesn't
            // re-shield the user's currently-unlocked apps.
            store.shield.applicationCategories = .all(except: selection.applicationTokens)
            store.shield.webDomainCategories = .all(except: selection.webDomainTokens)
            let shieldApps = knownApps.subtracting(selection.applicationTokens)
            let shieldDomains = knownDomains.subtracting(selection.webDomainTokens)
            store.shield.applications = shieldApps.isEmpty ? nil : shieldApps
            store.shield.webDomains = shieldDomains.isEmpty ? nil : shieldDomains
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
/// Rationale: on iOS 26 Apple DTS 807934 documents that extension-process
/// `clearAllSettings()` writes are dropped from the springboard shield
/// layer cache — the store is updated but the shield UI doesn't re-render
/// until a main-app-process write propagates. Additive policy writes
/// (.all(), .all(except:)) DO render reliably from the extension process
/// per the patterns used by Opal / Jomo / habitdoom. So: extension writes
/// target-state additively, main app separately runs a full flush via
/// `ManagedSettingsShieldApplier` via DarwinWake / BGTask / scenePhase.
struct AdditiveShieldApplier: ShieldApplying {
    private let store = ManagedSettingsStore()

    func apply(_ config: ShieldConfig, knownApps: Set<ApplicationToken>, knownDomains: Set<WebDomainToken>) {
        DebugBreadcrumbs.record(.applierApply, note: "additive \(config) known=\(knownApps.count)a/\(knownDomains.count)d")
        switch config {
        case .none:
            // Additive "no shield" = explicit nil. No clearAllSettings.
            store.shield.applications = nil
            store.shield.applicationCategories = nil
            store.shield.webDomains = nil
            store.shield.webDomainCategories = nil
            store.webContent.blockedByFilter = nil

        case .all:
            store.shield.applicationCategories = .all()
            store.shield.webDomainCategories = .all()
            store.webContent.blockedByFilter = .all()
            if !knownApps.isEmpty { store.shield.applications = knownApps }
            if !knownDomains.isEmpty { store.shield.webDomains = knownDomains }

        case .allExcept(let selection):
            store.shield.applicationCategories = .all(except: selection.applicationTokens)
            store.shield.webDomainCategories = .all(except: selection.webDomainTokens)
            store.webContent.blockedByFilter = .all()
            let shieldApps = knownApps.subtracting(selection.applicationTokens)
            let shieldDomains = knownDomains.subtracting(selection.webDomainTokens)
            store.shield.applications = shieldApps.isEmpty ? nil : shieldApps
            store.shield.webDomains = shieldDomains.isEmpty ? nil : shieldDomains
        }
    }
}
