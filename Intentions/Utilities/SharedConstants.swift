//
//  SharedConstants.swift
//  Shared between Intentions app, IntentionsWidget, and IntentionsShieldConfiguration targets.
//
//  This file must be included in the Intentions, IntentionsWidget, and
//  IntentionsShieldConfiguration targets.
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

    enum ShieldKeys {
        /// User's current intention quote, mirrored from WeeklySchedule.intentionQuote
        /// so the shield extension can read it without decoding the full schedule.
        static let intentionQuote = "intentions.shield.intentionQuote"
    }
}
