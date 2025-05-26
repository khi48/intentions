// Services/ScreenTimeUIAdapter.swift
// UI Integration Layer for Screen Time Service

import Foundation
@preconcurrency import FamilyControls
@preconcurrency import ManagedSettings

/// Observable wrapper for ScreenTimeService to enable SwiftUI integration
/// This is where @MainActor is appropriate - for UI state management only
@MainActor
@Observable
final class ScreenTimeUIAdapter<Service: ScreenTimeManaging> {
    private let service: Service
    
    // UI-relevant state that needs to be on MainActor
    var isLoading: Bool = false
    var lastError: AppError?
    var statusInfo: ScreenTimeStatusInfo?
    
    init(service: Service) {
        self.service = service
    }
    
    // MARK: - UI-Optimized Methods (MainActor appropriate for UI updates)
    
    func requestAuthorization() async {
        isLoading = true
        lastError = nil
        
        let success = try await service.requestAuthorization()
        
        isLoading = false
        if !success {
            lastError = .screenTimeAuthorizationFailed
        }
        
        await updateStatusInfo()
    }
    
    func blockAllApps() async {
        isLoading = true
        lastError = nil
        
        do {
            try await service.blockAllApps()
        } catch let error as AppError {
            lastError = error
        } catch {
            lastError = .appBlockingFailed(error.localizedDescription)
        }
        
        isLoading = false
        await updateStatusInfo()
    }
    
    func allowApps(_ tokens: sending Set<ApplicationToken>, categories: Set<ActivityCategoryToken> = [], duration: TimeInterval) async {
        isLoading = true
        lastError = nil
        
        do {
            try await service.allowApps(tokens, categories: categories, duration: duration)
        } catch let error as AppError {
            lastError = error
        } catch {
            lastError = .appBlockingFailed(error.localizedDescription)
        }
        
        isLoading = false
        await updateStatusInfo()
    }
    
    func initialize() async {
        isLoading = true
        lastError = nil
        
        do {
            try await service.initialize()
        } catch let error as AppError {
            lastError = error
        } catch {
            lastError = .appBlockingFailed(error.localizedDescription)
        }
        
        isLoading = false
        await updateStatusInfo()
    }
    
    // MARK: - Direct Service Access (when UI state not needed)
    
    func getService() -> Service {
        return service
    }
    
    // MARK: - Private Helpers
    
    private func updateStatusInfo() async {
        statusInfo = await service.getStatusInfo()
    }
}

// MARK: - Convenience Type Aliases

/// Type alias for production usage with real ScreenTimeService
//typealias ProductionScreenTimeUIAdapter = ScreenTimeUIAdapter<ScreenTimeService>
//
///// Type alias for testing usage with MockScreenTimeService
//typealias MockScreenTimeUIAdapter = ScreenTimeUIAdapter<MockScreenTimeService>Loading: Bool = false
//    var lastError: AppError?
//    var statusInfo: ScreenTimeStatusInfo?
//    
//    init<T: ScreenTimeManaging>(service: T) {
//        self.service = service
//    }
//    
//    // MARK: - UI-Optimized Methods (MainActor appropriate for UI updates)
//    
//    func requestAuthorization() async {
//        isLoading = true
//        lastError = nil
//        
//        let success = await service.requestAuthorization()
//        
//        isLoading = false
//        if !success {
//            lastError = .screenTimeAuthorizationFailed
//        }
//        
//        await updateStatusInfo()
//    }
//    
//    func blockAllApps() async {
//        isLoading = true
//        lastError = nil
//        
//        do {
//            try await service.blockAllApps()
//        } catch let error as AppError {
//            lastError = error
//        } catch {
//            lastError = .appBlockingFailed(error.localizedDescription)
//        }
//        
//        isLoading = false
//        await updateStatusInfo()
//    }
//    
//    func allowApps(_ tokens: sending Set<ApplicationToken>, duration: TimeInterval) async {
//        isLoading = true
//        lastError = nil
//        
//        do {
//            try await service.allowApps(tokens, categories: [], duration: duration)
//        } catch let error as AppError {
//            lastError = error
//        } catch {
//            lastError = .appBlockingFailed(error.localizedDescription)
//        }
//        
//        isLoading = false
//        await updateStatusInfo()
//    }
//    
//    func initialize() async {
//        isLoading = true
//        lastError = nil
//        
//        do {
//            try await service.initialize()
//        } catch let error as AppError {
//            lastError = error
//        } catch {
//            lastError = .appBlockingFailed(error.localizedDescription)
//        }
//        
//        isLoading = false
//        await updateStatusInfo()
//    }
//    
//    // MARK: - Direct Service Access (when UI state not needed)
//    
//    func getService() -> ScreenTimeManaging {
//        return service
//    }
//    
//    // MARK: - Private Helpers
//    
//    private func updateStatusInfo() async {
//        statusInfo = await service.getStatusInfo()
//    }
//}
