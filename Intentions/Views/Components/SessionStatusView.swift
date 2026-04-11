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
            // Session Context (quick action name or apps)
            sessionContext

            // Time Display
            timeDisplay

            // Progress Bar
            progressBar

            // Action Buttons
            actionButtons
        }
        .padding()
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
    
    // MARK: - Session Context

    private var sessionContext: some View {
        VStack(spacing: 12) {
            if let session = viewModel.session {
                if case .quickAction(let quickAction) = session.source {
                    HStack(spacing: 12) {
                        Image(systemName: quickAction.iconName)
                            .foregroundColor(.gray)
                            .font(.title)
                            .frame(width: 28, height: 28)

                        Text(quickAction.name)
                            .font(.title2)
                            .fontWeight(.medium)
                            .foregroundColor(.gray)

                        Spacer()
                    }
                } else if !session.requestedApplications.isEmpty {
                    HStack(spacing: 12) {
                        Text("Apps Allowed")
                            .font(.title2)
                            .fontWeight(.medium)
                            .foregroundColor(.gray)

                        let tokens = Array(session.requestedApplications)
                        let maxPreviewIcons = 3

                        HStack(spacing: -2) {
                            ForEach(tokens.prefix(maxPreviewIcons).enumerated().map { $0 }, id: \.offset) { index, token in
                                Label(token)
                                    .labelStyle(.iconOnly)
                                    .grayscale(1.0)
                                    .frame(width: 20, height: 20)
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                                    .zIndex(Double(maxPreviewIcons - index))
                            }

                            if tokens.count > maxPreviewIcons {
                                Text("+\(tokens.count - maxPreviewIcons)")
                                    .font(.caption2)
                                    .foregroundColor(.gray)
                                    .padding(.leading, 4)
                            }
                        }

                        Spacer()
                    }
                }
            }
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
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Time remaining: \(viewModel.formattedRemainingTime)")
    }
    
    // MARK: - Progress Bar
    
    private var progressBar: some View {
        VStack(spacing: 8) {
            ProgressView(value: viewModel.progress)
                .progressViewStyle(LinearProgressViewStyle(tint: AppConstants.Colors.textSecondary))
                .scaleEffect(y: 3)

            HStack {
                Text("\(Int(viewModel.progress * 100))% complete")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                if viewModel.progress > 0.8 {
                    Text("Almost done!")
                        .font(.caption)
                        .foregroundStyle(AppConstants.Colors.textSecondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(Int(viewModel.progress * 100)) percent complete")
    }
    
    // MARK: - Action Buttons

    private var actionButtons: some View {
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
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .foregroundColor(.gray)
        .disabled(viewModel.isLoading)
        .accessibilityLabel("End current session")
        .accessibilityHint("Double tap to end your focused session and re-block apps")
    }
}

// MARK: - Extend Session Sheet

private struct ExtendSessionSheet: View {
    @Bindable var viewModel: SessionStatusViewModel
    let onExtend: (Int) async -> Void
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VStack(spacing: 16) {
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
                .padding(.top, 8)

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
                .padding(.top, 8)

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
            .background(AppConstants.Colors.surface)
            .foregroundStyle(AppConstants.Colors.text)
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