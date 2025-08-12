//
//  AppBlockerProtocol.swift
//  Intentions
//
//  Created by Kieran Hitchcock on 5/06/25.
//

// AppBlockerProtocol.swift
// Protocol for handling app blocking/unlocking in the Intentions app.

import Foundation

class AppBlocker: ObservableObject {
    func unlockAppGroup(_ appGroup: AppGroupModel, forDuration: TimeInterval) throws {
        print("Unlocked \(appGroup.name) for \(forDuration) seconds")
    }
}
