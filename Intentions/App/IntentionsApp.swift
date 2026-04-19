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
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    private static let log = Logger(subsystem: "oh.Intent", category: "App")

    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Register a Darwin observer so the DAM extension can wake this
        // process instantly (when alive in background) and we can write
        // the shield config from the main-app process for springboard
        // re-render. Extension-process writes alone don't render on
        // iOS 26 (Apple DTS 807934).
        DarwinWake.observe {
            DebugBreadcrumbs.record(.darwinReceived)
            let bgLog = Logger(subsystem: "oh.Intent", category: "App")
            bgLog.notice("Darwin wake → ShieldEngine.reapplyCurrentState()")
            ShieldEngine.mainApp().reapplyCurrentState()
        }
        DebugBreadcrumbs.record(.darwinObserverInstalled)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            DebugBreadcrumbs.record(.scenePhaseActive)
            let dump = DebugBreadcrumbs.dump()
            Self.log.notice("scenePhase → active\n\(dump, privacy: .public)")
            print("SHIELDSTATE_BREADCRUMBS_START")
            print(dump)
            print("SHIELDSTATE_BREADCRUMBS_END")
            let engine = ShieldEngine.mainApp()
            engine.catchUpOnForeground()
            engine.reapplyCurrentState()
        }
        // BGTask handler is registered in AppDelegate via BGTaskScheduler.register,
        // which is the only guaranteed-to-work registration point per Apple docs.
        // The SwiftUI .backgroundTask modifier was unreliable on iOS 26.
    }
}
