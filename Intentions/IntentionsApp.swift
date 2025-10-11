//
//  IntentionsApp.swift
//  Intentions
//
//  Created by Kieran Hitchcock on 26/05/25.
//

import SwiftUI

@main
struct IntentionsApp: App {
    let persistenceController = PersistenceController.shared

    init() {
        // Initialize crash reporting
        CrashReporting.initialize()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                .environmentObject(ScheduleManager(persistenceController: persistenceController))
                .environmentObject(GroupManager(persistenceController: persistenceController))
                .onAppear {
                        #if DEBUG
                        clearCoreDataCache()
                        #endif
                    }
        }
    }
    
    #if DEBUG
    func clearCoreDataCache() {
        let coordinator = persistenceController.container.persistentStoreCoordinator
        
        for store in coordinator.persistentStores {
            try? coordinator.remove(store)
        }
        
        let storeURL = persistenceController.container.persistentStoreDescriptions.first?.url
        if let url = storeURL {
            try? FileManager.default.removeItem(at: url)
            try? FileManager.default.removeItem(at: url.appendingPathExtension("shm"))
            try? FileManager.default.removeItem(at: url.appendingPathExtension("wal"))
        }
        
        persistenceController.container.loadPersistentStores { _, error in
            if let error = error {
                print("Error reloading store: \(error)")
            }
        }
    }
    #endif
}
