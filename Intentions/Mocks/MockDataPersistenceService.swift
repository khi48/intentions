import Foundation
import SwiftUI
import FamilyControls

// MARK: - Mock Data Persistence Service
@MainActor
final class MockDataPersistenceService: DataPersisting {

    // In-memory storage for testing
    private var keyValueStore: [String: Data] = [:]
    private var intentionSessions: [UUID: IntentionSession] = [:]
    private var scheduleSettings: ScheduleSettings?
    var weeklyScheduleStore: WeeklySchedule?

    // Error simulation flags
    var shouldThrowError = false
    var shouldThrowSaveError = false
    var shouldThrowLoadError = false
    var shouldThrowDeleteError = false
    var errorToThrow: Error?

    // Method call tracking for testing
    var methodCalls: [String] = []

    // Convenience aliases for testing
    var shouldFailSave: Bool {
        get { shouldThrowSaveError }
        set { shouldThrowSaveError = newValue }
    }

    // MARK: - Initialization

    init() {
        setupDefaultQuickActions()
    }

    private func setupDefaultQuickActions() {
        let defaultQuickActions = [
            QuickAction(
                name: "Work Session",
                subtitle: "Productivity focus",
                iconName: "laptopcomputer",
                color: Color.blue,
                duration: 30 * 60
            ),
            QuickAction(
                name: "Study Time",
                subtitle: "Deep learning",
                iconName: "book.fill",
                color: Color.green,
                duration: 60 * 60
            ),
            QuickAction(
                name: "Break Time",
                subtitle: "Social & entertainment",
                iconName: "cup.and.saucer.fill",
                color: Color.orange,
                duration: 15 * 60
            )
        ]

        do {
            let data = try JSONEncoder().encode(defaultQuickActions)
            keyValueStore["quickActions"] = data
        } catch {
            print("Failed to setup default quick actions: \(error)")
        }
    }

    private func trackMethodCall(_ method: String) {
        methodCalls.append(method)
    }

    private func throwErrorIfNeeded() throws {
        if shouldThrowError, let error = errorToThrow {
            throw error
        }
    }

    // MARK: - Generic Storage Methods

    func save<T: Codable & Sendable>(_ object: T, forKey key: String) async throws {
        if shouldThrowSaveError {
            throw AppError.persistenceError("Mock save error for key: \(key)")
        }

        do {
            let data = try JSONEncoder().encode(object)
            keyValueStore[key] = data
        } catch {
            throw AppError.persistenceError("Failed to encode \(key): \(error.localizedDescription)")
        }
    }

    func load<T: Codable & Sendable>(_ type: T.Type, forKey key: String) async throws -> T? {
        if shouldThrowLoadError {
            throw AppError.persistenceError("Mock load error for key: \(key)")
        }

        guard let data = keyValueStore[key] else { return nil }

        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw AppError.persistenceError("Failed to decode \(key): \(error.localizedDescription)")
        }
    }

    func delete(forKey key: String) async throws {
        if shouldThrowDeleteError {
            throw AppError.persistenceError("Mock delete error for key: \(key)")
        }

        keyValueStore.removeValue(forKey: key)
    }

    // MARK: - Schedule Settings Methods

    func saveScheduleSettings(_ settings: ScheduleSettings) async throws {
        trackMethodCall("saveScheduleSettings")
        try throwErrorIfNeeded()

        if shouldThrowSaveError {
            throw AppError.persistenceError("Mock save error for ScheduleSettings")
        }

        scheduleSettings = settings
    }

    func loadScheduleSettings() async throws -> ScheduleSettings? {
        if shouldThrowLoadError {
            throw AppError.persistenceError("Mock load error for ScheduleSettings")
        }

        return scheduleSettings
    }

    // MARK: - Weekly Schedule Methods

    func saveWeeklySchedule(_ schedule: WeeklySchedule) async throws {
        trackMethodCall("saveWeeklySchedule")
        try throwErrorIfNeeded()

        if shouldThrowSaveError {
            throw AppError.persistenceError("Mock save error for WeeklySchedule")
        }

        weeklyScheduleStore = schedule
    }

    func loadWeeklySchedule() async throws -> WeeklySchedule? {
        if shouldThrowLoadError {
            throw AppError.persistenceError("Mock load error for WeeklySchedule")
        }

        return weeklyScheduleStore
    }

    // MARK: - Intention Session Methods

    func saveIntentionSession(_ session: IntentionSession) async throws {
        if shouldThrowSaveError {
            throw AppError.persistenceError("Mock save error for IntentionSession: \(session.id)")
        }

        intentionSessions[session.id] = session
    }

    func loadIntentionSessions() async throws -> [IntentionSession] {
        if shouldThrowLoadError {
            throw AppError.persistenceError("Mock load error for IntentionSessions")
        }

        return Array(intentionSessions.values).sorted { $0.startTime > $1.startTime }
    }

    func loadIntentionSessionsSince(_ date: Date) async throws -> [IntentionSession] {
        if shouldThrowLoadError {
            throw AppError.persistenceError("Mock load error for IntentionSessions")
        }

        return Array(intentionSessions.values)
            .filter { $0.createdAt >= date }
            .sorted { $0.startTime > $1.startTime }
    }

    func deleteIntentionSession(_ id: UUID) async throws {
        if shouldThrowDeleteError {
            throw AppError.persistenceError("Mock delete error for IntentionSession: \(id)")
        }

        guard intentionSessions[id] != nil else {
            throw AppError.dataNotFound("IntentionSession with ID \(id)")
        }

        intentionSessions.removeValue(forKey: id)
    }

    func clearExpiredSessions() async throws {
        if shouldThrowDeleteError {
            throw AppError.persistenceError("Mock error clearing expired sessions")
        }

        let cutoffDate = Date().addingTimeInterval(-24 * 60 * 60 * 7)
        let expiredSessionIds = intentionSessions.values
            .filter { $0.startTime < cutoffDate }
            .map(\.id)

        for id in expiredSessionIds {
            intentionSessions.removeValue(forKey: id)
        }
    }

    // MARK: - Test Helper Methods

    func reset() async {
        keyValueStore.removeAll()
        intentionSessions.removeAll()
        scheduleSettings = nil
        weeklyScheduleStore = nil
        shouldThrowError = false
        shouldThrowSaveError = false
        shouldThrowLoadError = false
        shouldThrowDeleteError = false
        errorToThrow = nil
        methodCalls.removeAll()
    }

    func getStoredSessionCount() async -> Int {
        intentionSessions.count
    }

    func hasScheduleSettings() async -> Bool {
        scheduleSettings != nil
    }

    func getSession(id: UUID) async -> IntentionSession? {
        intentionSessions[id]
    }
}
