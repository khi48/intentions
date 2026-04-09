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

    @State private var isEnabled: Bool
    @State private var startHour: Int
    @State private var endHour: Int
    @State private var selectedDays: Set<Weekday>

    init(settings: ScheduleSettings, onSave: @escaping (ScheduleSettings) -> Void, onCancel: @escaping () -> Void) {
        self.settings = settings
        self.onSave = onSave
        self.onCancel = onCancel
        self._isEnabled = State(initialValue: settings.isEnabled)
        self._startHour = State(initialValue: settings.activeHours.lowerBound)
        self._endHour = State(initialValue: settings.activeHours.upperBound)
        self._selectedDays = State(initialValue: settings.activeDays)
    }

    var body: some View {
        NavigationView {
            List {
                Section {
                    Toggle("Enable Scheduled Blocking", isOn: $isEnabled)
                        .tint(AppConstants.Colors.accent)
                } header: {
                    Text("Blocking Mode")
                } footer: {
                    Text(isEnabled ? "Apps will only be blocked during specified times and days" : "Apps will be blocked by default 24/7")
                        .foregroundColor(AppConstants.Colors.textSecondary)
                }

                if isEnabled {
                    Section {
                        HStack {
                            Text("Start Time")
                                .foregroundColor(AppConstants.Colors.text)
                            Spacer()
                            Picker("Start Hour", selection: $startHour) {
                                ForEach(0..<24) { hour in
                                    Text(hourFormatter.string(from: dateFromHour(hour)))
                                        .tag(hour)
                                }
                            }
                            .pickerStyle(.menu)
                        }

                        HStack {
                            Text("End Time")
                                .foregroundColor(AppConstants.Colors.text)
                            Spacer()
                            Picker("End Hour", selection: $endHour) {
                                ForEach(1..<24) { hour in
                                    Text(hourFormatter.string(from: dateFromHour(hour)))
                                        .tag(hour)
                                }
                            }
                            .pickerStyle(.menu)
                        }
                    } header: {
                        Text("Blocking Hours")
                    } footer: {
                        Text("Apps will be blocked from \(hourFormatter.string(from: dateFromHour(startHour))) to \(hourFormatter.string(from: dateFromHour(endHour)))")
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

                        VStack(spacing: 8) {
                            HStack {
                                Button("All Days") {
                                    selectedDays = Set(Weekday.allCases)
                                }
                                .buttonStyle(.bordered)
                                .tint(AppConstants.Colors.accent)

                                Button("Weekdays") {
                                    selectedDays = [.monday, .tuesday, .wednesday, .thursday, .friday]
                                }
                                .buttonStyle(.bordered)
                                .tint(AppConstants.Colors.accent)

                                Button("Weekends") {
                                    selectedDays = [.saturday, .sunday]
                                }
                                .buttonStyle(.bordered)
                                .tint(AppConstants.Colors.accent)
                            }

                            Button("Clear All") {
                                selectedDays.removeAll()
                            }
                            .buttonStyle(.bordered)
                            .tint(AppConstants.Colors.destructive)
                        }
                        .padding(.vertical, 8)
                    } header: {
                        Text("Blocking Days")
                    } footer: {
                        Text("Select the days when apps should be blocked by default. At least one day must be selected.")
                            .foregroundColor(AppConstants.Colors.textSecondary)
                    }
                }
            }
            .background(AppConstants.Colors.background)
            .scrollContentBackground(.hidden)
            .navigationTitle("Protected Hours")
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
        if !isEnabled { return true }
        return startHour < endHour && !selectedDays.isEmpty
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
        updatedSettings.isEnabled = isEnabled
        updatedSettings.activeHours = startHour...endHour
        updatedSettings.activeDays = selectedDays
        updatedSettings.timeZone = settings.timeZone
        onSave(updatedSettings)
    }

    private var hourFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }

    private func dateFromHour(_ hour: Int) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: Date()) ?? Date()
    }
}
