// GroupManagerTests.swift
// Unit tests for GroupManager to verify CRUD operations with CoreData.

import XCTest
import CoreData
@testable import Intentions // Replace with your module name

class GroupManagerTests: XCTestCase {
    private var groupManager: GroupManager!
    private var persistenceController: PersistenceController!
    
    // MA RK: - Setup and Teardown
    
    override func setUpWithError() throws {
        persistenceController = PersistenceController.diskTestController
        groupManager = GroupManager(persistenceController: persistenceController)
    }
    
    override func tearDownWithError() throws {
        groupManager = nil
        persistenceController = nil
    }
    
    // MARK: - Test Cases
    
    func testCreateAppGroup() throws {
        // Given
        let name = "Social Media"
        let bundleIDs = ["com.apple.mobilesafari", "com.twitter"]
        
        // When
        let createdGroup = try groupManager.createAppGroup(name: name, bundleIDs: bundleIDs)
        
        // Then
        XCTAssertNotNil(createdGroup.id)
        XCTAssertEqual(createdGroup.name, name)
        XCTAssertEqual(createdGroup.bundleIDs, bundleIDs)
        
        // Verify in CoreData
        let fetchRequest: NSFetchRequest<AppGroup> = AppGroup.fetchRequest()
        let groups = try persistenceController.container.viewContext.fetch(fetchRequest)
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups.first?.id, createdGroup.id)
        XCTAssertEqual(groups.first?.name, name)
        XCTAssertEqual(groups.first?.bundleIDs as? [String], bundleIDs)
    }
    
    func testFetchAppGroups() throws {
        // Given
        let group1 = try groupManager.createAppGroup(name: "Social Media", bundleIDs: ["com.apple.mobilesafari"])
        let group2 = try groupManager.createAppGroup(name: "Games", bundleIDs: ["com.game.example"])
        
        // When
        let fetchedGroups = try groupManager.fetchAppGroups()
        
        // Then
        XCTAssertEqual(fetchedGroups.count, 2)
        XCTAssertTrue(fetchedGroups.contains { $0.id == group1.id })
        XCTAssertTrue(fetchedGroups.contains { $0.id == group2.id })
        
        if let fetchedGroup1 = fetchedGroups.first(where: { $0.id == group1.id }) {
            XCTAssertEqual(fetchedGroup1.name, group1.name)
            XCTAssertEqual(fetchedGroup1.bundleIDs, group1.bundleIDs)
        } else {
            XCTFail("Group 1 not found in fetched groups")
        }
    }
    
    func testUpdateAppGroup() throws {
        // Given
        let initialGroup = try groupManager.createAppGroup(name: "Social Media", bundleIDs: ["com.apple.mobilesafari"])
        let groupId = initialGroup.id
        let updatedName = "Updated Group"
        let updatedBundleIDs = ["com.apple.mobilesafari", "com.twitter"]
        
        // When
        let updatedGroup = try groupManager.updateAppGroup(id: groupId, name: updatedName, bundleIDs: updatedBundleIDs)
        
        // Then
        XCTAssertNotNil(updatedGroup)
        XCTAssertEqual(updatedGroup?.id, groupId)
        XCTAssertEqual(updatedGroup?.name, updatedName)
        XCTAssertEqual(updatedGroup?.bundleIDs, updatedBundleIDs)
        
        // Verify in CoreData
        let fetchRequest: NSFetchRequest<AppGroup> = AppGroup.fetchRequest()
        let groups = try persistenceController.container.viewContext.fetch(fetchRequest)
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups.first?.id, groupId)
        XCTAssertEqual(groups.first?.name, updatedName)
        XCTAssertEqual(groups.first?.bundleIDs as? [String], updatedBundleIDs)
    }
    
    func testDeleteAppGroup() throws {
        // Given
        let group = try groupManager.createAppGroup(name: "Social Media", bundleIDs: ["com.apple.mobilesafari"])
        let groupId = group.id
        
        // When
        try groupManager.deleteAppGroup(id: groupId)
        
        // Then
        let fetchRequest: NSFetchRequest<AppGroup> = AppGroup.fetchRequest()
        let groups = try persistenceController.container.viewContext.fetch(fetchRequest)
        XCTAssertEqual(groups.count, 0)
    }
}
