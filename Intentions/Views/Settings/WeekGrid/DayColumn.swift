import SwiftUI

/// A single day's column in the week grid. Shows the base "blocked" fill plus any
/// free-time block rectangles belonging to this day.
struct DayColumn: View {
    let dayOfWeek: Weekday
    let renderedBlocks: [RenderedBlock]
    let selectedIntervalID: UUID?
    let onTapEmpty: (_ minuteOfDay: Int) -> Void
    let onTapBlock: (_ intervalID: UUID) -> Void
    let onEditBlock: (_ intervalID: UUID) -> Void
    let onDeleteBlock: (_ intervalID: UUID) -> Void

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(red: 0x1f/255, green: 0x1f/255, blue: 0x1f/255))

                // Block rectangles. BlockRect is defined in Task 7.
                ForEach(renderedBlocks) { block in
                    BlockRect(
                        block: block,
                        selected: block.intervalID == selectedIntervalID,
                        columnHeight: geo.size.height,
                        onTap: { onTapBlock(block.intervalID) },
                        onEdit: { onEditBlock(block.intervalID) },
                        onDelete: { onDeleteBlock(block.intervalID) }
                    )
                }
            }
            .contentShape(Rectangle())
            .onTapGesture(coordinateSpace: .local) { point in
                // Resolve the tapped minute-of-day from the y coordinate.
                let normalized = max(0, min(1, point.y / geo.size.height))
                let minute = Int(normalized * CGFloat(FreeTimeInterval.minutesPerDay))
                let snapped = (minute / 10) * 10
                // Swallow taps that land on an existing block — they should hit that block's gesture.
                let hitsBlock = renderedBlocks.contains { block in
                    let start = CGFloat(block.startMinuteOfDay) / CGFloat(FreeTimeInterval.minutesPerDay) * geo.size.height
                    let end = CGFloat(block.endMinuteOfDay) / CGFloat(FreeTimeInterval.minutesPerDay) * geo.size.height
                    return point.y >= start && point.y <= end
                }
                guard !hitsBlock else { return }
                onTapEmpty(snapped)
            }
        }
    }
}

/// One segment of a `FreeTimeInterval` rendered in a specific day column.
struct RenderedBlock: Identifiable {
    let id = UUID()
    let intervalID: UUID
    /// 0..<1440
    let startMinuteOfDay: Int
    /// 0..<=1440; exclusive end.
    let endMinuteOfDay: Int
}
