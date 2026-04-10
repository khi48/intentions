//
//  DisableBlockingConfirmationView.swift
//  Intentions
//
//  Created by Claude on 18/09/2025.
//

import SwiftUI
import Combine

/// Confirmation modal that adds friction when disabling Intentions blocking
/// Requires user to provide intention statement and wait through 10-second delay
struct DisableBlockingConfirmationView: View {
    let onConfirm: () -> Void
    let onCancel: () -> Void

    @State private var intentionText: String = ""
    @State private var countdownSecondsRemaining: Double = 10.0
    @State private var isCountdownActive: Bool = false
    @State private var countdownCancellable: AnyCancellable?
    @FocusState private var isTextFieldFocused: Bool

    private let minimumCharacters = 15

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 0) {
                        // Headline
                        Text("Disable app blocking?")
                            .font(.title2)
                            .fontWeight(.semibold)
                            .foregroundColor(AppConstants.Colors.text)
                            .multilineTextAlignment(.center)
                            .padding(.top, 24)
                            .padding(.bottom, 6)

                        Text("Take a moment to reflect on why you need full access.")
                            .font(.subheadline)
                            .foregroundColor(AppConstants.Colors.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.bottom, 28)

                        // Reason input
                        VStack(alignment: .leading, spacing: 8) {
                            Text("REASON")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(AppConstants.Colors.textSecondary)

                            TextField("Why do you need to disable blocking?", text: $intentionText)
                                .font(.body)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.sentences)
                                .focused($isTextFieldFocused)
                                .submitLabel(.done)
                                .onSubmit { isTextFieldFocused = false }
                                .onChange(of: intentionText) { _, newValue in
                                    if newValue.count >= minimumCharacters && !isCountdownActive {
                                        startCountdown()
                                    }
                                }
                                .padding(.vertical, 14)
                                .overlay(alignment: .bottom) {
                                    Rectangle()
                                        .fill(AppConstants.Colors.textSecondary.opacity(0.15))
                                        .frame(height: 0.5)
                                }

                            HStack {
                                Text("\(intentionText.count)/\(minimumCharacters) min")
                                    .font(.caption)
                                    .foregroundColor(intentionText.count >= minimumCharacters ? AppConstants.Colors.text : AppConstants.Colors.textSecondary)
                                Spacer()
                                if intentionText.count >= minimumCharacters {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.caption)
                                        .foregroundColor(AppConstants.Colors.text)
                                }
                            }
                        }
                        .padding(.bottom, 28)

                        // Countdown
                        if isCountdownActive {
                            VStack(spacing: 16) {
                                ZStack {
                                    Circle()
                                        .stroke(AppConstants.Colors.textSecondary.opacity(0.2), lineWidth: 4)
                                        .frame(width: 100, height: 100)

                                    Circle()
                                        .trim(from: 0, to: circleProgress)
                                        .stroke(AppConstants.Colors.text, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                                        .frame(width: 100, height: 100)
                                        .rotationEffect(.degrees(-90))

                                    Text("\(Int(ceil(max(0, countdownSecondsRemaining))))s")
                                        .font(.title2)
                                        .fontWeight(.bold)
                                        .foregroundColor(AppConstants.Colors.text)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.bottom, 20)
                        }
                    }
                    .padding(.horizontal)
                }
                .scrollDismissesKeyboard(.interactively)

                // Bottom button
                Button(action: { onConfirm() }) {
                    Text("Confirm Disable")
                        .font(.headline)
                        .foregroundColor(isConfirmEnabled ? AppConstants.Colors.background : AppConstants.Colors.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            isConfirmEnabled
                                ? AppConstants.Colors.text
                                : AppConstants.Colors.textSecondary.opacity(0.2)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(!isConfirmEnabled)
                .padding(.horizontal)
                .padding(.bottom, 20)
            }
            .navigationTitle("Confirm")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        countdownCancellable?.cancel()
                        countdownCancellable = nil
                        onCancel()
                    }
                }
            }
        }
        .onTapGesture {
            isTextFieldFocused = false
        }
        .onDisappear {
            countdownCancellable?.cancel()
            countdownCancellable = nil
        }
    }

    // MARK: - Computed Properties

    private var isConfirmEnabled: Bool {
        intentionText.count >= minimumCharacters && countdownSecondsRemaining <= 0
    }

    private var circleProgress: CGFloat {
        guard isCountdownActive else { return 0 }
        let progress = (10.0 - countdownSecondsRemaining) / 10.0
        return CGFloat(max(0, min(1, progress)))
    }

    private var isIntentionValid: Bool {
        let trimmed = intentionText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= minimumCharacters else { return false }

        // Basic validation to prevent lazy responses
        let lowercased = trimmed.lowercased()
        let invalidResponses = ["asdf", "test", "because", "idk", "whatever", "abc", "123"]

        for invalid in invalidResponses {
            if lowercased.contains(invalid) && trimmed.count < 25 {
                return false
            }
        }

        return true
    }

    // MARK: - Private Methods

    private func startCountdown() {
        guard isIntentionValid else { return }

        isCountdownActive = true
        countdownSecondsRemaining = 10.0

        // Use Timer.publish for ultra-smooth countdown at 60fps
        countdownCancellable = Timer.publish(every: 1.0/60.0, on: .main, in: .common)
            .autoconnect()
            .sink { _ in
                countdownSecondsRemaining = max(0, countdownSecondsRemaining - (1.0/60.0))

                // Stop when countdown reaches zero
                if countdownSecondsRemaining <= 0 {
                    countdownCancellable?.cancel()
                    countdownCancellable = nil
                }
            }
    }
}

// MARK: - Preview

#Preview {
    DisableBlockingConfirmationView(
        onConfirm: { print("Confirmed") },
        onCancel: { print("Cancelled") }
    )
}