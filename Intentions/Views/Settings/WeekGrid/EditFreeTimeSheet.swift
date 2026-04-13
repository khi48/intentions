import SwiftUI

/// Edit-free-time modal sheet. Lets the user pick start/end day and time with a 10-minute snap.
struct EditFreeTimeSheet: View {
    @State var editing: DraftInterval
    let onConfirm: (DraftInterval) -> Void
    let onDelete: () -> Void
    let onCopyTo: (DraftInterval) -> Void

    private static let days: [Weekday] = [.monday, .tuesday, .wednesday, .thursday, .friday, .saturday, .sunday]

    var body: some View {
        VStack(spacing: 0) {
            handle
            Text("Edit Free Time")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(AppConstants.Colors.text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.bottom, 12)

            pickerRow(label: "Starts", day: $editing.startDay, hour: $editing.startHour, minute: $editing.startMinute)
            Divider().overlay(AppConstants.Colors.textSecondary.opacity(0.3))
            pickerRow(label: "Ends", day: $editing.endDay, hour: $editing.endHour, minute: $editing.endMinute)

            HStack(spacing: 8) {
                Button(action: { onCopyTo(editing) }) {
                    Text("Copy to…")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.bordered)

                Button(action: onDelete) {
                    Text("Delete")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.bordered)
                .tint(AppConstants.Colors.textSecondary)
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)

            Button(action: {
                if isValid { onConfirm(editing) }
            }) {
                Text("Confirm")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(Color(red: 0x0a/255, green: 0x0a/255, blue: 0x0a/255))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(RoundedRectangle(cornerRadius: 12).fill(AppConstants.Colors.text))
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 24)
            .disabled(!isValid)
            .opacity(isValid ? 1 : 0.4)
        }
        .background(Color(red: 0x16/255, green: 0x16/255, blue: 0x16/255))
    }

    private var handle: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(Color.white.opacity(0.3))
            .frame(width: 36, height: 4)
            .padding(.top, 10)
            .padding(.bottom, 14)
    }

    private func pickerRow(label: String, day: Binding<Weekday>, hour: Binding<Int>, minute: Binding<Int>) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 14))
                .foregroundColor(AppConstants.Colors.text)
            Spacer()
            Menu {
                ForEach(Self.days, id: \.self) { d in
                    Button(d.displayName) { day.wrappedValue = d }
                }
            } label: {
                Text(day.wrappedValue.displayName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(AppConstants.Colors.text)
            }
            Text("·").foregroundColor(AppConstants.Colors.textSecondary.opacity(0.45))
            DatePicker("", selection: bindingForTime(hour: hour, minute: minute), displayedComponents: .hourAndMinute)
                .labelsHidden()
                .datePickerStyle(.compact)
                .environment(\.locale, Locale(identifier: "en_GB_POSIX"))
                .frame(maxWidth: 90)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 11)
    }

    private func bindingForTime(hour: Binding<Int>, minute: Binding<Int>) -> Binding<Date> {
        Binding<Date>(
            get: {
                Calendar.current.date(bySettingHour: hour.wrappedValue, minute: minute.wrappedValue, second: 0, of: Date()) ?? Date()
            },
            set: { newDate in
                let comps = Calendar.current.dateComponents([.hour, .minute], from: newDate)
                hour.wrappedValue = comps.hour ?? 0
                // Snap minute to the nearest 10-minute increment.
                let m = comps.minute ?? 0
                minute.wrappedValue = (Int((Double(m) / 10).rounded()) * 10) % 60
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
