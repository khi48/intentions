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

    init() {
        do {
            let vm = try ContentViewModel()
            self._viewModel = State(wrappedValue: vm)
        } catch {
            // If ContentViewModel initialization fails, we have a critical app failure
            fatalError("Failed to initialize ContentViewModel: \(error)")
        }
    }
    private let managedSettingsStore = ManagedSettingsStore()
    
    var body: some View {
        Group {
            if viewModel.showingSetupFlow {
                SetupFlowView(
                    setupCoordinator: viewModel.setupCoordinator
                ) {
                    viewModel.completeSetupFlow()
                }
            } else {
                MainTabView(viewModel: viewModel)
            }
        }
        .task {
            await viewModel.initializeApp()
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
    }
}

/// Main tab-based navigation when app is authorized
private struct MainTabView: View {
    let viewModel: ContentViewModel
    @StateObject private var navigationManager = NavigationStateManager()
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
                } else {
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
                authorizationStatus: viewModel.authorizationStatus,
                onScheduleSettingsChanged: { settings in
                    await viewModel.updateScheduleSettings(settings)
                },
                onViewModelReady: { vm in
                    settingsViewModel = vm
                }
            )
            .environmentObject(navigationManager)
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
