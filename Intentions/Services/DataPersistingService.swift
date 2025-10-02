import Foundation
import SwiftData
import FamilyControls
import ManagedSettings

// MARK: - Data Persistence Protocol
protocol DataPersisting: Sendable {
    func save<T: Codable & Sendable>(_ object: T, forKey key: String) async throws
    func load<T: Codable & Sendable>(_ type: T.Type, forKey key: String) async throws -> T?
    func delete(forKey key: String) async throws
    func saveAppGroup(_ group: AppGroup) async throws
    func loadAppGroups() async throws -> [AppGroup]
    func deleteAppGroup(_ id: UUID) async throws
    func saveScheduleSettings(_ settings: ScheduleSettings) async throws
    func loadScheduleSettings() async throws -> ScheduleSettings?
    func saveIntentionSession(_ session: IntentionSession) async throws
    func loadIntentionSessions() async throws -> [IntentionSession]
    func deleteIntentionSession(_ id: UUID) async throws
    func clearExpiredSessions() async throws
}

// MARK: - Model Actor for Thread-Safe SwiftData Access
@ModelActor
actor DataModelActor {
    func saveAppGroup(_ group: AppGroup) throws {
        print("💾 MODEL ACTOR: Saving app group '\(group.name)'")
        
        // Check if group already exists and update it
        let descriptor = FetchDescriptor<PersistentAppGroup>()
        let allGroups = try modelContext.fetch(descriptor)
        let existingGroups = allGroups.filter { $0.id == group.id }
        
        if let existingGroup = existingGroups.first {
            print("🔄 MODEL ACTOR: Updating existing group")
            existingGroup.update(from: group)
        } else {
            print("➕ MODEL ACTOR: Inserting new group")
            let persistentGroup = PersistentAppGroup(from: group)
            modelContext.insert(persistentGroup)
        }
        
        try modelContext.save()
        print("✅ MODEL ACTOR: Successfully saved app group '\(group.name)'")
    }
    
    func loadAppGroups() throws -> [AppGroup] {
        print("📖 MODEL ACTOR: Loading app groups from SwiftData")
        let descriptor = FetchDescriptor<PersistentAppGroup>(
            sortBy: [SortDescriptor(\.name)]
        )
        let persistentGroups = try modelContext.fetch(descriptor)
        let appGroups = persistentGroups.compactMap { $0.toAppGroup() }
        print("✅ MODEL ACTOR: Successfully loaded \(appGroups.count) app groups")
        return appGroups
    }
    
    func deleteAppGroup(_ id: UUID) throws {
        let descriptor = FetchDescriptor<PersistentAppGroup>()
        let allGroups = try modelContext.fetch(descriptor)
        let matchingGroups = allGroups.filter { $0.id == id }
        
        if let group = matchingGroups.first {
            modelContext.delete(group)
            try modelContext.save()
            print("✅ MODEL ACTOR: Successfully deleted app group")
        } else {
            throw AppError.persistenceError("AppGroup with ID \(id) not found")
        }
    }
}

// MARK: - Data Persistence Service Implementation
final class DataPersistenceService: DataPersisting, @unchecked Sendable {
    private let modelContainer: ModelContainer
    private let dataActor: DataModelActor
    private let modelContext: ModelContext // For non-app-group operations (will be replaced with more actors)
    
    // UserDefaults for simple key-value storage
    private let userDefaults = UserDefaults.standard
    
    // MARK: - Private Methods

    /// Get the App Group container URL for shared data storage
    /// Creates the directory if it doesn't exist
    private static func getAppGroupContainerURL() -> URL {
        let appGroupID = "group.oh.Intentions"

        // Try to get App Group container URL
        if let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) {
            // Return the container URL directly - SwiftData will handle its own subdirectories
            print("✅ DATA PERSISTENCE: App Group container ready at \(containerURL.path)")
            return containerURL
        } else {
            print("⚠️ DATA PERSISTENCE: App Group container not available")
            print("🔄 DATA PERSISTENCE: Falling back to Documents directory")
        }

        // Fallback to Documents directory
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!

        print("✅ DATA PERSISTENCE: Fallback container ready at \(documentsURL.path)")
        return documentsURL
    }

    // MARK: - Initialization
    init(container: ModelContainer? = nil) throws {
        print("🚀 DATA PERSISTENCE: Initializing DataPersistenceService")
        
        let schema = Schema([
            PersistentAppGroup.self,
            PersistentIntentionSession.self,
            PersistentScheduleSettings.self
        ])
        
        // Get App Group container URL for shared data access
        let appGroupURL = Self.getAppGroupContainerURL()

        // Create the Library/Application Support directory that SwiftData expects
        let libraryURL = appGroupURL.appendingPathComponent("Library").appendingPathComponent("Application Support")
        do {
            try FileManager.default.createDirectory(at: libraryURL, withIntermediateDirectories: true, attributes: nil)
            print("✅ DATA PERSISTENCE: Library/Application Support directory created at \(libraryURL.path)")

            // List what's in the directory after creation
            let contents = try FileManager.default.contentsOfDirectory(at: libraryURL, includingPropertiesForKeys: nil)
            print("📁 DATA PERSISTENCE: Directory contents: \(contents.map { $0.lastPathComponent })")
        } catch {
            print("⚠️ DATA PERSISTENCE: Failed to create Library/Application Support directory: \(error)")
        }

        // Use SwiftData's default configuration with App Group container
        // This will create "default.store" which SwiftData expects
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            groupContainer: .identifier("group.oh.Intentions")
            // Temporarily disable CloudKit to isolate the issue
            // cloudKitDatabase: .private("IntentionsAppDatabase")
        )

        print("🔧 DATA PERSISTENCE: Schema configured with \(schema.entities.count) entities")
        print("💾 DATA PERSISTENCE: Using persistent storage (CloudKit temporarily disabled)")

        if let container = container {
            // Use provided test container
            print("🧪 DATA PERSISTENCE: Using provided test container")
            self.modelContainer = container
            self.dataActor = DataModelActor(modelContainer: container)
            self.modelContext = ModelContext(container)
        } else {
            // Production initialization with ModelActor for thread safety
            do {
                print("🏗️ DATA PERSISTENCE: Creating production ModelContainer")
                self.modelContainer = try ModelContainer(
                    for: schema,
                    configurations: [modelConfiguration]
                )
                self.dataActor = DataModelActor(modelContainer: modelContainer)
                self.modelContext = ModelContext(modelContainer)
                print("✅ DATA PERSISTENCE: Successfully initialized with ModelActor")

                // Check if the database file was created
                let expectedDatabasePath = libraryURL.appendingPathComponent("default.store")
                if FileManager.default.fileExists(atPath: expectedDatabasePath.path) {
                    print("✅ DATA PERSISTENCE: Database file created at \(expectedDatabasePath.path)")
                } else {
                    print("⚠️ DATA PERSISTENCE: Database file not found at expected location: \(expectedDatabasePath.path)")

                    // Check what files were actually created
                    do {
                        let contents = try FileManager.default.contentsOfDirectory(at: libraryURL, includingPropertiesForKeys: nil)
                        print("📁 DATA PERSISTENCE: Actual directory contents after init: \(contents.map { $0.lastPathComponent })")
                    } catch {
                        print("❌ DATA PERSISTENCE: Failed to list directory contents: \(error)")
                    }
                }
            } catch {
                print("❌ DATA PERSISTENCE: Failed to initialize: \(error)")
                throw AppError.dataInitializationFailed(error.localizedDescription)
            }
        }
    }
    
    // MARK: - Generic Storage Methods (UserDefaults-based)
    func save<T: Codable & Sendable>(_ object: T, forKey key: String) async throws {
        // Validate key
        guard !key.isEmpty else {
            throw AppError.validationFailed("key", reason: "Storage key cannot be empty")
        }
        
        // Use prefixed key for namespace safety
        let prefixedKey = key.prefixedKey
        
        // Perform encoding and storage on a background queue for consistency
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .utility).async {
                do {
                    let encoder = JSONEncoder()
                    encoder.dateEncodingStrategy = .iso8601
                    let data = try encoder.encode(object)
                    
                    // Validate data size
                    guard data.count <= AppConstants.Storage.maxExportFileSize else {
                        continuation.resume(throwing: AppError.persistenceError("Data size exceeds maximum allowed"))
                        return
                    }
                    
                    // Store on main queue (UserDefaults is thread-safe but for consistency)
                    DispatchQueue.main.async {
                        self.userDefaults.set(data, forKey: prefixedKey)
                        continuation.resume()
                    }
                } catch {
                    continuation.resume(throwing: AppError.persistenceError("Failed to save \(key): \(error.localizedDescription)"))
                }
            }
        }
    }
    
    func load<T: Codable & Sendable>(_ type: T.Type, forKey key: String) async throws -> T? {
        // Validate key
        guard !key.isEmpty else {
            throw AppError.validationFailed("key", reason: "Storage key cannot be empty")
        }
        
        let prefixedKey = key.prefixedKey
        
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<T?, Error>) in
            DispatchQueue.global(qos: .utility).async {
                guard let data = self.userDefaults.data(forKey: prefixedKey) else {
                    continuation.resume(returning: nil)
                    return
                }
                
                do {
                    let decoder = JSONDecoder()
                    decoder.dateDecodingStrategy = .iso8601
                    let object = try decoder.decode(type, from: data)
                    continuation.resume(returning: object)
                } catch {
                    continuation.resume(throwing: AppError.persistenceError("Failed to load \(key): \(error.localizedDescription)"))
                }
            }
        }
    }
    
    func delete(forKey key: String) async throws {
        guard !key.isEmpty else {
            throw AppError.validationFailed("key", reason: "Storage key cannot be empty")
        }
        
        let prefixedKey = key.prefixedKey
        
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.main.async {
                self.userDefaults.removeObject(forKey: prefixedKey)
                continuation.resume()
            }
        }
    }
    
    // MARK: - App Group Methods
    func saveAppGroup(_ group: AppGroup) async throws {
        do {
            try await dataActor.saveAppGroup(group)
        } catch {
            print("❌ DATA PERSISTENCE: Failed to save app group: \(error)")
            throw AppError.persistenceError("Failed to save AppGroup \(group.name): \(error.localizedDescription)")
        }
    }
    
    func loadAppGroups() async throws -> [AppGroup] {
        do {
            return try await dataActor.loadAppGroups()
        } catch {
            print("❌ DATA PERSISTENCE: Failed to load app groups: \(error)")
            throw AppError.persistenceError("Failed to load AppGroups: \(error.localizedDescription)")
        }
    }
    
    func deleteAppGroup(_ id: UUID) async throws {
        do {
            try await dataActor.deleteAppGroup(id)
        } catch {
            print("❌ DATA PERSISTENCE: Failed to delete app group: \(error)")
            throw AppError.persistenceError("Failed to delete AppGroup: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Schedule Settings Methods
    @MainActor
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
    
    @MainActor
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
    @MainActor
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
    
    @MainActor
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
    
    @MainActor
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
    
    @MainActor
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

