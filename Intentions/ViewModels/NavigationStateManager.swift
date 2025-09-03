//
//  NavigationStateManager.swift
//  Intentions
//
//  Created by Claude on 30/08/2025.
//

import SwiftUI

/// Centralized navigation state manager for controlling navigation across the app
@MainActor
final class NavigationStateManager: ObservableObject {
    
    // MARK: - Published Properties
    
    /// Navigation path for the Settings tab
    @Published var settingsPath = NavigationPath()
    
    // MARK: - Navigation Control Methods
    
    /// Reset Settings navigation to root
    func resetSettingsNavigation() {
        print("🔄 NAV MANAGER: Resetting Settings navigation to root")
        print("   - Old path count: \(settingsPath.count)")
        settingsPath = NavigationPath()
        print("   ✅ New path count: \(settingsPath.count)")
    }
    
    /// Navigate back one level in Settings
    func popSettingsNavigation() {
        guard settingsPath.count > 0 else { return }
        print("🔙 NAV MANAGER: Popping Settings navigation (from \(settingsPath.count) to \(settingsPath.count - 1))")
        settingsPath.removeLast()
    }
    
    // MARK: - Future Extensions
    
    // Can add navigation paths for other tabs as needed:
    // @Published var groupsPath = NavigationPath()
    // @Published var homePath = NavigationPath()
}