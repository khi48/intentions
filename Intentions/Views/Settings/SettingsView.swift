//
//  SettingsView.swift
//  Intentions
//
//  Created by Claude on 12/07/2025.
//

import SwiftUI
@preconcurrency import FamilyControls
import ManagedSettings

// MARK: - Supporting Views

struct ScheduleDetailsRow: View {
    let title: String
    let value: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .foregroundStyle(.primary)
                
                Spacer()
                
                Text(value)
                    .foregroundStyle(.secondary)
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

struct AppGroupRow: View {
    let group: AppGroup
    let onEdit: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(group.name)
                    .font(.headline)
                
                Text("\(group.applications.count) apps")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            Menu {
                Button("Edit", systemImage: "pencil") {
                    onEdit()
                }
                
                Button("Delete", systemImage: "trash", role: .destructive) {
                    onDelete()
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct StatisticRow: View {
    let title: String
    let value: String
    let icon: String
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(.blue)
                .frame(width: 20)
            
            Text(title)
            
            Spacer()
            
            Text(value)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
        }
    }
}

struct SettingsRow: View {
    let title: String
    let subtitle: String
    let icon: String
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(.blue)
                .frame(width: 20)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
        }
    }
}

// MARK: - Main Settings View

/// Main settings view with app group management and schedule settings
struct SettingsView: View {
    @State private var viewModel: SettingsViewModel
    private let onScheduleSettingsChanged: ((ScheduleSettings) async -> Void)?
    
    init(
        dataService: DataPersisting? = nil,
        onScheduleSettingsChanged: ((ScheduleSettings) async -> Void)? = nil
    ) {
        let service = dataService ?? MockDataPersistenceService()
        self._viewModel = State(wrappedValue: SettingsViewModel(dataService: service))
        self.onScheduleSettingsChanged = onScheduleSettingsChanged
    }
    
    var body: some View {
        NavigationStack {
            if viewModel.isLoading {
                ProgressView("Loading Settings...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    // Schedule Settings Section
                    scheduleSection
                    
                    // App Groups Section
                    appGroupsSection
                    
                    // Statistics Section
                    statisticsSection
                    
                    // General Settings Section
                    generalSection
                    
                    // Debug Section (development only)
                    debugSection
                    
                    // About Section
                    aboutSection
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.large)
        .alert("Error", isPresented: .constant(viewModel.errorMessage != nil)) {
            Button("OK") {
                viewModel.clearError()
            }
        } message: {
            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
            }
        }
        .alert("Delete App Group", isPresented: $viewModel.showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) {
                viewModel.cancelDelete()
            }
            Button("Delete", role: .destructive) {
                Task {
                    await viewModel.executeDelete()
                }
            }
        } message: {
            if let group = viewModel.groupToDelete {
                Text("Are you sure you want to delete '\(group.name)'? This action cannot be undone.")
            }
        }
        .sheet(isPresented: $viewModel.showingScheduleEditor) {
            ScheduleSettingsView(
                settings: viewModel.scheduleSettings,
                onSave: { settings in
                    Task {
                        await viewModel.updateScheduleSettings(settings)
                        // Notify ContentViewModel of schedule change
                        await onScheduleSettingsChanged?(settings)
                    }
                    viewModel.hideScheduleEditor()
                },
                onCancel: {
                    viewModel.hideScheduleEditor()
                }
            )
        }
        .sheet(isPresented: $viewModel.showingAppGroupEditor) {
            AppGroupEditorView(
                onSave: { name, apps in
                    Task {
                        await viewModel.createAppGroup(name: name, applications: apps)
                    }
                    viewModel.hideAppGroupEditor()
                },
                onCancel: {
                    viewModel.hideAppGroupEditor()
                }
            )
        }
        .task {
            await viewModel.loadData()
        }
    }
    
    // MARK: - Schedule Section
    
    private var scheduleSection: some View {
        Section {
            // Schedule Toggle
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Active Schedule")
                        .font(.headline)
                    
                    Text("Control when Intentions is active")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Toggle("", isOn: Binding(
                        get: { viewModel.scheduleSettings.isEnabled },
                        set: { _ in
                            Task {
                                await viewModel.toggleScheduleEnabled()
                                // Notify ContentViewModel of schedule change
                                await onScheduleSettingsChanged?(viewModel.scheduleSettings)
                            }
                        }
                    ))
                    
                    Text(viewModel.scheduleStatusText)
                        .font(.caption)
                        .foregroundStyle(viewModel.scheduleStatusColor)
                }
            }
            
            // Schedule Details (when enabled)
            if viewModel.scheduleSettings.isEnabled {
                ScheduleDetailsRow(
                    title: "Active Hours",
                    value: viewModel.formattedActiveHours,
                    action: { viewModel.showScheduleEditor() }
                )
                
                ScheduleDetailsRow(
                    title: "Active Days",
                    value: viewModel.activeDaysText,
                    action: { viewModel.showScheduleEditor() }
                )
            }
        } header: {
            Text("Schedule Settings")
        } footer: {
            if viewModel.scheduleSettings.isEnabled {
                Text("Intentions will only be active during the specified times and days. Outside these hours, all apps remain accessible.")
            } else {
                Text("Schedule is disabled. Intentions is active 24/7.")
            }
        }
    }
    
    // MARK: - App Groups Section
    
    private var appGroupsSection: some View {
        Section {
            // Create New Group Button
            Button(action: { viewModel.showAppGroupEditor() }) {
                HStack {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(.blue)
                    
                    Text("Create App Group")
                        .foregroundStyle(.blue)
                    
                    Spacer()
                }
            }
            
            // Existing Groups
            ForEach(viewModel.appGroups) { group in
                AppGroupRow(
                    group: group,
                    onEdit: { 
                        // TODO: Implement edit functionality
                    },
                    onDelete: {
                        viewModel.confirmDeleteGroup(group)
                    }
                )
            }
        } header: {
            HStack {
                Text("App Groups")
                Spacer()
                Text("\(viewModel.appGroups.count)")
                    .foregroundStyle(.secondary)
            }
        } footer: {
            Text("Create groups of apps for quick session setup. Groups can be selected together when setting intentions.")
        }
    }
    
    // MARK: - Statistics Section
    
    private var statisticsSection: some View {
        Section("Usage Statistics") {
            StatisticRow(
                title: "App Groups",
                value: "\(viewModel.totalAppGroups)",
                icon: "square.stack.3d.up.fill"
            )
            
            StatisticRow(
                title: "Managed Apps",
                value: "\(viewModel.totalManagedApps)",
                icon: "apps.iphone"
            )
            
            StatisticRow(
                title: "Today's Sessions",
                value: "\(viewModel.todaySessionCount)",
                icon: "calendar"
            )
            
            StatisticRow(
                title: "This Week",
                value: "\(viewModel.weeklySessionCount)",
                icon: "chart.line.uptrend.xyaxis"
            )
        }
    }
    
    // MARK: - General Section
    
    private var generalSection: some View {
        Section("General") {
            NavigationLink {
                NotificationSettingsView()
            } label: {
                SettingsRow(
                    title: "Notifications",
                    subtitle: "Session warnings and reminders",
                    icon: "bell.fill"
                )
            }
            
            NavigationLink {
                PrivacySettingsView()
            } label: {
                SettingsRow(
                    title: "Privacy",
                    subtitle: "Data collection and sharing",
                    icon: "hand.raised.fill"
                )
            }
            
            NavigationLink {
                DataManagementView()
            } label: {
                SettingsRow(
                    title: "Data Management",
                    subtitle: "Export, import, and reset",
                    icon: "externaldrive.fill"
                )
            }
        }
    }
    
    // MARK: - About Section
    
    private var debugSection: some View {
        Section {
            NavigationLink {
                CategoryMappingSetupView { mappingService in
                    // Handle completion in debug context
                    print("Debug: Category mapping setup completed")
                }
            } label: {
                SettingsRow(
                    title: "Category Mapping Setup",
                    subtitle: "Map apps to categories for smart blocking",
                    icon: "folder.badge.gearshape"
                )
            }
            
            NavigationLink {
                IncludeEntireCategoryTestView()
            } label: {
                SettingsRow(
                    title: "includeEntireCategory MVP Test",
                    subtitle: "Simple test for category expansion",
                    icon: "testtube.2"
                )
            }
            
            NavigationLink {
                AllAppsDiscoveryTestView()
            } label: {
                SettingsRow(
                    title: "All Apps Discovery Test",
                    subtitle: "Test capturing all app tokens",
                    icon: "magnifyingglass.circle.fill"
                )
            }
        } header: {
            Text("Debug & Testing")
        }
    }
    
    private var aboutSection: some View {
        Section {
            NavigationLink {
                AboutView()
            } label: {
                SettingsRow(
                    title: "About Intentions",
                    subtitle: "Version, support, and feedback",
                    icon: "info.circle.fill"
                )
            }
            
            Link(destination: URL(string: "https://github.com/intentions-app/intentions")!) {
                SettingsRow(
                    title: "Open Source",
                    subtitle: "View on GitHub",
                    icon: "chevron.left.forwardslash.chevron.right"
                )
            }
        } footer: {
            Text("Intentions is designed to promote mindful phone usage through intentional app access.")
                .multilineTextAlignment(.center)
                .padding(.top)
        }
    }
}

// MARK: - Placeholder Views for Navigation

struct ScheduleSettingsView: View {
    let settings: ScheduleSettings
    let onSave: (ScheduleSettings) -> Void
    let onCancel: () -> Void
    
    var body: some View {
        NavigationView {
            VStack {
                Text("Schedule Settings Editor")
                    .font(.title2)
                Text("Coming Soon")
                    .foregroundStyle(.secondary)
            }
            .navigationTitle("Schedule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { onCancel() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") { onSave(settings) }
                }
            }
        }
    }
}

struct AppGroupEditorView: View {
    let onSave: (String, Set<ApplicationToken>) -> Void
    let onCancel: () -> Void
    
    var body: some View {
        NavigationView {
            VStack {
                Text("App Group Editor")
                    .font(.title2)
                Text("Coming Soon")
                    .foregroundStyle(.secondary)
            }
            .navigationTitle("New Group")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { onCancel() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") { 
                        onSave("New Group", Set<ApplicationToken>()) 
                    }
                }
            }
        }
    }
}

struct NotificationSettingsView: View {
    var body: some View {
        Text("Notification Settings")
            .navigationTitle("Notifications")
    }
}

struct PrivacySettingsView: View {
    var body: some View {
        Text("Privacy Settings")
            .navigationTitle("Privacy")
    }
}

struct DataManagementView: View {
    var body: some View {
        Text("Data Management")
            .navigationTitle("Data")
    }
}

struct AboutView: View {
    var body: some View {
        Text("About Intentions")
            .navigationTitle("About")
    }
}

// MARK: - All Apps Discovery Test View

/// Simple test view to discover all apps and capture tokens with debug output
struct AllAppsDiscoveryTestView: View {
    
    @State private var showingPicker = false
    @State private var allAppsSelection = FamilyActivitySelection(includeEntireCategory: true)
    @State private var discoveryComplete = false
    
    var body: some View {
        VStack(spacing: 20) {
            
            // Header
            Text("All Apps Discovery Test")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Text("This will discover ALL apps and categories on your device")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            Spacer()
            
            // Discovery Status
            if !discoveryComplete {
                VStack(spacing: 16) {
                    Image(systemName: "magnifyingglass.circle")
                        .font(.system(size: 60))
                        .foregroundColor(.blue)
                    
                    Text("Ready to Discover")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Text("Tap the button below and SELECT ALL apps and categories in the picker")
                        .font(.body)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    
                    Button("Start Discovery") {
                        print("🔍 DISCOVERY TEST: Opening FamilyActivityPicker")
                        print("🔍 INSTRUCTION: Please select ALL apps and ALL categories")
                        showingPicker = true
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
            } else {
                // Discovery Results
                VStack(spacing: 16) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.green)
                    
                    Text("Discovery Complete!")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    discoveryResultsView
                    
                    Button("Discover Again") {
                        resetDiscovery()
                    }
                    .buttonStyle(.bordered)
                }
            }
            
            Spacer()
        }
        .padding()
        .navigationTitle("Token Discovery")
        .navigationBarTitleDisplayMode(.inline)
        .familyActivityPicker(isPresented: $showingPicker, selection: $allAppsSelection)
        .onChange(of: allAppsSelection) { oldSelection, newSelection in
            handleSelectionChange(oldSelection: oldSelection, newSelection: newSelection)
        }
    }
    
    private var discoveryResultsView: some View {
        VStack(alignment: .leading, spacing: 12) {
            
            // Apps Summary
            HStack {
                Image(systemName: "app.badge")
                    .foregroundColor(.blue)
                Text("Apps: \(allAppsSelection.applications.count)")
                    .font(.headline)
                Spacer()
            }
            
            // Categories Summary  
            HStack {
                Image(systemName: "folder.badge")
                    .foregroundColor(.orange)
                Text("Categories: \(allAppsSelection.categories.count)")
                    .font(.headline)
                Spacer()
            }
            
            // Web Domains Summary
            HStack {
                Image(systemName: "globe.badge")
                    .foregroundColor(.green)
                Text("Web Domains: \(allAppsSelection.webDomains.count)")
                    .font(.headline)
                Spacer()
            }
            
            // Token Validity
            let validAppTokens = allAppsSelection.applications.compactMap { $0.token }.count
            let validCategoryTokens = allAppsSelection.categories.compactMap { $0.token }.count
            
            Divider()
            
            HStack {
                Image(systemName: "key.fill")
                    .foregroundColor(.purple)
                Text("Valid App Tokens: \(validAppTokens)")
                    .font(.subheadline)
                Spacer()
            }
            
            HStack {
                Image(systemName: "key.fill")
                    .foregroundColor(.purple)
                Text("Valid Category Tokens: \(validCategoryTokens)")
                    .font(.subheadline)
                Spacer()
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    private func handleSelectionChange(oldSelection: FamilyActivitySelection, newSelection: FamilyActivitySelection) {
        print("\n" + String(repeating: "=", count: 60))
        print("🔍 DISCOVERY TEST: Selection Changed")
        print(String(repeating: "=", count: 60))
        
        // Basic counts
        print("📊 BASIC COUNTS:")
        print("   Applications: \(newSelection.applications.count)")
        print("   Categories: \(newSelection.categories.count)")
        print("   Web Domains: \(newSelection.webDomains.count)")
        print("   includeEntireCategory: \(newSelection.includeEntireCategory)")
        
        // Token analysis
        let appTokens = newSelection.applications.compactMap { $0.token }
        let categoryTokens = newSelection.categories.compactMap { $0.token }
        
        print("\n🔑 TOKEN ANALYSIS:")
        print("   Valid App Tokens: \(appTokens.count)/\(newSelection.applications.count)")
        print("   Valid Category Tokens: \(categoryTokens.count)/\(newSelection.categories.count)")
        print("   🎯 With includeEntireCategory=true, selecting categories should populate individual apps too!")
        
        // Detailed app analysis
        print("\n📱 DETAILED APP ANALYSIS:")
        for (index, app) in newSelection.applications.enumerated().prefix(10) {
            let hasToken = app.token != nil
            print("   App \(index + 1): \(hasToken ? "✅ HAS TOKEN" : "❌ NO TOKEN")")
            
            print("     - App: \(app)")
            if let token = app.token {
                print("     - Token: \(token)")
            }
        }
        
        if newSelection.applications.count > 10 {
            print("   ... and \(newSelection.applications.count - 10) more apps")
        }
        
        // Detailed category analysis
        print("\n🏷️ DETAILED CATEGORY ANALYSIS:")
        for (index, category) in newSelection.categories.enumerated() {
            let hasToken = category.token != nil
            print("   Category \(index + 1): \(hasToken ? "✅ HAS TOKEN" : "❌ NO TOKEN")")
            print("     - Category: \(category)")
            if let token = category.token {
                print("     - Token: \(token)")
            }
        }
        
        // Web domains analysis
        if !newSelection.webDomains.isEmpty {
            print("\n🌐 WEB DOMAINS ANALYSIS:")
            for (index, domain) in newSelection.webDomains.enumerated().prefix(5) {
                print("   Domain \(index + 1): \(domain)")
            }
            if newSelection.webDomains.count > 5 {
                print("   ... and \(newSelection.webDomains.count - 5) more domains")
            }
        }
        
        // Summary
        print("\n📝 DISCOVERY SUMMARY:")
        if appTokens.count > 0 || categoryTokens.count > 0 {
            print("   ✅ Discovery SUCCESSFUL!")
            print("   📊 Total usable tokens: \(appTokens.count + categoryTokens.count)")
            discoveryComplete = true
        } else {
            print("   ⚠️ No valid tokens found - user may not have selected anything")
        }
        
        // Storage simulation
        print("\n💾 STORAGE SIMULATION:")
        do {
            let encoded = try JSONEncoder().encode(newSelection)
            print("   ✅ JSON encoding successful: \(encoded.count) bytes")
            
            let decoded = try JSONDecoder().decode(FamilyActivitySelection.self, from: encoded)
            let decodedAppTokens = decoded.applications.compactMap { $0.token }.count
            let decodedCategoryTokens = decoded.categories.compactMap { $0.token }.count
            
            print("   📊 After JSON round-trip:")
            print("     - App tokens: \(decodedAppTokens) (original: \(appTokens.count))")
            print("     - Category tokens: \(decodedCategoryTokens) (original: \(categoryTokens.count))")
            
            if decodedAppTokens == appTokens.count && decodedCategoryTokens == categoryTokens.count {
                print("   ✅ Token persistence looks good!")
            } else {
                print("   ⚠️ Token persistence may have issues")
            }
            
        } catch {
            print("   ❌ JSON encoding failed: \(error)")
        }
        
        print(String(repeating: "=", count: 60) + "\n")
    }
    
    private func resetDiscovery() {
        print("🔄 DISCOVERY TEST: Resetting for new discovery")
        allAppsSelection = FamilyActivitySelection(includeEntireCategory: true)
        discoveryComplete = false
    }
}

// MARK: - Include Entire Category MVP Test

/// Minimal test to verify includeEntireCategory: true behavior
struct IncludeEntireCategoryTestView: View {
    
    @State private var showingPicker = false
    
    // Test with includeEntireCategory: true
    @State private var selectionWithCategories = FamilyActivitySelection(includeEntireCategory: true)
    
    // Test with includeEntireCategory: false (default)
    @State private var selectionWithoutCategories = FamilyActivitySelection(includeEntireCategory: false)
    
    @State private var testMode: TestMode = .withCategories
    
    enum TestMode: String, CaseIterable {
        case withCategories = "includeEntireCategory: true"
        case withoutCategories = "includeEntireCategory: false"
    }
    
    var currentSelection: FamilyActivitySelection {
        switch testMode {
        case .withCategories:
            return selectionWithCategories
        case .withoutCategories:
            return selectionWithoutCategories
        }
    }
    
    var body: some View {
        VStack(spacing: 20) {
            
            // Header
            Text("includeEntireCategory Test")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            // Test Mode Selector
            Picker("Test Mode", selection: $testMode) {
                ForEach(TestMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .padding()
            
            // Instructions
            VStack(spacing: 8) {
                Text("Select a CATEGORY (not individual apps)")
                    .font(.headline)
                    .foregroundColor(.orange)
                
                Text("We want to see if selecting a category populates individual apps when includeEntireCategory: true")
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color.orange.opacity(0.1))
            .cornerRadius(8)
            
            // Open Picker Button
            Button("Open Family Activity Picker") {
                print("\n🧪 TESTING: \(testMode.rawValue)")
                showingPicker = true
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            
            // Results
            if currentSelection.applications.count > 0 || currentSelection.categories.count > 0 {
                resultsView
            }
            
            Spacer()
        }
        .padding()
        .navigationTitle("MVP Test")
        .navigationBarTitleDisplayMode(.inline)
        .familyActivityPicker(
            isPresented: $showingPicker, 
            selection: testMode == .withCategories ? $selectionWithCategories : $selectionWithoutCategories
        )
        .onChange(of: selectionWithCategories) { _, newSelection in
            if testMode == .withCategories {
                handleSelectionChange(newSelection, mode: .withCategories)
            }
        }
        .onChange(of: selectionWithoutCategories) { _, newSelection in
            if testMode == .withoutCategories {
                handleSelectionChange(newSelection, mode: .withoutCategories)
            }
        }
    }
    
    private var resultsView: some View {
        VStack(alignment: .leading, spacing: 12) {
            
            Text("Results for: \(testMode.rawValue)")
                .font(.headline)
                .foregroundColor(.primary)
            
            Divider()
            
            // Basic counts
            HStack {
                Image(systemName: "app.badge")
                    .foregroundColor(.blue)
                Text("Individual Apps: \(currentSelection.applications.count)")
                Spacer()
            }
            
            HStack {
                Image(systemName: "folder.badge")
                    .foregroundColor(.orange)
                Text("Categories: \(currentSelection.categories.count)")
                Spacer()
            }
            
            // Token validity
            let validAppTokens = currentSelection.applications.compactMap { $0.token }.count
            let validCategoryTokens = currentSelection.categories.compactMap { $0.token }.count
            
            Divider()
            
            HStack {
                Image(systemName: "key.fill")
                    .foregroundColor(.purple)
                Text("Valid App Tokens: \(validAppTokens)")
                Spacer()
            }
            
            HStack {
                Image(systemName: "key.fill")
                    .foregroundColor(.purple)
                Text("Valid Category Tokens: \(validCategoryTokens)")
                Spacer()
            }
            
            // Expected behavior explanation
            Divider()
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Expected Behavior:")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                
                if testMode == .withCategories {
                    Text("✅ Selecting 1 category should give you BOTH:")
                        .font(.caption)
                        .foregroundColor(.green)
                    Text("  • 1 category token")
                        .font(.caption)
                        .foregroundColor(.green)
                    Text("  • Multiple individual app tokens from that category")
                        .font(.caption)
                        .foregroundColor(.green)
                } else {
                    Text("⚠️ Selecting 1 category should give you ONLY:")
                        .font(.caption)
                        .foregroundColor(.orange)
                    Text("  • 1 category token")
                        .font(.caption)
                        .foregroundColor(.orange)
                    Text("  • No individual app tokens")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
            
            // Clear button
            Button("Clear Selection") {
                switch testMode {
                case .withCategories:
                    selectionWithCategories = FamilyActivitySelection(includeEntireCategory: true)
                case .withoutCategories:
                    selectionWithoutCategories = FamilyActivitySelection(includeEntireCategory: false)
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    private func handleSelectionChange(_ selection: FamilyActivitySelection, mode: TestMode) {
        print("\n" + String(repeating: "=", count: 50))
        print("🧪 MVP TEST RESULTS: \(mode.rawValue)")
        print(String(repeating: "=", count: 50))
        
        print("📊 BASIC COUNTS:")
        print("   Applications: \(selection.applications.count)")
        print("   Categories: \(selection.categories.count)")
        print("   Web Domains: \(selection.webDomains.count)")
        print("   includeEntireCategory: \(selection.includeEntireCategory)")
        
        let appTokens = selection.applications.compactMap { $0.token }
        let categoryTokens = selection.categories.compactMap { $0.token }
        
        print("\n🔑 TOKEN VALIDATION:")
        print("   Valid App Tokens: \(appTokens.count)/\(selection.applications.count)")
        print("   Valid Category Tokens: \(categoryTokens.count)/\(selection.categories.count)")
        
        print("\n🎯 TEST ANALYSIS:")
        if mode == .withCategories {
            if selection.categories.count > 0 && selection.applications.count > 0 {
                print("   ✅ SUCCESS: includeEntireCategory=true gave us BOTH categories AND individual apps!")
                print("   📱 This means selecting categories populated individual app tokens")
            } else if selection.categories.count > 0 && selection.applications.count == 0 {
                print("   ❌ UNEXPECTED: includeEntireCategory=true gave us categories but NO individual apps")
                print("   🤔 This suggests the feature might not work as expected")
            } else if selection.applications.count > 0 && selection.categories.count == 0 {
                print("   ✅ User selected individual apps (not categories) - this is fine")
            } else {
                print("   ⚠️ No selection made yet")
            }
        } else {
            if selection.categories.count > 0 && selection.applications.count == 0 {
                print("   ✅ EXPECTED: includeEntireCategory=false gave us only categories")
            } else if selection.categories.count > 0 && selection.applications.count > 0 {
                print("   🤔 UNEXPECTED: includeEntireCategory=false gave us categories AND individual apps")
            } else if selection.applications.count > 0 {
                print("   ✅ User selected individual apps - this is normal")
            }
        }
        
        print(String(repeating: "=", count: 50) + "\n")
    }
}

#Preview {
    SettingsView()
}

