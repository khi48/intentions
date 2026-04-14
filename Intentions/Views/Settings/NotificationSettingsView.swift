//
//  NotificationSettingsView.swift
//  Intentions
//

import SwiftUI
@preconcurrency import UserNotifications

/// Settings page for notification preferences. Uses the shared Settings dark
/// background, custom rows, and primary button so it matches every other
/// settings sub-page.
struct NotificationSettingsView: View {
    @State private var notificationService = NotificationService.shared
    @State private var settings: NotificationSettings
    @State private var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @State private var showingPermissionAlert = false

    init() {
        self._settings = State(initialValue: NotificationService.shared.currentSettings)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Permission section
                SettingsSectionHeader(title: "Permission")
                permissionRow

                if authorizationStatus == .notDetermined {
                    SettingsHelperText("Allow notifications to receive session reminders.")
                    SettingsPrimaryButton("Enable Notifications", systemImage: "bell.fill") {
                        Task { await requestPermissions() }
                    }
                    .padding(.top, 8)
                } else if authorizationStatus == .denied {
                    SettingsHelperText("To enable notifications, open iOS Settings → Notifications → Intent.")
                    SettingsPrimaryButton("Open iOS Settings", systemImage: "gear") {
                        openAppSettings()
                    }
                    .padding(.top, 8)
                } else {
                    SettingsHelperText("Intent can send you session reminders and completion notifications.")
                }

                if isAuthorized {
                    // Master toggle
                    SettingsSectionHeader(title: "Notifications")
                    SettingsToggleRow(
                        "Enable Notifications",
                        subtitle: "Turn off to silence all session-related notifications",
                        isOn: Binding(
                            get: { settings.isEnabled },
                            set: { newValue in
                                settings.isEnabled = newValue
                                Task { await saveSettings() }
                            }
                        )
                    )

                    if settings.isEnabled {
                        SettingsSectionHeader(title: "Session Reminders")
                        SettingsToggleRow(
                            NotificationType.sessionWarning.displayName,
                            subtitle: NotificationType.sessionWarning.description,
                            isOn: Binding(
                                get: { settings.sessionWarningsEnabled },
                                set: { newValue in
                                    settings.sessionWarningsEnabled = newValue
                                    Task { await saveSettings() }
                                }
                            )
                        )
                        SettingsToggleRow(
                            NotificationType.sessionCompletion.displayName,
                            subtitle: NotificationType.sessionCompletion.description,
                            isOn: Binding(
                                get: { settings.sessionCompletionEnabled },
                                set: { newValue in
                                    settings.sessionCompletionEnabled = newValue
                                    Task { await saveSettings() }
                                }
                            )
                        )

                        SettingsPrimaryButton("Reset to Defaults", systemImage: "arrow.counterclockwise") {
                            settings.resetToDefaults()
                            Task { await saveSettings() }
                        }
                        .padding(.top, 24)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 40)
        }
        .settingsPageBackground()
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

    // MARK: - Custom rows

    private var permissionRow: some View {
        HStack(spacing: 12) {
            Image(systemName: permissionStatusIcon)
                .font(.body)
                .foregroundColor(permissionStatusColor)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                Text("Notification Permission")
                    .font(.body)
                    .foregroundColor(AppConstants.Colors.text)
                Text(permissionStatusText)
                    .font(.caption)
                    .foregroundColor(AppConstants.Colors.textSecondary)
            }
            Spacer()
        }
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) { SettingsRowDivider() }
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
        case .authorized, .provisional, .ephemeral: return AppConstants.Colors.text
        case .denied: return AppConstants.Colors.disabled
        case .notDetermined: return AppConstants.Colors.textSecondary
        @unknown default: return AppConstants.Colors.disabled
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
