import Foundation

/// Cross-process Darwin notification used by the DAM extension to wake the
/// main-app process (when alive in background) for an immediate shield
/// re-render. iOS 26 springboard ignores extension-process ManagedSettings
/// writes; this is the fastest path to getting a main-app-process write
/// for the render to refresh. Works only while the main-app process is
/// alive — under force-quit there's no listener, and the BGTask +
/// foreground catch-up paths take over.
enum DarwinWake {
    /// Darwin notification name. Cross-process, global namespace — prefix
    /// with the app bundle to avoid collisions.
    static let notificationNameRaw = "oh.Intent.shieldstate.expiry"

    private static var notificationName: CFString { notificationNameRaw as CFString }

    /// Post from the DAM extension after handleExpiry. Best-effort; no
    /// delivery confirmation from iOS.
    static func post() {
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        CFNotificationCenterPostNotification(
            center,
            CFNotificationName(notificationName),
            nil,
            nil,
            true
        )
    }

    /// Install a process-wide observer. Fires `block` **synchronously on the
    /// CFNotificationCenter callback thread** whenever a Darwin notification
    /// with our name arrives. Call once during main-app startup. Observer
    /// lives for the life of the process.
    ///
    /// Intentionally does NOT dispatch to the main queue: for a backgrounded
    /// app the main queue is suspended, and the callback would wait until
    /// foreground (defeating the point of a Darwin wake). Running
    /// synchronously on the callback thread lets the work complete during
    /// the kernel-provided wake window. The block must therefore be
    /// thread-safe — the production use (ShieldEngine.reapplyCurrentState)
    /// touches Sendable types and ManagedSettingsStore writes, both of
    /// which are safe off the main actor.
    static func observe(_ block: @escaping @Sendable () -> Void) {
        final class Box: @unchecked Sendable {
            let block: @Sendable () -> Void
            init(_ block: @escaping @Sendable () -> Void) { self.block = block }
        }
        let box = Box(block)
        let pointer = Unmanaged.passRetained(box).toOpaque()

        let callback: CFNotificationCallback = { _, observer, _, _, _ in
            guard let observer else { return }
            let box = Unmanaged<Box>.fromOpaque(observer).takeUnretainedValue()
            box.block()
        }

        let center = CFNotificationCenterGetDarwinNotifyCenter()
        CFNotificationCenterAddObserver(
            center,
            pointer,
            callback,
            notificationName,
            nil,
            .deliverImmediately
        )
    }
}
