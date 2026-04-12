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
    case greyscale

    var title: String {
        switch self {
        case .notifications: return "Notifications"
        case .setupFlow: return "App Setup"
        case .greyscale: return "Enable Greyscale"
        }
    }

    var systemImage: String {
        switch self {
        case .notifications: return "bell.fill"
        case .setupFlow: return "gear.badge.checkmark"
        case .greyscale: return "circle.lefthalf.filled"
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
    @State private var showingIntentionQuoteEditor = false
    private let onScheduleSettingsChanged: ((ScheduleSettings) async -> Void)?
    private let onViewModelReady: ((SettingsViewModel) -> Void)?
    private let setupCoordinator: SetupCoordinator?
    private let hasActiveSession: Bool
    @Environment(NavigationStateManager.self) private var navigationManager

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
        @Bindable var navigationManager = navigationManager
        NavigationStack(path: $navigationManager.settingsPath) {
            if !viewModel.hasLoadedOnce {
                ProgressView("Loading Settings...")
                    .foregroundColor(AppConstants.Colors.text)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(AppConstants.Colors.background)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        // Stats banner
                        statsBanner

                        // Blocking
                        sectionLabel("Blocking")
                        blockingToggleRow
                        settingsRow("Free Hours", value: viewModel.formattedActiveHours, disabled: isScheduleEditingDisabled) {
                            viewModel.showScheduleEditor()
                        }
                        settingsRow("Free Days", value: viewModel.activeDaysText, disabled: isScheduleEditingDisabled) {
                            viewModel.showScheduleEditor()
                        }

                        if isScheduleEditingDisabled {
                            HStack(spacing: 6) {
                                Image(systemName: "info.circle")
                                    .font(.caption2)
                                Text(scheduleEditingDisabledReason)
                                    .font(.caption)
                            }
                            .foregroundColor(AppConstants.Colors.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 8)
                        }

                        // General
                        sectionLabel("General")
                        Button(action: { showingIntentionQuoteEditor = true }) {
                            HStack {
                                Text("Your Intention")
                                    .font(.body)
                                    .foregroundColor(AppConstants.Colors.text)
                                Spacer()
                                Text(viewModel.scheduleSettings.intentionQuote ?? "Not set")
                                    .font(.subheadline)
                                    .foregroundColor(AppConstants.Colors.textSecondary)
                                    .lineLimit(1)
                                Image(systemName: "chevron.right")
                                    .font(.caption2)
                                    .foregroundColor(AppConstants.Colors.textSecondary)
                            }
                            .padding(.vertical, 14)
                            .overlay(alignment: .bottom) { rowDivider }
                        }
                        .buttonStyle(.plain)
                        NavigationLink(value: SettingsDestination.notifications) {
                            settingsRowContent("Notifications")
                        }
                        .overlay(alignment: .bottom) { rowDivider }
                        NavigationLink(value: SettingsDestination.setupFlow) {
                            settingsRowContent("App Setup")
                        }
                        .overlay(alignment: .bottom) { rowDivider }
                        NavigationLink(value: SettingsDestination.greyscale) {
                            settingsRowContent("Enable Greyscale")
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 40)
                }
                .background(AppConstants.Colors.background)
                .navigationTitle("Settings")
                .navigationBarTitleDisplayMode(.large)
                .navigationDestination(for: SettingsDestination.self) { destination in
                    switch destination {
                    case .notifications:
                        NotificationSettingsView()
                    case .setupFlow:
                        if let coordinator = setupCoordinator {
                            SetupFlowView(
                                setupCoordinator: coordinator,
                                embedInNavigationView: false,
                                forceSetup: true,
                                onIntentionQuoteSet: { quote in
                                    viewModel.scheduleSettings.intentionQuote = quote
                                    Task {
                                        await viewModel.updateScheduleSettings(viewModel.scheduleSettings)
                                        await onScheduleSettingsChanged?(viewModel.scheduleSettings)
                                    }
                                }
                            ) {
                                navigationManager.resetSettingsNavigation()
                            }
                        } else {
                            Text("Setup not available")
                                .foregroundColor(AppConstants.Colors.textSecondary)
                        }
                    case .greyscale:
                        GreyscaleGuideView()
                    }
                }
            }
        }
        .background(AppConstants.Colors.background)
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
                streakDays: viewModel.streakDays,
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
        .sheet(isPresented: $showingIntentionQuoteEditor) {
            IntentionQuoteEditorView(
                quote: viewModel.scheduleSettings.intentionQuote ?? "",
                onSave: { newQuote in
                    viewModel.scheduleSettings.intentionQuote = newQuote.isEmpty ? nil : newQuote
                    Task {
                        await viewModel.updateScheduleSettings(viewModel.scheduleSettings)
                        await onScheduleSettingsChanged?(viewModel.scheduleSettings)
                    }
                    showingIntentionQuoteEditor = false
                },
                onCancel: { showingIntentionQuoteEditor = false }
            )
        }
        .task { await viewModel.loadData() }
        .onAppear { onViewModelReady?(viewModel) }
    }

    // MARK: - Stats Banner

    private var statsBanner: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text("\(viewModel.todaySessionCount)")
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundColor(AppConstants.Colors.text)
                Text("SESSIONS TODAY")
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundColor(AppConstants.Colors.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(AppConstants.Colors.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(AppConstants.Colors.textSecondary.opacity(0.15), lineWidth: 1)
            )

            VStack(alignment: .leading, spacing: 3) {
                Text("\(viewModel.weeklySessionCount)")
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundColor(AppConstants.Colors.text)
                Text("THIS WEEK")
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundColor(AppConstants.Colors.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(AppConstants.Colors.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(AppConstants.Colors.textSecondary.opacity(0.15), lineWidth: 1)
            )
        }
        .padding(.vertical, 4)
    }

    // MARK: - Sections

    private func sectionLabel(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.caption)
            .fontWeight(.medium)
            .foregroundColor(AppConstants.Colors.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 20)
            .padding(.bottom, 4)
    }

    private var blockingToggleRow: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Enabled")
                    .font(.body)
                    .foregroundColor(AppConstants.Colors.text)
                Text(blockingToggleSubtitle)
                    .font(.caption)
                    .foregroundColor(AppConstants.Colors.textSecondary)
            }
            Spacer()
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
        }
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) { rowDivider }
    }

    private var blockingToggleSubtitle: String {
        if viewModel.scheduleSettings.isEnabled {
            return "Blocks apps 24/7 outside free time"
        } else {
            return "Blocking is off — no apps are blocked"
        }
    }

    private func settingsRow(_ title: String, value: String, disabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: disabled ? {} : action) {
            HStack {
                Text(title)
                    .font(.body)
                    .foregroundColor(disabled ? AppConstants.Colors.disabled : AppConstants.Colors.text)
                Spacer()
                Text(value)
                    .font(.subheadline)
                    .foregroundColor(disabled ? AppConstants.Colors.disabled : AppConstants.Colors.textSecondary)
                if !disabled {
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundColor(AppConstants.Colors.textSecondary)
                }
            }
            .padding(.vertical, 14)
            .overlay(alignment: .bottom) { rowDivider }
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }

    private func settingsRowContent(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(.body)
                .foregroundColor(AppConstants.Colors.text)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundColor(AppConstants.Colors.textSecondary)
        }
        .padding(.vertical, 14)
    }

    private var rowDivider: some View {
        Rectangle()
            .fill(AppConstants.Colors.textSecondary.opacity(0.15))
            .frame(height: 0.5)
    }

}
