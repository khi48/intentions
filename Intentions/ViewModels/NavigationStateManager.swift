//
//  NavigationStateManager.swift
//  Intentions
//
//  Created by Claude on 30/08/2025.
//

import SwiftUI

/// Centralized navigation state manager for controlling navigation across the app
@MainActor
@Observable
final class NavigationStateManager {

    // MARK: - Properties

    /// Navigation path for the Settings tab
    var settingsPath = NavigationPath()
    
    // MARK: - Navigation Control Methods
    
    /// Reset Settings navigation to root
    func resetSettingsNavigation() {
        guard !settingsPath.isEmpty else { return }
        settingsPath = NavigationPath()
    }
    
    /// Reset Settings navigation to root without animation
    /// - Note: Uses transaction to disable animations for smooth tab transitions
    func resetSettingsNavigationWithoutAnimation() {
        guard !settingsPath.isEmpty else { return }
        
        // Use SwiftUI transaction to disable animations
        var transaction = Transaction()
        transaction.disablesAnimations = true
        
        withTransaction(transaction) {
            settingsPath = NavigationPath()
        }
        
    }
    
    /// Navigate back one level in Settings
    func popSettingsNavigation() {
        guard settingsPath.count > 0 else { return }
        settingsPath.removeLast()
    }
    
    // MARK: - Future Extensions
    
    // Can add navigation paths for other tabs as needed:
    // var groupsPath = NavigationPath()
    // var homePath = NavigationPath()
}