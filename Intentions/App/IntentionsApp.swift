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

    init() {
        // One-shot per process: freeze the live breadcrumb keys here so the
        // frozen snapshot reflects whatever the extension last wrote BEFORE
        // any main-app reconcile work runs. Do NOT call freeze() elsewhere —
        // a second freeze on scenePhase.active would clobber that pre-launch
        // snapshot with foreground-reapply data.
        DebugBreadcrumbs.freeze()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            // Do NOT call DebugBreadcrumbs.freeze() here — it's one-shot per
            // process and runs in App.init. Re-freezing on each foreground
            // would overwrite the pre-launch snapshot we want to inspect.
            DebugBreadcrumbs.record(.scenePhaseActive)
            let dump = DebugBreadcrumbs.dumpHistory()
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
