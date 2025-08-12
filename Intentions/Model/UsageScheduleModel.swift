//
//  UsageScheduleModel.swift
//  Intentions
//
//  Created by Kieran Hitchcock on 28/05/25.
//

import Foundation
import CoreData

/// Represents a schedule for when app restrictions are active, defining a time window.
/// Conforms to Codable for CoreData persistence and Identifiable for SwiftUI integration.
struct UsageScheduleModel: Codable, Identifiable {
    let id: UUID
    var isActive: Bool
    var startTime: Date
    var endTime: Date
}

extension UsageScheduleModel {
    func toManagedObject(context: NSManagedObjectContext) -> UsageSchedule {
        let entity = UsageSchedule(context: context)
        entity.id = id
        entity.isActive = isActive
        entity.startTime = startTime
        entity.endTime = endTime
        return entity
    }

    static func fromManagedObject(_ managedObject: UsageSchedule) -> UsageScheduleModel {
        UsageScheduleModel(id: managedObject.id, isActive: managedObject.isActive, startTime: managedObject.startTime, endTime: managedObject.endTime)
    }
}
