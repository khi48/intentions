import Foundation
import DeviceActivity
import OSLog

/// DeviceActivityMonitor extension. Runs in its own process; survives
/// main-app termination and force-quit (validated in block-mvp).
///
/// Three callbacks all route to the same idempotent `handleExpiry`:
///
///   1. `intervalDidStart` — the canonical trigger. Schedule's
///      `intervalStart` is set to the session's wall-clock end time, so
///      iOS fires this in the extension at session expiry (+2s to +9s
///      slop on iOS 26.5 beta 3).
///   2. `eventDidReachThreshold` — secondary. `firstTouch=1s` event on
///      the session's tokens fires when user opens the picked app
///      post-expiry; backstop if `intervalDidStart` was dropped.
///   3. `intervalDidEnd` — tertiary, fires at intervalStart + 15min30s.
///      Idempotent guard makes it a no-op once the session has been
///      reshielded.
class DeviceActivityMonitorExtension: DeviceActivityMonitor {

    private let logger = Logger(subsystem: "oh.Intent", category: "DeviceActivityMonitor")

    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
        DebugBreadcrumbs.record(.damIntervalDidStart, note: activity.rawValue)
        let engine = ShieldEngine.damExtension()
        if DAMScheduler.isSessionExpiryActivity(activity) {
            logger.notice("intervalDidStart: session expiry — primary trigger")
            engine.handleExpiry()
            WidgetBridge.pushNoSession(isBlocking: engine.currentBlockingState())
            return
        }
        if DAMScheduler.isScheduleBoundaryActivity(activity) {
            logger.notice("intervalDidStart: schedule boundary")
            // handleScheduleTransition → rescheduleBoundary → scheduleNextBoundary
            // cancels the current boundary activity first then registers the next.
            // That kills the [intervalStart, intervalEnd] window so iOS can't
            // replay intervalDidStart on subsequent ext relaunches.
            engine.handleScheduleTransition()
            WidgetBridge.pushNoSession(isBlocking: engine.currentBlockingState())
            return
        }
        logger.notice("intervalDidStart: ignoring unrelated activity \(activity.rawValue, privacy: .public)")
    }

    override func eventDidReachThreshold(_ event: DeviceActivityEvent.Name, activity: DeviceActivityName) {
        super.eventDidReachThreshold(event, activity: activity)
        DebugBreadcrumbs.record(.damEventThreshold, note: "\(activity.rawValue)/\(event.rawValue)")
        guard DAMScheduler.isSessionExpiryActivity(activity) else { return }
        guard event == DAMScheduler.firstTouchEventName else { return }
        logger.notice("eventDidReachThreshold: firstTouch on session tokens — secondary trigger")
        let engine = ShieldEngine.damExtension()
        engine.handleExpiry()
        WidgetBridge.pushNoSession(isBlocking: engine.currentBlockingState())
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        DebugBreadcrumbs.record(.damIntervalDidEnd, note: activity.rawValue)
        if DAMScheduler.isSessionExpiryActivity(activity) {
            logger.notice("intervalDidEnd: session expiry — tertiary trigger")
            let engine = ShieldEngine.damExtension()
            engine.handleExpiry()
            WidgetBridge.pushNoSession(isBlocking: engine.currentBlockingState())
            return
        }
        // Schedule-boundary intervalDidEnd is informational only — the boundary
        // itself fired at intervalDidStart 15min30s earlier and the chain has
        // already advanced. No-op.
        logger.notice("intervalDidEnd: ignoring \(activity.rawValue, privacy: .public)")
    }
}
