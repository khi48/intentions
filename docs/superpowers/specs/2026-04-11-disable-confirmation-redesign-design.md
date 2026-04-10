# Disable Blocking Confirmation — Redesign

## Overview

Redesign the `DisableBlockingConfirmationView` to deter users from starting the disable process by confronting them with their own commitment before they engage with the form. The current design (reason text field + circular countdown) provides friction during the process but doesn't discourage starting it.

The new design uses a "two halves" layout: a reflection section showing the user's streak, protection stats, and their own words back to them, followed by an action section with the reason input and a progress-bar-integrated disable button.

## Design

### Layout: Two Halves

**Top half — Reflection (read-only)**

| Element | Position | Style |
|---------|----------|-------|
| Streak (days without disabling) | Left-aligned, large (24pt, semibold) | Label "streak" below in secondary text |
| Protected time today | Right-aligned | e.g. "4h 12m protected" in secondary text |
| Time remaining today | Right-aligned, below protected time | e.g. "1h 48m remaining" in tertiary text |
| User's intention quote | Full width, below stats | Italic, slightly muted (e.g. `textSecondary` at higher opacity) |

A single subtle divider line separates the two halves.

**Bottom half — Action**

| Element | Position | Style |
|---------|----------|-------|
| "Why unlock?" label | Left-aligned | Secondary text color |
| Text input | Full width, underline style | Same as current — min 15 characters |
| Character count | Left below input | "0/15" in tertiary text |
| Disable button with timer | Full width | Progress bar fills left-to-right inside button over 10s. Text: "Disable · Xs". Disabled state until timer completes. |

### Timer-in-Button Behavior

- Button starts in disabled state with text "Disable"
- Once the user types 15+ valid characters, the 10-second countdown begins
- Button text changes to "Disable · 10s", counting down each second
- A subtle background fill (slightly lighter than the button bg) animates from left to right over 10 seconds
- When timer reaches 0, the fill covers the full button, text becomes "Disable", and the button enables (text color brightens)
- The same lazy-response validation from the current implementation applies (filters "asdf", "test", etc.)

### Navigation

- Presented as a sheet (same as current)
- "Cancel" button in navigation bar leading position (same as current)
- Navigation title: "Confirm" (same as current)

## New Data Requirements

### 1. Last Disable Timestamp

**What:** Store when the user last disabled blocking.

**Where:** New `lastDisabledAt: Date?` property on `ScheduleSettings`. Persisted to SwiftData via `PersistentScheduleSettings`. Not needed in UserDefaults (not used by extensions).

**When updated:** Set to `Date()` when the user confirms disabling blocking.

**Streak calculation:** Computed property on `ScheduleSettings`:
- If `lastDisabledAt` is nil, streak = days since `isEnabled` was first set (or 0 if never enabled). For simplicity in v1, treat nil as "never disabled" and show the streak as the number of days since the schedule was enabled. If we don't track when the schedule was enabled either, default to showing nothing (hide the streak element).
- Otherwise, streak = calendar days between `lastDisabledAt` and now.

### 2. User Intention Quote

**What:** A short personal statement the user writes explaining why they set up protection. Displayed on the disable confirmation screen to confront them with their own words.

**Where:** New `intentionQuote: String?` property on `ScheduleSettings`. Persisted to SwiftData via `PersistentScheduleSettings`. Not needed in UserDefaults.

**When set:** Prompt the user to write their intention when they first enable blocking. Add an editable field in the Schedule Settings view so they can update it later.

**On the disable screen:** If the quote is nil/empty, hide the quote element entirely. The screen still works without it — the stats and reason input carry enough weight on their own.

### 3. Protected Time Today / Remaining

**What:** How long the user has been within protected hours today, and how long remains.

**Where:** Computed at display time from `ScheduleSettings.activeHours` and the current time. No persistence needed.

**Calculation:**
- `protectedTimeToday`: minutes elapsed since today's `activeHours.lowerBound` (capped at current time or `activeHours.upperBound`, whichever is earlier)
- `remainingTimeToday`: minutes from now until `activeHours.upperBound` (0 if past upper bound)
- If today is not in `activeDays`, both are 0 (though this screen shouldn't appear outside active hours anyway)

## Changes by File

### Modified Files

| File | Changes |
|------|---------|
| `DisableBlockingConfirmationView.swift` | Full redesign of the view body. Replace circular countdown with progress-bar button. Add reflection section. Accept new data (streak, stats, quote) as parameters. |
| `ScheduleSettings.swift` | Add `lastDisabledAt: Date?` and `intentionQuote: String?` properties. Add computed properties for streak, protected time today, remaining time. |
| `PersistentScheduleSettings` (in DataPersistenceService or its own file) | Add persistence fields for `lastDisabledAt` and `intentionQuote`. Update encode/decode. |
| `SettingsView.swift` | Pass new data to `DisableBlockingConfirmationView`. Set `lastDisabledAt` on confirm. |
| `SettingsViewModel.swift` | Expose streak, protected time, remaining time, and intention quote for the view. |
| `ScheduleSettingsView.swift` | Add an editable field for the user's intention quote. |

### No New Files

All changes fit within existing files.

## Edge Cases

- **No intention quote set:** Hide the quote element. The screen is still effective with just streak + stats.
- **First day of use / no streak data:** If `lastDisabledAt` is nil and we can't determine when blocking was enabled, hide the streak element or show "New" instead of a number.
- **Streak of 0 days:** Show "0 days" — this is honest and still confrontational. The user sees they just disabled recently.
- **Outside protected hours:** This screen should only appear during protected hours (existing guard in `SettingsView`), but if it somehow appears outside, show 0 for protected/remaining time.
- **Keyboard handling:** Same as current — scroll dismisses keyboard, tap outside dismisses, submit label is "done".
