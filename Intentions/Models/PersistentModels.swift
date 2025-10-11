//
//  PersistentModels.swift
//  Intentions
//
//  Created by Kieran Hitchcock on 01/07/2025.
//


import Foundation
import SwiftData
import FamilyControls
import ManagedSettings

// MARK: - Persistent App Group Model
@Model
final class PersistentAppGroup {
    @Attribute(.unique) var id: UUID
    var name: String
    var applicationsData: Data // Stores encoded Set<ApplicationToken>
    var categoriesData: Data // Stores encoded Set<ActivityCategoryToken>
    var allowAllWebsites: Bool = false // Default to false for existing data
    var createdAt: Date
    var lastModified: Date
    
    init(
        id: UUID,
        name: String,
        applicationsData: Data,
        categoriesData: Data,
        allowAllWebsites: Bool,
        createdAt: Date,
        lastModified: Date
    ) {
        self.id = id
        self.name = name
        self.applicationsData = applicationsData
        self.categoriesData = categoriesData
        self.allowAllWebsites = allowAllWebsites
        self.createdAt = createdAt
        self.lastModified = lastModified
    }
    
    convenience init(from appGroup: AppGroup) {
        let applicationsData = (try? JSONEncoder().encode(appGroup.applications)) ?? Data()
        let categoriesData = (try? JSONEncoder().encode(appGroup.categories)) ?? Data()

        self.init(
            id: appGroup.id,
            name: appGroup.name,
            applicationsData: applicationsData,
            categoriesData: categoriesData,
            allowAllWebsites: appGroup.allowAllWebsites,
            createdAt: appGroup.createdAt,
            lastModified: appGroup.lastModified
        )
    }
    
    func update(from appGroup: AppGroup) {
        self.name = appGroup.name
        self.applicationsData = (try? JSONEncoder().encode(appGroup.applications)) ?? Data()
        self.categoriesData = (try? JSONEncoder().encode(appGroup.categories)) ?? Data()
        self.allowAllWebsites = appGroup.allowAllWebsites
        self.lastModified = appGroup.lastModified
    }
    
    func toAppGroup() -> AppGroup? {
        let applications = (try? JSONDecoder().decode(Set<ApplicationToken>.self, from: applicationsData)) ?? Set()
        let categories = (try? JSONDecoder().decode(Set<ActivityCategoryToken>.self, from: categoriesData)) ?? Set()

        do {
            let appGroup = try AppGroup(
                id: id,
                name: name,
                applications: applications,
                categories: categories,
                allowAllWebsites: allowAllWebsites,
                createdAt: createdAt,
                lastModified: lastModified
            )
            return appGroup
        } catch {
            // If reconstruction fails due to validation, return nil
            return nil
        }
    }
}

// MARK: - Persistent Intention Session Model
@Model
final class PersistentIntentionSession {
    @Attribute(.unique) var id: UUID
    var requestedAppGroupsData: Data // Stores encoded [UUID]
    var requestedApplicationsData: Data // Stores encoded Set<ApplicationToken>
    var allowAllWebsites: Bool = false // Default to false for existing data
    var duration: TimeInterval
    var startTime: Date
    var endTime: Date
    var isActive: Bool
    var wasCompleted: Bool
    var createdAt: Date
    
    init(
        id: UUID,
        requestedAppGroupsData: Data,
        requestedApplicationsData: Data,
        allowAllWebsites: Bool,
        duration: TimeInterval,
        startTime: Date,
        endTime: Date,
        isActive: Bool,
        wasCompleted: Bool,
        createdAt: Date
    ) {
        self.id = id
        self.requestedAppGroupsData = requestedAppGroupsData
        self.requestedApplicationsData = requestedApplicationsData
        self.allowAllWebsites = allowAllWebsites
        self.duration = duration
        self.startTime = startTime
        self.endTime = endTime
        self.isActive = isActive
        self.wasCompleted = wasCompleted
        self.createdAt = createdAt
    }
    
    convenience init(from session: IntentionSession) {
        let appGroupsData = (try? JSONEncoder().encode(session.requestedAppGroups)) ?? Data()
        let applicationsData = (try? JSONEncoder().encode(session.requestedApplications)) ?? Data()

        self.init(
            id: session.id,
            requestedAppGroupsData: appGroupsData,
            requestedApplicationsData: applicationsData,
            allowAllWebsites: session.allowAllWebsites,
            duration: session.duration,
            startTime: session.startTime,
            endTime: session.endTime,
            isActive: session.isActive,
            wasCompleted: session.wasCompleted,
            createdAt: session.createdAt
        )
    }
    
    func update(from session: IntentionSession) {
        self.requestedAppGroupsData = (try? JSONEncoder().encode(session.requestedAppGroups)) ?? Data()
        self.requestedApplicationsData = (try? JSONEncoder().encode(session.requestedApplications)) ?? Data()
        self.allowAllWebsites = session.allowAllWebsites
        self.duration = session.duration
        self.startTime = session.startTime
        self.endTime = session.endTime
        self.isActive = session.isActive
        self.wasCompleted = session.wasCompleted
        // Note: createdAt should not be updated - it represents the original creation time
    }
    
    func toIntentionSession() -> IntentionSession? {
        let requestedAppGroups = (try? JSONDecoder().decode([UUID].self, from: requestedAppGroupsData)) ?? []
        let requestedApplications = (try? JSONDecoder().decode(Set<ApplicationToken>.self, from: requestedApplicationsData)) ?? Set()
        
        // Reconstruct the appropriate SessionState based on stored properties
        let totalElapsed = endTime.timeIntervalSince(startTime)
        let state: SessionState
        
        if wasCompleted {
            state = .completed(totalElapsed: totalElapsed, completedAt: endTime)
        } else if isActive {
            state = .active(startedAt: startTime)
        } else {
            // Session was cancelled or paused
            state = .cancelled(totalElapsed: totalElapsed, cancelledAt: endTime)
        }
        
        // Use factory method to create session with preserved ID
        do {
            let session = try IntentionSession.fromPersistence(
                id: id,
                appGroups: requestedAppGroups,
                applications: requestedApplications,
                allowAllWebsites: allowAllWebsites,
                duration: duration,
                createdAt: createdAt,
                state: state
            )
            return session
        } catch {
            // If reconstruction fails due to validation, return nil
            return nil
        }
    }
}

// MARK: - Persistent Schedule Settings Model
@Model
final class PersistentScheduleSettings {
    var isEnabled: Bool
    var activeHoursStart: Int
    var activeHoursEnd: Int
    var activeDaysData: Data // Stores encoded Set<Weekday>
    var timeZoneIdentifier: String
    
    init(
        isEnabled: Bool,
        activeHoursStart: Int,
        activeHoursEnd: Int,
        activeDaysData: Data,
        timeZoneIdentifier: String
    ) {
        self.isEnabled = isEnabled
        self.activeHoursStart = activeHoursStart
        self.activeHoursEnd = activeHoursEnd
        self.activeDaysData = activeDaysData
        self.timeZoneIdentifier = timeZoneIdentifier
    }
    
    convenience init(from settings: ScheduleSettings) {
        let activeDaysData = (try? JSONEncoder().encode(settings.activeDays)) ?? Data()
        
        self.init(
            isEnabled: settings.isEnabled,
            activeHoursStart: settings.activeHours.lowerBound,
            activeHoursEnd: settings.activeHours.upperBound,
            activeDaysData: activeDaysData,
            timeZoneIdentifier: settings.timeZone.identifier
        )
    }
    
    func toScheduleSettings() -> ScheduleSettings? {
        guard let timeZone = TimeZone(identifier: timeZoneIdentifier) else {
            return nil
        }
        
        let activeDays = (try? JSONDecoder().decode(Set<Weekday>.self, from: activeDaysData)) ?? Set()
        
        let settings = ScheduleSettings()
        settings.isEnabled = isEnabled
        settings.activeHours = activeHoursStart...activeHoursEnd
        settings.activeDays = activeDays
        settings.timeZone = timeZone
        
        return settings
    }
}
