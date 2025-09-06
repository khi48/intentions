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
            if viewModel.showingCategoryMappingSetup {
                CategoryMappingSetupView { mappingService in
                    viewModel.completeCategoryMappingSetup(mappingService)
                }
            } else if viewModel.isAppReady {
                MainTabView(viewModel: viewModel)
            } else {
                AuthorizationView(viewModel: viewModel)
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

/// Authorization request view when Screen Time access is needed
private struct AuthorizationView: View {
    let viewModel: ContentViewModel
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 30) {
                Spacer()
                
                // App branding
                VStack(spacing: 16) {
                    Image(systemName: "shield.lefthalf.filled")
                        .font(.system(size: 80))
                        .foregroundStyle(.blue)
                    
                    Text("Intentions")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    Text("Focus with Purpose")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                // Authorization explanation
                VStack(spacing: 20) {
                    VStack(spacing: 12) {
                        Text("Screen Time Access Required")
                            .font(.headline)
                        
                        Text("Intentions needs Screen Time permissions to help you focus by blocking distracting apps.")
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                    }
                    
                    // Authorization status
                    AuthorizationStatusView(status: viewModel.authorizationStatus)
                }
                .padding(.horizontal)
                
                Spacer()
                
                // Action button
                VStack(spacing: 16) {
                    Button(action: {
                        Task {
                            await viewModel.requestAuthorization()
                        }
                    }) {
                        HStack {
                            if viewModel.isLoading {
                                ProgressView()
                                    .scaleEffect(0.8)
                            }
                            Text(authorizationButtonTitle)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Color.blue)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .disabled(viewModel.isLoading)
                    
                    if viewModel.authorizationStatus == .denied {
                        Text("Please enable Screen Time in System Settings")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 50)
            }
            .navigationTitle("Setup")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
    
    private var authorizationButtonTitle: String {
        switch viewModel.authorizationStatus {
        case .notDetermined:
            return "Request Screen Time Access"
        case .denied:
            return "Open Settings"
        case .approved:
            return "Continue"
        @unknown default:
            return "Request Access"
        }
    }
}

/// Shows the current authorization status with appropriate styling
private struct AuthorizationStatusView: View {
    let status: AuthorizationStatus
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: statusIcon)
                .foregroundStyle(statusColor)
            
            Text(statusText)
                .font(.subheadline)
                .foregroundStyle(statusColor)
        }
        .padding()
        .background(statusColor.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
    
    private var statusIcon: String {
        switch status {
        case .notDetermined:
            return "questionmark.circle"
        case .denied:
            return "xmark.circle"
        case .approved:
            return "checkmark.circle"
        @unknown default:
            return "questionmark.circle"
        }
    }
    
    private var statusColor: Color {
        switch status {
        case .notDetermined:
            return .orange
        case .denied:
            return .red
        case .approved:
            return .green
        @unknown default:
            return .gray
        }
    }
    
    private var statusText: String {
        switch status {
        case .notDetermined:
            return "Authorization not requested"
        case .denied:
            return "Access denied"
        case .approved:
            return "Access granted"
        @unknown default:
            return "Unknown status"
        }
    }
}

#Preview {
    ContentView()
}
