//
//  IntentionsApp.swift
//  Intentions
//
//  Created by Kieran Hitchcock on 26/05/25.
//

import SwiftUI
import OSLog

@main
struct IntentApp: App {
    private static let log = Logger(subsystem: "oh.Intent", category: "App")

    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            // Foreground repair: if DAM fired expiry while we were away but
            // Family Controls didn't render, or if DAM missed entirely,
            // the engine reads the persisted IntentLog and applies the
            // matching shield config. No-op when state is already correct.
            Self.log.notice("scenePhase → active: ShieldEngine.catchUpOnForeground()")
            ShieldEngine.mainApp().catchUpOnForeground()
        }
    }
}
