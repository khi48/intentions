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
            // Run catch-up off the main thread (#56). `catchUpOnForeground`
            // synchronously calls into ManagedSettings + DeviceActivity
            // (UsageTrackingAgent XPC), which is observably blocked for 10s+
            // when the agent is contended across DAM apps (e.g. Opal also
            // installed). Synchronous on main = black-screen launch hang +
            // 0x8badf00d watchdog kill at 20s. UI renders regardless of XPC
            // state; the user sees stale shield briefly rather than a hang.
            // No reapplyCurrentState — catchUpOnForeground already does
            // compute+apply on the same log read. The duplicate apply
            // (8 ManagedSettings XPC writes back-to-back) was a hang vector.
            Task.detached(priority: .userInitiated) {
                engine.catchUpOnForeground()
            }
            // Push fresh widget state — covers users who open the app after
            // a long gap during which no session ran (#20). Skip when a
            // session is in the log: pushNoSession wipes sessionTitle and
            // sessionEndTime, so unconditional firing destroys the
            // session-active widget render on every foreground.
            if IntentLogStore().load().activeSession == nil {
                WidgetBridge.pushNoSession(isBlocking: engine.currentBlockingState())
            }
        }
    }
}
