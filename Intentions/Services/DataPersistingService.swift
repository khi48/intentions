import Foundation
import SwiftData
import FamilyControls
import ManagedSettings

// MARK: - Data Persistence Protocol
protocol DataPersisting: Sendable {
    func save<T: Codable & Sendable>(_ object: T, forKey key: String) async throws
    func load<T: Codable & Sendable>(_ type: T.Type, forKey key: String) async throws -> T?
    func delete(forKey key: String) async throws
    func saveScheduleSettings(_ settings: ScheduleSettings) async throws
    func loadScheduleSettings() async throws -> ScheduleSettings?
    func saveIntentionSession(_ session: IntentionSession) async throws
    func loadIntentionSessions() async throws -> [IntentionSession]
    func loadIntentionSessionsSince(_ date: Date) async throws -> [IntentionSession]
    func deleteIntentionSession(_ id: UUID) async throws
    func clearExpiredSessions() async throws
}

// MARK: - Model Actor for Thread-Safe SwiftData Access
// Note: Currently unused but kept for future expansion
@ModelActor
actor DataModelActor {
    // Reserved for future use with additional models
}

// MARK: - Data Persistence Service Implementation
@MainActor final class DataPersistenceService: DataPersisting, Sendable {
    private let modelContainer: ModelContainer
    private let dataActor: DataModelActor
    private let modelContext: ModelContext // For non-app-group operations (will be replaced with more actors)
    
    // UserDefaults for simple key-value storage
    private let userDefaults = UserDefaults.standard
    
    // MARK: - Private Methods

    /// Get the App Group container URL for shared data storage
    /// Creates the directory if it doesn't exist
    private static func getAppGroupContainerURL() -> URL {
        let appGroupID = AppConstants.appGroupId

        // Try to get App Group container URL
        if let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) {
            // Return the container URL directly - SwiftData will handle its own subdirectories
            return containerURL
        }

        // Fallback to Documents directory
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    }

    // MARK: - Initialization
    init(container: ModelContainer? = nil) throws {
        let schema = Schema([
            PersistentIntentionSession.self,
            PersistentScheduleSettings.self
        ])

        // Get App Group container URL for shared data access
        let appGroupURL = Self.getAppGroupContainerURL()

        // Create the Library/Application Support directory that SwiftData expects
        let libraryURL = appGroupURL.appendingPathComponent("Library").appendingPathComponent("Application Support")
        try? FileManager.default.createDirectory(at: libraryURL, withIntermediateDirectories: true, attributes: nil)

        // Use SwiftData's default configuration with App Group container
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            groupContainer: .identifier(AppConstants.appGroupId)
        )

        if let container = container {
            // Use provided test container
            self.modelContainer = container
            self.dataActor = DataModelActor(modelContainer: container)
            self.modelContext = ModelContext(container)
        } else {
            // Production initialization
            do {
                self.modelContainer = try ModelContainer(
                    for: schema,
                    configurations: [modelConfiguration]
                )
                self.dataActor = DataModelActor(modelContainer: modelContainer)
                self.modelContext = ModelContext(modelContainer)
            } catch {
                throw AppError.dataInitializationFailed(error.localizedDescription)
            }
        }
    }
    
    // MARK: - Generic Storage Methods (UserDefaults-based)
    func save<T: Codable & Sendable>(_ object: T, forKey key: String) async throws {
        guard !key.isEmpty else {
            throw AppError.validationFailed("key", reason: "Storage key cannot be empty")
        }
        let prefixedKey = key.prefixedKey
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(object)
        guard data.count <= AppConstants.Storage.maxExportFileSize else {
            throw AppError.persistenceError("Data size exceeds maximum allowed")
        }
        userDefaults.set(data, forKey: prefixedKey)
    }
    
    func load<T: Codable & Sendable>(_ type: T.Type, forKey key: String) async throws -> T? {
        guard !key.isEmpty else {
            throw AppError.validationFailed("key", reason: "Storage key cannot be empty")
        }
        let prefixedKey = key.prefixedKey
        guard let data = userDefaults.data(forKey: prefixedKey) else {
            return nil
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(type, from: data)
    }
    
    func delete(forKey key: String) async throws {
        guard !key.isEmpty else {
            throw AppError.validationFailed("key", reason: "Storage key cannot be empty")
        }
        userDefaults.removeObject(forKey: key.prefixedKey)
    }
    
    // MARK: - Schedule Settings Methods
    func saveScheduleSettings(_ settings: ScheduleSettings) async throws {
        do {
            let persistentSettings = PersistentScheduleSettings(from: settings)
            
            // Remove existing settings (there should only be one)
            let descriptor = FetchDescriptor<PersistentScheduleSettings>()
            let existingSettings = try modelContext.fetch(descriptor)
            
            for existing in existingSettings {
                modelContext.delete(existing)
            }
            
            modelContext.insert(persistentSettings)
            try modelContext.save()
        } catch {
            throw AppError.persistenceError("Failed to save ScheduleSettings: \(error.localizedDescription)")
        }
    }
    
    func loadScheduleSettings() async throws -> ScheduleSettings? {
        do {
            let descriptor = FetchDescriptor<PersistentScheduleSettings>()
            let persistentSettings = try modelContext.fetch(descriptor)
            
            return persistentSettings.first?.toScheduleSettings()
        } catch {
            throw AppError.persistenceError("Failed to load ScheduleSettings: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Intention Session Methods
    func saveIntentionSession(_ session: IntentionSession) async throws {
        do {
            let persistentSession = PersistentIntentionSession(from: session)
            
            // Check if session already exists and update it - load all sessions and filter in memory
            let descriptor = FetchDescriptor<PersistentIntentionSession>()
            let allSessions = try modelContext.fetch(descriptor)
            let existingSessions = allSessions.filter { $0.id == session.id }
            
            if let existingSession = existingSessions.first {
                existingSession.update(from: session)
            } else {
                modelContext.insert(persistentSession)
            }
            
            try modelContext.save()
        } catch {
            throw AppError.persistenceError("Failed to save IntentionSession \(session.id): \(error.localizedDescription)")
        }
    }
    
    func loadIntentionSessions() async throws -> [IntentionSession] {
        do {
            let descriptor = FetchDescriptor<PersistentIntentionSession>(
                sortBy: [SortDescriptor(\.startTime, order: .reverse)]
            )
            
            let persistentSessions = try modelContext.fetch(descriptor)
            return persistentSessions.compactMap { $0.toIntentionSession() }
        } catch {
            throw AppError.persistenceError("Failed to load IntentionSessions: \(error.localizedDescription)")
        }
    }
    
    func loadIntentionSessionsSince(_ date: Date) async throws -> [IntentionSession] {
        do {
            let descriptor = FetchDescriptor<PersistentIntentionSession>(
                sortBy: [SortDescriptor(\.startTime, order: .reverse)]
            )
            let persistentSessions = try modelContext.fetch(descriptor)
            return persistentSessions
                .filter { $0.startTime >= date }
                .compactMap { $0.toIntentionSession() }
        } catch {
            throw AppError.persistenceError("Failed to load IntentionSessions: \(error.localizedDescription)")
        }
    }

    func deleteIntentionSession(_ id: UUID) async throws {
        do {
            // Load all sessions and filter in memory to avoid predicate issues
            let descriptor = FetchDescriptor<PersistentIntentionSession>()
            let allSessions = try modelContext.fetch(descriptor)
            let sessions = allSessions.filter { $0.id == id }
            
            guard let session = sessions.first else {
                throw AppError.dataNotFound("IntentionSession with ID \(id)")
            }
            
            modelContext.delete(session)
            try modelContext.save()
        } catch let error as AppError {
            throw error
        } catch {
            throw AppError.persistenceError("Failed to delete IntentionSession \(id): \(error.localizedDescription)")
        }
    }
    
    func clearExpiredSessions() async throws {
        do {
            // Load all sessions and filter in memory to avoid SwiftData predicate issues
            let descriptor = FetchDescriptor<PersistentIntentionSession>()
            let allSessions = try modelContext.fetch(descriptor)
            
            // Calculate cutoff date (7 days ago)
            let cutoffDate = Date().addingTimeInterval(-AppConstants.DataCleanup.retentionInterval)
            
            // Filter expired sessions in memory
            let expiredSessions = allSessions.filter { session in
                session.startTime < cutoffDate
            }
            
            for session in expiredSessions {
                modelContext.delete(session)
            }
            
            try modelContext.save()
        } catch {
            throw AppError.persistenceError("Failed to clear expired sessions: \(error.localizedDescription)")
        }
    }
}

