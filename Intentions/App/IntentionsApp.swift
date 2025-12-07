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
struct IntentApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
                .onOpenURL { url in
                    handleWidgetURL(url)
                }
        }
    }
    
    
    private func handleWidgetURL(_ url: URL) {

        guard url.scheme == "intent" else {
            return
        }

        switch url.host {
        case "home":
            // The app will naturally open to the home page via ContentView
            // We could add specific navigation logic here if needed
            break
        default:
            // Default to home page behavior
            break
        }
    }
}
