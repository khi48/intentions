# Remove Category Mapping System

## Summary

Strip the entire CategoryMappingService and 12-category setup flow. Replace the complex "smart blocking" strategy with a single `.all(except: tokens)` call. This removes ~800+ lines of code across 10+ files.

## Motivation

- Category mapping requires users to tediously map ALL 12 categories before setup completes
- The "smart blocking" strategy with category analysis and 50-app limit workarounds exists to solve a problem that doesn't apply — the app blocks everything by default and only excepts a few apps per session
- `.all(except: sessionApps)` handles the blocking model directly with no limit concerns (sessions typically allow 1-10 apps)
- Token fragility defensive code (retrySetupValidation, isTrulySetupCompleted) solves a non-existent problem — ApplicationTokens are stable and persist across restarts

## Files to Delete

| File | Lines | Purpose |
|------|-------|---------|
| `Services/CategoryMappingService.swift` | ~550 | Entire category mapping system |
| `Views/Setup/CategoryMappingSetupView.swift` | ~400 | 12-category picker UI |
| `Views/Setup/CategoryMappingStepView.swift` | ~230 | Setup step wrapper |
| `Models/DiscoveredApp.swift` | ~50 | Unused app model |

## Files to Modify

### ScreenTimeService.swift
- Delete `categoryMappingService` property
- Delete `setCategoryMappingService()` method
- Delete `applySmartCategoryBlocking()` (~70 lines)
- Delete `prioritizeAppsForBlocking()` (~12 lines)
- Simplify `allowApps()` to always use `.all(except: tokens)`

### ScreenTimeManaging.swift (protocol)
- Remove `setCategoryMappingService()` from protocol

### MockScreenTimeService.swift
- Remove `setCategoryMappingService()` stub

### ContentViewModel.swift
- Remove `categoryMappingService` property
- Remove `showingCategoryMappingSetup` flag
- Remove `retrySetupValidation()` call in `initializeApp()`
- Remove `setCategoryMappingService()` wiring in `initializeScreenTimeServiceAfterSetup()`
- Remove `checkLegacyCategoryMappingSetupRequired()`

### SetupState.swift
- Remove `categoryMappingCompleted` field
- Remove `withCategoryMappingCompleted()` method
- Remove `categoryMappingAddressed` computed property
- Remove `.categoryMapping` from `SetupStep` enum
- Simplify `isFullSetupComplete` / `isSetupSufficient` to just `screenTimeAuthorized`

### SetupCoordinator.swift
- Remove `categoryMappingService` dependency from init
- Remove category mapping validation from `getCurrentSystemStatus()`
- Remove `.categoryMapping` case from `updateStateForCompletedStep()`
- Remove `SystemStatus.categoryMappingCompleted`

### SetupFlowView.swift
- Remove `.categoryMapping` from `SetupPage` enum
- Remove `categoryMappingContent` view
- Simplify progress indicator (3 steps instead of 4)
- Update page transitions to skip category mapping

### SettingsView.swift
- Remove `categoryMappingSection`
- Remove category mapping debug info from diagnostic section

### QuickActionEditorSheet.swift
- Remove `categoryMappingService` parameter
- Remove `CategoryItemView` struct
- Remove `appsNotInSelectedCategories` logic
- Use native `Label(token)` for category display

### HomeView.swift
- Stop passing `categoryMappingService` to QuickActionEditorSheet

### QuickActionsView.swift
- Stop passing `categoryMappingService` to QuickActionEditorSheet

## Blocking Logic After Change

```swift
// allowApps() becomes:
if !tokens.isEmpty {
    managedSettingsStore.shield.applicationCategories = .all(except: tokens)
} else {
    managedSettingsStore.shield.applicationCategories = .all()
}
```

## Setup Flow After Change

Landing → Screen Time Auth → Always Allowed Info → Widget Setup

`SetupState.isSetupSufficient` = `screenTimeAuthorized` (no category gate)

## Testing Impact

- Tests referencing CategoryMappingService need deletion or updating
- ScreenTimeService tests need updating for simplified blocking logic
- SetupCoordinator tests need updating for removed category step
