import SwiftUI

/// Horizontal tick lines drawn over the week grid: one every two hours.
/// The 6/12/18 lines (the ones aligned with the labelled hours in `HourColumn`) are drawn
/// slightly bolder to act as visual anchors. Ignores pointer events.
struct HourGridOverlay: View {
    var body: some View {
        GeometryReader { geo in
            Canvas { context, size in
                let majorColor = Color.white.opacity(0.4)
                let minorColor = Color.white.opacity(0.14)
                let majorWidth: CGFloat = 1.2
                let minorWidth: CGFloat = 0.5

                for hour in stride(from: 2, to: 24, by: 2) {
                    let y = CGFloat(hour) / 24.0 * size.height
                    let isMajor = (hour == 6 || hour == 12 || hour == 18)
                    var path = Path()
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: size.width, y: y))
                    context.stroke(
                        path,
                        with: .color(isMajor ? majorColor : minorColor),
                        lineWidth: isMajor ? majorWidth : minorWidth
                    )
                }
            }
        }
        .allowsHitTesting(false)
    }
}
