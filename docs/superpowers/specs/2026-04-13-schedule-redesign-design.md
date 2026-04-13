# Schedule Redesign — Week Grid Editor + Cross-Day Free Time Intervals

## Summary

Replace the current `ScheduleSettings` single-window-plus-`activeDays` model with a list of `FreeTimeInterval` records that can span day boundaries. Replace `ScheduleSettingsView` with a week grid editor where the user taps to add blocks, taps or long-presses to edit/delete, and copies blocks to other days. Move free-time boundary enforcement off app-launch triggers and onto scheduled events so the physical shield state matches the model state without requiring the app to be foregrounded.

## Background

Today `ScheduleSettings` stores one free-time window (`startHour/startMinute` → `endHour/endMinute`) and applies it to a set of `activeDays`. Consequences that motivated this redesign:

- Cannot express different windows on different days.
- Cannot express multiple windows within one day.
- Cannot express a continuous interval that crosses midnight — each moment is evaluated against its own weekday's `activeDays` membership, so a Fri-night free window evaporates at Sat 00:00 if Sat is not in `activeDays`. The user expects the block to run continuously.
- `applyDefaultBlocking` only runs on app init, schedule save, and session start/end/expire. Free-time boundaries do not fire re-evaluations, so the shield state lags the model by hours whenever the app is backgrounded across a boundary.

The brainstorming session converged on: a tap-to-create 7-day × 24-hour week grid editor, an edit sheet with day + time pickers on both endpoints, a Copy sheet for duplicating a block to other days, blocks rendered as translucent white overlays at 40% alpha with uniform 3-hour horizontal gridlines. All mockups are in `.superpowers/brainstorm/` and mirrored to `designs.kieranhitchcock.com`.

Final visual reference: <https://designs.kieranhitchcock.com/intent-schedule-week-grid-v7/>

## Data Model

### `FreeTimeInterval`

```swift
struct FreeTimeInterval: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    /// Minute-of-week, measured from Monday 00:00. Range 0..<10080.
    let startMinuteOfWeek: Int
    /// Strictly positive. Max 10080 − 10 (one week minus one 10-minute tick).
    let durationMinutes: Int
}
```

Rationale for minute-of-week + duration:

- Single integer pair → trivial overlap / containment / boundary math.
- Wrap-around ("Sun 22:00 → Mon 02:00") is natural via `(startMinuteOfWeek + durationMinutes) % 10080`.
- 10-minute snap enforced at edit time; storage keeps minute precision so future UX changes don't need a migration.
- `Identifiable` makes SwiftUI `ForEach` + diffing straightforward on the editor.

Derived properties for the UI and evaluation code:

```swift
var startDayOfWeek: Weekday
var startHour: Int
var startMinute: Int
var endDayOfWeek: Weekday           // day containing the final rendered minute
var endHour: Int
var endMinute: Int
var wrapsWeekBoundary: Bool
func contains(minuteOfWeek: Int) -> Bool
func overlaps(_ other: FreeTimeInterval) -> Bool
```

Validation (enforced at edit time, not at decode time):

- `durationMinutes >= 10`
- `durationMinutes <= 10080 - 10`
- `durationMinutes.isMultiple(of: 10)` (10-min snap)
- `startMinuteOfWeek.isMultiple(of: 10)`

Overlapping intervals are allowed and treated as a union at evaluation time (matches the brainstorming decision).

### `WeeklySchedule`

Replaces `ScheduleSettings` outright.

```swift
@MainActor
@Observable
final class WeeklySchedule: Codable {
    var isEnabled: Bool
    var intervals: [FreeTimeInterval]
    var timeZone: TimeZone
    var lastDisabledAt: Date?
    var intentionQuote: String?
}
```

`DataPersistenceService` swaps the stored Codable shape. Persistence key stays the same; an `init(from:)` migration path reads the old `ScheduleSettings` blob if present (see Migration section).

Core methods:

```swift
func isFreeTime(at date: Date) -> Bool
func isBlocking(at date: Date) -> Bool          // convenience: !isFreeTime && isEnabled
func protectedMinutes(at date: Date) -> Int     // total minutes of blocking elapsed in today's local day, up to `date`
func remainingProtectedMinutes(at date: Date) -> Int
func nextBoundary(after date: Date) -> Date?    // next free→blocked or blocked→free transition in clock time
```

`isFreeTime(at:)` converts the date to a minute-of-week in `timeZone`, checks if any interval contains it. The union property falls out of "any contains".

`nextBoundary(after:)` is new — it drives the shield reconciliation scheduler. For a given wall-clock `date`, it returns the next transition boundary so iOS can wake the extension and reapply. Implementation: compute the minute-of-week of `date`, scan each interval's start and end as candidate boundaries, return the soonest one that is after `date` (wrapping across the week boundary if all are earlier).

## Editor UI

### `WeekScheduleEditorView`

Replaces `ScheduleSettingsView`. Presented as a `.sheet` from the Settings tab's "Free Time" row — same presentation style as today.

Structure (top to bottom):

- `NavigationStack` toolbar: `Cancel` / title "Free Time" / `Save`
- Scrollable body containing a fixed-height 7-day × 24-hour grid (one-screen, non-scrolling)
- `.sheet` for the edit / copy modals

The editor holds a working copy of the schedule (`@State var editing: WeeklySchedule`). `Save` commits it; `Cancel` discards all changes including any `Confirm`-ed block edits.

### Grid rendering

Components:

- `WeekGridView` — container that lays out 8 columns: an hour-label column plus 7 day columns.
- `HourColumn` — 22pt wide, displays "0" / "6" / "12" / "18" / "24" aligned to the three major boundaries.
- `DayColumn` — a `ZStack` with the column background (`#1f1f1f`) plus `BlockRect` overlays positioned by normalized minute-of-day offsets.
- `BlockRect` — renders one segment of a `FreeTimeInterval` on a specific day column, carries the interval's `id` for hit-testing.
- `HourGridOverlay` — absolute overlay spanning the full day area (all 7 day columns AND the gaps between them), rendering 7 horizontal lines at 3h boundaries (3/6/9/12/15/18/21). Uniform colour `rgba(255,255,255,0.3)`. Sits above blocks in the z-stack so the timeline reads continuously across the week.

#### Rendering a cross-day interval

A `FreeTimeInterval` that starts on day A at time T1 and ends on day B at time T2 renders as multiple `BlockRect`s — one per affected day:

- Day A: T1 → 23:59:59
- Middle days (if any): 00:00 → 23:59:59
- Day B: 00:00 → T2

All share the same interval `id`. A hit on any segment targets the whole interval for editing / deletion.

A single `WeekGridView` pass iterates over `schedule.intervals`, fans each one out into its segments via `FreeTimeInterval.renderedSegments(for: dayOfWeek)`, and places them in the correct columns.

### Interactions

| Gesture | Target | Action |
|---|---|---|
| Tap | Empty grid area | Create a new 1-hour `FreeTimeInterval` at the tapped day and nearest 10-min time slot. Select it and open the edit sheet. |
| Tap | Existing block segment | Select interval, open edit sheet. |
| **Long-press** | Existing block segment | Show a SwiftUI `.contextMenu` with two actions: **Edit** (identical to tap) and **Delete** (removes the interval from `editing.intervals` with no confirmation — user can Cancel the Save to revert). |

Drag-to-create (paint) and drag-to-resize are explicitly out of scope.

### Edit sheet

Presented as `.sheet` with `.presentationDetents([.medium])`. Contents:

- Title "Edit Free Time" in plain text, title case, no border.
- "Starts" row: label on the left, a `Button` on the right whose title is "Friday · 22:00" style text (plain, no rounded background — unlike v5). Tapping opens a day + time picker.
- "Ends" row: same.
- Action row: `Copy to…` button (secondary outlined), `Delete` button (tertiary outlined, muted).
- Primary button at bottom: `Confirm` (white fill, dark text).

Time picker implementation: `DatePicker` with `.hourAndMinute` style and a 10-minute stride enforced via `.minuteInterval = 10` (UIKit backing). Day picker is a `Picker` of 7 weekdays.

`Confirm` validates:

- End strictly after start (`durationMinutes >= 10`)
- Duration `<= 10080 - 10`
- Both endpoints snap to 10-min multiples

Invalid → `Confirm` disabled, offending row shows a subtle warning indicator (exact affordance left to implementation).

Dismissing the sheet without `Confirm` discards the block's pending edits. `Confirm` commits them to `editing.intervals`. The Save button at the top nav commits the whole `editing` to persistence.

### Copy sheet

Presented after the user taps `Copy to…` on the edit sheet (as a nested `.sheet`). Contents:

- Title "Copy To" in title case, no border.
- 7-cell day picker (M T W T F S S). Multi-select. Toggling a cell stores it in a local `Set<Weekday>`.
- Primary `Copy` button at the bottom.

On `Copy`, for each selected target day, create a new `FreeTimeInterval` cloned from the source with `startMinuteOfWeek` shifted to the target day's equivalent time. Duration is preserved. If the new interval wraps past `endOfWeek`, that's allowed — the minute-of-week math wraps correctly.

Overlapping copies merge naturally via the "any contains" evaluation. No validation, no dedupe.

## Shield Sync

The pre-existing bug: free-time boundaries don't trigger `applyDefaultBlocking`, so the physical shield lags the model whenever the app is backgrounded across a boundary. Fix comes in two layers:

1. **Scene-phase catch-up (cheap).** `ContentViewModel` observes `scenePhase` and calls `applyDefaultBlocking()` when the app becomes `.active`. Catches every foreground transition; cheap and reliable; does nothing for boundaries crossed while the app stays backgrounded.

2. **DeviceActivity boundary scheduling (proper).** On every schedule save (and once at launch), compute the next N (N ≈ 20) boundary timestamps via `nextBoundary(after:)` rolling forward. Register each as a lightweight `DeviceActivitySchedule` (or as threshold events on a rolling schedule — implementation plan will pick one) whose handler is `IntentionsDeviceActivityMonitor`. The extension's handler reads the persisted `WeeklySchedule` from shared `UserDefaults` and toggles the `ManagedSettingsStore` shield. This is the same mechanism the app already uses for per-session expiration, extended to free-time window boundaries.

Both layers are needed because iOS's background scheduling is historically flaky; scene-phase is the safety net.

Writing the persisted `WeeklySchedule` to shared UserDefaults remains the extension's source of truth — matching the existing `saveScheduleSettingsToUserDefaults` pattern in `ContentViewModel`.

## Settings Screen Integration

`SettingsView`'s existing "Free Time" row (in `SettingsView.swift`) currently shows two computed strings from `SettingsViewModel`: `formattedActiveHours` ("17:00 - 21:30") and `activeDaysText` ("Weekdays"). Those are no longer enough to summarise a multi-interval schedule.

Replace with a compact summary computed from `WeeklySchedule`:

- 0 intervals and enabled: "No free time set"
- 1 interval: the interval's start–end day/time, e.g. "Mon–Fri 17:00–21:30" when the same interval pattern was copied to those days (detection is best-effort — see below)
- More than 1 interval: count + shortest representative, e.g. "3 blocks · earliest Mon 17:00"

Pattern detection for a compact summary ("Mon–Fri 17:00–21:30") is nice-to-have. If the plan step decides it's too complex, fall back to a count-based summary — the grid editor is where details live.

The `SettingsViewModel` properties `formattedActiveHours`, `activeDaysText`, `intentionsStateText`, `intentionsStateColor` are replaced by a single `scheduleSummary: String` computed from `WeeklySchedule`. The Blocking section's structure in `SettingsView` stays the same otherwise.

## Migration

One-shot, runs on first launch after this change ships. If an existing `ScheduleSettings` blob is present in persistence, convert it:

```swift
func migrate(_ old: ScheduleSettings) -> WeeklySchedule {
    let new = WeeklySchedule()
    new.isEnabled = old.isEnabled
    new.timeZone = old.timeZone
    new.lastDisabledAt = old.lastDisabledAt
    new.intentionQuote = old.intentionQuote

    for weekday in old.activeDays {
        let dayStartMinute = WeeklySchedule.minuteOfWeekOrigin(for: weekday) // new helper
        let timeStart = old.startHour * 60 + old.startMinute
        let timeEnd = old.endHour * 60 + old.endMinute
        let duration = ((timeEnd - timeStart) + 1440) % 1440
        guard duration >= 10 else { continue }
        new.intervals.append(FreeTimeInterval(
            id: UUID(),
            startMinuteOfWeek: dayStartMinute + timeStart,
            durationMinutes: duration
        ))
    }
    return new
}
```

The `Weekday` enum in the codebase today uses calendar-weekday-style mapping (Sun=1 → Sat=7, per `WeekdayTests`). `WeeklySchedule` adds a static helper to convert from `Weekday` to a Monday-origin minute-of-week:

```swift
static func minuteOfWeekOrigin(for weekday: Weekday) -> Int {
    // Monday → 0, Tuesday → 1440, …, Sunday → 6 * 1440
    switch weekday {
    case .monday: return 0
    case .tuesday: return 1 * 1440
    case .wednesday: return 2 * 1440
    case .thursday: return 3 * 1440
    case .friday: return 4 * 1440
    case .saturday: return 5 * 1440
    case .sunday: return 6 * 1440
    }
}
```

The existing `Weekday` enum is not modified.

- If `old` had `start == end`, skip (old representation treated that as no free time).
- If `old.startHour > old.endHour` (overnight window), the per-day interval uses the same overnight duration — i.e. a user with "free 22:00–06:00 on all 7 days" ends up with 7 cross-day intervals. This faithfully represents the old model's behaviour, even though the old model's behaviour for overnight windows was buggy. Post-migration the user can consolidate if they want.
- `DataPersistenceService` keeps decoding the old `ScheduleSettings` blob for one additional app version after this ships so a rollback still works. The version after that deletes the old decoder.

## Out of Scope

- One-off exception intervals tied to calendar dates (option D from brainstorming — deferred).
- Drag-to-resize blocks directly in the grid.
- Tap-drag to paint new blocks.
- Zoom / scroll the grid for minute-level precision — the sheet is where precise editing happens.
- Per-app scheduling (different blocking rules per app group).
- A calendar view of historic protected-hour stats. This change does not rework the stats banner.

## Risks

- **DeviceActivity boundary reliability.** iOS's background scheduling has been flaky historically. The scene-phase catch-up mitigates but doesn't eliminate. Worth testing on a physical device before claiming the lag bug fixed.
- **Wrap-around math.** The minute-of-week representation needs careful unit tests for containment, overlap, and rendering of cross-week intervals (Sun night → Mon morning).
- **Migration correctness for overnight windows.** Need golden-value tests for the three shapes the old model could express: daytime, overnight, and full-day.
- **Cross-day block hit-testing.** Multiple segments share one interval `id`; the grid tap handler has to resolve the tapped segment back to the interval and the edit sheet has to know which interval is being edited.
- **`DataPersistenceService` backwards compat.** A user running the previous version who opens this version must migrate cleanly even if they had no active schedule at all.

## Touched Files

Non-exhaustive list to brief the implementation plan:

- `Intentions/Models/ScheduleSettings.swift` — delete, replaced by `WeeklySchedule.swift` and `FreeTimeInterval.swift`.
- `Intentions/Models/WeeklySchedule.swift` — new.
- `Intentions/Models/FreeTimeInterval.swift` — new.
- `Intentions/ViewModels/SettingsViewModel.swift` — rename `scheduleSettings` → `weeklySchedule`, delete `formattedActiveHours` / `activeDaysText`, add `scheduleSummary` computed property.
- `Intentions/ViewModels/ContentViewModel.swift` — replace `scheduleSettings` references; rewire `saveScheduleSettingsToUserDefaults` to persist the new shape; add `scenePhase` observer calling `applyDefaultBlocking`; extend `applyDefaultBlocking` to call into the new `WeeklySchedule.isBlocking(at:)` API; schedule boundary events via `DeviceActivityCenter`.
- `Intentions/Views/Settings/ScheduleSettingsView.swift` — delete, replaced by `WeekScheduleEditorView.swift` + its subviews (`WeekGridView`, `DayColumn`, `BlockRect`, `HourGridOverlay`, `EditFreeTimeSheet`, `CopyToSheet`).
- `Intentions/Views/Settings/SettingsView.swift` — update the Blocking row's subtitle to read from the new `scheduleSummary`.
- `Intentions/Services/DataPersistenceService.swift` — accept and emit the new `WeeklySchedule` shape; keep a decode-path for the old `ScheduleSettings` blob for one version.
- `IntentionsDeviceActivityMonitor/DeviceActivityMonitorExtension.swift` — replace `isCurrentlyInProtectedHours` with a call into the shared `WeeklySchedule` decoder; handle the new boundary-event names from the main app's scheduler.
- `IntentionsTests/ModelTests/ScheduleSettingsTests.swift` — delete the now-irrelevant tests, replaced by `FreeTimeIntervalTests.swift`, `WeeklyScheduleTests.swift`, `WeeklyScheduleMigrationTests.swift`.
- `IntentionsTests/ViewModels/SettingsViewModelTests.swift` — update references from `scheduleSettings` to `weeklySchedule`, rewrite `testDefaultScheduleSettings` against the new shape.
- `IntentionsTests/Integration/SettingsIntegrationTests.swift` — same.
- `Intentions/Utilities/Constants.swift` — replace `Schedule.defaultStartHour/Minute/EndHour/Minute` with a `defaultIntervals: [FreeTimeInterval]` (seed with the current 17:00–21:30 weekdays window).

## Testing

Unit tests (Swift XCTest):

- `FreeTimeIntervalTests`: containment (within, before, after, at endpoints, wrap-around), overlaps, duration bounds, codable round-trip.
- `WeeklyScheduleTests`: `isFreeTime(at:)` at deterministic dates including boundary cases, `protectedMinutes(at:)` math, `nextBoundary(after:)` including the "no intervals" and "all-week free" edge cases.
- `WeeklyScheduleMigrationTests`: fixtures for (a) weekdays-only daytime, (b) all-days daytime, (c) overnight on weekdays, (d) disabled schedule, (e) empty activeDays. Assert the intervals list, isEnabled, and carryover fields.

UI tests deferred to the implementation plan.

## References

- v7 mockup: <https://designs.kieranhitchcock.com/intent-schedule-week-grid-v7/>
- Block translucency ramp: <https://designs.kieranhitchcock.com/intent-schedule-block-colors-v3/>
- Column color variants: <https://designs.kieranhitchcock.com/intent-schedule-column-colors/>
- Earlier design artefacts in `.superpowers/brainstorm/30027-1776061334/content/`
