//
//  IntentionsWidgetControl.swift
//  IntentionsWidget
//
//  Created by Kieran Hitchcock on 06/09/2025.
//
//  Note: This is a stub file - Control Widgets are not implemented for this widget

import AppIntents
import SwiftUI
import WidgetKit

// Stub implementation - not used in our widget bundle
struct IntentionsWidgetControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(
            kind: "oh.Intent.IntentWidget.Control",
            provider: Provider()
        ) { value in
            ControlWidgetToggle(
                "Not implemented",
                isOn: value,
                action: StubIntent()
            ) { isRunning in
                Label("Stub", systemImage: "questionmark")
            }
        }
        .displayName("Stub")
        .description("Not implemented")
    }
}

extension IntentionsWidgetControl {
    struct Provider: ControlValueProvider {
        var previewValue: Bool {
            false
        }

        func currentValue() async throws -> Bool {
            return false
        }
    }
}

struct StubIntent: SetValueIntent {
    static let title: LocalizedStringResource = "Stub action"

    @Parameter(title: "Stub parameter")
    var value: Bool

    func perform() async throws -> some IntentResult {
        return .result()
    }
}