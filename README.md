# Intent - Mindful Phone Usage App

## Table of Contents
1. [Problem Definition & Vision](#problem-definition--vision)
2. [Requirements Gathering](#requirements-gathering)
3. [Technical Architecture Planning](#technical-architecture-planning)
4. [Design & Specification](#design--specification)
5. [Implementation Strategy](#implementation-strategy)
6. [Project Structure & Standards](#project-structure--standards)

---

## Problem Definition & Vision

### The Problem
Modern smartphone usage has become increasingly unconscious and compulsive. Users unlock their phones dozens of times per day without a clear purpose, leading to:
- **Time waste**: Hours lost to mindless scrolling and app-hopping
- **Reduced productivity**: Constant interruptions breaking focus and flow states
- **Mental health impacts**: Anxiety, FOMO, and dopamine-seeking behavior
- **Lack of intentionality**: Actions driven by habit rather than conscious choice

Existing solutions (screen time limits, app blockers) are insufficient because they:
- Block apps entirely rather than encouraging mindful use
- Require pre-planning that doesn't match dynamic daily needs
- Create binary all-or-nothing states
- Don't address the moment of temptation when unlocking the phone

### The Vision
**Intent** reimagines smartphone usage by making intentionality the default state through Quick Actions. Instead of having free access and trying to restrict yourself, you start with everything blocked and use pre-configured Quick Actions to unlock specific apps for specific durations.

**Core Philosophy**: Every session should be deliberate and pre-planned, not an ad-hoc decision made in the moment of temptation.

### Target Users
1. **Knowledge Workers**: People who need deep focus for creative/analytical work
2. **Students**: Individuals studying who struggle with phone distractions
3. **Mindfulness Practitioners**: Users seeking greater awareness in digital life
4. **Parents**: Adults modeling healthy phone habits for children
5. **Productivity Enthusiasts**: People optimizing their time and attention

### Success Criteria
The app succeeds if users:
- Unlock their phone with clear purpose rather than habit
- Reduce overall screen time without feeling restricted
- Experience less anxiety and more control over phone usage
- Complete phone sessions faster (get what they need and put phone down)
- Report increased awareness of their digital consumption patterns

---

## Requirements Gathering

### Functional Requirements

#### FR-1: Default App Blocking
**Priority**: CRITICAL
**Description**: All apps (except system essentials) must be blocked by default when the user unlocks their phone.
**Acceptance Criteria**:
- Blocking applies immediately upon fresh device unlock
- System apps (Phone, Messages, Settings) remain accessible
- Blocking persists across device restarts
- User cannot bypass blocking without explicitly creating a session

#### FR-2: Quick Action Interface
**Priority**: CRITICAL
**Description**: Users create and use Quick Actions as the primary way to start sessions.
**Acceptance Criteria**:
- Quick Actions are pre-configured session templates
- One-tap to start a session with specific apps and duration
- Users can create, edit, delete, and reorder Quick Actions
- Drag-and-drop reordering supported
- Icon, name, and color customization
- Quick Actions directly include selected apps and categories (no app groups)

#### FR-3: App Blocking
**Priority**: HIGH
**Description**: All apps blocked by default using `.all(except:)` category policy. Sessions allow specific apps temporarily.

#### FR-4: Session Management
**Priority**: CRITICAL
**Description**: Active sessions grant temporary access to selected apps for specified duration.
**Acceptance Criteria**:
- Sessions start only after user explicitly creates them
- Countdown timer shows remaining time
- Sessions end automatically when time expires
- User can manually end session early
- Only one session active at a time
- Session state persists across app restarts

#### FR-5: Session Customization
**Priority**: HIGH
**Description**: Quick Actions support flexible session configuration.
**Acceptance Criteria**:
- Quick Actions include individual apps or categories
- Users can enable/disable website access per Quick Action
- Duration is customizable for each Quick Action
- Quick Actions support subtitle/description for clarity
- Usage tracking to show most-used Quick Actions

#### FR-6: Protected Hours Schedule
**Priority**: HIGH
**Description**: Define time periods when blocking is always enforced.
**Acceptance Criteria**:
- Users set start/end times for protected hours
- Different schedules for weekdays/weekends optional
- Protected hours prevent any app access
- Visual indication when protected hours are active
- Can be temporarily overridden with authentication

#### FR-7: Widget Integration
**Priority**: MEDIUM
**Description**: Lock screen widget shows current blocking status and session info.
**Acceptance Criteria**:
- Widget displays "Blocked", "Open", or session countdown
- Updates in real-time during sessions
- Shows protected hours status
- Tapping widget opens app to home screen

#### FR-8: Notification Management
**Priority**: MEDIUM
**Description**: System notifications inform users of session events.
**Acceptance Criteria**:
- Notification when session is about to expire (configurable warning time)
- Notification when session expires
- Notification when protected hours begin
- Users can enable/disable each notification type
- Notifications delivered even when app is closed

**Note**: App Group management (FR-3 in earlier versions) has been removed from the project to simplify the architecture. Quick Actions now directly contain app and category selections.

### Non-Functional Requirements

#### NFR-1: Performance
- App launch time: < 2 seconds on iPhone 12 or newer
- Intention prompt display: < 500ms from unlock
- Session creation: < 1 second from selection to app unlock
- Widget update latency: < 2 seconds after state change
- Memory usage: < 100MB during normal operation

#### NFR-2: Reliability
- Blocking must be 100% reliable (no accidental access)
- Session expiration must trigger even if app is closed
- No data loss during app crashes or force quits
- All state changes persisted immediately
- Background monitoring must work on device restart

#### NFR-3: Security & Privacy
- All data stored locally on device (no cloud sync)
- No telemetry or usage tracking
- Screen Time authorization required before any blocking
- No screenshots allowed on sensitive screens
- Secure storage of user preferences

#### NFR-4: Usability
- First-time setup completable in < 5 minutes
- Intention selection requires < 3 taps for common cases
- Error messages clear and actionable
- Onboarding explains core concepts
- Graceful handling of authorization failures

#### NFR-5: Compatibility
- iOS 17.0+ required (for latest Screen Time APIs)
- iPhone only (iPad future consideration)
- Support for all iPhone screen sizes
- Light and dark mode support
- VoiceOver accessibility support

#### NFR-6: Maintainability
- Swift 6.0 with strict concurrency
- 100% Swift (no Objective-C)
- Comprehensive code documentation
- Modular architecture for future extension
- Unit test coverage for business logic

---

## Technical Architecture Planning

### Technology Stack

#### Core Frameworks
- **SwiftUI**: Declarative UI framework for all interface code
- **SwiftData**: Modern persistence layer (successor to Core Data)
- **Combine**: Reactive programming for data flow (minimal usage - prefer async/await)
- **Swift Concurrency**: Async/await, actors, and structured concurrency

#### Apple APIs
- **Screen Time API**:
  - `FamilyControls`: Authorization and app selection UI
  - `ManagedSettings`: Enforcement of app blocking rules
  - `DeviceActivity`: Background monitoring and session expiration
- **WidgetKit**: Lock screen widget implementation
- **UserNotifications**: Local notification delivery
- **App Groups**: Data sharing between app and extensions

#### Development Tools
- Xcode 15.0+
- Swift 6.0
- iOS Simulator for development
- Physical device required for Screen Time testing

### System Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                        Main App                              │
│  ┌────────────┐  ┌─────────────┐  ┌──────────────────┐     │
│  │   Views    │→ │ ViewModels  │→ │    Services      │     │
│  │  (SwiftUI) │  │ (@Observable)│  │  (Business Logic)│     │
│  └────────────┘  └─────────────┘  └──────────────────┘     │
│                          ↓                  ↓                │
│                  ┌──────────────┐  ┌──────────────────┐     │
│                  │  SwiftData   │  │  ManagedSettings │     │
│                  │   Models     │  │      Store       │     │
│                  └──────────────┘  └──────────────────┘     │
└─────────────────────────────────────────────────────────────┘
                          ↓                  ↓
                  ┌──────────────────────────────────────┐
                  │      App Group UserDefaults          │
                  │     (group.oh.Intent)                │
                  └──────────────────────────────────────┘
                          ↑                  ↑
        ┌─────────────────┴──────┬───────────┴──────────────┐
        │                        │                           │
┌───────▼────────┐   ┌───────────▼──────────┐   ┌──────────▼─────────┐
│ Widget         │   │ DeviceActivity       │   │ Notification       │
│ Extension      │   │ Monitor Extension    │   │ Service Extension  │
│                │   │                      │   │                    │
│ (Lock Screen)  │   │ (Background Process) │   │ (Future)           │
└────────────────┘   └──────────────────────┘   └────────────────────┘
```

### Data Flow Architecture

#### Session Creation Flow
```
User Unlocks Phone
    ↓
HomeView displays Quick Actions
    ↓
User taps a Quick Action
    ↓
QuickAction.createSession() generates IntentionSession
    (uses apps/categories directly from Quick Action)
    ↓
ContentViewModel.startSession(session)
    ↓
ScreenTimeService.allowApps(apps, categories, duration)
    ↓
ManagedSettingsStore.shield.applicationCategories = .all(except: selectedApps)
    ↓
DeviceActivityCenter schedules expiration event
    ↓
SessionStatusViewModel updates UI with countdown
    ↓
Widget updated via App Group UserDefaults
```

#### Session Expiration Flow
```
Session Timer Expires
    ↓
DeviceActivity triggers threshold event
    ↓
DeviceActivityMonitorExtension.eventDidReachThreshold()
    ↓
Extension validates session (5 checks)
    ↓
Extension calls restoreDefaultBlocking()
    ↓
ManagedSettingsStore.shield.applicationCategories = .all()
    ↓
Extension sets UserDefaults "intentions.session.expired" = true
    ↓
Main app observes UserDefaults change
    ↓
ContentViewModel.handleSessionExpiration()
    ↓
UI updates to show "Blocked" state
    ↓
Widget reloads with "Blocked" status
```

#### Widget Update Flow
```
App State Changes (session start/end/blocking change)
    ↓
ContentViewModel or ScreenTimeService
    ↓
Updates App Group UserDefaults:
  - intentions.widget.blockingStatus
  - intentions.widget.sessionTitle
  - intentions.widget.sessionEndTime
  - intentions.widget.lastUpdate
    ↓
WidgetCenter.shared.reloadTimelines(ofKind: "IntentionsWidget")
    ↓
Widget Provider's getTimeline() called
    ↓
Widget reads UserDefaults
    ↓
Widget displays current state
```

### Key Architectural Decisions

#### Decision 1: SwiftData vs Core Data
**Choice**: SwiftData
**Rationale**:
- Modern Swift-first API with macro support
- Better SwiftUI integration
- Type-safe queries
- Reduced boilerplate
- Future-proof (Apple's recommended path)

#### Decision 2: @Observable vs ObservableObject
**Choice**: @Observable (Swift 5.9+)
**Rationale**:
- More efficient (publishes only on actual changes)
- Less boilerplate (no @Published wrappers)
- Better performance (fine-grained observation)
- Recommended by Apple for new development

#### Decision 3: Centralized vs Distributed Services
**Choice**: Centralized service layer (ScreenTimeService)
**Rationale**:
- Single source of truth for Screen Time state
- Easier testing with mock services
- Clear separation of concerns
- Prevents duplicate API calls

#### Decision 4: UserDefaults vs File-based IPC
**Choice**: App Group UserDefaults for widget communication
**Rationale**:
- Built-in synchronization
- Simple key-value API
- Atomic updates
- Well-documented Apple approach for widget data

#### Decision 5: DeviceActivity vs Timer for Session Expiration
**Choice**: DeviceActivity with UserDefaults coordination
**Rationale**:
- Works even when app is closed/terminated
- System-managed lifecycle
- Reliable background execution
- Required for true "always blocking" guarantee

---

## Design & Specification

### Data Models

#### IntentionsSession
```swift
@Model
final class IntentionsSession: Identifiable {
    @Attribute(.unique) var id: UUID
    var title: String
    var startTime: Date
    var endTime: Date
    var allowedApps: [AllowedApp]
    var isActive: Bool
    var createdAt: Date
    var expirationNotified: Bool

    init(title: String, duration: TimeInterval, allowedApps: [AllowedApp]) {
        self.id = UUID()
        self.title = title
        self.startTime = Date()
        self.endTime = Date().addingTimeInterval(duration)
        self.allowedApps = allowedApps
        self.isActive = true
        self.createdAt = Date()
        self.expirationNotified = false
    }
}
```

#### AllowedApp
```swift
@Model
final class AllowedApp: Identifiable {
    @Attribute(.unique) var id: UUID
    var bundleIdentifier: String
    var name: String
    var token: Data  // FamilyControls application token
    var addedAt: Date

    init(bundleIdentifier: String, name: String, token: Data) {
        self.id = UUID()
        self.bundleIdentifier = bundleIdentifier
        self.name = name
        self.token = token
        self.addedAt = Date()
    }
}
```

#### QuickAction
```swift
struct QuickAction: Identifiable, Codable, Sendable {
    let id: UUID
    var name: String
    var subtitle: String?
    var iconName: String
    var color: Color  // Stored as hex string
    var duration: TimeInterval

    // Apps and categories directly selected for this Quick Action
    var individualApplications: Set<ApplicationToken>
    var individualCategories: Set<ActivityCategoryToken>

    var allowAllWebsites: Bool
    var isEnabled: Bool
    var usageCount: Int
    var lastUsed: Date?
    var sortOrder: Int

    // Create an IntentionSession from this Quick Action
    func createSession() throws -> IntentionSession
}
```

#### ScheduleSettings
```swift
@Model
final class ScheduleSettings {
    var isEnabled: Bool
    var startTime: Date  // Uses Date for time component
    var endTime: Date
    var enabledDays: Set<Weekday>
    var allowOverride: Bool
    var requireAuthentication: Bool

    enum Weekday: String, Codable {
        case monday, tuesday, wednesday, thursday, friday, saturday, sunday
    }

    func isCurrentlyActive() -> Bool {
        // Implementation checks current time against schedule
    }
}
```

#### NotificationSettings
```swift
@Model
final class NotificationSettings {
    var sessionExpiringEnabled: Bool
    var sessionExpiringWarningMinutes: Int  // Default: 5
    var sessionExpiredEnabled: Bool
    var protectedHoursStartEnabled: Bool
    var protectedHoursEndEnabled: Bool

    init() {
        self.sessionExpiringEnabled = true
        self.sessionExpiringWarningMinutes = 5
        self.sessionExpiredEnabled = true
        self.protectedHoursStartEnabled = false
        self.protectedHoursEndEnabled = false
    }
}
```

### Service Layer Specifications

#### ScreenTimeService
**Purpose**: Central service for all Screen Time API interactions

**Responsibilities**:
- Manage authorization state
- Apply/remove app blocking rules
- Create and monitor sessions
- Handle session expiration
- Update widget with blocking status

**Key Methods**:
```swift
class ScreenTimeService: @unchecked Sendable {
    // Initialization
    func initialize() async throws

    // Authorization
    func requestAuthorization() async throws
    func authorizationStatus() async -> AuthorizationStatus

    // Blocking Management
    func blockAllApps() async throws
    func allowAllAccess() async throws
    func startSession(allowing apps: [AllowedApp], duration: TimeInterval) async throws
    func endCurrentSession() async throws

    // State Queries
    func isBlocking() -> Bool
    func hasActiveSession() -> Bool

    // Widget Communication
    func updateWidgetBlockingStatus(isBlocking: Bool)
}
```

**Implementation Notes**:
- Singleton pattern (shared instance)
- `@unchecked Sendable` with internal locks for thread safety
- Uses `ManagedSettingsStore()` for enforcement
- Uses `DeviceActivityCenter()` for scheduling
- Validates all state transitions

#### NotificationService
**Purpose**: Schedule and deliver local notifications for session events

**Responsibilities**:
- Request notification permissions
- Schedule session expiring/expired notifications
- Schedule protected hours notifications
- Cancel pending notifications when sessions end early

**Key Methods**:
```swift
class NotificationService: @unchecked Sendable {
    // Permissions
    func requestAuthorization() async throws -> Bool
    func notificationSettings() async -> UNNotificationSettings

    // Session Notifications
    func scheduleSessionExpiringNotification(sessionEndTime: Date, warningMinutes: Int)
    func scheduleSessionExpiredNotification(sessionEndTime: Date)
    func cancelSessionNotifications()

    // Protected Hours
    func scheduleProtectedHoursNotifications(settings: ScheduleSettings)
    func cancelProtectedHoursNotifications()
}
```

**Implementation Notes**:
- Singleton pattern
- Uses `UNUserNotificationCenter`
- Notification identifiers: `session.expiring`, `session.expired`, `protected.start`, `protected.end`
- Checks `NotificationSettings` before scheduling

### Interface Contracts

#### App Group UserDefaults Keys
All widget communication uses `UserDefaults(suiteName: "group.oh.Intent")`

**Session State**:
- `intentions.currentSessionId` (String): Active session UUID
- `intentions.session.expired` (Bool): Set by extension when session expires
- `intentions.session.expirationTime` (Date): When session ended
- `intentions.session.expiredBy` (String): "DeviceActivityMonitor" or "UserCancelled"

**Widget Data**:
- `intentions.widget.blockingStatus` (Bool): True if apps are blocked
- `intentions.widget.sessionTitle` (String): Display name of active session
- `intentions.widget.sessionEndTime` (Date): When current session expires
- `intentions.widget.lastUpdate` (Date): Last time widget data was updated

**DeviceActivity Validation**:
- `intentions.lastScheduledActivity` (String): Activity name that was scheduled
- `intentions.lastScheduledEndTime` (Date): Expected end time of scheduled activity
- `intentions.lastScheduledDuration` (Double): Duration in seconds

**Debug/Monitoring**:
- `intentions.lastIntervalStart` (Date)
- `intentions.lastIntervalEnd` (Date)
- `intentions.lastThresholdReached` (Date)

#### DeviceActivity Naming Convention
- Activity names: `intentions.session.{UUID}`
- Event names: `intentions.session.threshold`

This allows the DeviceActivityMonitor extension to:
1. Validate activity name matches expectations
2. Extract session ID for validation
3. Prevent processing stale/cancelled sessions

---

## Implementation Strategy

### Development Phases

#### Phase 1: Foundation (COMPLETE)
**Goal**: Core architecture and data layer
**Tasks**:
1. ✅ Xcode project setup with proper targets
2. ✅ SwiftData model definitions
3. ✅ Service layer scaffolding
4. ✅ Screen Time API integration
5. ✅ Basic blocking/allowing logic
6. ✅ Authorization flow

**Deliverables**:
- Working ScreenTimeService with block/allow
- Data models persisting correctly
- Authorization request flow

#### Phase 2: Core Features (COMPLETE)
**Goal**: Essential user-facing functionality
**Tasks**:
1. ✅ Home screen with session status
2. ✅ Quick Action creation and editing UI
3. ✅ App/category selection using FamilyActivityPicker
4. ✅ Session creation and management via Quick Actions
5. ✅ Session countdown timer with seconds
6. ✅ Manual session end
7. ✅ DeviceActivity session expiration

**Deliverables**:
- Users can create Quick Actions with custom apps/categories
- Apps unlock during session
- Apps relock when session expires
- UI reflects current state accurately

#### Phase 3: Quick Actions (COMPLETE)
**Goal**: Streamlined session creation UX
**Tasks**:
1. ✅ Quick Action CRUD operations with app/category selection
2. ✅ Quick Action editor interface with FamilyActivityPicker
3. ✅ Quick Action reordering (drag & drop)
4. ✅ One-tap session start from Quick Actions
5. ✅ Removed ad-hoc intention prompt (Quick Actions only)
6. ✅ Removed app group management (simplified to direct selection)

**Deliverables**:
- Users create Quick Actions with direct app/category selection
- No intermediate app group management layer
- Simplified UX with no ad-hoc session creation
- Reorderable Quick Actions

#### Phase 4: Protected Hours (COMPLETE)
**Goal**: Time-based automatic blocking
**Tasks**:
1. ✅ ScheduleSettings model
2. ✅ Schedule configuration UI
3. ✅ Schedule activation/deactivation logic
4. ✅ Protected hours enforcement
5. ✅ Schedule-aware session creation

**Deliverables**:
- Users can set protected hours
- Blocking automatically enforces during protected hours
- UI shows protected hours status

#### Phase 6: Widget Integration (COMPLETE)
**Goal**: Lock screen status visibility
**Tasks**:
1. ✅ Widget extension target
2. ✅ Circular lock screen widget design
3. ✅ App Group UserDefaults communication
4. ✅ Widget timeline provider
5. ✅ Real-time widget updates during sessions
6. ✅ Widget state synchronization fixes

**Deliverables**:
- Lock screen widget shows blocking status
- Widget updates when sessions start/end
- Widget shows countdown during active sessions
- Widget correctly reflects protected hours

#### Phase 7: Notifications (IN PROGRESS)
**Goal**: Timely user notifications
**Tasks**:
1. ✅ NotificationService implementation
2. ✅ NotificationSettings model
3. ✅ Notification permission request
4. ⏳ Session expiring notification (5min warning)
5. ⏳ Session expired notification
6. ⏳ Protected hours start notification
7. ⏳ Notification settings UI

**Deliverables**:
- Users receive session expiration warnings
- Notifications delivered even when app closed
- User control over notification types

#### Phase 8: Polish & Refinement (PENDING)
**Goal**: Production-ready quality
**Tasks**:
1. ⏳ Comprehensive error handling
2. ⏳ Loading states and progress indicators
3. ⏳ Empty states for all screens
4. ⏳ Haptic feedback
5. ⏳ VoiceOver accessibility
6. ⏳ Dark mode refinement
7. ⏳ Animation polish

**Deliverables**:
- Smooth, polished user experience
- Accessible to VoiceOver users
- Graceful error handling
- Professional visual quality

#### Phase 9: Testing & Optimization (PENDING)
**Goal**: Robust, performant app
**Tasks**:
1. ⏳ Unit tests for services
2. ⏳ UI tests for critical flows
3. ⏳ Performance profiling
4. ⏳ Memory leak detection
5. ⏳ Device testing (various models)
6. ⏳ Edge case handling

**Deliverables**:
- Test coverage for business logic
- No memory leaks
- Smooth performance on older devices
- Validated on multiple iOS versions

### Current Status (December 2025)
**Phase**: Phase 7 (Notifications) - 60% complete

**Architecture Simplification** (December 2025):
- ✅ Removed ad-hoc intention prompt - Quick Actions are now the only way to start sessions
- ✅ Removed app group management - Quick Actions directly contain app/category selections
- ✅ Streamlined UX reduces decision fatigue by encouraging pre-planned sessions
- ✅ Simplified data model with fewer layers of abstraction

**Recent Achievements**:
- ✅ Fixed critical widget race condition bug
- ✅ Renamed app from "Intentions" to "Intent"
- ✅ Added seconds to session countdown timer
- ✅ Updated category icons with rounded corners
- ✅ Simplified session creation to Quick Actions only
- ✅ All core functionality working as a functional prototype

**Immediate Next Steps**:
1. Complete notification implementation
2. Add notification settings UI
3. Test notification delivery reliability
4. Begin Phase 8 polish work

---

## Project Structure & Standards

### File Organization

```
Intentions/
├── App/
│   ├── IntentionsApp.swift              # App entry point
│   └── Info.plist
│
├── Models/
│   ├── IntentionsSession.swift          # Session data model
│   ├── QuickAction.swift                # Quick action data model
│   ├── ScheduleSettings.swift           # Protected hours settings
│   └── NotificationSettings.swift       # Notification preferences
│
├── Services/
│   ├── ScreenTimeService.swift          # Screen Time API wrapper
│   └── NotificationService.swift        # Local notifications
│
├── ViewModels/
│   ├── ContentViewModel.swift           # Root view state management
│   ├── SessionStatusViewModel.swift     # Session countdown & status
│   └── AppGroupEditorViewModel.swift    # App group editing
│
├── Views/
│   ├── MainViews/
│   │   ├── HomeView.swift               # Main screen with Quick Actions
│   │   └── QuickActionEditorSheet.swift # Quick Action creation/editing
│   │
│   ├── Setup/
│   │   ├── SetupLandingView.swift       # Onboarding entry
│   │   └── ScreenTimeAuthorizationStepView.swift # Screen Time permission
│   │
│   ├── Settings/
│   │   └── SettingsView.swift           # App settings
│   │
│   └── Components/
│       ├── SessionStatusView.swift      # Session status card
│       ├── QuickActionButton.swift      # Quick action UI
│       └── AppPickerButton.swift        # App selection button
│
├── Utilities/
│   ├── AppConstants.swift               # Colors, strings, config
│   └── Extensions/
│       └── Date+Extensions.swift        # Date helpers
│
└── Resources/
    └── Assets.xcassets/                 # Images, colors, icons

IntentionsWidget/
├── IntentionsWidget.swift               # Widget entry point
├── IntentionsWidgetProvider.swift       # Timeline provider
└── Info.plist

IntentionsDeviceActivityMonitor/
├── DeviceActivityMonitorExtension.swift # Background monitor
└── Info.plist
```

### Coding Standards

#### Swift Style Guide

**Naming Conventions**:
```swift
// Types: UpperCamelCase
class ScreenTimeService { }
struct IntentionsSession { }
enum SetupStep { }

// Variables/Functions: lowerCamelCase
var currentSession: IntentionsSession?
func startNewSession() { }

// Constants: lowerCamelCase (prefer enum for namespacing)
enum AppConstants {
    static let sessionMinDuration: TimeInterval = 60
}

// Booleans: Use "is", "has", "should" prefixes
var isActive: Bool
var hasPermission: Bool
var shouldBlockApps: Bool
```

**Concurrency**:
```swift
// Prefer async/await over completion handlers
func requestAuthorization() async throws -> Bool {
    // implementation
}

// Mark async functions with await
let authorized = await service.requestAuthorization()

// Use @MainActor for UI code
@MainActor
final class ContentViewModel: ObservableObject {
    // All methods run on main thread
}

// Use actors for shared mutable state
actor SessionCoordinator {
    private var activeSession: Session?

    func updateSession(_ session: Session) {
        activeSession = session
    }
}
```

**SwiftUI Best Practices**:
```swift
// Extract subviews for readability
struct HomeView: View {
    var body: some View {
        VStack {
            headerSection
            sessionStatusSection
            quickActionsSection
        }
    }

    private var headerSection: some View {
        Text("Intent")
            .font(.largeTitle)
    }
}

// Use @Observable for view models (Swift 5.9+)
@Observable
final class SessionStatusViewModel {
    var remainingTime: TimeInterval = 0
    var sessionTitle: String = ""
}

// Avoid massive view hierarchies - extract components
// Good: SessionStatusCard, QuickActionButton
// Bad: 200-line body property
```

**Error Handling**:
```swift
// Define custom error types
enum AppError: LocalizedError {
    case screenTimeAuthorizationFailed
    case sessionCreationFailed(reason: String)
    case noActiveSession

    var errorDescription: String? {
        switch self {
        case .screenTimeAuthorizationFailed:
            return "Screen Time authorization not granted"
        case .sessionCreationFailed(let reason):
            return "Failed to create session: \(reason)"
        case .noActiveSession:
            return "No active session found"
        }
    }
}

// Handle errors gracefully in UI
do {
    try await screenTimeService.startSession(apps: apps, duration: duration)
} catch {
    errorMessage = error.localizedDescription
    showError = true
}
```

**Logging Standards**:
```swift
import OSLog

// Create logger per module
let logger = Logger(subsystem: "oh.Intent", category: "ScreenTimeService")

// Use appropriate log levels
logger.debug("Debug info during development")
logger.info("ℹ️ Informational message")
logger.notice("📋 Significant event occurred")
logger.warning("⚠️ Warning condition")
logger.error("❌ Error occurred")
logger.critical("🚨 Critical failure")

// Use privacy annotations for sensitive data
logger.info("Session created: \(sessionId, privacy: .public)")
logger.info("User selected apps: \(appNames, privacy: .private)")
```

### Testing Approach

**Unit Testing**:
```swift
import XCTest
@testable import Intentions

final class ScreenTimeServiceTests: XCTestCase {
    var service: ScreenTimeService!

    override func setUp() {
        super.setUp()
        service = ScreenTimeService()
    }

    func testSessionCreationValidatesApps() async throws {
        // Given
        let emptyApps: [AllowedApp] = []

        // When/Then
        await XCTAssertThrowsError(
            try await service.startSession(allowing: emptyApps, duration: 300)
        )
    }
}
```

**Mock Services**:
```swift
// Create mock versions for testing
final class MockScreenTimeService: ScreenTimeService {
    var isBlocking = false
    var authStatus: AuthorizationStatus = .approved

    override func blockAllApps() async throws {
        isBlocking = true
    }

    override func authorizationStatus() async -> AuthorizationStatus {
        return authStatus
    }
}
```

### Git Workflow

**Branch Strategy**:
- `main`: Production-ready code
- Feature branches: Short-lived, merged via PR
- No direct commits to main (except for solo development)

**Commit Messages**:
```
<type>: <short summary>

<optional body>

<optional footer>
```

Types: `feat`, `fix`, `refactor`, `docs`, `test`, `chore`

Example:
```
feat: Add session countdown with seconds display

Updated SessionStatusViewModel.formatTime() to include seconds
in the countdown timer display. Format now shows "25m 43s"
instead of just "25m".

🤖 Generated with Claude Code
```

**Pre-commit Checklist**:
- [ ] Code builds without warnings
- [ ] No force-unwraps (`!`) unless absolutely necessary
- [ ] No print statements (use Logger)
- [ ] No commented-out code
- [ ] Formatting consistent with project style

### Documentation Standards

**Code Documentation**:
```swift
/// Starts a new blocking session with specified apps and duration
///
/// This method:
/// 1. Validates the app list and duration
/// 2. Schedules session expiration via DeviceActivity
/// 3. Updates ManagedSettingsStore to allow selected apps
/// 4. Notifies widgets of new session state
///
/// - Parameters:
///   - apps: Array of apps to allow during session
///   - duration: Session length in seconds (minimum 60)
/// - Throws: `AppError.sessionCreationFailed` if validation fails
/// - Note: Only one session can be active at a time
func startSession(allowing apps: [AllowedApp], duration: TimeInterval) async throws {
    // Implementation
}
```

**File Headers**:
```swift
//
//  ScreenTimeService.swift
//  Intent
//
//  Central service for Screen Time API interactions.
//  Handles authorization, blocking, and session management.
//
```

---

## Appendix

### Known Issues & Limitations

1. **Simulator Limitations**: Screen Time APIs don't work in iOS Simulator - physical device required for testing
2. **DeviceActivity Delays**: Session expiration can have up to 30-second delay in some cases
3. **Widget Update Latency**: Widget updates may take 1-2 seconds after state changes
4. **Background Refresh**: Requires Background App Refresh to be enabled for reliable session expiration

### Future Enhancements

- [ ] iPad support with adapted layouts
- [ ] iCloud sync for settings (optional)
- [ ] Usage analytics and insights
- [ ] Integration with Health app (screen time tracking)
- [ ] Siri Shortcuts support
- [ ] Family sharing features
- [ ] Custom focus modes integration

### Resources

- [Apple Screen Time API Documentation](https://developer.apple.com/documentation/familycontrols)
- [SwiftData Documentation](https://developer.apple.com/documentation/swiftdata)
- [Swift Concurrency Guide](https://docs.swift.org/swift-book/LanguageGuide/Concurrency.html)
- [Human Interface Guidelines - Screen Time](https://developer.apple.com/design/human-interface-guidelines/screen-time)

---

**Last Updated**: December 6, 2025
**App Version**: 1.0.0 (Prototype)
**iOS Target**: 17.0+
