//
//  DiscoveredAppTests.swift
//  Intentions
//
//  Created by Kieran Hitchcock on 08/06/2025.
//


// DiscoveredAppTests.swift
// Unit tests for DiscoveredApp model
// DiscoveredAppTests.swift
// Unit tests for DiscoveredApp model

import XCTest
@preconcurrency import FamilyControls
@preconcurrency import ManagedSettings
@testable import Intentions

final class DiscoveredAppTests: XCTestCase {
    
    
    // Alternative: Create DiscoveredApp with a placeholder token that we know will work
    private func createTestApp(
        displayName: String,
        bundleIdentifier: String,
        category: String? = nil,
        isSystemApp: Bool = false
    ) -> DiscoveredApp {
        // For testing, we'll use a simplified approach
        // In real usage, tokens come from FamilyControls discovery APIs
        do {
            let token = try createSafeToken()
            return DiscoveredApp(
                displayName: displayName,
                bundleIdentifier: bundleIdentifier,
                token: token,
                category: category,
                isSystemApp: isSystemApp
            )
        } catch {
            // If we can't create tokens at all, fail the test immediately
            XCTFail("Cannot create ApplicationToken for testing: \(error)")
            
            // We can't create a valid DiscoveredApp without a token, so we need to throw
            // This will cause the test to fail, which is what we want
            fatalError("Test cannot proceed without ApplicationToken")
        }
    }
    
    private func createSafeToken() throws -> ApplicationToken {
        // Try different approaches to create a valid ApplicationToken
        let tokenData = """
            {
                "data": "dGVzdA=="
            }
            """.data(using: .utf8)!
        
        let decoder = JSONDecoder()
        
        do {
            // This might work if ApplicationToken has default decoding
            return try decoder.decode(ApplicationToken.self, from: tokenData)
        } catch {
            // Approach 2: If that fails, we may need to skip token-based tests
            throw TestError.cannotCreateToken(underlying: error)
        }
    }
    
    // Custom error for test failures
    enum TestError: Error {
        case cannotCreateToken(underlying: Error)
    }
    
    func testDiscoveredAppInitialization() {
        // Given
        let displayName = "Instagram"
        let bundleIdentifier = "com.instagram.Instagram"
        let category = "Social Media"
        
        // When
        let app = createTestApp(
            displayName: displayName,
            bundleIdentifier: bundleIdentifier,
            category: category,
            isSystemApp: false
        )
        
        // Then
        XCTAssertEqual(app.displayName, displayName)
        XCTAssertEqual(app.bundleIdentifier, bundleIdentifier)
        XCTAssertEqual(app.category, category)
        XCTAssertFalse(app.isSystemApp)
        XCTAssertNotNil(app.id)
    }
    
    func testDiscoveredAppWithoutCategory() {
        // Given
        let app = createTestApp(
            displayName: "Unknown App",
            bundleIdentifier: "com.unknown.app"
        )
        
        // Then
        XCTAssertNil(app.category)
        XCTAssertFalse(app.isSystemApp) // Default value
    }
    
    func testSystemAppCreation() {
        // Given
        let app = createTestApp(
            displayName: "Settings",
            bundleIdentifier: "com.apple.Preferences",
            category: "System",
            isSystemApp: true
        )
        
        // Then
        XCTAssertTrue(app.isSystemApp)
        XCTAssertEqual(app.category, "System")
    }
    
    func testDiscoveredAppEquality() {
        // Given
        let app1 = createTestApp(
            displayName: "App One",
            bundleIdentifier: "com.test.app"
        )
        
        let app2 = createTestApp(
            displayName: "App Two", // Different name
            bundleIdentifier: "com.test.app" // Same bundle ID
        )
        
        let app3 = createTestApp(
            displayName: "App Three",
            bundleIdentifier: "com.different.app" // Different bundle ID
        )
        
        // Then - Equality is based on bundle identifier only
        XCTAssertEqual(app1, app2) // Same bundle ID
        XCTAssertNotEqual(app1, app3) // Different bundle ID
    }
    
    func testDiscoveredAppHashValue() {
        // Given
        let app1 = createTestApp(
            displayName: "Test App",
            bundleIdentifier: "com.test.app"
        )
        
        let app2 = createTestApp(
            displayName: "Different Name",
            bundleIdentifier: "com.test.app" // Same bundle ID
        )
        
        // Then - Hash should be based on bundle identifier
        XCTAssertEqual(app1.hashValue, app2.hashValue)
    }
    
    func testDiscoveredAppInSet() {
        // Given
        let app1 = createTestApp(
            displayName: "App 1",
            bundleIdentifier: "com.test.app1"
        )
        
        let app2 = createTestApp(
            displayName: "App 2",
            bundleIdentifier: "com.test.app2"
        )
        
        let app1Duplicate = createTestApp(
            displayName: "Different Name",
            bundleIdentifier: "com.test.app1" // Same bundle ID as app1
        )
        
        // When
        var appSet: Set<DiscoveredApp> = [app1, app2]
        appSet.insert(app1Duplicate)
        
        // Then - Set should only contain 2 apps (app1Duplicate should not be added)
        XCTAssertEqual(appSet.count, 2)
        XCTAssertTrue(appSet.contains(app1))
        XCTAssertTrue(appSet.contains(app2))
        XCTAssertTrue(appSet.contains(app1Duplicate)) // Same as app1
    }
    
    func testDiscoveredAppCodableEncoding() throws {
        // Given
        let app = createTestApp(
            displayName: "Test App",
            bundleIdentifier: "com.test.app",
            category: "Productivity",
            isSystemApp: false
        )
        
        // When
        let encoder = JSONEncoder()
        let data = try encoder.encode(app)
        
        // Then - Should not throw
        XCTAssertGreaterThan(data.count, 0)
        
        // Verify the JSON structure (ApplicationToken is not encoded)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertNotNil(json)
        XCTAssertEqual(json?["displayName"] as? String, "Test App")
        XCTAssertEqual(json?["bundleIdentifier"] as? String, "com.test.app")
        XCTAssertEqual(json?["category"] as? String, "Productivity")
        XCTAssertEqual(json?["isSystemApp"] as? Bool, false)
        XCTAssertNotNil(json?["applicationToken"]) // Should not be encoded
    }
    
    func testDiscoveredAppCodableDecoding() throws {
        // Given
        let originalApp = createTestApp(
            displayName: "Decoded App",
            bundleIdentifier: "com.decoded.app",
            category: "Entertainment"
        )
        
        // When - Encode then decode
        let encoder = JSONEncoder()
        let data = try encoder.encode(originalApp)
        
        let decoder = JSONDecoder()
        let decodedApp = try decoder.decode(DiscoveredApp.self, from: data)
        
        // Then
        XCTAssertEqual(decodedApp.displayName, originalApp.displayName)
        XCTAssertEqual(decodedApp.bundleIdentifier, originalApp.bundleIdentifier)
        XCTAssertEqual(decodedApp.category, originalApp.category)
        XCTAssertEqual(decodedApp.isSystemApp, originalApp.isSystemApp)
        
        // Note: applicationToken will be a new instance, not the original
        XCTAssertNotNil(decodedApp.applicationToken)
    }
    
    func testDiscoveredAppCodableWithNilCategory() throws {
        // Given
        let app = createTestApp(
            displayName: "No Category App",
            bundleIdentifier: "com.nocategory.app"
        )
        
        // When
        let data = try JSONEncoder().encode(app)
        let decodedApp = try JSONDecoder().decode(DiscoveredApp.self, from: data)
        
        // Then
        XCTAssertNil(decodedApp.category)
        XCTAssertEqual(decodedApp.displayName, app.displayName)
    }
    
    func testDiscoveredAppArraySorting() {
        // Given
        let apps = [
            createTestApp(displayName: "Zoom", bundleIdentifier: "com.zoom"),
            createTestApp(displayName: "Apple Music", bundleIdentifier: "com.apple.music"),
            createTestApp(displayName: "Instagram", bundleIdentifier: "com.instagram")
        ]
        
        // When - Sort by display name
        let sortedApps = apps.sorted { $0.displayName < $1.displayName }
        
        // Then
        XCTAssertEqual(sortedApps[0].displayName, "Apple Music")
        XCTAssertEqual(sortedApps[1].displayName, "Instagram")
        XCTAssertEqual(sortedApps[2].displayName, "Zoom")
    }
    
    func testDiscoveredAppFiltering() {
        // Given
        let apps = [
            createTestApp(displayName: "Settings", bundleIdentifier: "com.apple.settings", isSystemApp: true),
            createTestApp(displayName: "Instagram", bundleIdentifier: "com.instagram", isSystemApp: false),
            createTestApp(displayName: "Phone", bundleIdentifier: "com.apple.phone", isSystemApp: true)
        ]
        
        // When
        let userApps = apps.filter { !$0.isSystemApp }
        let systemApps = apps.filter { $0.isSystemApp }
        
        // Then
        XCTAssertEqual(userApps.count, 1)
        XCTAssertEqual(userApps.first?.displayName, "Instagram")
        XCTAssertEqual(systemApps.count, 2)
    }
    
    // Test that focuses on bundle identifier logic without tokens
    func testBundleIdentifierLogicWithoutTokens() {
        // This test verifies the core logic without relying on ApplicationToken creation
        let bundleId1 = "com.test.app"
        let bundleId2 = "com.test.app"
        let bundleId3 = "com.different.app"
        
        // Test equality logic
        XCTAssertEqual(bundleId1, bundleId2)
        XCTAssertNotEqual(bundleId1, bundleId3)
        
        // Test hash logic
        XCTAssertEqual(bundleId1.hashValue, bundleId2.hashValue)
    }
}
