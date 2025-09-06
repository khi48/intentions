//
//  HomeView.swift
//  Intentions
//
//  Created by Claude on 12/07/2025.
//

import SwiftUI

/// Main home view showing current status and session controls
struct HomeView: View {
    let viewModel: ContentViewModel
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Current session status or welcome message
                    if let session = viewModel.activeSession {
                        ActiveSessionCard(session: session, viewModel: viewModel)
                    } else {
                        WelcomeCard(viewModel: viewModel)
                    }
                    
                    // Quick actions
                    QuickActionsSection(viewModel: viewModel)
                    
                    Spacer(minLength: 100)
                }
                .padding()
            }
            .navigationTitle("Intentions")
            .refreshable {
                await viewModel.initializeApp()
            }
        }
    }
}

/// Card showing active session information
private struct ActiveSessionCard: View {
    let session: IntentionSession
    let viewModel: ContentViewModel
    @State private var sessionStatusViewModel: SessionStatusViewModel
    
    init(session: IntentionSession, viewModel: ContentViewModel) {
        self.session = session
        self.viewModel = viewModel
        self._sessionStatusViewModel = State(initialValue: SessionStatusViewModel(
            session: session,
            contentViewModel: viewModel
        ))
    }
    
    var body: some View {
        SessionStatusView(
            viewModel: sessionStatusViewModel,
            onEndSession: {
                await viewModel.endCurrentSession()
            },
            onExtendSession: { _ in
                // Extension is handled internally by SessionStatusViewModel
                // This callback is kept for interface compatibility but does nothing
            }
        )
        .onAppear {
            // Legacy callback setup - no longer needed with direct dependency injection
            // SessionStatusViewModel now directly calls ContentViewModel methods
            // This block kept temporarily for any remaining edge cases
        }
        .onChange(of: session.id) { _, _ in
            // Update the session status view model when session changes
            sessionStatusViewModel.updateSession(session)
        }
    }
}

/// Welcome card for when no session is active
private struct WelcomeCard: View {
    let viewModel: ContentViewModel
    
    var body: some View {
        VStack(spacing: 20) {
            // Welcome header
            VStack(spacing: 8) {
                Image(systemName: "target")
                    .font(.system(size: 60))
                    .foregroundStyle(.blue)
                
                Text("Ready to Focus")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("Set an intention to unlock specific apps for a focused work session")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            // Start session button
            Button("Set Intention") {
                viewModel.showIntentionPrompt()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding()
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

/// Quick actions section
private struct QuickActionsSection: View {
    let viewModel: ContentViewModel
    @StateObject private var quickActionsViewModel = QuickActionsViewModel()
    @State private var availableQuickActions: [QuickAction] = []
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Quick Actions")
                    .font(.headline)
                
                Spacer()
                
                if !availableQuickActions.isEmpty {
                    Button("View All") {
                        viewModel.navigateToTab(.quickActions)
                    }
                    .font(.subheadline)
                    .foregroundColor(.blue)
                }
            }
            .padding(.horizontal)
            
            if availableQuickActions.isEmpty {
                // Show getting started card
                gettingStartedCard
            } else {
                // Show available quick actions (up to 4)
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 16) {
                    ForEach(Array(availableQuickActions.prefix(4))) { quickAction in
                        QuickActionCard(
                            title: quickAction.name,
                            subtitle: quickAction.subtitle ?? quickAction.formattedDuration,
                            icon: quickAction.iconName,
                            color: quickAction.color
                        ) {
                            Task {
                                await startQuickAction(quickAction)
                            }
                        }
                    }
                    
                    // Settings card if we have less than 4 quick actions
                    if availableQuickActions.count < 4 {
                        QuickActionCard(
                            title: "Settings",
                            subtitle: "Configure app",
                            icon: "gear",
                            color: .gray
                        ) {
                            viewModel.showSettings()
                        }
                    }
                }
            }
        }
        .onAppear {
            Task {
                await loadQuickActions()
            }
        }
        .onChange(of: viewModel.appGroupsDidChange) { _, _ in
            Task {
                await loadQuickActions()
            }
        }
    }
    
    private var gettingStartedCard: some View {
        VStack(spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 8) {
                    Text("No Quick Actions Yet")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    Text("Create quick actions for instant access to your favorite app groups and session types")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button("Create") {
                    viewModel.navigateToTab(.quickActions)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding()
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }
    
    private func loadQuickActions() async {
        quickActionsViewModel.setDataService(viewModel.dataServiceProvider)
        await quickActionsViewModel.loadData()
        availableQuickActions = quickActionsViewModel.getAvailableQuickActions()
    }
    
    private func startQuickAction(_ quickAction: QuickAction) async {
        do {
            // Record usage
            await quickActionsViewModel.recordQuickActionUsage(quickAction)
            
            // Create session from quick action
            let session = try quickAction.createSession(with: quickActionsViewModel.availableAppGroups)
            
            // Start the session through ContentViewModel
            await viewModel.startSession(session)
            
        } catch {
            // Handle error through viewModel
            await viewModel.handleError(error)
        }
    }
}

/// Individual quick action card
private struct QuickActionCard: View {
    let title: String
    let subtitle: String
    let icon: String
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 32))
                    .foregroundStyle(color)
                
                VStack(spacing: 4) {
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)
                    
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 120)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    HomeView(viewModel: try! ContentViewModel(dataService: MockDataPersistenceService()))
}