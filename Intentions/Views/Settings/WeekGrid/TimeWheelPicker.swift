import SwiftUI
import UIKit

/// Wraps a `UIDatePicker` so we can configure `minuteInterval` (SwiftUI's `DatePicker`
/// doesn't expose it). Displayed as a compact button that opens the system wheel picker
/// with 5-minute snapping.
struct TimeWheelPicker: UIViewRepresentable {
    @Binding var date: Date
    var minuteInterval: Int = 5

    func makeUIView(context: Context) -> UIDatePicker {
        let picker = UIDatePicker()
        picker.datePickerMode = .time
        picker.preferredDatePickerStyle = .compact
        picker.minuteInterval = minuteInterval
        // Force dark appearance + an explicit tint so the compact button's time text
        // is always legible regardless of the surrounding view's inherited tintColor.
        picker.overrideUserInterfaceStyle = .dark
        picker.tintColor = .white
        picker.addTarget(context.coordinator,
                         action: #selector(Coordinator.valueChanged(_:)),
                         for: .valueChanged)
        picker.setContentHuggingPriority(.required, for: .horizontal)
        picker.setContentCompressionResistancePriority(.required, for: .horizontal)
        return picker
    }

    func updateUIView(_ picker: UIDatePicker, context: Context) {
        if picker.minuteInterval != minuteInterval {
            picker.minuteInterval = minuteInterval
        }
        if picker.date != date {
            picker.date = date
        }
    }

    /// SwiftUI doesn't query `intrinsicContentSize` on every wrapped UIView automatically,
    /// so a `.compact` `UIDatePicker` can lay out at 0×0 inside a `.fixedSize()` HStack
    /// — making the time button literally have no room to render. Returning the picker's
    /// real intrinsic size here gives SwiftUI the width it needs.
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UIDatePicker, context: Context) -> CGSize? {
        let target = uiView.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
        return CGSize(width: ceil(target.width), height: ceil(target.height))
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject {
        var parent: TimeWheelPicker
        init(_ parent: TimeWheelPicker) { self.parent = parent }

        @objc func valueChanged(_ sender: UIDatePicker) {
            parent.date = sender.date
        }
    }
}
