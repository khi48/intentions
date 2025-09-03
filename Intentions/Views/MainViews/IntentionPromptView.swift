//
//  IntentionPromptView.swift
//  Intentions
//
//  Created by Claude on 13/07/2025.
//

import SwiftUI
@preconcurrency import FamilyControls

/// Main interface for setting intentions - selecting apps and duration
struct IntentionPromptView: View {
    
    @State private var viewModel: IntentionPromptViewModel
    let contentViewModel: ContentViewModel
    
    init(
        dataService: DataPersisting,
        screenTimeService: ScreenTimeManaging,
        categoryMappingService: CategoryMappingService,
        contentViewModel: ContentViewModel,
        onSessionStart: @escaping (IntentionSession) async -> Void,
        onCancel: @escaping () -> Void
    ) {
        let vm = IntentionPromptViewModel(
            dataService: dataService,
            screenTimeService: screenTimeService,
            categoryMappingService: categoryMappingService,
            onSessionStart: onSessionStart,
            onCancel: onCancel
        )
        self._viewModel = State(wrappedValue: vm)
        self.contentViewModel = contentViewModel
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                // Header
                headerSection
                
                // Content
                ScrollView {
                    VStack(spacing: 24) {
                        // Duration Selection
                        durationSection
                        
                        // App Selection
                        appSelectionSection
                        
                        // Selected Items Summary
                        if viewModel.selectionCount > 0 {
                            selectedItemsSection
                        }
                    }
                    .padding(.horizontal)
                }
                
                // Action Buttons
                actionButtonsSection
                    .padding()
            }
            .navigationTitle("Set Your Intention")
            .navigationBarTitleDisplayMode(.large)
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        viewModel.cancel()
                    }
                }
            }
        }
        .alert("Error", isPresented: Binding(
            get: { 
                // COMPLETELY DISABLE IntentionPromptView alerts to prevent presentation conflicts
                false  // Sheet-based error handling only
            },
            set: { _ in viewModel.clearError() }
        )) {
            Button("OK") {
                viewModel.clearError()
            }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .task {
            await viewModel.loadData()
        }
        .onAppear {
            // Refresh app groups when view appears (in case new groups were created)
            print("👁️ INTENTION PROMPT: View appeared, refreshing app groups...")
            Task {
                await viewModel.refreshAppGroups()
            }
        }
        .refreshable {
            // Allow pull-to-refresh
            await viewModel.refreshAppGroups()
        }
        .onChange(of: contentViewModel.appGroupsDidChange) { _, _ in
            // Refresh when app groups change
            print("🔔 INTENTION PROMPT: App groups changed notification received")
            Task {
                await viewModel.refreshAppGroups()
            }
        }
        // TEMPORARILY DISABLED: IntentionPrompt internal sheets to test presentation conflict
        .sheet(item: Binding(
            get: { nil }, // Disable all internal sheets
            set: { viewModel.currentSheet = $0 }
        )) { sheetType in
            switch sheetType {
            case .durationPicker:
                CustomDurationPicker(selectedDuration: Binding(
                    get: { viewModel.selectedDuration },
                    set: { viewModel.selectedDuration = $0 }
                ))
            case .appSelection:
                AppSelectionSheet(viewModel: viewModel)
            }
        }
        .background(
            IsolatedFamilyActivityPicker(
                isPresented: $viewModel.showingFamilyActivityPicker,
                selection: $viewModel.familyActivitySelection
            )
        )
    }
    
    // MARK: - Header Section
    
    private var headerSection: some View {
        VStack(spacing: 12) {
            Text("🚫 All apps are blocked by default")
                .font(.headline)
                .foregroundColor(.primary)
                .multilineTextAlignment(.center)
            
            Text("Select which apps you need for this focused session")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.1))
        .cornerRadius(12)
        .padding(.horizontal)
    }
    
    // MARK: - Duration Section
    
    private var durationSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Session Duration")
                    .font(.headline)
                
                Spacer()
                
                Text(viewModel.formattedDuration)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
            }
            
            // Preset Duration Buttons
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 12) {
                ForEach(viewModel.presetDurations, id: \.self) { duration in
                    DurationPresetButton(
                        duration: duration,
                        isSelected: viewModel.isPresetSelected(duration),
                        action: {
                            viewModel.selectPresetDuration(duration)
                        }
                    )
                }
            }
            
            // Custom Duration Input
            HStack {
                Text("Custom")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Button("Set Custom") {
                    viewModel.currentSheet = .durationPicker
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(AppConstants.UI.cornerRadius)
    }
    
    // MARK: - App Selection Section
    
    private var appSelectionSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            VStack(alignment: .leading, spacing: 8) {
                Text("Choose Apps to Allow")
                    .font(.headline)
                
                Text("Select apps using groups (quick) or individual selection (precise).")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            // Selection methods
            VStack(spacing: 16) {
                // App Groups (if available)
                if !viewModel.availableAppGroups.isEmpty {
                    appGroupsSection
                    
                    HStack {
                        Rectangle()
                            .frame(height: 1)
                            .foregroundColor(.secondary.opacity(0.3))
                        
                        Text("or")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 8)
                        
                        Rectangle()
                            .frame(height: 1)
                            .foregroundColor(.secondary.opacity(0.3))
                    }
                } else {
                    // Show placeholder when no groups exist
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Quick Select: App Groups")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                        
                        VStack(spacing: 8) {
                            Text("No app groups created yet")
                                .font(.body)
                                .foregroundColor(.secondary)
                            
                            Text("Create app groups in Settings to enable quick selection")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(8)
                    }
                    
                    HStack {
                        Rectangle()
                            .frame(height: 1)
                            .foregroundColor(.secondary.opacity(0.3))
                        
                        Text("or")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 8)
                        
                        Rectangle()
                            .frame(height: 1)
                            .foregroundColor(.secondary.opacity(0.3))
                    }
                }
                
                // Individual app picker
                VStack(alignment: .leading, spacing: 8) {
                    Text("Individual App Selection")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                    
                    Button("Pick Individual Apps") {
                        viewModel.showingFamilyActivityPicker = true
                    }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
                }
            }
            
            // Selection summary
            if viewModel.selectionCount > 0 {
                familyActivitySelectionSummary
            } else {
                Text("Use app groups for quick selection or pick individual apps for precise control")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.vertical, 12)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(AppConstants.UI.cornerRadius)
        .onChange(of: viewModel.familyActivitySelection) { _, newSelection in
            // Selection updated - UI will automatically refresh
        }
    }
    
    
    private var familyActivitySelectionSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Apps Allowed During Session")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Button("Modify") {
                    viewModel.showingFamilyActivityPicker = true
                }
                .font(.caption)
                .buttonStyle(.borderless)
            }
            
            Text("\(viewModel.familyActivitySelection.applications.count) apps, \(viewModel.familyActivitySelection.categories.count) categories")
                .font(.headline)
                .foregroundColor(.primary)
            
            Text("All other apps will be blocked using intelligent category-based blocking")
                .font(.caption)
                .foregroundColor(.orange)
        }
        .padding(12)
        .background(Color.green.opacity(0.1))
        .cornerRadius(8)
    }
    
    private var appGroupsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Quick Select: App Groups")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                if !viewModel.selectedAppGroups.isEmpty {
                    Text("\(viewModel.selectedAppGroups.count) selected")
                        .font(.caption)
                        .foregroundColor(.accentColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.1))
                        .cornerRadius(4)
                }
            }
            
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 12) {
                ForEach(viewModel.availableAppGroups) { group in
                    AppGroupSelectionCard(
                        group: group,
                        isSelected: viewModel.isAppGroupSelected(group.id),
                        action: {
                            viewModel.toggleAppGroup(group.id)
                        }
                    )
                }
            }
            
            if !viewModel.availableAppGroups.isEmpty {
                Text("Selecting an app group will include all its apps and categories in your session")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.leading)
            }
        }
    }
    
    
    // MARK: - Selected Items Section
    
    private var selectedItemsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Session Summary")
                    .font(.headline)
                
                Spacer()
                
                Button("Clear All") {
                    viewModel.clearSelections()
                }
                .buttonStyle(.borderless)
                .foregroundColor(.red)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                if !viewModel.selectedAppGroups.isEmpty {
                    selectedAppGroupsSummary
                }
                
                if !viewModel.familyActivitySelection.applications.isEmpty || !viewModel.familyActivitySelection.categories.isEmpty {
                    individualSelectionSummary
                }
                
                if !viewModel.selectedApplications.isEmpty {
                    manualAppsSummary
                }
            }
        }
        .padding()
        .background(Color(.systemBlue).opacity(0.1))
        .cornerRadius(AppConstants.UI.cornerRadius)
    }
    
    private var selectedAppGroupsSummary: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "square.stack.3d.up.fill")
                    .foregroundColor(.blue)
                Text("App Groups")
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            
            ForEach(Array(viewModel.selectedAppGroups), id: \.self) { groupId in
                if let group = viewModel.availableAppGroups.first(where: { $0.id == groupId }) {
                    Text("• \(group.name) (\(group.applications.count) apps, \(group.categories.count) categories)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
    
    private var individualSelectionSummary: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "hand.tap")
                    .foregroundColor(.green)
                Text("Individual Selection")
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            
            Text("• \(viewModel.familyActivitySelection.applications.count) apps, \(viewModel.familyActivitySelection.categories.count) categories")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    private var manualAppsSummary: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "app.badge")
                    .foregroundColor(.orange)
                Text("Manual Selection")
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            
            Text("• \(viewModel.selectedApplications.count) apps")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    // MARK: - Action Buttons
    
    private var actionButtonsSection: some View {
        VStack(spacing: 12) {
            Button(action: {
                Task {
                    // Small delay to ensure UI binding updates are processed
                    try? await Task.sleep(for: .milliseconds(100))
                    await viewModel.startSession()
                }
            }) {
                HStack {
                    if viewModel.isLoading {
                        ProgressView()
                            .scaleEffect(0.8)
                    }
                    
                    Text("Start Session")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 50)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!viewModel.canStartSession)
            
            Button("Cancel") {
                viewModel.cancel()
            }
            .buttonStyle(.bordered)
        }
    }
}

// MARK: - Supporting Views

struct DurationPresetButton: View {
    let duration: TimeInterval
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Text(formattedDuration)
                    .font(.title3)
                    .fontWeight(.medium)
                
                Text(durationLabel)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 60)
            .background(isSelected ? Color.accentColor : Color(.systemGray5))
            .foregroundColor(isSelected ? .white : .primary)
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
    
    private var formattedDuration: String {
        if duration < 3600 {
            return "\(Int(duration / 60))m"
        } else {
            return "\(Int(duration / 3600))h"
        }
    }
    
    private var durationLabel: String {
        if duration < 3600 {
            let minutes = Int(duration / 60)
            return minutes == 1 ? "minute" : "minutes"
        } else {
            let hours = Int(duration / 3600)
            return hours == 1 ? "hour" : "hours"
        }
    }
}


struct AppGroupSelectionCard: View {
    let group: AppGroup
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(group.name)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    
                    Spacer()
                    
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.accentColor)
                    }
                }
                
                HStack(spacing: 8) {
                    if !group.applications.isEmpty {
                        HStack(spacing: 2) {
                            Image(systemName: "app.badge")
                                .font(.caption2)
                            Text("\(group.applications.count)")
                                .font(.caption)
                        }
                    }
                    
                    if !group.categories.isEmpty {
                        HStack(spacing: 2) {
                            Image(systemName: "folder.badge")
                                .font(.caption2)
                            Text("\(group.categories.count)")
                                .font(.caption)
                        }
                    }
                }
                .foregroundColor(.secondary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? Color.accentColor.opacity(0.1) : Color(.systemGray5))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}

struct AppSelectionCard: View {
    let app: DiscoveredApp
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(app.displayName)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    
                    Spacer()
                    
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.accentColor)
                    }
                }
                
                if let category = app.category {
                    Text(category)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? Color.accentColor.opacity(0.1) : Color(.systemGray5))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Sheet Views

struct CustomDurationPicker: View {
    @Binding var selectedDuration: TimeInterval
    @Environment(\.dismiss) private var dismiss
    
    @State private var hours: Int = 0
    @State private var minutes: Int = 30
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text("Set Custom Duration")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                HStack(spacing: 20) {
                    VStack {
                        Text("Hours")
                            .font(.headline)
                        
                        Picker("Hours", selection: $hours) {
                            ForEach(0...8, id: \.self) { hour in
                                Text("\(hour)").tag(hour)
                            }
                        }
                        .pickerStyle(.wheel)
                        .frame(height: 150)
                    }
                    
                    VStack {
                        Text("Minutes")
                            .font(.headline)
                        
                        Picker("Minutes", selection: $minutes) {
                            ForEach(Array(stride(from: 0, through: 55, by: 5)), id: \.self) { minute in
                                Text("\(minute)").tag(minute)
                            }
                        }
                        .pickerStyle(.wheel)
                        .frame(height: 150)
                    }
                }
                
                Spacer()
            }
            .padding()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Set") {
                        let totalDuration = TimeInterval((hours * 60 + minutes) * 60)
                        if totalDuration >= AppConstants.Session.minimumDuration &&
                           totalDuration <= AppConstants.Session.maximumDuration {
                            selectedDuration = totalDuration
                        }
                        dismiss()
                    }
                    .disabled((hours * 60 + minutes) < 5 || (hours * 60 + minutes) > 480)
                }
            }
        }
        .onAppear {
            hours = Int(selectedDuration) / 3600
            minutes = (Int(selectedDuration) % 3600) / 60
        }
    }
}

struct AppSelectionSheet: View {
    @Bindable var viewModel: IntentionPromptViewModel
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VStack {
                // Search Bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    
                    TextField("Search apps...", text: $viewModel.searchText)
                        .textFieldStyle(.roundedBorder)
                }
                .padding()
                
                // Options
                HStack {
                    Toggle("Show System Apps", isOn: $viewModel.showSystemApps)
                    Spacer()
                }
                .padding(.horizontal)
                
                // App List
                List {
                    ForEach(viewModel.searchResults) { app in
                        AppSelectionRow(
                            app: app,
                            isSelected: viewModel.isApplicationSelected(app.applicationToken),
                            action: {
                                viewModel.toggleApplication(app.applicationToken)
                            }
                        )
                    }
                }
            }
            .navigationTitle("Select Apps")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct AppSelectionRow: View {
    let app: DiscoveredApp
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(app.displayName)
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Text(app.bundleIdentifier)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    if let category = app.category {
                        Text(category)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Color(.systemGray5))
                            .cornerRadius(4)
                    }
                }
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.accentColor)
                        .font(.title2)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// Back to simple Apple implementation - debugging the dismissal issue

#Preview {
    IntentionPromptView(
        dataService: MockDataPersistenceService(),
        screenTimeService: MockScreenTimeService(),
        categoryMappingService: CategoryMappingService(),
        contentViewModel: try! ContentViewModel(dataService: MockDataPersistenceService()),
        onSessionStart: { _ in },
        onCancel: { }
    )
}
