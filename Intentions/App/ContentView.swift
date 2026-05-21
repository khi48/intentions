//
//  ContentView.swift
//  Intentions
//
//  Created by Kieran Hitchcock on 26/05/25.
//

import SwiftUI
@preconcurrency import FamilyControls


/// Main app content view with navigation and authorization handling
struct ContentView: View {
    @State private var viewModel: ContentViewModel
    @Environment(\.scenePhase) private var scenePhase

    @State private var initError: String?

    init() {
        do {
            let vm = try ContentViewModel()
            self._viewModel = State(wrappedValue: vm)
            self._initError = State(wrappedValue: nil)
        } catch {
            // Create a fallback view model with mock services so the app can show an error
            let fallbackVM = try! ContentViewModel(
                screenTimeService: MockScreenTimeService(),
                dataService: MockDataPersistenceService()
            )
            self._viewModel = State(wrappedValue: fallbackVM)
            self._initError = State(wrappedValue: "Failed to initialize app: \(error.localizedDescription)")
        }
    }

    var body: some View {
        Group {
            if !viewModel.hasInitialized {
                Color(AppConstants.Colors.background)
                    .ignoresSafeArea()
            } else if viewModel.showingSetupFlow {
                SetupFlowView(
                    setupCoordinator: viewModel.setupCoordinator,
                    onIntentionQuoteSet: { quote in
                        viewModel.setIntentionQuote(quote)
                    }
                ) {
                    Task {
                        await viewModel.completeSetupFlow()
                    }
                }
            } else {
                MainTabView(viewModel: viewModel)
            }
        }
        .task {
            await viewModel.initializeApp()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                Task { await viewModel.reconcileBlockingOnForeground() }
            }
        }
        .onOpenURL { url in
            guard url.scheme == "intentions", url.host == "home" else { return }
            viewModel.navigateToTab(.home)
        }
        .alert("Error", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { _ in viewModel.clearError() }
        )) {
            Button("OK") {
                viewModel.clearError()
            }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .alert("Initialization Error", isPresented: Binding(
            get: { initError != nil },
            set: { _ in initError = nil }
        )) {
            Button("OK") { initError = nil }
        } message: {
            Text(initError ?? "")
        }
    }
}

/// Main tab-based navigation when app is authorized
private struct MainTabView: View {
    let viewModel: ContentViewModel
    @State private var navigationManager = NavigationStateManager()
    @State private var settingsViewModel: SettingsViewModel?
    
    var body: some View {
        TabView(selection: Binding(
            get: { viewModel.selectedTab },
            set: { newTab in
                // Smooth tab switch only — nav reset is driven by Settings
                // lifecycle hooks (onAppear / onDisappear) below so it fires
                // deterministically with TabView's own animation rather than
                // a timer-based asyncAfter (see #48).
                viewModel.navigateToTab(newTab)
            }
        )) {
            // Home Tab - Main intention interface with Quick Actions
            HomeView(viewModel: viewModel)
                .tabItem {
                    Label(AppTab.home.title, systemImage: AppTab.home.systemImage)
                }
                .tag(AppTab.home)

            // Settings Tab
            SettingsView(
                dataService: viewModel.dataServiceProvider,
                setupCoordinator: viewModel.setupCoordinator,
                hasActiveSession: viewModel.activeSession != nil,
                onScheduleSettingsChanged: { schedule in
                    await viewModel.updateWeeklySchedule(schedule)
                },
                onViewModelReady: { vm in
                    settingsViewModel = vm
                }
            )
            .environment(navigationManager)
                .tabItem {
                    Label(AppTab.settings.title, systemImage: AppTab.settings.systemImage)
                }
                .tag(AppTab.settings)
                // Reset Settings nav state at lifecycle boundaries so the pop
                // is invisible: onDisappear fires after the tab swap (user
                // can't see the reset), onAppear primes a clean root state
                // before the tab becomes visible. Replaces a 100ms
                // asyncAfter race (#48).
                .onAppear {
                    navigationManager.resetSettingsNavigationWithoutAnimation()
                    settingsViewModel?.resetSheetState()
                }
                .onDisappear {
                    navigationManager.resetSettingsNavigationWithoutAnimation()
                    settingsViewModel?.resetSheetState()
                }

        }
        .tint(AppConstants.Colors.tabBarIcon)
        // REMOVED: IntentionPromptView was legacy - intention functionality now via Quick Actions
    }
}


#Preview {
    ContentView()
}
