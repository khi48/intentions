import Foundation
@preconcurrency import DeviceActivity

/// Thin wrapper over DeviceActivityCenter that schedules session-expiry callbacks.
/// The DAM extension receives intervalDidEnd() for the DeviceActivityName we register.
struct DAMScheduler: Sendable {
    /// Canonical name for the single session-expiry schedule. Starting a new
    /// session overwrites any pending prior schedule because we always use the
    /// same name.
    static let sessionExpiryName = DeviceActivityName("shieldstate.session-expiry")

    private let center = DeviceActivityCenter()

    /// Schedule a single-fire interval that ends at `endsAt`.
    /// Throws if endsAt is in the past or if authorization is missing.
    func schedule(endsAt: Date) throws {
        let now = Date()
        let startComponents = Self.components(from: now)
        let endComponents   = Self.components(from: endsAt)

        let schedule = DeviceActivitySchedule(
            intervalStart: startComponents,
            intervalEnd: endComponents,
            repeats: false
        )
        try center.startMonitoring(Self.sessionExpiryName, during: schedule)
    }

    /// Cancel any in-flight schedule under our name. Safe to call when nothing is scheduled.
    func cancel() {
        center.stopMonitoring([Self.sessionExpiryName])
    }

    private static func components(from date: Date) -> DateComponents {
        Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: date
        )
    }
}
