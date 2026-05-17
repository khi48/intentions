import Foundation

/// One rendered grid block for a single (routine × day) pairing.
/// Layout-only data; no view code.
struct RoutineGridBlock: Equatable, Sendable {
    let routineID: UUID
    let day: Weekday
    let startMinute: Int
    let durationMinutes: Int
    let name: String?
}

/// Pure mapping: one block per (routine × day in `routine.days`).
/// Order: input routine order × Mon..Sun (Monday-first).
func gridBlocks(for routines: [FreeTimeRoutine]) -> [RoutineGridBlock] {
    let order: [Weekday] = [.monday, .tuesday, .wednesday, .thursday, .friday, .saturday, .sunday]
    var blocks: [RoutineGridBlock] = []
    for routine in routines {
        for day in order where routine.days.contains(day) {
            blocks.append(
                RoutineGridBlock(
                    routineID: routine.id,
                    day: day,
                    startMinute: routine.startMinute,
                    durationMinutes: routine.durationMinutes,
                    name: routine.name
                )
            )
        }
    }
    return blocks
}
