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
    private static var sharedUserDefaults: UserDefaults {
        UserDefaults(suiteName: SharedConstants.appGroupId) ?? UserDefaults.standard
    }

    static func getBlockingStatus() -> Bool {
        sharedUserDefaults.bool(forKey: SharedConstants.WidgetKeys.blockingStatus)
    }

    static func getLastUpdateTime() -> Date? {
        sharedUserDefaults.object(forKey: SharedConstants.WidgetKeys.lastUpdate) as? Date
    }

    /// Only flagged stale on first-ever read (no `lastUpdate` yet). Once the
    /// main app or DAM has written, we trust the value indefinitely — every
    /// state transition (session start/end, schedule boundary, app foreground)
    /// pushes a fresh write, so a stored value is always the latest known
    /// state. Time-based staleness was removed in #20.
    static func isDataStale() -> Bool {
        getLastUpdateTime() == nil
    }

    static func getSessionTitle() -> String? {
        sharedUserDefaults.string(forKey: SharedConstants.WidgetKeys.sessionTitle)
    }

    static func getSessionEndTime() -> Date? {
        sharedUserDefaults.object(forKey: SharedConstants.WidgetKeys.sessionEndTime) as? Date
    }

    /// Steady-state blocking value for the post-session pre-baked entry. Written
    /// by WidgetBridge.pushSession at session start (schedule-derived). Defaults
    /// to `true` when missing — safety fallback matching the prior hardcode for
    /// mid-upgrade installs where pushSession ran before this key existed (#69).
    static func getPostSessionBlockingStatus() -> Bool {
        sharedUserDefaults.object(forKey: SharedConstants.WidgetKeys.postSessionBlockingStatus) as? Bool ?? true
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
            // Active session - create entries aligned to displayed-minute boundaries.
            // Display uses ceil(remaining / 60), so the first transition happens
            // when remaining crosses the next whole-minute mark, not after a full
            // 60s from now. e.g. 4m50s left → next entry at +50s shows "4m".
            var firstOffset = remainingTime.truncatingRemainder(dividingBy: 60)
            if firstOffset == 0 { firstOffset = 60 }

            let totalEntries = min(Int((remainingTime / 60).rounded(.up)), 60)

            for i in 0..<totalEntries {
                let offset = firstOffset + Double(i) * 60
                let futureDate = Date().addingTimeInterval(offset)
                let futureRemaining = max(0, remainingTime - offset)

                if futureRemaining <= 0 {
                    // Post-expiry entry: override the stale session-start values
                    // baked into `entry` (isBlocking: false, sessionTitle) to
                    // avoid a transient flash before WidgetBridge.pushNoSession
                    // lands from the DAM extension (#58). Steady-state blocking
                    // is read from the side-band key written by pushSession at
                    // session start (#69) — pre-#69 this was hardcoded `true`,
                    // which was wrong once #59 allowed sessions with blocking
                    // off. Drop-entry alternative tested and reverted —
                    // WidgetKit defers reload-triggered re-renders on
                    // lockscreen, so timeline-driven transition is more
                    // reliable than reload-driven.
                    entries.append(IntentionsEntry(
                        date: futureDate,
                        isBlocking: WidgetDataManager.getPostSessionBlockingStatus(),
                        isDataStale: entry.isDataStale,
                        sessionTitle: nil,
                        remainingTime: nil
                    ))
                    break
                }

                entries.append(IntentionsEntry(
                    date: futureDate,
                    isBlocking: entry.isBlocking,
                    isDataStale: entry.isDataStale,
                    sessionTitle: entry.sessionTitle,
                    remainingTime: futureRemaining
                ))
            }

            // For active sessions, reload when session expires (or in 1 hour, whichever is sooner)
            let sessionEndDate = Date().addingTimeInterval(remainingTime)
            reloadPolicy = .after(sessionEndDate)
        } else {
            // No active session - periodic fallback so the widget recovers if the app
            // is killed before it can push an update via reloadAllTimelines().
            reloadPolicy = .after(Date().addingTimeInterval(3600))
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
        .widgetURL(URL(string: "intentions://home"))
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
        .widgetURL(URL(string: "intentions://home"))
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
        .widgetURL(URL(string: "intentions://home"))
    }

    // MARK: - Status Properties

    private var blockingIcon: String {
        if entry.isDataStale {
            return "questionmark.circle"
        } else if entry.sessionTitle != nil && entry.remainingTime != nil {
            return "timer"
        } else if entry.isBlocking {
            return "shield.fill"
        } else {
            return "checkmark.circle"
        }
    }

    private var blockingColor: Color {
        if entry.isDataStale {
            return Color.orange
        } else if entry.sessionTitle != nil && entry.remainingTime != nil {
            return Color.cyan
        } else if entry.isBlocking {
            return Color.red
        } else {
            return Color.green
        }
    }

    private var blockingText: String {
        if entry.isDataStale {
            return "Status"
        } else if entry.sessionTitle != nil && entry.remainingTime != nil {
            return "Active"
        } else if entry.isBlocking {
            return "Blocked"
        } else {
            return "Open"
        }
    }

    private var rectangularTitleText: String {
        if let sessionTitle = entry.sessionTitle, entry.remainingTime != nil {
            return sessionTitle
        } else {
            return "Intent"
        }
    }

    private var rectangularSubtitleText: String {
        if entry.isDataStale {
            return "Status unknown"
        } else if let remaining = entry.remainingTime {
            let minutes = Int((remaining / 60).rounded(.up))
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

    private var inlineStatusText: String {
        if entry.isDataStale {
            return "Intent (Unknown)"
        } else if let sessionTitle = entry.sessionTitle, let remaining = entry.remainingTime {
            let minutes = Int((remaining / 60).rounded(.up))
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
