//
//  IntentionsWidget.swift
//  IntentionsWidget
//
//  Created by Kieran Hitchcock on 06/09/2025.
//

import WidgetKit
import SwiftUI

// MARK: - Widget Data Management

private struct WidgetDataManager {
    // Widget Constants
    private enum Constants {
        static let appGroupId = "group.oh.Intentions"
        static let blockingStatusKey = "intentions.widget.blockingStatus"
        static let lastUpdateKey = "intentions.widget.lastUpdate"
    }
    
    // Shared UserDefaults for communication between app and widget
    private static var sharedUserDefaults: UserDefaults {
        // Debug: Check current user context
        let currentUser = getuid()
        let effectiveUser = geteuid()
        print("🔍 Widget User Context - UID: \(currentUser), EUID: \(effectiveUser)")

        // Debug: Check if we're in a sandbox
        let isSandboxed = getenv("APP_SANDBOX_CONTAINER_ID") != nil
        print("🔍 Widget Sandbox Status: \(isSandboxed ? "Sandboxed" : "Not Sandboxed")")

        // Force CFPreferences synchronization before creating UserDefaults
        CFPreferencesSynchronize(Constants.appGroupId as CFString, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)

        guard let sharedDefaults = UserDefaults(suiteName: Constants.appGroupId) else {
            print("⚠️ Widget: Failed to access App Group \(Constants.appGroupId), falling back to standard")
            return UserDefaults.standard
        }

        // Debug: Check UserDefaults access (avoid dictionaryRepresentation which triggers kCFPreferencesAnyUser)
        print("🔍 Widget UserDefaults Suite: Access successful")

        // Test read/write to see what actually happens
        let testKey = "widget.debug.test"
        sharedDefaults.set("widget-test-\(Date().timeIntervalSince1970)", forKey: testKey)
        let readValue = sharedDefaults.string(forKey: testKey)
        print("🔍 Widget R/W Test - Wrote and read: \(readValue ?? "nil")")

        // Advanced: Check CFPreferences directly to see actual domain access
        checkCFPreferencesAccess()

        return sharedDefaults
    }

    // Check CFPreferences access patterns
    private static func checkCFPreferencesAccess() {
        let appGroupId = Constants.appGroupId as CFString

        // Try different user scopes
        let currentUserValue = CFPreferencesCopyValue("intentions.widget.blockingStatus" as CFString, appGroupId, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        print("🔍 CFPrefs kCFPreferencesCurrentUser: \(currentUserValue != nil ? "✅ Success" : "❌ Failed")")

        let anyUserValue = CFPreferencesCopyValue("intentions.widget.blockingStatus" as CFString, appGroupId, kCFPreferencesAnyUser, kCFPreferencesAnyHost)
        print("🔍 CFPrefs kCFPreferencesAnyUser: \(anyUserValue != nil ? "✅ Success" : "❌ Failed")")

        // Check what domains are actually available
        let domains = CFPreferencesCopyKeyList(appGroupId, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        print("🔍 CFPrefs Available Keys Count: \(domains != nil ? CFArrayGetCount(domains!) : 0)")
    }
    
    // Get the current blocking status for widgets
    static func getBlockingStatus() -> Bool {
        // Try shared UserDefaults first
        let sharedStatus = sharedUserDefaults.bool(forKey: Constants.blockingStatusKey)

        // Try standard UserDefaults as fallback
        let standardStatus = UserDefaults.standard.bool(forKey: Constants.blockingStatusKey)

        // Use shared if available, fallback to standard
        let finalStatus = sharedUserDefaults == UserDefaults.standard ? standardStatus : sharedStatus

        return finalStatus
    }
    
    // Get the last update time
    static func getLastUpdateTime() -> Date? {
        // Try shared UserDefaults first
        let sharedTimestamp = sharedUserDefaults.object(forKey: Constants.lastUpdateKey) as? Date

        // Try standard UserDefaults as fallback
        let standardTimestamp = UserDefaults.standard.object(forKey: Constants.lastUpdateKey) as? Date

        // Use shared if available, fallback to standard
        let finalTimestamp = sharedUserDefaults == UserDefaults.standard ? standardTimestamp : sharedTimestamp

        return finalTimestamp
    }
    
    // Check if blocking status data is stale (older than 1 hour)
    static func isDataStale() -> Bool {
        guard let lastUpdate = getLastUpdateTime() else {
            return true
        }
        let isStale = Date().timeIntervalSince(lastUpdate) > 3600 // 1 hour
        return isStale
    }
}

struct IntentionsProvider: TimelineProvider {
    func placeholder(in context: Context) -> IntentionsEntry {
        IntentionsEntry(date: Date(), isBlocking: true, isDataStale: false)
    }

    func getSnapshot(in context: Context, completion: @escaping (IntentionsEntry) -> ()) {
        let isBlocking = WidgetDataManager.getBlockingStatus()
        let isDataStale = WidgetDataManager.isDataStale()
        let entry = IntentionsEntry(date: Date(), isBlocking: isBlocking, isDataStale: isDataStale)
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> ()) {
        let isBlocking = WidgetDataManager.getBlockingStatus()
        let isDataStale = WidgetDataManager.isDataStale()

        // Create multiple entries to ensure widget updates
        let currentDate = Date()
        let entries = [
            IntentionsEntry(date: currentDate, isBlocking: isBlocking, isDataStale: isDataStale),
            IntentionsEntry(date: currentDate.addingTimeInterval(1), isBlocking: isBlocking, isDataStale: isDataStale)
        ]

        // Update more frequently during active changes
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 5, to: Date()) ?? Date()
        let timeline = Timeline(entries: entries, policy: .after(nextUpdate))
        completion(timeline)
    }
}

struct IntentionsEntry: TimelineEntry {
    let date: Date
    let isBlocking: Bool
    let isDataStale: Bool
}

struct IntentionsWidgetEntryView: View {
    var entry: IntentionsProvider.Entry
    @Environment(\.widgetFamily) var family

    var body: some View {
        Group {
            switch family {
            case .accessoryCircular:
                circularView
            case .accessoryRectangular:
                rectangularView
            case .accessoryInline:
                inlineView
            default:
                // Fallback for other widget families
                circularView
            }
        }
    }
    
    // MARK: - Circular Widget (Main lockscreen widget)
    
    private var circularView: some View {
        VStack(spacing: 1) {
            Image(systemName: blockingIcon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(blockingColor)
            
            Text(blockingText)
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(blockingColor)
        }
        .widgetBackground()
        .widgetURL(URL(string: "intentions://home"))
    }
    
    // MARK: - Rectangular Widget (More detailed)
    
    private var rectangularView: some View {
        HStack(spacing: 8) {
            Image(systemName: blockingIcon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(blockingColor)
            
            VStack(alignment: .leading, spacing: 1) {
                Text("Intentions")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                
                Text(blockingStatusText)
                    .font(.system(size: 9, weight: .regular))
                    .foregroundColor(.white.opacity(0.8))
            }
            
            Spacer()
        }
        .padding(.horizontal, 8)
        .widgetBackground()
        .widgetURL(URL(string: "intentions://home"))
    }
    
    // MARK: - Inline Widget (Minimal text)
    
    private var inlineView: some View {
        HStack(spacing: 4) {
            Image(systemName: blockingIcon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(blockingColor)
            
            Text(inlineStatusText)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white)
        }
        .widgetBackground()
        .widgetURL(URL(string: "intentions://home"))
    }
    
    // MARK: - Status Properties
    
    private var blockingIcon: String {
        if entry.isDataStale {
            "questionmark.circle"
        } else if entry.isBlocking {
            "shield.fill"
        } else {
            "checkmark.circle"
        }
    }
    
    private var blockingColor: Color {
        if entry.isDataStale {
            Color.orange
        } else if entry.isBlocking {
            Color.red
        } else {
            Color.green
        }
    }
    
    private var blockingText: String {
        if entry.isDataStale {
            "Status"
        } else if entry.isBlocking {
            "Blocked"
        } else {
            "Open"
        }
    }
    
    private var blockingStatusText: String {
        if entry.isDataStale {
            return "Status unknown"
        } else if entry.isBlocking {
            return "Apps are blocked"
        } else {
            return "Apps are accessible"
        }
    }
    
    private var inlineStatusText: String {
        if entry.isDataStale {
            return "Intentions (Unknown)"
        } else if entry.isBlocking {
            return "Intentions (Blocked)"
        } else {
            return "Intentions (Open)"
        }
    }
}

struct IntentionsWidget: Widget {
    let kind: String = "IntentionsWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: IntentionsProvider()) { entry in
            IntentionsWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Intentions - Status & Access")
        .description("Shows app blocking status and provides quick access to the Intentions app.")
        .supportedFamilies([
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryInline
        ])
    }
}

#Preview("Circular - Blocked", as: .accessoryCircular) {
    IntentionsWidget()
} timeline: {
    IntentionsEntry(date: .now, isBlocking: true, isDataStale: false)
}

#Preview("Circular - Open", as: .accessoryCircular) {
    IntentionsWidget()
} timeline: {
    IntentionsEntry(date: .now, isBlocking: false, isDataStale: false)
}

#Preview("Rectangular - Blocked", as: .accessoryRectangular) {
    IntentionsWidget()
} timeline: {
    IntentionsEntry(date: .now, isBlocking: true, isDataStale: false)
}

#Preview("Inline - Open", as: .accessoryInline) {
    IntentionsWidget()
} timeline: {
    IntentionsEntry(date: .now, isBlocking: false, isDataStale: false)
}

// MARK: - iOS 17+ Compatibility Extension

extension View {
    /// Backwards compatible widget background modifier for iOS 17+ containerBackground API
    func widgetBackground() -> some View {
        if #available(iOSApplicationExtension 17.0, *) {
            return containerBackground(for: .widget) {
                AccessoryWidgetBackground()
            }
        } else {
            return background(AccessoryWidgetBackground())
        }
    }
}