import Foundation
import UIKit
import BackgroundTasks
import OSLog

/// UIApplicationDelegate adapter. Exists specifically so we can register the
/// BGTaskScheduler handler in application(_:didFinishLaunchingWithOptions:),
/// which Apple says is the only guaranteed registration point.
///
/// SwiftUI's .backgroundTask(.appRefresh(...)) modifier on the Scene is
/// supposed to do this automatically, but on iOS 26 there are reports of
/// it not registering reliably — handlers submitted by the DAM extension
/// never execute. Registering explicitly here is belt-and-suspenders.
final class AppDelegate: NSObject, UIApplicationDelegate {

    private let logger = Logger(subsystem: "oh.Intent", category: "AppDelegate")

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: "oh.Intent.shieldClear",
            using: nil
        ) { task in
            DebugBreadcrumbs.record(.bgtaskHandlerRan, note: "AppDelegate-registered")
            Logger(subsystem: "oh.Intent", category: "AppDelegate")
                .notice("BGTask oh.Intent.shieldClear fired — reapplying shield")
            ShieldEngine.mainApp().reapplyCurrentState()
            task.setTaskCompleted(success: true)
        }
        logger.notice("BGTaskScheduler handler registered for oh.Intent.shieldClear")
        return true
    }
}
