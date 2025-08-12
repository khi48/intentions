//
//  SettingsViewTests.swift
//  IntentionsTests
//
//  Created by Kieran Hitchcock on 6/06/25.
//
import XCTest
import ViewInspector
@testable import Intentions
import SwiftUI
import FamilyControls

import Combine

internal final class Inspection<V> {

    let notice = PassthroughSubject<UInt, Never>()
    var callbacks = [UInt: (V) -> Void]()

    func visit(_ view: V, _ line: UInt) {
        if let callback = callbacks.removeValue(forKey: line) {
            callback(view)
        }
    }
}

extension Inspection: InspectionEmissary { }

extension SettingsView {}
extension AppGroupDetailView {}


class SettingsViewTests: XCTestCase {
    private var groupManager: GroupManager!
    private var scheduleManager: ScheduleManager!
    private var persistenceController: PersistenceController!
    
    override func setUpWithError() throws {
        persistenceController = PersistenceController.testController
        groupManager = GroupManager(persistenceController: persistenceController)
        scheduleManager = ScheduleManager(persistenceController: persistenceController)
    }
    
    override func tearDownWithError() throws {
        groupManager = nil
        scheduleManager = nil
        persistenceController = nil
    }
    
    @MainActor
    func testAppGroupsDisplayedInList() throws {
        // Given
        let _ = try groupManager.createAppGroup(name: "Social", bundleIDs: ["com.social.app"])
        let _ = try groupManager.createAppGroup(name: "Games", bundleIDs: ["com.game.app"])
        let view = SettingsView()
            .environmentObject(groupManager)
            .environmentObject(scheduleManager)
        
        // When
        let list = try view.inspect().navigationView().list(0)
        let groupRows = try list.section(0).forEach(0) // Iterate over AppGroup rows
        
        // Then
        XCTAssertEqual(groupRows.count, 2, "Expected 2 AppGroup rows")
        
        // Verify first NavigationLink
        let firstRow = try groupRows[0].navigationLink()
        XCTAssertEqual(try firstRow.vStack().text(0).string(), "Social")
        XCTAssertEqual(try firstRow.vStack().text(1).string(), "com.social.app")
        
        // Verify second NavigationLink
        let secondRow = try groupRows[1].navigationLink()
        XCTAssertEqual(try secondRow.vStack().text(0).string(), "Games")
        XCTAssertEqual(try secondRow.vStack().text(1).string(), "com.game.app")
    }

    @MainActor
    func testAddGroupWithSelectedApps() throws {
        // Given
        let view = SettingsView()
            .environmentObject(groupManager)
            .environmentObject(scheduleManager)
        
        // When
        try view.inspect().navigationView().list(0).section(0).vStack(0).textField(0).setInput("Work")
        try view.inspect().navigationView().list(0).section(0).vStack(0).button(1).tap() // Select Apps
        //groupManager.simulateAppSelection(bundleIDs: ["com.work.app"], appNames: ["Work App"])
        try view.inspect().navigationView().list(0).section(0).vStack(0).button(2).tap() // Add Group
        
        // Then
        let groups = try groupManager.fetchAppGroups()
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups.first?.name, "Work")
        XCTAssertEqual(groups.first?.bundleIDs, ["com.work.app"])
    }
    
    @MainActor
    func testSelectedAppsDisplay() throws {
        // Given
        let view = SettingsView()
            .environmentObject(groupManager)
            .environmentObject(scheduleManager)
        
        // When
        //groupManager.simulateAppSelection(bundleIDs: ["com.app1", "com.app2"], appNames: ["App One", "App Two"])
        try view.inspect().navigationView().list(0).section(0).vStack(0).button(1).tap() // Select Apps
        let selectedText = try view.inspect().navigationView().list(0).section(0).vStack(0).text(2)
        
        // Then
        XCTAssertEqual(try selectedText.string(), "Selected: App One, App Two")
    }
    
    @MainActor
    func testDeleteGroup() async throws {
        print(groupManager!)
        // Given
        let a = try groupManager.createAppGroup(name: "Test", bundleIDs: ["com.test.app"])
        print(a)
        
        var sut_original = SettingsView()
        
        var sut_env = sut_original
            .environmentObject(groupManager!)
            .environmentObject(scheduleManager!)
        
        let exp = sut_env.on(\.didAppear) { view in
            let list = try view.navigationView().list(0).section(0).list(1).forEach(0).callOnDelete(IndexSet([0]))

            // then check
            let groups = try groupManager.fetchAppGroups()
            print("fetching app groups again")
            XCTAssertEqual(groups.count, 0)
        }
        ViewHosting.host(view: sut_env)
        wait(for: [exp], timeout: 0.1)
//        appGroups = try groupManager.fetchAppGroups()
        
        // When
//        print("-----------")
//        print(try view.inspect())
//        let list = try view.inspect().find(ViewType.List.self)
//        print("-----------")
//        print(list)
//        try list.callOnDelete(IndexSet([0]))
        
        
        
        // Host the view
//        ViewHosting.host(view: sut)
//        try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
//        
//        print("starting inspection")
//        // Direct inspection without the deprecated inspect method
//        let view = try sut.inspect()
//        print("finding list")
//        let list = try view.navigationView().list(0)
////        print("found lists")
////        print(list)
//
//        let section = try list.section(0)
////        print("found section")
////        print(section)
//
//        let final_list = try section.list(1)
//        print("found final list")
////        print(final_list)
//        // TODO: then delete
//        let for_each = try final_list.forEach(0)
////        print(for_each)
//        print("trying to delete")
//        try for_each.callOnDelete(IndexSet([0]))
//        print("deleted")
        // then check
//        let groups = try groupManager.fetchAppGroups()
//        print("fetching app groups again")
//        XCTAssertEqual(groups.count, 0)
    }
    
    @MainActor
    func testScheduleDatePickersDisplayed() throws {
        // Given
        _ = try scheduleManager.setSchedule(id: nil, isActive: true, startTime: Date(), endTime: Date().addingTimeInterval(3600))
        let view = SettingsView()
            .environmentObject(groupManager)
            .environmentObject(scheduleManager)
        
        // When
        let startPicker = try view.inspect().navigationView().list(0).section(1).datePicker(0)
        let endPicker = try view.inspect().navigationView().list(0).section(1).datePicker(1)
        
        // Then
        XCTAssertNotNil(startPicker)
        XCTAssertNotNil(endPicker)
    }
    
    @MainActor
    func testCreateSchedule() throws {
        // Given
        let view = SettingsView()
            .environmentObject(groupManager)
            .environmentObject(scheduleManager)
        
        // When
        try view.inspect().navigationView().list(0).section(1).button(1).tap()
        
        // Then
        let schedules = try scheduleManager.fetchSchedules()
        XCTAssertEqual(schedules.count, 1)
        XCTAssertTrue(schedules.first?.isActive ?? false)
    }
    
    @MainActor
    func testAuthorizationError() throws {
        // Given
        let view = SettingsView()
            .environmentObject(groupManager)
            .environmentObject(scheduleManager)
        
        // When
        //groupManager.simulateAuthorizationError()
        try view.inspect().navigationView().list(0).section(0).vStack(0).button(1).tap() // Select Apps
        
        // Then
        let alert = try view.inspect().alert()
        XCTAssertEqual(try alert.title().string(), "Error")
//        XCTAssertTrue(try alert.message().string().contains("Screen Time authorization failed"))
    }
}

// MARK: - Mock GroupManager
class MockGroupManager: GroupManager {
    private var simulatedBundleIDs: [String] = []
    private var simulatedAppNames: [String] = []
    private var shouldThrowAuthorizationError: Bool = false
    
    func simulateAppSelection(bundleIDs: [String], appNames: [String]) {
        simulatedBundleIDs = bundleIDs
        simulatedAppNames = appNames
    }
    
    func simulateAuthorizationError() {
        shouldThrowAuthorizationError = true
    }
    
    override func createAppGroup(name: String, bundleIDs: [String]) throws -> AppGroupModel {
        let finalBundleIDs = simulatedBundleIDs.isEmpty ? bundleIDs : simulatedBundleIDs
        if shouldThrowAuthorizationError {
            throw NSError(domain: "FamilyControls", code: -1, userInfo: [NSLocalizedDescriptionKey: "Authorization denied"])
        }
        return try super.createAppGroup(name: name, bundleIDs: finalBundleIDs)
    }
    
//    override func updateAppGroup(id: UUID, name: String, bundleIDs: [String]) throws {
//        let finalBundleIDs = simulatedBundleIDs.isEmpty ? bundleIDs : simulatedBundleIDs
//        if shouldThrowAuthorizationError {
//            throw NSError(domain: "FamilyControls", code: -1, userInfo: [NSLocalizedDescriptionKey: "Authorization denied"])
//        }
//        let _ = try super.updateAppGroup(id: id, name: name, bundleIDs: finalBundleIDs)
//    }
}
