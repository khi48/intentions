import Foundation
import SwiftUI
import FamilyControls

// MARK: - Mock Data Persistence Service
final class MockDataPersistenceService: DataPersisting, @unchecked Sendable {
    
    // In-memory storage for testing
    private var keyValueStore: [String: Data] = [:]
    private var appGroups: [UUID: AppGroup] = [:]
    private var intentionSessions: [UUID: IntentionSession] = [:]
    private var scheduleSettings: ScheduleSettings?
    
    // Error simulation flags
    var shouldThrowError = false
    var shouldThrowSaveError = false
    var shouldThrowLoadError = false
    var shouldThrowDeleteError = false
    var errorToThrow: Error?
    
    // Method call tracking for testing
    var methodCalls: [String] = []
    
    // Mock data for testing
    var mockAppGroups: [AppGroup] = []
    
    // Convenience aliases for testing
    var shouldFailSave: Bool {
        get { shouldThrowSaveError }
        set { shouldThrowSaveError = newValue }
    }
    
    // MARK: - Initialization
    
    init() {
        // Set up default quick actions for testing
        setupDefaultQuickActions()
    }
    
    private func setupDefaultQuickActions() {
        let defaultQuickActions = [
            QuickAction(
                name: "Work Session",
                subtitle: "Productivity focus",
                iconName: "laptopcomputer",
                color: Color.blue,
                duration: 30 * 60 // 30 minutes
            ),
            QuickAction(
                name: "Study Time", 
                subtitle: "Deep learning",
                iconName: "book.fill",
                color: Color.green,
                duration: 60 * 60 // 1 hour
            ),
            QuickAction(
                name: "Break Time",
                subtitle: "Social & entertainment",
                iconName: "cup.and.saucer.fill", 
                color: Color.orange,
                duration: 15 * 60 // 15 minutes
            )
        ]
        
        // Store as JSON data
        do {
            let data = try JSONEncoder().encode(defaultQuickActions)
            keyValueStore["quickActions"] = data
        } catch {
            print("Failed to setup default quick actions: \(error)")
        }
    }
    
    private let queue = DispatchQueue(label: "MockDataPersistenceService", attributes: .concurrent)
    
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
        
        return try await withCheckedThrowingContinuation { continuation in
            queue.async(flags: .barrier) {
                do {
                    let data = try JSONEncoder().encode(object)
                    self.keyValueStore[key] = data
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: AppError.persistenceError("Failed to encode \(key): \(error.localizedDescription)"))
                }
            }
        }
    }
    
    func load<T: Codable & Sendable>(_ type: T.Type, forKey key: String) async throws -> T? {
        if shouldThrowLoadError {
            throw AppError.persistenceError("Mock load error for key: \(key)")
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            queue.async {
                guard let data = self.keyValueStore[key] else {
                    continuation.resume(returning: nil)
                    return
                }
                
                do {
                    let object = try JSONDecoder().decode(type, from: data)
                    continuation.resume(returning: object)
                } catch {
                    continuation.resume(throwing: AppError.persistenceError("Failed to decode \(key): \(error.localizedDescription)"))
                }
            }
        }
    }
    
    func delete(forKey key: String) async throws {
        if shouldThrowDeleteError {
            throw AppError.persistenceError("Mock delete error for key: \(key)")
        }
        
        return try await withCheckedContinuation { continuation in
            queue.async(flags: .barrier) {
                self.keyValueStore.removeValue(forKey: key)
                continuation.resume()
            }
        }
    }
    
    // MARK: - App Group Methods
    
    func saveAppGroup(_ group: AppGroup) async throws {
        trackMethodCall("saveAppGroup")
        try throwErrorIfNeeded()
        
        if shouldThrowSaveError {
            throw AppError.persistenceError("Mock save error for AppGroup: \(group.name)")
        }
        
        return try await withCheckedContinuation { continuation in
            queue.async(flags: .barrier) {
                self.appGroups[group.id] = group
                continuation.resume()
            }
        }
    }
    
    func loadAppGroups() async throws -> [AppGroup] {
        trackMethodCall("loadAppGroups")
        try throwErrorIfNeeded()
        
        if shouldThrowLoadError {
            throw AppError.persistenceError("Mock load error for AppGroups")
        }
        
        return try await withCheckedContinuation { continuation in
            queue.async {
                // Return mock data if available, otherwise return stored data
                if !self.mockAppGroups.isEmpty {
                    continuation.resume(returning: self.mockAppGroups)
                } else {
                    let groups = Array(self.appGroups.values).sorted { $0.name < $1.name }
                    continuation.resume(returning: groups)
                }
            }
        }
    }
    
    func deleteAppGroup(_ id: UUID) async throws {
        trackMethodCall("deleteAppGroup")
        try throwErrorIfNeeded()
        
        if shouldThrowDeleteError {
            throw AppError.persistenceError("Mock delete error for AppGroup: \(id)")
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            queue.async(flags: .barrier) {
                guard self.appGroups[id] != nil else {
                    continuation.resume(throwing: AppError.dataNotFound("AppGroup with ID \(id)"))
                    return
                }
                
                self.appGroups.removeValue(forKey: id)
                continuation.resume()
            }
        }
    }
    
    // MARK: - Schedule Settings Methods
    
    func saveScheduleSettings(_ settings: ScheduleSettings) async throws {
        trackMethodCall("saveScheduleSettings")
        try throwErrorIfNeeded()
        
        if shouldThrowSaveError {
            throw AppError.persistenceError("Mock save error for ScheduleSettings")
        }
        
        return try await withCheckedContinuation { continuation in
            queue.async(flags: .barrier) {
                self.scheduleSettings = settings
                continuation.resume()
            }
        }
    }
    
    func loadScheduleSettings() async throws -> ScheduleSettings? {
        if shouldThrowLoadError {
            throw AppError.persistenceError("Mock load error for ScheduleSettings")
        }
        
        return try await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: self.scheduleSettings)
            }
        }
    }
    
    // MARK: - Intention Session Methods
    
    func saveIntentionSession(_ session: IntentionSession) async throws {
        if shouldThrowSaveError {
            throw AppError.persistenceError("Mock save error for IntentionSession: \(session.id)")
        }
        
        return try await withCheckedContinuation { continuation in
            queue.async(flags: .barrier) {
                self.intentionSessions[session.id] = session
                continuation.resume()
            }
        }
    }
    
    func loadIntentionSessions() async throws -> [IntentionSession] {
        if shouldThrowLoadError {
            throw AppError.persistenceError("Mock load error for IntentionSessions")
        }
        
        return try await withCheckedContinuation { continuation in
            queue.async {
                let sessions = Array(self.intentionSessions.values).sorted { $0.startTime > $1.startTime }
                continuation.resume(returning: sessions)
            }
        }
    }
    
    func deleteIntentionSession(_ id: UUID) async throws {
        if shouldThrowDeleteError {
            throw AppError.persistenceError("Mock delete error for IntentionSession: \(id)")
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            queue.async(flags: .barrier) {
                guard self.intentionSessions[id] != nil else {
                    continuation.resume(throwing: AppError.dataNotFound("IntentionSession with ID \(id)"))
                    return
                }
                
                self.intentionSessions.removeValue(forKey: id)
                continuation.resume()
            }
        }
    }
    
    func clearExpiredSessions() async throws {
        if shouldThrowDeleteError {
            throw AppError.persistenceError("Mock error clearing expired sessions")
        }
        
        return try await withCheckedContinuation { continuation in
            queue.async(flags: .barrier) {
                let cutoffDate = Date().addingTimeInterval(-24 * 60 * 60 * 7) // 7 days ago
                
                let expiredSessionIds = self.intentionSessions.values
                    .filter { $0.startTime < cutoffDate }
                    .map(\.id)
                
                for id in expiredSessionIds {
                    self.intentionSessions.removeValue(forKey: id)
                }
                
                continuation.resume()
            }
        }
    }
    
    // MARK: - Test Helper Methods
    
    func reset() async {
        await withCheckedContinuation { continuation in
            queue.async(flags: .barrier) {
                self.keyValueStore.removeAll()
                self.appGroups.removeAll()
                self.intentionSessions.removeAll()
                self.scheduleSettings = nil
                self.shouldThrowError = false
                self.shouldThrowSaveError = false
                self.shouldThrowLoadError = false
                self.shouldThrowDeleteError = false
                self.errorToThrow = nil
                self.methodCalls.removeAll()
                self.mockAppGroups.removeAll()
                continuation.resume()
            }
        }
    }
    
    func getStoredAppGroupCount() async -> Int {
        await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: self.appGroups.count)
            }
        }
    }
    
    func getStoredSessionCount() async -> Int {
        await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: self.intentionSessions.count)
            }
        }
    }
    
    func hasScheduleSettings() async -> Bool {
        await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: self.scheduleSettings != nil)
            }
        }
    }
    
    func getAppGroup(id: UUID) async -> AppGroup? {
        await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: self.appGroups[id])
            }
        }
    }
    
    func getSession(id: UUID) async -> IntentionSession? {
        await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: self.intentionSessions[id])
            }
        }
    }
}
