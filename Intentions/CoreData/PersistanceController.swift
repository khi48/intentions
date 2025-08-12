// PersistenceController.swift
// Centralized CoreData stack setup for the Intentions app, managing AppGroup and GroupSchedule entities.

import CoreData

class PersistenceController {
    // MARK: - Properties
    @MainActor static let shared = PersistenceController()
    
    static var testController: PersistenceController {
        PersistenceController(inMemory: true)
    }
    
    static var diskTestController: PersistenceController {
        PersistenceController(inMemory: false, useTestStore: true)
    }
    
    let container: NSPersistentContainer
    private let isTestStore: Bool
    private let storeURL: URL?
    private let storeQueue = DispatchQueue(label: "com.intentions.persistencecontroller.store")
    
    // MARK: - Initialization
    private init(inMemory: Bool = false, useTestStore: Bool = false) {
        
//        #if DEBUG
//            // Clear cache BEFORE loading persistent stores
//            Self.clearCoreDataFiles()
//        #endif
        
        container = NSPersistentContainer(name: "IntentionsModel")
        
        
        self.isTestStore = inMemory || useTestStore
        
        if inMemory {
            let description = NSPersistentStoreDescription()
            description.type = NSInMemoryStoreType
            container.persistentStoreDescriptions = [description]
            self.storeURL = nil
        } else if useTestStore {
            let tempDir = FileManager.default.temporaryDirectory
            let storeURL = tempDir.appendingPathComponent("IntentionsTest.sqlite")
            // Ensure temporary directory exists
            do {
                try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true, attributes: nil)
                // Clean up any existing corrupted files
                try? FileManager.default.removeItem(at: storeURL)
                try? FileManager.default.removeItem(at: storeURL.appendingPathExtension("sqlite-shm"))
                try? FileManager.default.removeItem(at: storeURL.appendingPathExtension("sqlite-wal"))
            } catch {
                fatalError("Failed to prepare temporary directory: \(error)")
            }
            let description = NSPersistentStoreDescription(url: storeURL)
            description.type = NSSQLiteStoreType
            container.persistentStoreDescriptions = [description]
            self.storeURL = storeURL
        } else {
            self.storeURL = nil
        }
        
        // Load stores synchronously with error handling
        var loadError: Error?
        storeQueue.sync {
            container.loadPersistentStores { _, error in
                loadError = error
            }
        }
        if let error = loadError {
            print("Failed to load CoreData store:")
            fatalError("Unresolved error \(error)")

//            #if DEBUG
//            // If loading fails, try one more time after clearing
//            print("🔄 Attempting to recover from corrupted database...")
//            Self.clearCoreDataFiles()
//            fatalError("Database corrupted - please restart app after clearing")
//            #else
//            fatalError("Unresolved error \(error), \(error.userInfo)")
//            #endif
        
        }
        
        container.viewContext.automaticallyMergesChangesFromParent = true
    }
    
    #if DEBUG
    static private func clearCoreDataFiles() {
        print("🔥 Attempting to clear corrupted Core Data files...")
        
        let fileManager = FileManager.default
        
        // Get all possible Core Data file locations
        let urls = [
            fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first,
            fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
        ].compactMap { $0 }
        
        for baseURL in urls {
            do {
                let contents = try fileManager.contentsOfDirectory(at: baseURL, includingPropertiesForKeys: nil)
                for url in contents {
                    let filename = url.lastPathComponent
                    if filename.contains("IntentionsModel") &&
                       (filename.hasSuffix(".sqlite") ||
                        filename.hasSuffix(".sqlite-shm") ||
                        filename.hasSuffix(".sqlite-wal")) {
                        print("🗑️ Removing corrupted file: \(filename)")
                        try fileManager.removeItem(at: url)
                    }
                }
            } catch {
                print("Error clearing directory \(baseURL): \(error)")
            }
        }
        
        print("✅ Corrupted Core Data files cleared")
    }
    #endif
        
    
    // MARK: - Cleanup
    func resetTestStore() throws {
        guard isTestStore else { return }
        
        try storeQueue.sync {
            let coordinator = container.persistentStoreCoordinator
            for store in coordinator.persistentStores {
                guard let storeURL = store.url else { continue }
                // Destroy store to close SQLite connections
                do {
                    try coordinator.destroyPersistentStore(at: storeURL, ofType: store.type, options: nil)
                } catch {
                    print("Failed to destroy store at \(storeURL): \(error)")
                }
                // Remove store from coordinator
                try coordinator.remove(store)
                // Delete SQLite files if disk-based
                if store.type == NSSQLiteStoreType, FileManager.default.fileExists(atPath: storeURL.path) {
                    try FileManager.default.removeItem(at: storeURL)
                    try? FileManager.default.removeItem(at: storeURL.appendingPathExtension("sqlite-shm"))
                    try? FileManager.default.removeItem(at: storeURL.appendingPathExtension("sqlite-wal"))
                }
            }
            
            // Clear viewContext
            container.viewContext.reset()
            
            // Recreate store for disk-based tests
            if let storeURL = storeURL, !isTestStoreInMemory() {
                let description = NSPersistentStoreDescription(url: storeURL)
                description.type = NSSQLiteStoreType
                container.persistentStoreDescriptions = [description]
                var loadError: Error?
                container.loadPersistentStores { _, error in
                    loadError = error
                }
                if let error = loadError {
                    throw error
                }
            }
        }
    }
    
    // MARK: - Helpers
    private func isTestStoreInMemory() -> Bool {
        container.persistentStoreDescriptions.contains { $0.type == NSInMemoryStoreType }
    }
    
    // MARK: - Deinitialization
    deinit {
        if isTestStore {
            do {
                try resetTestStore()
            } catch {
                print("Failed to reset test store during deinit: \(error)")
            }
        }
    }
}
