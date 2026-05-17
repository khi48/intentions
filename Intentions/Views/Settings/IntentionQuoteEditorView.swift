//
//  IntentionQuoteEditorView.swift
//  Intentions
//

import SwiftUI

/// Navigation page (no longer a sheet) for editing the user's intention quote.
/// Pushed from `SettingsView` via `SettingsDestination.intentionQuote`.
struct IntentionQuoteEditorView: View {
    let initialQuote: String
    let isReadOnly: Bool
    let onSave: (String) -> Void

    @State private var quote: String
    @FocusState private var isFocused: Bool
    @Environment(\.dismiss) private var dismiss

    init(quote: String, isReadOnly: Bool = false, onSave: @escaping (String) -> Void) {
        self.initialQuote = quote
        self.isReadOnly = isReadOnly
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
                }
                .padding(.top, 8)

                if isReadOnly {
                    lockedBanner
                }

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
                        .disabled(isReadOnly)
                        .padding(14)
                        .background(AppConstants.Colors.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(AppConstants.Colors.textSecondary.opacity(0.15), lineWidth: 1)
                        )
                }

                if !isReadOnly {
                    SettingsPrimaryButton("Save", systemImage: "checkmark") {
                        onSave(quote.trimmingCharacters(in: .whitespacesAndNewlines))
                        dismiss()
                    }
                }

                Spacer(minLength: 24)
            }
            .padding()
        }
        .settingsPageBackground()
        .navigationTitle("Your Intention")
        .navigationBarTitleDisplayMode(.large)
        .onAppear { if !isReadOnly { isFocused = true } }
    }

    private var lockedBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "lock.fill")
                .font(.caption)
                .foregroundColor(AppConstants.Colors.accent)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                Text("Intention locked while Blocking is on.")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(AppConstants.Colors.text)
                Text("Turn off Blocking in Settings to edit.")
                    .font(.caption)
                    .foregroundColor(AppConstants.Colors.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 11)
        .padding(.horizontal, 13)
        .background(AppConstants.Colors.surface)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(AppConstants.Colors.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
