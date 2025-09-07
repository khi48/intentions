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
                .onOpenURL { url in
                    handleWidgetURL(url)
                }
        }
    }
    
    
    private func handleWidgetURL(_ url: URL) {
        print("🔗 WIDGET: Received URL from widget: \(url)")
        
        guard url.scheme == "intentions" else {
            print("❌ WIDGET: Invalid URL scheme: \(url.scheme ?? "nil")")
            return
        }
        
        switch url.host {
        case "home":
            print("✅ WIDGET: Opening app to home page")
            // The app will naturally open to the home page via ContentView
            // We could add specific navigation logic here if needed
            break
        default:
            print("⚠️ WIDGET: Unknown URL path: \(url.host ?? "nil")")
            // Default to home page behavior
            break
        }
    }
}
