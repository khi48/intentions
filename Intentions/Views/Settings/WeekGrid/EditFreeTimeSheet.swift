import SwiftUI

/// Edit-free-time modal sheet. Lets the user pick start/end day and time with a 10-minute snap.
/// Visual format mirrors the v7 mockup: title, two inline picker rows, action row, primary Confirm button.
struct EditFreeTimeSheet: View {
    @Binding var editing: DraftInterval
    let onConfirm: (DraftInterval) -> Void
    let onDelete: () -> Void
    let onCopyTo: (DraftInterval) -> Void

    @Environment(\.dismiss) private var dismiss

    private static let days: [Weekday] = [.monday, .tuesday, .wednesday, .thursday, .friday, .saturday, .sunday]

    var body: some View {
        VStack(spacing: 0) {
            Text("Edit Free Time")
                .font(.title3.weight(.semibold))
                .foregroundColor(AppConstants.Colors.text)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, 16)
                .padding(.top, 24)
                .padding(.bottom, 18)

            VStack(spacing: 0) {
                pickerRow(label: "Starts",
                          day: $editing.startDay,
                          hour: $editing.startHour,
                          minute: $editing.startMinute)
                Divider()
                    .background(AppConstants.Colors.textSecondary.opacity(0.3))
                    .padding(.horizontal, 16)
                pickerRow(label: "Ends",
                          day: $editing.endDay,
                          hour: $editing.endHour,
                          minute: $editing.endMinute)
            }

            HStack(spacing: 10) {
                Button {
                    onCopyTo(editing)
                } label: {
                    Text("Copy to…")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .tint(AppConstants.Colors.text)

                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Text("Delete")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 12)

            Button {
                if isValid { onConfirm(editing) }
            } label: {
                Text("Confirm")
                    .font(.subheadline.weight(.bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(AppConstants.Colors.text)
            .foregroundColor(AppConstants.Colors.background)
            .disabled(!isValid)
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(AppConstants.Colors.surface)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    private func pickerRow(label: String, day: Binding<Weekday>, hour: Binding<Int>, minute: Binding<Int>) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.body)
                .foregroundColor(AppConstants.Colors.text)
            Spacer(minLength: 4)
            Picker("", selection: day) {
                ForEach(Self.days, id: \.self) { d in
                    Text(d.displayName).tag(d)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .tint(AppConstants.Colors.text)
            .fixedSize()
            TimeWheelPicker(date: bindingForTime(hour: hour, minute: minute))
                .fixedSize()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private func bindingForTime(hour: Binding<Int>, minute: Binding<Int>) -> Binding<Date> {
        Binding<Date>(
            get: {
                Calendar.current.date(bySettingHour: hour.wrappedValue, minute: minute.wrappedValue, second: 0, of: Date()) ?? Date()
            },
            set: { newDate in
                let comps = Calendar.current.dateComponents([.hour, .minute], from: newDate)
                hour.wrappedValue = comps.hour ?? 0
                minute.wrappedValue = comps.minute ?? 0
            }
        )
    }

    private var isValid: Bool {
        editing.durationMinutes >= 10 && editing.durationMinutes <= FreeTimeInterval.minutesPerWeek - 10
    }
}

/// Mutable draft used inside the edit sheet. Converts to/from `FreeTimeInterval`.
struct DraftInterval: Equatable, Identifiable {
    var id: UUID
    var startDay: Weekday
    var startHour: Int
    var startMinute: Int
    var endDay: Weekday
    var endHour: Int
    var endMinute: Int

    init(from interval: FreeTimeInterval) {
        self.id = interval.id
        self.startDay = interval.startDayOfWeek
        self.startHour = interval.startHour
        self.startMinute = interval.startMinute
        self.endDay = interval.endDayOfWeek
        self.endHour = interval.endHour
        self.endMinute = interval.endMinute
    }

    func toInterval() -> FreeTimeInterval {
        let startMoW = FreeTimeInterval.mondayDayIndex(for: startDay) * FreeTimeInterval.minutesPerDay + startHour * 60 + startMinute
        let endMoW = FreeTimeInterval.mondayDayIndex(for: endDay) * FreeTimeInterval.minutesPerDay + endHour * 60 + endMinute
        let duration = ((endMoW - startMoW) + FreeTimeInterval.minutesPerWeek) % FreeTimeInterval.minutesPerWeek
        return FreeTimeInterval(id: id, startMinuteOfWeek: startMoW, durationMinutes: duration)
    }

    var durationMinutes: Int {
        toInterval().durationMinutes
    }
}
