# Pre-Publication Code Review - Intent App

**Date**: December 6, 2025
**Reviewer**: Claude Code
**Status**: **NOT READY FOR PUBLICATION** - Requires cleanup

---

## Executive Summary

The codebase contains significant **legacy code** and **architectural inconsistencies** that must be addressed before publication. While the core Quick Actions functionality is implemented, there are **AppGroup references throughout the code** despite the README stating this feature has been removed.

### Critical Issues Found
1. ❌ **AppGroup code still exists** - Model, views, and services all reference AppGroups
2. ❌ **Legacy CoreData files** - Old persistence layer not being used
3. ❌ **Unused view files** - IntentionPromptView, AppGroupsView, AppGroupListView still present
4. ❌ **QuickAction model still has appGroupIds** - Inconsistent with README
5. ❌ **Settings UI contains AppGroup management** - UI code for feature that should be removed

---

## Detailed Findings

### 1. AppGroup Model & References

#### Files That MUST Be Removed:
```
❌ Intentions/Models/AppGroup.swift
❌ Intentions/ViewModels/AppGroupsViewModel.swift
❌ Intentions/Views/MainViews/AppGroupsView.swift
❌ Intentions/Views/MainViews/AppGroupListView.swift
❌ Intentions/Views/MainViews/AppGroupEditorSheet.swift
❌ Intentions/Model/AppGroupModel.swift (legacy)
❌ Intentions/Controllers/GroupManager.swift (legacy)
```

#### Files With AppGroup References That Need Updates:

**QuickAction.swift** (Lines 38, 98, 110, 117, 128, 144, 159, 185, 207, 217, 239-261)
- Still has `appGroupIds: Set<UUID>` property
- `createSession(with appGroups:)` method should be `createSession()`
- Remove all app group resolution logic

**SettingsView.swift** (Lines 82-115, 264-277, 296-308, 821-847)
- Contains `AppGroupRow` view component
- Has app group deletion alert
- Has disabled `AppGroupEditorView` sheet
- All AppGroup UI code should be removed

**ContentViewModel.swift** (Multiple references)
- `appGroupsDidChange` property should be removed
- `notifyAppGroupsChanged()` method should be removed
- References in session creation logic

**QuickActionsViewModel.swift**
- Likely has `availableAppGroups` property that should be removed
- Check for app group loading logic

**DataPersistingService.swift**
- Likely has `loadAppGroups()`, `saveAppGroup()`, `deleteAppGroup()` methods
- All AppGroup persistence should be removed

**MockDataPersistenceService.swift**
- Mock AppGroup data and methods should be removed

### 2. Legacy CoreData Files

#### Files That MUST Be Removed:
```
❌ Intentions/CoreData/AppGroup+CoreDataClass.swift
❌ Intentions/CoreData/AppGroup+CoreDataProperties.swift
❌ Intentions/CoreData/UsageSchedule+CoreDataClass.swift
❌ Intentions/CoreData/UsageSchedule+CoreDataProperties.swift
❌ Intentions/CoreData/PersistanceController.swift
```

These are remnants of an old persistence layer and are not used by the current SwiftData implementation.

### 3. Legacy View Files

#### Files That MUST Be Removed:
```
❌ Intentions/Views/MainViews/IntentionPromptView.swift
❌ Intentions/ViewModels/IntentionPromptViewModel.swift
❌ Intentions/Views/MainViews/AppGroupsView.swift
❌ Intentions/Controllers/AppBlockerProtocol.swift
❌ Intentions/Controllers/ScheduleManager.swift
❌ Intentions/ViewModels/HomeViewModel.swift (if not used)
```

These implement the ad-hoc intention prompt feature that was explicitly removed.

### 4. Unused/Legacy Models

#### Files to Review/Remove:
```
⚠️ Intentions/Models/DiscoveredApp.swift
⚠️ Intentions/Models/ScreenTimeStatusInfo.swift
⚠️ Intentions/Models/AppGroupModel.swift (legacy)
⚠️ Intentions/Models/UsageScheduleModel.swift (legacy)
⚠️ Intentions/Extensions/ApplicationExtension.swift
```

### 5. Test Files Referencing AppGroups

#### Test Files That Need Updates:
```
⚠️ IntentionsTests/ModelTests/AppGroupTests.swift
⚠️ IntentionsTests/ViewModels/AppGroupsViewModelTests.swift
⚠️ IntentionsTests/ViewModels/IntentionPromptViewModelTests.swift
⚠️ IntentionsTests/Views/IntentionPromptSupportingViewsTests.swift
⚠️ IntentionsTests/Views/SettingsSupportingViewsTests.swift
⚠️ IntentionsTests/Integration/SettingsIntegrationTests.swift
⚠️ IntentionsTests/Services/DataPersistenceServiceTests.swift
⚠️ IntentionsTests/ModelTests/DataPersistenceIntegrationTests.swift
```

All tests for AppGroup functionality should be removed. Tests for QuickActions should be updated to remove AppGroup dependencies.

---

## Required Changes by File

### HIGH PRIORITY - Must Fix Before Publication

#### 1. QuickAction.swift
```swift
// REMOVE:
var appGroupIds: Set<UUID>

// UPDATE:
func createSession(with appGroups: [AppGroup]) throws -> IntentionSession
// TO:
func createSession() throws -> IntentionSession

// REMOVE all logic that:
- References appGroupIds
- Resolves app groups
- Iterates through appGroups parameter
```

#### 2. SettingsView.swift
```swift
// REMOVE:
- AppGroupRow struct (lines 82-115)
- Delete app group alert (lines 264-277)
- AppGroupEditorView sheet (lines 296-308)
- AppGroupEditorView placeholder (lines 821-847)

// REMOVE from statistics:
- Any "App Groups" count display
```

#### 3. ContentViewModel.swift
```swift
// REMOVE:
var appGroupsDidChange: UUID = UUID()

func notifyAppGroupsChanged() {
    appGroupsDidChange = UUID()
}

// UPDATE session creation to not pass app groups
```

#### 4. QuickActionsViewModel.swift
```swift
// REMOVE:
var availableAppGroups: [AppGroup] = []

// REMOVE:
- Any loadAppGroups() logic
- Any app group filtering/resolution
```

#### 5. DataPersistingService.swift (Protocol)
```swift
// REMOVE methods:
func loadAppGroups() async throws -> [AppGroup]
func saveAppGroup(_ appGroup: AppGroup) async throws
func deleteAppGroup(_ id: UUID) async throws

// VERIFY QuickAction methods don't reference AppGroups
```

---

## Medium Priority - Code Quality Issues

### 1. TODO/FIXME Comments
Need to search for and address:
```bash
grep -r "TODO" Intentions/**/*.swift
grep -r "FIXME" Intentions/**/*.swift
grep -r "HACK" Intentions/**/*.swift
```

### 2. Print Statements vs Logging
Many files still use `print()` instead of `Logger`. Should standardize on OSLog for production:
```swift
// BAD:
print("Session started")

// GOOD:
logger.info("Session started")
```

### 3. Disabled Code Sections
SettingsView has several `.constant(false)` sheet bindings (lines 279, 296):
```swift
// TEMPORARY DISABLED - should either fix or remove
.sheet(isPresented: .constant(false)) {
```

### 4. Error Alert Disabled
SettingsView.swift line 252-256:
```swift
// COMPLETELY DISABLE SettingsView error alerts to prevent presentation conflicts
false  // Only delete confirmation alert remains active
```
This should be properly fixed, not just disabled.

---

## Low Priority - Polish Items

### 1. Missing Documentation
Files lacking proper documentation:
- Many view files have minimal headers
- Service methods lack parameter documentation
- Complex logic needs inline comments

### 2. Magic Numbers
Should be moved to AppConstants:
```swift
// In various files:
.frame(width: 56, height: 56)  // Should be AppConstants.UI.iconSize
try? await Task.sleep(nanoseconds: 500_000_000)  // Should be AppConstants.timeouts...
```

### 3. Test Views Still in Production Code
SettingsView.swift contains test views (lines 1224-1695):
- AllAppsDiscoveryTestView
- IncludeEntireCategoryTestView

These should either be:
- Moved to a separate debug/test target
- Wrapped in `#if DEBUG` conditionals
- Removed entirely for production

---

## Recommended Cleanup Sequence

### Phase 1: Remove Dead Code (1-2 hours)
1. ✅ Delete all legacy CoreData files
2. ✅ Delete AppGroup model file
3. ✅ Delete AppGroupsViewModel
4. ✅ Delete AppGroup view files (AppGroupsView, AppGroupListView, AppGroupEditorSheet)
5. ✅ Delete IntentionPromptView and ViewModel
6. ✅ Delete legacy controller files

### Phase 2: Update Active Code (2-3 hours)
1. ✅ Update QuickAction.swift to remove appGroupIds
2. ✅ Update SettingsView.swift to remove AppGroup UI
3. ✅ Update ContentViewModel.swift to remove app group references
4. ✅ Update QuickActionsViewModel.swift to remove app group logic
5. ✅ Update DataPersistingService protocol and implementation
6. ✅ Update all call sites that use createSession(with:)

### Phase 3: Update Tests (1-2 hours)
1. ✅ Remove AppGroup test files
2. ✅ Update QuickAction tests
3. ✅ Update integration tests
4. ✅ Verify all tests pass

### Phase 4: Code Quality (1-2 hours)
1. ✅ Replace print() with Logger throughout
2. ✅ Fix or remove disabled sheet bindings
3. ✅ Fix error alert presentation
4. ✅ Remove or properly conditionally compile test views
5. ✅ Add missing documentation

### Phase 5: Final Verification (1 hour)
1. ✅ Clean build (no warnings)
2. ✅ All tests passing
3. ✅ Manual testing of core flows:
   - Setup flow
   - Quick Action creation
   - Session creation from Quick Action
   - Session expiration
   - Protected hours
   - Widget updates
4. ✅ Verify README matches implementation

---

## Pre-Publication Checklist

Before publishing, verify:

### Code Quality
- [ ] No AppGroup references in active code
- [ ] No legacy files remain
- [ ] No TODO/FIXME comments in production code
- [ ] All print() replaced with Logger
- [ ] All tests passing
- [ ] No compiler warnings
- [ ] No force unwraps (!) except where absolutely necessary
- [ ] All errors handled gracefully

### Documentation
- [ ] README.md accurately reflects implementation
- [ ] CLAUDE.md updated with current architecture
- [ ] All public methods have documentation comments
- [ ] Complex logic has inline comments

### Functionality
- [ ] Quick Actions work end-to-end
- [ ] Session creation/expiration works
- [ ] Protected hours work correctly
- [ ] Widget updates correctly
- [ ] Notifications deliver properly
- [ ] Category mapping setup works
- [ ] No crashes on common user paths

### Privacy & Security
- [ ] No hardcoded secrets or API keys
- [ ] User data stays on device
- [ ] Screen Time permissions properly requested
- [ ] Notification permissions properly requested
- [ ] No telemetry/tracking code

### App Store Requirements
- [ ] Bundle ID is correct (oh.Intent)
- [ ] App name is "Intent"
- [ ] Privacy manifest included (if required)
- [ ] Proper entitlements configured
- [ ] All assets at correct resolutions
- [ ] App icon present

---

## Estimated Cleanup Time

**Total**: 6-10 hours of focused development work

**Breakdown**:
- Phase 1 (Dead Code Removal): 1-2 hours
- Phase 2 (Active Code Updates): 2-3 hours
- Phase 3 (Test Updates): 1-2 hours
- Phase 4 (Code Quality): 1-2 hours
- Phase 5 (Final Verification): 1 hour

---

## Conclusion

The Intent app has a **solid foundation** but requires significant cleanup before publication. The main issue is **incomplete removal of the AppGroup feature** - while the README states it's been removed, the code still contains extensive AppGroup logic.

**Recommendation**: **DO NOT PUBLISH** until AppGroup code is fully removed and the checklist above is completed.

The cleanup is straightforward but will take 6-10 hours of focused work. Once complete, the app will have a clean, maintainable codebase that matches the simplified architecture described in the README.

---

## Next Steps

1. Start with Phase 1 (dead code removal) - this is the easiest and safest
2. Move to Phase 2 (active code updates) - requires careful testing
3. Update tests in Phase 3
4. Polish in Phase 4
5. Final verification in Phase 5
6. Once checklist is complete, app is ready for publication

Would you like me to begin with Phase 1 now?
