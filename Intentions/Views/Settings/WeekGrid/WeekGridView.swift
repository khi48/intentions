import SwiftUI

/// The full week grid: hour label column + 7 day columns + shared horizontal gridlines.
/// Emits tap / edit / delete events up to the parent editor view.
struct WeekGridView: View {
    let intervals: [FreeTimeInterval]
    let selectedIntervalID: UUID?
    let onTapEmpty: (_ day: Weekday, _ minuteOfDay: Int) -> Void
    let onTapBlock: (_ intervalID: UUID) -> Void
    let onEditBlock: (_ intervalID: UUID) -> Void
    let onDeleteBlock: (_ intervalID: UUID) -> Void

    private static let days: [Weekday] = [.monday, .tuesday, .wednesday, .thursday, .friday, .saturday, .sunday]

    var body: some View {
        // Use a GeometryReader to get explicit dimensions; pass concrete heights to each row.
        GeometryReader { geo in
            let labelHeight: CGFloat = 22
            let spacing: CGFloat = 8
            let hourColWidth: CGFloat = 26
            let bodyHeight = max(0, geo.size.height - labelHeight - spacing)

            VStack(spacing: spacing) {
                // Header row — empty spacer over hour column, then 7 day labels.
                HStack(spacing: 4) {
                    Color.clear.frame(width: hourColWidth, height: labelHeight)
                    HStack(spacing: 4) {
                        ForEach(Self.days, id: \.self) { day in
                            Text(day.shortName.prefix(1).uppercased())
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(AppConstants.Colors.textSecondary)
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
                .frame(height: labelHeight)

                // Body: hour column + day columns + overlay. Explicit height.
                HStack(spacing: 4) {
                    HourColumn()
                        .frame(width: hourColWidth, height: bodyHeight)
                    ZStack {
                        HStack(spacing: 4) {
                            ForEach(Self.days, id: \.self) { day in
                                DayColumn(
                                    dayOfWeek: day,
                                    renderedBlocks: renderedBlocks(for: day),
                                    selectedIntervalID: selectedIntervalID,
                                    onTapEmpty: { minute in onTapEmpty(day, minute) },
                                    onTapBlock: onTapBlock,
                                    onEditBlock: onEditBlock,
                                    onDeleteBlock: onDeleteBlock
                                )
                                .frame(maxWidth: .infinity)
                            }
                        }
                        HourGridOverlay()
                    }
                    .frame(height: bodyHeight)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    // MARK: - Fanning intervals across day columns

    private func renderedBlocks(for day: Weekday) -> [RenderedBlock] {
        let dayIndex = FreeTimeInterval.mondayDayIndex(for: day)
        let dayStartMoW = dayIndex * FreeTimeInterval.minutesPerDay
        let dayEndMoW = dayStartMoW + FreeTimeInterval.minutesPerDay

        var result: [RenderedBlock] = []
        for interval in intervals {
            let segs = segments(for: interval, dayStartMoW: dayStartMoW, dayEndMoW: dayEndMoW)
            for (segStart, segEnd) in segs {
                result.append(RenderedBlock(
                    intervalID: interval.id,
                    startMinuteOfDay: segStart - dayStartMoW,
                    endMinuteOfDay: segEnd - dayStartMoW
                ))
            }
        }
        return result
    }

    /// Returns any `(startMoW, endMoW)` sub-ranges of `interval` that fall inside the given day.
    /// Handles wrap-around intervals that may include this day from a "previous" iteration.
    private func segments(for interval: FreeTimeInterval, dayStartMoW: Int, dayEndMoW: Int) -> [(Int, Int)] {
        let weekLen = FreeTimeInterval.minutesPerWeek
        let rawStart = interval.startMinuteOfWeek
        let rawEnd = interval.startMinuteOfWeek + interval.durationMinutes

        // Walk the two copies of the interval (current week and wrapped-into-next-week).
        var ranges: [(Int, Int)] = []
        if rawEnd <= weekLen {
            ranges.append((rawStart, rawEnd))
        } else {
            ranges.append((rawStart, weekLen))                  // tail of this week
            ranges.append((0, rawEnd - weekLen))                // head of next week, which maps back onto the same grid
        }

        var out: [(Int, Int)] = []
        for (rs, re) in ranges {
            let clippedStart = max(rs, dayStartMoW)
            let clippedEnd = min(re, dayEndMoW)
            if clippedStart < clippedEnd {
                out.append((clippedStart, clippedEnd))
            }
        }
        return out
    }
}
