//
//  SetupStateManager.swift
//  Intentions
//
//  Created by Claude on 07/09/2025.
//

import Foundation

/// Manages persistence and validation of app setup state
/// Ensures setup is only shown when necessary and tracks completion properly
@MainActor
final class SetupStateManager: Sendable {
    
    // MARK: - Constants
    
    private static let setupStateKey = "IntentionsAppSetupState"
    private static let setupStateFileName = "setup_state.json"
    
    // MARK: - Properties
    
    private let userDefaults: UserDefaults
    private let fileManager: FileManager
    
    // MARK: - Initialization
    
    init(
        userDefaults: UserDefaults = .standard,
        fileManager: FileManager = .default
    ) {
        self.userDefaults = userDefaults
        self.fileManager = fileManager
    }
    
    // MARK: - Public API
    
    /// Load current setup state from persistent storage
    func loadSetupState() async -> SetupState? {
        // Try UserDefaults first (fast)
        if let state = loadFromUserDefaults() {
            return state
        }
        
        // Fallback to file system (more reliable)
        if let state = await loadFromFileSystem() {
            // Save back to UserDefaults for faster future access
            saveToUserDefaults(state)
            return state
        }
        
        // No saved state found
        return nil
    }
    
    /// Save setup state to persistent storage
    func saveSetupState(_ state: SetupState) async {
        // Save to both UserDefaults and file system for redundancy
        saveToUserDefaults(state)
        await saveToFileSystem(state)
    }
    
    /// Clear all setup state (for testing or reset)
    func clearSetupState() async {
        userDefaults.removeObject(forKey: Self.setupStateKey)
        await deleteFromFileSystem()
    }
    
    /// Check if setup has ever been completed
    func hasSetupBeenCompleted() async -> Bool {
        guard let state = await loadSetupState() else {
            return false
        }
        return state.isSetupSufficient
    }
    
    /// Get the documents directory URL for file storage
    private var documentsDirectory: URL {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
    }
    
    /// Get the setup state file URL
    private var setupStateFileURL: URL {
        documentsDirectory.appendingPathComponent(Self.setupStateFileName)
    }
    
    // MARK: - UserDefaults Storage
    
    private func loadFromUserDefaults() -> SetupState? {
        guard let data = userDefaults.data(forKey: Self.setupStateKey) else {
            return nil
        }
        
        do {
            let state = try JSONDecoder().decode(SetupState.self, from: data)
            return state
        } catch {
            print("❌ SETUP STATE: Failed to decode from UserDefaults: \(error)")
            return nil
        }
    }
    
    private func saveToUserDefaults(_ state: SetupState) {
        do {
            let data = try JSONEncoder().encode(state)
            userDefaults.set(data, forKey: Self.setupStateKey)
            print("✅ SETUP STATE: Saved to UserDefaults")
        } catch {
            print("❌ SETUP STATE: Failed to encode to UserDefaults: \(error)")
        }
    }
    
    // MARK: - File System Storage
    
    private func loadFromFileSystem() async -> SetupState? {
        let fileURL = setupStateFileURL
        
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return nil
        }
        
        do {
            let data = try Data(contentsOf: fileURL)
            let state = try JSONDecoder().decode(SetupState.self, from: data)
            return state
        } catch {
            print("❌ SETUP STATE: Failed to load from file system: \(error)")
            return nil
        }
    }
    
    private func saveToFileSystem(_ state: SetupState) async {
        let fileURL = setupStateFileURL
        
        do {
            let data = try JSONEncoder().encode(state)
            try data.write(to: fileURL)
            print("✅ SETUP STATE: Saved to file system")
        } catch {
            print("❌ SETUP STATE: Failed to save to file system: \(error)")
        }
    }
    
    private func deleteFromFileSystem() async {
        let fileURL = setupStateFileURL
        
        if fileManager.fileExists(atPath: fileURL.path) {
            do {
                try fileManager.removeItem(at: fileURL)
                print("✅ SETUP STATE: Deleted from file system")
            } catch {
                print("❌ SETUP STATE: Failed to delete from file system: \(error)")
            }
        }
    }
}

// MARK: - Setup State Factory

extension SetupStateManager {
    
    /// Create a new setup state based on current system conditions
    func createCurrentSetupState(
        screenTimeAuthorized: Bool,
        categoryMappingCompleted: Bool,
        systemHealthValidated: Bool
    ) -> SetupState {
        return SetupState(
            screenTimeAuthorized: screenTimeAuthorized,
            categoryMappingCompleted: categoryMappingCompleted,
            systemHealthValidated: systemHealthValidated,
            setupVersion: SetupState.currentSetupVersion,
            completedDate: Date(),
            lastValidatedDate: Date(),
            userSkippedOptionalSteps: false
        )
    }
    
    /// Create a default "incomplete" setup state
    func createIncompleteSetupState() -> SetupState {
        return SetupState(
            screenTimeAuthorized: false,
            categoryMappingCompleted: false,
            systemHealthValidated: false,
            setupVersion: SetupState.currentSetupVersion,
            completedDate: Date(),
            lastValidatedDate: Date(),
            userSkippedOptionalSteps: false
        )
    }
}