//
//  WeekdayTests.swift
//  Intentions
//
//  Created by Kieran Hitchcock on 08/06/2025.
//


// WeekdayTests.swift
// Unit tests for Weekday enum

import XCTest
@testable import Intentions

final class WeekdayTests: XCTestCase {
    
    func testWeekdayAllCases() {
        // When
        let allWeekdays = Weekday.allCases
        
        // Then
        XCTAssertEqual(allWeekdays.count, 7)
        XCTAssertEqual(allWeekdays, [.sunday, .monday, .tuesday, .wednesday, .thursday, .friday, .saturday])
    }
    
    func testWeekdayRawValues() {
        // Then
        XCTAssertEqual(Weekday.sunday.rawValue, "Sunday")
        XCTAssertEqual(Weekday.monday.rawValue, "Monday")
        XCTAssertEqual(Weekday.tuesday.rawValue, "Tuesday")
        XCTAssertEqual(Weekday.wednesday.rawValue, "Wednesday")
        XCTAssertEqual(Weekday.thursday.rawValue, "Thursday")
        XCTAssertEqual(Weekday.friday.rawValue, "Friday")
        XCTAssertEqual(Weekday.saturday.rawValue, "Saturday")
    }
    
    func testWeekdayFromCalendarWeekday() {
        // Then - Calendar weekday starts from 1 (Sunday)
        XCTAssertEqual(Weekday.from(calendarWeekday: 1), .sunday)
        XCTAssertEqual(Weekday.from(calendarWeekday: 2), .monday)
        XCTAssertEqual(Weekday.from(calendarWeekday: 3), .tuesday)
        XCTAssertEqual(Weekday.from(calendarWeekday: 4), .wednesday)
        XCTAssertEqual(Weekday.from(calendarWeekday: 5), .thursday)
        XCTAssertEqual(Weekday.from(calendarWeekday: 6), .friday)
        XCTAssertEqual(Weekday.from(calendarWeekday: 7), .saturday)
    }
    
    func testCalendarWeekdayProperty() {
        // Then
        XCTAssertEqual(Weekday.sunday.calendarWeekday, 1)
        XCTAssertEqual(Weekday.monday.calendarWeekday, 2)
        XCTAssertEqual(Weekday.tuesday.calendarWeekday, 3)
        XCTAssertEqual(Weekday.wednesday.calendarWeekday, 4)
        XCTAssertEqual(Weekday.thursday.calendarWeekday, 5)
        XCTAssertEqual(Weekday.friday.calendarWeekday, 6)
        XCTAssertEqual(Weekday.saturday.calendarWeekday, 7)
    }
    
    func testWeekdayRoundTripConversion() {
        // Given
        for weekday in Weekday.allCases {
            // When
            let calendarWeekday = weekday.calendarWeekday
            let convertedBack = Weekday.from(calendarWeekday: calendarWeekday)
            
            // Then
            XCTAssertEqual(convertedBack, weekday)
        }
    }
    
    func testInvalidCalendarWeekdayHandling() {
        // When & Then - Invalid values should default to Sunday
        XCTAssertEqual(Weekday.from(calendarWeekday: 0), .sunday)
        XCTAssertEqual(Weekday.from(calendarWeekday: 8), .sunday)
        XCTAssertEqual(Weekday.from(calendarWeekday: -1), .sunday)
        XCTAssertEqual(Weekday.from(calendarWeekday: 100), .sunday)
    }
    
    func testWeekdayCodable() throws {
        // Given
        let weekdays: [Weekday] = [.monday, .friday, .sunday]
        
        // When - Encode
        let encoder = JSONEncoder()
        let data = try encoder.encode(weekdays)
        
        // Then - Decode
        let decoder = JSONDecoder()
        let decodedWeekdays = try decoder.decode([Weekday].self, from: data)
        
        XCTAssertEqual(decodedWeekdays, weekdays)
    }
    
    func testWeekdaySetOperations() {
        // Given
        let weekendDays: Set<Weekday> = [.saturday, .sunday]
        let weekDays: Set<Weekday> = [.monday, .tuesday, .wednesday, .thursday, .friday]
        
        // When
        let allDays = weekendDays.union(weekDays)
        let intersection = weekendDays.intersection(weekDays)
        
        // Then
        XCTAssertEqual(allDays.count, 7)
        XCTAssertTrue(intersection.isEmpty)
        
        for weekday in Weekday.allCases {
            XCTAssertTrue(allDays.contains(weekday))
        }
    }
    
    func testWeekdayEquality() {
        // Then
        XCTAssertEqual(Weekday.monday, Weekday.monday)
        XCTAssertNotEqual(Weekday.monday, Weekday.tuesday)
    }
    
    func testWeekdayStringRepresentation() {
        // Then - Verify proper string representation for UI display
        XCTAssertEqual(String(describing: Weekday.monday), "monday")
        XCTAssertEqual(Weekday.monday.rawValue, "Monday") // Capitalized for display
    }
}
