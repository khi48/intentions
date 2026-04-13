import SwiftUI

struct CopyToSheet: View {
    let source: DraftInterval
    @State private var selectedDays: Set<Weekday>
    let onCopy: (_ days: Set<Weekday>) -> Void
    let onBack: () -> Void

    private static let days: [Weekday] = [.monday, .tuesday, .wednesday, .thursday, .friday, .saturday, .sunday]

    init(source: DraftInterval,
         onCopy: @escaping (_ days: Set<Weekday>) -> Void,
         onBack: @escaping () -> Void) {
        self.source = source
        self.onCopy = onCopy
        self.onBack = onBack
        // Pre-select the source day so the button starts enabled and the user can see which
        // day this block already lives on. Copying to the source day is a no-op (filtered in
        // the parent), so leaving it selected has no negative effect.
        self._selectedDays = State(initialValue: [source.startDay])
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Text("Copy To")
                    .font(.title3.weight(.semibold))
                    .foregroundColor(AppConstants.Colors.text)
                HStack {
                    Button(action: onBack) {
                        Image(systemName: "chevron.left")
                            .font(.body.weight(.semibold))
                            .foregroundColor(AppConstants.Colors.text)
                            .padding(.vertical, 6)
                            .padding(.horizontal, 4)
                            .contentShape(Rectangle())
                    }
                    Spacer()
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 22)
            .padding(.bottom, 16)

            HStack(spacing: 6) {
                ForEach(Self.days, id: \.self) { day in
                    Button(action: { toggle(day) }) {
                        Text(day.shortName.prefix(1).uppercased())
                            .font(.system(size: 16, weight: .semibold))
                            .frame(width: 44, height: 44)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(selectedDays.contains(day) ? AppConstants.Colors.text : AppConstants.Colors.surface)
                            )
                            .foregroundColor(selectedDays.contains(day) ? AppConstants.Colors.background : AppConstants.Colors.textSecondary)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(AppConstants.Colors.textSecondary.opacity(0.18), lineWidth: 1)
                            )
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 18)

            Button {
                guard !selectedDays.isEmpty else { return }
                onCopy(selectedDays)
            } label: {
                Text("Copy")
                    .font(.subheadline.weight(.bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(AppConstants.Colors.text)
            .foregroundColor(AppConstants.Colors.background)
            .opacity(selectedDays.isEmpty ? 0.45 : 1.0)
            .padding(.horizontal, 24)
            .padding(.bottom, 18)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(AppConstants.Colors.surface)
        .presentationDetents([.fraction(0.32)])
        .presentationDragIndicator(.visible)
    }

    private func toggle(_ day: Weekday) {
        if selectedDays.contains(day) {
            selectedDays.remove(day)
        } else {
            selectedDays.insert(day)
        }
    }
}
