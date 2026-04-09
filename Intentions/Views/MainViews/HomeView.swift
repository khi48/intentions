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
                    // Current session status
                    if let session = viewModel.activeSession {
                        ActiveSessionCard(session: session, viewModel: viewModel)
                    }

                    // Quick actions (now the main way to start sessions)
                    QuickActionsSection(viewModel: viewModel)

                    Spacer(minLength: 100)
                }
                .padding()
            }
            .background(AppConstants.Colors.background)
            .navigationTitle("Intent")
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

/// Quick actions section
private struct QuickActionsSection: View {
    let viewModel: ContentViewModel
    @ObservedObject private var quickActionsViewModel: QuickActionsViewModel
    @State private var draggingQuickAction: QuickAction?
    @State private var editorMode: QuickActionEditorMode?

    init(viewModel: ContentViewModel) {
        self.viewModel = viewModel
        self.quickActionsViewModel = viewModel.sharedQuickActionsViewModel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Quick Actions")
                    .font(.headline)
                    .foregroundColor(AppConstants.Colors.text)

                Spacer()

                Button(action: {
                    editorMode = .create
                }) {
                    Image(systemName: "plus")
                        .font(.title3)
                        .foregroundColor(AppConstants.Colors.accent)
                }
            }
            .padding(.horizontal)

            if quickActionsViewModel.quickActions.isEmpty {
                // Show getting started card
                gettingStartedCard
            } else {
                // Show available quick actions with drag-to-reorder
                VStack(spacing: 16) {
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: 16) {
                        ForEach(Array(quickActionsViewModel.quickActions.enumerated()), id: \.element.id) { index, quickAction in
                            QuickActionCard(
                                title: quickAction.name,
                                subtitle: quickAction.subtitle ?? quickAction.formattedDuration,
                                icon: quickAction.iconName,
                                color: quickAction.color,
                                isReady: viewModel.isScreenTimeServiceReady,
                                onTap: {
                                    Task {
                                        await startQuickAction(quickAction)
                                    }
                                },
                                onEdit: {
                                    editorMode = .edit(quickAction)
                                },
                                onDelete: {
                                    quickActionsViewModel.confirmDeleteQuickAction(quickAction)
                                }
                            )
                            .onDrag {
                                draggingQuickAction = quickAction
                                return NSItemProvider(object: quickAction.id.uuidString as NSString)
                            } preview: {
                                // Custom drag preview - empty view to hide the default preview
                                Color.clear
                                    .frame(width: 1, height: 1)
                            }
                            .onDrop(of: [.text], delegate: QuickActionDragRelocateDelegate(
                                item: quickAction,
                                quickActionsViewModel: quickActionsViewModel,
                                current: $draggingQuickAction
                            ))
                        }
                    }
                    .animation(.default, value: quickActionsViewModel.quickActions)
                }
            }
        }
        .onDrop(of: [.text], delegate: QuickActionDropOutsideDelegate(current: $draggingQuickAction))
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
        .sheet(item: $editorMode) { mode in
            QuickActionEditorSheet(
                dataService: viewModel.dataServiceProvider,
                editingQuickAction: mode.quickAction,
                onSave: { quickAction in
                    await quickActionsViewModel.saveQuickAction(quickAction)
                    editorMode = nil
                },
                onCancel: {
                    editorMode = nil
                },
                onDelete: { quickAction in
                    await quickActionsViewModel.deleteQuickAction(quickAction)
                    editorMode = nil
                }
            )
        }
        .alert("Delete Quick Action", isPresented: Binding(
            get: { quickActionsViewModel.showingDeleteAlert },
            set: { quickActionsViewModel.showingDeleteAlert = $0 }
        )) {
            Button("Cancel", role: .cancel) {
                quickActionsViewModel.cancelDelete()
            }
            Button("Delete", role: .destructive) {
                if let quickAction = quickActionsViewModel.quickActionToDelete {
                    Task {
                        await quickActionsViewModel.deleteQuickAction(quickAction)
                    }
                }
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
                        .foregroundColor(AppConstants.Colors.text)

                    Text("Create quick actions for instant access to your favorite app groups and session types")
                        .font(.caption)
                        .foregroundColor(AppConstants.Colors.textSecondary)
                }

                Spacer()

                Button("Create") {
                    editorMode = .create
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .foregroundColor(AppConstants.Colors.text)
            }
        }
        .padding()
        .background(AppConstants.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }
    
    private func loadQuickActions() async {
        await quickActionsViewModel.loadData()
    }
    
    private func startQuickAction(_ quickAction: QuickAction) async {
        do {
            // Record usage
            await quickActionsViewModel.recordQuickActionUsage(quickAction)

            // Create session from quick action
            let session = try quickAction.createSession()

            // Start the session through ContentViewModel
            await viewModel.startSession(session)

        } catch {
            // Handle error through viewModel
            await viewModel.handleError(error)
        }
    }

    // Drag and drop functionality is now handled by delegates below
}

/// Drop delegate for quick action reordering within the grid
private struct QuickActionDragRelocateDelegate: DropDelegate {
    let item: QuickAction
    let quickActionsViewModel: QuickActionsViewModel
    @Binding var current: QuickAction?

    func dropEntered(info: DropInfo) {
        guard let current = current, item != current else { return }

        let from = quickActionsViewModel.quickActions.firstIndex(of: current)!
        let to = quickActionsViewModel.quickActions.firstIndex(of: item)!

        if from != to {
            Task {
                await quickActionsViewModel.moveQuickAction(from: from, to: to)
            }
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        return DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        current = nil
        return true
    }
}

/// Drop delegate for handling drops outside the grid (to reset drag state)
private struct QuickActionDropOutsideDelegate: DropDelegate {
    @Binding var current: QuickAction?

    func dropUpdated(info: DropInfo) -> DropProposal? {
        return DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        current = nil
        return true
    }
}

/// Individual quick action card
private struct QuickActionCard: View {
    let title: String
    let subtitle: String
    let icon: String
    let color: Color
    let isReady: Bool
    let onTap: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 32))
                    .foregroundStyle(AppConstants.Colors.text)

                VStack(spacing: 4) {
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(AppConstants.Colors.text)

                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(AppConstants.Colors.textSecondary)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 120)
            .background(AppConstants.Colors.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .disabled(!isReady)
        .opacity(isReady ? 1.0 : 0.6)
        .animation(.easeInOut(duration: 0.3), value: isReady)
        .contextMenu {
            Button(action: onEdit) {
                Label("Edit", systemImage: "pencil")
            }
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}


#Preview {
    HomeView(viewModel: try! ContentViewModel(dataService: MockDataPersistenceService()))
}