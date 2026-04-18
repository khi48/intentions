import Foundation
import DeviceActivity
import OSLog

/// DeviceActivityMonitor extension. Runs in its own process; survives main-app
/// termination and force-quit. Delegates all shield-state decisions to
/// ShieldEngine, which derives the target config from the persisted IntentLog
/// and writes ManagedSettingsStore directly.
class DeviceActivityMonitorExtension: DeviceActivityMonitor {

    private let logger = Logger(subsystem: "oh.Intent", category: "DeviceActivityMonitor")

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)

        guard activity == DAMScheduler.sessionExpiryName else {
            logger.notice("intervalDidEnd: ignoring unrelated activity \(activity.rawValue, privacy: .public)")
            return
        }

        logger.notice("intervalDidEnd: session expiry — handing off to ShieldEngine")
        ShieldEngine.damExtension().handleExpiry()
    }
}
