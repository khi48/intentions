# Blocking Section Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rename Settings "Free Time" section to "Blocking", merge "Free Hours" and "Free Days" rows into a single "Free Time" row, and add dynamic/static subtitles that make the inverse relationship between free time and blocking explicit.

**Architecture:** All changes are isolated to `SettingsView.swift` (new row markup, removed rows, section label rename) and `SettingsViewModel.swift` (delete two now-unused computed properties). No new view models, no new data, no new localization layer. Existing `formattedActiveHours`, `activeDaysText`, and `scheduleSettings.isEnabled` drive the whole redesign.

**Tech Stack:** SwiftUI, Swift 6, `@Observable` view model, XCTest, `xcodebuild` against iOS simulator.

**Spec:** `docs/superpowers/specs/2026-04-13-blocking-section-redesign-design.md`

---

## File Structure

- **Modify** `Intentions/Views/Settings/SettingsView.swift`
  - Rename section label
  - Replace `blockingToggleRow` contents (title + dynamic subtitle + toggle)
  - Delete the two `settingsRow("Free Hours", ...)` / `settingsRow("Free Days", ...)` call sites
  - Add a new private `freeTimeRow` view
- **Modify** `Intentions/ViewModels/SettingsViewModel.swift`
  - Delete `intentionsStateText` and `intentionsStateColor` computed properties (confirmed no other callers)
- **Verify** `IntentionsTests/ViewModels/SettingsViewModelTests.swift`
  - No changes expected — confirmed no existing tests reference the deleted properties

---

## Task 1: Delete unused view-model properties

**Files:**
- Modify: `Intentions/ViewModels/SettingsViewModel.swift:153-171`

- [ ] **Step 1: Delete `intentionsStateText` and `intentionsStateColor`**

In `Intentions/ViewModels/SettingsViewModel.swift`, delete the block from line 153 through line 171 (both properties and the blank line between them). The surrounding code is:

```swift
    var scheduleStatusColor: Color {
        if !scheduleSettings.isEnabled {
            return .gray
        }

        return scheduleSettings.isCurrentlyActive ? .green : .orange
    }

    // DELETE FROM HERE
    var intentionsStateText: String {
        if !scheduleSettings.isEnabled {
            return "Disabled"
        }

        if scheduleSettings.isCurrentlyActive {
            return "Blocked"
        } else {
            return "Free Time"
        }
    }

    var intentionsStateColor: Color {
        if !scheduleSettings.isEnabled {
            return .gray
        }

        return scheduleSettings.isCurrentlyActive ? .green : .orange
    }
    // DELETE TO HERE

    var formattedActiveHours: String {
```

After deletion the file should go directly from `scheduleStatusColor` to `formattedActiveHours` with one blank line between.

- [ ] **Step 2: Build to confirm no callers remain**

Run:
```bash
xcodebuild -project Intentions.xcodeproj -scheme Intentions -destination 'generic/platform=iOS Simulator' build 2>&1 | tail -20
```

Expected: `** BUILD SUCCEEDED **`. Compilation is the test here — if anything still referenced the deleted properties, it would fail.

- [ ] **Step 3: Commit**

```bash
git add Intentions/ViewModels/SettingsViewModel.swift
git commit -m "$(cat <<'EOF'
refactor: drop unused intentionsStateText/Color from SettingsViewModel

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: Rename section label

**Files:**
- Modify: `Intentions/Views/Settings/SettingsView.swift:165`

- [ ] **Step 1: Change section label from "Free Time" to "Blocking"**

In `Intentions/Views/Settings/SettingsView.swift`, find the line (currently ~165):

```swift
                        // Free Time
                        sectionLabel("Free Time")
```

Replace with:

```swift
                        // Blocking
                        sectionLabel("Blocking")
```

- [ ] **Step 2: Build to confirm compilation**

Run:
```bash
xcodebuild -project Intentions.xcodeproj -scheme Intentions -destination 'generic/platform=iOS Simulator' build 2>&1 | tail -10
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add Intentions/Views/Settings/SettingsView.swift
git commit -m "$(cat <<'EOF'
refactor(settings): rename Free Time section to Blocking

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: Rewrite blocking toggle row

**Files:**
- Modify: `Intentions/Views/Settings/SettingsView.swift:359-386`

- [ ] **Step 1: Replace `blockingToggleRow` body**

In `Intentions/Views/Settings/SettingsView.swift`, replace the entire `blockingToggleRow` computed property (currently lines 359–386):

```swift
    private var blockingToggleRow: some View {
        HStack {
            Text("Blocking")
                .font(.body)
                .foregroundColor(AppConstants.Colors.text)
            Spacer()
            Text(viewModel.intentionsStateText)
                .font(.subheadline)
                .foregroundColor(AppConstants.Colors.textSecondary)
                .padding(.trailing, 8)
            Toggle("", isOn: Binding(
                get: { viewModel.scheduleSettings.isEnabled },
                set: { newValue in
                    if newValue {
                        Task {
                            await viewModel.toggleScheduleEnabled()
                            await onScheduleSettingsChanged?(viewModel.scheduleSettings)
                        }
                    } else {
                        showingDisableConfirmation = true
                    }
                }
            ))
            .labelsHidden()
        }
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) { rowDivider }
    }
```

With:

```swift
    private var blockingToggleRow: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Enabled")
                    .font(.body)
                    .foregroundColor(AppConstants.Colors.text)
                Text(blockingToggleSubtitle)
                    .font(.caption)
                    .foregroundColor(AppConstants.Colors.textSecondary)
            }
            Spacer()
            Toggle("", isOn: Binding(
                get: { viewModel.scheduleSettings.isEnabled },
                set: { newValue in
                    if newValue {
                        Task {
                            await viewModel.toggleScheduleEnabled()
                            await onScheduleSettingsChanged?(viewModel.scheduleSettings)
                        }
                    } else {
                        showingDisableConfirmation = true
                    }
                }
            ))
            .labelsHidden()
        }
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) { rowDivider }
    }

    private var blockingToggleSubtitle: String {
        if viewModel.scheduleSettings.isEnabled {
            return "Blocks apps 24/7 outside free time"
        } else {
            return "Blocking is off — no apps are blocked"
        }
    }
```

- [ ] **Step 2: Build to confirm compilation**

Run:
```bash
xcodebuild -project Intentions.xcodeproj -scheme Intentions -destination 'generic/platform=iOS Simulator' build 2>&1 | tail -10
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add Intentions/Views/Settings/SettingsView.swift
git commit -m "$(cat <<'EOF'
feat(settings): two-line blocking toggle with dynamic subtitle

Title is "Enabled"; subtitle reads "Blocks apps 24/7 outside free time"
when blocking is on and "Blocking is off — no apps are blocked" when off.
Removes the previous right-side state text.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: Add merged Free Time row

**Files:**
- Modify: `Intentions/Views/Settings/SettingsView.swift:167-172` (call site)
- Modify: `Intentions/Views/Settings/SettingsView.swift` (new private view near other row helpers)

- [ ] **Step 1: Add `freeTimeRow` private view**

In `Intentions/Views/Settings/SettingsView.swift`, directly after the `blockingToggleSubtitle` computed property added in Task 3, add the following new view:

```swift
    private var freeTimeRow: some View {
        let disabled = isScheduleEditingDisabled
        let titleColor = disabled ? AppConstants.Colors.disabled : AppConstants.Colors.text
        let valueColor = disabled ? AppConstants.Colors.disabled : AppConstants.Colors.textSecondary
        let secondaryColor = disabled ? AppConstants.Colors.disabled : AppConstants.Colors.textSecondary.opacity(0.75)

        return Button(action: disabled ? {} : { viewModel.showScheduleEditor() }) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Free Time")
                        .font(.body)
                        .foregroundColor(titleColor)
                    Text("Every other hour is blocked")
                        .font(.caption)
                        .foregroundColor(secondaryColor)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(viewModel.formattedActiveHours)
                        .font(.subheadline)
                        .foregroundColor(valueColor)
                    Text(viewModel.activeDaysText)
                        .font(.caption)
                        .foregroundColor(secondaryColor)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                if !disabled {
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundColor(AppConstants.Colors.textSecondary)
                }
            }
            .padding(.vertical, 14)
            .overlay(alignment: .bottom) { rowDivider }
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }
```

- [ ] **Step 2: Replace the two old rows with the merged row**

In the same file, find the existing Free Hours / Free Days block (currently ~lines 167–172):

```swift
                        blockingToggleRow
                        settingsRow("Free Hours", value: viewModel.formattedActiveHours, disabled: isScheduleEditingDisabled) {
                            viewModel.showScheduleEditor()
                        }
                        settingsRow("Free Days", value: viewModel.activeDaysText, disabled: isScheduleEditingDisabled) {
                            viewModel.showScheduleEditor()
                        }
```

Replace with:

```swift
                        blockingToggleRow
                        freeTimeRow
```

Leave the disabled-reason `if isScheduleEditingDisabled { ... }` info-line block that follows this section unchanged — it still applies to the new row.

- [ ] **Step 3: Build to confirm compilation**

Run:
```bash
xcodebuild -project Intentions.xcodeproj -scheme Intentions -destination 'generic/platform=iOS Simulator' build 2>&1 | tail -10
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
git add Intentions/Views/Settings/SettingsView.swift
git commit -m "$(cat <<'EOF'
feat(settings): merge Free Hours and Free Days into Free Time row

Single tappable row with title "Free Time", subtitle "Every other hour
is blocked", and a two-line value showing hours primary and days
secondary. Opens the same ScheduleSettingsView sheet as before. Dims
when the schedule cannot be edited (active session or active free-time
window).

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 5: Run the test suite

**Files:** none (verification only)

- [ ] **Step 1: Run the full test suite on the simulator**

> **Important:** This step runs a simulator. If you are a subagent, STOP and hand back to the main conversation — subagents must never boot simulators per the project CLAUDE.md.

From the main conversation, run:
```bash
xcodebuild -project Intentions.xcodeproj -scheme Intentions \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  test 2>&1 | tail -40
```

Expected: `** TEST SUCCEEDED **`. No `SettingsViewModelTests` failures. If any fail, debug per the systematic-debugging skill before proceeding — do not patch over symptoms.

---

## Task 6: Manual verification on simulator

**Files:** none (manual QA)

> **Important:** Simulator run. Subagents STOP here and hand back to the main conversation.

- [ ] **Step 1: Build and run on simulator**

From the main conversation:
```bash
xcodebuild -project Intentions.xcodeproj -scheme Intentions \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  build 2>&1 | tail -5
```

Then launch the app in the booted simulator (via Xcode or `xcrun simctl launch booted app.kieranhitchcock.Intentions`).

- [ ] **Step 2: Walk the checklist**

Verify each case in the simulator and tick the box once confirmed visually:

- [ ] Settings → Blocking section header reads "BLOCKING"
- [ ] Toggle row title is "Enabled"
- [ ] With blocking ON: toggle subtitle reads "Blocks apps 24/7 outside free time"
- [ ] Toggle OFF via confirmation sheet → subtitle flips to "Blocking is off — no apps are blocked"
- [ ] Toggle back ON → subtitle returns
- [ ] Free Time row title reads "Free Time", subtitle reads "Every other hour is blocked"
- [ ] Right side shows two lines: formatted hours primary, days secondary
- [ ] Tapping the Free Time row opens the schedule editor sheet
- [ ] Editing hours or days in the sheet and saving updates both lines of the Free Time value
- [ ] Pick a custom day set (e.g. Mon/Tue/Thu/Fri) → days line shows the list, truncates cleanly if long
- [ ] During an active free-time window or active session, the Free Time row dims and becomes non-tappable, and the existing "Cannot modify schedule…" info line renders below it
- [ ] Fresh open of Settings with blocking disabled → no toggle flicker (should already hold from build 95, but confirm regression-free)

- [ ] **Step 3: Report results**

Note any deviations. If everything passes, proceed. If not, file the specific deviation and debug systematically.

---

## Task 7: Update vault notes

**Files:**
- Modify: `.project-notes/overview.md` (or `tasks.md` / `notes.md` depending on current structure)

- [ ] **Step 1: Record the UI change in the vault**

Add a dated note under the relevant section (e.g. recent changes, UI log) summarising:

> 2026-04-13 — Settings: renamed Free Time section to Blocking; merged Free Hours / Free Days into a single Free Time row with dynamic toggle subtitle. Spec: `docs/superpowers/specs/2026-04-13-blocking-section-redesign-design.md`.

- [ ] **Step 2: Commit the vault update**

```bash
git -C .project-notes add overview.md
git -C .project-notes commit -m "notes: blocking section redesign"
```

(If `.project-notes` is a symlink into the iCloud vault, the commit happens in the vault repo. If there is no vault repo, skip the commit step — saving the file is enough.)

---

## Out of Scope

- Localization of new strings
- Any change to `ScheduleSettingsView` beyond the label rename that shipped in build 95
- Home screen / widget surfaces that show schedule state
- New computed properties on the view model
