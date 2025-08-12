// ScheduleManagerTests.swift
// Unit tests for ScheduleManager to verify CRUD operations with CoreData.

import XCTest
import CoreData
@testable import Intentions // Replace with your module name

class ScheduleManagerTests: XCTestCase {
    private var scheduleManager: ScheduleManager!
    private var persistenceController: PersistenceController!
    
    // MARK: - Setup and Teardown
    
    override func setUpWithError() throws {
        persistenceController = PersistenceController.diskTestController
        scheduleManager = ScheduleManager(persistenceController: persistenceController)
    }
    
    override func tearDownWithError() throws {
        scheduleManager = nil
        persistenceController = nil
    }
    
    // MARK: - Test Cases
    
    func testSetScheduleCreatesNewSchedule() throws {
        // Given
        let isActive = true
        let startTime = Date()
        let endTime = startTime.addingTimeInterval(3600) // 1 hour later
        
        // When
        let createdSchedule = try scheduleManager.setSchedule(isActive: isActive, startTime: startTime, endTime: endTime)
        
        // Then
        XCTAssertNotNil(createdSchedule.id)
        XCTAssertEqual(createdSchedule.isActive, isActive)
        XCTAssertEqual(createdSchedule.startTime, startTime)
        XCTAssertEqual(createdSchedule.endTime, endTime)
        
        // Verify in CoreData
        let fetchRequest: NSFetchRequest<UsageSchedule> = UsageSchedule.fetchRequest()
        let schedules = try persistenceController.container.viewContext.fetch(fetchRequest)
        XCTAssertEqual(schedules.count, 1)
        XCTAssertEqual(schedules.first?.id, createdSchedule.id)
        XCTAssertEqual(schedules.first?.isActive, isActive)
        XCTAssertEqual(schedules.first?.startTime, startTime)
        XCTAssertEqual(schedules.first?.endTime, endTime)
    }
    
    func testSetScheduleUpdatesExistingSchedule() throws {
        // Given
        let initialSchedule = try scheduleManager.setSchedule(
            isActive: true,
            startTime: Date(),
            endTime: Date().addingTimeInterval(3600)
        )
        let scheduleId = initialSchedule.id
        let updatedIsActive = false
        let updatedStartTime = Date().addingTimeInterval(7200)
        let updatedEndTime = Date().addingTimeInterval(10800)
        
        // When
        let updatedSchedule = try scheduleManager.setSchedule(
            id: scheduleId,
            isActive: updatedIsActive,
            startTime: updatedStartTime,
            endTime: updatedEndTime
        )
        
        // Then
        XCTAssertEqual(updatedSchedule.id, scheduleId)
        XCTAssertEqual(updatedSchedule.isActive, updatedIsActive)
        XCTAssertEqual(updatedSchedule.startTime, updatedStartTime)
        XCTAssertEqual(updatedSchedule.endTime, updatedEndTime)
        
        // Verify in CoreData
        let fetchRequest: NSFetchRequest<UsageSchedule> = UsageSchedule.fetchRequest()
        let schedules = try persistenceController.container.viewContext.fetch(fetchRequest)
        XCTAssertEqual(schedules.count, 1)
        XCTAssertEqual(schedules.first?.id, scheduleId)
        XCTAssertEqual(schedules.first?.isActive, updatedIsActive)
        XCTAssertEqual(schedules.first?.startTime, updatedStartTime)
        XCTAssertEqual(schedules.first?.endTime, updatedEndTime)
    }
    
    func testFetchSchedulesReturnsAllSchedules() throws {
        // Given
        let schedule1 = try scheduleManager.setSchedule(
            isActive: true,
            startTime: Date(),
            endTime: Date().addingTimeInterval(3600)
        )
        let schedule2 = try scheduleManager.setSchedule(
            isActive: false,
            startTime: Date().addingTimeInterval(7200),
            endTime: Date().addingTimeInterval(10800)
        )
        
        // When
        let fetchedSchedules = try scheduleManager.fetchSchedules()
        
        // Then
        XCTAssertEqual(fetchedSchedules.count, 2)
        XCTAssertTrue(fetchedSchedules.contains { $0.id == schedule1.id })
        XCTAssertTrue(fetchedSchedules.contains { $0.id == schedule2.id })
        
        if let fetchedSchedule1 = fetchedSchedules.first(where: { $0.id == schedule1.id }) {
            XCTAssertEqual(fetchedSchedule1.isActive, schedule1.isActive)
            XCTAssertEqual(fetchedSchedule1.startTime, schedule1.startTime)
            XCTAssertEqual(fetchedSchedule1.endTime, schedule1.endTime)
        } else {
            XCTFail("Schedule 1 not found in fetched schedules")
        }
        
        if let fetchedSchedule2 = fetchedSchedules.first(where: { $0.id == schedule2.id }) {
            XCTAssertEqual(fetchedSchedule2.isActive, schedule2.isActive)
            XCTAssertEqual(fetchedSchedule2.startTime, schedule2.startTime)
            XCTAssertEqual(fetchedSchedule2.endTime, schedule2.endTime)
        } else {
            XCTFail("Schedule 2 not found in fetched schedules")
        }
    }
    
    func testFetchSchedulesReturnsEmptyArrayWhenNoSchedules() throws {
        // When
        let fetchedSchedules = try scheduleManager.fetchSchedules()
        
        // Then
        XCTAssertEqual(fetchedSchedules.count, 0)
    }
}
