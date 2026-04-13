import SwiftUI

struct BlockRect: View {
    let block: RenderedBlock
    let selected: Bool
    let columnHeight: CGFloat
    let onTap: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    private var topOffset: CGFloat {
        CGFloat(block.startMinuteOfDay) / CGFloat(FreeTimeInterval.minutesPerDay) * columnHeight
    }
    private var height: CGFloat {
        CGFloat(block.endMinuteOfDay - block.startMinuteOfDay) / CGFloat(FreeTimeInterval.minutesPerDay) * columnHeight
    }

    var body: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(Color.white.opacity(selected ? 0.6 : 0.4))
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .stroke(Color.white.opacity(selected ? 1.0 : 0), lineWidth: 2)
            )
            .padding(.horizontal, 2)
            .frame(height: max(height, 4))
            .offset(y: topOffset)
            .contentShape(Rectangle())
            .onTapGesture { onTap() }
            .contextMenu {
                Button {
                    onEdit()
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
    }
}
