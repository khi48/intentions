//
//  AppGroupTests.swift
//  Intentions
//
//  Created by Kieran Hitchcock on 08/06/2025.
//


// AppGroupTests.swift
// Unit tests for AppGroup model

import XCTest
import FamilyControls
@testable import Intentions

final class AppGroupTests: XCTestCase {
    
    func testAppGroupInitialization() throws {
        // Given
        let groupName = "Social Media"
        
        // When
        let appGroup = try AppGroup(name: groupName)
        
        // Then
        XCTAssertEqual(appGroup.name, groupName)
        XCTAssertTrue(appGroup.applications.isEmpty)
        XCTAssertTrue(appGroup.categories.isEmpty)
        XCTAssertNotNil(appGroup.id)
        XCTAssertNotNil(appGroup.createdAt)
        XCTAssertEqual(appGroup.createdAt.timeIntervalSince1970, appGroup.lastModified.timeIntervalSince1970, accuracy: 100)
    }
    
    func testUpdateModifiedDate() throws {
        // Given
        let appGroup = try AppGroup(name: "Test Group")
        let originalModified = appGroup.lastModified
        
        // When
        Thread.sleep(forTimeInterval: 0.01) // Small delay to ensure time difference
        appGroup.updateModified()
        
        // Then
        XCTAssertGreaterThan(appGroup.lastModified, originalModified)
    }
    
    func testAppGroupCodable() throws {
        // Given
        let appGroup = try AppGroup(name: "Productivity Apps")
        appGroup.updateModified()
        
        // When - Encode
        let encoder = JSONEncoder()
        let data = try encoder.encode(appGroup)
        
        // Then - Decode
        let decoder = JSONDecoder()
        let decodedGroup = try decoder.decode(AppGroup.self, from: data)
        
        XCTAssertEqual(decodedGroup.id, appGroup.id)
        XCTAssertEqual(decodedGroup.name, appGroup.name)
        XCTAssertEqual(decodedGroup.createdAt.timeIntervalSince1970, 
                      appGroup.createdAt.timeIntervalSince1970, accuracy: 0.001)
        XCTAssertEqual(decodedGroup.lastModified.timeIntervalSince1970, 
                      appGroup.lastModified.timeIntervalSince1970, accuracy: 0.001)
    }
    
    func testAppGroupEquality() throws {
        // Given
        let group1 = try AppGroup(name: "Games")
        let group2 = try AppGroup(name: "Games")
        
        // Then - Different instances should have different IDs
        XCTAssertNotEqual(group1.id, group2.id)
    }
    
    func testAppGroupNameChange() throws {
        // Given
        let appGroup = try AppGroup(name: "Original Name")
        let originalModified = appGroup.lastModified
        
        // When
        Thread.sleep(forTimeInterval: 0.01)
        appGroup.name = "New Name"
        appGroup.updateModified()
        
        // Then
        XCTAssertEqual(appGroup.name, "New Name")
        XCTAssertGreaterThan(appGroup.lastModified, originalModified)
    }
    
    func testEmptyAppGroupSerialization() throws {
        // Given - this should now throw an error
        XCTAssertThrowsError(try AppGroup(name: "")) { error in
            // Then - verify we get the correct validation error
            if case AppError.invalidConfiguration(let message) = error {
                XCTAssertTrue(message.contains("AppGroup name cannot be empty"))
            } else {
                XCTFail("Expected AppError.invalidConfiguration but got \(error)")
            }
        }
    }
    
    // MARK: - Validation Tests
    
    func testAppGroupNameTooLong() throws {
        // Given - name exceeding maximum length
        let longName = String(repeating: "a", count: AppConstants.AppGroup.maxNameLength + 1)
        
        // When & Then
        XCTAssertThrowsError(try AppGroup(name: longName)) { error in
            if case AppError.invalidConfiguration(let message) = error {
                XCTAssertTrue(message.contains("exceeds maximum length"))
            } else {
                XCTFail("Expected AppError.invalidConfiguration but got \(error)")
            }
        }
    }
    
    func testAppGroupReservedName() throws {
        // Given - reserved name
        let reservedName = AppConstants.AppGroup.reservedNames.first!
        
        // When & Then
        XCTAssertThrowsError(try AppGroup(name: reservedName)) { error in
            if case AppError.invalidConfiguration(let message) = error {
                XCTAssertTrue(message.contains("is reserved"))
            } else {
                XCTFail("Expected AppError.invalidConfiguration but got \(error)")
            }
        }
    }
    
    func testAppGroupWhitespaceOnlyName() throws {
        // Given - name with only whitespace
        let whitespaceName = "   \t\n  "
        
        // When & Then
        XCTAssertThrowsError(try AppGroup(name: whitespaceName)) { error in
            if case AppError.invalidConfiguration(let message) = error {
                XCTAssertTrue(message.contains("AppGroup name cannot be empty"))
            } else {
                XCTFail("Expected AppError.invalidConfiguration but got \(error)")
            }
        }
    }
    
    func testAppGroupValidBoundaryName() throws {
        // Given - name exactly at maximum length
        let maxLengthName = String(repeating: "a", count: AppConstants.AppGroup.maxNameLength)
        
        // When
        let appGroup = try AppGroup(name: maxLengthName)
        
        // Then
        XCTAssertEqual(appGroup.name, maxLengthName)
    }
}
