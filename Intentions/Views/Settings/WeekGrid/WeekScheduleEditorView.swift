import SwiftUI

struct WeekScheduleEditorView: View {
    @State private var editing: WeeklySchedule
    @State private var selectedIntervalID: UUID?
    @State private var draftForEdit: DraftInterval?
    @State private var draftForCopy: DraftInterval?

    let onSave: (WeeklySchedule) -> Void

    @MainActor
    init(schedule: WeeklySchedule,
         onSave: @escaping (WeeklySchedule) -> Void) {
        // Deep copy via codable round-trip so the caller's schedule isn't mutated until Save.
        let data = (try? JSONEncoder().encode(schedule)) ?? Data()
        let copy = (try? JSONDecoder().decode(WeeklySchedule.self, from: data)) ?? WeeklySchedule()
        _editing = State(wrappedValue: copy)
        self.onSave = onSave
    }

    /// Intervals to render: the editing schedule plus a live preview of the in-progress draft
    /// (if any). For new drafts the preview is appended; for existing drafts the persisted
    /// interval is replaced with the live draft so edits show immediately.
    private var displayedIntervals: [FreeTimeInterval] {
        guard let draft = draftForEdit else { return editing.intervals }
        let live = draft.toInterval()
        if let idx = editing.intervals.firstIndex(where: { $0.id == draft.id }) {
            var copy = editing.intervals
            copy[idx] = live
            return copy
        } else {
            return editing.intervals + [live]
        }
    }

    private var editSheetBinding: Binding<Bool> {
        Binding(
            get: { draftForEdit != nil },
            set: { newValue in if !newValue { draftForEdit = nil } }
        )
    }

    private var draftBinding: Binding<DraftInterval> {
        Binding(
            get: { draftForEdit ?? DraftInterval(from: FreeTimeInterval(id: UUID(), startMinuteOfWeek: 0, durationMinutes: 60)) },
            set: { draftForEdit = $0 }
        )
    }

    var body: some View {
        WeekGridView(
            intervals: displayedIntervals,
            selectedIntervalID: draftForEdit?.id ?? selectedIntervalID,
            onTapEmpty: handleTapEmpty,
            onTapBlock: handleTapBlock,
            onEditBlock: handleEditBlock,
            onDeleteBlock: handleDeleteBlock
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 12)
        .padding(.top, 20)
        .padding(.bottom, 28)
        .background(AppConstants.Colors.background)
        .navigationTitle("Free Time Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Save") { onSave(editing) }
                    .fontWeight(.semibold)
            }
        }
        .sheet(isPresented: editSheetBinding) {
            EditFreeTimeSheet(
                editing: draftBinding,
                onConfirm: { updated in
                    commitEditedInterval(updated)
                    draftForEdit = nil
                },
                onDelete: {
                    if let id = draftForEdit?.id {
                        deleteInterval(id: id)
                    }
                    draftForEdit = nil
                },
                onCopyTo: { current in
                    draftForEdit = nil
                    draftForCopy = current
                }
            )
        }
        .sheet(item: $draftForCopy) { draft in
            CopyToSheet(
                source: draft,
                onCopy: { targets in
                    copyIntervalToDays(source: draft, targets: targets)
                    draftForCopy = nil
                },
                onBack: {
                    // Return to the edit sheet with the same draft.
                    draftForCopy = nil
                    draftForEdit = draft
                }
            )
        }
    }

    // MARK: - Gesture handlers

    private func handleTapEmpty(day: Weekday, minuteOfDay: Int) {
        // Open the edit sheet for a NEW 1-hour block, but do NOT append it to `intervals`
        // until the user taps Confirm. Dismissing the sheet without confirming discards the
        // pending block. The tapped minute snaps DOWN to the nearest whole hour so a tap at
        // 6:15 produces a 6:00–7:00 block.
        let snappedToHour = (minuteOfDay / 60) * 60
        let mow = FreeTimeInterval.mondayDayIndex(for: day) * FreeTimeInterval.minutesPerDay + snappedToHour
        let newInterval = FreeTimeInterval(id: UUID(), startMinuteOfWeek: mow, durationMinutes: 60)
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
            // Skip the source day — the block already lives there. CopyToSheet pre-selects
            // it so the user can see the source, but we don't want to create a duplicate.
            guard target != sourceInterval.startDayOfWeek else { continue }

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
