// GroupManager.swift
// Manages CRUD operations for AppGroup entities using CoreData, converting to/from AppGroup structs.

import CoreData

class GroupManager: ObservableObject  {
    // MARK: - Properties
    private let persistenceController: PersistenceController
    
    // MARK: - Initialization
    init(persistenceController: PersistenceController) {
        self.persistenceController = persistenceController
    }
    
    // MARK: - CRUD Operations
    
    /// Creates a new AppGroup entity and returns the created AppGroup struct.
    /// - Parameters:
    ///   - name: The name of the app group.
    ///   - bundleIDs: Array of app bundle identifiers.
    /// - Returns: The created AppGroup struct.
    /// - Throws: CoreData errors if save fails.
    func createAppGroup(name: String, bundleIDs: [String]) throws -> AppGroupModel {
        let context = self.persistenceController.container.viewContext
        guard let entity = NSEntityDescription.entity(forEntityName: "AppGroup", in: context) else {
            throw NSError(domain: "Intentions", code: -1, userInfo: [NSLocalizedDescriptionKey: "AppGroup entity not found"])
        }
        let appGroup = AppGroup(entity: entity, insertInto: context)
        let id = UUID()
        appGroup.id = id
        appGroup.name = name
        appGroup.bundleIDs = bundleIDs
        
        try context.save()
        
        return AppGroupModel(id: id, name: name, bundleIDs: bundleIDs)
    }
    
    /// Retrieves all AppGroup entities and returns them as an array of AppGroup structs.
    /// - Returns: Array of AppGroup structs.
    /// - Throws: CoreData errors if fetch fails.
    func fetchAppGroups() throws -> [AppGroupModel] {
        let context = persistenceController.container.viewContext
        let fetchRequest: NSFetchRequest<AppGroup> = AppGroup.fetchRequest()
        
        let appGroups = try context.fetch(fetchRequest)
        return appGroups.map { entity in
            AppGroupModel(
                id: entity.id,
                name: entity.name,
                bundleIDs: entity.bundleIDs
            )
        }
    }
    
    /// Updates an existing AppGroup entity identified by id.
    /// - Parameters:
    ///   - id: The UUID of the AppGroup to update.
    ///   - name: The new name (optional).
    ///   - bundleIDs: The new bundleIDs array (optional).
    /// - Returns: The updated AppGroup struct, or nil if not found.
    /// - Throws: CoreData errors if fetch or save fails.
    func updateAppGroup(id: UUID, name: String, bundleIDs: [String]) throws -> AppGroupModel? {
        let context = persistenceController.container.viewContext
        let fetchRequest: NSFetchRequest<AppGroup> = AppGroup.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id == %@", id as NSUUID)
        
        guard let appGroup = try context.fetch(fetchRequest).first else {
            return nil
        }
        
        appGroup.name = name
        appGroup.bundleIDs = bundleIDs
        
        try context.save()
        
        return AppGroupModel(
            id: appGroup.id,
            name: appGroup.name,
            bundleIDs: appGroup.bundleIDs
        )
    }
    
    /// Deletes an AppGroup entity identified by id.
    /// - Parameter id: The UUID of the AppGroup to delete.
    /// - Throws: CoreData errors if fetch or save fails.
    func deleteAppGroup(id: UUID) throws {
        let context = persistenceController.container.viewContext
        let fetchRequest: NSFetchRequest<AppGroup> = AppGroup.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id == %@", id as NSUUID)
        
        guard let appGroup = try context.fetch(fetchRequest).first else {
            return
        }
        
        context.delete(appGroup)
        try context.save()
    }
}
