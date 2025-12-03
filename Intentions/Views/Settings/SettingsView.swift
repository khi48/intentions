//
//  SettingsView.swift
//  Intentions
//
//  Created by Claude on 12/07/2025.
//

import SwiftUI
@preconcurrency import FamilyControls
import ManagedSettings
import UserNotifications

// MARK: - Settings Navigation Destinations

enum SettingsDestination: Hashable, CaseIterable {
    case notifications
    case privacy
    case dataManagement
    case about
    case setupFlow
    
    // Better practice: Include presentation metadata in the enum
    var title: String {
        switch self {
        case .notifications: return "Notifications"
        case .privacy: return "Privacy"
        case .dataManagement: return "Data Management"
        case .about: return "About"
        case .setupFlow: return "App Setup"
        }
    }
    
    var systemImage: String {
        switch self {
        case .notifications: return "bell.fill"
        case .privacy: return "hand.raised.fill"
        case .dataManagement: return "externaldrive.fill"
        case .about: return "info.circle.fill"
        case .setupFlow: return "gear.badge.checkmark"
        }
    }
}

// MARK: - Supporting Views


struct ScheduleDetailsRow: View {
    let title: String
    let value: String
    let action: () -> Void
    let isDisabled: Bool

    init(title: String, value: String, action: @escaping () -> Void, isDisabled: Bool = false) {
        self.title = title
        self.value = value
        self.action = action
        self.isDisabled = isDisabled
    }

    var body: some View {
        Button(action: isDisabled ? {} : action) {
            HStack {
                Text(title)
                    .foregroundColor(isDisabled ? AppConstants.Colors.disabled : AppConstants.Colors.text)

                Spacer()

                Text(value)
                    .foregroundColor(isDisabled ? AppConstants.Colors.disabled : AppConstants.Colors.textSecondary)

                if !isDisabled {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(AppConstants.Colors.disabled)
                }
            }
        }
        .disabled(isDisabled)
    }
}

struct AppGroupRow: View {
    let group: AppGroup
    let onEdit: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(group.name)
                    .font(.headline)
                    .foregroundColor(AppConstants.Colors.text)
                
                Text("\(group.applications.count) apps")
                    .font(.caption)
                    .foregroundColor(AppConstants.Colors.textSecondary)
            }
            
            Spacer()
            
            Menu {
                Button("Edit", systemImage: "pencil") {
                    onEdit()
                }
                
                Button("Delete", systemImage: "trash", role: .destructive) {
                    onDelete()
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .foregroundColor(AppConstants.Colors.textSecondary)
            }
        }
    }
}

struct StatisticRow: View {
    let title: String
    let value: String
    let icon: String
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(AppConstants.Colors.accent)
                .frame(width: 20)

            Text(title)
                .foregroundColor(AppConstants.Colors.text)
            
            Spacer()
            
            Text(value)
                .fontWeight(.medium)
                .foregroundColor(AppConstants.Colors.textSecondary)
        }
    }
}

struct SettingsRow: View {
    let title: String
    let subtitle: String
    let icon: String
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(AppConstants.Colors.accent)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(AppConstants.Colors.text)

                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(AppConstants.Colors.textSecondary)
            }
            
            Spacer()
        }
    }
}

// MARK: - Main Settings View

/// Main settings view with app group management and Intentions State configuration
struct SettingsView: View {
    @State private var viewModel: SettingsViewModel
    @State private var showingDisableConfirmation = false
    private let onScheduleSettingsChanged: ((ScheduleSettings) async -> Void)?
    private let onViewModelReady: ((SettingsViewModel) -> Void)?
    private let setupCoordinator: SetupCoordinator?
    private let hasActiveSession: Bool
    private let authorizationStatus: AuthorizationStatus
    @EnvironmentObject private var navigationManager: NavigationStateManager

    init(
        dataService: DataPersisting? = nil,
        setupCoordinator: SetupCoordinator? = nil,
        hasActiveSession: Bool = false,
        authorizationStatus: AuthorizationStatus = .notDetermined,
        onScheduleSettingsChanged: ((ScheduleSettings) async -> Void)? = nil,
        onViewModelReady: ((SettingsViewModel) -> Void)? = nil
    ) {
        let service = dataService ?? MockDataPersistenceService()
        self._viewModel = State(wrappedValue: SettingsViewModel(dataService: service))
        self.setupCoordinator = setupCoordinator
        self.hasActiveSession = hasActiveSession
        self.authorizationStatus = authorizationStatus
        self.onScheduleSettingsChanged = onScheduleSettingsChanged
        self.onViewModelReady = onViewModelReady
    }
    
    var body: some View {
        NavigationStack(path: $navigationManager.settingsPath) {
            if viewModel.isLoading {
                ProgressView("Loading Settings...")
                    .foregroundColor(AppConstants.Colors.text)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(AppConstants.Colors.background)
            } else {
                List {
                    // Intentions State Section
                    scheduleSection

                    // Category Mapping Section
                    categoryMappingSection

                    // Statistics Section
                    statisticsSection

                    // General Settings Section
                    generalSection

                }
                .listStyle(.insetGrouped)
                .background(AppConstants.Colors.background)
                .scrollContentBackground(.hidden)
                .navigationDestination(for: SettingsDestination.self) { destination in
                    switch destination {
                    case .notifications:
                        NotificationSettingsView()
                    case .setupFlow:
                        if let coordinator = setupCoordinator {
                            SetupFlowView(
                                setupCoordinator: coordinator,
                                embedInNavigationView: false,
                                forceSetup: true
                            ) {
                                // Handle completion in navigation context
                                print("Navigation: Setup flow completed")
                                navigationManager.resetSettingsNavigation()
                            }
                        } else {
                            Text("Setup not available")
                                .foregroundColor(AppConstants.Colors.textSecondary)
                        }
                    case .privacy, .dataManagement, .about:
                        // Removed sections - should not be reachable
                        EmptyView()
                    }
                }
            }
        }
        .background(AppConstants.Colors.background)
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(.visible, for: .tabBar)
        .alert("Error", isPresented: Binding(
            get: { 
                // COMPLETELY DISABLE SettingsView error alerts to prevent presentation conflicts
                false  // Only delete confirmation alert remains active
            },
            set: { _ in viewModel.clearError() }
        )) {
            Button("OK") {
                viewModel.clearError()
            }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .alert("Delete App Group", isPresented: $viewModel.showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) {
                viewModel.cancelDelete()
            }
            Button("Delete", role: .destructive) {
                Task {
                    await viewModel.executeDelete()
                }
            }
        } message: {
            if let group = viewModel.groupToDelete {
                Text("Are you sure you want to delete '\(group.name)'? This action cannot be undone.")
            }
        }
        // TEMPORARILY DISABLED: Schedule editor sheet to test presentation conflict
        .sheet(isPresented: .constant(false)) {
            ScheduleSettingsView(
                settings: viewModel.scheduleSettings,
                onSave: { settings in
                    Task {
                        await viewModel.updateScheduleSettings(settings)
                        // Notify ContentViewModel of schedule change
                        await onScheduleSettingsChanged?(settings)
                    }
                    viewModel.hideScheduleEditor()
                },
                onCancel: {
                    viewModel.hideScheduleEditor()
                }
            )
        }
        // TEMPORARILY DISABLED: App group editor sheet to test presentation conflict
        .sheet(isPresented: .constant(false)) {
            AppGroupEditorView(
                onSave: { name, apps in
                    Task {
                        await viewModel.createAppGroup(name: name, applications: apps)
                    }
                    viewModel.hideAppGroupEditor()
                },
                onCancel: {
                    viewModel.hideAppGroupEditor()
                }
            )
        }
        .sheet(isPresented: $showingDisableConfirmation) {
            DisableBlockingConfirmationView(
                onConfirm: {
                    showingDisableConfirmation = false
                    Task {
                        await viewModel.toggleScheduleEnabled()
                        // Notify ContentViewModel of schedule change
                        await onScheduleSettingsChanged?(viewModel.scheduleSettings)
                    }
                },
                onCancel: {
                    showingDisableConfirmation = false
                }
            )
        }
        .task {
            await viewModel.loadData()
        }
        .onAppear {
            print("🏠 SETTINGS VIEW: onAppear called")
            print("   - Navigation path count: \(navigationManager.settingsPath.count)")
            onViewModelReady?(viewModel)
            print("   ✅ ViewModel ready callback sent")
        }
    }
    
    // MARK: - Schedule Section
    
    private var scheduleSection: some View {
        Section {
            // Intentions State Toggle
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Protected Hours")
                        .font(.headline)

                    Text("Control when apps are blocked by default")
                        .font(.caption)
                        .foregroundColor(AppConstants.Colors.textSecondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Toggle("", isOn: Binding(
                        get: { viewModel.scheduleSettings.isEnabled },
                        set: { newValue in
                            if newValue {
                                // Enabling - allow immediately
                                Task {
                                    await viewModel.toggleScheduleEnabled()
                                    // Notify ContentViewModel of schedule change
                                    await onScheduleSettingsChanged?(viewModel.scheduleSettings)
                                }
                            } else {
                                // Disabling - show confirmation with friction
                                showingDisableConfirmation = true
                            }
                        }
                    ))

                    Text(viewModel.intentionsStateText)
                        .font(.caption)
                        .foregroundColor(AppConstants.Colors.textSecondary)
                }
            }

            // Schedule Details (always visible)
            ScheduleDetailsRow(
                title: "Blocking Hours",
                value: viewModel.formattedActiveHours,
                action: { viewModel.showScheduleEditor() },
                isDisabled: hasActiveSession
            )

            ScheduleDetailsRow(
                title: "Blocking Days",
                value: viewModel.activeDaysText,
                action: { viewModel.showScheduleEditor() },
                isDisabled: hasActiveSession
            )


            // Show information when disabled due to active session
            if hasActiveSession {
                HStack {
                    Image(systemName: "info.circle")
                        .foregroundColor(AppConstants.Colors.textSecondary)
                    Text("Cannot modify schedule while session is active")
                        .font(.caption)
                        .foregroundColor(AppConstants.Colors.textSecondary)
                }
                .padding(.top, 4)
            }
        } header: {
            Text("Protected Hours")
        } footer: {
            if viewModel.scheduleSettings.isEnabled {
                Text("Apps are blocked by default during the specified times and days. Outside these hours, all apps remain accessible unless you start a focused session.")
            } else {
                Text("Scheduled blocking is disabled. Apps remain accessible by default unless you start a focused session.")
            }
        }
    }


    // MARK: - Statistics Section
    
    private var statisticsSection: some View {
        Section("Usage Statistics") {
            StatisticRow(
                title: "Managed Apps",
                value: "\(viewModel.totalManagedApps)",
                icon: "apps.iphone"
            )
            
            StatisticRow(
                title: "Today's Sessions",
                value: "\(viewModel.todaySessionCount)",
                icon: "calendar"
            )
            
            StatisticRow(
                title: "This Week",
                value: "\(viewModel.weeklySessionCount)",
                icon: "chart.line.uptrend.xyaxis"
            )
        }
    }
    
    // MARK: - General Section

    private var generalSection: some View {
        Section("General") {
            NavigationLink(value: SettingsDestination.notifications) {
                SettingsRow(
                    title: SettingsDestination.notifications.title,
                    subtitle: "Session warnings and reminders",
                    icon: SettingsDestination.notifications.systemImage
                )
            }
        }
    }
    
    // MARK: - Category Mapping Section

    private var categoryMappingSection: some View {
        Section {
            NavigationLink(value: SettingsDestination.setupFlow) {
                SettingsRow(
                    title: SettingsDestination.setupFlow.title,
                    subtitle: "Configure app permissions and category mappings",
                    icon: SettingsDestination.setupFlow.systemImage
                )
            }

            // Greyscale recommendation
            Button(action: {
                openGeneralAccessibilitySettings()
            }) {
                SettingsRow(
                    title: "Enable Greyscale",
                    subtitle: "Opens Settings app. Navigate to: Accessibility → Display & Text Size → Color Filters → Grayscale",
                    icon: "eye.slash"
                )
            }
        } header: {
            Text("Setup")
        }
    }

    // MARK: - Debug Diagnostic Section

    private var debugSetupStateSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                Text("Diagnostic Information")
                    .font(.headline)
                    .foregroundColor(.primary)

                Divider()

                // Authorization Status
                HStack {
                    Image(systemName: "checkmark.shield.fill")
                        .foregroundColor(authorizationStatusColor)
                        .frame(width: 20)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Authorization")
                            .font(.subheadline)
                            .foregroundColor(.primary)
                        Text(authorizationStatusText)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                // Setup State
                if let setupState = setupCoordinator?.setupState {
                    Divider()

                    HStack {
                        Image(systemName: "gearshape.fill")
                            .foregroundColor(setupState.isSetupSufficient ? .green : .orange)
                            .frame(width: 20)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Setup Complete")
                                .font(.subheadline)
                                .foregroundColor(.primary)
                            Text(setupState.isSetupSufficient ? "Yes" : "No")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    // Detailed setup flags
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Setup Details:")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .padding(.top, 4)

                        setupDetailRow("Authorization", value: setupState.screenTimeAuthorized)
                        setupDetailRow("Category Mapping", value: setupState.categoryMappingCompleted)
                        setupDetailRow("System Health", value: setupState.systemHealthValidated)
                    }
                } else {
                    Divider()

                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                            .frame(width: 20)

                        Text("Setup state not available")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                // Has Active Session
                Divider()

                HStack {
                    Image(systemName: hasActiveSession ? "play.circle.fill" : "pause.circle.fill")
                        .foregroundColor(hasActiveSession ? .blue : .gray)
                        .frame(width: 20)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Active Session")
                            .font(.subheadline)
                            .foregroundColor(.primary)
                        Text(hasActiveSession ? "Yes" : "No")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(AppConstants.UI.cornerRadius)
        } header: {
            Text("Debug Diagnostics")
        } footer: {
            Text("This section shows the current state of app initialization. Use this to debug issues when the app isn't working as expected.")
                .foregroundColor(AppConstants.Colors.textSecondary)
        }
    }

    private func setupDetailRow(_ label: String, value: Bool) -> some View {
        HStack(spacing: 4) {
            Image(systemName: value ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.caption2)
                .foregroundColor(value ? .green : .red)
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
            Spacer()
            Text(value ? "Complete" : "Incomplete")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.leading, 8)
    }

    private var authorizationStatusColor: Color {
        switch authorizationStatus {
        case .approved:
            return .green
        case .denied:
            return .red
        case .notDetermined:
            return .orange
        @unknown default:
            return .gray
        }
    }

    private var authorizationStatusText: String {
        switch authorizationStatus {
        case .approved:
            return "Approved"
        case .denied:
            return "Denied"
        case .notDetermined:
            return "Not Determined"
        @unknown default:
            return "Unknown"
        }
    }

    // MARK: - Helper Functions

    /// Open iOS Settings app
    /// Note: Due to iOS sandbox restrictions, we can only open to the app's settings page
    /// User will need to navigate back to root Settings, then: Accessibility → Display & Text Size → Color Filters
    private func openGeneralAccessibilitySettings() {
        // The only officially supported URL is openSettingsURLString which opens to app-specific settings
        // Deep linking to other settings pages is blocked by iOS sandbox permissions
        if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(settingsURL) { success in
                if success {
                    print("✅ Opened Settings (app page)")
                    print("ℹ️  User needs to navigate: < Settings → Accessibility → Display & Text Size → Color Filters")
                } else {
                    print("❌ Failed to open Settings app")
                }
            }
        }
    }
}

// MARK: - Placeholder Views for Navigation

struct ScheduleSettingsView: View {
    let settings: ScheduleSettings
    let onSave: (ScheduleSettings) -> Void
    let onCancel: () -> Void
    
    @State private var isEnabled: Bool
    @State private var startHour: Int
    @State private var endHour: Int
    @State private var selectedDays: Set<Weekday>
    
    init(settings: ScheduleSettings, onSave: @escaping (ScheduleSettings) -> Void, onCancel: @escaping () -> Void) {
        self.settings = settings
        self.onSave = onSave
        self.onCancel = onCancel
        self._isEnabled = State(initialValue: settings.isEnabled)
        self._startHour = State(initialValue: settings.activeHours.lowerBound)
        self._endHour = State(initialValue: settings.activeHours.upperBound)
        self._selectedDays = State(initialValue: settings.activeDays)
    }
    
    var body: some View {
        NavigationView {
            List {
                // Intentions State Toggle
                Section {
                    Toggle("Enable Scheduled Blocking", isOn: $isEnabled)
                        .tint(AppConstants.Colors.accent)
                } header: {
                    Text("Blocking Mode")
                } footer: {
                    Text(isEnabled ? "Apps will only be blocked during specified times and days" : "Apps will be blocked by default 24/7")
                        .foregroundColor(AppConstants.Colors.textSecondary)
                }
                
                if isEnabled {
                    // Active Hours
                    Section {
                        HStack {
                            Text("Start Time")
                                .foregroundColor(AppConstants.Colors.text)
                            Spacer()
                            Picker("Start Hour", selection: $startHour) {
                                ForEach(0..<24) { hour in
                                    Text(hourFormatter.string(from: dateFromHour(hour)))
                                        .tag(hour)
                                }
                            }
                            .pickerStyle(.menu)
                        }
                        
                        HStack {
                            Text("End Time")
                                .foregroundColor(AppConstants.Colors.text)
                            Spacer()
                            Picker("End Hour", selection: $endHour) {
                                ForEach(1..<24) { hour in
                                    Text(hourFormatter.string(from: dateFromHour(hour)))
                                        .tag(hour)
                                }
                            }
                            .pickerStyle(.menu)
                        }
                    } header: {
                        Text("Blocking Hours")
                    } footer: {
                        Text("Apps will be blocked from \(hourFormatter.string(from: dateFromHour(startHour))) to \(hourFormatter.string(from: dateFromHour(endHour)))")
                            .foregroundColor(AppConstants.Colors.textSecondary)
                    }
                    
                    // Active Days
                    Section {
                        ForEach(Weekday.allCases, id: \.self) { day in
                            HStack {
                                Text(day.displayName)
                                    .foregroundColor(AppConstants.Colors.text)
                                Spacer()
                                if selectedDays.contains(day) {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(AppConstants.Colors.accent)
                                }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                toggleDay(day)
                            }
                        }
                        
                        // Quick Select Options
                        VStack(spacing: 8) {
                            HStack {
                                Button("All Days") {
                                    selectedDays = Set(Weekday.allCases)
                                }
                                .buttonStyle(.bordered)
                                .tint(AppConstants.Colors.accent)
                                
                                Button("Weekdays") {
                                    selectedDays = [.monday, .tuesday, .wednesday, .thursday, .friday]
                                }
                                .buttonStyle(.bordered)
                                .tint(AppConstants.Colors.accent)
                                
                                Button("Weekends") {
                                    selectedDays = [.saturday, .sunday]
                                }
                                .buttonStyle(.bordered)
                                .tint(AppConstants.Colors.accent)
                            }
                            
                            Button("Clear All") {
                                selectedDays.removeAll()
                            }
                            .buttonStyle(.bordered)
                            .tint(AppConstants.Colors.destructive)
                        }
                        .padding(.vertical, 8)
                    } header: {
                        Text("Blocking Days")
                    } footer: {
                        Text("Select the days when apps should be blocked by default. At least one day must be selected.")
                            .foregroundColor(AppConstants.Colors.textSecondary)
                    }
                }
            }
            .background(AppConstants.Colors.background)
            .scrollContentBackground(.hidden)
            .navigationTitle("Protected Hours")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { onCancel() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") { 
                        saveSettings()
                    }
                    .disabled(!isValidConfiguration)
                }
            }
        }
    }
    
    private var isValidConfiguration: Bool {
        if !isEnabled { return true }
        return startHour < endHour && !selectedDays.isEmpty
    }
    
    private func toggleDay(_ day: Weekday) {
        if selectedDays.contains(day) {
            selectedDays.remove(day)
        } else {
            selectedDays.insert(day)
        }
    }
    
    private func saveSettings() {
        let updatedSettings = ScheduleSettings()
        updatedSettings.isEnabled = isEnabled
        updatedSettings.activeHours = startHour...endHour
        updatedSettings.activeDays = selectedDays
        updatedSettings.timeZone = settings.timeZone
        
        onSave(updatedSettings)
    }
    
    private var hourFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }
    
    private func dateFromHour(_ hour: Int) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: Date()) ?? Date()
    }
}

struct AppGroupEditorView: View {
    let onSave: (String, Set<ApplicationToken>) -> Void
    let onCancel: () -> Void
    
    var body: some View {
        NavigationView {
            VStack {
                Text("App Group Editor")
                    .font(.title2)
                Text("Coming Soon")
                    .foregroundStyle(.secondary)
            }
            .navigationTitle("New Group")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { onCancel() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") { 
                        onSave("New Group", Set<ApplicationToken>()) 
                    }
                }
            }
        }
    }
}

struct NotificationSettingsView: View {
    @State private var notificationService = NotificationService.shared
    @State private var settings: NotificationSettings
    @State private var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @State private var showingPermissionAlert = false

    init() {
        let service = NotificationService.shared
        self._settings = State(initialValue: service.currentSettings)
    }

    var body: some View {
        List {
            // Permission Status Section
            permissionSection

            // Master Toggle
            if authorizationStatus == .authorized || authorizationStatus == .provisional {
                masterToggleSection
            }

            // Detailed Settings (only if enabled)
            if settings.isEnabled && isAuthorized {
                sessionNotificationsSection

                // Reset button
                Section {
                    Button("Reset to Defaults") {
                        settings.resetToDefaults()
                        Task { await saveSettings() }
                    }
                    .foregroundColor(AppConstants.Colors.destructive)
                }
            }
        }
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(.visible, for: .tabBar)
        .task {
            await loadSettings()
            await notificationService.checkAuthorizationStatus()
            authorizationStatus = notificationService.authorizationStatus
        }
        .alert("Enable Notifications", isPresented: $showingPermissionAlert) {
            Button("Settings") {
                openAppSettings()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("To receive session reminders, please enable notifications in Settings.")
        }
    }

    // MARK: - Permission Section

    private var permissionSection: some View {
        Section {
            HStack {
                Image(systemName: permissionStatusIcon)
                    .foregroundColor(permissionStatusColor)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Notification Permission")
                        .font(.headline)

                    Text(permissionStatusText)
                        .font(.caption)
                        .foregroundColor(AppConstants.Colors.textSecondary)
                }

                Spacer()

                if authorizationStatus == .denied {
                    Button("Settings") {
                        openAppSettings()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                } else if authorizationStatus == .notDetermined {
                    Button("Enable") {
                        Task {
                            await requestPermissions()
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        } footer: {
            Text(permissionFooterText)
                .foregroundColor(AppConstants.Colors.textSecondary)
        }
    }

    // MARK: - Master Toggle Section

    private var masterToggleSection: some View {
        Section {
            Toggle("Enable Notifications", isOn: Binding(
                get: { settings.isEnabled },
                set: { newValue in
                    settings.isEnabled = newValue
                    Task {
                        await saveSettings()
                    }
                }
            ))
            .tint(AppConstants.Colors.accent)
        } footer: {
            Text("Turn off to disable all session-related notifications.")
                .foregroundColor(AppConstants.Colors.textSecondary)
        }
    }

    // MARK: - Session Notifications Section

    private var sessionNotificationsSection: some View {
        Section("Session Reminders") {
            NotificationToggleRow(
                type: .sessionWarning,
                isOn: Binding(
                    get: { settings.sessionWarningsEnabled },
                    set: { newValue in
                        settings.sessionWarningsEnabled = newValue
                        Task { await saveSettings() }
                    }
                )
            )

            NotificationToggleRow(
                type: .sessionCompletion,
                isOn: Binding(
                    get: { settings.sessionCompletionEnabled },
                    set: { newValue in
                        settings.sessionCompletionEnabled = newValue
                        Task { await saveSettings() }
                    }
                )
            )

        }
    }

    // MARK: - Warning Intervals Section

    private var warningIntervalsSection: some View {
        Section {
            ForEach(settings.sortedWarningIntervals, id: \.self) { minutes in
                HStack {
                    Image(systemName: "clock")
                        .foregroundColor(AppConstants.Colors.accent)
                        .frame(width: 20)

                    Text("\(minutes) minute\(minutes == 1 ? "" : "s") before")
                        .foregroundColor(AppConstants.Colors.text)

                    Spacer()

                    Button("Remove") {
                        settings.removeWarningInterval(minutes)
                        Task { await saveSettings() }
                    }
                    .foregroundColor(.red)
                    .font(.caption)
                }
            }

            // Add custom interval button
            Button(action: {
                // For now, add common intervals. Could be made customizable later.
                let newInterval = 10
                if !settings.warningIntervals.contains(newInterval) {
                    settings.addWarningInterval(newInterval)
                    Task { await saveSettings() }
                }
            }) {
                HStack {
                    Image(systemName: "plus.circle")
                        .foregroundColor(AppConstants.Colors.accent)
                    Text("Add 10-minute warning")
                        .foregroundColor(AppConstants.Colors.accent)
                }
            }
        } header: {
            Text("Warning Times")
        } footer: {
            Text("Choose when to receive warnings before your session ends.")
                .foregroundColor(AppConstants.Colors.textSecondary)
        }
    }


    // MARK: - Helper Properties

    private var isAuthorized: Bool {
        authorizationStatus == .authorized || authorizationStatus == .provisional
    }

    private var permissionStatusIcon: String {
        switch authorizationStatus {
        case .authorized, .provisional:
            return "checkmark.circle.fill"
        case .denied:
            return "xmark.circle.fill"
        case .notDetermined:
            return "questionmark.circle.fill"
        @unknown default:
            return "questionmark.circle.fill"
        }
    }

    private var permissionStatusColor: Color {
        switch authorizationStatus {
        case .authorized, .provisional:
            return AppConstants.Colors.textSecondary
        case .denied:
            return .red
        case .notDetermined:
            return .orange
        @unknown default:
            return .gray
        }
    }

    private var permissionStatusText: String {
        switch authorizationStatus {
        case .authorized:
            return "Notifications are enabled"
        case .provisional:
            return "Quiet notifications enabled"
        case .denied:
            return "Notifications are disabled"
        case .notDetermined:
            return "Permission not requested"
        @unknown default:
            return "Unknown status"
        }
    }

    private var permissionFooterText: String {
        switch authorizationStatus {
        case .authorized, .provisional:
            return "Intent can send you session reminders and completion notifications."
        case .denied:
            return "To enable notifications, go to Settings > Notifications > Intent."
        case .notDetermined:
            return "Allow notifications to receive session reminders."
        @unknown default:
            return ""
        }
    }

    // MARK: - Helper Methods

    private func loadSettings() async {
        await notificationService.loadSettings()
        settings = notificationService.currentSettings
    }

    private func saveSettings() async {
        await notificationService.updateSettings(settings)
    }

    private func requestPermissions() async {
        let granted = await notificationService.requestPermissions()
        authorizationStatus = notificationService.authorizationStatus

        if !granted {
            showingPermissionAlert = true
        }
    }

    private func openAppSettings() {
        guard let settingsUrl = URL(string: UIApplication.openSettingsURLString),
              UIApplication.shared.canOpenURL(settingsUrl) else { return }
        UIApplication.shared.open(settingsUrl)
    }

}

// MARK: - Supporting Views

struct NotificationToggleRow: View {
    let type: NotificationType
    let isOn: Binding<Bool>

    var body: some View {
        HStack {
            Image(systemName: type.systemImage)
                .foregroundColor(AppConstants.Colors.accent)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(type.displayName)
                    .foregroundColor(AppConstants.Colors.text)

                Text(type.description)
                    .font(.caption)
                    .foregroundColor(AppConstants.Colors.textSecondary)
            }

            Spacer()

            Toggle("", isOn: isOn)
                .tint(AppConstants.Colors.accent)
        }
    }
}

struct PrivacySettingsView: View {
    var body: some View {
        List {
            Section {
                Text("Manage your privacy and data settings")
                    .foregroundColor(AppConstants.Colors.textSecondary)
            }
            
            Section("Data Usage") {
                Text("Screen Time access required")
                Text("Usage data stays on device")
            }
        }
        .navigationTitle("Privacy")
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(.visible, for: .tabBar)
    }
}

struct DataManagementView: View {
    var body: some View {
        List {
            Section {
                Text("Manage your app data and settings")
                    .foregroundColor(AppConstants.Colors.textSecondary)
            }
            
            Section("Actions") {
                Button("Export Settings") {}
                    .foregroundColor(AppConstants.Colors.text)
                Button("Reset All Data", role: .destructive) {}
            }
        }
        .navigationTitle("Data")
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(.visible, for: .tabBar)
    }
}

struct AboutView: View {
    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Intent")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Text("Promoting mindful phone usage through intentional app access")
                        .foregroundColor(AppConstants.Colors.textSecondary)
                    
                    Text("Version 1.0")
                        .font(.caption)
                        .foregroundColor(AppConstants.Colors.disabled)
                }
                .padding(.vertical, 8)
            }
        }
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(.visible, for: .tabBar)
    }
}


// MARK: - All Apps Discovery Test View

/// Simple test view to discover all apps and capture tokens with debug output
struct AllAppsDiscoveryTestView: View {
    
    @State private var showingPicker = false
    @State private var allAppsSelection = FamilyActivitySelection(includeEntireCategory: true)
    @State private var discoveryComplete = false
    
    var body: some View {
        VStack(spacing: 20) {
            
            // Header
            Text("All Apps Discovery Test")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Text("This will discover ALL apps and categories on your device")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            Spacer()
            
            // Discovery Status
            if !discoveryComplete {
                VStack(spacing: 16) {
                    Image(systemName: "magnifyingglass.circle")
                        .font(.system(size: 60))
                        .foregroundColor(AppConstants.Colors.text)
                    
                    Text("Ready to Discover")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Text("Tap the button below and SELECT ALL apps and categories in the picker")
                        .font(.body)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    
                    Button("Start Discovery") {
                        print("🔍 DISCOVERY TEST: Opening FamilyActivityPicker")
                        print("🔍 INSTRUCTION: Please select ALL apps and ALL categories")
                        showingPicker = true
                    }
                    .buttonStyle(.bordered)
                    .foregroundColor(AppConstants.Colors.text)
                    .controlSize(.large)
                }
            } else {
                // Discovery Results
                VStack(spacing: 16) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 60))
                        .foregroundColor(AppConstants.Colors.text)
                    
                    Text("Discovery Complete!")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    discoveryResultsView
                    
                    Button("Discover Again") {
                        resetDiscovery()
                    }
                    .buttonStyle(.bordered)
                }
            }
            
            Spacer()
        }
        .padding()
        .navigationTitle("Token Discovery")
        .navigationBarTitleDisplayMode(.inline)
        .familyActivityPicker(isPresented: $showingPicker, selection: $allAppsSelection)
        .onChange(of: allAppsSelection) { oldSelection, newSelection in
            handleSelectionChange(oldSelection: oldSelection, newSelection: newSelection)
        }
    }
    
    private var discoveryResultsView: some View {
        VStack(alignment: .leading, spacing: 12) {
            
            // Apps Summary
            HStack {
                Image(systemName: "app.badge")
                    .foregroundColor(AppConstants.Colors.text)
                Text("Apps: \(allAppsSelection.applications.count)")
                    .font(.headline)
                Spacer()
            }
            
            // Categories Summary  
            HStack {
                Image(systemName: "folder.badge")
                    .foregroundColor(AppConstants.Colors.textSecondary)
                Text("Categories: \(allAppsSelection.categories.count)")
                    .font(.headline)
                Spacer()
            }
            
            // Web Domains Summary
            HStack {
                Image(systemName: "globe.badge")
                    .foregroundColor(AppConstants.Colors.text)
                Text("Web Domains: \(allAppsSelection.webDomains.count)")
                    .font(.headline)
                Spacer()
            }
            
            // Token Validity
            let validAppTokens = allAppsSelection.applications.compactMap { $0.token }.count
            let validCategoryTokens = allAppsSelection.categories.compactMap { $0.token }.count
            
            Divider()
            
            HStack {
                Image(systemName: "key.fill")
                    .foregroundColor(AppConstants.Colors.text)
                Text("Valid App Tokens: \(validAppTokens)")
                    .font(.subheadline)
                Spacer()
            }
            
            HStack {
                Image(systemName: "key.fill")
                    .foregroundColor(AppConstants.Colors.text)
                Text("Valid Category Tokens: \(validCategoryTokens)")
                    .font(.subheadline)
                Spacer()
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    private func handleSelectionChange(oldSelection: FamilyActivitySelection, newSelection: FamilyActivitySelection) {
        print("\n" + String(repeating: "=", count: 60))
        print("🔍 DISCOVERY TEST: Selection Changed")
        print(String(repeating: "=", count: 60))
        
        // Basic counts
        print("📊 BASIC COUNTS:")
        print("   Applications: \(newSelection.applications.count)")
        print("   Categories: \(newSelection.categories.count)")
        print("   Web Domains: \(newSelection.webDomains.count)")
        print("   includeEntireCategory: \(newSelection.includeEntireCategory)")
        
        // Token analysis
        let appTokens = newSelection.applications.compactMap { $0.token }
        let categoryTokens = newSelection.categories.compactMap { $0.token }
        
        print("\n🔑 TOKEN ANALYSIS:")
        print("   Valid App Tokens: \(appTokens.count)/\(newSelection.applications.count)")
        print("   Valid Category Tokens: \(categoryTokens.count)/\(newSelection.categories.count)")
        print("   🎯 With includeEntireCategory=true, selecting categories should populate individual apps too!")
        
        // Detailed app analysis
        print("\n📱 DETAILED APP ANALYSIS:")
        for (index, app) in newSelection.applications.enumerated().prefix(10) {
            let hasToken = app.token != nil
            print("   App \(index + 1): \(hasToken ? "✅ HAS TOKEN" : "❌ NO TOKEN")")
            
            print("     - App: \(app)")
            if let token = app.token {
                print("     - Token: \(token)")
            }
        }
        
        if newSelection.applications.count > 10 {
            print("   ... and \(newSelection.applications.count - 10) more apps")
        }
        
        // Detailed category analysis
        print("\n🏷️ DETAILED CATEGORY ANALYSIS:")
        for (index, category) in newSelection.categories.enumerated() {
            let hasToken = category.token != nil
            print("   Category \(index + 1): \(hasToken ? "✅ HAS TOKEN" : "❌ NO TOKEN")")
            print("     - Category: \(category)")
            if let token = category.token {
                print("     - Token: \(token)")
            }
        }
        
        // Web domains analysis
        if !newSelection.webDomains.isEmpty {
            print("\n🌐 WEB DOMAINS ANALYSIS:")
            for (index, domain) in newSelection.webDomains.enumerated().prefix(5) {
                print("   Domain \(index + 1): \(domain)")
            }
            if newSelection.webDomains.count > 5 {
                print("   ... and \(newSelection.webDomains.count - 5) more domains")
            }
        }
        
        // Summary
        print("\n📝 DISCOVERY SUMMARY:")
        if appTokens.count > 0 || categoryTokens.count > 0 {
            print("   ✅ Discovery SUCCESSFUL!")
            print("   📊 Total usable tokens: \(appTokens.count + categoryTokens.count)")
            discoveryComplete = true
        } else {
            print("   ⚠️ No valid tokens found - user may not have selected anything")
        }
        
        // Storage simulation
        print("\n💾 STORAGE SIMULATION:")
        do {
            let encoded = try JSONEncoder().encode(newSelection)
            print("   ✅ JSON encoding successful: \(encoded.count) bytes")
            
            let decoded = try JSONDecoder().decode(FamilyActivitySelection.self, from: encoded)
            let decodedAppTokens = decoded.applications.compactMap { $0.token }.count
            let decodedCategoryTokens = decoded.categories.compactMap { $0.token }.count
            
            print("   📊 After JSON round-trip:")
            print("     - App tokens: \(decodedAppTokens) (original: \(appTokens.count))")
            print("     - Category tokens: \(decodedCategoryTokens) (original: \(categoryTokens.count))")
            
            if decodedAppTokens == appTokens.count && decodedCategoryTokens == categoryTokens.count {
                print("   ✅ Token persistence looks good!")
            } else {
                print("   ⚠️ Token persistence may have issues")
            }
            
        } catch {
            print("   ❌ JSON encoding failed: \(error)")
        }
        
        print(String(repeating: "=", count: 60) + "\n")
    }
    
    private func resetDiscovery() {
        print("🔄 DISCOVERY TEST: Resetting for new discovery")
        allAppsSelection = FamilyActivitySelection(includeEntireCategory: true)
        discoveryComplete = false
    }
}

// MARK: - Include Entire Category MVP Test

/// Minimal test to verify includeEntireCategory: true behavior
struct IncludeEntireCategoryTestView: View {
    
    @State private var showingPicker = false
    
    // Test with includeEntireCategory: true
    @State private var selectionWithCategories = FamilyActivitySelection(includeEntireCategory: true)
    
    // Test with includeEntireCategory: false (default)
    @State private var selectionWithoutCategories = FamilyActivitySelection(includeEntireCategory: false)
    
    @State private var testMode: TestMode = .withCategories
    
    enum TestMode: String, CaseIterable {
        case withCategories = "includeEntireCategory: true"
        case withoutCategories = "includeEntireCategory: false"
    }
    
    var currentSelection: FamilyActivitySelection {
        switch testMode {
        case .withCategories:
            return selectionWithCategories
        case .withoutCategories:
            return selectionWithoutCategories
        }
    }
    
    var body: some View {
        VStack(spacing: 20) {
            
            // Header
            Text("includeEntireCategory Test")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            // Test Mode Selector
            Picker("Test Mode", selection: $testMode) {
                ForEach(TestMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .padding()
            
            // Instructions
            VStack(spacing: 8) {
                Text("Select a CATEGORY (not individual apps)")
                    .font(.headline)
                    .foregroundColor(AppConstants.Colors.textSecondary)
                
                Text("We want to see if selecting a category populates individual apps when includeEntireCategory: true")
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(AppConstants.Colors.surface)
            .cornerRadius(8)
            
            // Open Picker Button
            Button("Open Family Activity Picker") {
                print("\n🧪 TESTING: \(testMode.rawValue)")
                showingPicker = true
            }
            .buttonStyle(.bordered)
            .foregroundColor(AppConstants.Colors.text)
            .controlSize(.large)
            
            // Results
            if currentSelection.applications.count > 0 || currentSelection.categories.count > 0 {
                resultsView
            }
            
            Spacer()
        }
        .padding()
        .navigationTitle("MVP Test")
        .navigationBarTitleDisplayMode(.inline)
        .familyActivityPicker(
            isPresented: $showingPicker, 
            selection: testMode == .withCategories ? $selectionWithCategories : $selectionWithoutCategories
        )
        .onChange(of: selectionWithCategories) { _, newSelection in
            if testMode == .withCategories {
                handleSelectionChange(newSelection, mode: .withCategories)
            }
        }
        .onChange(of: selectionWithoutCategories) { _, newSelection in
            if testMode == .withoutCategories {
                handleSelectionChange(newSelection, mode: .withoutCategories)
            }
        }
    }
    
    private var resultsView: some View {
        VStack(alignment: .leading, spacing: 12) {
            
            Text("Results for: \(testMode.rawValue)")
                .font(.headline)
                .foregroundColor(.primary)
            
            Divider()
            
            // Basic counts
            HStack {
                Image(systemName: "app.badge")
                    .foregroundColor(AppConstants.Colors.text)
                Text("Individual Apps: \(currentSelection.applications.count)")
                Spacer()
            }
            
            HStack {
                Image(systemName: "folder.badge")
                    .foregroundColor(AppConstants.Colors.textSecondary)
                Text("Categories: \(currentSelection.categories.count)")
                Spacer()
            }
            
            // Token validity
            let validAppTokens = currentSelection.applications.compactMap { $0.token }.count
            let validCategoryTokens = currentSelection.categories.compactMap { $0.token }.count
            
            Divider()
            
            HStack {
                Image(systemName: "key.fill")
                    .foregroundColor(AppConstants.Colors.text)
                Text("Valid App Tokens: \(validAppTokens)")
                Spacer()
            }
            
            HStack {
                Image(systemName: "key.fill")
                    .foregroundColor(AppConstants.Colors.text)
                Text("Valid Category Tokens: \(validCategoryTokens)")
                Spacer()
            }
            
            // Expected behavior explanation
            Divider()
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Expected Behavior:")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                
                if testMode == .withCategories {
                    Text("✅ Selecting 1 category should give you BOTH:")
                        .font(.caption)
                        .foregroundColor(AppConstants.Colors.text)
                    Text("  • 1 category token")
                        .font(.caption)
                        .foregroundColor(AppConstants.Colors.text)
                    Text("  • Multiple individual app tokens from that category")
                        .font(.caption)
                        .foregroundColor(AppConstants.Colors.text)
                } else {
                    Text("⚠️ Selecting 1 category should give you ONLY:")
                        .font(.caption)
                        .foregroundColor(AppConstants.Colors.textSecondary)
                    Text("  • 1 category token")
                        .font(.caption)
                        .foregroundColor(AppConstants.Colors.textSecondary)
                    Text("  • No individual app tokens")
                        .font(.caption)
                        .foregroundColor(AppConstants.Colors.textSecondary)
                }
            }
            
            // Clear button
            Button("Clear Selection") {
                switch testMode {
                case .withCategories:
                    selectionWithCategories = FamilyActivitySelection(includeEntireCategory: true)
                case .withoutCategories:
                    selectionWithoutCategories = FamilyActivitySelection(includeEntireCategory: false)
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    private func handleSelectionChange(_ selection: FamilyActivitySelection, mode: TestMode) {
        print("\n" + String(repeating: "=", count: 50))
        print("🧪 MVP TEST RESULTS: \(mode.rawValue)")
        print(String(repeating: "=", count: 50))
        
        print("📊 BASIC COUNTS:")
        print("   Applications: \(selection.applications.count)")
        print("   Categories: \(selection.categories.count)")
        print("   Web Domains: \(selection.webDomains.count)")
        print("   includeEntireCategory: \(selection.includeEntireCategory)")
        
        let appTokens = selection.applications.compactMap { $0.token }
        let categoryTokens = selection.categories.compactMap { $0.token }
        
        print("\n🔑 TOKEN VALIDATION:")
        print("   Valid App Tokens: \(appTokens.count)/\(selection.applications.count)")
        print("   Valid Category Tokens: \(categoryTokens.count)/\(selection.categories.count)")
        
        print("\n🎯 TEST ANALYSIS:")
        if mode == .withCategories {
            if selection.categories.count > 0 && selection.applications.count > 0 {
                print("   ✅ SUCCESS: includeEntireCategory=true gave us BOTH categories AND individual apps!")
                print("   📱 This means selecting categories populated individual app tokens")
            } else if selection.categories.count > 0 && selection.applications.count == 0 {
                print("   ❌ UNEXPECTED: includeEntireCategory=true gave us categories but NO individual apps")
                print("   🤔 This suggests the feature might not work as expected")
            } else if selection.applications.count > 0 && selection.categories.count == 0 {
                print("   ✅ User selected individual apps (not categories) - this is fine")
            } else {
                print("   ⚠️ No selection made yet")
            }
        } else {
            if selection.categories.count > 0 && selection.applications.count == 0 {
                print("   ✅ EXPECTED: includeEntireCategory=false gave us only categories")
            } else if selection.categories.count > 0 && selection.applications.count > 0 {
                print("   🤔 UNEXPECTED: includeEntireCategory=false gave us categories AND individual apps")
            } else if selection.applications.count > 0 {
                print("   ✅ User selected individual apps - this is normal")
            }
        }
        
        print(String(repeating: "=", count: 50) + "\n")
    }
}

//#Preview {
//    SettingsView()
//        .environmentObject(NavigationStateManager())
//}


