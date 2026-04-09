//
//  SettingsView.swift
//  Intentions
//

import SwiftUI
@preconcurrency import FamilyControls

// MARK: - Settings Navigation

enum SettingsDestination: Hashable {
    case notifications
    case setupFlow

    var title: String {
        switch self {
        case .notifications: return "Notifications"
        case .setupFlow: return "App Setup"
        }
    }

    var systemImage: String {
        switch self {
        case .notifications: return "bell.fill"
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

struct SettingsView: View {
    @State private var viewModel: SettingsViewModel
    @State private var showingDisableConfirmation = false
    private let onScheduleSettingsChanged: ((ScheduleSettings) async -> Void)?
    private let onViewModelReady: ((SettingsViewModel) -> Void)?
    private let setupCoordinator: SetupCoordinator?
    private let hasActiveSession: Bool
    @EnvironmentObject private var navigationManager: NavigationStateManager

    private var isScheduleEditingDisabled: Bool {
        hasActiveSession || viewModel.scheduleSettings.isCurrentlyActive
    }

    private var scheduleEditingDisabledReason: String {
        if hasActiveSession {
            return "Cannot modify schedule while session is active"
        } else if viewModel.scheduleSettings.isCurrentlyActive {
            return "Cannot modify schedule during active protected hours"
        }
        return ""
    }

    init(
        dataService: DataPersisting? = nil,
        setupCoordinator: SetupCoordinator? = nil,
        hasActiveSession: Bool = false,
        onScheduleSettingsChanged: ((ScheduleSettings) async -> Void)? = nil,
        onViewModelReady: ((SettingsViewModel) -> Void)? = nil
    ) {
        let service = dataService ?? MockDataPersistenceService()
        self._viewModel = State(wrappedValue: SettingsViewModel(dataService: service))
        self.setupCoordinator = setupCoordinator
        self.hasActiveSession = hasActiveSession
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
                    scheduleSection
                    setupSection
                    statisticsSection
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
                                navigationManager.resetSettingsNavigation()
                            }
                        } else {
                            Text("Setup not available")
                                .foregroundColor(AppConstants.Colors.textSecondary)
                        }
                    }
                }
            }
        }
        .background(AppConstants.Colors.background)
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(.visible, for: .tabBar)
        .sheet(isPresented: $viewModel.showingScheduleEditor) {
            ScheduleSettingsView(
                settings: viewModel.scheduleSettings,
                onSave: { settings in
                    Task {
                        await viewModel.updateScheduleSettings(settings)
                        await onScheduleSettingsChanged?(settings)
                    }
                    viewModel.hideScheduleEditor()
                },
                onCancel: { viewModel.hideScheduleEditor() }
            )
        }
        .sheet(isPresented: $showingDisableConfirmation) {
            DisableBlockingConfirmationView(
                onConfirm: {
                    showingDisableConfirmation = false
                    Task {
                        await viewModel.toggleScheduleEnabled()
                        await onScheduleSettingsChanged?(viewModel.scheduleSettings)
                    }
                },
                onCancel: { showingDisableConfirmation = false }
            )
        }
        .task { await viewModel.loadData() }
        .onAppear { onViewModelReady?(viewModel) }
    }

    // MARK: - Sections

    private var scheduleSection: some View {
        Section {
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

                    Text(viewModel.intentionsStateText)
                        .font(.caption)
                        .foregroundColor(AppConstants.Colors.textSecondary)
                }
            }

            ScheduleDetailsRow(
                title: "Blocking Hours",
                value: viewModel.formattedActiveHours,
                action: { viewModel.showScheduleEditor() },
                isDisabled: isScheduleEditingDisabled
            )

            ScheduleDetailsRow(
                title: "Blocking Days",
                value: viewModel.activeDaysText,
                action: { viewModel.showScheduleEditor() },
                isDisabled: isScheduleEditingDisabled
            )

            if isScheduleEditingDisabled {
                HStack {
                    Image(systemName: "info.circle")
                        .foregroundColor(AppConstants.Colors.textSecondary)
                    Text(scheduleEditingDisabledReason)
                        .font(.caption)
                        .foregroundColor(AppConstants.Colors.textSecondary)
                }
                .padding(.top, 4)
            }
        } header: {
            Text("Protected Hours")
        }
    }

    private var setupSection: some View {
        Section {
            NavigationLink(value: SettingsDestination.setupFlow) {
                SettingsRow(
                    title: SettingsDestination.setupFlow.title,
                    subtitle: "Configure app permissions",
                    icon: SettingsDestination.setupFlow.systemImage
                )
            }

            Button(action: { openAccessibilitySettings() }) {
                SettingsRow(
                    title: "Enable Greyscale",
                    subtitle: "Opens Settings app. Navigate to: Accessibility > Display & Text Size > Color Filters > Grayscale",
                    icon: "eye.slash"
                )
            }
        } header: {
            Text("Setup")
        }
    }

    private var statisticsSection: some View {
        Section("Usage Statistics") {
            StatisticRow(title: "Today's Sessions", value: "\(viewModel.todaySessionCount)", icon: "calendar")
            StatisticRow(title: "This Week", value: "\(viewModel.weeklySessionCount)", icon: "chart.line.uptrend.xyaxis")
        }
    }

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

    // MARK: - Helpers

    private func openAccessibilitySettings() {
        if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(settingsURL)
        }
    }
}
