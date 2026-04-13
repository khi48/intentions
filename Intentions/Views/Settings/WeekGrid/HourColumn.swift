import SwiftUI

/// A narrow left-hand column showing 0 / 6 / 12 / 18 / 24 aligned with the horizontal gridlines.
struct HourColumn: View {
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topTrailing) {
                Color.clear
                hourLabel("0",  y: 0)
                hourLabel("6",  y: geo.size.height * 0.25)
                hourLabel("12", y: geo.size.height * 0.50)
                hourLabel("18", y: geo.size.height * 0.75)
                hourLabel("24", y: geo.size.height, alignBottom: true)
            }
        }
        .frame(width: 26)
    }

    @ViewBuilder
    private func hourLabel(_ text: String, y: CGFloat, alignBottom: Bool = false) -> some View {
        Text(text)
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(AppConstants.Colors.textSecondary)
            .monospacedDigit()
            .offset(y: alignBottom ? y - 14 : y - (y == 0 ? 0 : 7))
            .padding(.trailing, 4)
    }
}
