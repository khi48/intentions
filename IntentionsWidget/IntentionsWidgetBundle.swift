//
//  IntentionsWidgetBundle.swift
//  IntentionsWidget
//
//  Created by Kieran Hitchcock on 06/09/2025.
//

import WidgetKit
import SwiftUI

@main
struct IntentionsWidgetBundle: WidgetBundle {
    var body: some Widget {
        IntentionsWidget()
        // Note: Removed IntentionsWidgetControl and IntentionsWidgetLiveActivity 
        // as they're not needed for our lockscreen widget functionality
    }
}