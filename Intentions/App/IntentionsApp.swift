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
    }
}
