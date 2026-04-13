import SwiftUI

/// A single day's column in the week grid. Shows the base "blocked" fill plus any
/// free-time block rectangles belonging to this day.
///
/// Block visuals are positioned via `.padding(.top:)` (which affects layout) rather
/// than `.offset` (which doesn't), so each block's tap and context-menu hit areas
/// align with where it visually appears.
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
                // Background — receives taps that don't hit any block.
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(red: 0x1f/255, green: 0x1f/255, blue: 0x1f/255))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color.white.opacity(0.18), lineWidth: 1)
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture(coordinateSpace: .local) { point in
                        let normalized = max(0, min(1, point.y / geo.size.height))
                        let minute = Int(normalized * CGFloat(FreeTimeInterval.minutesPerDay))
                        onTapEmpty(minute)
                    }

                // Block layer — each block is positioned via top padding.
                // padding(.top:) DOES affect layout, so the gesture / contextMenu hit area
                // lives at the visual position of the block, not at the top of the column.
                ForEach(renderedBlocks) { block in
                    blockView(for: block, columnHeight: geo.size.height)
                }
            }
        }
    }

    @ViewBuilder
    private func blockView(for block: RenderedBlock, columnHeight: CGFloat) -> some View {
        let topY = CGFloat(block.startMinuteOfDay) / CGFloat(FreeTimeInterval.minutesPerDay) * columnHeight
        let blockHeight = max(
            4,
            CGFloat(block.endMinuteOfDay - block.startMinuteOfDay) / CGFloat(FreeTimeInterval.minutesPerDay) * columnHeight
        )
        let isSelected = block.intervalID == selectedIntervalID

        RoundedRectangle(cornerRadius: 3)
            .fill(Color.white.opacity(isSelected ? 0.6 : 0.4))
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .stroke(Color.white.opacity(isSelected ? 1.0 : 0), lineWidth: 2)
            )
            .frame(height: blockHeight)
            .padding(.horizontal, 2)
            .contentShape(Rectangle())
            .onTapGesture { onTapBlock(block.intervalID) }
            .contextMenu {
                Button {
                    onEditBlock(block.intervalID)
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
                Button(role: .destructive) {
                    onDeleteBlock(block.intervalID)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
            .padding(.top, topY)
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
