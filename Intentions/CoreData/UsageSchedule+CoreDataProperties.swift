//
//  UsageSchedule+CoreDataProperties.swift
//  Intentions
//
//  Created by Kieran Hitchcock on 07/06/2025.
//
//

import Foundation
import CoreData


extension UsageSchedule {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<UsageSchedule> {
        return NSFetchRequest<UsageSchedule>(entityName: "UsageSchedule")
    }

    @NSManaged public var id: UUID
    @NSManaged public var isActive: Bool
    @NSManaged public var startTime: Date
    @NSManaged public var endTime: Date

}

extension UsageSchedule : Identifiable {

}
