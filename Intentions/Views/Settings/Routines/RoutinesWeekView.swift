import SwiftUI

/// Read-only 7-column × 24-hour grid with horizontal scrolling. Columns are
/// sized so exactly 4 fit the viewport (between the 36pt hour gutter and the
/// 8pt trailing margin). Hour gutter pins to the leading edge during
/// horizontal scroll; the day-header row pins to the top during vertical
/// scroll. On appear today is positioned as the second of four visible
/// columns and the now-line is centred vertically.
@MainActor
struct RoutinesWeekView: View {
    let routines: [FreeTimeRoutine]

    private static let hourHeight: CGFloat = 48
    private static let headerHeight: CGFloat = 28
    private static let hourGutterWidth: CGFloat = 36
    private static let trailingMargin: CGFloat = 8
    private static let visibleColumns: CGFloat = 4
    private static let weekOrder: [Weekday] = [
        .monday, .tuesday, .wednesday, .thursday, .friday, .saturday, .sunday
    ]

    @State private var vScrollOffset: CGFloat = 0
    @State private var hScrollPos = ScrollPosition()
    @State private var vScrollPos = ScrollPosition()
    @State private var selectedRoutine: FreeTimeRoutine?

    private var blocks: [RoutineGridBlock] { gridBlocks(for: routines) }
    private var totalHeight: CGFloat { Self.hourHeight * 24 }

    var body: some View {
        GeometryReader { geo in
            let colWidth = max(
                (geo.size.width - Self.hourGutterWidth - Self.trailingMargin) / Self.visibleColumns,
                1
            )

            ScrollView(.vertical, showsIndicators: true) {
                HStack(alignment: .top, spacing: 0) {
                    hourGutter
                    bodyHScroll(colWidth: colWidth)
                    Color.clear.frame(width: Self.trailingMargin)
                }
                .frame(height: totalHeight + Self.headerHeight)
                .padding(.bottom, 16)
            }
            .scrollPosition($vScrollPos)
            .onScrollGeometryChange(for: CGFloat.self, of: { $0.contentOffset.y }) { _, new in
                vScrollOffset = new
            }
            .background(AppConstants.Colors.background)
            .overlay(alignment: .topLeading) {
                // Intersection mask: pinned on both axes; hides hour-gutter
                // labels that scroll up into the day-header zone.
                AppConstants.Colors.background
                    .frame(width: Self.hourGutterWidth, height: Self.headerHeight)
            }
            .sheet(item: $selectedRoutine) { routine in
                RoutineDetailSheet(routine: routine)
            }
            .onAppear {
                applyAnchors(colWidth: colWidth, viewportHeight: geo.size.height)
            }
        }
    }

    // MARK: - Hour gutter (pinned-x; scrolls-y with content)

    private var hourGutter: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
                .frame(width: Self.hourGutterWidth, height: totalHeight + Self.headerHeight)
            ForEach(0..<24, id: \.self) { hour in
                Text(String(format: "%02d", hour))
                    .font(.system(size: 9))
                    .foregroundColor(AppConstants.Colors.textSecondary)
                    .frame(width: Self.hourGutterWidth, alignment: .trailing)
                    .padding(.trailing, 6)
                    .alignmentGuide(.top) { d in d[VerticalAlignment.center] }
                    .offset(y: Self.headerHeight + CGFloat(hour) * Self.hourHeight)
            }
        }
    }

    // MARK: - Body horizontal scroll

    private func bodyHScroll(colWidth: CGFloat) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 0) {
                ForEach(Self.weekOrder, id: \.self) { day in
                    dayColumn(day, colWidth: colWidth)
                }
            }
        }
        .scrollPosition($hScrollPos)
    }

    @ViewBuilder
    private func dayColumn(_ day: Weekday, colWidth: CGFloat) -> some View {
        let isTodayDay = isToday(day)
        VStack(spacing: 0) {
            Text(day.shortName)
                .font(.caption.weight(.semibold))
                .foregroundColor(isTodayDay
                    ? AppConstants.Colors.text
                    : AppConstants.Colors.textSecondary)
                .frame(width: colWidth, height: Self.headerHeight)
                .background(AppConstants.Colors.background)
                .offset(y: vScrollOffset)
                .zIndex(2)

            dayColumnBody(day, colWidth: colWidth, tintToday: isTodayDay)
        }
        .frame(width: colWidth)
    }

    @ViewBuilder
    private func dayColumnBody(_ day: Weekday, colWidth: CGFloat, tintToday: Bool) -> some View {
        ZStack(alignment: .topLeading) {
            // Claim full proposed height — without this the ZStack sizes to
            // its tallest child and outer .frame(height:) recentres every
            // offset-positioned child.
            Color.clear
                .frame(width: colWidth, height: totalHeight)
            if tintToday {
                AppConstants.Colors.accent
                    .opacity(0.07)
                    .frame(width: colWidth, height: totalHeight)
            }
            hourLines(width: colWidth)
            ForEach(blocksFor(day), id: \.routineID) { block in
                blockView(block, width: colWidth)
            }
            if tintToday {
                TimelineView(.everyMinute) { context in
                    nowLine(at: context.date, width: colWidth)
                }
            }
        }
        .frame(width: colWidth, height: totalHeight)
        .overlay(
            Rectangle()
                .stroke(AppConstants.Colors.border.opacity(0.5), lineWidth: 0.5)
        )
    }

    private func hourLines(width: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(0..<25, id: \.self) { hour in
                let isMajor = (hour % 6 == 0)
                Rectangle()
                    .fill(AppConstants.Colors.border
                        .opacity(isMajor ? 0.9 : 0.35))
                    .frame(width: width, height: isMajor ? 0.75 : 0.5)
                    .offset(y: CGFloat(hour) * Self.hourHeight)
            }
        }
    }

    @ViewBuilder
    private func blockView(_ block: RoutineGridBlock, width: CGFloat) -> some View {
        let y = CGFloat(block.startMinute) / 60 * Self.hourHeight
        let h = max(CGFloat(block.durationMinutes) / 60 * Self.hourHeight, 2)
        RoundedRectangle(cornerRadius: 4)
            .fill(AppConstants.Colors.accent.opacity(0.4))
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(AppConstants.Colors.accent, lineWidth: 1)
            )
            .overlay(alignment: .topLeading) {
                blockLabel(block, height: h)
            }
            .frame(width: width - 2, height: h)
            .padding(.horizontal, 1)
            .contentShape(Rectangle())
            .onTapGesture {
                if let routine = routines.first(where: { $0.id == block.routineID }) {
                    selectedRoutine = routine
                }
            }
            .offset(y: y)
    }

    @ViewBuilder
    private func blockLabel(_ block: RoutineGridBlock, height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            if height >= 16 {
                Text(blockTitle(block))
                    .font(.system(size: 10, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundColor(AppConstants.Colors.text)
                    .italic(isUntitled(block))
            }
            if height >= 30 {
                Text(timeRange(block))
                    .font(.system(size: 9))
                    .lineLimit(1)
                    .foregroundColor(AppConstants.Colors.textSecondary)
            }
        }
        .padding(.horizontal, 4)
        .padding(.top, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func isUntitled(_ block: RoutineGridBlock) -> Bool {
        (block.name ?? "").isEmpty
    }

    private func blockTitle(_ block: RoutineGridBlock) -> String {
        if let name = block.name, !name.isEmpty { return name }
        return String(localized: "Untitled", comment: "Placeholder title shown on a routine block that has no user-provided name")
    }

    private func timeRange(_ block: RoutineGridBlock) -> String {
        let endMinute = block.startMinute + block.durationMinutes
        return String(
            format: "%02d:%02d – %02d:%02d",
            block.startMinute / 60,
            block.startMinute % 60,
            (endMinute / 60) % 24,
            endMinute % 60
        )
    }

    @ViewBuilder
    private func nowLine(at date: Date, width: CGFloat) -> some View {
        let cal = Calendar.current
        let comps = cal.dateComponents([.hour, .minute], from: date)
        let minute = (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
        let y = CGFloat(minute) / 60 * Self.hourHeight
        let label = String(format: "%02d:%02d", comps.hour ?? 0, comps.minute ?? 0)

        // Rect as root with overlay label — keeps the line's frame fixed at
        // 1.25pt. A ZStack with both would expand to fit the taller capsule's
        // alignment-guide-pushed bounds and shift the rect down by ~half the
        // capsule height (~5–8pt = ~7–10min visual drift).
        Rectangle()
            .fill(AppConstants.Colors.accent)
            .frame(width: width, height: 1.25)
            .overlay(alignment: .leading) {
                Text(label)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(AppConstants.Colors.text)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(
                        Capsule().fill(AppConstants.Colors.accent)
                    )
                    .offset(x: 2)
            }
            .offset(y: y - 0.625)
    }

    // MARK: - Anchors

    private func applyAnchors(colWidth: CGFloat, viewportHeight: CGFloat) {
        // Horizontal: today as 2nd of 4 visible columns, clamped to bounds.
        let todayIdx = Self.weekOrder.firstIndex(of: Weekday.today) ?? 0
        let maxOffsetX = colWidth * (CGFloat(Self.weekOrder.count) - Self.visibleColumns)
        let targetX = (CGFloat(todayIdx) - 1) * colWidth
        let clampedX = min(max(targetX, 0), max(maxOffsetX, 0))
        hScrollPos.scrollTo(x: clampedX)

        // Vertical: centre the now-line, clamped to bounds.
        let cal = Calendar.current
        let comps = cal.dateComponents([.hour, .minute], from: Date())
        let nowMinute = (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
        let nowY = CGFloat(nowMinute) / 60 * Self.hourHeight + Self.headerHeight
        let maxOffsetY = max(totalHeight + Self.headerHeight - viewportHeight, 0)
        let targetY = min(max(nowY - viewportHeight / 2, 0), maxOffsetY)
        vScrollPos.scrollTo(y: targetY)
    }

    // MARK: - Helpers

    private func isToday(_ day: Weekday) -> Bool { day == Weekday.today }

    private func blocksFor(_ day: Weekday) -> [RoutineGridBlock] {
        blocks.filter { $0.day == day }
    }
}

/// Read-only summary of a tapped routine. No editing affordances — the week
/// view is read-only by contract; edits happen via the routines-list editor.
@MainActor
private struct RoutineDetailSheet: View {
    let routine: FreeTimeRoutine
    @Environment(\.dismiss) private var dismiss

    private static let weekOrder: [Weekday] = [
        .monday, .tuesday, .wednesday, .thursday, .friday, .saturday, .sunday
    ]

    var body: some View {
        NavigationStack {
            List {
                LabeledContent("Name", value: displayName)
                LabeledContent("Time", value: "\(routine.startTimeOfDayString) – \(routine.endTimeOfDayString)")
                LabeledContent("Days", value: daysString)
            }
            .navigationTitle("Routine")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.fraction(0.35), .medium])
    }

    private var displayName: String {
        guard let name = routine.name, !name.isEmpty else {
            return String(localized: "Untitled", comment: "Placeholder name for a routine that has no user-provided name")
        }
        return name
    }

    private var daysString: String {
        Self.weekOrder
            .filter { routine.days.contains($0) }
            .map(\.shortName)
            .joined(separator: ", ")
    }
}

