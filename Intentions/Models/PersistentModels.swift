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

// MARK: - Persistent Intention Session Model
@Model
final class PersistentIntentionSession {
    @Attribute(.unique) var id: UUID
    var requestedAppGroupsData: Data // Stores encoded [UUID]
    var requestedApplicationsData: Data // Stores encoded Set<ApplicationToken>
    var requestedWebDomainsData: Data = Data() // Stores encoded Set<WebDomainToken>
    var allowAllWebsites: Bool = false // Default to false for existing data
    var duration: TimeInterval
    var startTime: Date
    var endTime: Date
    var isActive: Bool
    var wasCompleted: Bool
    var createdAt: Date
    var sourceData: Data? // Stores encoded SessionSource (optional for backward compatibility)

    init(
        id: UUID,
        requestedAppGroupsData: Data,
        requestedApplicationsData: Data,
        requestedWebDomainsData: Data = Data(),
        allowAllWebsites: Bool,
        duration: TimeInterval,
        startTime: Date,
        endTime: Date,
        isActive: Bool,
        wasCompleted: Bool,
        createdAt: Date,
        sourceData: Data? = nil
    ) {
        self.id = id
        self.requestedAppGroupsData = requestedAppGroupsData
        self.requestedApplicationsData = requestedApplicationsData
        self.requestedWebDomainsData = requestedWebDomainsData
        self.allowAllWebsites = allowAllWebsites
        self.duration = duration
        self.startTime = startTime
        self.endTime = endTime
        self.isActive = isActive
        self.wasCompleted = wasCompleted
        self.createdAt = createdAt
        self.sourceData = sourceData
    }
    
    @MainActor
    convenience init(from session: IntentionSession) {
        let encoder = JSONEncoder()
        let appGroupsData = (try? encoder.encode(session.requestedAppGroups)) ?? {
            assertionFailure("Failed to encode requestedAppGroups for session \(session.id)")
            return Data()
        }()
        let applicationsData = (try? encoder.encode(session.requestedApplications)) ?? {
            assertionFailure("Failed to encode requestedApplications for session \(session.id)")
            return Data()
        }()
        let webDomainsData = (try? encoder.encode(session.requestedWebDomains)) ?? Data()
        let sourceData = (try? encoder.encode(session.source)) ?? {
            assertionFailure("Failed to encode source for session \(session.id)")
            return Data()
        }()

        self.init(
            id: session.id,
            requestedAppGroupsData: appGroupsData,
            requestedApplicationsData: applicationsData,
            requestedWebDomainsData: webDomainsData,
            allowAllWebsites: session.allowAllWebsites,
            duration: session.duration,
            startTime: session.startTime,
            endTime: session.endTime,
            isActive: session.isActive,
            wasCompleted: session.wasCompleted,
            createdAt: session.createdAt,
            sourceData: sourceData
        )
    }

    @MainActor
    func update(from session: IntentionSession) {
        let encoder = JSONEncoder()
        self.requestedAppGroupsData = (try? encoder.encode(session.requestedAppGroups)) ?? Data()
        self.requestedApplicationsData = (try? encoder.encode(session.requestedApplications)) ?? Data()
        self.requestedWebDomainsData = (try? encoder.encode(session.requestedWebDomains)) ?? Data()
        self.sourceData = (try? encoder.encode(session.source)) ?? Data()
        self.allowAllWebsites = session.allowAllWebsites
        self.duration = session.duration
        self.startTime = session.startTime
        self.endTime = session.endTime
        self.isActive = session.isActive
        self.wasCompleted = session.wasCompleted
        // Note: createdAt should not be updated - it represents the original creation time
    }
    
    @MainActor
    func toIntentionSession() -> IntentionSession? {
        let requestedAppGroups = (try? JSONDecoder().decode([UUID].self, from: requestedAppGroupsData)) ?? []
        let requestedApplications = (try? JSONDecoder().decode(Set<ApplicationToken>.self, from: requestedApplicationsData)) ?? Set()
        let requestedWebDomains = requestedWebDomainsData.isEmpty ? Set<WebDomainToken>() : ((try? JSONDecoder().decode(Set<WebDomainToken>.self, from: requestedWebDomainsData)) ?? Set())

        // Decode source if available, otherwise default to .manual for backward compatibility
        let source: SessionSource
        if let sourceData = sourceData, !sourceData.isEmpty {
            source = (try? JSONDecoder().decode(SessionSource.self, from: sourceData)) ?? .manual
        } else {
            source = .manual
        }

        // Reconstruct the appropriate SessionState based on stored properties
        let totalElapsed = endTime.timeIntervalSince(startTime)
        let state: SessionState

        if wasCompleted {
            state = .completed(totalElapsed: totalElapsed, completedAt: endTime)
        } else if isActive {
            state = .active(startedAt: startTime)
        } else {
            state = .cancelled(totalElapsed: totalElapsed, cancelledAt: endTime)
        }

        // Use factory method to create session with preserved ID
        do {
            let session = try IntentionSession.fromPersistence(
                id: id,
                appGroups: requestedAppGroups,
                applications: requestedApplications,
                webDomains: requestedWebDomains,
                allowAllWebsites: allowAllWebsites,
                duration: duration,
                createdAt: createdAt,
                state: state,
                source: source
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
    var lastDisabledAt: Date?
    var intentionQuote: String?

    init(
        isEnabled: Bool,
        activeHoursStart: Int,
        activeHoursEnd: Int,
        activeDaysData: Data,
        timeZoneIdentifier: String,
        lastDisabledAt: Date? = nil,
        intentionQuote: String? = nil
    ) {
        self.isEnabled = isEnabled
        self.activeHoursStart = activeHoursStart
        self.activeHoursEnd = activeHoursEnd
        self.activeDaysData = activeDaysData
        self.timeZoneIdentifier = timeZoneIdentifier
        self.lastDisabledAt = lastDisabledAt
        self.intentionQuote = intentionQuote
    }

    @MainActor
    convenience init(from settings: ScheduleSettings) {
        let activeDaysData = (try? JSONEncoder().encode(settings.activeDays)) ?? Data()

        self.init(
            isEnabled: settings.isEnabled,
            activeHoursStart: settings.startHour,
            activeHoursEnd: settings.endHour,
            activeDaysData: activeDaysData,
            timeZoneIdentifier: settings.timeZone.identifier,
            lastDisabledAt: settings.lastDisabledAt,
            intentionQuote: settings.intentionQuote
        )
    }

    @MainActor
    func toScheduleSettings() -> ScheduleSettings? {
        guard let timeZone = TimeZone(identifier: timeZoneIdentifier) else {
            return nil
        }

        let activeDays = (try? JSONDecoder().decode(Set<Weekday>.self, from: activeDaysData)) ?? Set()

        let settings = ScheduleSettings()
        settings.isEnabled = isEnabled
        settings.startHour = activeHoursStart
        settings.endHour = activeHoursEnd
        settings.activeDays = activeDays
        settings.timeZone = timeZone
        settings.lastDisabledAt = lastDisabledAt
        settings.intentionQuote = intentionQuote

        return settings
    }
}
