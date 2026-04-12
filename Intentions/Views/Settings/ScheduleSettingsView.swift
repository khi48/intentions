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

    @State private var startHour: Int
    @State private var endHour: Int
    @State private var selectedDays: Set<Weekday>

    init(settings: ScheduleSettings, onSave: @escaping (ScheduleSettings) -> Void, onCancel: @escaping () -> Void) {
        self.settings = settings
        self.onSave = onSave
        self.onCancel = onCancel
        self._startHour = State(initialValue: settings.startHour)
        self._endHour = State(initialValue: settings.endHour)
        self._selectedDays = State(initialValue: settings.activeDays)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Text("Free from")
                            .foregroundColor(AppConstants.Colors.text)
                        Spacer()
                        Picker("Start Hour", selection: $startHour) {
                            ForEach(0..<24) { hour in
                                Text(Self.hourFormatter.string(from: dateFromHour(hour)))
                                    .tag(hour)
                            }
                        }
                        .pickerStyle(.menu)
                    }

                    HStack {
                        Text("Free until")
                            .foregroundColor(AppConstants.Colors.text)
                        Spacer()
                        Picker("End Hour", selection: $endHour) {
                            ForEach(0..<24) { hour in
                                Text(Self.hourFormatter.string(from: dateFromHour(hour)))
                                    .tag(hour)
                            }
                        }
                        .pickerStyle(.menu)
                    }
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
        startHour != endHour
    }

    private var scheduleFooterText: String {
        let start = Self.hourFormatter.string(from: dateFromHour(startHour))
        let end = Self.hourFormatter.string(from: dateFromHour(endHour))
        return "Apps will be unblocked from \(start) to \(end)"
    }

    private func toggleDay(_ day: Weekday) {
        if selectedDays.contains(day) {
            selectedDays.remove(day)
        } else {
            selectedDays.insert(day)
        }
    }

    private func saveSettings() {
        let updatedSettings = ScheduleSettings()
        updatedSettings.isEnabled = true
        updatedSettings.startHour = startHour
        updatedSettings.endHour = endHour
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

    private func dateFromHour(_ hour: Int) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: Date()) ?? Date()
    }
}
