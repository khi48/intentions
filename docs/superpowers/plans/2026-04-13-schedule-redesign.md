# Schedule Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the single-window `ScheduleSettings` model and its editor with a week-grid editor backed by a list of `FreeTimeInterval` records that can span day boundaries.

**Architecture:** Data-first refactor. New `FreeTimeInterval` struct and `WeeklySchedule` @Observable class with minute-of-week storage land first with TDD-driven unit tests. A migration function converts any persisted `ScheduleSettings` blob into the new shape on first read. The Settings tab's free-time row then points at a rewritten SwiftUI editor view (week grid + edit sheet + copy sheet). Old model, old view, and old tests are deleted at the end. Scene-phase catch-up is included to mitigate the shield-lag bug partially; the full DeviceActivity-boundary fix is deferred to a follow-up spec.

**Tech Stack:** Swift 6, SwiftUI (`@Observable`, `NavigationStack`, `.sheet`, `.contextMenu`), XCTest, iOS 18+ deployment target. Uses the existing `DataPersisting` / `DataPersistenceService` layer and the `Weekday` enum that ships with the codebase.

**Scope note:** This plan covers the data model, editor UI, migration, Settings integration, and scene-phase catch-up for shield sync. It does **not** include scheduling DeviceActivity boundary events for free-time transitions — that is tracked as a follow-up bug fix and will get its own spec.

**Spec reference:** `docs/superpowers/specs/2026-04-13-schedule-redesign-design.md`

---

## Preflight

Before Task 1 starts, verify the working tree is clean. The session that produced this plan left several uncommitted edits to `ScheduleSettings.swift`, `Constants.swift`, `SettingsView.swift`, and `ScheduleSettingsTests.swift`. They must either be committed or reverted before this plan begins, because subsequent tasks delete or heavily rewrite those files.

- [ ] **Verify clean working tree**

```bash
git status
```

If there are uncommitted edits to the files above, commit them as a single "prep" commit or `git restore` the ones you don't want. Do not start Task 1 until `git status` reports a clean tree (ignoring untracked non-source files like `.claude/`).

---

## Task 1: `FreeTimeInterval` struct + core math

**Files:**
- Create: `Intentions/Models/FreeTimeInterval.swift`
- Create: `IntentionsTests/ModelTests/FreeTimeIntervalTests.swift`

- [ ] **Step 1: Write the failing test file**

Create `IntentionsTests/ModelTests/FreeTimeIntervalTests.swift`:

```swift
import XCTest
@testable import Intentions

@MainActor
final class FreeTimeIntervalTests: XCTestCase {

    // MARK: - Basic construction

    func testMinuteOfWeekConstantsMatchExpectations() {
        XCTAssertEqual(FreeTimeInterval.minutesPerDay, 1440)
        XCTAssertEqual(FreeTimeInterval.minutesPerWeek, 10080)
    }

    // MARK: - Containment (non-wrapping)

    func testContainsWithinNonWrappingInterval() {
        // Mon 09:00 → Mon 17:00
        let interval = FreeTimeInterval(
            id: UUID(),
            startMinuteOfWeek: 9 * 60,
            durationMinutes: 8 * 60
        )
        XCTAssertTrue(interval.contains(minuteOfWeek: 9 * 60))       // start edge
        XCTAssertTrue(interval.contains(minuteOfWeek: 12 * 60))      // middle
        XCTAssertFalse(interval.contains(minuteOfWeek: 17 * 60))     // end edge (exclusive)
        XCTAssertFalse(interval.contains(minuteOfWeek: 9 * 60 - 1))  // before
        XCTAssertFalse(interval.contains(minuteOfWeek: 17 * 60 + 1)) // after
    }

    // MARK: - Containment (wrapping)

    func testContainsWithinWrappingInterval() {
        // Sun 22:00 → Mon 02:00
        // Sun = day 6 (Mon-origin), 22:00 = 22*60 = 1320
        // startMinuteOfWeek = 6 * 1440 + 1320 = 9960
        // duration = 4h = 240
        let interval = FreeTimeInterval(
            id: UUID(),
            startMinuteOfWeek: 9960,
            durationMinutes: 240
        )
        XCTAssertTrue(interval.contains(minuteOfWeek: 9960))       // Sun 22:00
        XCTAssertTrue(interval.contains(minuteOfWeek: 10079))      // Sun 23:59
        XCTAssertTrue(interval.contains(minuteOfWeek: 0))          // Mon 00:00
        XCTAssertTrue(interval.contains(minuteOfWeek: 119))        // Mon 01:59
        XCTAssertFalse(interval.contains(minuteOfWeek: 120))       // Mon 02:00 (end, exclusive)
        XCTAssertFalse(interval.contains(minuteOfWeek: 9959))      // Sun 21:59
    }

    // MARK: - Overlap

    func testOverlapsSimple() {
        let a = FreeTimeInterval(id: UUID(), startMinuteOfWeek: 100, durationMinutes: 200)
        let b = FreeTimeInterval(id: UUID(), startMinuteOfWeek: 200, durationMinutes: 200)
        let c = FreeTimeInterval(id: UUID(), startMinuteOfWeek: 400, durationMinutes: 50)
        XCTAssertTrue(a.overlaps(b))
        XCTAssertFalse(a.overlaps(c))
        XCTAssertFalse(b.overlaps(c))
    }

    // MARK: - Derived day/time

    func testStartDayOfWeekAndTime() {
        // Wed = day 2 (Mon-origin), 14:30
        let mow = 2 * 1440 + 14 * 60 + 30
        let interval = FreeTimeInterval(id: UUID(), startMinuteOfWeek: mow, durationMinutes: 60)
        XCTAssertEqual(interval.startDayOfWeek, .wednesday)
        XCTAssertEqual(interval.startHour, 14)
        XCTAssertEqual(interval.startMinute, 30)
    }

    func testEndDayOfWeekAndTimeForWrappingInterval() {
        // Fri 22:00 → Sat 02:00
        let mow = 4 * 1440 + 22 * 60
        let interval = FreeTimeInterval(id: UUID(), startMinuteOfWeek: mow, durationMinutes: 4 * 60)
        XCTAssertEqual(interval.startDayOfWeek, .friday)
        XCTAssertEqual(interval.endDayOfWeek, .saturday)
        XCTAssertEqual(interval.endHour, 2)
        XCTAssertEqual(interval.endMinute, 0)
        XCTAssertTrue(interval.wrapsWeekBoundary == false) // wraps a day, not the week
    }

    func testWrapsWeekBoundary() {
        // Sun 22:00 → Mon 02:00 (wraps the week edge)
        let mow = 6 * 1440 + 22 * 60
        let interval = FreeTimeInterval(id: UUID(), startMinuteOfWeek: mow, durationMinutes: 4 * 60)
        XCTAssertTrue(interval.wrapsWeekBoundary)
    }

    // MARK: - Codable round-trip

    func testCodableRoundTrip() throws {
        let original = FreeTimeInterval(id: UUID(), startMinuteOfWeek: 1234, durationMinutes: 567)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(FreeTimeInterval.self, from: data)
        XCTAssertEqual(original, decoded)
    }
}
```

- [ ] **Step 2: Run the tests — expect compile failure**

Run from the project root:

```bash
xcodebuild -project Intentions.xcodeproj -scheme Intentions \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:IntentionsTests/FreeTimeIntervalTests \
  test-without-building 2>&1 | tail -10
```

Expected: compile failure because `FreeTimeInterval` does not exist yet.

- [ ] **Step 3: Create `FreeTimeInterval.swift`**

Create `Intentions/Models/FreeTimeInterval.swift`:

```swift
import Foundation

/// A contiguous block of free time on the weekly schedule.
/// Stored as a (start, duration) pair measured in minutes from Monday 00:00.
struct FreeTimeInterval: Identifiable, Codable, Hashable, Sendable {
    static let minutesPerDay = 24 * 60          // 1440
    static let minutesPerWeek = 7 * 24 * 60     // 10080

    let id: UUID
    /// 0..<10080. Monday 00:00 is 0.
    let startMinuteOfWeek: Int
    /// Strictly positive, max 10080 − 10.
    let durationMinutes: Int

    // MARK: - Containment

    /// Returns true if `minuteOfWeek` (0..<10080) falls inside this interval.
    /// End is exclusive. Wrap-around across the week boundary is supported.
    func contains(minuteOfWeek: Int) -> Bool {
        let end = startMinuteOfWeek + durationMinutes
        if end <= FreeTimeInterval.minutesPerWeek {
            return minuteOfWeek >= startMinuteOfWeek && minuteOfWeek < end
        } else {
            let wrappedEnd = end - FreeTimeInterval.minutesPerWeek
            return minuteOfWeek >= startMinuteOfWeek || minuteOfWeek < wrappedEnd
        }
    }

    /// Returns true if this interval shares any minute with `other`.
    func overlaps(_ other: FreeTimeInterval) -> Bool {
        // Treat each interval as a set of minutes and check for intersection.
        // Because intervals may wrap, walk a handful of candidate minutes: the four endpoints.
        return contains(minuteOfWeek: other.startMinuteOfWeek)
            || contains(minuteOfWeek: (other.startMinuteOfWeek + other.durationMinutes - 1) % FreeTimeInterval.minutesPerWeek)
            || other.contains(minuteOfWeek: startMinuteOfWeek)
            || other.contains(minuteOfWeek: (startMinuteOfWeek + durationMinutes - 1) % FreeTimeInterval.minutesPerWeek)
    }

    // MARK: - Derived day/time

    var startDayOfWeek: Weekday {
        Self.weekday(fromMondayDayIndex: startMinuteOfWeek / FreeTimeInterval.minutesPerDay)
    }

    var startHour: Int {
        (startMinuteOfWeek % FreeTimeInterval.minutesPerDay) / 60
    }

    var startMinute: Int {
        startMinuteOfWeek % 60
    }

    /// The minute-of-week of the final minute contained by this interval (inclusive).
    var lastMinuteOfWeek: Int {
        (startMinuteOfWeek + durationMinutes - 1) % FreeTimeInterval.minutesPerWeek
    }

    var endDayOfWeek: Weekday {
        Self.weekday(fromMondayDayIndex: lastMinuteOfWeek / FreeTimeInterval.minutesPerDay)
    }

    var endHour: Int {
        let endMinuteExclusive = (startMinuteOfWeek + durationMinutes) % FreeTimeInterval.minutesPerWeek
        return (endMinuteExclusive % FreeTimeInterval.minutesPerDay) / 60
    }

    var endMinute: Int {
        let endMinuteExclusive = (startMinuteOfWeek + durationMinutes) % FreeTimeInterval.minutesPerWeek
        return endMinuteExclusive % 60
    }

    /// True if the interval's extent crosses from Sunday back to Monday.
    var wrapsWeekBoundary: Bool {
        startMinuteOfWeek + durationMinutes > FreeTimeInterval.minutesPerWeek
    }

    // MARK: - Internal helpers

    /// Convert a 0..6 Monday-origin day index to a `Weekday` case.
    private static func weekday(fromMondayDayIndex index: Int) -> Weekday {
        switch index {
        case 0: return .monday
        case 1: return .tuesday
        case 2: return .wednesday
        case 3: return .thursday
        case 4: return .friday
        case 5: return .saturday
        case 6: return .sunday
        default: return .monday
        }
    }

    /// Convert a `Weekday` case to a 0..6 Monday-origin day index.
    static func mondayDayIndex(for weekday: Weekday) -> Int {
        switch weekday {
        case .monday: return 0
        case .tuesday: return 1
        case .wednesday: return 2
        case .thursday: return 3
        case .friday: return 4
        case .saturday: return 5
        case .sunday: return 6
        }
    }
}
```

- [ ] **Step 4: Run the tests — expect pass**

```bash
xcodebuild -project Intentions.xcodeproj -scheme Intentions \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:IntentionsTests/FreeTimeIntervalTests \
  test 2>&1 | tail -20
```

Expected: all 7 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add Intentions/Models/FreeTimeInterval.swift IntentionsTests/ModelTests/FreeTimeIntervalTests.swift
git commit -m "$(cat <<'EOF'
feat(model): add FreeTimeInterval struct with minute-of-week storage

TDD-first data model for the schedule redesign. Stores a single
free-time block as (startMinuteOfWeek, durationMinutes) with helpers
for containment, overlap, and derived day/time.
EOF
)"
```

---

## Task 2: `WeeklySchedule` class + evaluation methods

**Files:**
- Create: `Intentions/Models/WeeklySchedule.swift`
- Create: `IntentionsTests/ModelTests/WeeklyScheduleTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `IntentionsTests/ModelTests/WeeklyScheduleTests.swift`:

```swift
import XCTest
@testable import Intentions

@MainActor
final class WeeklyScheduleTests: XCTestCase {

    // MARK: - Test helpers

    /// 2024-01-01 is a Monday — offsets from there give deterministic weekdays.
    private func date(weekday: Weekday, hour: Int, minute: Int = 0) -> Date {
        let offset = FreeTimeInterval.mondayDayIndex(for: weekday)
        let calendar = Calendar.current
        let monday = calendar.date(from: DateComponents(year: 2024, month: 1, day: 1))!
        let day = calendar.date(byAdding: .day, value: offset, to: monday)!
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
    }

    private func interval(start day: Weekday, _ hour: Int, duration minutes: Int) -> FreeTimeInterval {
        let mow = FreeTimeInterval.mondayDayIndex(for: day) * 1440 + hour * 60
        return FreeTimeInterval(id: UUID(), startMinuteOfWeek: mow, durationMinutes: minutes)
    }

    // MARK: - isFreeTime

    func testIsFreeTimeWithSingleWeekdayInterval() {
        let schedule = WeeklySchedule()
        schedule.intervals = [interval(start: .monday, 9, duration: 8 * 60)] // Mon 09:00-17:00

        XCTAssertTrue(schedule.isFreeTime(at: date(weekday: .monday, hour: 10)))
        XCTAssertFalse(schedule.isFreeTime(at: date(weekday: .monday, hour: 18)))
        XCTAssertFalse(schedule.isFreeTime(at: date(weekday: .tuesday, hour: 10)))
    }

    func testIsFreeTimeWithWrappingInterval() {
        let schedule = WeeklySchedule()
        // Fri 22:00 → Sat 02:00
        schedule.intervals = [interval(start: .friday, 22, duration: 4 * 60)]

        XCTAssertTrue(schedule.isFreeTime(at: date(weekday: .friday, hour: 23)))
        XCTAssertTrue(schedule.isFreeTime(at: date(weekday: .saturday, hour: 1)))
        XCTAssertFalse(schedule.isFreeTime(at: date(weekday: .saturday, hour: 3)))
    }

    func testIsFreeTimeWhenDisabled() {
        let schedule = WeeklySchedule()
        schedule.intervals = [interval(start: .monday, 0, duration: 10080)] // all week
        schedule.isEnabled = false

        // Disabled schedule means blocking is off entirely — treat as "always free"
        XCTAssertTrue(schedule.isFreeTime(at: date(weekday: .monday, hour: 12)))
    }

    // MARK: - isBlocking

    func testIsBlockingIsInverseOfIsFreeTimeWhenEnabled() {
        let schedule = WeeklySchedule()
        schedule.intervals = [interval(start: .monday, 9, duration: 8 * 60)]

        XCTAssertFalse(schedule.isBlocking(at: date(weekday: .monday, hour: 10)))
        XCTAssertTrue(schedule.isBlocking(at: date(weekday: .monday, hour: 18)))
    }

    func testIsBlockingWhenDisabled() {
        let schedule = WeeklySchedule()
        schedule.isEnabled = false
        schedule.intervals = []
        XCTAssertFalse(schedule.isBlocking(at: date(weekday: .monday, hour: 10)))
    }

    // MARK: - protectedMinutes

    func testProtectedMinutesDaytimeWindow() {
        let schedule = WeeklySchedule()
        schedule.intervals = [interval(start: .monday, 9, duration: 8 * 60)] // Mon 09-17

        // Mon 20:00: 9h blocked morning + 3h blocked evening = 12h = 720
        XCTAssertEqual(schedule.protectedMinutes(at: date(weekday: .monday, hour: 20)), 12 * 60)
        // Mon 08:00: all 8h of morning blocked
        XCTAssertEqual(schedule.protectedMinutes(at: date(weekday: .monday, hour: 8)), 8 * 60)
        // Mon 12:00 (inside free window): 9h protected so far
        XCTAssertEqual(schedule.protectedMinutes(at: date(weekday: .monday, hour: 12)), 9 * 60)
    }

    func testProtectedMinutesOnDayWithNoFreeTime() {
        let schedule = WeeklySchedule()
        schedule.intervals = [interval(start: .monday, 9, duration: 8 * 60)]
        // Tuesday has no free time → entire elapsed day is blocked
        XCTAssertEqual(schedule.protectedMinutes(at: date(weekday: .tuesday, hour: 12)), 12 * 60)
    }

    // MARK: - nextBoundary

    func testNextBoundaryReturnsStartOfNextInterval() {
        let schedule = WeeklySchedule()
        schedule.intervals = [interval(start: .monday, 9, duration: 8 * 60)] // Mon 09-17

        let now = date(weekday: .monday, hour: 8)
        let next = schedule.nextBoundary(after: now)
        XCTAssertEqual(next, date(weekday: .monday, hour: 9))
    }

    func testNextBoundaryReturnsEndOfCurrentInterval() {
        let schedule = WeeklySchedule()
        schedule.intervals = [interval(start: .monday, 9, duration: 8 * 60)]

        let now = date(weekday: .monday, hour: 12)
        let next = schedule.nextBoundary(after: now)
        XCTAssertEqual(next, date(weekday: .monday, hour: 17))
    }

    func testNextBoundaryWrapsToFollowingWeek() {
        let schedule = WeeklySchedule()
        schedule.intervals = [interval(start: .monday, 9, duration: 8 * 60)]

        // Sun 20:00: no boundary left this week after this moment; wrap to next Mon 09:00
        let now = date(weekday: .sunday, hour: 20)
        let next = schedule.nextBoundary(after: now)
        XCTAssertNotNil(next)
        // The wrapped boundary should be 7 days − (19h) = 6 days 5h away approximately.
        // Easier assertion: the wall-clock hour of the returned date is 9.
        let hour = Calendar.current.component(.hour, from: next!)
        XCTAssertEqual(hour, 9)
    }

    func testNextBoundaryReturnsNilWhenDisabled() {
        let schedule = WeeklySchedule()
        schedule.isEnabled = false
        schedule.intervals = [interval(start: .monday, 9, duration: 8 * 60)]
        XCTAssertNil(schedule.nextBoundary(after: date(weekday: .monday, hour: 10)))
    }

    // MARK: - Codable round-trip

    func testCodableRoundTrip() throws {
        let original = WeeklySchedule()
        original.intervals = [
            interval(start: .monday, 9, duration: 8 * 60),
            interval(start: .friday, 22, duration: 4 * 60)
        ]
        original.intentionQuote = "Test"

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(WeeklySchedule.self, from: data)
        XCTAssertEqual(decoded.intervals.count, 2)
        XCTAssertEqual(decoded.intentionQuote, "Test")
        XCTAssertEqual(decoded.isEnabled, true)
    }
}
```

- [ ] **Step 2: Run tests — expect compile failure**

```bash
xcodebuild -project Intentions.xcodeproj -scheme Intentions \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:IntentionsTests/WeeklyScheduleTests \
  test-without-building 2>&1 | tail -10
```

Expected: `Cannot find 'WeeklySchedule' in scope`.

- [ ] **Step 3: Create `WeeklySchedule.swift`**

Create `Intentions/Models/WeeklySchedule.swift`:

```swift
import Foundation

@MainActor
@Observable
final class WeeklySchedule: @preconcurrency Codable {

    var isEnabled: Bool
    var intervals: [FreeTimeInterval]
    var timeZone: TimeZone
    var lastDisabledAt: Date?
    var intentionQuote: String?

    init() {
        self.isEnabled = true
        self.intervals = AppConstants.Schedule.defaultIntervals
        self.timeZone = TimeZone.current
        self.lastDisabledAt = nil
        self.intentionQuote = nil
    }

    // MARK: - Public API

    /// Returns true when the given date is inside any free-time interval.
    /// If the schedule is disabled, returns true unconditionally (blocking is off).
    func isFreeTime(at date: Date) -> Bool {
        guard isEnabled else { return true }
        let mow = minuteOfWeek(for: date)
        return intervals.contains { $0.contains(minuteOfWeek: mow) }
    }

    func isBlocking(at date: Date) -> Bool {
        guard isEnabled else { return false }
        return !isFreeTime(at: date)
    }

    /// Total minutes of blocking that have elapsed in the local calendar day of `date`, up to `date`.
    func protectedMinutes(at date: Date) -> Int {
        guard isEnabled else { return 0 }
        var calendar = Calendar.current
        calendar.timeZone = timeZone

        let startOfDay = calendar.startOfDay(for: date)
        let minuteOfDayNow = calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)

        var blocked = 0
        for offset in 0..<minuteOfDayNow {
            let probe = calendar.date(byAdding: .minute, value: offset, to: startOfDay)!
            if isBlocking(at: probe) {
                blocked += 1
            }
        }
        return blocked
    }

    /// Remaining minutes of blocking in the local calendar day of `date`, after `date`.
    func remainingProtectedMinutes(at date: Date) -> Int {
        guard isEnabled else { return 0 }
        var calendar = Calendar.current
        calendar.timeZone = timeZone
        let startOfDay = calendar.startOfDay(for: date)
        let minuteOfDayNow = calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)

        var blocked = 0
        for offset in minuteOfDayNow..<FreeTimeInterval.minutesPerDay {
            let probe = calendar.date(byAdding: .minute, value: offset, to: startOfDay)!
            if isBlocking(at: probe) {
                blocked += 1
            }
        }
        return blocked
    }

    /// The next wall-clock moment when `isBlocking(at:)` changes value, or `nil` if the schedule is disabled.
    func nextBoundary(after date: Date) -> Date? {
        guard isEnabled else { return nil }

        let calendar = calendarInScheduleTimezone()
        // Probe minute-by-minute over the next 7 days. 10_080 iterations is trivial.
        var probe = date
        let reference = isBlocking(at: date)
        for _ in 0..<FreeTimeInterval.minutesPerWeek {
            probe = calendar.date(byAdding: .minute, value: 1, to: probe)!
            if isBlocking(at: probe) != reference {
                return probe
            }
        }
        return nil
    }

    /// Days since the user last disabled blocking. Nil if never disabled.
    var streakDays: Int? {
        guard let lastDisabledAt else { return nil }
        let calendar = calendarInScheduleTimezone()
        let startOfLastDisable = calendar.startOfDay(for: lastDisabledAt)
        let startOfToday = calendar.startOfDay(for: Date())
        return calendar.dateComponents([.day], from: startOfLastDisable, to: startOfToday).day
    }

    // MARK: - Internal helpers

    /// Convert a wall-clock date to its minute-of-week (0..<10080) in `timeZone`.
    /// Monday is day 0.
    func minuteOfWeek(for date: Date) -> Int {
        let calendar = calendarInScheduleTimezone()
        // Normalise weekday so Monday=0. Foundation's calendar.weekday is Sun=1..Sat=7.
        let calendarWeekday = calendar.component(.weekday, from: date)
        let mondayZeroIndex: Int
        switch calendarWeekday {
        case 1: mondayZeroIndex = 6 // Sunday
        case 2: mondayZeroIndex = 0 // Monday
        case 3: mondayZeroIndex = 1
        case 4: mondayZeroIndex = 2
        case 5: mondayZeroIndex = 3
        case 6: mondayZeroIndex = 4
        case 7: mondayZeroIndex = 5 // Saturday
        default: mondayZeroIndex = 0
        }
        let hour = calendar.component(.hour, from: date)
        let minute = calendar.component(.minute, from: date)
        return mondayZeroIndex * FreeTimeInterval.minutesPerDay + hour * 60 + minute
    }

    private func calendarInScheduleTimezone() -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = timeZone
        c.firstWeekday = 2 // Monday; does not affect .weekday component but keeps intent explicit
        return c
    }

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case isEnabled, intervals, timeZone, lastDisabledAt, intentionQuote
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        isEnabled = try c.decode(Bool.self, forKey: .isEnabled)
        intervals = try c.decode([FreeTimeInterval].self, forKey: .intervals)
        let tzID = try c.decode(String.self, forKey: .timeZone)
        timeZone = TimeZone(identifier: tzID) ?? TimeZone.current
        lastDisabledAt = try c.decodeIfPresent(Date.self, forKey: .lastDisabledAt)
        intentionQuote = try c.decodeIfPresent(String.self, forKey: .intentionQuote)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(isEnabled, forKey: .isEnabled)
        try c.encode(intervals, forKey: .intervals)
        try c.encode(timeZone.identifier, forKey: .timeZone)
        try c.encodeIfPresent(lastDisabledAt, forKey: .lastDisabledAt)
        try c.encodeIfPresent(intentionQuote, forKey: .intentionQuote)
    }
}
```

Note: `AppConstants.Schedule.defaultIntervals` does not exist yet. Step 4 below adds it. If you run tests before Step 4 they will fail on this symbol.

- [ ] **Step 4: Update `AppConstants.Schedule` defaults**

Open `Intentions/Utilities/Constants.swift`, find the `Schedule` nested enum, and replace its `defaultStartHour / defaultStartMinute / defaultEndHour / defaultEndMinute` constants with a `defaultIntervals` computed property:

```swift
// MARK: - Schedule Settings
enum Schedule {
    /// Seed intervals for a brand-new install. Mon–Fri 17:00–21:30.
    static var defaultIntervals: [FreeTimeInterval] {
        (0...4).map { dayIndex in
            FreeTimeInterval(
                id: UUID(),
                startMinuteOfWeek: dayIndex * FreeTimeInterval.minutesPerDay + 17 * 60,
                durationMinutes: 4 * 60 + 30
            )
        }
    }

    static let validHourRange: ClosedRange<Int> = 0...23
    static let validMinuteRange: ClosedRange<Int> = 0...59
}
```

Delete the old `defaultStartHour`, `defaultStartMinute`, `defaultEndHour`, `defaultEndMinute` constants from the same enum. Do not delete `validHourRange` or `validMinuteRange` — they may still be referenced by the edit sheet.

- [ ] **Step 5: Run the tests — expect pass**

```bash
xcodebuild -project Intentions.xcodeproj -scheme Intentions \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:IntentionsTests/WeeklyScheduleTests \
  test 2>&1 | tail -30
```

Expected: all WeeklyScheduleTests PASS. Note that this will likely break `ScheduleSettingsTests` and other callers of the old default constants. Those breakages are expected — they get fixed in later tasks. Do not fix them now.

- [ ] **Step 6: Commit**

```bash
git add Intentions/Models/WeeklySchedule.swift \
        IntentionsTests/ModelTests/WeeklyScheduleTests.swift \
        Intentions/Utilities/Constants.swift
git commit -m "$(cat <<'EOF'
feat(model): add WeeklySchedule with isFreeTime, protectedMinutes, nextBoundary

Adds the replacement for ScheduleSettings as an @Observable class
holding a list of FreeTimeInterval. Evaluation methods convert wall
clock to minute-of-week and do an "any contains" check across
intervals (implicit union of overlaps).
EOF
)"
```

Note: the commit intentionally leaves the project build broken because other files still reference the old constants — subsequent tasks repair the breakage.

---

## Task 3: Migration helper from `ScheduleSettings` to `WeeklySchedule`

**Files:**
- Modify: `Intentions/Models/WeeklySchedule.swift`
- Create: `IntentionsTests/ModelTests/WeeklyScheduleMigrationTests.swift`

- [ ] **Step 1: Write failing tests**

Create `IntentionsTests/ModelTests/WeeklyScheduleMigrationTests.swift`:

```swift
import XCTest
@testable import Intentions

@MainActor
final class WeeklyScheduleMigrationTests: XCTestCase {

    func testMigrateWeekdaysOnlyDaytimeWindow() {
        let old = ScheduleSettings()
        old.isEnabled = true
        old.startHour = 9
        old.startMinute = 0
        old.endHour = 17
        old.endMinute = 0
        old.activeDays = [.monday, .tuesday, .wednesday, .thursday, .friday]

        let new = WeeklySchedule.migrate(from: old)

        XCTAssertTrue(new.isEnabled)
        XCTAssertEqual(new.intervals.count, 5)

        for interval in new.intervals {
            XCTAssertEqual(interval.durationMinutes, 8 * 60)
            XCTAssertEqual(interval.startHour, 9)
            XCTAssertEqual(interval.startMinute, 0)
        }
        let days = Set(new.intervals.map { $0.startDayOfWeek })
        XCTAssertEqual(days, [.monday, .tuesday, .wednesday, .thursday, .friday])
    }

    func testMigrateAllDaysDaytimeWindow() {
        let old = ScheduleSettings()
        old.startHour = 17
        old.startMinute = 0
        old.endHour = 21
        old.endMinute = 30
        old.activeDays = Set(Weekday.allCases)

        let new = WeeklySchedule.migrate(from: old)
        XCTAssertEqual(new.intervals.count, 7)
        XCTAssertTrue(new.intervals.allSatisfy { $0.durationMinutes == 4 * 60 + 30 })
    }

    func testMigrateOvernightWindowProducesOvernightPerDay() {
        let old = ScheduleSettings()
        old.startHour = 22
        old.startMinute = 0
        old.endHour = 6
        old.endMinute = 0
        old.activeDays = [.friday]

        let new = WeeklySchedule.migrate(from: old)
        XCTAssertEqual(new.intervals.count, 1)
        let i = new.intervals[0]
        XCTAssertEqual(i.startDayOfWeek, .friday)
        XCTAssertEqual(i.startHour, 22)
        XCTAssertEqual(i.durationMinutes, 8 * 60)
        XCTAssertEqual(i.endDayOfWeek, .saturday)
        XCTAssertEqual(i.endHour, 6)
    }

    func testMigrateDisabledScheduleCarriesFlag() {
        let old = ScheduleSettings()
        old.isEnabled = false
        old.activeDays = [.monday]
        old.startHour = 9
        old.endHour = 17

        let new = WeeklySchedule.migrate(from: old)
        XCTAssertFalse(new.isEnabled)
        XCTAssertEqual(new.intervals.count, 1)
    }

    func testMigrateEmptyActiveDaysProducesNoIntervals() {
        let old = ScheduleSettings()
        old.activeDays = []
        old.startHour = 9
        old.endHour = 17

        let new = WeeklySchedule.migrate(from: old)
        XCTAssertEqual(new.intervals.count, 0)
    }

    func testMigratePreservesIntentionQuoteAndLastDisabledAt() {
        let old = ScheduleSettings()
        old.activeDays = [.monday]
        old.startHour = 9
        old.endHour = 17
        old.intentionQuote = "Be present"
        old.lastDisabledAt = Date(timeIntervalSince1970: 1_700_000_000)

        let new = WeeklySchedule.migrate(from: old)
        XCTAssertEqual(new.intentionQuote, "Be present")
        XCTAssertEqual(new.lastDisabledAt, Date(timeIntervalSince1970: 1_700_000_000))
    }
}
```

- [ ] **Step 2: Run tests — expect compile failure**

Missing `WeeklySchedule.migrate(from:)`. Continue.

- [ ] **Step 3: Add `migrate(from:)` to `WeeklySchedule.swift`**

Append the following extension at the bottom of `Intentions/Models/WeeklySchedule.swift`:

```swift
// MARK: - Migration from legacy ScheduleSettings

extension WeeklySchedule {
    /// One-shot conversion of the legacy `ScheduleSettings` model to `WeeklySchedule`.
    /// Creates one `FreeTimeInterval` per day in `old.activeDays`, faithfully replaying
    /// overnight windows (start > end) as per-day cross-midnight intervals.
    static func migrate(from old: ScheduleSettings) -> WeeklySchedule {
        let schedule = WeeklySchedule()
        schedule.intervals = [] // overwrite the defaultIntervals seed
        schedule.isEnabled = old.isEnabled
        schedule.timeZone = old.timeZone
        schedule.lastDisabledAt = old.lastDisabledAt
        schedule.intentionQuote = old.intentionQuote

        let timeStart = old.startHour * 60 + old.startMinute
        let timeEnd = old.endHour * 60 + old.endMinute
        // Modulo-1440 so overnight windows keep their natural duration.
        let duration = ((timeEnd - timeStart) + FreeTimeInterval.minutesPerDay) % FreeTimeInterval.minutesPerDay
        guard duration >= 10 else { return schedule }

        // Sort for a stable order in tests.
        let sortedDays = old.activeDays.sorted { FreeTimeInterval.mondayDayIndex(for: $0) < FreeTimeInterval.mondayDayIndex(for: $1) }
        for day in sortedDays {
            let dayOrigin = FreeTimeInterval.mondayDayIndex(for: day) * FreeTimeInterval.minutesPerDay
            schedule.intervals.append(FreeTimeInterval(
                id: UUID(),
                startMinuteOfWeek: dayOrigin + timeStart,
                durationMinutes: duration
            ))
        }
        return schedule
    }
}
```

- [ ] **Step 4: Run tests — expect pass**

```bash
xcodebuild -project Intentions.xcodeproj -scheme Intentions \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:IntentionsTests/WeeklyScheduleMigrationTests \
  test 2>&1 | tail -20
```

Expected: all 6 migration tests PASS.

- [ ] **Step 5: Commit**

```bash
git add Intentions/Models/WeeklySchedule.swift \
        IntentionsTests/ModelTests/WeeklyScheduleMigrationTests.swift
git commit -m "feat(model): migrate legacy ScheduleSettings into WeeklySchedule"
```

---

## Task 4: Swap persistence layer to use `WeeklySchedule`

**Files:**
- Modify: `Intentions/Services/DataPersistenceService.swift`
- Modify: `Intentions/Protocols/DataPersisting.swift`
- Modify: `Intentions/Mocks/MockDataPersistenceService.swift`

- [ ] **Step 1: Read the protocol and find the old signatures**

```bash
rg -n "loadScheduleSettings|saveScheduleSettings" Intentions Intentions.xcodeproj/project.pbxproj IntentionsTests 2>&1 | head -40
```

You will see references in `DataPersisting.swift`, `DataPersistenceService.swift`, `MockDataPersistenceService.swift`, and tests. The existing signatures look like:

```swift
func loadScheduleSettings() async throws -> ScheduleSettings?
func saveScheduleSettings(_ settings: ScheduleSettings) async throws
```

- [ ] **Step 2: Add new methods alongside old ones in `DataPersisting`**

In `Intentions/Protocols/DataPersisting.swift`, keep the old method declarations and add:

```swift
func loadWeeklySchedule() async throws -> WeeklySchedule?
func saveWeeklySchedule(_ schedule: WeeklySchedule) async throws
```

- [ ] **Step 3: Implement the new methods in `DataPersistenceService`**

In `Intentions/Services/DataPersistenceService.swift`, implement the new methods. The load method prefers the new shape and falls back to reading the legacy `ScheduleSettings` blob for one-time migration:

```swift
func loadWeeklySchedule() async throws -> WeeklySchedule? {
    // Prefer the new blob.
    if let data = userDefaults.data(forKey: Self.weeklyScheduleKey) {
        return try JSONDecoder().decode(WeeklySchedule.self, from: data)
    }
    // Legacy fallback: migrate the old ScheduleSettings blob if present.
    if let legacyData = userDefaults.data(forKey: Self.scheduleSettingsKey) {
        let legacy = try JSONDecoder().decode(ScheduleSettings.self, from: legacyData)
        let migrated = WeeklySchedule.migrate(from: legacy)
        // Persist the migrated shape immediately so we don't run migration twice.
        let encoded = try JSONEncoder().encode(migrated)
        userDefaults.set(encoded, forKey: Self.weeklyScheduleKey)
        return migrated
    }
    return nil
}

func saveWeeklySchedule(_ schedule: WeeklySchedule) async throws {
    let data = try JSONEncoder().encode(schedule)
    userDefaults.set(data, forKey: Self.weeklyScheduleKey)
    // Clear the legacy blob so a future load doesn't re-migrate.
    userDefaults.removeObject(forKey: Self.scheduleSettingsKey)
}
```

Add `static let weeklyScheduleKey = "intentions.weeklySchedule"` next to the existing `scheduleSettingsKey` constant (whatever it is called — look at the existing file for the convention).

- [ ] **Step 4: Implement the new methods in `MockDataPersistenceService`**

In `Intentions/Mocks/MockDataPersistenceService.swift`, add an in-memory `weeklyScheduleStore: WeeklySchedule?` and implement:

```swift
func loadWeeklySchedule() async throws -> WeeklySchedule? {
    if shouldThrowError { throw errorToThrow }
    return weeklyScheduleStore
}

func saveWeeklySchedule(_ schedule: WeeklySchedule) async throws {
    if shouldThrowError { throw errorToThrow }
    weeklyScheduleStore = schedule
    saveWeeklyScheduleCalled = true
}
```

Add a `var saveWeeklyScheduleCalled = false` property next to the existing `saveScheduleSettingsCalled` if that exists. Do not delete the old mock state; tests may still reference it until later tasks.

- [ ] **Step 5: Build and make sure nothing broke in the services**

```bash
xcodebuild -project Intentions.xcodeproj -scheme Intentions \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  build 2>&1 | tail -30
```

Expected: the build should succeed for the Intent target. Any errors will likely be in `SettingsViewModel` or `ContentViewModel` because they still reference the old `scheduleSettings` property — those get fixed in Task 5.

If the build fails in the service layer (not in the view models), fix those errors before proceeding. Service-layer failures are Task 4 bugs.

- [ ] **Step 6: Commit**

```bash
git add Intentions/Protocols/DataPersisting.swift \
        Intentions/Services/DataPersistenceService.swift \
        Intentions/Mocks/MockDataPersistenceService.swift
git commit -m "feat(persistence): add WeeklySchedule load/save with legacy migration"
```

---

## Task 5: Rewire `SettingsViewModel` and `ContentViewModel`

**Files:**
- Modify: `Intentions/ViewModels/SettingsViewModel.swift`
- Modify: `Intentions/ViewModels/ContentViewModel.swift`

- [ ] **Step 1: Rename `scheduleSettings` → `weeklySchedule` in `SettingsViewModel`**

In `Intentions/ViewModels/SettingsViewModel.swift`:

1. Change the stored property from `var scheduleSettings: ScheduleSettings` to `var weeklySchedule: WeeklySchedule`.
2. Delete `formattedActiveHours` and `activeDaysText` computed properties — they no longer make sense against the new model.
3. Delete the now-unused `scheduleStatusText` and `scheduleStatusColor` computed properties if they reference the old shape (they do — leave them only if another view still reads them; `SettingsView` no longer does).
4. Add a new computed property:

```swift
var scheduleSummary: String {
    guard weeklySchedule.isEnabled else { return "Blocking is off" }
    let count = weeklySchedule.intervals.count
    switch count {
    case 0: return "No free time set"
    case 1:
        let i = weeklySchedule.intervals[0]
        return "\(i.startDayOfWeek.shortName) \(formattedTime(hour: i.startHour, minute: i.startMinute))–\(formattedTime(hour: i.endHour, minute: i.endMinute))"
    default:
        return "\(count) free time blocks"
    }
}

private func formattedTime(hour: Int, minute: Int) -> String {
    String(format: "%02d:%02d", hour, minute)
}
```

5. In `loadData()`, replace `try await dataService.loadScheduleSettings()` with `try await dataService.loadWeeklySchedule() ?? WeeklySchedule()`.
6. In `updateScheduleSettings(_:)`, rename to `updateSchedule(_ schedule: WeeklySchedule)` and update its body to call `dataService.saveWeeklySchedule(schedule)` instead.
7. Find `recordDisableAndToggle` and any other method that mutates `scheduleSettings` — update them to mutate `weeklySchedule` and call `saveWeeklySchedule`.

- [ ] **Step 2: Rewire `ContentViewModel`**

In `Intentions/ViewModels/ContentViewModel.swift`:

1. Change `var scheduleSettings: ScheduleSettings` to `var weeklySchedule: WeeklySchedule`.
2. Anywhere that reads `scheduleSettings.isCurrentlyActive`, replace with `weeklySchedule.isBlocking(at: Date())`.
3. Anywhere that reads `scheduleSettings.isEnabled`, leave the symbol name and just rename the receiver: `weeklySchedule.isEnabled`.
4. Rename `saveScheduleSettingsToUserDefaults(_:)` to `saveWeeklyScheduleToUserDefaults(_:)` and rewrite its body to persist the new keys:

```swift
private func saveWeeklyScheduleToUserDefaults(_ schedule: WeeklySchedule) {
    guard let sharedDefaults = UserDefaults(suiteName: AppConstants.appGroupId) else { return }

    sharedDefaults.set(schedule.isEnabled, forKey: AppConstants.Keys.scheduleIsEnabled)
    if let data = try? JSONEncoder().encode(schedule.intervals) {
        sharedDefaults.set(data, forKey: AppConstants.Keys.scheduleIntervalsData)
    }
    sharedDefaults.set(schedule.timeZone.identifier, forKey: AppConstants.Keys.scheduleTimeZoneId)
    sharedDefaults.synchronize()
}
```

5. Add `AppConstants.Keys.scheduleIntervalsData` and `AppConstants.Keys.scheduleTimeZoneId` in `Intentions/Utilities/Constants.swift` (find the existing `Keys` nested type). Delete the now-unused `scheduleStartHour`, `scheduleStartMinute`, `scheduleEndHour`, `scheduleEndMinute`, `scheduleActiveDays` keys while you are there.

6. Find `updateScheduleSettings(_:)` on `ContentViewModel` and rename/rewire to `updateWeeklySchedule(_ schedule: WeeklySchedule)`. Its body calls the new `dataService.saveWeeklySchedule`, persists to shared defaults via the renamed method, and still calls `applyDefaultBlocking()`.

- [ ] **Step 3: Build**

```bash
xcodebuild -project Intentions.xcodeproj -scheme Intentions \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  build 2>&1 | tail -40
```

Expected: the Intent main target builds clean. The tests target will still be broken (old `ScheduleSettingsTests` references removed symbols; `SettingsViewModelTests` references the old property name). Those are fixed in Tasks 9 and 14.

- [ ] **Step 4: Commit**

```bash
git add Intentions/ViewModels/SettingsViewModel.swift \
        Intentions/ViewModels/ContentViewModel.swift \
        Intentions/Utilities/Constants.swift
git commit -m "refactor(viewmodel): point Settings/Content view models at WeeklySchedule"
```

---

## Task 6: `HourColumn` and `DayColumn` SwiftUI subviews

**Files:**
- Create: `Intentions/Views/Settings/WeekGrid/HourColumn.swift`
- Create: `Intentions/Views/Settings/WeekGrid/DayColumn.swift`

(Create the `WeekGrid` subdirectory if it does not exist.)

- [ ] **Step 1: Write `HourColumn.swift`**

```swift
import SwiftUI

/// A narrow left-hand column showing 0 / 6 / 12 / 18 / 24 aligned with the horizontal gridlines.
struct HourColumn: View {
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topTrailing) {
                Color.clear
                hourLabel("0",  y: 0)
                hourLabel("6",  y: geo.size.height * 0.25)
                hourLabel("12", y: geo.size.height * 0.50)
                hourLabel("18", y: geo.size.height * 0.75)
                hourLabel("24", y: geo.size.height, alignBottom: true)
            }
        }
        .frame(width: 22)
    }

    @ViewBuilder
    private func hourLabel(_ text: String, y: CGFloat, alignBottom: Bool = false) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold))
            .foregroundColor(AppConstants.Colors.textSecondary)
            .monospacedDigit()
            .offset(y: alignBottom ? y - 9 : y - (y == 0 ? 0 : 4))
            .padding(.trailing, 2)
    }
}
```

- [ ] **Step 2: Write `DayColumn.swift`**

```swift
import SwiftUI

/// A single day's column in the week grid. Shows the base "blocked" fill plus any
/// free-time block rectangles belonging to this day.
struct DayColumn: View {
    let dayOfWeek: Weekday
    let renderedBlocks: [RenderedBlock]
    let selectedIntervalID: UUID?
    let onTapEmpty: (_ minuteOfDay: Int) -> Void
    let onTapBlock: (_ intervalID: UUID) -> Void
    let onEditBlock: (_ intervalID: UUID) -> Void
    let onDeleteBlock: (_ intervalID: UUID) -> Void

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(red: 0x1f/255, green: 0x1f/255, blue: 0x1f/255))

                // Block rectangles. BlockRect is defined in Task 7.
                ForEach(renderedBlocks) { block in
                    BlockRect(
                        block: block,
                        selected: block.intervalID == selectedIntervalID,
                        columnHeight: geo.size.height,
                        onTap: { onTapBlock(block.intervalID) },
                        onEdit: { onEditBlock(block.intervalID) },
                        onDelete: { onDeleteBlock(block.intervalID) }
                    )
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { point in
                // Resolve the tapped minute-of-day from the y coordinate.
                let normalized = max(0, min(1, point.y / geo.size.height))
                let minute = Int(normalized * CGFloat(FreeTimeInterval.minutesPerDay))
                let snapped = (minute / 10) * 10
                // Swallow taps that land on an existing block — they should hit that block's gesture.
                let hitsBlock = renderedBlocks.contains { block in
                    let start = CGFloat(block.startMinuteOfDay) / CGFloat(FreeTimeInterval.minutesPerDay) * geo.size.height
                    let end = CGFloat(block.endMinuteOfDay) / CGFloat(FreeTimeInterval.minutesPerDay) * geo.size.height
                    return point.y >= start && point.y <= end
                }
                guard !hitsBlock else { return }
                onTapEmpty(snapped)
            }
        }
    }
}

/// One segment of a `FreeTimeInterval` rendered in a specific day column.
struct RenderedBlock: Identifiable {
    let id = UUID()
    let intervalID: UUID
    /// 0..<1440
    let startMinuteOfDay: Int
    /// 0..<=1440; exclusive end.
    let endMinuteOfDay: Int
}
```

- [ ] **Step 3: Build**

```bash
xcodebuild -project Intentions.xcodeproj -scheme Intentions \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  build 2>&1 | tail -10
```

Expected: missing `BlockRect` — that's Task 7. Commit what exists and proceed.

- [ ] **Step 4: Commit**

```bash
git add Intentions/Views/Settings/WeekGrid/HourColumn.swift \
        Intentions/Views/Settings/WeekGrid/DayColumn.swift
git commit -m "feat(editor): add HourColumn and DayColumn subviews"
```

---

## Task 7: `BlockRect` subview + `HourGridOverlay`

**Files:**
- Create: `Intentions/Views/Settings/WeekGrid/BlockRect.swift`
- Create: `Intentions/Views/Settings/WeekGrid/HourGridOverlay.swift`

- [ ] **Step 1: Write `BlockRect.swift`**

```swift
import SwiftUI

struct BlockRect: View {
    let block: RenderedBlock
    let selected: Bool
    let columnHeight: CGFloat
    let onTap: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    private var topOffset: CGFloat {
        CGFloat(block.startMinuteOfDay) / CGFloat(FreeTimeInterval.minutesPerDay) * columnHeight
    }
    private var height: CGFloat {
        CGFloat(block.endMinuteOfDay - block.startMinuteOfDay) / CGFloat(FreeTimeInterval.minutesPerDay) * columnHeight
    }

    var body: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(Color.white.opacity(selected ? 0.6 : 0.4))
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .stroke(Color.white.opacity(selected ? 1.0 : 0), lineWidth: 2)
            )
            .padding(.horizontal, 2)
            .frame(height: max(height, 4))
            .offset(y: topOffset)
            .contentShape(Rectangle())
            .onTapGesture { onTap() }
            .contextMenu {
                Button {
                    onEdit()
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
    }
}
```

- [ ] **Step 2: Write `HourGridOverlay.swift`**

```swift
import SwiftUI

/// Seven horizontal tick lines drawn over the week grid at every 3 hours.
/// Uniform colour and stroke. Ignores pointer events.
struct HourGridOverlay: View {
    var body: some View {
        GeometryReader { geo in
            Canvas { context, size in
                let color = Color.white.opacity(0.3)
                for i in 1...7 {
                    let y = CGFloat(i) / 8.0 * size.height
                    var path = Path()
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: size.width, y: y))
                    context.stroke(path, with: .color(color), lineWidth: 1)
                }
            }
        }
        .allowsHitTesting(false)
    }
}
```

- [ ] **Step 3: Build**

```bash
xcodebuild -project Intentions.xcodeproj -scheme Intentions \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  build 2>&1 | tail -10
```

Expected: `DayColumn` now compiles because `BlockRect` exists. Full assembly still needs `WeekGridView` (Task 8).

- [ ] **Step 4: Commit**

```bash
git add Intentions/Views/Settings/WeekGrid/BlockRect.swift \
        Intentions/Views/Settings/WeekGrid/HourGridOverlay.swift
git commit -m "feat(editor): add BlockRect with contextMenu and HourGridOverlay"
```

---

## Task 8: `WeekGridView` — assemble the 7-day grid

**Files:**
- Create: `Intentions/Views/Settings/WeekGrid/WeekGridView.swift`

- [ ] **Step 1: Write `WeekGridView.swift`**

```swift
import SwiftUI

/// The full week grid: hour label column + 7 day columns + shared horizontal gridlines.
/// Emits tap / edit / delete events up to the parent editor view.
struct WeekGridView: View {
    let intervals: [FreeTimeInterval]
    let selectedIntervalID: UUID?
    let onTapEmpty: (_ day: Weekday, _ minuteOfDay: Int) -> Void
    let onTapBlock: (_ intervalID: UUID) -> Void
    let onEditBlock: (_ intervalID: UUID) -> Void
    let onDeleteBlock: (_ intervalID: UUID) -> Void

    private static let days: [Weekday] = [.monday, .tuesday, .wednesday, .thursday, .friday, .saturday, .sunday]

    var body: some View {
        VStack(spacing: 6) {
            // Header row — empty spacer over hour column, then 7 day labels.
            HStack(spacing: 4) {
                Color.clear.frame(width: 22)
                HStack(spacing: 4) {
                    ForEach(Self.days, id: \.self) { day in
                        Text(day.shortName.prefix(1).uppercased())
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(AppConstants.Colors.textSecondary)
                            .frame(maxWidth: .infinity)
                    }
                }
            }

            // Body: hour column + day columns + overlay.
            HStack(spacing: 4) {
                HourColumn()
                ZStack {
                    HStack(spacing: 4) {
                        ForEach(Self.days, id: \.self) { day in
                            DayColumn(
                                dayOfWeek: day,
                                renderedBlocks: renderedBlocks(for: day),
                                selectedIntervalID: selectedIntervalID,
                                onTapEmpty: { minute in onTapEmpty(day, minute) },
                                onTapBlock: onTapBlock,
                                onEditBlock: onEditBlock,
                                onDeleteBlock: onDeleteBlock
                            )
                            .frame(maxWidth: .infinity)
                        }
                    }
                    HourGridOverlay()
                }
            }
        }
    }

    // MARK: - Fanning intervals across day columns

    private func renderedBlocks(for day: Weekday) -> [RenderedBlock] {
        let dayIndex = FreeTimeInterval.mondayDayIndex(for: day)
        let dayStartMoW = dayIndex * FreeTimeInterval.minutesPerDay
        let dayEndMoW = dayStartMoW + FreeTimeInterval.minutesPerDay

        var result: [RenderedBlock] = []
        for interval in intervals {
            let segments = segments(for: interval, dayStartMoW: dayStartMoW, dayEndMoW: dayEndMoW)
            for (segStart, segEnd) in segments {
                result.append(RenderedBlock(
                    intervalID: interval.id,
                    startMinuteOfDay: segStart - dayStartMoW,
                    endMinuteOfDay: segEnd - dayStartMoW
                ))
            }
        }
        return result
    }

    /// Returns any `(startMoW, endMoW)` sub-ranges of `interval` that fall inside the given day.
    /// Handles wrap-around intervals that may include this day from a "previous" iteration.
    private func segments(for interval: FreeTimeInterval, dayStartMoW: Int, dayEndMoW: Int) -> [(Int, Int)] {
        let weekLen = FreeTimeInterval.minutesPerWeek
        let rawStart = interval.startMinuteOfWeek
        let rawEnd = interval.startMinuteOfWeek + interval.durationMinutes

        // Walk the two copies of the interval (current week and wrapped-into-next-week).
        var ranges: [(Int, Int)] = []
        if rawEnd <= weekLen {
            ranges.append((rawStart, rawEnd))
        } else {
            ranges.append((rawStart, weekLen))                  // tail of this week
            ranges.append((0, rawEnd - weekLen))                // head of next week, which maps back onto the same grid
        }

        var out: [(Int, Int)] = []
        for (rs, re) in ranges {
            let clippedStart = max(rs, dayStartMoW)
            let clippedEnd = min(re, dayEndMoW)
            if clippedStart < clippedEnd {
                out.append((clippedStart, clippedEnd))
            }
        }
        return out
    }
}
```

- [ ] **Step 2: Build**

```bash
xcodebuild -project Intentions.xcodeproj -scheme Intentions \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  build 2>&1 | tail -20
```

Expected: clean compile of the view files. No tests for this view — SwiftUI-only rendering is validated in the simulator in Task 10.

- [ ] **Step 3: Commit**

```bash
git add Intentions/Views/Settings/WeekGrid/WeekGridView.swift
git commit -m "feat(editor): assemble WeekGridView with cross-day block fanning"
```

---

## Task 9: `EditFreeTimeSheet` and `CopyToSheet`

**Files:**
- Create: `Intentions/Views/Settings/WeekGrid/EditFreeTimeSheet.swift`
- Create: `Intentions/Views/Settings/WeekGrid/CopyToSheet.swift`

- [ ] **Step 1: Write `EditFreeTimeSheet.swift`**

```swift
import SwiftUI

/// Edit-free-time modal sheet. Lets the user pick start/end day and time with a 10-minute snap.
struct EditFreeTimeSheet: View {
    @State var editing: DraftInterval
    let onConfirm: (DraftInterval) -> Void
    let onDelete: () -> Void
    let onCopyTo: (DraftInterval) -> Void

    private static let days: [Weekday] = [.monday, .tuesday, .wednesday, .thursday, .friday, .saturday, .sunday]

    var body: some View {
        VStack(spacing: 0) {
            handle
            Text("Edit Free Time")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(AppConstants.Colors.text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.bottom, 12)

            pickerRow(label: "Starts", day: $editing.startDay, hour: $editing.startHour, minute: $editing.startMinute)
            Divider().overlay(AppConstants.Colors.textSecondary.opacity(0.3))
            pickerRow(label: "Ends", day: $editing.endDay, hour: $editing.endHour, minute: $editing.endMinute)

            HStack(spacing: 8) {
                Button(action: { onCopyTo(editing) }) {
                    Text("Copy to…")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.bordered)

                Button(action: onDelete) {
                    Text("Delete")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.bordered)
                .tint(AppConstants.Colors.textSecondary)
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)

            Button(action: {
                if isValid { onConfirm(editing) }
            }) {
                Text("Confirm")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(Color(red: 0x0a/255, green: 0x0a/255, blue: 0x0a/255))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(RoundedRectangle(cornerRadius: 12).fill(AppConstants.Colors.text))
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 24)
            .disabled(!isValid)
            .opacity(isValid ? 1 : 0.4)
        }
        .background(Color(red: 0x16/255, green: 0x16/255, blue: 0x16/255))
    }

    private var handle: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(Color.white.opacity(0.3))
            .frame(width: 36, height: 4)
            .padding(.top, 10)
            .padding(.bottom, 14)
    }

    private func pickerRow(label: String, day: Binding<Weekday>, hour: Binding<Int>, minute: Binding<Int>) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 14))
                .foregroundColor(AppConstants.Colors.text)
            Spacer()
            Menu {
                ForEach(Self.days, id: \.self) { d in
                    Button(d.displayName) { day.wrappedValue = d }
                }
            } label: {
                Text(day.wrappedValue.displayName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(AppConstants.Colors.text)
            }
            Text("·").foregroundColor(AppConstants.Colors.textSecondary.opacity(0.45))
            DatePicker("", selection: bindingForTime(hour: hour, minute: minute), displayedComponents: .hourAndMinute)
                .labelsHidden()
                .datePickerStyle(.compact)
                .environment(\.locale, Locale(identifier: "en_GB_POSIX"))
                .frame(maxWidth: 90)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 11)
    }

    private func bindingForTime(hour: Binding<Int>, minute: Binding<Int>) -> Binding<Date> {
        Binding<Date>(
            get: {
                Calendar.current.date(bySettingHour: hour.wrappedValue, minute: minute.wrappedValue, second: 0, of: Date()) ?? Date()
            },
            set: { newDate in
                let comps = Calendar.current.dateComponents([.hour, .minute], from: newDate)
                hour.wrappedValue = comps.hour ?? 0
                // Snap minute to the nearest 10-minute increment.
                let m = comps.minute ?? 0
                minute.wrappedValue = (Int((Double(m) / 10).rounded()) * 10) % 60
            }
        )
    }

    private var isValid: Bool {
        editing.durationMinutes >= 10 && editing.durationMinutes <= FreeTimeInterval.minutesPerWeek - 10
    }
}

/// Mutable draft used inside the edit sheet. Converts to/from `FreeTimeInterval`.
struct DraftInterval: Equatable, Identifiable {
    var id: UUID
    var startDay: Weekday
    var startHour: Int
    var startMinute: Int
    var endDay: Weekday
    var endHour: Int
    var endMinute: Int

    init(from interval: FreeTimeInterval) {
        self.id = interval.id
        self.startDay = interval.startDayOfWeek
        self.startHour = interval.startHour
        self.startMinute = interval.startMinute
        self.endDay = interval.endDayOfWeek
        self.endHour = interval.endHour
        self.endMinute = interval.endMinute
    }

    func toInterval() -> FreeTimeInterval {
        let startMoW = FreeTimeInterval.mondayDayIndex(for: startDay) * FreeTimeInterval.minutesPerDay + startHour * 60 + startMinute
        let endMoW = FreeTimeInterval.mondayDayIndex(for: endDay) * FreeTimeInterval.minutesPerDay + endHour * 60 + endMinute
        let duration = ((endMoW - startMoW) + FreeTimeInterval.minutesPerWeek) % FreeTimeInterval.minutesPerWeek
        return FreeTimeInterval(id: id, startMinuteOfWeek: startMoW, durationMinutes: duration)
    }

    var durationMinutes: Int {
        toInterval().durationMinutes
    }
}
```

- [ ] **Step 2: Write `CopyToSheet.swift`**

```swift
import SwiftUI

struct CopyToSheet: View {
    let source: DraftInterval
    @State private var selectedDays: Set<Weekday> = []
    let onCopy: (_ days: Set<Weekday>) -> Void

    private static let days: [Weekday] = [.monday, .tuesday, .wednesday, .thursday, .friday, .saturday, .sunday]

    var body: some View {
        VStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.white.opacity(0.3))
                .frame(width: 36, height: 4)
                .padding(.top, 10)
                .padding(.bottom, 14)

            Text("Copy To")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(AppConstants.Colors.text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.bottom, 12)

            HStack(spacing: 8) {
                ForEach(Self.days, id: \.self) { day in
                    Button(action: { toggle(day) }) {
                        Text(day.shortName.prefix(1).uppercased())
                            .font(.system(size: 14, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .aspectRatio(1, contentMode: .fit)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(selectedDays.contains(day) ? AppConstants.Colors.text : AppConstants.Colors.surface)
                            )
                            .foregroundColor(selectedDays.contains(day) ? Color(red: 0x0a/255, green: 0x0a/255, blue: 0x0a/255) : AppConstants.Colors.textSecondary)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(AppConstants.Colors.textSecondary.opacity(0.12), lineWidth: 1)
                            )
                    }
                }
            }
            .padding(.horizontal, 20)

            Button(action: { onCopy(selectedDays) }) {
                Text("Copy")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(Color(red: 0x0a/255, green: 0x0a/255, blue: 0x0a/255))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(RoundedRectangle(cornerRadius: 12).fill(AppConstants.Colors.text))
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 24)
            .disabled(selectedDays.isEmpty)
            .opacity(selectedDays.isEmpty ? 0.4 : 1)
        }
        .background(Color(red: 0x16/255, green: 0x16/255, blue: 0x16/255))
    }

    private func toggle(_ day: Weekday) {
        if selectedDays.contains(day) {
            selectedDays.remove(day)
        } else {
            selectedDays.insert(day)
        }
    }
}
```

- [ ] **Step 3: Build**

```bash
xcodebuild -project Intentions.xcodeproj -scheme Intentions \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  build 2>&1 | tail -20
```

Expected: clean compile.

- [ ] **Step 4: Commit**

```bash
git add Intentions/Views/Settings/WeekGrid/EditFreeTimeSheet.swift \
        Intentions/Views/Settings/WeekGrid/CopyToSheet.swift
git commit -m "feat(editor): add EditFreeTimeSheet and CopyToSheet modals"
```

---

## Task 10: `WeekScheduleEditorView` — top-level screen

**Files:**
- Create: `Intentions/Views/Settings/WeekGrid/WeekScheduleEditorView.swift`

- [ ] **Step 1: Write `WeekScheduleEditorView.swift`**

```swift
import SwiftUI

struct WeekScheduleEditorView: View {
    @State private var editing: WeeklySchedule
    @State private var selectedIntervalID: UUID?
    @State private var draftForEdit: DraftInterval?
    @State private var draftForCopy: DraftInterval?

    let onSave: (WeeklySchedule) -> Void
    let onCancel: () -> Void

    init(schedule: WeeklySchedule,
         onSave: @escaping (WeeklySchedule) -> Void,
         onCancel: @escaping () -> Void) {
        // Deep copy via codable round-trip so the caller's schedule isn't mutated until Save.
        let data = (try? JSONEncoder().encode(schedule)) ?? Data()
        let copy = (try? JSONDecoder().decode(WeeklySchedule.self, from: data)) ?? WeeklySchedule()
        _editing = State(wrappedValue: copy)
        self.onSave = onSave
        self.onCancel = onCancel
    }

    var body: some View {
        NavigationStack {
            WeekGridView(
                intervals: editing.intervals,
                selectedIntervalID: selectedIntervalID,
                onTapEmpty: handleTapEmpty,
                onTapBlock: handleTapBlock,
                onEditBlock: handleEditBlock,
                onDeleteBlock: handleDeleteBlock
            )
            .padding(.horizontal, 12)
            .padding(.top, 4)
            .padding(.bottom, 24)
            .background(AppConstants.Colors.background)
            .navigationTitle("Free Time")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { onCancel() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") { onSave(editing) }
                        .fontWeight(.semibold)
                }
            }
        }
        .sheet(item: $draftForEdit) { draft in
            EditFreeTimeSheet(
                editing: draft,
                onConfirm: { updated in
                    commitEditedInterval(updated)
                    draftForEdit = nil
                },
                onDelete: {
                    deleteInterval(id: draft.id)
                    draftForEdit = nil
                },
                onCopyTo: { current in
                    draftForEdit = nil
                    draftForCopy = current
                }
            )
            .presentationDetents([.medium])
        }
        .sheet(item: $draftForCopy) { draft in
            CopyToSheet(
                source: draft,
                onCopy: { targets in
                    copyIntervalToDays(source: draft, targets: targets)
                    draftForCopy = nil
                }
            )
            .presentationDetents([.medium])
        }
    }

    // MARK: - Gesture handlers

    private func handleTapEmpty(day: Weekday, minuteOfDay: Int) {
        // Create a new 1-hour block at the tapped day/minute.
        let mow = FreeTimeInterval.mondayDayIndex(for: day) * FreeTimeInterval.minutesPerDay + minuteOfDay
        let newInterval = FreeTimeInterval(id: UUID(), startMinuteOfWeek: mow, durationMinutes: 60)
        editing.intervals.append(newInterval)
        selectedIntervalID = newInterval.id
        draftForEdit = DraftInterval(from: newInterval)
    }

    private func handleTapBlock(_ id: UUID) {
        guard let interval = editing.intervals.first(where: { $0.id == id }) else { return }
        selectedIntervalID = id
        draftForEdit = DraftInterval(from: interval)
    }

    private func handleEditBlock(_ id: UUID) {
        handleTapBlock(id)
    }

    private func handleDeleteBlock(_ id: UUID) {
        editing.intervals.removeAll { $0.id == id }
        if selectedIntervalID == id { selectedIntervalID = nil }
    }

    private func commitEditedInterval(_ draft: DraftInterval) {
        let updated = draft.toInterval()
        if let idx = editing.intervals.firstIndex(where: { $0.id == draft.id }) {
            editing.intervals[idx] = updated
        } else {
            editing.intervals.append(updated)
        }
        selectedIntervalID = updated.id
    }

    private func deleteInterval(id: UUID) {
        editing.intervals.removeAll { $0.id == id }
        if selectedIntervalID == id { selectedIntervalID = nil }
    }

    private func copyIntervalToDays(source: DraftInterval, targets: Set<Weekday>) {
        let sourceInterval = source.toInterval()
        let sourceDayIndex = FreeTimeInterval.mondayDayIndex(for: sourceInterval.startDayOfWeek)
        let timeOfDayStart = sourceInterval.startMinuteOfWeek - sourceDayIndex * FreeTimeInterval.minutesPerDay

        for target in targets {
            let dayIndex = FreeTimeInterval.mondayDayIndex(for: target)
            let newMoW = dayIndex * FreeTimeInterval.minutesPerDay + timeOfDayStart
            editing.intervals.append(FreeTimeInterval(
                id: UUID(),
                startMinuteOfWeek: newMoW,
                durationMinutes: sourceInterval.durationMinutes
            ))
        }
    }
}

```

- [ ] **Step 2: Build and make sure everything compiles**

```bash
xcodebuild -project Intentions.xcodeproj -scheme Intentions \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  build 2>&1 | tail -30
```

Expected: the target builds. Warnings about unused properties are OK.

- [ ] **Step 3: Commit**

```bash
git add Intentions/Views/Settings/WeekGrid/WeekScheduleEditorView.swift
git commit -m "feat(editor): add WeekScheduleEditorView with tap/edit/copy/delete flow"
```

---

## Task 11: Swap `ScheduleSettingsView` for `WeekScheduleEditorView` in `SettingsView`

**Files:**
- Modify: `Intentions/Views/Settings/SettingsView.swift`

- [ ] **Step 1: Update the sheet presentation**

In `Intentions/Views/Settings/SettingsView.swift`, find the `.sheet(isPresented: $viewModel.showingScheduleEditor)` block. Replace its body:

```swift
.sheet(isPresented: $viewModel.showingScheduleEditor) {
    WeekScheduleEditorView(
        schedule: viewModel.weeklySchedule,
        onSave: { updated in
            Task {
                await viewModel.updateSchedule(updated)
                await onScheduleSettingsChanged?(updated)
            }
            viewModel.hideScheduleEditor()
        },
        onCancel: { viewModel.hideScheduleEditor() }
    )
}
```

Also update the `onScheduleSettingsChanged` closure type in the `SettingsView` init (and the corresponding call sites) from `((ScheduleSettings) async -> Void)?` to `((WeeklySchedule) async -> Void)?`. Follow the compiler errors until both the init and the caller (`ContentView.swift` or wherever `SettingsView` is instantiated) agree.

- [ ] **Step 2: Update the "Free Time" row subtitle to use `scheduleSummary`**

Inside `freeTimeRow` in `SettingsView.swift`, replace the two-line value stack (`formattedActiveHours` + `activeDaysText`) with a single-line reading of `viewModel.scheduleSummary`:

```swift
VStack(alignment: .trailing, spacing: 2) {
    Text(viewModel.scheduleSummary)
        .font(.subheadline)
        .foregroundColor(valueColor)
        .multilineTextAlignment(.trailing)
        .lineLimit(2)
}
```

Delete the secondary-line `Text(viewModel.activeDaysText)` and surrounding `spacing` tweak.

- [ ] **Step 3: Build and run in simulator**

```bash
xcodebuild -project Intentions.xcodeproj -scheme Intentions \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  build 2>&1 | tail -20
```

Then launch in a simulator and verify manually:

1. Open Settings tab. The "Free Time" row shows the summary.
2. Tap the row — new editor opens with Mon–Fri 17:00–21:30 blocks visible.
3. Tap an empty area — a new 1-hour block appears, edit sheet opens.
4. Confirm the new block — sheet dismisses, block visible.
5. Tap an existing block — edit sheet re-opens.
6. Long-press a block — context menu appears with Edit / Delete.
7. Delete a block via the context menu — block disappears.
8. Tap Copy to… on an edit sheet — copy sheet opens, select 2 days, tap Copy, confirm new blocks appear.
9. Tap Save — editor dismisses, settings row summary updates.
10. Re-open the editor — the saved state persists.

If any of these fail, fix before the commit.

- [ ] **Step 4: Commit**

```bash
git add Intentions/Views/Settings/SettingsView.swift
git commit -m "feat(settings): present WeekScheduleEditorView from Free Time row"
```

---

## Task 12: Update `DeviceActivityMonitorExtension` to read the new shape

**Files:**
- Modify: `IntentionsDeviceActivityMonitor/DeviceActivityMonitorExtension.swift`

- [ ] **Step 1: Rewrite `isCurrentlyInProtectedHours`**

The extension reads persisted schedule data from shared UserDefaults and decides whether to block. Replace `isCurrentlyInProtectedHours(sharedDefaults:)` with a version that decodes the interval list:

```swift
private func isCurrentlyInProtectedHours(sharedDefaults: UserDefaults) -> Bool {
    let isEnabled = sharedDefaults.bool(forKey: "intentions.schedule.isEnabled")
    guard isEnabled else {
        logger.info("📅 SCHEDULE CHECK: Schedule is disabled - not blocking")
        return false
    }

    guard let data = sharedDefaults.data(forKey: "intentions.schedule.intervalsData"),
          let intervals = try? JSONDecoder().decode([FreeTimeIntervalLite].self, from: data) else {
        logger.info("📅 SCHEDULE CHECK: No intervals data — defaulting to blocking")
        return true
    }

    let tzID = sharedDefaults.string(forKey: "intentions.schedule.timeZoneId") ?? TimeZone.current.identifier
    let tz = TimeZone(identifier: tzID) ?? TimeZone.current

    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = tz
    let now = Date()
    let mow = Self.minuteOfWeek(date: now, calendar: calendar)

    let inFree = intervals.contains { interval in
        let start = interval.startMinuteOfWeek
        let end = start + interval.durationMinutes
        if end <= 10080 {
            return mow >= start && mow < end
        } else {
            return mow >= start || mow < (end - 10080)
        }
    }
    return !inFree
}

/// Minimal mirror of FreeTimeInterval so the extension target does not have to import the main target.
private struct FreeTimeIntervalLite: Codable {
    let id: UUID
    let startMinuteOfWeek: Int
    let durationMinutes: Int
}

private static func minuteOfWeek(date: Date, calendar: Calendar) -> Int {
    let calendarWeekday = calendar.component(.weekday, from: date)
    let mondayZero: Int
    switch calendarWeekday {
    case 1: mondayZero = 6
    case 2: mondayZero = 0
    case 3: mondayZero = 1
    case 4: mondayZero = 2
    case 5: mondayZero = 3
    case 6: mondayZero = 4
    case 7: mondayZero = 5
    default: mondayZero = 0
    }
    let hour = calendar.component(.hour, from: date)
    let minute = calendar.component(.minute, from: date)
    return mondayZero * 1440 + hour * 60 + minute
}
```

Delete any now-unused branch that read `scheduleStartHour` / `scheduleEndHour` / `scheduleActiveDays`.

- [ ] **Step 2: Build**

```bash
xcodebuild -project Intentions.xcodeproj -scheme Intentions \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  build 2>&1 | tail -20
```

Expected: target builds cleanly including the extension.

- [ ] **Step 3: Commit**

```bash
git add IntentionsDeviceActivityMonitor/DeviceActivityMonitorExtension.swift
git commit -m "feat(extension): read WeeklySchedule intervals from shared defaults"
```

---

## Task 13: Scene-phase catch-up for shield sync

**Files:**
- Modify: `Intentions/App/ContentView.swift` (or the file that owns the root `SceneView`)
- Modify: `Intentions/ViewModels/ContentViewModel.swift`

- [ ] **Step 1: Add a scenePhase observer in the root view**

In the file that constructs the root view (likely `ContentView.swift` or `IntentionsApp.swift`), add:

```swift
@Environment(\.scenePhase) private var scenePhase
```

And an `.onChange(of: scenePhase)` modifier on the root body:

```swift
.onChange(of: scenePhase) { _, newPhase in
    if newPhase == .active {
        Task { await contentViewModel.reconcileBlockingOnForeground() }
    }
}
```

- [ ] **Step 2: Implement `reconcileBlockingOnForeground` on `ContentViewModel`**

In `Intentions/ViewModels/ContentViewModel.swift`, add:

```swift
/// Called when the app becomes active. Re-applies the blocking state so the physical
/// shield matches the schedule even if iOS has been sitting on a stale state.
func reconcileBlockingOnForeground() async {
    await applyDefaultBlocking()
}
```

`applyDefaultBlocking` already exists and handles the active-session preservation path. No further rewiring needed for the scene-phase catch-up layer.

- [ ] **Step 3: Build and verify manually**

Build the app and run it. Open a schedule where "now" is inside a free-time window, close the app, wait until the free-time window ends, then reopen the app. The apps you had allowed should now be blocked.

(If you cannot wait the full duration, force-change the schedule so the current moment transitions states mid-test: save a schedule with a 5-minute free window that ends in the next minute, background the app, wait, and reopen.)

- [ ] **Step 4: Commit**

```bash
git add Intentions/App/ContentView.swift \
        Intentions/ViewModels/ContentViewModel.swift
git commit -m "fix(blocking): reconcile shield state on scenePhase .active"
```

---

## Task 14: Update existing tests and delete the old model

**Files:**
- Delete: `Intentions/Models/ScheduleSettings.swift`
- Delete: `IntentionsTests/ModelTests/ScheduleSettingsTests.swift`
- Modify: `IntentionsTests/ViewModels/SettingsViewModelTests.swift`
- Modify: `IntentionsTests/Integration/SettingsIntegrationTests.swift`

- [ ] **Step 1: Update `SettingsViewModelTests`**

Open the file and rename every occurrence of `scheduleSettings` to `weeklySchedule`. Replace `testDefaultScheduleSettings` with:

```swift
func testDefaultWeeklySchedule() {
    XCTAssertTrue(viewModel.weeklySchedule.isEnabled)
    XCTAssertEqual(viewModel.weeklySchedule.intervals.count, 5) // Mon-Fri seed
    XCTAssertTrue(viewModel.weeklySchedule.intervals.allSatisfy { $0.durationMinutes == 4 * 60 + 30 })
}
```

Delete `testFormattedActiveHours` and `testActiveDaysText` (the methods they tested no longer exist).

- [ ] **Step 2: Update `SettingsIntegrationTests`**

Any assertion involving `activeDaysText`, `formattedActiveHours`, or old `scheduleSettings.activeHours` setter syntax → replace with equivalent assertions against `weeklySchedule.intervals`. Where the old tests constructed a synthetic schedule via `settings.activeHours = 9...17`, replace with:

```swift
viewModel.weeklySchedule.intervals = [
    FreeTimeInterval(id: UUID(), startMinuteOfWeek: 9 * 60, durationMinutes: 8 * 60)
]
```

- [ ] **Step 3: Delete the old files**

```bash
git rm Intentions/Models/ScheduleSettings.swift \
       IntentionsTests/ModelTests/ScheduleSettingsTests.swift
```

- [ ] **Step 4: Build + run the full test suite**

```bash
xcodebuild -project Intentions.xcodeproj -scheme Intentions \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  test 2>&1 | tail -40
```

Expected: everything builds and all tests pass. Fix any leftover references to `ScheduleSettings` until the test run is green.

- [ ] **Step 5: Commit**

```bash
git add -u Intentions IntentionsTests
git commit -m "$(cat <<'EOF'
refactor: delete ScheduleSettings, migrate tests to WeeklySchedule

The legacy ScheduleSettings model and its editor are replaced by
WeeklySchedule + FreeTimeInterval + WeekScheduleEditorView. All
callers and tests are ported; the migration helper still reads the
legacy persisted blob so existing users' schedules carry over.
EOF
)"
```

---

## Task 15: Manual end-to-end verification

**No files modified. This is a checklist you walk through in the running simulator before closing the plan.**

- [ ] **Step 1: Fresh-install flow**

Delete the app from the simulator. Build and run. Walk through the setup flow and verify the Settings tab shows the default Mon-Fri 17:00-21:30 schedule reflected in the summary row.

- [ ] **Step 2: Editor round-trip**

1. Open the editor, tap an existing block, change start to Mon 15:00, Confirm.
2. Tap Save.
3. Re-open the editor. The change should be visible.

- [ ] **Step 3: Cross-day block**

1. Open the editor. Tap the Friday column at ~22:00 area. A new block appears, edit sheet opens.
2. Change end to Saturday 02:00. Confirm.
3. Save. Re-open. The block should render as two visible segments (Fri 22-24, Sat 0-2) with gridlines passing through both.

- [ ] **Step 4: Long-press Delete**

1. Open editor. Long-press any block. Context menu shows Edit / Delete.
2. Tap Delete. The block vanishes.
3. Save, re-open. The block stays gone.

- [ ] **Step 5: Copy to other days**

1. Open editor. Tap a Monday block, tap "Copy to…".
2. Select Tue, Wed, Thu. Tap Copy.
3. Confirm those days now show the same block shape.
4. Save, re-open. Persistence confirmed.

- [ ] **Step 6: Migration from legacy**

If possible on a device or simulator with a prior install, verify that the app boot reads an old `ScheduleSettings` blob and migrates to the new shape without crashing. (If no device has the old install available, seed a UserDefaults dict manually via `xcrun simctl` and re-run.)

- [ ] **Step 7: Shield scene-phase catch-up**

1. Set a schedule whose next boundary falls 2 minutes in the future.
2. Background the app. Wait 3 minutes across the boundary.
3. Re-open. Confirm the shield state matches the new side of the boundary (e.g. if blocking just turned ON, the apps should now be blocked).

- [ ] **Step 8: Close plan**

Update the plan file with any discovered issues. If there are follow-ups that are out of scope for this plan (e.g. DeviceActivity boundary events), add them to the project notes in `.project-notes/tasks.md`.

---

## Out of scope follow-ups (not in this plan)

- DeviceActivity boundary events for full shield sync (separate spec).
- One-off date-anchored exceptions (option D from brainstorming — deferred).
- Drag-to-resize blocks in the grid.
- Calendar view of historic protected-hour stats.
- Per-app scheduling.
