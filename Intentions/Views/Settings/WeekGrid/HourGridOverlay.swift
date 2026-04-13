import SwiftUI

/// Seven horizontal tick lines drawn over the week grid at every 3 hours.
/// Uniform colour and stroke. Ignores pointer events.
struct HourGridOverlay: View {
    var body: some View {
        GeometryReader { geo in
            Canvas { context, size in
                let color = Color.white.opacity(0.3)
                for i in 1...7 {
                    let y = CGFloat(i) / 8.0 * size.height
                    var path = Path()
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: size.width, y: y))
                    context.stroke(path, with: .color(color), lineWidth: 1)
                }
            }
        }
        .allowsHitTesting(false)
    }
}
