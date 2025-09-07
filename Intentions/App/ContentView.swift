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
            self._viewModel = State(wrappedValue: try ContentViewModel())
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
            } else if viewModel.showingCategoryMappingSetup {
                CategoryMappingSetupView { mappingService in
                    viewModel.completeCategoryMappingSetup(mappingService)
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
                print("🔄 TAB CHANGE: \(viewModel.selectedTab.rawValue) → \(newTab.rawValue)")
                
                let oldTab = viewModel.selectedTab
                
                // First, perform the smooth tab switch immediately
                viewModel.navigateToTab(newTab)
                
                // Then reset Settings navigation in the background after a brief delay
                if oldTab == .settings && newTab != .settings {
                    print("🏠 SETTINGS RESET: Will reset Settings navigation in background")
                    // Use a small delay to let the tab transition complete smoothly
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        navigationManager.resetSettingsNavigationWithoutAnimation()
                        settingsViewModel?.resetSheetState()
                        print("   ✅ Background reset completed")
                    }
                }
                // Also reset when navigating TO Settings tab (ensures clean state) 
                else if oldTab != .settings && newTab == .settings {
                    print("🏠 SETTINGS ENTRY: Will ensure clean Settings state in background")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        navigationManager.resetSettingsNavigationWithoutAnimation()
                        settingsViewModel?.resetSheetState()
                        print("   ✅ Clean entry state ensured")
                    }
                } else {
                    print("   ℹ️ No Settings reset needed")
                }
            }
        )) {
            // Home Tab - Main intention interface
            HomeView(viewModel: viewModel)
                .tabItem {
                    Label(AppTab.home.rawValue, systemImage: AppTab.home.systemImage)
                }
                .tag(AppTab.home)
            
            // Groups Tab - App group management
            AppGroupsView(dataService: viewModel.dataServiceProvider, contentViewModel: viewModel)
                .tabItem {
                    Label(AppTab.groups.rawValue, systemImage: AppTab.groups.systemImage)
                }
                .tag(AppTab.groups)
            
            // Quick Actions Tab - Quick session management
            QuickActionsView(dataService: viewModel.dataServiceProvider, contentViewModel: viewModel)
                .tabItem {
                    Label(AppTab.quickActions.rawValue, systemImage: AppTab.quickActions.systemImage)
                }
                .tag(AppTab.quickActions)
            
            // Settings Tab
            SettingsView(
                dataService: viewModel.dataServiceProvider,
                setupCoordinator: viewModel.setupCoordinator,
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
        .sheet(isPresented: Binding(
            get: { viewModel.showingIntentionPrompt },
            set: { viewModel.showingIntentionPrompt = $0 }
        )) {
            IntentionPromptView(
                dataService: viewModel.dataServiceProvider,
                screenTimeService: viewModel.screenTimeService,
                categoryMappingService: viewModel.categoryMappingService,
                contentViewModel: viewModel,
                onSessionStart: { session in
                    await viewModel.startSession(session)
                },
                onCancel: {
                    viewModel.showingIntentionPrompt = false
                }
            )
        }
    }
}


#Preview {
    ContentView()
}
