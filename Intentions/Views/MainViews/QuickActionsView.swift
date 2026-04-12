//
//  QuickActionsView.swift
//  Intentions
//
//  Created by Claude on 03/09/2025.
//

import SwiftUI
import FamilyControls

/// Sheet presentation mode for QuickActionEditor
enum QuickActionEditorMode: Identifiable {
    case create
    case edit(QuickAction)

    var id: String {
        switch self {
        case .create:
            return "create"
        case .edit(let action):
            return "edit-\(action.id.uuidString)"
        }
    }

    var quickAction: QuickAction? {
        switch self {
        case .create:
            return nil
        case .edit(let action):
            return action
        }
    }
}

/// Main view for managing quick actions - pre-configured sessions for fast access
struct QuickActionsView: View {
    let dataService: DataPersisting
    let contentViewModel: ContentViewModel

    @Bindable private var viewModel: QuickActionsViewModel
    @State private var editorMode: QuickActionEditorMode?
    @State private var searchText = ""

    init(dataService: DataPersisting, contentViewModel: ContentViewModel) {
        self.dataService = dataService
        self.contentViewModel = contentViewModel
        self.viewModel = contentViewModel.sharedQuickActionsViewModel
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Search bar
                searchBar

                if viewModel.isLoading {
                    loadingView
                } else if viewModel.quickActions.isEmpty {
                    emptyStateView
                } else {
                    actionsList
                }
            }
            .background(AppConstants.Colors.background)
            .navigationTitle("Quick Actions")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    createQuickActionButton
                }
            }
            .sheet(item: $editorMode) { mode in
                QuickActionEditorSheet(
                    dataService: dataService,
                    editingQuickAction: mode.quickAction,
                    onSave: { quickAction in
                        await viewModel.saveQuickAction(quickAction)
                        editorMode = nil
                    },
                    onCancel: {
                        editorMode = nil
                    },
                    onDelete: { quickAction in
                        await viewModel.deleteQuickAction(quickAction)
                        editorMode = nil
                    }
                )
            }
            .alert("Error", isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { _ in viewModel.clearError() }
            )) {
                Button("OK") { viewModel.clearError() }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
            .alert("Delete Quick Action", isPresented: $viewModel.showingDeleteAlert) {
                deleteConfirmationAlert
            }
        }
        .task {
            await loadData()
        }
    }
    
    // MARK: - Loading View
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
            
            Text("Loading quick actions...")
                .font(.subheadline)
                .foregroundColor(AppConstants.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Empty State
    
    private var emptyStateView: some View {
        VStack(spacing: 24) {
            Spacer()
            
            Image(systemName: "bolt.slash")
                .font(.system(size: 80))
                .foregroundColor(AppConstants.Colors.textSecondary)
            
            VStack(spacing: 8) {
                Text("No Quick Actions Yet")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(AppConstants.Colors.text)
                
                Text("Create quick actions for instant access to your most common app groups and session types")
                    .font(.subheadline)
                    .foregroundColor(AppConstants.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            
            Button(action: createQuickAction) {
                HStack(spacing: 8) {
                    Image(systemName: "plus")
                    Text("Create Your First Quick Action")
                }
                .font(.headline)
                .foregroundColor(AppConstants.Colors.text)
                .padding(.vertical, 12)
                .padding(.horizontal, 24)
                .background(AppConstants.Colors.buttonPrimary)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            
            Spacer()
        }
        .padding()
    }
    
    // MARK: - Search Bar
    
    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(AppConstants.Colors.textSecondary)
            
            TextField("Search quick actions...", text: $searchText)
                .textFieldStyle(PlainTextFieldStyle())
            
            if !searchText.isEmpty {
                Button(action: { searchText = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(AppConstants.Colors.textSecondary)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(AppConstants.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal)
        .padding(.top, 8)
    }
    
    // MARK: - Actions List
    
    private var actionsList: some View {
        List {
                ForEach(filteredQuickActions) { quickAction in
                    QuickActionRowView(
                        quickAction: quickAction,
                        onTap: {
                            Task {
                                await startQuickAction(quickAction)
                            }
                        },
                        onEdit: {
                            editorMode = .edit(quickAction)
                        },
                        onDelete: {
                            viewModel.confirmDeleteQuickAction(quickAction)
                        },
                    )
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }
            }
            .listStyle(PlainListStyle())
            .background(AppConstants.Colors.background)
            .scrollContentBackground(.hidden)
    }
    
    
    // MARK: - Create Button
    
    private var createQuickActionButton: some View {
        Button(action: createQuickAction) {
            Image(systemName: "plus")
                .font(.title2)
                .fontWeight(.medium)
        }
        .disabled(viewModel.isLoading)
    }
    
    
    // MARK: - Delete Alert
    
    private var deleteConfirmationAlert: some View {
        Group {
            Button("Cancel", role: .cancel) {
                viewModel.cancelDelete()
            }
            
            Button("Delete", role: .destructive) {
                if let quickAction = viewModel.quickActionToDelete {
                    Task {
                        await viewModel.deleteQuickAction(quickAction)
                    }
                }
            }
        }
    }
    
    // MARK: - Actions
    
    private func createQuickAction() {
        editorMode = .create
    }
    
    private func startQuickAction(_ quickAction: QuickAction) async {
        do {
            // Record usage
            await viewModel.recordQuickActionUsage(quickAction)

            // Create session from quick action
            let session = try quickAction.createSession()

            // Start the session through ContentViewModel
            await contentViewModel.startSession(session)
            
            // Navigate to Home tab to show active session
            contentViewModel.navigateToTab(.home)
            
        } catch {
            await viewModel.handleError(error)
        }
    }
    
    private func loadData() async {
        await viewModel.loadData()

        // Also trigger app groups refresh
        contentViewModel.notifyAppGroupsChanged()
    }
    
    // MARK: - Computed Properties
    
    private var filteredQuickActions: [QuickAction] {
        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return viewModel.quickActions.sorted { $0.usageCount > $1.usageCount }
        } else {
            let searchQuery = searchText.lowercased()
            return viewModel.quickActions.filter { quickAction in
                quickAction.name.lowercased().contains(searchQuery) ||
                (quickAction.subtitle?.lowercased().contains(searchQuery) ?? false)
            }.sorted { $0.usageCount > $1.usageCount }
        }
    }
}

// MARK: - Quick Action Row View

private struct QuickActionRowView: View {
    let quickAction: QuickAction
    let onTap: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with name and info
            HStack {
                HStack(spacing: 12) {
                    // Icon with greyscale
                    Image(systemName: quickAction.iconName)
                        .font(.title2)
                        .foregroundColor(AppConstants.Colors.text)
                        .frame(width: 32, height: 32)
                        .frame(minWidth: 32, minHeight: 32)
                        .background(AppConstants.Colors.surface)
                        .clipShape(Circle())
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(quickAction.name)
                            .font(.headline)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                            .lineLimit(1)
                        
                        if let subtitle = quickAction.subtitle {
                            Text(subtitle)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                
                Spacer()
            }
            
            // Duration and content info
            HStack(spacing: 20) {
                HStack(spacing: 6) {
                    Image(systemName: "clock")
                        .font(.caption)
                        .foregroundColor(AppConstants.Colors.textSecondary)
                    Text(quickAction.formattedDuration)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                HStack(spacing: 6) {
                    Image(systemName: "app.badge")
                        .font(.caption)
                        .foregroundColor(AppConstants.Colors.textSecondary)
                    Text("\(quickAction.individualApplications.count) items")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if quickAction.usageCount > 0 {
                    HStack(spacing: 6) {
                        Image(systemName: "chart.bar")
                            .font(.caption)
                            .foregroundColor(AppConstants.Colors.textSecondary)
                        Text("Used \(quickAction.usageCount)x")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
            }
        }
        .padding()
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .contentShape(Rectangle())
        .onTapGesture {
            onTap()
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button("Delete", role: .destructive) {
                onDelete()
            }
            .tint(Color(.systemGray3))
            .foregroundColor(AppConstants.Colors.text)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.systemGray3))
                    .padding(4)
            )

            Button("Edit") {
                onEdit()
            }
            .tint(Color(.systemGray5))
            .foregroundColor(AppConstants.Colors.text)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.systemGray5))
                    .padding(4)
            )
        }
    }
}

#Preview {
    QuickActionsView(
        dataService: MockDataPersistenceService(),
        contentViewModel: try! ContentViewModel(dataService: MockDataPersistenceService())
    )
}