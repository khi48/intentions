//
//  IntentionQuoteEditorView.swift
//  Intentions
//

import SwiftUI

/// Navigation page (no longer a sheet) for editing the user's intention quote.
/// Pushed from `SettingsView` via `SettingsDestination.intentionQuote`.
struct IntentionQuoteEditorView: View {
    let initialQuote: String
    let onSave: (String) -> Void

    @State private var quote: String
    @FocusState private var isFocused: Bool
    @Environment(\.dismiss) private var dismiss

    init(quote: String, onSave: @escaping (String) -> Void) {
        self.initialQuote = quote
        self.onSave = onSave
        self._quote = State(initialValue: quote)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 12) {
                    Image(systemName: "quote.opening")
                        .font(.system(size: 48))
                        .foregroundColor(AppConstants.Colors.accent)

                    Text("Why have you tried to control your screen time?")
                        .font(.headline)
                        .foregroundColor(AppConstants.Colors.text)
                        .multilineTextAlignment(.center)

                    Text("This is shown when you try to disable blocking, to remind you why you started.")
                        .font(.subheadline)
                        .foregroundColor(AppConstants.Colors.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 8)

                // Editor card
                VStack(alignment: .leading, spacing: 8) {
                    TextField("e.g. To be more present with my family",
                              text: $quote,
                              axis: .vertical)
                        .lineLimit(3...8)
                        .font(.body)
                        .foregroundColor(AppConstants.Colors.text)
                        .focused($isFocused)
                        .textInputAutocapitalization(.sentences)
                        .padding(14)
                        .background(AppConstants.Colors.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(AppConstants.Colors.textSecondary.opacity(0.15), lineWidth: 1)
                        )
                }

                SettingsPrimaryButton("Save", systemImage: "checkmark") {
                    onSave(quote.trimmingCharacters(in: .whitespacesAndNewlines))
                    dismiss()
                }

                Spacer(minLength: 24)
            }
            .padding()
        }
        .settingsPageBackground()
        .navigationTitle("Your Intention")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { isFocused = true }
    }
}
