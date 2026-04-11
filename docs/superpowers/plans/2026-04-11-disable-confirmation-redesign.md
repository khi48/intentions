# Disable Blocking Confirmation Redesign — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Redesign the disable blocking confirmation screen with a "two halves" layout — reflection (streak, stats, intention quote) above action (reason input + progress-bar-in-button timer).

**Architecture:** Add `lastDisabledAt` and `intentionQuote` properties to `ScheduleSettings`, persist via `PersistentScheduleSettings`, add computed properties for streak/time stats, then rebuild the confirmation view and wire it up.

**Tech Stack:** SwiftUI, SwiftData, Swift 6.0 / iOS 26.0+

**Build:** `xcodebuild -project Intentions.xcodeproj -scheme Intentions -destination 'platform=iOS Simulator,name=iPhone 16' build` (note: Screen Time APIs require physical device, but model/view compilation works on simulator)

**Test:** `xcodebuild -project Intentions.xcodeproj -scheme Intentions -destination 'platform=iOS Simulator,name=iPhone 16' test`

**Important:** New files need to be added to the Xcode project manually — prompt the user before building. All existing files are already in the project.

---

### Task 1: Add `lastDisabledAt` and `intentionQuote` to ScheduleSettings

**Files:**
- Modify: `Intentions/Models/ScheduleSettings.swift`

- [ ] **Step 1: Add new properties to ScheduleSettings**

In `Intentions/Models/ScheduleSettings.swift`, add two new properties and update the initializer and Codable implementation:

Add properties after line 19 (`var timeZone: TimeZone`):

```swift
var lastDisabledAt: Date?
var intentionQuote: String?
```

Update `init()` (line 21-26) to initialize them:

```swift
init() {
    self.isEnabled = true
    self.activeHours = AppConstants.Schedule.defaultActiveHours
    self.activeDays = Set(Weekday.allCases)
    self.timeZone = AppConstants.Schedule.defaultTimeZone
    self.lastDisabledAt = nil
    self.intentionQuote = nil
}
```

Add to `CodingKeys` enum (line 65-67):

```swift
enum CodingKeys: String, CodingKey {
    case isEnabled, activeHoursStart, activeHoursEnd, activeDays, timeZone
    case lastDisabledAt, intentionQuote
}
```

Add to `init(from decoder:)` after line 78 (`timeZone = ...`):

```swift
lastDisabledAt = try container.decodeIfPresent(Date.self, forKey: .lastDisabledAt)
intentionQuote = try container.decodeIfPresent(String.self, forKey: .intentionQuote)
```

Add to `encode(to:)` after line 87 (`try container.encode(timeZone...)`):

```swift
try container.encodeIfPresent(lastDisabledAt, forKey: .lastDisabledAt)
try container.encodeIfPresent(intentionQuote, forKey: .intentionQuote)
```

- [ ] **Step 2: Add computed properties for streak and time stats**

Add these computed properties after the `isActive(at:)` method (after line 62):

```swift
/// Days since the user last disabled blocking. Nil if never disabled.
var streakDays: Int? {
    guard let lastDisabledAt else { return nil }
    let calendar = Calendar.current
    let startOfLastDisable = calendar.startOfDay(for: lastDisabledAt)
    let startOfToday = calendar.startOfDay(for: Date())
    return calendar.dateComponents([.day], from: startOfLastDisable, to: startOfToday).day
}

/// Minutes the user has been within protected hours today.
var protectedMinutesToday: Int {
    let calendar = Calendar.current
    let now = Date()
    let currentHour = calendar.component(.hour, from: now)
    let currentMinute = calendar.component(.minute, from: now)

    let startHour = activeHours.lowerBound
    let endHour = activeHours.upperBound

    guard currentHour >= startHour else { return 0 }

    let effectiveEndHour = min(currentHour, endHour)
    let fullHoursMinutes = max(0, effectiveEndHour - startHour) * 60

    if currentHour < endHour {
        return fullHoursMinutes + currentMinute
    } else {
        return max(0, endHour - startHour) * 60
    }
}

/// Minutes remaining in today's protected hours.
var remainingProtectedMinutesToday: Int {
    let calendar = Calendar.current
    let now = Date()
    let currentHour = calendar.component(.hour, from: now)
    let currentMinute = calendar.component(.minute, from: now)

    let endHour = activeHours.upperBound

    guard currentHour < endHour else { return 0 }

    return (endHour - currentHour) * 60 - currentMinute
}
```

- [ ] **Step 3: Build to verify compilation**

Run: `xcodebuild -project Intentions.xcodeproj -scheme Intentions -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 4: Commit**

```bash
git add Intentions/Models/ScheduleSettings.swift
git commit -m "feat: add lastDisabledAt, intentionQuote, and time stats to ScheduleSettings"
```

---

### Task 2: Add tests for new ScheduleSettings properties

**Files:**
- Modify: `IntentionsTests/ModelTests/ScheduleSettingsTests.swift`

- [ ] **Step 1: Add streak tests**

Add these test methods to `ScheduleSettingsTests`:

```swift
func testStreakDaysWhenNeverDisabled() {
    let settings = ScheduleSettings()
    settings.lastDisabledAt = nil
    XCTAssertNil(settings.streakDays)
}

func testStreakDaysWhenDisabledToday() {
    let settings = ScheduleSettings()
    settings.lastDisabledAt = Date()
    XCTAssertEqual(settings.streakDays, 0)
}

func testStreakDaysWhenDisabledDaysAgo() {
    let settings = ScheduleSettings()
    let threeDaysAgo = Calendar.current.date(byAdding: .day, value: -3, to: Date())!
    settings.lastDisabledAt = threeDaysAgo
    XCTAssertEqual(settings.streakDays, 3)
}
```

- [ ] **Step 2: Add time stats tests**

```swift
func testProtectedMinutesTodayBeforeSchedule() {
    let settings = ScheduleSettings()
    settings.activeHours = 22...23 // Late night schedule

    let calendar = Calendar.current
    let hour = calendar.component(.hour, from: Date())

    if hour < 22 {
        XCTAssertEqual(settings.protectedMinutesToday, 0)
    }
    // If hour >= 22, the result depends on current time — skip assertion
}

func testRemainingProtectedMinutesAfterSchedule() {
    let settings = ScheduleSettings()
    settings.activeHours = 0...1 // Early morning schedule

    let calendar = Calendar.current
    let hour = calendar.component(.hour, from: Date())

    if hour >= 1 {
        XCTAssertEqual(settings.remainingProtectedMinutesToday, 0)
    }
}
```

- [ ] **Step 3: Add Codable test for new fields**

```swift
func testCodableWithNewFields() throws {
    let settings = ScheduleSettings()
    settings.lastDisabledAt = Date(timeIntervalSince1970: 1700000000)
    settings.intentionQuote = "Be more present"

    let data = try JSONEncoder().encode(settings)
    let decoded = try JSONDecoder().decode(ScheduleSettings.self, from: data)

    XCTAssertEqual(decoded.lastDisabledAt, settings.lastDisabledAt)
    XCTAssertEqual(decoded.intentionQuote, "Be more present")
}

func testCodableBackwardsCompatibility() throws {
    // Simulate old data without the new fields
    let settings = ScheduleSettings()
    settings.lastDisabledAt = nil
    settings.intentionQuote = nil

    let data = try JSONEncoder().encode(settings)
    let decoded = try JSONDecoder().decode(ScheduleSettings.self, from: data)

    XCTAssertNil(decoded.lastDisabledAt)
    XCTAssertNil(decoded.intentionQuote)
}
```

- [ ] **Step 4: Run tests**

Run: `xcodebuild -project Intentions.xcodeproj -scheme Intentions -destination 'platform=iOS Simulator,name=iPhone 16' test 2>&1 | tail -10`
Expected: Tests pass

- [ ] **Step 5: Commit**

```bash
git add IntentionsTests/ModelTests/ScheduleSettingsTests.swift
git commit -m "test: add tests for streak, time stats, and Codable with new fields"
```

---

### Task 3: Update PersistentScheduleSettings for new fields

**Files:**
- Modify: `Intentions/Models/PersistentModels.swift` (lines 147-198)

- [ ] **Step 1: Add new stored properties**

Add after `var timeZoneIdentifier: String` (line 153):

```swift
var lastDisabledAt: Date?
var intentionQuote: String?
```

- [ ] **Step 2: Update the memberwise init**

Replace the `init(...)` at lines 155-168 with:

```swift
init(
    isEnabled: Bool,
    activeHoursStart: Int,
    activeHoursEnd: Int,
    activeDaysData: Data,
    timeZoneIdentifier: String,
    lastDisabledAt: Date? = nil,
    intentionQuote: String? = nil
) {
    self.isEnabled = isEnabled
    self.activeHoursStart = activeHoursStart
    self.activeHoursEnd = activeHoursEnd
    self.activeDaysData = activeDaysData
    self.timeZoneIdentifier = timeZoneIdentifier
    self.lastDisabledAt = lastDisabledAt
    self.intentionQuote = intentionQuote
}
```

- [ ] **Step 3: Update convenience init(from:)**

Replace the `convenience init(from settings:)` at lines 170-181 with:

```swift
@MainActor
convenience init(from settings: ScheduleSettings) {
    let activeDaysData = (try? JSONEncoder().encode(settings.activeDays)) ?? Data()
    
    self.init(
        isEnabled: settings.isEnabled,
        activeHoursStart: settings.activeHours.lowerBound,
        activeHoursEnd: settings.activeHours.upperBound,
        activeDaysData: activeDaysData,
        timeZoneIdentifier: settings.timeZone.identifier,
        lastDisabledAt: settings.lastDisabledAt,
        intentionQuote: settings.intentionQuote
    )
}
```

- [ ] **Step 4: Update toScheduleSettings()**

In `toScheduleSettings()` (lines 183-198), add the new fields after `settings.timeZone = timeZone` (line 195):

```swift
settings.lastDisabledAt = lastDisabledAt
settings.intentionQuote = intentionQuote
```

- [ ] **Step 5: Build to verify**

Run: `xcodebuild -project Intentions.xcodeproj -scheme Intentions -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 6: Commit**

```bash
git add Intentions/Models/PersistentModels.swift
git commit -m "feat: persist lastDisabledAt and intentionQuote in PersistentScheduleSettings"
```

---

### Task 4: Expose new data from SettingsViewModel

**Files:**
- Modify: `Intentions/ViewModels/SettingsViewModel.swift`

- [ ] **Step 1: Add computed properties for the disable confirmation screen**

Add after `activeDaysText` (after line 193):

```swift
// MARK: - Disable Confirmation Data

var streakDays: Int? {
    scheduleSettings.streakDays
}

var formattedProtectedTimeToday: String {
    let totalMinutes = scheduleSettings.protectedMinutesToday
    let hours = totalMinutes / 60
    let minutes = totalMinutes % 60
    if hours > 0 {
        return "\(hours)h \(minutes)m protected"
    } else {
        return "\(minutes)m protected"
    }
}

var formattedRemainingTime: String {
    let totalMinutes = scheduleSettings.remainingProtectedMinutesToday
    let hours = totalMinutes / 60
    let minutes = totalMinutes % 60
    if hours > 0 {
        return "\(hours)h \(minutes)m remaining"
    } else {
        return "\(minutes)m remaining"
    }
}
```

- [ ] **Step 2: Add method to record disable event**

Add after `toggleScheduleEnabled()` (after line 80):

```swift
func recordDisableAndToggle() async {
    scheduleSettings.lastDisabledAt = Date()
    scheduleSettings.isEnabled = false
    await updateScheduleSettings(scheduleSettings)
}
```

- [ ] **Step 3: Build to verify**

Run: `xcodebuild -project Intentions.xcodeproj -scheme Intentions -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 4: Commit**

```bash
git add Intentions/ViewModels/SettingsViewModel.swift
git commit -m "feat: expose streak, time stats, and recordDisable from SettingsViewModel"
```

---

### Task 5: Redesign DisableBlockingConfirmationView

**Files:**
- Modify: `Intentions/Views/Settings/DisableBlockingConfirmationView.swift`

- [ ] **Step 1: Rewrite the entire view**

Replace the full contents of `DisableBlockingConfirmationView.swift` with:

```swift
//
//  DisableBlockingConfirmationView.swift
//  Intentions
//
//  Created by Claude on 18/09/2025.
//

import SwiftUI
import Combine

/// Confirmation modal that adds friction when disabling Intentions blocking.
/// Two-halves layout: reflection (streak, stats, intention quote) above
/// action (reason input + progress-bar-in-button timer).
struct DisableBlockingConfirmationView: View {
    let streakDays: Int?
    let protectedTimeText: String
    let remainingTimeText: String
    let intentionQuote: String?
    let onConfirm: () -> Void
    let onCancel: () -> Void

    @State private var reasonText: String = ""
    @State private var countdownSecondsRemaining: Double = 10.0
    @State private var isCountdownActive: Bool = false
    @State private var countdownCancellable: AnyCancellable?
    @FocusState private var isTextFieldFocused: Bool

    private let minimumCharacters = 15
    private let countdownDuration: Double = 10.0

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 0) {
                        reflectionSection
                        divider
                        actionSection
                    }
                    .padding(.horizontal)
                }
                .scrollDismissesKeyboard(.interactively)

                // Bottom button with progress bar
                progressButton
                    .padding(.horizontal)
                    .padding(.bottom, 20)
            }
            .navigationTitle("Confirm")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        countdownCancellable?.cancel()
                        countdownCancellable = nil
                        onCancel()
                    }
                }
            }
        }
        .onTapGesture {
            isTextFieldFocused = false
        }
        .onDisappear {
            countdownCancellable?.cancel()
            countdownCancellable = nil
        }
    }

    // MARK: - Reflection Section (Top Half)

    private var reflectionSection: some View {
        VStack(spacing: 0) {
            // Stats row: streak left, time stats right
            HStack(alignment: .top) {
                if let streak = streakDays {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(streak) days")
                            .font(.title2)
                            .fontWeight(.semibold)
                            .foregroundColor(AppConstants.Colors.text)
                        Text("streak")
                            .font(.caption)
                            .foregroundColor(AppConstants.Colors.textSecondary)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(protectedTimeText)
                        .font(.subheadline)
                        .foregroundColor(AppConstants.Colors.textSecondary)
                    Text(remainingTimeText)
                        .font(.caption)
                        .foregroundColor(AppConstants.Colors.textSecondary.opacity(0.7))
                }
            }
            .padding(.top, 24)
            .padding(.bottom, 20)

            // Intention quote
            if let quote = intentionQuote, !quote.isEmpty {
                Text("\"\(quote)\"")
                    .font(.body)
                    .italic()
                    .foregroundColor(AppConstants.Colors.textSecondary.opacity(0.85))
                    .lineSpacing(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 20)
            }
        }
    }

    // MARK: - Action Section (Bottom Half)

    private var actionSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Why unlock?")
                .font(.subheadline)
                .foregroundColor(AppConstants.Colors.textSecondary)
                .padding(.top, 20)
                .padding(.bottom, 10)

            TextField("Write your reason...", text: $reasonText)
                .font(.body)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.sentences)
                .focused($isTextFieldFocused)
                .submitLabel(.done)
                .onSubmit { isTextFieldFocused = false }
                .onChange(of: reasonText) { _, newValue in
                    if newValue.count >= minimumCharacters && !isCountdownActive {
                        startCountdown()
                    }
                }
                .padding(.bottom, 12)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(AppConstants.Colors.textSecondary.opacity(0.15))
                        .frame(height: 0.5)
                }

            Text("\(reasonText.count)/\(minimumCharacters)")
                .font(.caption)
                .foregroundColor(AppConstants.Colors.textSecondary.opacity(0.5))
                .padding(.top, 6)
                .padding(.bottom, 20)
        }
    }

    // MARK: - Progress Bar Button

    private var progressButton: some View {
        Button(action: { onConfirm() }) {
            ZStack {
                // Background
                RoundedRectangle(cornerRadius: 12)
                    .fill(AppConstants.Colors.textSecondary.opacity(0.15))

                // Progress fill
                GeometryReader { geometry in
                    RoundedRectangle(cornerRadius: 12)
                        .fill(isConfirmEnabled
                              ? AppConstants.Colors.text
                              : AppConstants.Colors.textSecondary.opacity(0.08))
                        .frame(width: geometry.size.width * progressFraction)
                        .animation(.linear(duration: 1.0 / 60.0), value: progressFraction)
                }

                // Label
                Text(buttonLabel)
                    .font(.headline)
                    .foregroundColor(isConfirmEnabled
                                    ? AppConstants.Colors.background
                                    : AppConstants.Colors.textSecondary)
            }
            .frame(height: 52)
        }
        .disabled(!isConfirmEnabled)
    }

    // MARK: - Divider

    private var divider: some View {
        Rectangle()
            .fill(AppConstants.Colors.textSecondary.opacity(0.1))
            .frame(height: 0.5)
    }

    // MARK: - Computed Properties

    private var isConfirmEnabled: Bool {
        reasonText.count >= minimumCharacters && countdownSecondsRemaining <= 0
    }

    private var progressFraction: CGFloat {
        guard isCountdownActive else { return 0 }
        let elapsed = countdownDuration - countdownSecondsRemaining
        return CGFloat(max(0, min(1, elapsed / countdownDuration)))
    }

    private var buttonLabel: String {
        if !isCountdownActive {
            return "Disable"
        }
        let seconds = Int(ceil(max(0, countdownSecondsRemaining)))
        if seconds > 0 {
            return "Disable · \(seconds)s"
        }
        return "Disable"
    }

    private var isReasonValid: Bool {
        let trimmed = reasonText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= minimumCharacters else { return false }

        let lowercased = trimmed.lowercased()
        let invalidResponses = ["asdf", "test", "because", "idk", "whatever", "abc", "123"]

        for invalid in invalidResponses {
            if lowercased.contains(invalid) && trimmed.count < 25 {
                return false
            }
        }

        return true
    }

    // MARK: - Timer

    private func startCountdown() {
        guard isReasonValid else { return }

        isCountdownActive = true
        countdownSecondsRemaining = countdownDuration

        countdownCancellable = Timer.publish(every: 1.0 / 60.0, on: .main, in: .common)
            .autoconnect()
            .sink { _ in
                countdownSecondsRemaining = max(0, countdownSecondsRemaining - (1.0 / 60.0))

                if countdownSecondsRemaining <= 0 {
                    countdownCancellable?.cancel()
                    countdownCancellable = nil
                }
            }
    }
}

// MARK: - Preview

#Preview {
    DisableBlockingConfirmationView(
        streakDays: 6,
        protectedTimeText: "4h 12m protected",
        remainingTimeText: "1h 48m remaining",
        intentionQuote: "I want to be more present with my family.",
        onConfirm: { print("Confirmed") },
        onCancel: { print("Cancelled") }
    )
}
```

- [ ] **Step 2: Build to verify**

Run: `xcodebuild -project Intentions.xcodeproj -scheme Intentions -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add Intentions/Views/Settings/DisableBlockingConfirmationView.swift
git commit -m "feat: redesign DisableBlockingConfirmationView with two-halves layout"
```

---

### Task 6: Wire up SettingsView to pass new data and record disable

**Files:**
- Modify: `Intentions/Views/Settings/SettingsView.swift`

- [ ] **Step 1: Update the sheet presentation**

Replace the `.sheet(isPresented: $showingDisableConfirmation)` block at lines 237-248 with:

```swift
.sheet(isPresented: $showingDisableConfirmation) {
    DisableBlockingConfirmationView(
        streakDays: viewModel.streakDays,
        protectedTimeText: viewModel.formattedProtectedTimeToday,
        remainingTimeText: viewModel.formattedRemainingTime,
        intentionQuote: viewModel.scheduleSettings.intentionQuote,
        onConfirm: {
            showingDisableConfirmation = false
            Task {
                await viewModel.recordDisableAndToggle()
                await onScheduleSettingsChanged?(viewModel.scheduleSettings)
            }
        },
        onCancel: { showingDisableConfirmation = false }
    )
}
```

- [ ] **Step 2: Build to verify**

Run: `xcodebuild -project Intentions.xcodeproj -scheme Intentions -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add Intentions/Views/Settings/SettingsView.swift
git commit -m "feat: wire SettingsView to pass streak/stats/quote to disable confirmation"
```

---

### Task 7: Add intention quote editor to ScheduleSettingsView

**Files:**
- Modify: `Intentions/Views/Settings/ScheduleSettingsView.swift`

- [ ] **Step 1: Add state for intention quote**

Add after `@State private var selectedDays: Set<Weekday>` (line 17):

```swift
@State private var intentionQuote: String
```

Update `init(...)` — add to the State initializations after line 26:

```swift
self._intentionQuote = State(initialValue: settings.intentionQuote ?? "")
```

- [ ] **Step 2: Add intention quote section to the form**

Add a new section inside the `if isEnabled` block, after the "Blocking Days" section (after line 127, before the closing `}`):

```swift
Section {
    TextField("Why did you set up protection?", text: $intentionQuote, axis: .vertical)
        .lineLimit(2...4)
        .foregroundColor(AppConstants.Colors.text)
} header: {
    Text("Your Intention")
} footer: {
    Text("Shown when you try to disable blocking, to remind you why you started.")
        .foregroundColor(AppConstants.Colors.textSecondary)
}
```

- [ ] **Step 3: Include intentionQuote in saveSettings()**

In `saveSettings()` (lines 158-165), add after `updatedSettings.timeZone = settings.timeZone` (line 163):

```swift
updatedSettings.intentionQuote = intentionQuote.isEmpty ? nil : intentionQuote
updatedSettings.lastDisabledAt = settings.lastDisabledAt
```

- [ ] **Step 4: Build to verify**

Run: `xcodebuild -project Intentions.xcodeproj -scheme Intentions -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 5: Commit**

```bash
git add Intentions/Views/Settings/ScheduleSettingsView.swift
git commit -m "feat: add intention quote editor to schedule settings"
```

---

### Task 8: Run full test suite and verify

**Files:** None (verification only)

- [ ] **Step 1: Run full test suite**

Run: `xcodebuild -project Intentions.xcodeproj -scheme Intentions -destination 'platform=iOS Simulator,name=iPhone 16' test 2>&1 | tail -20`
Expected: All tests pass

- [ ] **Step 2: Fix any failures**

If tests fail, read the output, identify the cause, and fix. Common issues:
- `testScheduleSettingsInitialization` may need updating if it checks property counts
- Mock services may need updating if `DataPersisting` protocol changed

- [ ] **Step 3: Final commit if any fixes were needed**

```bash
git add -A
git commit -m "fix: resolve test failures from disable confirmation redesign"
```
