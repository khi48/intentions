//
//  NotificationSettingsView.swift
//  Intentions
//

import SwiftUI
@preconcurrency import UserNotifications

/// Settings view for notification preferences
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
            permissionSection

            if authorizationStatus == .authorized || authorizationStatus == .provisional {
                masterToggleSection
            }

            if settings.isEnabled && isAuthorized {
                sessionNotificationsSection

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
            Button("Settings") { openAppSettings() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("To receive session reminders, please enable notifications in Settings.")
        }
    }

    // MARK: - Sections

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
                    Button("Settings") { openAppSettings() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                } else if authorizationStatus == .notDetermined {
                    Button("Enable") {
                        Task { await requestPermissions() }
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

    private var masterToggleSection: some View {
        Section {
            Toggle("Enable Notifications", isOn: Binding(
                get: { settings.isEnabled },
                set: { newValue in
                    settings.isEnabled = newValue
                    Task { await saveSettings() }
                }
            ))
            .tint(AppConstants.Colors.accent)
        } footer: {
            Text("Turn off to disable all session-related notifications.")
                .foregroundColor(AppConstants.Colors.textSecondary)
        }
    }

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

    // MARK: - Helpers

    private var isAuthorized: Bool {
        authorizationStatus == .authorized || authorizationStatus == .provisional
    }

    private var permissionStatusIcon: String {
        switch authorizationStatus {
        case .authorized, .provisional, .ephemeral: return "checkmark.circle.fill"
        case .denied: return "xmark.circle.fill"
        case .notDetermined: return "questionmark.circle.fill"
        @unknown default: return "questionmark.circle.fill"
        }
    }

    private var permissionStatusColor: Color {
        switch authorizationStatus {
        case .authorized, .provisional, .ephemeral: return AppConstants.Colors.textSecondary
        case .denied: return .red
        case .notDetermined: return .orange
        @unknown default: return .gray
        }
    }

    private var permissionStatusText: String {
        switch authorizationStatus {
        case .authorized: return "Notifications are enabled"
        case .provisional: return "Quiet notifications enabled"
        case .ephemeral: return "Temporary notifications enabled"
        case .denied: return "Notifications are disabled"
        case .notDetermined: return "Permission not requested"
        @unknown default: return "Unknown status"
        }
    }

    private var permissionFooterText: String {
        switch authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return "Intent can send you session reminders and completion notifications."
        case .denied:
            return "To enable notifications, go to Settings > Notifications > Intent."
        case .notDetermined:
            return "Allow notifications to receive session reminders."
        @unknown default:
            return ""
        }
    }

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
        if !granted { showingPermissionAlert = true }
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
