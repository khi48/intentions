//
//  RoutineGridLayoutTests.swift
//  IntentionsTests
//
//  Covers the pure routine → grid block mapping used by RoutinesWeekView.
//

import XCTest
@testable import Intentions

final class RoutineGridLayoutTests: XCTestCase {

    // MARK: - Helpers

    private func makeRoutine(
        id: UUID = UUID(),
        name: String? = nil,
        startMinute: Int = 9 * 60,
        durationMinutes: Int = 60,
        days: Set<Weekday> = [.monday],
        sortIndex: Int = 0
    ) -> FreeTimeRoutine {
        FreeTimeRoutine(
            id: id,
            name: name,
            startMinute: startMinute,
            durationMinutes: durationMinutes,
            days: days,
            sortIndex: sortIndex
        )
    }

    // MARK: - Empty / single-day

    func test_emptyInput_returnsNoBlocks() {
        XCTAssertEqual(gridBlocks(for: []), [])
    }

    func test_singleRoutineWithOneDay_producesOneBlock() {
        let id = UUID()
        let r = makeRoutine(id: id, name: "Morning",
                            startMinute: 9 * 60, durationMinutes: 60,
                            days: [.tuesday])

        let result = gridBlocks(for: [r])
        XCTAssertEqual(result.count, 1)

        let block = result[0]
        XCTAssertEqual(block.routineID, id)
        XCTAssertEqual(block.day, .tuesday)
        XCTAssertEqual(block.startMinute, 9 * 60)
        XCTAssertEqual(block.durationMinutes, 60)
        XCTAssertEqual(block.name, "Morning")
    }

    // MARK: - Multi-day per routine

    func test_routineWithThreeDays_producesThreeBlocksOrderedMondayFirst() {
        let id = UUID()
        let r = makeRoutine(id: id, name: "MWF",
                            startMinute: 12 * 60, durationMinutes: 30,
                            days: [.monday, .wednesday, .friday])

        let result = gridBlocks(for: [r])
        XCTAssertEqual(result.count, 3)
        XCTAssertEqual(result.map(\.day), [.monday, .wednesday, .friday])
        XCTAssertTrue(result.allSatisfy { $0.routineID == id })
        XCTAssertTrue(result.allSatisfy { $0.startMinute == 12 * 60 })
        XCTAssertTrue(result.allSatisfy { $0.durationMinutes == 30 })
        XCTAssertTrue(result.allSatisfy { $0.name == "MWF" })
    }

    // MARK: - Multiple routines

    func test_twoOverlappingRoutines_produceCombinedBlockCount() {
        let a = makeRoutine(name: "A",
                            startMinute: 9 * 60, durationMinutes: 60,
                            days: [.monday, .tuesday])
        let b = makeRoutine(name: "B",
                            startMinute: 9 * 60 + 30, durationMinutes: 60,
                            days: [.tuesday, .wednesday])

        let result = gridBlocks(for: [a, b])
        XCTAssertEqual(result.count, 4)

        let aBlocks = result.filter { $0.routineID == a.id }
        let bBlocks = result.filter { $0.routineID == b.id }
        XCTAssertEqual(Set(aBlocks.map(\.day)), [.monday, .tuesday])
        XCTAssertEqual(Set(bBlocks.map(\.day)), [.tuesday, .wednesday])
        XCTAssertTrue(aBlocks.allSatisfy { $0.name == "A" })
        XCTAssertTrue(bBlocks.allSatisfy { $0.name == "B" })
    }

    // MARK: - Order

    func test_dayOrderWithinRoutineIsMondayFirstThroughSunday() {
        let r = makeRoutine(days: [.sunday, .saturday, .monday, .friday])
        let result = gridBlocks(for: [r])
        XCTAssertEqual(result.map(\.day), [.monday, .friday, .saturday, .sunday])
    }

    func test_routinesPreserveInputOrder() {
        let first = makeRoutine(name: "first", days: [.monday])
        let second = makeRoutine(name: "second", days: [.monday])
        let result = gridBlocks(for: [first, second])
        XCTAssertEqual(result.map(\.name), ["first", "second"])
    }

    // MARK: - Nil name

    func test_nilNamePropagatesToBlock() {
        let r = makeRoutine(name: nil, days: [.monday])
        let result = gridBlocks(for: [r])
        XCTAssertNil(result.first?.name)
    }
}
