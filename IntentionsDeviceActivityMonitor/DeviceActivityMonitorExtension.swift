import Foundation
import DeviceActivity
import OSLog

/// DeviceActivityMonitor extension. Runs in its own process; survives main-app
/// termination and force-quit. Delegates all shield-state decisions to
/// ShieldEngine, which derives the target config from the persisted IntentLog
/// and writes ManagedSettingsStore directly.
///
/// We register BOTH interval and threshold callbacks. For sessions shorter
/// than the iOS minimum interval length (~15 min) the threshold event is the
/// one that fires at the actual expiry time; the padded intervalDidEnd is a
/// no-op because handleExpiry() is idempotent (session already cleared).
class DeviceActivityMonitorExtension: DeviceActivityMonitor {

    private let logger = Logger(subsystem: "oh.Intent", category: "DeviceActivityMonitor")

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        guard activity == DAMScheduler.sessionExpiryName else {
            logger.notice("intervalDidEnd: ignoring unrelated activity \(activity.rawValue, privacy: .public)")
            return
        }
        logger.notice("intervalDidEnd: session expiry")
        ShieldEngine.damExtension().handleExpiry()
    }

    override func eventDidReachThreshold(_ event: DeviceActivityEvent.Name, activity: DeviceActivityName) {
        super.eventDidReachThreshold(event, activity: activity)
        guard activity == DAMScheduler.sessionExpiryName,
              event == DAMScheduler.thresholdEventName else {
            logger.notice("eventDidReachThreshold: ignoring unrelated event \(event.rawValue, privacy: .public)/\(activity.rawValue, privacy: .public)")
            return
        }
        logger.notice("eventDidReachThreshold: session expiry (exact-time path)")
        ShieldEngine.damExtension().handleExpiry()
    }
}
