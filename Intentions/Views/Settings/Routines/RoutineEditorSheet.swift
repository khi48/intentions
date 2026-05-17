import SwiftUI

/// Minimal create/edit sheet for a single `FreeTimeRoutine`. Slice #31 — no guards,
/// no copy-to, no name field UX beyond raw availability (model already supports it).
/// Slices #32–#35 will layer richer validation and visual polish.
@MainActor
struct RoutineEditorSheet: View {
    /// `nil` = creating a new routine. Non-nil = editing existing.
    let editing: FreeTimeRoutine?
    /// Sort index to assign on create. Ignored when editing.
    let defaultSortIndex: Int
    let onSave: (FreeTimeRoutine) -> Void
    /// Called only when editing existing — UI hides the delete button on create.
    let onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var startDate: Date
    @State private var endDate: Date
    @State private var selectedDays: Set<Weekday>

    /// Stable UUID for the routine being edited. Persisted across rebuilds via @State init.
    @State private var routineID: UUID

    init(
        editing: FreeTimeRoutine?,
        defaultSortIndex: Int,
        onSave: @escaping (FreeTimeRoutine) -> Void,
        onDelete: @escaping () -> Void
    ) {
        self.editing = editing
        self.defaultSortIndex = defaultSortIndex
        self.onSave = onSave
        self.onDelete = onDelete

        let baseStartMinute: Int
        let baseEndMinute: Int
        let baseDays: Set<Weekday>
        let baseID: UUID
        let baseName: String

        if let routine = editing {
            baseStartMinute = routine.startMinute
            baseEndMinute = routine.endMinute
            baseDays = routine.days
            baseID = routine.id
            baseName = routine.name ?? ""
        } else {
            // New routine snaps start to current time; default duration 60min, clamped to end-of-day.
            let nowMinute = Self.minuteOfDay(from: Date())
            let clampedStart = min(max(nowMinute, 0), FreeTimeRoutine.minutesPerDay - 2)
            baseStartMinute = clampedStart
            baseEndMinute = min(clampedStart + 60, FreeTimeRoutine.minutesPerDay - 1)
            baseDays = [.monday, .tuesday, .wednesday, .thursday, .friday]
            baseID = UUID()
            baseName = ""
        }

        _name = State(initialValue: baseName)
        _startDate = State(initialValue: Self.date(forMinuteOfDay: baseStartMinute))
        _endDate = State(initialValue: Self.date(forMinuteOfDay: baseEndMinute))
        _selectedDays = State(initialValue: baseDays)
        _routineID = State(initialValue: baseID)
    }

    private static let dayOrder: [Weekday] = [
        .monday, .tuesday, .wednesday, .thursday, .friday, .saturday, .sunday
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                AppConstants.Colors.background.ignoresSafeArea()
                form
            }
            .navigationTitle(isCreating ? "New Routine" : "Edit Routine")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") { saveTapped() }
                        .fontWeight(.semibold)
                        .disabled(!isValid)
                }
            }
        }
    }

    private var form: some View {
        Form {
            Section("Name") {
                TextField("", text: $name, prompt: Text(currentPlaceholder))
                    .foregroundColor(AppConstants.Colors.text)
                    .autocorrectionDisabled()
            }
            .listRowBackground(AppConstants.Colors.surface)

            Section("Time") {
                DatePicker(
                    "Starts",
                    selection: $startDate,
                    displayedComponents: .hourAndMinute
                )
                .environment(\.locale, Locale(identifier: "en_GB_POSIX")) // 24-hour
                .foregroundColor(AppConstants.Colors.text)
                .onChange(of: startDate) { _, newStart in
                    // Keep end strictly after start. Bump end by the prior gap
                    // (or 1 min minimum) so the user's chosen duration sticks.
                    if endDate <= newStart {
                        endDate = newStart.addingTimeInterval(60)
                    }
                }

                DatePicker(
                    "Ends",
                    selection: $endDate,
                    in: endPickerRange,
                    displayedComponents: .hourAndMinute
                )
                .environment(\.locale, Locale(identifier: "en_GB_POSIX"))
                .foregroundColor(AppConstants.Colors.text)
            }
            .listRowBackground(AppConstants.Colors.surface)

            Section("Days") {
                dayChips
                    .listRowBackground(AppConstants.Colors.surface)
            }

            if !isCreating {
                Section {
                    Button(role: .destructive) {
                        onDelete()
                        dismiss()
                    } label: {
                        Text("Delete routine")
                            .frame(maxWidth: .infinity)
                    }
                }
                .listRowBackground(AppConstants.Colors.surface)
            }
        }
        .scrollContentBackground(.hidden)
    }

    private var dayChips: some View {
        HStack(spacing: 6) {
            ForEach(Self.dayOrder, id: \.self) { day in
                dayChip(day)
            }
        }
        .padding(.vertical, 4)
    }

    private func dayChip(_ day: Weekday) -> some View {
        let isSelected = selectedDays.contains(day)
        return Button {
            toggle(day)
        } label: {
            Text(day.shortName)
                .font(.caption.weight(.semibold))
                .foregroundColor(isSelected ? AppConstants.Colors.background : AppConstants.Colors.text)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isSelected ? AppConstants.Colors.accent : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(AppConstants.Colors.border, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Derived

    private var isCreating: Bool { editing == nil }

    private var startMinute: Int { Self.minuteOfDay(from: startDate) }
    private var endMinute: Int { Self.minuteOfDay(from: endDate) }

    private var isValid: Bool {
        endMinute > startMinute && !selectedDays.isEmpty
    }

    /// Live `HH:mm–HH:mm` shown as the name field's placeholder.
    private var currentPlaceholder: String {
        "\(FreeTimeRoutine.timeOfDayString(forMinute: startMinute))–\(FreeTimeRoutine.timeOfDayString(forMinute: endMinute))"
    }

    /// End picker may only pick a time strictly after the current start.
    /// Upper bound is end-of-day (23:59 on the same anchor day) so the picker
    /// can't roll into tomorrow — model is single-day.
    private var endPickerRange: ClosedRange<Date> {
        let lower = startDate.addingTimeInterval(60)
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: startDate)
        let endOfDay = calendar.date(byAdding: .minute, value: FreeTimeRoutine.minutesPerDay - 1, to: startOfDay) ?? lower
        return lower...max(lower, endOfDay)
    }

    // MARK: - Actions

    private func toggle(_ day: Weekday) {
        if selectedDays.contains(day) {
            selectedDays.remove(day)
        } else {
            selectedDays.insert(day)
        }
    }

    private func saveTapped() {
        guard isValid else { return }
        let duration = endMinute - startMinute
        let sortIndex = editing?.sortIndex ?? defaultSortIndex
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let routine = FreeTimeRoutine(
            id: routineID,
            name: trimmed.isEmpty ? nil : trimmed,
            startMinute: startMinute,
            durationMinutes: duration,
            days: selectedDays,
            sortIndex: sortIndex
        )
        onSave(routine)
        dismiss()
    }

    // MARK: - Date <-> minute-of-day

    /// Build a Date with today's start-of-day plus `minute` minutes.
    /// Caller only cares about the hour/minute components.
    private static func date(forMinuteOfDay minute: Int) -> Date {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        return calendar.date(byAdding: .minute, value: minute, to: startOfDay) ?? startOfDay
    }

    private static func minuteOfDay(from date: Date) -> Int {
        let calendar = Calendar.current
        let comps = calendar.dateComponents([.hour, .minute], from: date)
        return (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
    }
}
