import SwiftUI

struct WeekScheduleEditorView: View {
    @State private var editing: WeeklySchedule
    @State private var selectedIntervalID: UUID?
    @State private var draftForEdit: DraftInterval?
    @State private var draftForCopy: DraftInterval?

    let onSave: (WeeklySchedule) -> Void
    let onCancel: () -> Void

    @MainActor
    init(schedule: WeeklySchedule,
         onSave: @escaping (WeeklySchedule) -> Void,
         onCancel: @escaping () -> Void) {
        // Deep copy via codable round-trip so the caller's schedule isn't mutated until Save.
        let data = (try? JSONEncoder().encode(schedule)) ?? Data()
        let copy = (try? JSONDecoder().decode(WeeklySchedule.self, from: data)) ?? WeeklySchedule()
        _editing = State(wrappedValue: copy)
        self.onSave = onSave
        self.onCancel = onCancel
    }

    var body: some View {
        NavigationStack {
            WeekGridView(
                intervals: editing.intervals,
                selectedIntervalID: selectedIntervalID,
                onTapEmpty: handleTapEmpty,
                onTapBlock: handleTapBlock,
                onEditBlock: handleEditBlock,
                onDeleteBlock: handleDeleteBlock
            )
            .padding(.horizontal, 12)
            .padding(.top, 4)
            .padding(.bottom, 24)
            .background(AppConstants.Colors.background)
            .navigationTitle("Free Time")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { onCancel() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") { onSave(editing) }
                        .fontWeight(.semibold)
                }
            }
        }
        .sheet(item: $draftForEdit) { draft in
            EditFreeTimeSheet(
                editing: draft,
                onConfirm: { updated in
                    commitEditedInterval(updated)
                    draftForEdit = nil
                },
                onDelete: {
                    deleteInterval(id: draft.id)
                    draftForEdit = nil
                },
                onCopyTo: { current in
                    draftForEdit = nil
                    draftForCopy = current
                }
            )
            .presentationDetents([.medium])
        }
        .sheet(item: $draftForCopy) { draft in
            CopyToSheet(
                source: draft,
                onCopy: { targets in
                    copyIntervalToDays(source: draft, targets: targets)
                    draftForCopy = nil
                }
            )
            .presentationDetents([.medium])
        }
    }

    // MARK: - Gesture handlers

    private func handleTapEmpty(day: Weekday, minuteOfDay: Int) {
        // Create a new 1-hour block at the tapped day/minute.
        let mow = FreeTimeInterval.mondayDayIndex(for: day) * FreeTimeInterval.minutesPerDay + minuteOfDay
        let newInterval = FreeTimeInterval(id: UUID(), startMinuteOfWeek: mow, durationMinutes: 60)
        editing.intervals.append(newInterval)
        selectedIntervalID = newInterval.id
        draftForEdit = DraftInterval(from: newInterval)
    }

    private func handleTapBlock(_ id: UUID) {
        guard let interval = editing.intervals.first(where: { $0.id == id }) else { return }
        selectedIntervalID = id
        draftForEdit = DraftInterval(from: interval)
    }

    private func handleEditBlock(_ id: UUID) {
        handleTapBlock(id)
    }

    private func handleDeleteBlock(_ id: UUID) {
        editing.intervals.removeAll { $0.id == id }
        if selectedIntervalID == id { selectedIntervalID = nil }
    }

    private func commitEditedInterval(_ draft: DraftInterval) {
        let updated = draft.toInterval()
        if let idx = editing.intervals.firstIndex(where: { $0.id == draft.id }) {
            editing.intervals[idx] = updated
        } else {
            editing.intervals.append(updated)
        }
        selectedIntervalID = updated.id
    }

    private func deleteInterval(id: UUID) {
        editing.intervals.removeAll { $0.id == id }
        if selectedIntervalID == id { selectedIntervalID = nil }
    }

    private func copyIntervalToDays(source: DraftInterval, targets: Set<Weekday>) {
        let sourceInterval = source.toInterval()
        let sourceDayIndex = FreeTimeInterval.mondayDayIndex(for: sourceInterval.startDayOfWeek)
        let timeOfDayStart = sourceInterval.startMinuteOfWeek - sourceDayIndex * FreeTimeInterval.minutesPerDay

        for target in targets {
            let dayIndex = FreeTimeInterval.mondayDayIndex(for: target)
            let newMoW = dayIndex * FreeTimeInterval.minutesPerDay + timeOfDayStart
            editing.intervals.append(FreeTimeInterval(
                id: UUID(),
                startMinuteOfWeek: newMoW,
                durationMinutes: sourceInterval.durationMinutes
            ))
        }
    }
}
