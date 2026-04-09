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
    private enum Constants {
        static let appGroupId = "group.oh.Intent"
        static let blockingStatusKey = "intentions.widget.blockingStatus"
        static let lastUpdateKey = "intentions.widget.lastUpdate"
        static let sessionTitleKey = "intentions.widget.sessionTitle"
        static let sessionEndTimeKey = "intentions.widget.sessionEndTime"
    }

    private static var sharedUserDefaults: UserDefaults {
        CFPreferencesSynchronize(Constants.appGroupId as CFString, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        return UserDefaults(suiteName: Constants.appGroupId) ?? UserDefaults.standard
    }

    static func getBlockingStatus() -> Bool {
        sharedUserDefaults.bool(forKey: Constants.blockingStatusKey)
    }

    static func getLastUpdateTime() -> Date? {
        sharedUserDefaults.object(forKey: Constants.lastUpdateKey) as? Date
    }

    static func isDataStale() -> Bool {
        guard let lastUpdate = getLastUpdateTime() else { return true }
        return Date().timeIntervalSince(lastUpdate) > 3600
    }

    static func getSessionTitle() -> String? {
        sharedUserDefaults.string(forKey: Constants.sessionTitleKey)
    }

    static func getSessionEndTime() -> Date? {
        sharedUserDefaults.object(forKey: Constants.sessionEndTimeKey) as? Date
    }

    // Calculate remaining time for active session
    static func getRemainingTime() -> TimeInterval? {
        guard let endTime = getSessionEndTime() else { return nil }
        let remaining = endTime.timeIntervalSince(Date())
        return remaining > 0 ? remaining : nil
    }
}

struct IntentionsProvider: TimelineProvider {
    func placeholder(in context: Context) -> IntentionsEntry {
        IntentionsEntry(date: Date(), isBlocking: true, isDataStale: false, sessionTitle: nil, remainingTime: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (IntentionsEntry) -> ()) {
        let entry = createEntry()
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> ()) {
        let entry = createEntry()

        // If there's an active session, create entries for smooth countdown updates
        var entries: [IntentionsEntry] = [entry]
        var reloadPolicy: TimelineReloadPolicy

        if let remainingTime = entry.remainingTime, remainingTime > 0 {
            // Active session - create entries every minute for countdown
            let minutesToCreate = min(Int(remainingTime / 60) + 1, 60) // Max 60 entries (1 hour)

            for minuteOffset in 1...minutesToCreate {
                let futureDate = Date().addingTimeInterval(TimeInterval(minuteOffset * 60))
                let futureRemaining = max(0, remainingTime - TimeInterval(minuteOffset * 60))

                entries.append(IntentionsEntry(
                    date: futureDate,
                    isBlocking: entry.isBlocking,
                    isDataStale: entry.isDataStale,
                    sessionTitle: entry.sessionTitle,
                    remainingTime: futureRemaining > 0 ? futureRemaining : nil
                ))

                // Stop creating entries once session would be expired
                if futureRemaining <= 0 {
                    break
                }
            }

            // For active sessions, reload when session expires (or in 1 hour, whichever is sooner)
            let sessionEndDate = Date().addingTimeInterval(remainingTime)
            reloadPolicy = .after(sessionEndDate)
        } else {
            // No active session - rely entirely on push updates from main app
            // Use .never policy since we call WidgetCenter.shared.reloadAllTimelines() when state changes
            // This eliminates unnecessary polling
            reloadPolicy = .never
        }

        let timeline = Timeline(entries: entries, policy: reloadPolicy)
        completion(timeline)
    }

    private func createEntry() -> IntentionsEntry {
        let isBlocking = WidgetDataManager.getBlockingStatus()
        let isDataStale = WidgetDataManager.isDataStale()
        let sessionTitle = WidgetDataManager.getSessionTitle()
        let remainingTime = WidgetDataManager.getRemainingTime()

        return IntentionsEntry(
            date: Date(),
            isBlocking: isBlocking,
            isDataStale: isDataStale,
            sessionTitle: sessionTitle,
            remainingTime: remainingTime
        )
    }
}

struct IntentionsEntry: TimelineEntry {
    let date: Date
    let isBlocking: Bool
    let isDataStale: Bool
    let sessionTitle: String?
    let remainingTime: TimeInterval?
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
        VStack(spacing: 3) {
            Image(systemName: blockingIcon)
                .font(.system(size: 32, weight: .semibold))
                .foregroundColor(blockingColor)

            Text(blockingText)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(blockingColor)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, 6)
        .widgetBackground()
        .widgetURL(URL(string: "intent://home"))
    }
    
    // MARK: - Rectangular Widget (More detailed)

    private var rectangularView: some View {
        GeometryReader { geometry in
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: blockingIcon)
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundColor(blockingColor)
                    .frame(width: 28, alignment: .leading)

                VStack(alignment: .leading, spacing: 2) {
                    Text(rectangularTitleText)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text(rectangularSubtitleText)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(Color(white: 0.7))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
            .padding(.leading, 8)
            .padding(.top, 6)
            .padding(.trailing, 8)
        }
        .widgetBackground()
        .widgetURL(URL(string: "intent://home"))
    }
    
    // MARK: - Inline Widget (Minimal text)

    private var inlineView: some View {
        HStack(spacing: 5) {
            Image(systemName: blockingIcon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(blockingColor)

            Text(inlineStatusText)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.white)
        }
        .widgetBackground()
        .widgetURL(URL(string: "intent://home"))
    }
    
    // MARK: - Status Properties

    private var blockingIcon: String {
        if entry.isDataStale {
            return "questionmark.circle"
        } else if entry.sessionTitle != nil && entry.remainingTime != nil {
            // Active session - show play/timer icon
            return "timer"
        } else if entry.isBlocking {
            // Blocking without session - show shield
            return "shield.fill"
        } else {
            // Open/accessible - show checkmark
            return "checkmark.circle"
        }
    }
    
    private var blockingColor: Color {
        if entry.isDataStale {
            return Color.orange
        } else if entry.sessionTitle != nil && entry.remainingTime != nil {
            // Active session - show blue/cyan for focus mode
            return Color.cyan
        } else if entry.isBlocking {
            // Blocking - show red
            return Color.red
        } else {
            // Open/accessible - show green
            return Color.green
        }
    }
    
    private var blockingText: String {
        if entry.isDataStale {
            return "Status"
        } else if entry.sessionTitle != nil && entry.remainingTime != nil {
            // Active session - show "Active" or session name (truncated)
            return "Active"
        } else if entry.isBlocking {
            return "Blocked"
        } else {
            return "Open"
        }
    }
    
    private var rectangularTitleText: String {
        if let sessionTitle = entry.sessionTitle, entry.remainingTime != nil {
            // Active session - show session name as title
            return sessionTitle
        } else {
            // No active session - show "Intent"
            return "Intent"
        }
    }

    private var rectangularSubtitleText: String {
        if entry.isDataStale {
            return "Status unknown"
        } else if let remaining = entry.remainingTime {
            // Active session - show remaining time
            let minutes = Int(remaining / 60)
            let hours = minutes / 60
            let mins = minutes % 60

            if hours > 0 {
                return "\(hours)h \(mins)m remaining"
            } else {
                return "\(mins)m remaining"
            }
        } else if entry.isBlocking {
            return "Apps are blocked"
        } else {
            return "Apps are accessible"
        }
    }

    private var blockingStatusText: String {
        if entry.isDataStale {
            return "Status unknown"
        } else if let sessionTitle = entry.sessionTitle, let remaining = entry.remainingTime {
            // Active session - show session name and remaining time
            let minutes = Int(remaining / 60)
            let hours = minutes / 60
            let mins = minutes % 60

            if hours > 0 {
                return "\(sessionTitle) (\(hours)h \(mins)m left)"
            } else {
                return "\(sessionTitle) (\(mins)m left)"
            }
        } else if entry.isBlocking {
            return "Apps are blocked"
        } else {
            return "Apps are accessible"
        }
    }
    
    private var inlineStatusText: String {
        if entry.isDataStale {
            return "Intent (Unknown)"
        } else if let sessionTitle = entry.sessionTitle, let remaining = entry.remainingTime {
            // Active session - show compact time
            let minutes = Int(remaining / 60)
            let hours = minutes / 60
            let mins = minutes % 60

            if hours > 0 {
                return "\(sessionTitle) (\(hours)h\(mins)m)"
            } else {
                return "\(sessionTitle) (\(mins)m)"
            }
        } else if entry.isBlocking {
            return "Intent (Blocked)"
        } else {
            return "Intent (Open)"
        }
    }
}

struct IntentionsWidget: Widget {
    let kind: String = "IntentionsWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: IntentionsProvider()) { entry in
            IntentionsWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Intent - Status & Access")
        .description("Shows app blocking status and provides quick access to the Intent app.")
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
    IntentionsEntry(date: .now, isBlocking: true, isDataStale: false, sessionTitle: nil, remainingTime: nil)
}

#Preview("Circular - Active Session", as: .accessoryCircular) {
    IntentionsWidget()
} timeline: {
    IntentionsEntry(date: .now, isBlocking: false, isDataStale: false, sessionTitle: "Work Focus", remainingTime: 1800)
}

#Preview("Rectangular - Blocked", as: .accessoryRectangular) {
    IntentionsWidget()
} timeline: {
    IntentionsEntry(date: .now, isBlocking: true, isDataStale: false, sessionTitle: nil, remainingTime: nil)
}

#Preview("Rectangular - Active Session", as: .accessoryRectangular) {
    IntentionsWidget()
} timeline: {
    IntentionsEntry(date: .now, isBlocking: false, isDataStale: false, sessionTitle: "Deep Work", remainingTime: 3600)
}

#Preview("Inline - Open", as: .accessoryInline) {
    IntentionsWidget()
} timeline: {
    IntentionsEntry(date: .now, isBlocking: false, isDataStale: false, sessionTitle: nil, remainingTime: nil)
}

// MARK: - Widget Background Extension

extension View {
    func widgetBackground() -> some View {
        containerBackground(for: .widget) {
            AccessoryWidgetBackground()
        }
    }
}