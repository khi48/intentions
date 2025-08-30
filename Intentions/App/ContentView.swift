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
        .alert("Error", isPresented: .constant(viewModel.errorMessage != nil)) {
            Button("OK") {
                viewModel.clearError()
            }
        } message: {
            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
            }
        }
    }
}

/// Main tab-based navigation when app is authorized
private struct MainTabView: View {
    let viewModel: ContentViewModel
    
    var body: some View {
        TabView(selection: Binding(
            get: { viewModel.selectedTab },
            set: { viewModel.navigateToTab($0) }
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
            
            // Settings Tab
            SettingsView(
                dataService: viewModel.dataServiceProvider
            )
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
