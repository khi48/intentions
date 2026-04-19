import Foundation
import DeviceActivity
import BackgroundTasks
import OSLog

/// DeviceActivityMonitor extension. Runs in its own process; survives main-app
/// termination and force-quit. Delegates all shield-state decisions to
/// ShieldEngine, which derives the target config from the persisted IntentLog.
///
/// On iOS 26, extension-process ManagedSettingsStore writes do NOT re-render
/// the springboard shield layer (Apple DTS 807934) — even for shield
/// ADDITION. The store is updated, but springboard keeps its cached shield
/// state until the MAIN APP process writes. So after handing off to the
/// engine (which writes from this extension, best-effort) we also submit a
/// BGAppRefreshTask request. iOS wakes the main app, the main app's
/// BGTask handler re-applies the current config from its own process,
/// and springboard re-reads. Under force-quit BGTask is disabled — the
/// foreground catch-up path picks up the slack on next app launch.
///
/// We register BOTH interval and threshold callbacks. For sessions shorter
/// than the iOS minimum interval length (~15 min) the threshold event fires
/// at the actual expiry time; the padded intervalDidEnd is an idempotent
/// no-op because handleExpiry already cleared the session.
class DeviceActivityMonitorExtension: DeviceActivityMonitor {

    private let logger = Logger(subsystem: "oh.Intent", category: "DeviceActivityMonitor")

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        guard activity == DAMScheduler.sessionExpiryName else {
            logger.notice("intervalDidEnd: ignoring unrelated activity \(activity.rawValue, privacy: .public)")
            return
        }
        logger.notice("intervalDidEnd: session expiry")
        handleSessionExpiry()
    }

    override func eventDidReachThreshold(_ event: DeviceActivityEvent.Name, activity: DeviceActivityName) {
        super.eventDidReachThreshold(event, activity: activity)
        guard activity == DAMScheduler.sessionExpiryName,
              event == DAMScheduler.thresholdEventName else {
            logger.notice("eventDidReachThreshold: ignoring unrelated event \(event.rawValue, privacy: .public)/\(activity.rawValue, privacy: .public)")
            return
        }
        logger.notice("eventDidReachThreshold: session expiry (exact-time path)")
        handleSessionExpiry()
    }

    private func handleSessionExpiry() {
        ShieldEngine.damExtension().handleExpiry()
        // Fastest wake path: if the main-app process is still alive in
        // background, its Darwin observer fires immediately and writes
        // the shield config from its own process. Under force-quit there's
        // no listener — the BGTask path below is the next tier.
        DarwinWake.post()
        submitMainAppReapplyRequest()
    }

    /// Submit a BGAppRefreshTask so the main app wakes and re-applies the
    /// shield config from its own process. Needed because springboard
    /// doesn't observe extension-process store writes on iOS 26.
    private func submitMainAppReapplyRequest() {
        let request = BGAppRefreshTaskRequest(identifier: "oh.Intent.shieldClear")
        request.earliestBeginDate = nil
        do {
            try BGTaskScheduler.shared.submit(request)
            logger.notice("BGTask submitted: main app will re-apply on wake")
        } catch {
            logger.error("BGTask submit failed: \(error.localizedDescription, privacy: .public) — fallback to foreground catch-up")
        }
    }
}
