# Block / Unblock Framework Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a clean, testable shield-state engine that owns all block/unblock decisions, driven by a persisted intent log shared between the main app and the `DeviceActivityMonitor` extension. Then migrate the existing ad-hoc shield writes (`ScreenTimeService` + `IntentionsApp.swift`) to use it.

**Architecture:** Single `IntentLog` in App Group `UserDefaults` is the source of truth. A pure `compute(log, now) -> ShieldConfig` function derives shield state. An `apply(config)` primitive writes `ManagedSettingsStore` directly. The DAM extension handles time-driven expiry; the main app handles user-driven transitions and catches stale sessions on foreground.

**Tech Stack:** Swift 6 (Sendable), Family Controls (`ManagedSettings`, `DeviceActivity`, `FamilyControls`), `XCTest`.

**Spec reference:** `docs/superpowers/specs/2026-04-19-block-unblock-framework-design.md`

---

## File Structure

New directory: `Intentions/ShieldState/` — added to target membership of both `Intentions` (main app) and `IntentionsDeviceActivityMonitor` (DAM extension).

| File | Responsibility |
|------|---------------|
| `Intentions/ShieldState/Types.swift` | `DefaultState`, `Session`, `IntentLog`, `ShieldConfig` value types. |
| `Intentions/ShieldState/Compute.swift` | Pure `compute(_:at:)` function. |
| `Intentions/ShieldState/IntentLogStore.swift` | App Group `UserDefaults` load/save with fresh-suite reads. |
| `Intentions/ShieldState/ShieldApplier.swift` | `ShieldApplying` protocol + `ManagedSettingsShieldApplier` concrete impl. |
| `Intentions/ShieldState/DAMScheduler.swift` | `DeviceActivityCenter` schedule + cancel helpers, keyed by session id. |
| `Intentions/ShieldState/ShieldEngine.swift` | Orchestrator: `startSession`, `endSession`, `flipDefault`, `handleExpiry`, `catchUpOnForeground`. |
| `IntentionsTests/ShieldState/ComputeTests.swift` | Exhaustive compute() coverage. |
| `IntentionsTests/ShieldState/IntentLogStoreTests.swift` | Round-trip + migration from empty. |
| `IntentionsTests/ShieldState/ShieldEngineTests.swift` | Engine behavior with fake applier + in-memory store. |
| `IntentionsTests/ShieldState/Fakes/FakeShieldApplier.swift` | Test double. |
| `IntentionsTests/ShieldState/Fakes/InMemoryIntentLogStore.swift` | Test double. |

Call-site migrations (tasks 8–10):
- `Intentions/App/IntentionsApp.swift` — replace startup shield writes with `ShieldEngine.catchUpOnForeground()`.
- `Intentions/Services/ScreenTimeService.swift` — remove shield-write responsibilities; delegate to `ShieldEngine`. Authorization / picker / monitoring-threshold concerns stay.
- `IntentionsDeviceActivityMonitor/DeviceActivityMonitorExtension.swift` — `intervalDidEnd` calls `ShieldEngine.handleExpiry()`.

---

## Task 1: Add shared folder and scaffold `Types.swift`

**Files:**
- Create: `Intentions/ShieldState/Types.swift`
- Modify: `Intentions.xcodeproj/project.pbxproj` (add `ShieldState/` folder to targets `Intentions` and `IntentionsDeviceActivityMonitor`)

- [ ] **Step 1: Create the directory and `Types.swift`**

```bash
mkdir -p Intentions/ShieldState
```

Write `Intentions/ShieldState/Types.swift`:

```swift
import Foundation
import FamilyControls

/// Base mode the app returns to when no session is active.
enum DefaultState: String, Codable, Sendable, Equatable {
    case blocked
    case open
}

/// A time-bounded user-granted access window.
struct Session: Codable, Sendable, Equatable, Identifiable {
    let id: UUID
    let apps: FamilyActivitySelection
    let startedAt: Date
    let endsAt: Date

    init(id: UUID = UUID(), apps: FamilyActivitySelection, startedAt: Date, endsAt: Date) {
        self.id = id
        self.apps = apps
        self.startedAt = startedAt
        self.endsAt = endsAt
    }
}

/// Persisted source of truth for shield decisions. Read/written by main app and DAM extension.
struct IntentLog: Codable, Sendable, Equatable {
    var defaultState: DefaultState
    var activeSession: Session?

    static let empty = IntentLog(defaultState: .blocked, activeSession: nil)
}

/// What the shield store should be configured to, at a moment in time.
enum ShieldConfig: Equatable, Sendable {
    case none                               // nothing shielded
    case allExcept(FamilyActivitySelection) // everything except these
    case all                                // everything shielded
}
```

- [ ] **Step 2: Add folder membership to both targets in Xcode**

Open `Intentions.xcodeproj` in Xcode. Right-click the project navigator, "Add Files to Intentions", select `Intentions/ShieldState/`, check target membership for **both** `Intentions` and `IntentionsDeviceActivityMonitor`. Save.

Verify the project builds.

- [ ] **Step 3: Compile check**

Run:
```bash
xcodebuild -project Intentions.xcodeproj -scheme Intentions -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO | tail -20
```
Expected: `** BUILD SUCCEEDED **`

Run again with the DAM scheme:
```bash
xcodebuild -project Intentions.xcodeproj -scheme IntentionsDeviceActivityMonitor -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO | tail -20
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add Intentions/ShieldState/Types.swift Intentions.xcodeproj/project.pbxproj
git commit -m "feat(shieldstate): scaffold Types.swift shared across main app + DAM"
```

---

## Task 2: Pure `compute()` function with full test coverage

**Files:**
- Create: `Intentions/ShieldState/Compute.swift`
- Create: `IntentionsTests/ShieldState/ComputeTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `IntentionsTests/ShieldState/ComputeTests.swift`:

```swift
import XCTest
import FamilyControls
@testable import Intentions

final class ComputeTests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    private func session(endOffset: TimeInterval, apps: FamilyActivitySelection = .init()) -> Session {
        Session(apps: apps, startedAt: t0, endsAt: t0.addingTimeInterval(endOffset))
    }

    // MARK: - No session

    func test_noSession_defaultBlocked_returnsAll() {
        let log = IntentLog(defaultState: .blocked, activeSession: nil)
        XCTAssertEqual(compute(log, at: t0), .all)
    }

    func test_noSession_defaultOpen_returnsNone() {
        let log = IntentLog(defaultState: .open, activeSession: nil)
        XCTAssertEqual(compute(log, at: t0), .none)
    }

    // MARK: - Active session

    func test_sessionActive_returnsAllExceptApps() {
        var picks = FamilyActivitySelection()
        // Note: we cannot construct ApplicationToken values directly in tests.
        // The selection is opaque — we only verify the case and that the
        // associated value round-trips by reference equality via Equatable.
        let log = IntentLog(
            defaultState: .blocked,
            activeSession: session(endOffset: 300, apps: picks)
        )
        guard case .allExcept(let returned) = compute(log, at: t0.addingTimeInterval(100)) else {
            return XCTFail("expected .allExcept")
        }
        XCTAssertEqual(returned, picks)
    }

    func test_sessionActive_independentOfDefault() {
        // Same session, flipping default should not change the active-session output.
        let picks = FamilyActivitySelection()
        let blockedLog = IntentLog(defaultState: .blocked, activeSession: session(endOffset: 300, apps: picks))
        let openLog    = IntentLog(defaultState: .open,    activeSession: session(endOffset: 300, apps: picks))
        XCTAssertEqual(compute(blockedLog, at: t0.addingTimeInterval(100)),
                       compute(openLog,    at: t0.addingTimeInterval(100)))
    }

    // MARK: - Expiry boundary

    func test_sessionExactlyAtEndsAt_treatedAsExpired() {
        // endsAt is exclusive upper bound: t < endsAt means active.
        let log = IntentLog(defaultState: .blocked, activeSession: session(endOffset: 300))
        XCTAssertEqual(compute(log, at: t0.addingTimeInterval(300)), .all)
    }

    func test_sessionPastEndsAt_defaultBlocked_returnsAll() {
        let log = IntentLog(defaultState: .blocked, activeSession: session(endOffset: 300))
        XCTAssertEqual(compute(log, at: t0.addingTimeInterval(301)), .all)
    }

    func test_sessionPastEndsAt_defaultOpen_returnsNone() {
        let log = IntentLog(defaultState: .open, activeSession: session(endOffset: 300))
        XCTAssertEqual(compute(log, at: t0.addingTimeInterval(301)), .none)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
xcodebuild test -project Intentions.xcodeproj -scheme Intentions -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:IntentionsTests/ComputeTests 2>&1 | tail -30
```
Expected: build failure — `cannot find 'compute' in scope`.

- [ ] **Step 3: Implement `compute()`**

Create `Intentions/ShieldState/Compute.swift`:

```swift
import Foundation

/// Returns the ShieldConfig that should be applied, given a log and a moment in time.
/// Pure; deterministic.
func compute(_ log: IntentLog, at now: Date) -> ShieldConfig {
    if let session = log.activeSession, now < session.endsAt {
        return .allExcept(session.apps)
    }
    switch log.defaultState {
    case .blocked: return .all
    case .open:    return .none
    }
}
```

Add `Compute.swift` to Xcode target membership for both `Intentions` and `IntentionsDeviceActivityMonitor`, and add `ComputeTests.swift` to the `IntentionsTests` target.

- [ ] **Step 4: Run tests to verify they pass**

```bash
xcodebuild test -project Intentions.xcodeproj -scheme Intentions -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:IntentionsTests/ComputeTests 2>&1 | tail -30
```
Expected: `Test Suite 'ComputeTests' passed`.

- [ ] **Step 5: Commit**

```bash
git add Intentions/ShieldState/Compute.swift IntentionsTests/ShieldState/ComputeTests.swift Intentions.xcodeproj/project.pbxproj
git commit -m "feat(shieldstate): add pure compute() with exhaustive tests"
```

---

## Task 3: `IntentLogStore` with App Group persistence + tests

**Files:**
- Create: `Intentions/ShieldState/IntentLogStore.swift`
- Create: `IntentionsTests/ShieldState/IntentLogStoreTests.swift`
- Reference: `Intentions/Utilities/SharedConstants.swift` for `AppConstants.appGroupId`

- [ ] **Step 1: Write the failing tests**

Create `IntentionsTests/ShieldState/IntentLogStoreTests.swift`:

```swift
import XCTest
@testable import Intentions

final class IntentLogStoreTests: XCTestCase {

    private let testSuiteName = "test.intentions.shieldstate"

    override func setUp() {
        super.setUp()
        UserDefaults(suiteName: testSuiteName)?.removePersistentDomain(forName: testSuiteName)
    }

    override func tearDown() {
        UserDefaults(suiteName: testSuiteName)?.removePersistentDomain(forName: testSuiteName)
        super.tearDown()
    }

    func test_loadFromEmpty_returnsDefaultBlockedNoSession() {
        let store = IntentLogStore(suiteName: testSuiteName)
        let log = store.load()
        XCTAssertEqual(log, .empty)
    }

    func test_saveThenLoad_roundTrips() {
        let store = IntentLogStore(suiteName: testSuiteName)
        var log = IntentLog.empty
        log.defaultState = .open
        store.save(log)

        let reloaded = store.load()
        XCTAssertEqual(reloaded.defaultState, .open)
        XCTAssertNil(reloaded.activeSession)
    }

    func test_freshInstancePerRead_avoidsStaleCache() {
        let writer = IntentLogStore(suiteName: testSuiteName)
        writer.save(IntentLog(defaultState: .open, activeSession: nil))

        // Simulated second process: new instance
        let reader = IntentLogStore(suiteName: testSuiteName)
        XCTAssertEqual(reader.load().defaultState, .open)
    }

    func test_corruptedData_fallsBackToEmpty() {
        let defaults = UserDefaults(suiteName: testSuiteName)!
        defaults.set(Data([0xFF, 0xFE, 0xFD]), forKey: IntentLogStore.storageKey)

        let store = IntentLogStore(suiteName: testSuiteName)
        XCTAssertEqual(store.load(), .empty)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
xcodebuild test -project Intentions.xcodeproj -scheme Intentions -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:IntentionsTests/IntentLogStoreTests 2>&1 | tail -30
```
Expected: `cannot find 'IntentLogStore' in scope`.

- [ ] **Step 3: Implement `IntentLogStore`**

Create `Intentions/ShieldState/IntentLogStore.swift`:

```swift
import Foundation

/// Reads and writes the IntentLog to an App Group UserDefaults suite.
/// Uses a fresh UserDefaults instance per call to avoid stale per-process caches
/// that bite cross-process readers (main app vs. DAM extension).
struct IntentLogStore: Sendable {
    static let storageKey = "shieldstate.intentlog.v1"

    /// Literal App Group id. Kept local so this file compiles as a standalone
    /// member of the DAM extension target.
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
            // Corrupted payload — treat as empty. Better than crashing at a
            // shield-decision site; foreground catch-up will repair.
            return .empty
        }
    }

    func save(_ log: IntentLog) {
        guard let defaults = UserDefaults(suiteName: suiteName) else { return }
        let data = (try? JSONEncoder().encode(log)) ?? Data()
        defaults.set(data, forKey: Self.storageKey)
    }
}
```

Add `IntentLogStore.swift` to Xcode target membership for both `Intentions` and `IntentionsDeviceActivityMonitor`. Add the test file to `IntentionsTests`.

- [ ] **Step 4: Run tests to verify they pass**

```bash
xcodebuild test -project Intentions.xcodeproj -scheme Intentions -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:IntentionsTests/IntentLogStoreTests 2>&1 | tail -30
```
Expected: all 4 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Intentions/ShieldState/IntentLogStore.swift IntentionsTests/ShieldState/IntentLogStoreTests.swift Intentions.xcodeproj/project.pbxproj
git commit -m "feat(shieldstate): add IntentLogStore with App Group UserDefaults persistence"
```

---

## Task 4: `ShieldApplying` protocol and concrete `ManagedSettings` impl

`ManagedSettingsStore` can't be instantiated meaningfully in unit tests (no FC entitlement on simulator), so we wrap the write surface behind a protocol for test seams.

**Files:**
- Create: `Intentions/ShieldState/ShieldApplier.swift`
- Create: `IntentionsTests/ShieldState/Fakes/FakeShieldApplier.swift`

- [ ] **Step 1: Define protocol + fake; no tests yet (tests come in Task 6)**

Create `Intentions/ShieldState/ShieldApplier.swift`:

```swift
import Foundation
import ManagedSettings

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
```

Create `IntentionsTests/ShieldState/Fakes/FakeShieldApplier.swift`:

```swift
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
```

Add both to their respective Xcode targets (`ShieldApplier.swift` → main app + DAM extension; fake → `IntentionsTests`).

- [ ] **Step 2: Compile check**

```bash
xcodebuild build -project Intentions.xcodeproj -scheme Intentions -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO | tail -5
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add Intentions/ShieldState/ShieldApplier.swift IntentionsTests/ShieldState/Fakes/FakeShieldApplier.swift Intentions.xcodeproj/project.pbxproj
git commit -m "feat(shieldstate): ShieldApplying protocol + ManagedSettings impl + fake"
```

---

## Task 5: `DAMScheduler` — schedule and cancel DeviceActivity intervals

**Files:**
- Create: `Intentions/ShieldState/DAMScheduler.swift`

No unit tests here — `DeviceActivityCenter` cannot be faked without introducing another protocol layer, and the logic is thin (two method calls wrapped). Coverage comes from integration tests in Task 11.

- [ ] **Step 1: Implement the scheduler**

Create `Intentions/ShieldState/DAMScheduler.swift`:

```swift
import Foundation
import DeviceActivity

/// Thin wrapper over DeviceActivityCenter that schedules session-expiry callbacks.
/// The DAM extension receives intervalDidEnd() for the DeviceActivityName we register.
struct DAMScheduler: Sendable {
    /// Canonical name for the single session-expiry schedule. We always use the
    /// same name — starting a new session overwrites any pending prior schedule.
    static let sessionExpiryName = DeviceActivityName("shieldstate.session-expiry")

    private let center = DeviceActivityCenter()

    /// Schedule a single-fire interval that ends at `endsAt`.
    /// Starts immediately so intervalDidEnd() fires at endsAt.
    /// Throws if endsAt is in the past or if authorization is missing.
    func schedule(endsAt: Date) throws {
        let now = Date()
        // DeviceActivitySchedule uses DateComponents, resolution at minute level.
        let startComponents = Self.components(from: now)
        let endComponents   = Self.components(from: endsAt)

        let schedule = DeviceActivitySchedule(
            intervalStart: startComponents,
            intervalEnd: endComponents,
            repeats: false
        )
        try center.startMonitoring(Self.sessionExpiryName, during: schedule)
    }

    /// Cancel any in-flight schedule under our name. Safe to call when nothing is scheduled.
    func cancel() {
        center.stopMonitoring([Self.sessionExpiryName])
    }

    private static func components(from date: Date) -> DateComponents {
        Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: date
        )
    }
}
```

Add to target membership of `Intentions` only (the DAM extension doesn't schedule; it only receives the callback).

- [ ] **Step 2: Compile check**

```bash
xcodebuild build -project Intentions.xcodeproj -scheme Intentions -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO | tail -5
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add Intentions/ShieldState/DAMScheduler.swift Intentions.xcodeproj/project.pbxproj
git commit -m "feat(shieldstate): DAMScheduler for session-expiry DeviceActivity intervals"
```

---

## Task 6: `ShieldEngine` orchestrator with full test coverage

**Files:**
- Create: `Intentions/ShieldState/ShieldEngine.swift`
- Create: `IntentionsTests/ShieldState/Fakes/InMemoryIntentLogStore.swift`
- Create: `IntentionsTests/ShieldState/ShieldEngineTests.swift`

- [ ] **Step 1: Write in-memory log store fake**

Create `IntentionsTests/ShieldState/Fakes/InMemoryIntentLogStore.swift`:

```swift
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
```

This references a protocol `IntentLogStoring` that doesn't exist yet — introduce it in Step 3. Leave the file; it won't compile until then.

- [ ] **Step 2: Write the failing engine tests**

Create `IntentionsTests/ShieldState/ShieldEngineTests.swift`:

```swift
import XCTest
import FamilyControls
@testable import Intentions

final class ShieldEngineTests: XCTestCase {

    private var store: InMemoryIntentLogStore!
    private var applier: FakeShieldApplier!
    private var engine: ShieldEngine!
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    override func setUp() {
        super.setUp()
        store = InMemoryIntentLogStore()
        applier = FakeShieldApplier()
        engine = ShieldEngine(store: store, applier: applier, scheduler: nil)
    }

    // MARK: - Start session

    func test_startSession_fromNoActive_writesLogAndAppliesAllExcept() {
        let picks = FamilyActivitySelection()
        engine.startSession(apps: picks, endsAt: t0.addingTimeInterval(300), now: t0)

        XCTAssertNotNil(store.load().activeSession)
        XCTAssertEqual(store.load().activeSession?.endsAt, t0.addingTimeInterval(300))

        XCTAssertEqual(applier.calls.count, 1)
        guard case .allExcept = applier.calls.first else {
            return XCTFail("expected .allExcept")
        }
    }

    func test_startSession_replacesExistingActiveSession() {
        engine.startSession(apps: .init(), endsAt: t0.addingTimeInterval(300), now: t0)
        let firstId = store.load().activeSession?.id

        engine.startSession(apps: .init(), endsAt: t0.addingTimeInterval(600), now: t0)
        let secondId = store.load().activeSession?.id

        XCTAssertNotNil(firstId)
        XCTAssertNotNil(secondId)
        XCTAssertNotEqual(firstId, secondId)
        XCTAssertEqual(store.load().activeSession?.endsAt, t0.addingTimeInterval(600))
    }

    // MARK: - End session

    func test_endSession_defaultBlocked_appliesAll() {
        engine.startSession(apps: .init(), endsAt: t0.addingTimeInterval(300), now: t0)
        applier.calls.removeAll(keepingCapacity: false)

        engine.endSession(now: t0.addingTimeInterval(60))

        XCTAssertNil(store.load().activeSession)
        XCTAssertEqual(applier.calls, [.all])
    }

    func test_endSession_defaultOpen_appliesNone() {
        var log = store.load()
        log.defaultState = .open
        store.save(log)

        engine.startSession(apps: .init(), endsAt: t0.addingTimeInterval(300), now: t0)
        applier.calls.removeAll(keepingCapacity: false)

        engine.endSession(now: t0.addingTimeInterval(60))

        XCTAssertNil(store.load().activeSession)
        XCTAssertEqual(applier.calls, [.none])
    }

    // MARK: - Flip default

    func test_flipDefault_blockedToOpen_cancelsActiveSession_andAppliesNone() {
        engine.startSession(apps: .init(), endsAt: t0.addingTimeInterval(300), now: t0)
        applier.calls.removeAll(keepingCapacity: false)

        engine.flipDefault(to: .open, now: t0.addingTimeInterval(60))

        XCTAssertNil(store.load().activeSession)
        XCTAssertEqual(store.load().defaultState, .open)
        XCTAssertEqual(applier.calls, [.none])
    }

    func test_flipDefault_openToBlocked_noActiveSession_appliesAll() {
        var log = store.load()
        log.defaultState = .open
        store.save(log)

        engine.flipDefault(to: .blocked, now: t0)

        XCTAssertEqual(store.load().defaultState, .blocked)
        XCTAssertEqual(applier.calls, [.all])
    }

    // MARK: - Handle expiry (DAM path)

    func test_handleExpiry_sessionPastEndsAt_defaultBlocked_appliesAll() {
        engine.startSession(apps: .init(), endsAt: t0.addingTimeInterval(300), now: t0)
        applier.calls.removeAll(keepingCapacity: false)

        engine.handleExpiry(now: t0.addingTimeInterval(301))

        XCTAssertNil(store.load().activeSession)
        XCTAssertEqual(applier.calls, [.all])
    }

    func test_handleExpiry_sessionStillActive_noOp() {
        engine.startSession(apps: .init(), endsAt: t0.addingTimeInterval(300), now: t0)
        applier.calls.removeAll(keepingCapacity: false)

        // DAM fired early or spuriously — session not yet expired
        engine.handleExpiry(now: t0.addingTimeInterval(100))

        XCTAssertNotNil(store.load().activeSession, "session should not be cleared early")
        XCTAssertEqual(applier.calls.count, 0, "no shield write for non-expiry")
    }

    func test_handleExpiry_noActiveSession_noOp() {
        engine.handleExpiry(now: t0)
        XCTAssertEqual(applier.calls.count, 0)
    }

    // MARK: - Foreground catch-up

    func test_catchUpOnForeground_staleExpiredSession_clearsAndApplies() {
        engine.startSession(apps: .init(), endsAt: t0.addingTimeInterval(300), now: t0)
        applier.calls.removeAll(keepingCapacity: false)

        engine.catchUpOnForeground(now: t0.addingTimeInterval(500))

        XCTAssertNil(store.load().activeSession)
        XCTAssertEqual(applier.calls, [.all])
    }

    func test_catchUpOnForeground_activeSession_noOp() {
        engine.startSession(apps: .init(), endsAt: t0.addingTimeInterval(300), now: t0)
        applier.calls.removeAll(keepingCapacity: false)

        engine.catchUpOnForeground(now: t0.addingTimeInterval(60))

        XCTAssertNotNil(store.load().activeSession)
        XCTAssertEqual(applier.calls.count, 0)
    }

    func test_catchUpOnForeground_noSession_noOp() {
        engine.catchUpOnForeground(now: t0)
        XCTAssertEqual(applier.calls.count, 0)
    }
}
```

- [ ] **Step 3: Run tests to verify they fail**

```bash
xcodebuild test -project Intentions.xcodeproj -scheme Intentions -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:IntentionsTests/ShieldEngineTests 2>&1 | tail -40
```
Expected: build failure — `cannot find 'ShieldEngine' in scope`, `cannot find 'IntentLogStoring' in scope`.

- [ ] **Step 4: Introduce `IntentLogStoring` protocol; make `IntentLogStore` conform**

Modify `Intentions/ShieldState/IntentLogStore.swift` — add a protocol and conformance. The struct keeps its existing API; the protocol mirrors it.

Replace the file contents:

```swift
import Foundation

protocol IntentLogStoring: Sendable {
    func load() -> IntentLog
    func save(_ log: IntentLog)
}

struct IntentLogStore: IntentLogStoring, Sendable {
    static let storageKey = "shieldstate.intentlog.v1"

    /// Literal App Group id. The main app defines this in SharedConstants.swift
    /// (AppConstants.appGroupId) but we keep a local literal here so this file
    /// compiles cleanly as a standalone member of the DAM extension target
    /// without a dependency on SharedConstants.swift's target membership.
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
```

- [ ] **Step 5: Implement `ShieldEngine`**

Create `Intentions/ShieldState/ShieldEngine.swift`:

```swift
import Foundation
import FamilyControls

/// Orchestrator that owns all transitions in the shield state machine.
/// Reads/writes the intent log, calls the applier, optionally schedules DAM.
///
/// The scheduler parameter is optional because the DAM extension doesn't need
/// to schedule anything — only the main app schedules, and both sides handle expiry.
struct ShieldEngine: Sendable {
    private let store: IntentLogStoring
    private let applier: ShieldApplying
    private let scheduler: DAMScheduler?

    init(store: IntentLogStoring, applier: ShieldApplying, scheduler: DAMScheduler?) {
        self.store = store
        self.applier = applier
        self.scheduler = scheduler
    }

    // MARK: - User-driven transitions

    func startSession(apps: FamilyActivitySelection, endsAt: Date, now: Date = Date()) {
        scheduler?.cancel()

        var log = store.load()
        log.activeSession = Session(apps: apps, startedAt: now, endsAt: endsAt)
        store.save(log)

        do {
            try scheduler?.schedule(endsAt: endsAt)
        } catch {
            // Scheduling failed — we still apply the shield. Foreground catch-up
            // will repair if the DAM never fires.
        }

        applier.apply(compute(log, at: now))
    }

    func endSession(now: Date = Date()) {
        scheduler?.cancel()

        var log = store.load()
        guard log.activeSession != nil else { return }
        log.activeSession = nil
        store.save(log)

        applier.apply(compute(log, at: now))
    }

    func flipDefault(to newDefault: DefaultState, now: Date = Date()) {
        scheduler?.cancel()

        var log = store.load()
        log.defaultState = newDefault
        log.activeSession = nil
        store.save(log)

        applier.apply(compute(log, at: now))
    }

    // MARK: - System-driven transitions

    /// Called by the DAM extension at interval end.
    func handleExpiry(now: Date = Date()) {
        var log = store.load()
        guard let session = log.activeSession, session.endsAt <= now else {
            // Session was already replaced/cancelled, or DAM fired early.
            return
        }
        log.activeSession = nil
        store.save(log)
        applier.apply(compute(log, at: now))
    }

    /// Called by main app on appDidBecomeActive / scenePhase change to foreground.
    /// Repairs state if DAM silently failed to fire.
    func catchUpOnForeground(now: Date = Date()) {
        var log = store.load()
        guard let session = log.activeSession, session.endsAt <= now else { return }
        log.activeSession = nil
        store.save(log)
        applier.apply(compute(log, at: now))
    }
}
```

Add `ShieldEngine.swift` to target membership of **both** `Intentions` and `IntentionsDeviceActivityMonitor`. Add the test files and fake to `IntentionsTests`.

- [ ] **Step 6: Run tests to verify they pass**

```bash
xcodebuild test -project Intentions.xcodeproj -scheme Intentions -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:IntentionsTests/ShieldEngineTests 2>&1 | tail -40
```
Expected: all 11 tests in `ShieldEngineTests` pass. The existing `ComputeTests` and `IntentLogStoreTests` still pass.

- [ ] **Step 7: Commit**

```bash
git add Intentions/ShieldState/ShieldEngine.swift Intentions/ShieldState/IntentLogStore.swift IntentionsTests/ShieldState/ShieldEngineTests.swift IntentionsTests/ShieldState/Fakes/InMemoryIntentLogStore.swift Intentions.xcodeproj/project.pbxproj
git commit -m "feat(shieldstate): ShieldEngine orchestrator with full transition coverage"
```

---

## Task 7: Factory for production engine

Give both processes a one-liner to spin up the real engine, so call-sites don't need to wire dependencies themselves.

**Files:**
- Modify: `Intentions/ShieldState/ShieldEngine.swift`

- [ ] **Step 1: Add factory method at bottom of `ShieldEngine.swift`**

Append:

```swift
extension ShieldEngine {
    /// Production engine used by the main app (schedules DAM).
    static func mainApp() -> ShieldEngine {
        ShieldEngine(
            store: IntentLogStore(),
            applier: ManagedSettingsShieldApplier(),
            scheduler: DAMScheduler()
        )
    }

    /// Production engine used by the DAM extension (does not schedule — only handles expiry).
    static func damExtension() -> ShieldEngine {
        ShieldEngine(
            store: IntentLogStore(),
            applier: ManagedSettingsShieldApplier(),
            scheduler: nil
        )
    }
}
```

- [ ] **Step 2: Compile check**

```bash
xcodebuild build -project Intentions.xcodeproj -scheme Intentions -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO | tail -5
xcodebuild build -project Intentions.xcodeproj -scheme IntentionsDeviceActivityMonitor -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO | tail -5
```
Expected: both `** BUILD SUCCEEDED **`.

Note: `DAMScheduler` is main-app-only. The `damExtension()` factory intentionally passes `nil` and the `mainApp()` factory needs to compile only against the main app target. If the extension target complains about missing `DAMScheduler`, gate the `mainApp()` factory behind a `#if canImport(DeviceActivity)` check *inside* a separate file that's only a member of the main app target.

If needed, split: move `mainApp()` factory into `Intentions/ShieldState/ShieldEngine+MainApp.swift` (main app target only). Keep `damExtension()` in the shared file (it only depends on types visible to both targets).

- [ ] **Step 3: Commit**

```bash
git add Intentions/ShieldState/ShieldEngine.swift Intentions/ShieldState/ShieldEngine+MainApp.swift Intentions.xcodeproj/project.pbxproj
git commit -m "feat(shieldstate): factory methods for main-app and DAM engines"
```

---

## Task 8: Wire DAM extension to `ShieldEngine.handleExpiry()`

**Files:**
- Modify: `IntentionsDeviceActivityMonitor/DeviceActivityMonitorExtension.swift`

- [ ] **Step 1: Read the current implementation to understand the existing `intervalDidEnd`**

Run:
```bash
cat IntentionsDeviceActivityMonitor/DeviceActivityMonitorExtension.swift
```

Understand: what does the current `intervalDidEnd(for:)` do? What other callbacks exist (`intervalDidStart`, threshold events)? Our change only replaces the **shield-mutation side** of `intervalDidEnd` — any logging, analytics, or unrelated side effects stay.

- [ ] **Step 2: Modify `intervalDidEnd(for:)`**

Locate `override func intervalDidEnd(for activity: DeviceActivityName)`. Replace its shield-writing body with:

```swift
override func intervalDidEnd(for activity: DeviceActivityName) {
    super.intervalDidEnd(for: activity)
    guard activity == DAMScheduler.sessionExpiryName else { return }
    ShieldEngine.damExtension().handleExpiry()
}
```

Remove any direct `ManagedSettingsStore` writes, any direct `IntentLog`/session mutations, and any `clearAllSettings()` calls from this method. If the existing code has separate threshold-event handling (`eventDidReachThreshold`), leave it alone — this plan is scoped to interval-based session expiry.

- [ ] **Step 3: Build the extension target**

```bash
xcodebuild build -project Intentions.xcodeproj -scheme IntentionsDeviceActivityMonitor -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO | tail -5
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
git add IntentionsDeviceActivityMonitor/DeviceActivityMonitorExtension.swift
git commit -m "refactor(monitor): delegate interval-end shield logic to ShieldEngine"
```

---

## Task 9: Main app — start/end session + flip default via engine

**Files:**
- Modify: `Intentions/Services/ScreenTimeService.swift`

`ScreenTimeService` currently owns shield writes across ~22 sites. We leave it as the surface that UI/view-models call, but its shield-mutation methods now delegate to `ShieldEngine.mainApp()`. Authorization, picker presentation, threshold-event registration stay.

- [ ] **Step 1: Identify the public methods that mutate shield state**

Run:
```bash
grep -n "shield\.\|ManagedSettingsStore\|startMonitoring\|stopMonitoring" Intentions/Services/ScreenTimeService.swift
```

Catalog:
- `startSession(apps:duration:)` or equivalent — currently writes shield + schedules.
- `endSession()` or equivalent — currently writes shield + cancels schedule.
- Any "set default blocked/open" toggle — writes shield.

- [ ] **Step 2: Replace each shield-mutation method's body with an engine call**

Example transformation (adapt to the real method names found in Step 1):

```swift
// Before:
func startSession(apps: FamilyActivitySelection, duration: TimeInterval) {
    let store = ManagedSettingsStore()
    store.shield.applicationCategories = .all(except: apps.applicationTokens)
    // … plus scheduling, log persistence, observable state updates …
}

// After:
func startSession(apps: FamilyActivitySelection, duration: TimeInterval) {
    let endsAt = Date().addingTimeInterval(duration)
    ShieldEngine.mainApp().startSession(apps: apps, endsAt: endsAt)
    syncPublishedState()
}

private func syncPublishedState() {
    let log = IntentLogStore().load()
    // Update the @Published / @Observable properties this service already
    // exposes to the UI. Names below are placeholders — use whatever the
    // existing `ScreenTimeService` surface exposes (e.g. `isSessionActive`,
    // `currentSession`, `defaultState`).
    self.currentSession = log.activeSession
    self.defaultState   = log.defaultState
}
```

If `ScreenTimeService` already has its own "re-read from source of truth" helper (look for any `reloadFromDefaults` / `publishState` / equivalent in the existing file), call that instead — don't duplicate. The intent is: after every engine call, the service's observable properties reflect the updated log so the UI layer updates without extra wiring.

Apply the same pattern to `endSession()` → `ShieldEngine.mainApp().endSession()` + `syncPublishedState()`, and to the default-flip method → `ShieldEngine.mainApp().flipDefault(to: newDefault)` + `syncPublishedState()`.

- [ ] **Step 3: Delete now-dead shield-write code in `ScreenTimeService`**

Remove any fields and helpers whose only purpose was the shield write (e.g. private `ManagedSettingsStore` property, private schedule helpers that `DAMScheduler` now owns). Leave authorization, picker, and event-threshold code untouched.

- [ ] **Step 4: Build**

```bash
xcodebuild build -project Intentions.xcodeproj -scheme Intentions -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO | tail -5
```
Expected: `** BUILD SUCCEEDED **`. Fix any call-sites that referenced removed fields.

- [ ] **Step 5: Run the existing service test suite to catch regressions**

```bash
xcodebuild test -project Intentions.xcodeproj -scheme Intentions -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:IntentionsTests/ScreenTimeServiceTests 2>&1 | tail -30
```
Expected: existing tests either pass or need surface-level updates (mock expectations change). If any test was asserting on internal shield calls, update it to assert on engine state via an injected `InMemoryIntentLogStore`.

- [ ] **Step 6: Commit**

```bash
git add Intentions/Services/ScreenTimeService.swift IntentionsTests/Services/ScreenTimeServiceTests.swift
git commit -m "refactor(screentime): delegate shield writes to ShieldEngine"
```

---

## Task 10: Main app — foreground catch-up on scene activation

**Files:**
- Modify: `Intentions/App/IntentionsApp.swift`

- [ ] **Step 1: Read the current file to find the scene-phase handler**

Run:
```bash
cat Intentions/App/IntentionsApp.swift
```

Look for `@Environment(\.scenePhase)`, `.onChange(of: scenePhase)`, or an `AppDelegate` hook for `applicationDidBecomeActive`. Locate the existing startup shield logic at lines ~55-81 flagged by the integration survey.

- [ ] **Step 2: Replace startup shield writes with catch-up call**

Inside the `scenePhase` `.active` branch (or `applicationDidBecomeActive`), remove any direct shield writes and add:

```swift
ShieldEngine.mainApp().catchUpOnForeground()
```

Remove any leftover `ManagedSettingsStore()` usage and any startup "clear shields" logic — catch-up handles stale sessions and idempotent re-apply is not needed here (only-changes-when-stale is the design).

- [ ] **Step 3: Build + run on simulator**

```bash
xcodebuild build -project Intentions.xcodeproj -scheme Intentions -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO | tail -5
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
git add Intentions/App/IntentionsApp.swift
git commit -m "refactor(app): foreground catch-up via ShieldEngine"
```

---

## Task 11: Device integration verification

**Files:** none — manual verification on a physical device with Family Controls authorized.

Unit tests cover the state engine. These are the end-to-end checks that the DAM path, `ManagedSettingsStore`, and foreground catch-up actually work together under iOS.

- [ ] **Step 1: Build + install on device**

```bash
xcodebuild -project Intentions.xcodeproj -scheme Intentions -configuration Debug -destination 'platform=iOS,name=<your-device>' build
```
Then install via Xcode Run button (⌘R) with the device selected. Verify Family Controls permission is already granted (from prior runs).

- [ ] **Step 2: Case A — happy path (app backgrounded)**

1. Set default to `blocked`.
2. Start a 2-minute session with one or two apps picked.
3. Verify picked apps are accessible, others shielded.
4. Background the app (home gesture).
5. Wait past 2 minutes.
6. Open a picked app — it should now be shielded (session expired, default blocked).

Expected: shield re-applies without main app being in foreground.

- [ ] **Step 3: Case B — force-quit**

1. Set default to `blocked`.
2. Start a 2-minute session.
3. Force-quit the main app (swipe up from app switcher).
4. Wait past 2 minutes.
5. Attempt to open a previously-picked app.

Expected: shield re-applies (possibly with FC render lag of a few seconds — documented trade-off).

- [ ] **Step 4: Case C — default flip mid-session cancels session**

1. Start a session with default `blocked`.
2. Mid-session, flip default to `open` via UI.
3. Observe: shields drop immediately, everything accessible.

Expected: session cancelled at flip, default effect visible instantly.

- [ ] **Step 5: Case D — session replace**

1. Start session A (5 min, apps X+Y).
2. Before A expires, start session B (2 min, apps Y+Z).
3. Verify X is now shielded, Z now accessible.
4. Wait past B's 2 min.
5. Verify state matches default (not A's 5-min window).

Expected: A fully replaced by B; A's schedule cancelled.

- [ ] **Step 6: Case E — foreground catch-up repairs stale state**

1. Start a 2-minute session.
2. Force-quit the app.
3. Disable Wi-Fi/cellular to reduce OS activity (simulate DAM miss as best as possible on a real device).
4. Wait past 2 minutes.
5. Re-open the main app.

Expected: on foreground, shield snaps to default. (Even if DAM did fire, this verifies catch-up does not produce a flash.)

- [ ] **Step 7: Flash check**

1. Start a session.
2. With the shielded screen visible (open a blocked app, see the shield), trigger end-session from the main app.
3. Watch carefully for any unshielded-frame flash before the new state renders.

Expected: hard cut from shield to unshielded (or from one shield config to another). No empty-shield flash.

- [ ] **Step 8: If everything passes, commit a tag-style marker commit**

```bash
git commit --allow-empty -m "test(device): shieldstate verified on physical device per plan §11"
```

---

## Task 12: Update project vault notes

Per global `CLAUDE.md` instructions: architecture changes require a vault notes update.

**Files:**
- Modify: `.project-notes/overview.md` (symlink to vault)
- Possibly: `.project-notes/architecture.md`, `.project-notes/notes.md`

- [ ] **Step 1: Add a dated entry to `.project-notes/overview.md`**

Append:

```markdown
## 2026-04-19 — ShieldState module

Replaced ad-hoc shield writes in `ScreenTimeService` + `IntentionsApp` with a
clean `ShieldState/` module driven by a persisted `IntentLog` in App Group
`group.oh.Intent`.

Key pieces:
- Pure `compute(log, now) -> ShieldConfig`
- `ShieldApplying` protocol (real + fake)
- `IntentLogStore` with fresh `UserDefaults(suiteName:)` reads
- `ShieldEngine` orchestrator (user actions + DAM expiry + foreground catch-up)

Ownership: DAM extension handles time-driven expiry; main app handles user-driven
transitions + stale-session repair on foreground. No BGTask dependency — survives
force-quit.

Spec: `docs/superpowers/specs/2026-04-19-block-unblock-framework-design.md`
Plan: `docs/superpowers/plans/2026-04-19-block-unblock-framework.md`
```

- [ ] **Step 2: Commit**

```bash
git add .project-notes/overview.md
git commit -m "docs(notes): log ShieldState module in vault"
```

---

## Spec Coverage Check

| Spec section | Covered by task(s) |
|-------------|-------------------|
| §2.1 `DefaultState` | 1 |
| §2.2 `Session` | 1 |
| §2.3 `IntentLog` + App Group persistence | 1, 3 |
| §3.1 session invariant | 2 (compute tests), 6 (engine tests) |
| §3.2 transition table | 6 (`ShieldEngineTests` covers all five rows) |
| §3.3 `compute()` | 2 |
| §4.1 ownership split | 8 (DAM), 9 (main app) |
| §4.2 `apply()` primitive + no `clearAllSettings` | 4 |
| §4.3 DAM scheduling + `intervalDidEnd` | 5, 8 |
| §4.4 user-driven writes | 9 |
| §4.5 foreground catch-up | 6 (test), 10 (integration) |
| §5 trade-offs | 11 (device verification) |
| §7.1 unit tests | 2, 3, 6 |
| §7.2 integration tests | 11 |
| §7.3 manual QA (flash, lag) | 11 steps 7 + 3 |
