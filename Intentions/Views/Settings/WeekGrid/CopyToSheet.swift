import SwiftUI

struct CopyToSheet: View {
    let source: DraftInterval
    @State private var selectedDays: Set<Weekday> = []
    let onCopy: (_ days: Set<Weekday>) -> Void

    private static let days: [Weekday] = [.monday, .tuesday, .wednesday, .thursday, .friday, .saturday, .sunday]

    var body: some View {
        VStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.white.opacity(0.3))
                .frame(width: 36, height: 4)
                .padding(.top, 10)
                .padding(.bottom, 14)

            Text("Copy To")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(AppConstants.Colors.text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.bottom, 12)

            HStack(spacing: 8) {
                ForEach(Self.days, id: \.self) { day in
                    Button(action: { toggle(day) }) {
                        Text(day.shortName.prefix(1).uppercased())
                            .font(.system(size: 14, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .aspectRatio(1, contentMode: .fit)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(selectedDays.contains(day) ? AppConstants.Colors.text : AppConstants.Colors.surface)
                            )
                            .foregroundColor(selectedDays.contains(day) ? Color(red: 0x0a/255, green: 0x0a/255, blue: 0x0a/255) : AppConstants.Colors.textSecondary)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(AppConstants.Colors.textSecondary.opacity(0.12), lineWidth: 1)
                            )
                    }
                }
            }
            .padding(.horizontal, 20)

            Button(action: { onCopy(selectedDays) }) {
                Text("Copy")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(Color(red: 0x0a/255, green: 0x0a/255, blue: 0x0a/255))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(RoundedRectangle(cornerRadius: 12).fill(AppConstants.Colors.text))
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 24)
            .disabled(selectedDays.isEmpty)
            .opacity(selectedDays.isEmpty ? 0.4 : 1)
        }
        .background(Color(red: 0x16/255, green: 0x16/255, blue: 0x16/255))
    }

    private func toggle(_ day: Weekday) {
        if selectedDays.contains(day) {
            selectedDays.remove(day)
        } else {
            selectedDays.insert(day)
        }
    }
}
