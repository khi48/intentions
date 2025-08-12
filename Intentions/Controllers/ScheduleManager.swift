// ScheduleManager.swift
// Manages CRUD operations for UsageSchedule entities using CoreData, converting to/from UsageScheduleModel structs.

import CoreData
import Foundation

enum ScheduleManagerError: Error {
    case invalidTimeRange
    case scheduleNotFound
    case persistenceError(String)
}

class ScheduleManager: ObservableObject  {
    // MARK: - Properties
    private let persistenceController: PersistenceController
    
    // MARK: - Initialization
    init(persistenceController: PersistenceController) {
        self.persistenceController = persistenceController
    }
    
    // MARK: - CRUD Operations
    
    /// Creates or updates a UsageSchedule entity and returns the corresponding UsageScheduleModel struct.
    /// - Parameters:
    ///   - id: The UUID of the schedule (optional for new schedules).
    ///   - isActive: Whether the schedule is active.
    ///   - startTime: The start time of the schedule.
    ///   - endTime: The end time of the schedule.
    /// - Returns: The created or updated UsageScheduleModel struct.
    /// - Throws: CoreData errors if save fails or entity not found.
    func setSchedule(id: UUID? = nil, isActive: Bool, startTime: Date, endTime: Date) throws -> UsageScheduleModel {
        let context = persistenceController.container.viewContext
        let schedule: UsageSchedule
        
        guard endTime > startTime else {
            throw ScheduleManagerError.invalidTimeRange
        }
        
        if let id = id {
            // Attempt to update existing schedule
            let fetchRequest: NSFetchRequest<UsageSchedule> = UsageSchedule.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "id == %@", id as NSUUID)
            if let existingSchedule = try context.fetch(fetchRequest).first {
                schedule = existingSchedule
            } else {
                // Create new schedule with explicit entity name
                guard let entity = NSEntityDescription.entity(forEntityName: "UsageSchedule", in: context) else {
                    throw NSError(domain: "Intentions", code: -1, userInfo: [NSLocalizedDescriptionKey: "UsageSchedule entity not found"])
                }
                schedule = UsageSchedule(entity: entity, insertInto: context)
                schedule.id = id
            }
        } else {
            // Create new schedule with explicit entity name
            guard let entity = NSEntityDescription.entity(forEntityName: "UsageSchedule", in: context) else {
                throw NSError(domain: "Intentions", code: -1, userInfo: [NSLocalizedDescriptionKey: "UsageSchedule entity not found"])
            }
            schedule = UsageSchedule(entity: entity, insertInto: context)
            schedule.id = UUID()
        }
        
        schedule.isActive = isActive
        schedule.startTime = startTime
        schedule.endTime = endTime
        
        try context.save()
        
        return UsageScheduleModel(
            id: schedule.id,
            isActive: schedule.isActive,
            startTime: schedule.startTime,
            endTime: schedule.endTime
        )
    }
    
    /// Retrieves all UsageSchedule entities and returns them as an array of UsageScheduleModel structs.
    /// - Returns: Array of UsageScheduleModel structs.
    /// - Throws: CoreData errors if fetch fails.
    func fetchSchedules() throws -> [UsageScheduleModel] {
        let context = persistenceController.container.viewContext
        let fetchRequest: NSFetchRequest<UsageSchedule> = UsageSchedule.fetchRequest()
        
        let scheduleEntities = try context.fetch(fetchRequest)
        return scheduleEntities.map { entity in
            UsageScheduleModel(
                id: entity.id,
                isActive: entity.isActive,
                startTime: entity.startTime,
                endTime: entity.endTime
            )
        }
    }
}
