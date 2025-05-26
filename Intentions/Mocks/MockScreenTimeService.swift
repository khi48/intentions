// Mocks/MockScreenTimeService.swift
// Mock Implementation for Testing and Development

import Foundation
@preconcurrency import FamilyControls
@preconcurrency import ManagedSettings

/// Mock implementation of ScreenTimeManaging for testing and development
actor MockScreenTimeService: ScreenTimeManaging {
    
    // MARK: - Mock Properties
    
    private var mockAuthorizationStatus: AuthorizationStatus = .notDetermined
    private var mockCurrentlyAllowedApps: Set<ApplicationToken> = []
    private var mockSystemApps: Set<ApplicationToken> = []
    private var mockSessionTask: Task<Void, Never>?
    private var mockIsInitialized = false
    
    // MARK: - Test Configuration Properties
    
    /// Whether authorization should succeed (for testing failures)
    var shouldSucceedAuthorization: Bool = true
    
    /// Delay for authorization request (for testing loading states)
    var authorizationDelay: TimeInterval = 0.5
    
    // MARK: - Mock Configuration
    
    /// Configure the mock authorization status for testing
    func setMockAuthorizationStatus(_ status: AuthorizationStatus) async {
        mockAuthorizationStatus = status
    }
    
    /// Configure whether authorization should succeed
    func setShouldSucceedAuthorization(_ shouldSucceed: Bool) async {
        shouldSucceedAuthorization = shouldSucceed
    }
    
    /// Configure authorization delay
    func setAuthorizationDelay(_ delay: TimeInterval) async {
        authorizationDelay = delay
    }
    
    /// Add mock system apps for testing
    func addMockSystemApp(_ token: sending ApplicationToken) async {
        mockSystemApps.insert(token)
    }
    
    // MARK: - ScreenTimeManaging Implementation
    
    func requestAuthorization() async -> Bool {
        // Simulate network delay
        try? await Task.sleep(nanoseconds: UInt64(authorizationDelay * 1_000_000_000))
        
        // Check if authorization should succeed
        if shouldSucceedAuthorization {
            if mockAuthorizationStatus == .notDetermined {
                mockAuthorizationStatus = .approved
            }
            return true
        } else {
            // Simulate authorization failure
            mockAuthorizationStatus = .denied
            return false
        }
    }
    
    func authorizationStatus() async -> AuthorizationStatus {
        return mockAuthorizationStatus
    }
    
    func initialize() async throws {
        guard !mockIsInitialized else { return }
        
        let authorized = await requestAuthorization()
        guard authorized else {
            throw AppError.screenTimeAuthorizationFailed
        }
        
        try await blockAllApps()
        mockIsInitialized = true
    }
    
    func blockAllApps() async throws {
        let status = await authorizationStatus()
        guard status == .approved else {
            throw AppError.screenTimeAuthorizationFailed
        }
        
        mockCurrentlyAllowedApps.removeAll()
        mockSessionTask?.cancel()
        mockSessionTask = nil
        
        print("Mock: All apps blocked")
    }
    
    func allowApps(_ tokens: sending Set<ApplicationToken>, categories: Set<ActivityCategoryToken> = [], duration: TimeInterval) async throws {
        let status = await authorizationStatus()
        guard status == .approved else {
            throw AppError.screenTimeAuthorizationFailed
        }
        
        guard duration > 0 else {
            throw AppError.invalidConfiguration("Duration must be greater than 0")
        }
        
        mockCurrentlyAllowedApps = tokens
        
        // Mock session expiration
        mockSessionTask?.cancel()
        mockSessionTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
                guard !Task.isCancelled else { return }
                
                try? await self?.blockAllApps()
                print("Mock: Session expired")
            } catch {
                // Task cancelled or sleep interrupted
                return
            }
        }
        
        print("Mock: Allowed \(tokens.count) apps for \(duration) seconds")
    }
    
    func getCurrentlyAllowedApps() async -> Set<ApplicationToken> {
        return mockCurrentlyAllowedApps
    }
    
    func allowAllAccess() async throws {
        // Mock implementation: clear all restrictions (all apps are now accessible)
        mockCurrentlyAllowedApps.removeAll()
        print("🧪 MockScreenTimeService: All access allowed - no restrictions")
    }
    
    func isAppAllowed(_ token: sending ApplicationToken) async -> Bool {
        return mockCurrentlyAllowedApps.contains(token) || mockSystemApps.contains(token)
    }
    
    func getEssentialSystemApps() async -> Set<ApplicationToken> {
        return mockSystemApps
    }
    
    func getStatusInfo() async -> ScreenTimeStatusInfo {
        let status = await authorizationStatus()
        return ScreenTimeStatusInfo(
            authorizationStatus: status,
            currentlyAllowedAppsCount: mockCurrentlyAllowedApps.count,
            essentialSystemAppsCount: mockSystemApps.count,
            hasActiveSession: mockSessionTask != nil,
            isInitialized: mockIsInitialized
        )
    }
    
    func setDiscoveredAppSelection(_ allAvailable: FamilyActivitySelection) async {
        // Mock implementation - just log it
        let appCount = allAvailable.applications.compactMap { $0.token }.count
        let categoryCount = allAvailable.categories.compactMap { $0.token }.count
        print("Mock: Received app discovery - \(appCount) apps, \(categoryCount) categories")
    }
    
    func setCategoryMappingService(_ service: CategoryMappingService) async {
        // Mock implementation - just log it
        print("Mock: Category mapping service configured")
    }
}
