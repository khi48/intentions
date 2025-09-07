//
//  IntentionsWidgetLiveActivity.swift
//  IntentionsWidget
//
//  Created by Kieran Hitchcock on 06/09/2025.
//
//  Note: This is a stub file - Live Activities are not implemented for this widget

import ActivityKit
import WidgetKit
import SwiftUI

// Stub implementation - not used in our widget bundle
struct IntentionsWidgetAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var placeholder: String = ""
    }
    
    var name: String = "Intentions"
}

// Stub implementation - not used in our widget bundle
struct IntentionsWidgetLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: IntentionsWidgetAttributes.self) { context in
            VStack {
                Text("Not implemented")
            }
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.center) {
                    Text("Not implemented")
                }
            } compactLeading: {
                Text("")
            } compactTrailing: {
                Text("")
            } minimal: {
                Text("")
            }
            .widgetURL(URL(string: "intentions://home"))
        }
    }
}