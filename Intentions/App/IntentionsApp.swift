//
//  IntentionsApp.swift
//  Intentions
//
//  Created by Kieran Hitchcock on 26/05/25.
//

import SwiftUI
import BackgroundTasks
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
            Self.log.notice("scenePhase → active: ShieldEngine.catchUpOnForeground()")
            ShieldEngine.mainApp().catchUpOnForeground()
        }
        // Main-app wake triggered by the DAM extension after session expiry.
        // On iOS 26, extension-process ManagedSettingsStore writes don't
        // re-render the springboard shield layer; the main app must write
        // from its own process for the render to refresh.
        .backgroundTask(.appRefresh("oh.Intent.shieldClear")) {
            let bgLog = Logger(subsystem: "oh.Intent", category: "App")
            bgLog.notice("BGTask oh.Intent.shieldClear → ShieldEngine.reapplyCurrentState()")
            ShieldEngine.mainApp().reapplyCurrentState()
        }
    }
}
