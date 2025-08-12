//
//  AppGroupModel.swift
//  Intentions
//
//  Created by Kieran Hitchcock on 28/05/25.
//

import Foundation
import CoreData

/// Represents a group of apps that can be managed together for screen time restrictions. 
struct AppGroupModel: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    var bundleIDs: [String]
}


extension AppGroupModel {
    func toManagedObject(context: NSManagedObjectContext) -> AppGroup {
        let entity = AppGroup(context: context)
        entity.id = id
        entity.name = name
        entity.bundleIDs = bundleIDs
        return entity
    }

    static func fromManagedObject(_ managedObject: AppGroup) -> AppGroupModel {
        AppGroupModel(id: managedObject.id, name: managedObject.name, bundleIDs: managedObject.bundleIDs)
    }
}
