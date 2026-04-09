//
//  SetupStateManager.swift
//  Intentions
//
//  Created by Claude on 07/09/2025.
//

import Foundation
import OSLog

/// Manages persistence and validation of app setup state
@MainActor
final class SetupStateManager: Sendable {

    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Intentions", category: "SetupStateManager")
    
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
    
    private var setupStateFileURL: URL? {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent(Self.setupStateFileName)
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
            return nil
        }
    }
    
    private func saveToUserDefaults(_ state: SetupState) {
        do {
            let data = try JSONEncoder().encode(state)
            userDefaults.set(data, forKey: Self.setupStateKey)
        } catch {
            Self.log.error("Failed to save setup state to UserDefaults: \(error.localizedDescription)")
        }
    }
    
    // MARK: - File System Storage
    
    private func loadFromFileSystem() async -> SetupState? {
        guard let fileURL = setupStateFileURL,
              fileManager.fileExists(atPath: fileURL.path) else {
            return nil
        }

        do {
            let data = try Data(contentsOf: fileURL)
            return try JSONDecoder().decode(SetupState.self, from: data)
        } catch {
            return nil
        }
    }
    
    private func saveToFileSystem(_ state: SetupState) async {
        guard let fileURL = setupStateFileURL else { return }

        do {
            let data = try JSONEncoder().encode(state)
            try data.write(to: fileURL)
        } catch {
            Self.log.error("Failed to save setup state to file: \(error.localizedDescription)")
        }
    }

    private func deleteFromFileSystem() async {
        guard let fileURL = setupStateFileURL else { return }

        if fileManager.fileExists(atPath: fileURL.path) {
            do {
                try fileManager.removeItem(at: fileURL)
            } catch {
                Self.log.error("Failed to delete setup state file: \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - Setup State Factory

extension SetupStateManager {
    
    func createCurrentSetupState(
        screenTimeAuthorized: Bool
    ) -> SetupState {
        SetupState(
            screenTimeAuthorized: screenTimeAuthorized
        )
    }

    func createIncompleteSetupState() -> SetupState {
        SetupState()
    }
}