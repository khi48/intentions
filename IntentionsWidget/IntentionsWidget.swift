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
        return UserDefaults(suiteName: Constants.appGroupId) ?? UserDefaults.standard
    }
    
    // Get the current blocking status for widgets
    static func getBlockingStatus() -> Bool {
        print("🏷️ WIDGET DATA: Attempting to read blocking status...")
        print("🏷️ WIDGET DATA: App Group ID: \(Constants.appGroupId)")
        print("🏷️ WIDGET DATA: Shared defaults available: \(sharedUserDefaults != UserDefaults.standard)")
        
        // Try shared UserDefaults first
        let sharedStatus = sharedUserDefaults.bool(forKey: Constants.blockingStatusKey)
        print("🏷️ WIDGET DATA: Shared UserDefaults status = \(sharedStatus)")
        
        // Try standard UserDefaults as fallback
        let standardStatus = UserDefaults.standard.bool(forKey: Constants.blockingStatusKey)
        print("🏷️ WIDGET DATA: Standard UserDefaults status = \(standardStatus)")
        
        // Use shared if available, fallback to standard
        let finalStatus = sharedUserDefaults == UserDefaults.standard ? standardStatus : sharedStatus
        print("🏷️ WIDGET DATA: Final status = \(finalStatus)")
        
        return finalStatus
    }
    
    // Get the last update time
    static func getLastUpdateTime() -> Date? {
        print("🏷️ WIDGET DATA: Attempting to read last update time...")
        
        // Try shared UserDefaults first
        let sharedTimestamp = sharedUserDefaults.object(forKey: Constants.lastUpdateKey) as? Date
        print("🏷️ WIDGET DATA: Shared UserDefaults timestamp = \(sharedTimestamp?.description ?? "nil")")
        
        // Try standard UserDefaults as fallback
        let standardTimestamp = UserDefaults.standard.object(forKey: Constants.lastUpdateKey) as? Date
        print("🏷️ WIDGET DATA: Standard UserDefaults timestamp = \(standardTimestamp?.description ?? "nil")")
        
        // Use shared if available, fallback to standard
        let finalTimestamp = sharedUserDefaults == UserDefaults.standard ? standardTimestamp : sharedTimestamp
        print("🏷️ WIDGET DATA: Final timestamp = \(finalTimestamp?.description ?? "nil")")
        
        return finalTimestamp
    }
    
    // Check if blocking status data is stale (older than 1 hour)
    static func isDataStale() -> Bool {
        guard let lastUpdate = getLastUpdateTime() else { 
            print("🏷️ WIDGET DATA: isDataStale() = true (no lastUpdate)")
            return true 
        }
        let isStale = Date().timeIntervalSince(lastUpdate) > 3600 // 1 hour
        let ageInMinutes = Date().timeIntervalSince(lastUpdate) / 60
        print("🏷️ WIDGET DATA: isDataStale() = \(isStale) (age: \(String(format: "%.1f", ageInMinutes)) minutes)")
        return isStale
    }
}

struct IntentionsProvider: TimelineProvider {
    func placeholder(in context: Context) -> IntentionsEntry {
        IntentionsEntry(date: Date(), isBlocking: true, isDataStale: false)
    }

    func getSnapshot(in context: Context, completion: @escaping (IntentionsEntry) -> ()) {
        print("📱 WIDGET PROVIDER: getSnapshot called at \(Date())")
        let isBlocking = WidgetDataManager.getBlockingStatus()
        let isDataStale = WidgetDataManager.isDataStale()
        let entry = IntentionsEntry(date: Date(), isBlocking: isBlocking, isDataStale: isDataStale)
        print("📱 WIDGET PROVIDER: Created snapshot entry - isBlocking: \(isBlocking), isDataStale: \(isDataStale)")
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> ()) {
        print("📱 WIDGET PROVIDER: getTimeline called at \(Date())")
        let isBlocking = WidgetDataManager.getBlockingStatus()
        let isDataStale = WidgetDataManager.isDataStale()
        print("📱 WIDGET PROVIDER: Created timeline entry - isBlocking: \(isBlocking), isDataStale: \(isDataStale)")
        
        // Create multiple entries to ensure widget updates
        let currentDate = Date()
        let entries = [
            IntentionsEntry(date: currentDate, isBlocking: isBlocking, isDataStale: isDataStale),
            IntentionsEntry(date: currentDate.addingTimeInterval(1), isBlocking: isBlocking, isDataStale: isDataStale)
        ]
        
        // Update more frequently during active changes
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 5, to: Date()) ?? Date()
        let timeline = Timeline(entries: entries, policy: .after(nextUpdate))
        print("📱 WIDGET PROVIDER: Timeline created with \(entries.count) entries, next update: \(nextUpdate)")
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
        print("🎨 WIDGET VIEW: Rendering at \(Date()) - isBlocking: \(entry.isBlocking), isDataStale: \(entry.isDataStale), family: \(family)")
        
        return Group {
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
        let icon = if entry.isDataStale {
            "questionmark.circle"
        } else if entry.isBlocking {
            "shield.fill"
        } else {
            "checkmark.circle"
        }
        print("🎨 WIDGET ICON: \(icon) (isBlocking: \(entry.isBlocking), isDataStale: \(entry.isDataStale))")
        return icon
    }
    
    private var blockingColor: Color {
        let color = if entry.isDataStale {
            Color.orange
        } else if entry.isBlocking {
            Color.red
        } else {
            Color.green
        }
        print("🎨 WIDGET COLOR: \(color) (isBlocking: \(entry.isBlocking), isDataStale: \(entry.isDataStale))")
        return color
    }
    
    private var blockingText: String {
        let text = if entry.isDataStale {
            "Status"
        } else if entry.isBlocking {
            "Blocked"
        } else {
            "Open"
        }
        print("🎨 WIDGET TEXT: \(text) (isBlocking: \(entry.isBlocking), isDataStale: \(entry.isDataStale))")
        return text
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