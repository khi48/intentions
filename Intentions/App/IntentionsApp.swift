//
//  IntentionsApp.swift
//  Intentions
//
//  Created by Kieran Hitchcock on 26/05/25.
//
// =============================================================================
// App/IntentionsApp.swift - Main App Entry Point
// =============================================================================

import SwiftUI
import FamilyControls

@main
struct IntentionsApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
                    // Request Family Controls authorization on app launch
                    requestFamilyControlsAuthorization()
                }
        }
    }
    
    private func requestFamilyControlsAuthorization() {
        Task {
            do {
                try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
                print("Family Controls authorization granted")
            } catch {
                print("Family Controls authorization failed: \(error)")
            }
        }
    }
}
