//
//  ContentView.swift
//  Intentions
//
//  Created by Kieran Hitchcock on 26/05/25.
//

import SwiftUI
@preconcurrency import FamilyControls
@preconcurrency import ManagedSettings


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
    private let managedSettingsStore = ManagedSettingsStore()
    
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
                
                let oldTab = viewModel.selectedTab
                
                // First, perform the smooth tab switch immediately
                viewModel.navigateToTab(newTab)
                
                // Then reset Settings navigation in the background after a brief delay
                if oldTab == .settings && newTab != .settings {
                    // Use a small delay to let the tab transition complete smoothly
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        navigationManager.resetSettingsNavigationWithoutAnimation()
                        settingsViewModel?.resetSheetState()
                    }
                }
                // Also reset when navigating TO Settings tab (ensures clean state) 
                else if oldTab != .settings && newTab == .settings {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        navigationManager.resetSettingsNavigationWithoutAnimation()
                        settingsViewModel?.resetSheetState()
                    }
                }
            }
        )) {
            // Home Tab - Main intention interface with Quick Actions
            HomeView(viewModel: viewModel)
                .tabItem {
                    Label(AppTab.home.rawValue, systemImage: AppTab.home.systemImage)
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
                    Label(AppTab.settings.rawValue, systemImage: AppTab.settings.systemImage)
                }
                .tag(AppTab.settings)
            
        }
        .tint(AppConstants.Colors.tabBarIcon)
        // REMOVED: IntentionPromptView was legacy - intention functionality now via Quick Actions
    }
}


#Preview {
    ContentView()
}
