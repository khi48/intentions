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
        .navigationBarTitleDisplayMode(.inline)
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
                .padding(.horizontal, 16)
                .padding(.top, 12)

            if isReadOnly {
                lockedBanner
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
        List {
            ForEach(sortedRoutines) { routine in
                Button {
                    guard !isReadOnly else { return }
                    editorTarget = EditorTarget(routine: routine)
                } label: {
                    routineRow(routine)
                }
                .buttonStyle(.plain)
                .disabled(isReadOnly)
                .listRowBackground(AppConstants.Colors.surface)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(AppConstants.Colors.background)
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

    private func routineRow(_ routine: FreeTimeRoutine) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title(for: routine))
                .font(.body.weight(.medium))
                .foregroundColor(AppConstants.Colors.text)
            Text(daysSubtitle(for: routine))
                .font(.caption)
                .foregroundColor(AppConstants.Colors.textSecondary)
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private var lockedBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "lock.fill")
                .font(.caption)
                .foregroundColor(AppConstants.Colors.accent)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                Text("Schedule locked while Blocking is on.")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(AppConstants.Colors.text)
                Text("Turn off Blocking in Settings to edit.")
                    .font(.caption)
                    .foregroundColor(AppConstants.Colors.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 11)
        .padding(.horizontal, 13)
        .background(AppConstants.Colors.surface)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(AppConstants.Colors.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
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

    private func title(for routine: FreeTimeRoutine) -> String {
        if let name = routine.name, !name.isEmpty { return name }
        return "\(routine.startTimeOfDayString)–\(routine.endTimeOfDayString)"
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
