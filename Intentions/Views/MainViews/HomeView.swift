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
            dataService: viewModel.dataServiceProvider
        ))
    }
    
    var body: some View {
        VStack(spacing: 16) {
            // Session header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Active Session")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    
                    Text("Focus time in progress")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                // Session status indicator
                Circle()
                    .fill(.green)
                    .frame(width: 12, height: 12)
            }
            
            // Time remaining
            VStack(spacing: 8) {
                Text(sessionStatusViewModel.formattedRemainingTime)
                    .font(.largeTitle.monospacedDigit())
                    .fontWeight(.bold)
                    .foregroundStyle(.primary)
                
                Text("remaining")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            
            // Progress bar
            ProgressView(value: sessionStatusViewModel.progress)
                .progressViewStyle(LinearProgressViewStyle(tint: .blue))
                .scaleEffect(y: 2)
            
            // Session actions
            HStack(spacing: 16) {
                Button("Extend") {
                    // TODO: Implement extend session
                }
                .buttonStyle(.bordered)
                
                Button("End Session") {
                    Task {
                        await viewModel.endCurrentSession()
                    }
                }
                .buttonStyle(.borderedProminent)
                .foregroundStyle(.white)
            }
        }
        .padding()
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .onAppear {
            // Set up session callbacks
            sessionStatusViewModel.onSessionExpired = {
                await viewModel.endCurrentSession()
            }
            sessionStatusViewModel.onSessionEnded = {
                await viewModel.endCurrentSession()
            }
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
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Quick Actions")
                .font(.headline)
                .padding(.horizontal)
            
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 16) {
                QuickActionCard(
                    title: "Work Session",
                    subtitle: "30 min focus",
                    icon: "laptopcomputer",
                    color: .blue
                ) {
                    // TODO: Start work session
                }
                
                QuickActionCard(
                    title: "Break Time",
                    subtitle: "15 min social",
                    icon: "cup.and.saucer.fill",
                    color: .orange
                ) {
                    // TODO: Start break session
                }
                
                QuickActionCard(
                    title: "Study Time",
                    subtitle: "60 min deep work",
                    icon: "book.fill",
                    color: .green
                ) {
                    // TODO: Start study session
                }
                
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
    HomeView(viewModel: ContentViewModel())
}