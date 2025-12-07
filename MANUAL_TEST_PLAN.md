# Manual Test Plan - Intent App

**Version**: Pre-Publication
**Date**: December 6, 2025
**Purpose**: Minimal verification of core functionality before publication

---

## Test Environment

- **Device**: Physical iOS device (Screen Time API requires real device)
- **iOS Version**: 17.0+
- **Build Configuration**: Debug or Release

---

## Critical Path Tests (30 minutes)

### 1. First Launch & Setup Flow (10 minutes)

**Objective**: Verify new user onboarding completes successfully

**Steps**:
1. Delete app and reinstall (fresh state)
2. Launch app
3. **Setup Landing**: Tap "Get Started"
4. **Screen Time Authorization**:
   - Tap "Grant Access"
   - Approve Screen Time permission in iOS settings
   - Return to app
5. **Category Mapping**:
   - Wait for app discovery to complete
   - Verify apps are grouped into categories
   - Tap "Continue"
6. **Widget Setup**:
   - Read instructions
   - Tap "Complete Setup"
7. **Verify**: App shows Home screen with "Quick Actions" section

**Expected Results**:
- ✓ No crashes during setup
- ✓ Screen Time permission granted successfully
- ✓ Apps discovered and categorized
- ✓ Setup completes and shows Home screen

**Pass/Fail**: ___________

---

### 2. Quick Action Creation (5 minutes)

**Objective**: Create a Quick Action with selected apps

**Steps**:
1. On Home screen, tap "+ New Quick Action"
2. Enter name: "Focus Mode"
3. Select duration: 30 minutes
4. Tap "Add Apps" button
5. In Family Activity Picker, select 2-3 apps (e.g., Safari, Messages, Notes)
6. Tap "Done"
7. Tap "Save" to create Quick Action
8. Verify Quick Action appears in list

**Expected Results**:
- ✓ Quick Action created successfully
- ✓ Shows correct name and duration
- ✓ Displays selected apps with icons

**Pass/Fail**: ___________

---

### 3. Session Creation & Active Session (5 minutes)

**Objective**: Start a session from Quick Action and verify apps unlock

**Steps**:
1. Tap on the "Focus Mode" Quick Action you created
2. **Verify Session Started**:
   - Session status banner appears at top
   - Shows countdown timer
   - Shows "End Session" button
3. **Test App Access**:
   - Exit Intent app
   - Open one of the apps you selected (e.g., Safari)
   - Verify it opens normally (not blocked)
4. **Test Blocked App**:
   - Try to open an app NOT in your Quick Action
   - Verify it shows Screen Time shield/block screen

**Expected Results**:
- ✓ Session starts successfully
- ✓ Timer counts down correctly
- ✓ Selected apps are accessible
- ✓ Non-selected apps remain blocked

**Pass/Fail**: ___________

---

### 4. Session Expiration (5 minutes)

**Objective**: Verify apps re-lock when session expires

**Steps**:
1. While session is active, tap "End Session" button
2. Confirm session ends
3. **Verify Re-lock**:
   - Try to open previously accessible app (e.g., Safari)
   - Should now be blocked by Screen Time
4. **Verify Home Screen**:
   - Return to Intent app
   - Session banner should be gone
   - Quick Actions should be available again

**Expected Results**:
- ✓ Session ends successfully
- ✓ Apps re-lock immediately
- ✓ UI returns to normal state

**Pass/Fail**: ___________

---

### 5. Protected Hours (5 minutes)

**Objective**: Verify schedule-based blocking works

**Steps**:
1. Tap Settings tab
2. Tap "When Intent is Active" row
3. **Configure Schedule**:
   - Ensure "Schedule Enabled" is ON
   - Set active hours to current time + 1 hour to current time + 2 hours
   - Or set to exclude current day to test "inactive" state
4. Return to Settings
5. **Verify Status**:
   - If current time is within active hours: Shows "Active" / "Enabled"
   - If current time is outside active hours: Shows "Inactive" / "Open Access"

**Expected Results**:
- ✓ Schedule can be configured
- ✓ Status reflects current time vs schedule
- ✓ Changes save correctly

**Pass/Fail**: ___________

---

## Edge Cases (Optional - 10 minutes)

### 6. Multiple Sessions

**Steps**:
1. Create second Quick Action with different apps
2. Start session from first Quick Action
3. Try to start second session while first is active
4. Verify: Should end first session and start second

**Pass/Fail**: ___________

---

### 7. App Backgrounding

**Steps**:
1. Start a session
2. Background the Intent app (go to home screen)
3. Wait 30 seconds
4. Return to Intent app
5. Verify session timer still running correctly

**Pass/Fail**: ___________

---

### 8. Quick Action Editing

**Steps**:
1. Long-press existing Quick Action
2. Tap "Edit"
3. Change name, duration, or apps
4. Save changes
5. Verify changes reflected in list

**Pass/Fail**: ___________

---

### 9. Quick Action Deletion

**Steps**:
1. Long-press existing Quick Action
2. Tap "Delete"
3. Confirm deletion
4. Verify Quick Action removed from list

**Pass/Fail**: ___________

---

## Test Results Summary

**Date Tested**: ___________
**Tester**: ___________
**Build Version**: ___________

**Critical Tests Passed**: ____ / 5
**Edge Cases Passed**: ____ / 4

**Issues Found**:
-
-
-

**Ready for Publication**: YES / NO

---

## Known Limitations

The following features are not yet implemented and should not be tested:
- Widget functionality (placeholder only)
- Notifications (NotificationService exists but may not be fully integrated)
- App usage statistics
- Session history

---

## Notes for Tester

1. **Screen Time Permission is Required**: This app cannot function without Screen Time access. If permission is denied, the core functionality will not work.

2. **Physical Device Required**: Screen Time APIs do not work in iOS Simulator. All testing must be on a real device.

3. **First App Discovery Takes Time**: The category mapping step may take 30-60 seconds to discover and categorize all installed apps. This is normal.

4. **Some Apps Cannot Be Blocked**: System apps and certain Apple apps cannot be blocked by Screen Time API. This is an iOS limitation, not a bug.

5. **Reset Instructions**: To fully reset the app for retesting:
   - Delete app from device
   - Go to Settings > Screen Time > App Limits
   - Remove any limits set by Intent app
   - Reinstall app

---

## Post-Test Actions

After completing manual testing:

1. **Document all issues** found in GitHub Issues or bug tracker
2. **Update README** if any functionality doesn't match documentation
3. **Fix critical bugs** before publication
4. **Re-test** after fixes are applied
5. **Sign off** on test plan when all critical tests pass

---

*This test plan covers the minimum viable functionality needed for v1.0 publication. More comprehensive testing should be performed for major releases.*
