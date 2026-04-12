# Blocking Section Redesign

**Date:** 2026-04-13
**Status:** Approved, pending implementation plan
**Target:** `Intentions/Views/Settings/SettingsView.swift`

## Problem

The current Settings page has a "Free Time" section containing three rows: a "Blocking" master toggle, a "Free Hours" row, and a "Free Days" row. Two issues:

1. "Free Hours" and "Free Days" link to the same schedule editor sheet. Splitting them into separate rows creates redundant taps and wastes vertical space.
2. The section framing ("Free Time" heading + "Blocking" toggle inside it) is confusing. Users cannot tell from a glance that apps are blocked 24/7 *outside* of scheduled free time, not during it. The schedule defines when blocking is *relaxed*, not when it is applied.

## Goal

Rename the section to "Blocking", merge the schedule rows into a single "Free Time" row, and add copy that makes the inverse relationship between free time and blocking explicit. A first-time visitor should understand that blocking is 24/7 and that the schedule carves out exceptions.

## Design

### Section

Section label: `BLOCKING` (unchanged copy, new meaning now that it is the section name rather than a row title).

### Row 1 — Master toggle

- **Title:** `Enabled`
- **Subtitle (dynamic):**
  - When `scheduleSettings.isEnabled == true`: `Blocks apps 24/7 outside free time`
  - When `scheduleSettings.isEnabled == false`: `Blocking is off — no apps are blocked`
- **Trailing control:** `Toggle` bound to `viewModel.scheduleSettings.isEnabled` (existing binding logic preserved — tapping off still presents `DisableBlockingConfirmationView`).
- **No state text** to the right of the title. The subtitle replaces the previous `intentionsStateText` ("Free Time" / "Blocked" / "Disabled") usage on this row.

### Row 2 — Free Time (merged schedule row)

- **Title:** `Free Time`
- **Subtitle (static):** `Every other hour is blocked`
- **Trailing value (two-line, right-aligned):**
  - Primary: `viewModel.formattedActiveHours` — e.g., `9:00 AM – 5:00 PM`
  - Secondary (smaller, muted): `viewModel.activeDaysText` — e.g., `Mon, Tue, Thu, Fri` / `Weekdays` / `Every day`
- **Chevron** on the far right.
- **Tap:** opens `ScheduleSettingsView` sheet via `viewModel.showScheduleEditor()` (same as current `settingsRow` behaviour).
- **Disabled state:** when `isScheduleEditingDisabled` is true (active session or currently inside a free-time window), row dims using the existing `AppConstants.Colors.disabled` treatment. The existing "Cannot modify schedule while session is active" / "Cannot modify schedule during active protected hours" info line renders below, unchanged.

### Removed

- Separate `Free Hours` row (`settingsRow("Free Hours", ...)`)
- Separate `Free Days` row (`settingsRow("Free Days", ...)`)

Both underlying data points are now surfaced in the Free Time row's two-line value. The existing `formattedActiveHours` and `activeDaysText` computed properties on `SettingsViewModel` are reused without change.

## Component Changes

### `SettingsView.swift`

- `sectionLabel("Free Time")` → `sectionLabel("Blocking")`
- Replace `blockingToggleRow` body with a two-line title layout: `VStack(alignment: .leading)` containing title `Text("Enabled")` and a dynamic subtitle `Text`. Remove the `intentionsStateText` `Text`.
- Delete both `settingsRow("Free Hours", …)` and `settingsRow("Free Days", …)` calls.
- Add a new private view `freeTimeRow` that renders:
  - Title/subtitle column (`Free Time` + `Every other hour is blocked`)
  - Spacer
  - Two-line value column (hours / days)
  - Chevron
  - Tap action → `viewModel.showScheduleEditor()`
  - Disabled dim treatment gated on `isScheduleEditingDisabled`
- Keep the existing disabled-reason info line logic; it now follows the single `freeTimeRow`.

### `SettingsViewModel.swift`

No new computed properties needed — `formattedActiveHours`, `activeDaysText`, and `scheduleSettings.isEnabled` already cover everything the new layout reads. Delete `intentionsStateText` and `intentionsStateColor`: `SettingsView` is the only caller and neither survives this redesign.

### New copy strings

Defined inline in `SettingsView.swift` (no localization layer exists in the project today, so matches existing pattern):

- `"Blocks apps 24/7 outside free time"`
- `"Blocking is off — no apps are blocked"`
- `"Every other hour is blocked"`

## Visual Reference

Final layout corresponds to the "Subtitle per row" variant (option 2) in `.superpowers/brainstorm/94195-1776021602/content/clarity-copy.html`, with the dynamic toggle subtitle applied on top.

## Testing

- **`SettingsViewModelTests`:** delete any tests referencing `intentionsStateText` / `intentionsStateColor`. Existing tests for `formattedActiveHours`, `activeDaysText`, and `toggleScheduleEnabled` still apply unchanged.
- **Manual verification on device/simulator:**
  1. Fresh launch, blocking enabled → toggle on, subtitle "Blocks apps 24/7 outside free time", Free Time row shows hours + days.
  2. Toggle off via confirmation sheet → subtitle flips to "Blocking is off — no apps are blocked", Free Time row (still tappable) continues to show the stored schedule.
  3. Tap Free Time row → `ScheduleSettingsView` sheet opens. Save modifies hours + days both reflected in the two-line value.
  4. Pick individual days (e.g., Mon, Tue, Thu, Fri) → secondary line shows the full list, truncates gracefully if needed.
  5. During an active session → Free Time row dims, existing info line renders.
  6. Open Settings fresh with blocking disabled → no toggle flicker (behaviour from build 95 already in place via `hasLoadedOnce`).

## Out of Scope

- Localization of the new strings (the project does not localize today).
- Any change to `ScheduleSettingsView` itself (its `"Start"` / `"Finish"` labels landed in build 95).
- Redesign of the disabled-schedule info line.
- Changes to how `intentionsStateText` / `intentionsStateColor` are used elsewhere (Home, widget, etc.).
