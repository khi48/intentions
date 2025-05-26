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
    
    init(
        dataService: DataPersisting,
        screenTimeService: ScreenTimeManaging,
        categoryMappingService: CategoryMappingService,
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
        .alert("Error", isPresented: .constant(viewModel.errorMessage != nil)) {
            Button("OK") {
                viewModel.clearError()
            }
        } message: {
            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
            }
        }
        .task {
            await viewModel.loadData()
        }
        .sheet(item: Binding(
            get: { viewModel.currentSheet },
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
                
                Text("Select which applications you need for this focused session.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            // Main picker button
            HStack {
                Spacer()
                
                Button("Pick Apps") {
                    viewModel.showingFamilyActivityPicker = true
                }
                .buttonStyle(.borderedProminent)
                
                Spacer()
            }
            
            // Selection summary
            if viewModel.selectionCount > 0 {
                familyActivitySelectionSummary
            } else {
                Text("Tap 'Pick Apps' to choose which applications you need for this focused session")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.vertical, 12)
            }
            
            // App Groups (keep existing functionality)
            if !viewModel.availableAppGroups.isEmpty {
                Divider()
                appGroupsSection
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
            Text("App Groups")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
            
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
        }
    }
    
    
    // MARK: - Selected Items Section
    
    private var selectedItemsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Selected Items")
                    .font(.headline)
                
                Spacer()
                
                Button("Clear All") {
                    viewModel.clearSelections()
                }
                .buttonStyle(.borderless)
                .foregroundColor(.red)
            }
            
            Text("\(viewModel.selectionCount) items selected")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.systemBlue).opacity(0.1))
        .cornerRadius(AppConstants.UI.cornerRadius)
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
                
                Text("\(group.applications.count) apps")
                    .font(.caption)
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
        onSessionStart: { _ in },
        onCancel: { }
    )
}
