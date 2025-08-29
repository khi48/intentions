//
//  SessionStatusView.swift
//  Intentions
//
//  Created by Claude on 13/08/2025.
//

import SwiftUI

/// Comprehensive session status view showing active session progress and controls
struct SessionStatusView: View {
    @Bindable var viewModel: SessionStatusViewModel
    let onEndSession: () async -> Void
    let onExtendSession: (TimeInterval) async -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            // Session Header
            sessionHeader
            
            // Time Display
            timeDisplay
            
            // Progress Bar
            progressBar
            
            // Session Apps (if available)
            if !viewModel.sessionApps.isEmpty {
                sessionAppsSection
            }
            
            // Action Buttons
            actionButtons
        }
        .padding()
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .sheet(isPresented: $viewModel.showingExtendDialog) {
            ExtendSessionSheet(
                viewModel: viewModel,
                onExtend: { minutes in
                    await viewModel.extendSession(by: minutes)
                    // Note: onExtendSession is not needed here as SessionStatusViewModel handles the extension
                }
            )
        }
    }
    
    // MARK: - Session Header
    
    private var sessionHeader: some View {
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
            
            // Session status indicator with pulse animation
            Circle()
                .fill(.green)
                .frame(width: 12, height: 12)
                .scaleEffect(viewModel.isSessionActive ? 1.0 : 0.8)
                .opacity(viewModel.isSessionActive ? 1.0 : 0.6)
                .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: viewModel.isSessionActive)
        }
    }
    
    // MARK: - Time Display
    
    private var timeDisplay: some View {
        VStack(spacing: 12) {
            // Remaining Time
            VStack(spacing: 8) {
                Text(viewModel.formattedRemainingTime)
                    .font(.largeTitle.monospacedDigit())
                    .fontWeight(.bold)
                    .foregroundStyle(.primary)
                
                Text("remaining")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            
            // Elapsed vs Total
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Elapsed")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(viewModel.formattedElapsedTime)
                        .font(.subheadline.monospacedDigit())
                        .fontWeight(.medium)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Total")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(viewModel.formattedTotalDuration)
                        .font(.subheadline.monospacedDigit())
                        .fontWeight(.medium)
                }
            }
        }
    }
    
    // MARK: - Progress Bar
    
    private var progressBar: some View {
        VStack(spacing: 8) {
            ProgressView(value: viewModel.progress)
                .progressViewStyle(LinearProgressViewStyle(tint: progressColor))
                .scaleEffect(y: 3)
            
            HStack {
                Text("\(Int(viewModel.progress * 100))% complete")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                if viewModel.progress > 0.8 {
                    Text("Almost done! 🎯")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
    }
    
    private var progressColor: Color {
        switch viewModel.progress {
        case 0.0..<0.5:
            return .green
        case 0.5..<0.8:
            return .orange
        default:
            return .red
        }
    }
    
    // MARK: - Session Apps Section
    
    private var sessionAppsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Allowed Apps")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                Text("\(viewModel.sessionApps.count) apps")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(viewModel.sessionApps.prefix(10)) { app in
                        VStack(spacing: 4) {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(.blue.opacity(0.1))
                                .frame(width: 40, height: 40)
                                .overlay(
                                    Text(String(app.displayName.prefix(1)))
                                        .font(.headline)
                                        .fontWeight(.semibold)
                                        .foregroundStyle(.blue)
                                )
                            
                            Text(app.displayName)
                                .font(.caption2)
                                .lineLimit(1)
                                .foregroundStyle(.secondary)
                        }
                        .frame(width: 50)
                    }
                    
                    if viewModel.sessionApps.count > 10 {
                        VStack(spacing: 4) {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(.gray.opacity(0.1))
                                .frame(width: 40, height: 40)
                                .overlay(
                                    Text("+\(viewModel.sessionApps.count - 10)")
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                        .foregroundStyle(.gray)
                                )
                            
                            Text("more")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .frame(width: 50)
                    }
                }
                .padding(.horizontal, 4)
            }
        }
        .padding()
        .background(.blue.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    // MARK: - Action Buttons
    
    private var actionButtons: some View {
        HStack(spacing: 16) {
            // Extend Button
            Button(action: {
                viewModel.showExtendDialog()
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "clock.arrow.circlepath")
                    Text("Extend")
                }
            }
            .buttonStyle(.bordered)
            .disabled(viewModel.isLoading)
            
            // End Session Button
            Button(action: {
                Task {
                    await onEndSession()
                }
            }) {
                HStack(spacing: 8) {
                    if viewModel.isLoading {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "stop.circle")
                    }
                    Text("End Session")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.isLoading)
        }
    }
}

// MARK: - Extend Session Sheet

private struct ExtendSessionSheet: View {
    @Bindable var viewModel: SessionStatusViewModel
    let onExtend: (Int) async -> Void
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 8) {
                    Text("Extend Session")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Text("Add more time to your current focused session")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top)
                
                // Current time info
                VStack(spacing: 12) {
                    HStack {
                        Text("Current session:")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        
                        Spacer()
                        
                        Text(viewModel.formattedRemainingTime)
                            .font(.subheadline.monospacedDigit())
                            .fontWeight(.medium)
                            .foregroundStyle(.primary)
                    }
                    
                    ProgressView(value: viewModel.progress)
                        .progressViewStyle(LinearProgressViewStyle(tint: .blue))
                        .scaleEffect(y: 2)
                }
                .padding()
                .background(.blue.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                
                // Extension options
                VStack(alignment: .leading, spacing: 16) {
                    Text("Add time:")
                        .font(.headline)
                    
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 12) {
                        ForEach(viewModel.extensionOptions, id: \.self) { minutes in
                            ExtensionOptionButton(
                                minutes: minutes,
                                action: {
                                    Task {
                                        await onExtend(minutes)
                                        dismiss()
                                    }
                                }
                            )
                        }
                    }
                }
                
                Spacer()
            }
            .padding()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

private struct ExtensionOptionButton: View {
    let minutes: Int
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Text("+\(minutes)")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text(minutes == 1 ? "minute" : "minutes")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 60)
            .background(.blue.opacity(0.1))
            .foregroundStyle(.blue)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    // Create a mock session for preview
    let mockSession = try! IntentionSession(
        appGroups: [],
        applications: Set(),
        categories: Set(),
        duration: 1800 // 30 minutes
    )
    
    let mockContentViewModel = try! ContentViewModel(dataService: MockDataPersistenceService())
    let mockViewModel = SessionStatusViewModel(
        session: mockSession,
        contentViewModel: mockContentViewModel
    )
    
    return SessionStatusView(
        viewModel: mockViewModel,
        onEndSession: { },
        onExtendSession: { _ in }
    )
    .padding()
}