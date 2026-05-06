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
        // re-render. In our current iOS 26 testing the extension-process
        // flush has not been observed re-rendering the springboard cache,
        // so we route shield-drop renders through the main app.
        DarwinWake.observe {
            DebugBreadcrumbs.record(.darwinReceived)
            let bgLog = Logger(subsystem: "oh.Intent", category: "App")
            bgLog.notice("Darwin wake → ShieldEngine.reapplyCurrentState()")
            ShieldEngine.mainApp().reapplyCurrentState()
        }
        DebugBreadcrumbs.record(.darwinObserverInstalled)
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
