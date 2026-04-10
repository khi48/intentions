//
//  SharedConstants.swift
//  Shared between Intentions app and IntentionsWidget extension
//
//  This file must be included in both the Intentions and IntentionsWidget targets.
//

import Foundation

enum SharedConstants {
    static let appGroupId = "group.oh.Intent"

    enum WidgetKeys {
        static let blockingStatus = "intentions.widget.blockingStatus"
        static let lastUpdate = "intentions.widget.lastUpdate"
        static let sessionTitle = "intentions.widget.sessionTitle"
        static let sessionEndTime = "intentions.widget.sessionEndTime"
    }
}
