//
//  AppGroupListView.swift
//  Intentions
//
//  Created by Claude on 27/08/2025.
//

import SwiftUI
import ManagedSettings
import FamilyControls

/// Comprehensive view for managing app groups and collections
/// Provides CRUD operations for user-created app groups
struct AppGroupListView: View {
    @Bindable var viewModel: AppGroupsViewModel
    
    // Tap debouncing for create group button
    @State private var lastCreateTapTime: Date = .distantPast
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Search bar
                searchBar

                // Content based on state
                if viewModel.isLoading {
                    loadingView
                } else if viewModel.appGroups.isEmpty {
                    emptyStateView
                } else {
                    groupsList
                }
            }
            .background(AppConstants.Colors.background)
            .navigationTitle("App Groups")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    createGroupButton
                }
            }
            .sheet(isPresented: $viewModel.showingGroupEditor) {
                AppGroupEditorSheet(
                    viewModel: viewModel,
                    editingGroup: viewModel.editingGroup
                )
            }
            .alert("Delete App Group", isPresented: $viewModel.showingDeleteAlert) {
                deleteConfirmationAlert
            }
            // Use a more defensive approach for error alerts
            .background(
                EmptyView()
                    .alert("Error", isPresented: Binding(
                        get: { 
                            // COMPLETELY DISABLE AppGroupListView alerts to prevent presentation conflicts
                            false  // All errors will be handled by individual sheets/views
                        },
                        set: { _ in 
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                viewModel.clearError() 
                            }
                        }
                    )) {
                        Button("OK") {
                            viewModel.clearError() 
                        }
                    } message: {
                        Text(viewModel.errorMessage ?? "")
                    }
            )
        }
        .task {
            await viewModel.loadData()
        }
    }
    
    // MARK: - Search Bar
    
    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(AppConstants.Colors.textSecondary)
            
            TextField("Search app groups...", text: $viewModel.searchText)
                .textFieldStyle(PlainTextFieldStyle())
            
            if !viewModel.searchText.isEmpty {
                Button(action: { viewModel.searchText = "" }) {
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
    
    // MARK: - Loading View
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
            
            Text("Loading app groups...")
                .font(.subheadline)
                .foregroundColor(AppConstants.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Empty State
    
    private var emptyStateView: some View {
        VStack(spacing: 24) {
            Spacer()
            
            Image(systemName: "square.stack.3d.up.slash")
                .font(.system(size: 80))
                .foregroundColor(AppConstants.Colors.textSecondary)
            
            VStack(spacing: 8) {
                Text("No App Groups Yet")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(AppConstants.Colors.text)
                
                Text("Create your first app group to organize apps into collections for quick session setup")
                    .font(.subheadline)
                    .foregroundColor(AppConstants.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            
            Button(action: {
                viewModel.showCreateGroupEditor()
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "plus")
                    Text("Create Your First Group")
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
    
    // MARK: - Groups List
    
    private var groupsList: some View {
        List {
                ForEach(filteredAppGroups) { group in
                    AppGroupRowView(
                        group: group,
                        onEdit: { viewModel.showEditGroupEditor(for: group) },
                        onDelete: { viewModel.confirmDeleteGroup(group) }
                    )
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button("Delete", role: .destructive) {
                            viewModel.confirmDeleteGroup(group)
                        }
                        .tint(Color(.systemGray3))
                        .foregroundColor(AppConstants.Colors.text)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(.systemGray3))
                                .padding(4)
                        )

                        Button("Edit") {
                            viewModel.showEditGroupEditor(for: group)
                        }
                        .tint(Color(.systemGray5))
                        .foregroundColor(AppConstants.Colors.text)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(.systemGray5))
                                .padding(4)
                        )
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }
            }
            .listStyle(PlainListStyle())
            .background(AppConstants.Colors.background)
            .scrollContentBackground(.hidden)
    }
    
    
    // MARK: - Create Group Button
    
    private var createGroupButton: some View {
        Button(action: {
            // Debounce rapid taps to prevent multiple sheet presentations
            let now = Date()
            let timeSinceLastTap = now.timeIntervalSince(lastCreateTapTime)
            
            guard timeSinceLastTap > 1.0 else {
                print("🚫 CREATE DEBOUNCE: Ignoring rapid tap (\(timeSinceLastTap)s ago)")
                return
            }
            
            lastCreateTapTime = now
            print("➕ CREATE TAP: Opening group editor")
            viewModel.showCreateGroupEditor()
        }) {
            Image(systemName: "plus")
                .font(.title2)
                .fontWeight(.medium)
        }
        .disabled(viewModel.isLoading)
    }
    
    // MARK: - Delete Confirmation Alert
    
    private var deleteConfirmationAlert: some View {
        Group {
            Button("Cancel", role: .cancel) {
                viewModel.cancelDelete()
            }
            
            Button("Delete", role: .destructive) {
                if let group = viewModel.groupToDelete {
                    Task {
                        await viewModel.deleteAppGroup(group)
                    }
                }
            }
        }
    }
    
    
    // MARK: - Computed Properties
    
    private var filteredAppGroups: [AppGroup] {
        if viewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return viewModel.appGroups.sorted { $0.lastModified > $1.lastModified }
        } else {
            let searchQuery = viewModel.searchText.lowercased()
            return viewModel.appGroups.filter { group in
                group.name.lowercased().contains(searchQuery)
            }.sorted { $0.lastModified > $1.lastModified }
        }
    }
}

// MARK: - App Group Row View

private struct AppGroupRowView: View {
    let group: AppGroup
    let onEdit: () -> Void
    let onDelete: () -> Void
    
    static let relativeDateFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.dateTimeStyle = .named
        formatter.formattingContext = .listItem
        return formatter
    }()
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with name and actions
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(group.name)
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(AppConstants.Colors.text)
                        .lineLimit(1)
                }
                
                Spacer()
            }
            
            // App icons preview
            AppIconsPreview(group: group)
            
            // Stats and details
            HStack(spacing: 24) {
                StatDetail(
                    icon: "app.badge",
                    label: "Apps",
                    value: "\(group.applications.count)"
                )

                StatDetail(
                    icon: "folder.fill",
                    label: "Categories",
                    value: "\(group.categories.count)"
                )

                Spacer()
            }
        }
        .padding()
        .background(AppConstants.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Statistic Card

private struct StatisticCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
                .frame(width: 32, height: 32)
                .background(color.opacity(0.1))
                .clipShape(Circle())
            
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            Spacer(minLength: 0)
        }
        .padding()
        .frame(minHeight: 60)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Stat Detail

private struct StatDetail: View {
    let icon: String
    let label: String
    let value: String
    
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(AppConstants.Colors.textSecondary)

            Text("\(value) \(label)")
                .font(.caption)
                .foregroundColor(AppConstants.Colors.textSecondary)
        }
    }
}

// MARK: - App Icons Preview

private struct AppIconsPreview: View {
    let group: AppGroup
    
    private let maxPreviewIcons = 3
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Show app icons with count indicator
            if !group.applications.isEmpty {
                HStack(spacing: 8) {
                    Spacer()

                    // Show app icons with overflow indicator
                    HStack(spacing: -2) {
                        ForEach(Array(group.applications.prefix(maxPreviewIcons)).enumerated().map { $0 }, id: \.offset) { index, token in
                            Label(token)
                                .labelStyle(.iconOnly)
                                .grayscale(1.0) // Convert to greyscale
                                .frame(width: 20, height: 20)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                                .zIndex(Double(maxPreviewIcons - index))
                                .id("group_app_\(token.hashValue)")
                        }

                        // Show remaining count if more than 3 apps
                        if group.applications.count > maxPreviewIcons {
                            Text("+\(group.applications.count - maxPreviewIcons)")
                                .font(.caption2)
                                .fontWeight(.medium)
                                .foregroundColor(AppConstants.Colors.textSecondary)
                        }
                    }
                }
            }
        }
    }
}

// All app icons are shown only in the editor sheet where they can be properly managed


// MARK: - Preview

#Preview {
    AppGroupListView(viewModel: AppGroupsViewModel(dataService: MockDataPersistenceService()))
}
