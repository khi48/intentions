//
//  AppGroup+CoreDataProperties.swift
//  Intentions
//
//  Created by Kieran Hitchcock on 07/06/2025.
//
//

import Foundation
import CoreData


extension AppGroup {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<AppGroup> {
        return NSFetchRequest<AppGroup>(entityName: "AppGroup")
    }

    @NSManaged public var id: UUID
    @NSManaged public var name: String
    @NSManaged public var bundleIDs: [String]

}

extension AppGroup : Identifiable {

}
