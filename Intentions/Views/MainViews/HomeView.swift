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

                    // Auth-revoked banner
                    if !viewModel.isScreenTimeServiceReady && !viewModel.isAppReady {
                        ScreenTimeAccessBanner(viewModel: viewModel)
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
    private var quickActionsViewModel: QuickActionsViewModel
    @State private var draggingQuickAction: QuickAction?
    @State private var editorMode: QuickActionEditorMode?
    @State private var isPulsing = false
    @State private var pendingQuickAction: QuickAction?

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

            if quickActionsViewModel.quickActions.isEmpty && !quickActionsViewModel.isLoading {
                // Show getting started card only after loading completes
                gettingStartedCard
            } else if !quickActionsViewModel.quickActions.isEmpty {
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
                                isRunning: isQuickActionRunning(quickAction),
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
                            .accessibilityHint("Long press to reorder")
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
        .alert("Please re-pick your apps", isPresented: Binding(
            get: { quickActionsViewModel.showStaleTokenMigrationNotice },
            set: { quickActionsViewModel.showStaleTokenMigrationNotice = $0 }
        )) {
            Button("OK", role: .cancel) {
                quickActionsViewModel.showStaleTokenMigrationNotice = false
            }
        } message: {
            Text("A Screen Time update required clearing the app selections on your quick actions. Your names, icons, and durations are preserved — tap a quick action to re-pick its apps.")
        }
        .alert("Replace current session?", isPresented: Binding(
            get: { pendingQuickAction != nil },
            set: { if !$0 { pendingQuickAction = nil } }
        )) {
            Button("Cancel", role: .cancel) {
                pendingQuickAction = nil
            }
            Button("Replace") {
                if let quickAction = pendingQuickAction {
                    pendingQuickAction = nil
                    Task {
                        await executeQuickAction(quickAction)
                    }
                }
            }
        } message: {
            if let session = viewModel.activeSession {
                Text("You have \(session.remainingTime.formattedDuration) left on your current session. Starting a new one will end it.")
            }
        }
    }
    
    private var gettingStartedCard: some View {
        VStack(spacing: 0) {
            // Headline
            Text("Set your first intention")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(AppConstants.Colors.text)
                .multilineTextAlignment(.center)
                .padding(.top, 8)
                .padding(.bottom, 28)

            // The altar card — a single prominent ghost card in the shape of
            // an eventual QuickActionCard, but larger. Tapping opens the editor.
            Button(action: {
                editorMode = .create
            }) {
                VStack(spacing: 14) {
                    // Emblem: pulsing ring around a plus symbol
                    ZStack {
                        // Pulsing outer ring (animates outward and fades)
                        Circle()
                            .stroke(AppConstants.Colors.textSecondary, lineWidth: 1)
                            .frame(width: 88, height: 88)
                            .scaleEffect(isPulsing ? 1.15 : 1.0)
                            .opacity(isPulsing ? 0 : 0.5)

                        // Static ring
                        Circle()
                            .stroke(AppConstants.Colors.textSecondary.opacity(0.5), lineWidth: 1)
                            .frame(width: 88, height: 88)

                        Image(systemName: "plus")
                            .font(.system(size: 32, weight: .light))
                            .foregroundColor(AppConstants.Colors.text)
                    }
                    .frame(width: 88, height: 88)
                    .padding(.bottom, 4)

                    Text("Create a quick action")
                        .font(.headline)
                        .foregroundColor(AppConstants.Colors.text)
                }
                .frame(maxWidth: .infinity)
                .frame(minHeight: 340)
                .padding(.vertical, 40)
                .background(
                    RadialGradient(
                        colors: [
                            AppConstants.Colors.text.opacity(0.04),
                            Color.clear
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: 180
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .strokeBorder(
                            AppConstants.Colors.textSecondary.opacity(0.6),
                            style: StrokeStyle(lineWidth: 1, dash: [4, 4])
                        )
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Create a quick action")
            .accessibilityHint("Double tap to open the quick action editor")
        }
        .padding(.horizontal)
        .onAppear {
            withAnimation(.easeOut(duration: 4).repeatForever(autoreverses: false)) {
                isPulsing = true
            }
        }
    }
    
    private func isQuickActionRunning(_ quickAction: QuickAction) -> Bool {
        guard let session = viewModel.activeSession, session.isActive,
              case .quickAction(let qa) = session.source else { return false }
        return qa.id == quickAction.id
    }

    private func loadQuickActions() async {
        await quickActionsViewModel.loadData()
    }
    
    private func startQuickAction(_ quickAction: QuickAction) async {
        // Confirm before replacing a running session
        if viewModel.activeSession?.isActive == true {
            pendingQuickAction = quickAction
            return
        }
        await executeQuickAction(quickAction)
    }

    private func executeQuickAction(_ quickAction: QuickAction) async {
        do {
            await quickActionsViewModel.recordQuickActionUsage(quickAction)
            let session = try quickAction.createSession()
            await viewModel.startSession(session)
        } catch {
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

        guard let from = quickActionsViewModel.quickActions.firstIndex(of: current),
              let to = quickActionsViewModel.quickActions.firstIndex(of: item) else { return }

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

/// Banner shown when Screen Time authorization is missing or revoked
private struct ScreenTimeAccessBanner: View {
    let viewModel: ContentViewModel
    @State private var isRequesting = false

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.shield")
                .font(.system(size: 36))
                .foregroundColor(AppConstants.Colors.textSecondary)

            Text("Screen Time Access Required")
                .font(.headline)
                .foregroundColor(AppConstants.Colors.text)

            Text("Intent needs Screen Time access to manage app blocking. Enable it to start using quick actions.")
                .font(.subheadline)
                .foregroundColor(AppConstants.Colors.textSecondary)
                .multilineTextAlignment(.center)

            Button(action: {
                isRequesting = true
                Task {
                    await viewModel.requestReauthorization()
                    isRequesting = false
                }
            }) {
                HStack(spacing: 8) {
                    if isRequesting {
                        ProgressView()
                            .tint(AppConstants.Colors.background)
                    }
                    Text("Enable Access")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(AppConstants.Colors.text)
                .foregroundColor(AppConstants.Colors.background)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled(isRequesting)

            Text("Or go to **Settings → Screen Time → Intent** to enable manually.")
                .font(.caption)
                .foregroundColor(AppConstants.Colors.textSecondary.opacity(0.7))
                .multilineTextAlignment(.center)
        }
        .padding(20)
        .background(AppConstants.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(AppConstants.Colors.textSecondary.opacity(0.15), lineWidth: 1)
        )
    }
}

/// Individual quick action card
private struct QuickActionCard: View {
    let title: String
    let subtitle: String
    let icon: String
    let color: Color
    let isReady: Bool
    let isRunning: Bool
    let onTap: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 32))
                    .foregroundStyle(AppConstants.Colors.text)
                    .accessibilityHidden(true)

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
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(subtitle)")
        .accessibilityHint(isReady ? "Double tap to start session" : "Screen Time not ready")
        .contextMenu {
            if isRunning {
                Label("Session in progress", systemImage: "lock.fill")
            } else {
                Button(action: onEdit) {
                    Label("Edit", systemImage: "pencil")
                }
                Button(role: .destructive, action: onDelete) {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
    }
}


#Preview {
    HomeView(viewModel: try! ContentViewModel(dataService: MockDataPersistenceService()))
}