import SwiftUI

/// Read-only 7-column × 24-hour grid. One block per (routine × day in routine.days).
/// Today's column overlays a now-line + time pill, updating per minute.
@MainActor
struct RoutinesWeekView: View {
    let routines: [FreeTimeRoutine]

    private static let hourHeight: CGFloat = 24
    private static let headerHeight: CGFloat = 28
    private static let weekOrder: [Weekday] = [
        .monday, .tuesday, .wednesday, .thursday, .friday, .saturday, .sunday
    ]

    private var blocks: [RoutineGridBlock] { gridBlocks(for: routines) }
    private var totalHeight: CGFloat { Self.hourHeight * 24 }

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(spacing: 0) {
                columnHeader
                gridBody
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
        }
        .background(AppConstants.Colors.background)
    }

    // MARK: - Header

    private var columnHeader: some View {
        HStack(spacing: 0) {
            // Spacer aligns columns with the hour-rule gutter below.
            Color.clear.frame(width: hourGutterWidth, height: Self.headerHeight)
            ForEach(Self.weekOrder, id: \.self) { day in
                Text(day.shortName)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(isToday(day)
                        ? AppConstants.Colors.text
                        : AppConstants.Colors.textSecondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: Self.headerHeight)
            }
        }
    }

    // MARK: - Grid

    private var gridBody: some View {
        HStack(alignment: .top, spacing: 0) {
            hourGutter
            ForEach(Self.weekOrder, id: \.self) { day in
                dayColumn(day)
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(height: totalHeight)
    }

    private var hourGutterWidth: CGFloat { 36 }

    private var hourGutter: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
                .frame(width: hourGutterWidth, height: totalHeight)
            ForEach(0..<24, id: \.self) { hour in
                Text(String(format: "%02d", hour))
                    .font(.system(size: 9))
                    .foregroundColor(AppConstants.Colors.textSecondary)
                    .frame(width: hourGutterWidth, alignment: .trailing)
                    .padding(.trailing, 6)
                    .alignmentGuide(.top) { d in d[VerticalAlignment.center] }
                    .offset(y: CGFloat(hour) * Self.hourHeight)
            }
        }
    }

    @ViewBuilder
    private func dayColumn(_ day: Weekday) -> some View {
        ZStack(alignment: .topLeading) {
            hourLines
            ForEach(blocksFor(day), id: \.routineID) { block in
                blockView(block)
            }
            if isToday(day) {
                TimelineView(.everyMinute) { context in
                    nowLine(at: context.date)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: totalHeight)
        .overlay(
            Rectangle()
                .stroke(AppConstants.Colors.border.opacity(0.5), lineWidth: 0.5)
        )
    }

    private var hourLines: some View {
        ZStack(alignment: .topLeading) {
            ForEach(0..<25, id: \.self) { hour in
                let isMajor = (hour % 6 == 0)
                Rectangle()
                    .fill(AppConstants.Colors.border
                        .opacity(isMajor ? 0.9 : 0.35))
                    .frame(height: isMajor ? 0.75 : 0.5)
                    .offset(y: CGFloat(hour) * Self.hourHeight)
            }
        }
    }

    @ViewBuilder
    private func blockView(_ block: RoutineGridBlock) -> some View {
        let y = CGFloat(block.startMinute) / 60 * Self.hourHeight
        let h = max(CGFloat(block.durationMinutes) / 60 * Self.hourHeight, 2)
        RoundedRectangle(cornerRadius: 3)
            .fill(AppConstants.Colors.accent.opacity(0.4))
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .stroke(AppConstants.Colors.accent, lineWidth: 1)
            )
            .overlay(alignment: .topLeading) {
                if let name = block.name, !name.isEmpty, h >= 14 {
                    Text(name)
                        .font(.system(size: 9, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .foregroundColor(AppConstants.Colors.text)
                        .padding(.horizontal, 3)
                        .padding(.top, 1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(height: h)
            .padding(.horizontal, 1)
            .offset(y: y)
    }

    @ViewBuilder
    private func nowLine(at date: Date) -> some View {
        let cal = Calendar.current
        let comps = cal.dateComponents([.hour, .minute], from: date)
        let minute = (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
        let y = CGFloat(minute) / 60 * Self.hourHeight
        let label = String(format: "%02d:%02d", comps.hour ?? 0, comps.minute ?? 0)

        ZStack(alignment: .leading) {
            Rectangle()
                .fill(AppConstants.Colors.accent)
                .frame(height: 1.25)
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(AppConstants.Colors.text)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(
                    Capsule().fill(AppConstants.Colors.accent)
                )
                .offset(x: 2, y: -1)
        }
        .offset(y: y - 0.5)
    }

    // MARK: - Helpers

    private func isToday(_ day: Weekday) -> Bool { day == Weekday.today }

    private func blocksFor(_ day: Weekday) -> [RoutineGridBlock] {
        blocks.filter { $0.day == day }
    }
}
