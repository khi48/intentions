# feature/shield-config-quote — pending Dev Portal capability

**Status:** parked, waiting for Apple Developer Portal to register `App Groups` capability on the App ID `oh.Intent.IntentShieldConfiguration`.

**Branched from:** `main` @ 430a2ac (2026-04-29).

## What this branch contains (vs main)

- `IntentionsShieldConfiguration/IntentionsShieldConfiguration.entitlements` includes `com.apple.security.application-groups = [group.oh.Intent]`.
- `IntentionsShieldAction/IntentionsShieldAction.entitlements` includes `com.apple.security.application-groups = [group.oh.Intent]` (defensive — current code doesn't read App Group, but if a future ShieldAction ever needs to, it's wired).
- Existing `ShieldConfigurationExtension.swift` reads `intentionQuote` from shared `UserDefaults(suiteName: "group.oh.Intent")` to render the user's personalized "Whisper" subtitle on the shield UI. Falls back to the static three-line "Be intentional…" string when not present.

## Why parked

App Store distribution archive fails because the Dev Portal App IDs `oh.Intent.IntentShieldConfiguration` and `oh.Intent.IntentShieldAction` were never registered for the App Group `group.oh.Intent`. Distribution provisioning profile generation refuses to add the capability automatically.

Build 99 (Dec 2025 working TestFlight) had only `family-controls` on these extensions — no App Group. App Group was added to the entitlement files in commit c019dd0 (Apr 19) without a corresponding Dev Portal change.

## What needs to happen before merge

1. Open https://developer.apple.com/account/resources/identifiers/list (Team ID `QUR55L9SP5`).
2. For App ID `oh.Intent.IntentShieldConfiguration`:
   - Open the identifier
   - Enable the `App Groups` capability
   - Save
   - In the next pane, ensure `group.oh.Intent` is in the App Group set
3. Same for `oh.Intent.IntentShieldAction`.
4. Distribution provisioning profile will regenerate next archive. Verify with:
   ```
   xcodebuild archive ... -allowProvisioningUpdates
   ```
5. If it succeeds → fast-forward merge this branch into `main`, bump build, archive, upload.

## Reminder cadence

Re-check the Dev Portal weekly. Apple capability requests for Family Controls / App Groups have historically taken anywhere from minutes to days.

A standalone `.project-notes/shield-config-quote-pending.md` mirrors this so it persists across machines via the iCloud vault.

## Backout plan

If after 2 weeks the capability isn't approved:
- Decide whether to drop the personalized intention quote feature entirely (revert ShieldConfiguration to the static three-line subtitle), OR
- File an expedited request via Apple Developer support.

## Code reference

Key files at this branch's HEAD:
- `IntentionsShieldConfiguration/ShieldConfigurationExtension.swift:75-89` — `subtitleText()` + `storedIntentionQuote()` reading from shared defaults.
- `IntentionsShieldAction/ShieldActionExtension.swift` — stub only; does NOT read App Group, so its inclusion in this branch is defensive (entitlement parity).
