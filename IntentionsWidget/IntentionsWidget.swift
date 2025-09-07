//
//  IntentionsWidget.swift
//  IntentionsWidget
//
//  Created by Kieran Hitchcock on 06/09/2025.
//

import WidgetKit
import SwiftUI

struct IntentionsProvider: TimelineProvider {
    func placeholder(in context: Context) -> IntentionsEntry {
        IntentionsEntry(date: Date())
    }

    func getSnapshot(in context: Context, completion: @escaping (IntentionsEntry) -> ()) {
        let entry = IntentionsEntry(date: Date())
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> ()) {
        // For a simple app launcher widget, we only need one entry that doesn't change
        let entry = IntentionsEntry(date: Date())
        let timeline = Timeline(entries: [entry], policy: .never)
        completion(timeline)
    }
}

struct IntentionsEntry: TimelineEntry {
    let date: Date
}

struct IntentionsWidgetEntryView: View {
    var entry: IntentionsProvider.Entry
    @Environment(\.widgetFamily) var family

    var body: some View {
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
    
    // MARK: - Circular Widget (Main lockscreen widget)
    
    private var circularView: some View {
        ZStack {
            AccessoryWidgetBackground()
            
            VStack(spacing: 1) {
                // Use a more universally available icon
                Image(systemName: "target")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                
                Text("Intent")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(.white)
            }
        }
        .widgetURL(URL(string: "intentions://home"))
    }
    
    // MARK: - Rectangular Widget (More detailed)
    
    private var rectangularView: some View {
        ZStack {
            AccessoryWidgetBackground()
            
            HStack(spacing: 8) {
                Image(systemName: "target")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                
                VStack(alignment: .leading, spacing: 1) {
                    Text("Intentions")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                    
                    Text("Mindful app access")
                        .font(.system(size: 9, weight: .regular))
                        .foregroundColor(.white.opacity(0.8))
                }
                
                Spacer()
            }
            .padding(.horizontal, 8)
        }
        .widgetURL(URL(string: "intentions://home"))
    }
    
    // MARK: - Inline Widget (Minimal text)
    
    private var inlineView: some View {
        HStack(spacing: 4) {
            Image(systemName: "target")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white)
            
            Text("Intentions")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white)
        }
        .widgetURL(URL(string: "intentions://home"))
    }
}

struct IntentionsWidget: Widget {
    let kind: String = "IntentionsWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: IntentionsProvider()) { entry in
            IntentionsWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Intentions - Quick Access")
        .description("Launch Intentions app for mindful phone usage.")
        .supportedFamilies([
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryInline
        ])
    }
}

#Preview("Circular", as: .accessoryCircular) {
    IntentionsWidget()
} timeline: {
    IntentionsEntry(date: .now)
}

#Preview("Rectangular", as: .accessoryRectangular) {
    IntentionsWidget()
} timeline: {
    IntentionsEntry(date: .now)
}

#Preview("Inline", as: .accessoryInline) {
    IntentionsWidget()
} timeline: {
    IntentionsEntry(date: .now)
}