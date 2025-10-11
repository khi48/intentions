//
//  IncludeEntireCategoryTestView.swift
//  Intentions
//
//  MVP test for includeEntireCategory functionality
//

import SwiftUI
@preconcurrency import FamilyControls

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
                    .foregroundColor(AppConstants.Colors.textSecondary)
                
                Text("We want to see if selecting a category populates individual apps when includeEntireCategory: true")
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(AppConstants.Colors.surface)
            .cornerRadius(8)
            
            // Open Picker Button
            Button("Open Family Activity Picker") {
                print("\n🧪 TESTING: \(testMode.rawValue)")
                showingPicker = true
            }
            .buttonStyle(.bordered)
            .foregroundColor(AppConstants.Colors.text)
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
                    .foregroundColor(AppConstants.Colors.textSecondary)
                Text("Categories: \(currentSelection.categories.count)")
                Spacer()
            }
            
            HStack {
                Image(systemName: "globe.badge")
                    .foregroundColor(AppConstants.Colors.text)
                Text("Web Domains: \(currentSelection.webDomains.count)")
                Spacer()
            }
            
            // Token validity
            let validAppTokens = currentSelection.applications.compactMap { $0.token }.count
            let validCategoryTokens = currentSelection.categories.compactMap { $0.token }.count
            
            Divider()
            
            HStack {
                Image(systemName: "key.fill")
                    .foregroundColor(AppConstants.Colors.text)
                Text("Valid App Tokens: \(validAppTokens)")
                Spacer()
            }
            
            HStack {
                Image(systemName: "key.fill")
                    .foregroundColor(AppConstants.Colors.text)
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
                        .foregroundColor(AppConstants.Colors.text)
                    Text("  • 1 category token")
                        .font(.caption)
                        .foregroundColor(AppConstants.Colors.text)
                    Text("  • Multiple individual app tokens from that category")
                        .font(.caption)
                        .foregroundColor(AppConstants.Colors.text)
                } else {
                    Text("⚠️ Selecting 1 category should give you ONLY:")
                        .font(.caption)
                        .foregroundColor(AppConstants.Colors.textSecondary)
                    Text("  • 1 category token")
                        .font(.caption)
                        .foregroundColor(AppConstants.Colors.textSecondary)
                    Text("  • No individual app tokens")
                        .font(.caption)
                        .foregroundColor(AppConstants.Colors.textSecondary)
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
    NavigationView {
        IncludeEntireCategoryTestView()
    }
}