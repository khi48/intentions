//
//  ScheduleSettingsView.swift
//  Intentions
//

import SwiftUI

/// Sheet for editing protected hours schedule settings
struct ScheduleSettingsView: View {
    let settings: ScheduleSettings
    let onSave: (ScheduleSettings) -> Void
    let onCancel: () -> Void

    @State private var startTime: Date
    @State private var endTime: Date
    @State private var selectedDays: Set<Weekday>

    init(settings: ScheduleSettings, onSave: @escaping (ScheduleSettings) -> Void, onCancel: @escaping () -> Void) {
        self.settings = settings
        self.onSave = onSave
        self.onCancel = onCancel
        self._startTime = State(initialValue: Self.dateFromComponents(hour: settings.startHour, minute: settings.startMinute))
        self._endTime = State(initialValue: Self.dateFromComponents(hour: settings.endHour, minute: settings.endMinute))
        self._selectedDays = State(initialValue: settings.activeDays)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    DatePicker(
                        "Start",
                        selection: $startTime,
                        displayedComponents: .hourAndMinute
                    )
                    .foregroundColor(AppConstants.Colors.text)

                    DatePicker(
                        "Finish",
                        selection: $endTime,
                        displayedComponents: .hourAndMinute
                    )
                    .foregroundColor(AppConstants.Colors.text)
                } header: {
                    Text("Free Time Window")
                } footer: {
                    Text(scheduleFooterText)
                        .foregroundColor(AppConstants.Colors.textSecondary)
                }

                Section {
                    ForEach(Weekday.allCases, id: \.self) { day in
                        HStack {
                            Text(day.displayName)
                                .foregroundColor(AppConstants.Colors.text)
                            Spacer()
                            if selectedDays.contains(day) {
                                Image(systemName: "checkmark")
                                    .foregroundColor(AppConstants.Colors.accent)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            toggleDay(day)
                        }
                    }

                    if selectedDays.count < Weekday.allCases.count {
                        Button("Select All") {
                            selectedDays = Set(Weekday.allCases)
                        }
                        .frame(maxWidth: .infinity)
                    }
                } header: {
                    Text("Free Time Days")
                } footer: {
                    Text("Select the days when free time applies. Days not selected will be fully blocked.")
                        .foregroundColor(AppConstants.Colors.textSecondary)
                }
            }
            .background(AppConstants.Colors.background)
            .scrollContentBackground(.hidden)
            .navigationTitle("Free Time")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { onCancel() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") { saveSettings() }
                        .disabled(!isValidConfiguration)
                }
            }
        }
    }

    private var isValidConfiguration: Bool {
        let start = startComponents
        let end = endComponents
        return !(start.hour == end.hour && start.minute == end.minute)
    }

    private var scheduleFooterText: String {
        let start = Self.hourFormatter.string(from: startTime)
        let end = Self.hourFormatter.string(from: endTime)
        return "Apps will be unblocked from \(start) to \(end)"
    }

    private func toggleDay(_ day: Weekday) {
        if selectedDays.contains(day) {
            selectedDays.remove(day)
        } else {
            selectedDays.insert(day)
        }
    }

    private var startComponents: (hour: Int, minute: Int) {
        let comps = Calendar.current.dateComponents([.hour, .minute], from: startTime)
        return (comps.hour ?? 0, comps.minute ?? 0)
    }

    private var endComponents: (hour: Int, minute: Int) {
        let comps = Calendar.current.dateComponents([.hour, .minute], from: endTime)
        return (comps.hour ?? 0, comps.minute ?? 0)
    }

    private func saveSettings() {
        let start = startComponents
        let end = endComponents
        let updatedSettings = ScheduleSettings()
        updatedSettings.isEnabled = true
        updatedSettings.startHour = start.hour
        updatedSettings.startMinute = start.minute
        updatedSettings.endHour = end.hour
        updatedSettings.endMinute = end.minute
        updatedSettings.activeDays = selectedDays
        updatedSettings.timeZone = settings.timeZone
        updatedSettings.intentionQuote = settings.intentionQuote
        updatedSettings.lastDisabledAt = settings.lastDisabledAt
        onSave(updatedSettings)
    }

    private static let hourFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }()

    private static func dateFromComponents(hour: Int, minute: Int) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: Date()) ?? Date()
    }
}
