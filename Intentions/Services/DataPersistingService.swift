import Foundation
import SwiftData
import FamilyControls
import ManagedSettings
#if DEBUG
import os // DEBUG-PROBE #16: remove with probe block in mirrorIntentionQuoteToSharedDefaults
#endif

// MARK: - Data Persistence Protocol
protocol DataPersisting: Sendable {
    func save<T: Codable & Sendable>(_ object: T, forKey key: String) async throws
    func load<T: Codable & Sendable>(_ type: T.Type, forKey key: String) async throws -> T?
    func delete(forKey key: String) async throws
    func saveScheduleSettings(_ settings: ScheduleSettings) async throws
    func loadScheduleSettings() async throws -> ScheduleSettings?
    func saveWeeklySchedule(_ schedule: WeeklySchedule) async throws
    func loadWeeklySchedule() async throws -> WeeklySchedule?
    func saveIntentionSession(_ session: IntentionSession) async throws
    func loadIntentionSessions() async throws -> [IntentionSession]
    func loadIntentionSessionsSince(_ date: Date) async throws -> [IntentionSession]
    func deleteIntentionSession(_ id: UUID) async throws
    func clearExpiredSessions() async throws
}

// MARK: - Data Persistence Service Implementation
@MainActor final class DataPersistenceService: DataPersisting, Sendable {
    private let modelContainer: ModelContainer
    private let modelContext: ModelContext

    /// Standard-suite UserDefaults. Used for the generic `save(_:forKey:)` /
    /// `load(_:forKey:)` API, the per-install backfill flag, and as the
    /// **source** of the one-shot legacy `WeeklySchedule` migration that
    /// hoists the canonical blob into the App Group suite. Never the
    /// canonical store for `WeeklySchedule` — that lives in `appGroupDefaults`.
    private let userDefaults = UserDefaults.standard

    /// App Group UserDefaults — the canonical store for the unified
    /// `WeeklySchedule` blob (see issue #8). The DAM extension reads schedule
    /// state via `IntentLog.weeklySchedule` (orthogonal), but the main app's
    /// load/save path now writes here so a single store owns the truth.
    private let appGroupDefaults: UserDefaults?

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
    /// - Parameters:
    ///   - container: Optional `ModelContainer` (tests inject in-memory).
    ///   - appGroupSuiteName: Suite name for the canonical `WeeklySchedule`
    ///     store. Defaults to `AppConstants.appGroupId`; tests inject a
    ///     scratch suite to avoid clobbering the real App Group on-device.
    init(
        container: ModelContainer? = nil,
        appGroupSuiteName: String = AppConstants.appGroupId
    ) throws {
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

        // Resolve the App Group UserDefaults handle once, up-front. If the
        // group can't be opened we surface a clear failure rather than
        // silently writing to .standard later.
        self.appGroupDefaults = UserDefaults(suiteName: appGroupSuiteName)
        if appGroupDefaults == nil {
            throw AppError.dataInitializationFailed(
                "Failed to open App Group UserDefaults for suite \(appGroupSuiteName)."
            )
        }

        if let container = container {
            // Use provided test container
            self.modelContainer = container
            self.modelContext = ModelContext(container)
        } else {
            // Production initialization
            do {
                self.modelContainer = try ModelContainer(
                    for: schema,
                    configurations: [modelConfiguration]
                )
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
    
    // MARK: - Weekly Schedule Storage Keys
    /// Canonical key for the unified `WeeklySchedule` blob in App Group
    /// UserDefaults. `.v2` distinguishes from the pre-issue-#8 standard-suite
    /// `.v1`-equivalent key (`legacyStandardSuiteWeeklyScheduleKey` below)
    /// so future schema migrations have a clean version axis to bump.
    static let weeklyScheduleKey = "intentions.weeklySchedule.v2" // gitleaks:allow

    /// Pre-issue-#8 key in `UserDefaults.standard`. Read-only — drained by
    /// the one-shot migration in `loadWeeklySchedule` and then deleted.
    static let legacyStandardSuiteWeeklyScheduleKey = "intentions.weeklySchedule"

    // MARK: - Weekly Schedule Methods
    func saveWeeklySchedule(_ schedule: WeeklySchedule) async throws {
        guard let appGroupDefaults else {
            throw AppError.persistenceError("App Group UserDefaults unavailable.")
        }
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(schedule)
            appGroupDefaults.set(data, forKey: Self.weeklyScheduleKey)
            Self.mirrorIntentionQuoteToSharedDefaults(schedule.intentionQuote)
        } catch {
            throw AppError.persistenceError("Failed to save WeeklySchedule: \(error.localizedDescription)")
        }
    }

    func loadWeeklySchedule() async throws -> WeeklySchedule? {
        guard let appGroupDefaults else {
            throw AppError.persistenceError("App Group UserDefaults unavailable.")
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        // 1. Try the canonical App Group blob first.
        if let data = appGroupDefaults.data(forKey: Self.weeklyScheduleKey) {
            do {
                let schedule = try decoder.decode(WeeklySchedule.self, from: data)
                Self.mirrorIntentionQuoteToSharedDefaults(schedule.intentionQuote)
                DebugBreadcrumbs.record(
                    .weeklyScheduleLoaded,
                    note: "newBlob enabled=\(schedule.isEnabled) intervals=\(schedule.intervals.count)"
                )
                return schedule
            } catch {
                DebugBreadcrumbs.record(.weeklyScheduleLoaded, note: "decodeError: \(error.localizedDescription)")
                throw AppError.persistenceError("Failed to decode WeeklySchedule: \(error.localizedDescription)")
            }
        }

        // 2. One-shot migration: hoist a pre-issue-#8 standard-suite blob into
        //    the App Group suite. Idempotent — once the standard-suite key is
        //    deleted, this branch never runs again. Note that we cannot call
        //    `saveWeeklySchedule` here because the schedule contains an
        //    `@MainActor`-isolated WeeklySchedule that we re-encode straight
        //    from the legacy bytes (no main-actor hop needed).
        if let legacyData = userDefaults.data(forKey: Self.legacyStandardSuiteWeeklyScheduleKey) {
            do {
                let schedule = try decoder.decode(WeeklySchedule.self, from: legacyData)
                appGroupDefaults.set(legacyData, forKey: Self.weeklyScheduleKey)
                userDefaults.removeObject(forKey: Self.legacyStandardSuiteWeeklyScheduleKey)
                Self.mirrorIntentionQuoteToSharedDefaults(schedule.intentionQuote)
                DebugBreadcrumbs.record(
                    .weeklyScheduleLoaded,
                    note: "appGroupMigration enabled=\(schedule.isEnabled) intervals=\(schedule.intervals.count)"
                )
                return schedule
            } catch {
                // Bytes were present but undecodable — surface the error and
                // delete the corrupt legacy blob so we don't loop on it next
                // launch. The user will fall through to a fresh default schedule.
                userDefaults.removeObject(forKey: Self.legacyStandardSuiteWeeklyScheduleKey)
                DebugBreadcrumbs.record(
                    .weeklyScheduleLoaded,
                    note: "decodeError(appGroupMigration): \(error.localizedDescription)"
                )
                throw AppError.persistenceError("Failed to decode legacy WeeklySchedule: \(error.localizedDescription)")
            }
        }

        // 3. Fall back to legacy ScheduleSettings via SwiftData.
        let legacy = try await loadScheduleSettings()
        guard let legacy else {
            DebugBreadcrumbs.record(.weeklyScheduleLoaded, note: "nil (no blob, no legacy)")
            return nil
        }

        // Migrate once and persist so future reads skip this path
        let migrated = WeeklySchedule.migrate(from: legacy)
        try await saveWeeklySchedule(migrated)
        DebugBreadcrumbs.record(
            .weeklyScheduleLoaded,
            note: "legacyMigration enabled=\(migrated.isEnabled) intervals=\(migrated.intervals.count)"
        )
        return migrated
    }

    /// Mirrors the user's intention quote into App Group UserDefaults so the
    /// ShieldConfiguration extension can read it without decoding the full
    /// WeeklySchedule (which lives only in the main app target).
    // DEBUG-PROBE #16: remove when App Group testing infra no longer needed
    #if DEBUG
    private static let appGroupLog = Logger(subsystem: "oh.Intent", category: "appGroup")
    #endif

    private static func mirrorIntentionQuoteToSharedDefaults(_ quote: String?) {
        guard let shared = UserDefaults(suiteName: SharedConstants.appGroupId) else {
            // DEBUG-PROBE #16: remove when App Group testing infra no longer needed
            #if DEBUG
            appGroupLog.error("probe-write: UserDefaults(suiteName:) returned nil — App Group entitlement missing in main app")
            #endif
            return
        }
        let trimmed = quote?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmed, !trimmed.isEmpty {
            shared.set(trimmed, forKey: SharedConstants.ShieldKeys.intentionQuote)
            // DEBUG-PROBE #16: remove when App Group testing infra no longer needed
            #if DEBUG
            appGroupLog.notice("probe-write: key=\(SharedConstants.ShieldKeys.intentionQuote, privacy: .public) action=set length=\(trimmed.count, privacy: .public) prefix=\(String(trimmed.prefix(8)), privacy: .private)")
            #endif
        } else {
            shared.removeObject(forKey: SharedConstants.ShieldKeys.intentionQuote)
            // DEBUG-PROBE #16: remove when App Group testing infra no longer needed
            #if DEBUG
            appGroupLog.notice("probe-write: key=\(SharedConstants.ShieldKeys.intentionQuote, privacy: .public) action=remove")
            #endif
        }
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

