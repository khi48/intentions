# Block / Unblock Framework — Design Spec

**Status:** draft — revised 2026-04-19 after on-device testing
**Author:** Kieran Hitchcock (with Claude)
**Date:** 2026-04-19
**Scope:** Shield-state model and mechanism for session-based app blocking. No UI, no onboarding, no picker internals — only the state engine and its write path.

## Revision Log

**2026-04-19 (post-impl):** On-device Case A test revealed two spec premises were wrong:

1. **§4.2 was wrong to forbid `clearAllSettings()`.** Direct-overwrite does not reliably transition Family Controls from `.all(except: X)` to `.all()` or `.none` on iOS 26; FC retains the stale except-set. The `apply()` primitive now flushes (nil every property + `clearAllSettings()`) for `.all` and `.none`; `.allExcept` stays as direct overwrite. The brief empty-shield window is the lesser regression.

2. **§4.1 overstated extension-write reliability.** Apple DTS 807934: extension-process `ManagedSettingsStore` writes do NOT re-render the springboard shield layer on iOS 26 — even for shield ADDITION, not only removal. The store is correct, but the springboard keeps its cached render until the MAIN APP process writes. Mechanism now: DAM writes best-effort, then submits a `BGAppRefreshTask` so the main app wakes and calls `reapplyCurrentState()` from its own process. Force-quit still falls back to foreground catch-up (BGTask is disabled post force-quit).

Sections below reflect the corrected design.

---

## 1. Overview

Intent blocks apps by default and grants temporary, time-bounded access via user-initiated **sessions**. The shield state must survive main-app backgrounding, termination, and force-quit — which means the OS-level `DeviceActivityMonitor` (DAM) extension owns all time-driven transitions. The main app owns user-driven transitions. Both processes share a persisted **intent log** in an App Group container; both use the same pure-function compute to derive the target `ManagedSettingsStore` config.

---

## 2. State Model

### 2.1 Default state

```swift
enum DefaultState: String, Codable, Sendable {
    case blocked   // all apps shielded
    case open      // nothing shielded ("break" mode)
}
```

Persistent. Changes only by explicit user action. Not affected by sessions.

### 2.2 Session

```swift
struct Session: Codable, Sendable {
    let id: UUID
    let apps: FamilyActivitySelection
    let startedAt: Date
    let endsAt: Date
}
```

At most one active at a time. Lives in the intent log until either (a) `now >= endsAt` (timer expiry), (b) user ends it early, or (c) user flips default state.

### 2.3 Intent log

```swift
struct IntentLog: Codable, Sendable {
    var defaultState: DefaultState
    var activeSession: Session?
}
```

Single source of truth. Stored in App Group `UserDefaults` under a single key, value encoded as JSON. Both main app and DAM extension read and write the same key. Writes are whole-object replacements — no partial mutation. Reads use a fresh `UserDefaults(suiteName:)` instance to avoid stale per-process caches.

---

## 3. Semantics

### 3.1 Session effect (invariant)

For the lifetime of an active session, shield config is **exactly**: picked apps accessible, everything else shielded. Independent of `defaultState`. The default only determines *what happens after*.

### 3.2 Transition table

| Event | Precondition | Effect on log | Post-log-write shield |
|-------|-------------|---------------|----------------------|
| Start session(`apps`, `duration`) | no active session | `activeSession = Session(…, endsAt: now+duration)` | apps-only |
| Start session(`apps`, `duration`) | active session exists | **replace** — overwrite `activeSession`, cancel existing DAM schedule | apps-only |
| End session early | active session | `activeSession = nil` | match `defaultState` |
| Timer expiry (DAM) | `activeSession.endsAt <= now` | `activeSession = nil` | match `defaultState` |
| Flip default (`blocked`↔`open`) | any | `defaultState = new` AND `activeSession = nil` (flip implicitly cancels) | match new `defaultState` |

### 3.3 Shield compute (pure)

```swift
enum ShieldConfig: Equatable {
    case none                              // nothing shielded
    case allExcept(FamilyActivitySelection) // everything except these
    case all                                // everything shielded
}

func compute(_ log: IntentLog, at t: Date) -> ShieldConfig {
    if let s = log.activeSession, t < s.endsAt {
        return .allExcept(s.apps)
    }
    switch log.defaultState {
    case .blocked: return .all
    case .open:    return .none
    }
}
```

Totally determined by log + time. Easy to unit-test.

---

## 4. Write Mechanism

### 4.1 Ownership

- **DAM extension:** time-driven transitions (session expiry). Sole writer when main app is dead or backgrounded past the wake window.
- **Main app:** user-driven transitions (start, end, flip). Sole writer during foreground interactions.

No overlap — each event type has exactly one responsible writer. No races.

### 4.2 `apply(_ config: ShieldConfig)` primitive

Shared code (in a module linked by both targets):

```swift
func apply(_ config: ShieldConfig) {
    let store = ManagedSettingsStore(named: .main)
    switch config {
    case .none:
        store.shield.applications = nil
        store.shield.applicationCategories = nil
        store.shield.webDomains = nil
        store.shield.webDomainCategories = nil

    case .all:
        store.shield.applicationCategories = .all()
        store.shield.webDomainCategories = .all()

    case .allExcept(let selection):
        // Shield everything except what the user picked.
        // ShieldSettings category policies accept an `except:` set of tokens.
        store.shield.applications = nil
        store.shield.applicationCategories = .all(except: selection.applicationTokens)
        store.shield.webDomains = nil
        store.shield.webDomainCategories = .all(except: selection.webDomainTokens)
    }
}
```

Direct property overwrite per property, transactional at the `ManagedSettings` level. **Never call `clearAllSettings()` before writing** — the empty state between clear and re-apply is a real state and produces a visible shield-drop flash. If `selection` contains category-level picks (not just individual app/domain tokens), translate them into the appropriate `except:` set — the selection API exposes both application and category tokens.

### 4.3 DAM scheduling

- On session start, main app schedules a `DeviceActivitySchedule` with `intervalEnd = session.endsAt`.
- DAM's `intervalDidEnd(for:)` callback:
  1. Re-read intent log (session may have been ended/replaced in the meantime).
  2. If `activeSession` still present and `endsAt <= now`, clear it and write log.
  3. Call `apply(compute(log, now))`.

### 4.4 User-driven writes (main app)

On each user action:
1. Cancel any pending DAM schedule.
2. Update intent log.
3. If starting a session, schedule DAM for new `endsAt`.
4. Call `apply(compute(log, now))`.

### 4.5 Foreground catch-up (main app safety net)

On `appDidBecomeActive`:

```swift
var log = IntentLog.load()
if let s = log.activeSession, s.endsAt <= Date() {
    log.activeSession = nil
    log.save()
    apply(compute(log, .now))
}
```

Covers: DAM silently failed to fire, app was reinstalled mid-session, clock skew, OS reboot, user toggled Screen Time permissions mid-session. Cheap. No background runtime required.

---

## 5. Accepted Trade-offs

1. **FC render lag under force-quit.** If the user has force-quit the main app, DAM's write to `ManagedSettingsStore` is the only write. Family Controls sometimes lags in re-rendering on-screen shields after extension-only writes. We accept up to several seconds of visible lag in this case. No iOS mechanism delivers guaranteed-instant relock under force-quit; `BGAppRefreshTask` is disabled post force-quit, silent push is disabled, and Darwin notifications need a running listener.

2. **No active recovery from DAM miss.** If DAM fails to fire at all (rare — extension crash, OS resource pressure), the shield stays in "session active" state until the user next foregrounds the main app. Foreground catch-up (§4.5) then repairs state.

3. **Session is not infinitely granular.** `DeviceActivitySchedule` has minute-level resolution. Sub-minute session durations are not supported by the mechanism.

---

## 6. Alternatives Considered

### 6.1 Approach A — Pure extension-writes (without catch-up)

Extension writes all transitions, including user-driven ones via Darwin-notification handoff. Main app only reads.

**Rejected because:** user-driven writes in main app are simpler, don't require cross-process IPC, and main app is guaranteed to be running when user takes an action. Adding a Darwin round-trip for foreground writes is complexity without benefit.

### 6.2 Approach B — Main-app-writes via BGTask handoff

DAM fires at expiry, schedules `BGAppRefreshTask`, posts Darwin notification. Main app wakes, reads intent log, applies shield.

**Rejected because:** `BGAppRefreshTask` is **disabled by iOS for force-quit apps** until user manually relaunches. Silent push and Darwin listeners also require a running main app. Under force-quit, main app never wakes and shield never updates. B's entire mechanism collapses in the one scenario we most need it to work.

### 6.3 Approach C — Hybrid (both processes write, dedupe via hash)

Extension writes best-effort at expiry. Main app, on any wake (foreground, BGTask, notification), re-reads log and re-applies idempotently, guarded by a `lastAppliedConfigHash` in the App Group to skip no-op writes.

**Rejected because:** dedupe machinery and cross-process write coordination add complexity for a small benefit. The main-app re-apply doesn't fix FC render lag (same underlying FC quirk), it only catches cases where the extension write never happened — which foreground catch-up (§4.5) already handles more cheaply. Also risks flicker if extension and app ever compute different configs from the same log (shouldn't happen, but guardrails cost code).

### 6.4 Approach A′ — Extension-writes + cache-bust via `clearAllSettings()`

Extension writes, and clears the store first to force FC re-read.

**Rejected because:** `clearAllSettings()` followed by `apply(target)` creates a real empty-shield state for the duration of the two calls. A user opening an app during that window sees content flash through. The *reason* to cache-bust (forcing FC to render the new state) does not outweigh the flash cost. Direct property overwrite (§4.2) handles the common case without the risk.

---

## 7. Testing

### 7.1 Unit tests (pure, no FC)

- `compute(log, at:)` across the full state space: default × session presence × time-vs-endsAt.
- Transition table §3.2: for each row, feed an input log + event, assert resulting log.
- Session replace semantics: starting session while one is active overwrites cleanly.

### 7.2 Integration tests (device required)

- Start session → background app → wait past `endsAt` → foreground → shield state matches `defaultState`.
- Start session → force-quit app → wait past `endsAt` → foreground → shield state matches `defaultState` (validates §4.5 catch-up).
- Start session → flip default mid-session → verify session cancelled and new default applied immediately.
- Start session → end early → verify immediate transition to `defaultState`.
- Start session → start second session → verify replace semantics (old schedule cancelled, new schedule honored).

### 7.3 Manual QA

- Flash check: start/end a session while foregrounded with a shielded app visible in the background — confirm no visible unshielded frame.
- FC render lag: force-quit and observe worst-case lag after expiry. Document actual bound for reference.

---

## 8. Out of Scope

- UI for session picker, default toggle, end-session button.
- Onboarding / Family Controls permission flow.
- Analytics, logging, telemetry.
- Widget / Shortcuts surface.
- Multi-device / iCloud-sync of intent log.

Each is a separate design.
