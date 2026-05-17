import Foundation

/// A recurring free-time window. Time-of-day + a set of weekdays it repeats on.
/// Single-day only: `startMinute + durationMinutes` must not exceed 1440. Late-night
/// routines that cross midnight are expressed as two separate routines.
struct FreeTimeRoutine: Identifiable, Codable, Hashable, Sendable {
    static let minutesPerDay = 24 * 60          // 1440

    let id: UUID
    var name: String?
    /// 0..<1440. Minute-of-day in the schedule's timezone.
    var startMinute: Int
    /// 1...(1440 - startMinute). Strictly positive, single-day.
    var durationMinutes: Int
    /// Days of the week on which this routine recurs.
    var days: Set<Weekday>
    /// Manual order index — list view sorts ascending.
    var sortIndex: Int

    init(
        id: UUID = UUID(),
        name: String? = nil,
        startMinute: Int,
        durationMinutes: Int,
        days: Set<Weekday>,
        sortIndex: Int
    ) {
        self.id = id
        self.name = name
        self.startMinute = startMinute
        self.durationMinutes = durationMinutes
        self.days = days
        self.sortIndex = sortIndex
    }

    /// Exclusive end-minute-of-day. Always `<= 1440`.
    var endMinute: Int { startMinute + durationMinutes }

    /// True if `weekday ∈ days && minuteOfDay ∈ [startMinute, endMinute)`.
    func isActive(weekday: Weekday, minuteOfDay: Int) -> Bool {
        guard days.contains(weekday) else { return false }
        return minuteOfDay >= startMinute && minuteOfDay < endMinute
    }

    /// Display string, e.g. `"08:30"`.
    var startTimeOfDayString: String {
        Self.timeOfDayString(forMinute: startMinute)
    }

    /// Display string, e.g. `"12:00"`.
    var endTimeOfDayString: String {
        Self.timeOfDayString(forMinute: endMinute)
    }

    static func timeOfDayString(forMinute minute: Int) -> String {
        let h = minute / 60
        let m = minute % 60
        return String(format: "%02d:%02d", h, m)
    }
}

// MARK: - Editor guards

/// Spec for what the routine editor sheet should disable / clamp, so it
/// can't create a routine that starts in the past on today.
struct EditorGuardSpec: Equatable, Sendable {
    let disabledDays: Set<Weekday>
    /// `nil` = no minimum (today not selected, or editing an in-progress routine).
    let minStartMinute: Int?
    /// Always >= currentStart + 1.
    let minEndMinute: Int
}

/// Pure guard-spec for the routine editor sheet.
///
/// Pass `isNewRoutine = true` for new routines AND for edits of routines that
/// have not yet started on today. Pass `false` only when editing a routine that
/// is currently in-progress (today ∈ days && start ≤ nowMinute < end) — in that
/// case no guards apply, since the user is just adjusting a live window.
func editorGuards(
    now: Date,
    isNewRoutine: Bool,
    currentStart: Int?,
    daysSelected: Set<Weekday>
) -> EditorGuardSpec {
    let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.firstWeekday = 2
        return c
    }()
    let comps = calendar.dateComponents([.hour, .minute, .weekday], from: now)
    let nowMinute = (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
    let today = Weekday.from(calendarWeekday: comps.weekday ?? 1)

    let baseStart = currentStart ?? 0
    let endFloor = min(baseStart + 1, FreeTimeRoutine.minutesPerDay)

    guard isNewRoutine else {
        return EditorGuardSpec(disabledDays: [], minStartMinute: nil, minEndMinute: endFloor)
    }

    let disabled = pastWeekdays(before: today)
    let minStart = daysSelected.contains(today) ? nowMinute : nil
    return EditorGuardSpec(disabledDays: disabled, minStartMinute: minStart, minEndMinute: endFloor)
}

/// Weekdays earlier in the current week than `today`, using Mon=baseline.
/// If today is Mon → empty. If today is Sun → all six prior days.
private func pastWeekdays(before today: Weekday) -> Set<Weekday> {
    let order: [Weekday] = [.monday, .tuesday, .wednesday, .thursday, .friday, .saturday, .sunday]
    guard let idx = order.firstIndex(of: today) else { return [] }
    return Set(order.prefix(idx))
}
