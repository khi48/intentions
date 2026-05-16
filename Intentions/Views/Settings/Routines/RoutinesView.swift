import SwiftUI

/// Cards-based replacement for `WeekScheduleEditorView`. Lists each `FreeTimeRoutine`
/// as a tappable card; routines are created, edited, and deleted via `RoutineEditorSheet`.
/// This is the minimal cutover slice (#31) — no active highlight, no drag-reorder, no
/// optional-name polish, no picker guards.
@MainActor
struct RoutinesView: View {
    /// Live in-flight editing copy of routines. Mutations stay local until `Save` taps.
    @State private var routines: [FreeTimeRoutine]

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
        NavigationStack {
            ZStack {
                AppConstants.Colors.background.ignoresSafeArea()
                content
            }
            .navigationTitle("Free Time")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !isReadOnly {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Save") { commitSave() }
                            .fontWeight(.semibold)
                    }
                }
            }
            .sheet(item: $editorTarget) { target in
                RoutineEditorSheet(
                    editing: target.routine,
                    defaultSortIndex: nextSortIndex,
                    onSave: { saved in
                        upsert(saved)
                    },
                    onDelete: {
                        if let id = target.routine?.id { delete(id: id) }
                    }
                )
            }
        }
    }

    // MARK: - Body content

    @ViewBuilder
    private var content: some View {
        VStack(spacing: 0) {
            if isReadOnly {
                lockedBanner
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
            }

            if routines.isEmpty {
                emptyState
            } else {
                routinesList
            }
        }
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

            if !isReadOnly {
                Button {
                    editorTarget = EditorTarget(routine: nil)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(AppConstants.Colors.accent)
                        Text("Add routine")
                            .foregroundColor(AppConstants.Colors.text)
                            .fontWeight(.medium)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
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
            if !isReadOnly {
                Button {
                    editorTarget = EditorTarget(routine: nil)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus.circle.fill")
                        Text("Add routine")
                            .fontWeight(.semibold)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
                .tint(AppConstants.Colors.text)
                .foregroundColor(AppConstants.Colors.background)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
