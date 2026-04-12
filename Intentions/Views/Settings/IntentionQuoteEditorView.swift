//
//  IntentionQuoteEditorView.swift
//  Intentions
//

import SwiftUI

/// Sheet for editing the user's intention quote
struct IntentionQuoteEditorView: View {
    let onSave: (String) -> Void
    let onCancel: () -> Void

    @State private var quote: String
    @FocusState private var isFocused: Bool

    init(quote: String, onSave: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
        self._quote = State(initialValue: quote)
        self.onSave = onSave
        self.onCancel = onCancel
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                VStack(spacing: 8) {
                    Image(systemName: "quote.opening")
                        .font(.title)
                        .foregroundColor(AppConstants.Colors.accent)

                    Text("Why did you set up protection?")
                        .font(.headline)
                        .foregroundColor(AppConstants.Colors.text)

                    Text("This is shown when you try to disable blocking, to remind you why you started.")
                        .font(.subheadline)
                        .foregroundColor(AppConstants.Colors.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 12)

                TextField("e.g. To be more present with my family", text: $quote, axis: .vertical)
                    .lineLimit(3...6)
                    .textFieldStyle(.roundedBorder)
                    .focused($isFocused)

                Spacer()
            }
            .padding()
            .background(AppConstants.Colors.background)
            .navigationTitle("Your Intention")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { onCancel() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") { onSave(quote) }
                }
            }
            .onAppear { isFocused = true }
        }
        .presentationDetents([.medium])
    }
}
