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
    case scheduleEditor
    case intentionQuote

    var title: String {
        switch self {
        case .notifications: return "Notifications"
        case .setupFlow: return "App Setup"
        case .greyscale: return "Enable Greyscale"
        case .scheduleEditor: return "Free Time Settings"
        case .intentionQuote: return "Your Intention"
        }
    }

    var systemImage: String {
        switch self {
        case .notifications: return "bell.fill"
        case .setupFlow: return "gear.badge.checkmark"
        case .greyscale: return "circle.lefthalf.filled"
        case .scheduleEditor: return "calendar"
        case .intentionQuote: return "quote.opening"
        }
    }
}

// MARK: - Main Settings View

struct SettingsView: View {
    @State private var viewModel: SettingsViewModel
    @State private var showingDisableConfirmation = false
    private let onScheduleSettingsChanged: ((WeeklySchedule) async -> Void)?
    private let onViewModelReady: ((SettingsViewModel) -> Void)?
    private let setupCoordinator: SetupCoordinator?
    private let hasActiveSession: Bool
    @Environment(NavigationStateManager.self) private var navigationManager

    private var isScheduleEditingDisabled: Bool {
        hasActiveSession || viewModel.weeklySchedule.isBlocking(at: Date())
    }

    private var scheduleEditingDisabledReason: String {
        if hasActiveSession {
            return "Cannot modify schedule while session is active"
        } else if viewModel.weeklySchedule.isBlocking(at: Date()) {
            return "Cannot modify schedule during active protected hours"
        }
        return ""
    }

    init(
        dataService: DataPersisting? = nil,
        setupCoordinator: SetupCoordinator? = nil,
        hasActiveSession: Bool = false,
        onScheduleSettingsChanged: ((WeeklySchedule) async -> Void)? = nil,
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
                        freeTimeRow

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
                        SettingsNavigationRow(
                            "Your Intention",
                            value: SettingsDestination.intentionQuote,
                            trailingText: viewModel.weeklySchedule.intentionQuote ?? "Not set"
                        )
                        SettingsNavigationRow(
                            "Notifications",
                            value: SettingsDestination.notifications
                        )
                        SettingsNavigationRow(
                            "Enable Greyscale",
                            value: SettingsDestination.greyscale
                        )
                        SettingsNavigationRow(
                            "App Setup",
                            value: SettingsDestination.setupFlow
                        )
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
                                    viewModel.weeklySchedule.intentionQuote = quote
                                    Task {
                                        await viewModel.updateSchedule(viewModel.weeklySchedule)
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
                    case .scheduleEditor:
                        WeekScheduleEditorView(
                            schedule: viewModel.weeklySchedule,
                            onSave: { updated in
                                Task {
                                    await viewModel.updateSchedule(updated)
                                    await onScheduleSettingsChanged?(updated)
                                }
                                navigationManager.resetSettingsNavigation()
                            }
                        )
                    case .intentionQuote:
                        IntentionQuoteEditorView(
                            quote: viewModel.weeklySchedule.intentionQuote ?? ""
                        ) { newQuote in
                            viewModel.weeklySchedule.intentionQuote = newQuote.isEmpty ? nil : newQuote
                            Task {
                                await viewModel.updateSchedule(viewModel.weeklySchedule)
                            }
                        }
                    }
                }
            }
        }
        .background(AppConstants.Colors.background)
        .toolbarBackground(.visible, for: .tabBar)
        .sheet(isPresented: $showingDisableConfirmation) {
            DisableBlockingConfirmationView(
                streakDays: viewModel.streakDays,
                timeUntilFreeTimeText: viewModel.timeUntilFreeTimeText,
                intentionQuote: viewModel.weeklySchedule.intentionQuote,
                onConfirm: {
                    showingDisableConfirmation = false
                    Task {
                        await viewModel.recordDisableAndToggle()
                    }
                },
                onCancel: { showingDisableConfirmation = false }
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
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.title3)
                .fontWeight(.bold)
                .foregroundColor(AppConstants.Colors.text)
            Rectangle()
                .fill(AppConstants.Colors.textSecondary.opacity(0.25))
                .frame(height: 1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 28)
        .padding(.bottom, 8)
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
                get: { viewModel.weeklySchedule.isEnabled },
                set: { newValue in
                    if newValue {
                        Task {
                            await viewModel.toggleScheduleEnabled()
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
        if viewModel.weeklySchedule.isEnabled {
            return "Blocks apps 24/7 outside free time"
        } else {
            return "Blocking is off — no apps are blocked"
        }
    }

    private var freeTimeRow: some View {
        SettingsNavigationRow(
            "Free Time Settings",
            value: SettingsDestination.scheduleEditor,
            isDisabled: isScheduleEditingDisabled
        )
    }

    private var rowDivider: some View {
        SettingsRowDivider()
    }

}
