import SwiftUI

/// Cards-based replacement for `WeekScheduleEditorView`. Lists each `FreeTimeRoutine`
/// as a tappable card; routines are created, edited, and deleted via `RoutineEditorSheet`.
/// Auto-saves on every mutation — no toolbar Save.
@MainActor
struct RoutinesView: View {
    enum Tab: Hashable { case routines, weekView }

    @State private var routines: [FreeTimeRoutine]
    @State private var selectedTab: Tab = .routines

    /// Sheet presentation: `.some(routine)` to edit; `.some(nil)` to create. `nil` = closed.
    @State private var editorTarget: EditorTarget?

    let schedule: WeeklySchedule
    let isReadOnly: Bool
    let onSave: (WeeklySchedule) -> Void

    init(
        schedule: WeeklySchedule,
        isReadOnly: Bool,
        onSave: @escaping (WeeklySchedule) -> Void
    ) {
        self.schedule = schedule
        self.isReadOnly = isReadOnly
        self.onSave = onSave
        _routines = State(initialValue: schedule.routines)
    }

    var body: some View {
        ZStack {
            AppConstants.Colors.background.ignoresSafeArea()
            content
        }
        .navigationTitle("Free Time")
        .navigationBarTitleDisplayMode(.large)
        .sheet(item: $editorTarget) { target in
            RoutineEditorSheet(
                editing: target.routine,
                defaultSortIndex: nextSortIndex,
                onSave: { saved in
                    upsert(saved)
                    commitSave()
                },
                onDelete: {
                    if let id = target.routine?.id {
                        delete(id: id)
                        commitSave()
                    }
                }
            )
        }
    }

    // MARK: - Body content

    @ViewBuilder
    private var content: some View {
        VStack(spacing: 0) {
            tabPicker
                .padding(.leading, 16)
                .padding(.trailing, 24)
                .padding(.top, 12)

            if isReadOnly {
                StateLockBanner(
                    title: "Schedule locked while blocking is on.",
                    remedy: "Turn off blocking in Settings to edit."
                )
                .padding(.horizontal, 16)
                .padding(.top, 12)
            }

            switch selectedTab {
            case .routines:
                if routines.isEmpty {
                    emptyState
                } else {
                    routinesList
                }

                if !isReadOnly {
                    addRoutineButton
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .padding(.bottom, 16)
                }
            case .weekView:
                RoutinesWeekView(routines: routines)
                    .padding(.top, 16)
            }
        }
    }

    private var tabPicker: some View {
        Picker("View", selection: $selectedTab) {
            Text("Routines").tag(Tab.routines)
            Text("Week view").tag(Tab.weekView)
        }
        .pickerStyle(.segmented)
    }

    private var routinesList: some View {
        // TimelineView at .everyMinute drives row re-evaluation so the active
        // highlight + progress fill cross minute boundaries without manual timers.
        TimelineView(.everyMinute) { context in
            List {
                ForEach(sortedRoutines) { routine in
                    let active = isActive(routine: routine, now: context.date)
                    Button {
                        guard !isReadOnly else { return }
                        editorTarget = EditorTarget(routine: routine)
                    } label: {
                        routineRow(routine, now: context.date, active: active)
                    }
                    .buttonStyle(.plain)
                    .disabled(isReadOnly)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(
                        active
                            ? AppConstants.Colors.surfaceElevated
                            : AppConstants.Colors.surface
                    )
                }
                .onMove(perform: isReadOnly ? nil : moveAction)
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(AppConstants.Colors.background)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Text("No routines yet")
                .font(.body)
                .foregroundColor(AppConstants.Colors.textSecondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var addRoutineButton: some View {
        Button {
            editorTarget = EditorTarget(routine: nil)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus.circle.fill")
                Text("Add routine")
                    .fontWeight(.semibold)
            }
            .font(.headline)
            .foregroundColor(AppConstants.Colors.text)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(AppConstants.Colors.buttonPrimary)
            )
        }
    }

    private func routineRow(_ routine: FreeTimeRoutine, now: Date, active: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            titleLine(for: routine)
            Text(daysSubtitle(for: routine))
                .font(.caption)
                .foregroundColor(AppConstants.Colors.textSecondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) {
            if active {
                progressBar(for: routine, now: now)
            }
        }
    }

    /// `HH:mm–HH:mm` (monospaced) optionally followed by `· Name`. Time range
    /// stays primary; name is rendered in the secondary text colour.
    @ViewBuilder
    private func titleLine(for routine: FreeTimeRoutine) -> some View {
        let timeRange = "\(routine.startTimeOfDayString)–\(routine.endTimeOfDayString)"
        let trimmedName: String? = {
            guard let raw = routine.name else { return nil }
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }()
        HStack(spacing: 8) {
            Text(timeRange)
                .font(.body.weight(.medium).monospacedDigit())
                .foregroundColor(AppConstants.Colors.text)
            if let name = trimmedName {
                Text("·")
                    .font(.body)
                    .foregroundColor(AppConstants.Colors.textSecondary)
                Text(name)
                    .font(.body)
                    .foregroundColor(AppConstants.Colors.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
    }

    /// 2 pt bar pinned to the bottom edge of the row's card. Faint white track,
    /// `Colors.text` (white) fill. Width derived from elapsed fraction of the
    /// routine's window at `now`.
    private func progressBar(for routine: FreeTimeRoutine, now: Date) -> some View {
        let fraction = progressFraction(routine: routine, now: now)
        return GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Color.white.opacity(0.12))
                Rectangle()
                    .fill(AppConstants.Colors.text)
                    .frame(width: proxy.size.width * fraction)
            }
        }
        .frame(height: 2)
        .accessibilityHidden(true)
    }

    /// Elapsed fraction `(minuteOfDay(now) - startMinute) / durationMinutes`,
    /// clamped to `[0, 1]`. Returns 0 if the routine has no duration (defensive
    /// — model invariants forbid this, but the math would divide by zero).
    private func progressFraction(routine: FreeTimeRoutine, now: Date) -> CGFloat {
        guard routine.durationMinutes > 0 else { return 0 }
        let calendar = Calendar.current
        let minuteOfDay = calendar.component(.hour, from: now) * 60
            + calendar.component(.minute, from: now)
        let elapsed = minuteOfDay - routine.startMinute
        let raw = CGFloat(elapsed) / CGFloat(routine.durationMinutes)
        return min(max(raw, 0), 1)
    }

    // MARK: - Derived

    private var sortedRoutines: [FreeTimeRoutine] {
        routines.sorted { lhs, rhs in
            if lhs.sortIndex != rhs.sortIndex { return lhs.sortIndex < rhs.sortIndex }
            return lhs.startMinute < rhs.startMinute
        }
    }

    private var nextSortIndex: Int {
        (routines.map(\.sortIndex).max() ?? -1) + 1
    }

    /// Days sorted Mon..Sun (Monday-first), comma-joined short names.
    private func daysSubtitle(for routine: FreeTimeRoutine) -> String {
        let order: [Weekday] = [.monday, .tuesday, .wednesday, .thursday, .friday, .saturday, .sunday]
        return order
            .filter { routine.days.contains($0) }
            .map(\.shortName)
            .joined(separator: ", ")
    }

    // MARK: - Mutations

    private func upsert(_ routine: FreeTimeRoutine) {
        if let idx = routines.firstIndex(where: { $0.id == routine.id }) {
            routines[idx] = routine
        } else {
            routines.append(routine)
        }
    }

    private func delete(id: UUID) {
        routines.removeAll { $0.id == id }
    }

    private var moveAction: (IndexSet, Int) -> Void {
        { source, destination in
            routines = RoutineOrdering.reorder(
                sortedRoutines: sortedRoutines,
                from: source,
                to: destination
            )
            commitSave()
        }
    }

    private func commitSave() {
        // Deep-copy via codable round-trip so we don't mutate the caller's instance
        // until they accept ownership of the saved schedule.
        let data = (try? JSONEncoder().encode(schedule)) ?? Data()
        let copy = (try? JSONDecoder().decode(WeeklySchedule.self, from: data)) ?? WeeklySchedule()
        copy.routines = routines
        onSave(copy)
    }
}

// MARK: - Sheet presentation identity

/// `nil` routine → creation; non-nil → edit.
/// Wrapped struct so `.sheet(item:)` treats "create new" as a distinct identity per tap.
private struct EditorTarget: Identifiable {
    let id: UUID
    let routine: FreeTimeRoutine?

    init(routine: FreeTimeRoutine?) {
        self.routine = routine
        self.id = routine?.id ?? UUID()
    }
}
