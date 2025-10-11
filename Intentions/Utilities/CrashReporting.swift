import Foundation
import os.log
import OSLog

/// Lightweight crash reporting that works with Apple Analytics
/// This helps ensure crashes are properly logged and identifiable
class CrashReporting {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Intentions", category: "CrashReporting")

    /// Initialize crash reporting - call this once at app launch
    static func initialize() {
        // Log app launch for reference
        logger.info("App launched successfully - version \(appVersion)")

        // Set up exception handler that logs before crash
        NSSetUncaughtExceptionHandler { exception in
            // Use os_log directly since we can't capture variables
            let log = OSLog(subsystem: Bundle.main.bundleIdentifier ?? "Intentions", category: "CrashReporting")
            os_log("Uncaught exception: %{public}@ - %{public}@",
                   log: log,
                   type: .fault,
                   exception.name.rawValue,
                   exception.reason ?? "Unknown reason")

            // Reset handler to allow system crash
            NSSetUncaughtExceptionHandler(nil)
        }

        logger.info("Crash reporting initialized")
    }

    /// Log significant errors that might lead to crashes
    static func logError(_ error: Error, context: String = "") {
        let contextInfo = context.isEmpty ? "" : " [\(context)]"
        logger.error("Error\(contextInfo): \(error.localizedDescription)")
        logger.debug("Error details\(contextInfo): \(String(describing: error))")
    }

    /// Log critical issues that might indicate instability
    static func logCritical(_ message: String, context: String = "") {
        let contextInfo = context.isEmpty ? "" : " [\(context)]"
        logger.critical("Critical issue\(contextInfo): \(message)")
    }

    /// Force a test crash (debug builds only)
    #if DEBUG
    static func testCrash() {
        logger.fault("Test crash triggered - this is intentional for testing")
        fatalError("Test crash - this is intentional for debugging crash reporting")
    }
    #endif

    private static var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
        return "\(version) (\(build))"
    }

}